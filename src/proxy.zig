const std = @import("std");

const crypto = @import("crypto.zig");
const util = @import("util.zig");

const VecPos = struct {
    index: usize,
    offset: usize,
};

pub fn proxy_response(iovecs: []std.posix.iovec_const, stream: *std.net.Stream, enable_signing: bool) error{Unexpected}!void {
    return @call(.never_inline, proxy_response_, .{ iovecs, stream, enable_signing });
}

pub fn proxy_response_(iovecs: []std.posix.iovec_const, stream: *std.net.Stream, enable_signing: bool) error{Unexpected}!void {
    if (iovecs.len == 0) return;

    Proxy.start_proxy(iovecs, stream, enable_signing) catch |err| {
        std.log.err("Unexpected error proxying response: {s}", .{@errorName(err)});
        return error.Unexpected;
    };
}

//noinline
fn create_content_length_header(allocator: std.mem.Allocator, file_size: u64) ![]u8 {
    const str = try std.fmt.allocPrint(allocator, "Content-Length: {d}\r\n", .{file_size});
    return str;
}

//noinline
fn stream_write(stream: *std.net.Stream, data: []const u8) !void {
    try stream.writeAll(data);
}

//noinline
fn stream_write_p(stream: *std.net.Stream, base: [*]const u8, len: usize) !void {
    const iovec = std.posix.iovec_const{
        .base = base,
        .len = len,
    };
    var iovecs: [1]std.posix.iovec_const = undefined;
    iovecs[0] = iovec;
    try stream_writevAll(stream, iovecs[0..1]);
}
//noinline
fn stream_writevAll(stream: *std.net.Stream, iovecs: []std.posix.iovec_const) !void {
    try stream.writevAll(iovecs);
}

var enc_proxies = std.AutoHashMap(u32, *EncProxy).init(std.heap.page_allocator);

//noinline
pub fn connection_read(connection: *std.net.Server.Connection, buffer: []u8) !usize {
    return connection.stream.read(buffer);
}

//noinline
pub fn connection_write(connection: *std.net.Server.Connection, data: []const u8) void {
    return connection.stream.writeAll(data) catch {
        return;
    };
}

//noinline
pub fn connection_read_p(uuid: u32, connection: *std.net.Server.Connection, buffer: []u8, first_read: bool) std.posix.ReadError!usize {
    var enc_proxy = enc_proxies.get(uuid);
    if (enc_proxy == null) {
        var n_read: usize = 0;
        if (first_read) {
            n_read = try connection_read(connection, buffer[0..36]);
        } else {
            n_read = try connection_read(connection, buffer);
        }
        if (first_read and n_read == 36) {
            if (util.mem_eql(buffer[0..4], "zedh")) {
                enable_enc_proxy(uuid, connection, buffer[4..36]);

                return connection_read_p(uuid, connection, buffer, false);
            }
        }
        return n_read;
    } else {
        const n_read = try connection_read(connection, buffer);
        enc_proxy.?.do_xor(buffer[0..n_read]);
        return n_read;
    }
}

//noinline
pub fn enable_enc_proxy(uuid: u32, connection: *std.net.Server.Connection, pubkey: []const u8) void {
    var pubkey_copy: [32]u8 = undefined;
    for (0..32) |i| {
        pubkey_copy[i] = pubkey[i];
    }

    const keypair = std.crypto.dh.X25519.KeyPair.generate();

    const shared_key: [32]u8 = std.crypto.dh.X25519.scalarmult(keypair.secret_key, pubkey_copy) catch {
        return;
    };

    var nonce: [12]u8 = undefined;
    for (0..12) |i| {
        nonce[i] = 0;
    }

    var enc_proxy = EncProxy.new(std.heap.page_allocator) catch {
        return;
    };

    enc_proxy.* = EncProxy{
        .shared_key = shared_key,
        .nonce = nonce,
        .xor_buffer = undefined,
        .xor_index = 0,
        .counter = 0,
    };
    enc_proxies.put(uuid, enc_proxy) catch {
        return;
    };

    _ = connection_write(connection, "zedh");
    _ = connection_write(connection, keypair.public_key[0..]);

    enc_proxy.refill_xor_buffer();
}

const EncProxy = struct {
    shared_key: [32]u8,
    nonce: [12]u8,
    xor_buffer: [64]u8,
    xor_index: usize,
    counter: u32,

    //noinline
    fn new(allocator: std.mem.Allocator) !*EncProxy {
        const enc_proxy = try allocator.create(EncProxy);
        return enc_proxy;
    }

    //noinline
    fn refill_xor_buffer(self: *EncProxy) void {
        std.crypto.stream.chacha.ChaCha12IETF.stream(self.xor_buffer[0..], self.counter, self.shared_key, self.nonce);
        self.counter += 1;
        self.xor_index = 0;
    }

    //noinline
    fn do_xor(self: *EncProxy, data: []u8) void {
        for (0..data.len) |i| {
            data[i] = data[i] ^ self.xor_buffer[self.xor_index];
            self.xor_index += 1;
            if (self.xor_index == self.xor_buffer.len) {
                self.refill_xor_buffer();
            }
        }
    }
};

