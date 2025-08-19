const std = @import("std");
const util = @import("util.zig");

const Enc = struct {
    shared_key: [32]u8,
    nonce: [12]u8,
    xor_buffer: [64]u8,
    xor_index: usize,
    counter: u32,

    //noinline
    fn refill_xor_buffer(self: *Enc) void {
        std.crypto.stream.chacha.ChaCha12IETF.stream(self.xor_buffer[0..], self.counter, self.shared_key, self.nonce);
        util.hex_dump(self.xor_buffer[0..]);
        self.counter += 1;
        self.xor_index = 0;
    }

    //noinline
    fn do_xor(self: *Enc, data: []u8) void {
        for (0..data.len) |i| {
            data[i] = data[i] ^ self.xor_buffer[self.xor_index];
            self.xor_index += 1;
            if (self.xor_index == self.xor_buffer.len) {
                self.refill_xor_buffer();
            }
        }
    }
};

pub fn main() !void {
    const host = std.process.getEnvVarOwned(std.heap.page_allocator, "HOST") catch "127.0.0.1";
    defer if (!std.mem.eql(u8, host, "127.0.0.1")) std.heap.page_allocator.free(host);

    const port_str = std.process.getEnvVarOwned(std.heap.page_allocator, "PORT") catch "8080";
    defer if (!std.mem.eql(u8, port_str, "8080")) std.heap.page_allocator.free(port_str);

    const port = std.fmt.parseInt(u16, port_str, 10) catch {
        return error.InvalidPort;
    };

    const address = std.net.Address.parseIp(host, port) catch |err| {
        _ = err;
        return error.InvalidAddress;
    };
    const stream = std.net.tcpConnectToAddress(address) catch |err| {
        _ = err;
        return error.FailedToConnect;
    };
    defer stream.close();

    const keypair = std.crypto.dh.X25519.KeyPair.generate();

    var to_send: util.String = util.String.new(std.heap.page_allocator);
    try to_send.appendSlice("zedh");
    try to_send.appendSlice(&keypair.public_key);
    util.hex_dump(to_send.data.items);

    try stream.writeAll(to_send.data.items);

    var buffer: [1024]u8 = undefined;
    var bytes_read = stream.readAll(buffer[0..4]) catch {
        return error.FailedToRead;
    };
    _ = stream.readAll(buffer[0..32]) catch {
        return error.FailedToRead;
    };
    var bob_pubkey: [32]u8 = undefined;
    for (0..32) |i| {
        bob_pubkey[i] = buffer[i];
    }
    util.hex_dump(bob_pubkey[0..]);

    const shared_key = try std.crypto.dh.X25519.scalarmult(keypair.secret_key, bob_pubkey);

    util.hex_dump(shared_key[0..]);

    _ = try stream.writeAll("");

    var nonce: [12]u8 = undefined;
    for (0..12) |i| {
        nonce[i] = 0;
    }

    var enc = Enc{
        .shared_key = shared_key,
        .nonce = nonce,
        .xor_buffer = undefined,
        .xor_index = 0,
        .counter = 0,
    };

    enc.refill_xor_buffer();

    const http_request = try std.fmt.allocPrint(std.heap.page_allocator, "GET / HTTP/1.1\r\nHost: 127.0.0.1:{d}\r\n\r\n", .{port});
    defer std.heap.page_allocator.free(http_request);
    var input = try util.clone_slice(std.heap.page_allocator, http_request);
    enc.do_xor(input);

    std.log.info("Input:", .{});
    util.hex_dump(input[0..]);

    stream.writeAll(input) catch {
        std.log.info("Failed to write to server", .{});
        return error.FailedToWrite;
    };

    var response_buffer: [4096]u8 = undefined;
    bytes_read = stream.readAll(response_buffer[0..]) catch {
        std.log.info("Failed to read from server", .{});
        return error.FailedToRead;
    };
    std.log.info("Response: {s}", .{response_buffer[0..bytes_read]});

    if (util.mem_starts_with(response_buffer[0..bytes_read], "HTTP/1.1 200 OK\r\n")) {
        return;
    }

    return error.InvalidResponse;
}