const Proxy = struct {
    allocator: std.mem.Allocator,
    stream: *std.net.Stream,
    iovecs: []std.posix.iovec_const,
    end_of_headers: ?VecPos,
    cursor: VecPos,
    file_path: ?[]const u8,
    content_length_header_pos: ?VecPos,
    sig_enabled: bool,

    //noinline
    fn start_proxy(iovecs: []std.posix.iovec_const, stream: *std.net.Stream, enable_signing: bool) !void {
        var heap_buffer: [4096 * 10]u8 = undefined;
        var ha = std.heap.FixedBufferAllocator.init(&heap_buffer);
        const allocator = ha.allocator();
        var proxy = Proxy{
            .allocator = allocator,
            .stream = stream,
            .iovecs = iovecs,
            .end_of_headers = null,
            .cursor = VecPos{ .index = 0, .offset = 0 },
            .file_path = null,
            .content_length_header_pos = null,
            .sig_enabled = enable_signing,
        };
        try proxy.process();
    }

    //noinline
    pub fn find_next_char(self: *Proxy, cursor: *VecPos, char: u8) !?VecPos {
        var i: usize = cursor.index;
        var j: usize = cursor.offset;
        while (i < self.iovecs.len) {
            while (j < self.iovecs[i].len) {
                if (self.iovecs[i].base[j] == char) {
                    return VecPos{ .index = i, .offset = j };
                }
                j += 1;
            }
            i += 1;
            j = 0;
        }
        return null;
    }

    //noinline
    pub fn increment_pos(self: *Proxy, pos: *VecPos) void {
        if (pos.offset >= self.iovecs[pos.index].len - 1 and pos.index < self.iovecs.len - 1) {
            pos.index = pos.index + 1;
            pos.offset = 0;
        } else {
            pos.offset = pos.offset + 1;
        }
    }

    //noinline
    pub fn flush_until(self: *Proxy, pos: VecPos) !void {
        var i: usize = self.cursor.index;
        var offset: usize = self.cursor.offset;
        while (i < pos.index) {
            try stream_write_p(self.stream, self.iovecs[i].base + offset, self.iovecs[i].len - offset);
            offset = 0;
            i += 1;
        }
        if (pos.offset > 0) {
            try stream_write_p(self.stream, self.iovecs[pos.index].base, pos.offset);
        }
        self.cursor = pos;
    }

    //noinline
    pub fn flush_rest(self: *Proxy) !void {
        var i: usize = self.cursor.index;
        const offset: usize = self.cursor.offset;
        if (offset > 0) {
            const iovec = self.iovecs[i];
            const left = iovec.len - offset;
            stream_write_p(self.stream, iovec.base + offset, left) catch {
                return;
            };
            i += 1;
        }
        stream_writevAll(self.stream, self.iovecs[i..]) catch {
            return;
        };
    }

    //noinline
    pub fn char_at(self: *Proxy, pos: *const VecPos) u8 {
        return self.iovecs[pos.index].base[pos.offset];
    }
    //noinline
    pub fn str_at(self: *Proxy, pos: *const VecPos) []const u8 {
        const len = self.iovecs[pos.index].len;
        return self.iovecs[pos.index].base[pos.offset..len];
    }

    //noinline
    pub fn next_header(self: *Proxy, cursor: *VecPos) !?VecPos {
        var pos = try self.find_next_char(cursor, '\n');
        if (pos == null) return null;

        var orig_pos = pos.?;

        self.increment_pos(&pos.?);

        const next_char = self.char_at(&pos.?);

        if (next_char == '\n' or next_char == '\r') {
            self.increment_pos(&orig_pos);
            self.end_of_headers = orig_pos;
            return null;
        }

        return pos;
    }

    //noinline
    fn process_headers(self: *Proxy) !void {
        var cursor = self.cursor;
        while (self.end_of_headers == null) {
            const pos = try self.next_header(&cursor);
            if (pos == null) break;

            if (self.end_of_headers != null) {
                break;
            }

            const header_name = self.str_at(&pos.?);

            cursor = pos.?;

            const val_pos = try self.find_next_char(&cursor, ' ');

            if (val_pos == null) {
                continue;
            }

            cursor = val_pos.?;

            self.increment_pos(&cursor);

            const val_str = self.str_at(&cursor);

            if (util.mem_starts_with(header_name, "x-game-asset")) {
                self.file_path = val_str;
            } else if (util.mem_starts_with(header_name, "content-length")) {
                self.content_length_header_pos = pos;
            }
        }
    }

    //noinline
    fn get_content_type(self: *Proxy, path: []const u8) []const u8 {
        const dot_index = util.index_of_char(path, '.');
        if (dot_index == null) {
            return "Content-Type: application/octet-stream\r\n";
        }

        const extension = path[dot_index.? + 1 ..];

        _ = self;
        if (util.mem_eql(extension, "png")) {
            return "Content-Type: image/png\r\n";
        }
        if (util.mem_eql(extension, "js")) {
            return "Content-Type: application/javascript\r\n";
        }
        if (util.mem_eql(extension, "css")) {
            return "Content-Type: text/css\r\n";
        }
        if (util.mem_eql(extension, "html")) {
            return "Content-Type: text/html\r\n";
        }
        if (util.mem_eql(extension, "json")) {
            return "Content-Type: application/json\r\n";
        }
        if (util.mem_eql(extension, "txt")) {
            return "Content-Type: text/plain\r\n";
        }
        if (util.mem_eql(extension, "xml")) {
            return "Content-Type: application/xml\r\n";
        }
        if (util.mem_eql(extension, "svg")) {
            return "Content-Type: image/svg+xml\r\n";
        }
        return "Content-Type: application/octet-stream\r\n";
    }

    //noinline
    fn add_proxy_headers(self: *Proxy) !void {
        const proxy_headers = "Server: nautro-proxy\r\nConnection: close\r\n";
        try stream_write(self.stream, proxy_headers);
    }

    pub fn sign_body(self: *Proxy) !void {
        const body_iovec = self.iovecs[self.cursor.index + 1];
        const body_len = body_iovec.len;
        const body = body_iovec.base[self.cursor.offset..body_len];

        var signer = try crypto.Signer.from_data(self.allocator, body);
        const resp = try signer.sign();
        try stream_write(self.stream, "X-Sig: ");
        try stream_write(self.stream, resp.data.items);
        try stream_write(self.stream, "\r\n");

        try self.flush_rest();
    }

    //noinline
    pub fn process(self: *Proxy) !void {
        try self.process_headers();

        if (self.file_path != null) {
            try self.flush_until(self.content_length_header_pos.?);
            self.increment_pos(&self.cursor);
        }

        if (self.end_of_headers != null) {
            try self.flush_until(self.end_of_headers.?);
        }

        try self.add_proxy_headers();

        if (self.file_path != null) {
            try self.process_file();
        } else if (self.sig_enabled) {
            self.sign_body() catch |err| {
                std.log.err("Error signing body: {s}", .{@errorName(err)});
                try stream_write(self.stream, "X-Sig: error\r\n");
                try self.flush_rest();
            };
        } else {
            try self.flush_rest();
        }
    }

    //noinline
    fn process_file(self: *Proxy) !void {
        const file_path = self.file_path.?;
        if (std.mem.indexOf(u8, file_path, "..") != null) {
            try stream_write(self.stream, "Content-Length: 16\r\n\r\nFile not found\r\n");
            return;
        }

        const file = file_open(file_path) catch {
            try stream_write(self.stream, "Content-Length: 16\r\n\r\nFile not found\r\n");
            return;
        };

        var file_size = try file_get_end_pos(file);

        const content_type_header = self.get_content_type(file_path);
        try stream_write(self.stream, content_type_header);

        const content_length_header = try create_content_length_header(self.allocator, file_size);

        try stream_write(self.stream, content_length_header);

        try file_seek_to(file, 0);

        try stream_write(self.stream, "\r\n");

        var buffer: [1024]u8 = undefined;
        var bytes_read: usize = 0;
        while (file_size > 0) {
            bytes_read = try file_read(file, buffer[0..]);
            try stream_write(self.stream, buffer[0..bytes_read]);
            file_size -= bytes_read;
        }

        try file_close(file);
    }
};

//noinline
fn file_read(file: std.fs.File, buffer: []u8) !usize {
    return file.read(buffer);
}

//noinline
fn file_seek_to(file: std.fs.File, pos: u64) !void {
    return file.seekTo(pos);
}

//noinline
fn file_get_end_pos(file: std.fs.File) !u64 {
    return file.getEndPos();
}

//noinline
fn file_open(path: []const u8) !std.fs.File {
    return std.fs.cwd().openFile(path, .{});
}

//noinline
fn file_close(file: std.fs.File) !void {
    return file.close();
}
