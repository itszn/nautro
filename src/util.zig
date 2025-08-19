const std = @import("std");

//noinline
pub fn waitForEnter() void {
    const stdin = std.io.getStdIn().reader();
    var buffer: [1]u8 = undefined;
    _ = stdin.readUntilDelimiterOrEof(&buffer, '\n') catch return;
}

//noinline
pub fn get_line_from_stdin(allocator: std.mem.Allocator) ![]u8 {
    const stdin = std.io.getStdIn().reader();
    const out = allocator.alloc(u8, 4096) catch return error.OutOfMemory;
    const res = try stdin.readUntilDelimiterOrEof(out, '\n');
    if (res == null) {
        return error.EOF;
    }
    return res.?;
}

//noinline
pub fn puts(s: []const u8) void {
    const stdout = std.io.getStdOut().writer();
    _ = stdout.print("{s}\n", .{s}) catch return;
}

//noinline
pub fn puts_debug(s: []const u8) void {
    _ = std.debug.print("{s}\n", .{s});
}

//noinline
pub fn base64_encode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const encoder = std.base64.standard.Encoder;
    const b64_size = encoder.calcSize(data.len);
    const dest = try allocator.alloc(u8, b64_size);
    _ = encoder.encode(dest, data);
    return dest;
}

//noinline
pub fn base64_decode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const decoder = std.base64.standard.Decoder;
    const b64_size = try decoder.calcSizeForSlice(data);
    const dest = try allocator.alloc(u8, b64_size);
    _ = try decoder.decode(dest, data);
    return dest;
}

pub const CString = struct {
    data: [*:0]u8,
    fn length(self: *CString) usize {
        return std.mem.len(self.data);
    }
};

pub const String = struct {
    data: std.ArrayList(u8),
    //noinline
    pub fn new(allocator: std.mem.Allocator) String {
        return String{ .data = std.ArrayList(u8).init(allocator) };
    }
    //noinline
    pub fn deinit(self: *String) void {
        self.data.deinit();
    }
    //noinline
    pub fn appendSlice(self: *String, items: []const u8) !void {
        try self.data.appendSlice(items);
    }
    //noinline
    pub fn append(self: *String, value: u8) !void {
        try self.data.append(value);
    }

    //noinline
    pub fn from_slice(allocator: std.mem.Allocator, data: []const u8) !String {
        var s = String.new(allocator);
        try s.appendSlice(data);
        return s;
    }
};

//noinline
pub fn read_all_of_file(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();
    const data = try file.readToEndAlloc(allocator, 0x100);
    return data;
}

//noinline
pub fn file_exists(path: []const u8) bool {
    const file = std.fs.cwd().openFile(path, .{}) catch return false;
    defer file.close();
    return true;
}

//noinline
pub fn read_all_of_file_in_dir(allocator: std.mem.Allocator, dir: std.fs.Dir, path: []const u8) ![]u8 {
    const file = try dir.openFile(path, .{ .mode = .read_only });
    defer file.close();
    const data = try file.readToEndAlloc(allocator, 4096);
    return data;
}

//noinline
pub fn write_all_of_file(path: []const u8, data: []u8) !void {
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .write_only });
    defer file.close();
    _ = try file.writeAll(data);
}

//noinline
pub fn lock(l: *std.Thread.RwLock.DefaultRwLock) void {
    l.*.lock();
}

//noinline
pub fn unlock(l: *std.Thread.RwLock.DefaultRwLock) void {
    l.*.unlock();
}

//noinline
pub fn rlock(l: *std.Thread.RwLock.DefaultRwLock) void {
    l.*.lockShared();
}

//noinline
pub fn runlock(l: *std.Thread.RwLock.DefaultRwLock) void {
    l.*.unlockShared();
}

//noinline
pub fn mem_eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

//noinline
pub fn to_u64(s: []const u8) !u64 {
    return try std.fmt.parseInt(u64, s, 10);
}

//noinline
pub fn u64_to_str(allocator: std.mem.Allocator, value: u64) ![]u8 {
    const str = try std.fmt.allocPrint(allocator, "{d}", .{value});
    return str;
}

//noinline
pub fn free_u8_slice(allocator: std.mem.Allocator, ptr: []const u8) void {
    allocator.free(ptr);
}

//noinline
pub fn mem_starts_with(a: []const u8, b: []const u8) bool {
    return std.mem.startsWith(u8, a, b);
}

//noinline
pub fn index_of(a: []const u8, b: []const u8) ?usize {
    return std.mem.indexOf(u8, a, b);
}

//noinline
pub fn index_of_char(a: []const u8, b: u8) ?usize {
    return std.mem.indexOfScalar(u8, a, b);
}

const TAG_U64 = 85;
const TAG_STR = 83;

//noinline
pub fn bin_write_u64(s: *String, value: u64) !void {
    try s.append(TAG_U64);

    var i: u64 = value;
    while (true) {
        var b: u8 = @truncate(i & 0x3f);
        i >>= 6;

        if (i > 0) {
            b |= 0x40;
        }
        try s.append(b);

        if (i == 0) {
            break;
        }
    }
}

const BinReadError = error{
    EOF,
    InvalidTag,
};

//noinline
pub fn bin_read_u64(data: []const u8, offset: *u64) !u64 {
    var i: u64 = offset.*;
    if (data.len < i + 2) {
        return BinReadError.EOF;
    }
    if (data[i] != TAG_U64) {
        return BinReadError.InvalidTag;
    }
    i += 1;

    var v: u64 = 0;
    var shift: u6 = 0;
    while (true) {
        const b: u64 = @intCast(data[i]);
        v |= (b & 0x3f) << shift;
        shift += 6;
        i += 1;
        if (b & 0x40 == 0) {
            break;
        }
    }
    offset.* = i;
    return v;
}

//noinline
pub fn bin_write_str(s: *String, value: []const u8) !void {
    try s.data.append(TAG_STR);

    try bin_write_u64(s, value.len);
    try s.data.appendSlice(value);
}

//noinline
pub fn bin_read_str(data: []u8, offset: *u64) ![]u8 {
    var i = offset.*;
    if (data.len < i + 1) {
        std.log.err("bin_read_str: EOF: {d}", .{i});
        return BinReadError.EOF;
    }
    if (data[i] != TAG_STR) {
        return BinReadError.InvalidTag;
    }

    i += 1;

    const length = try bin_read_u64(data, &i);

    if (data.len < i + length) {
        std.log.err("bin_read_str: EOF: {d} {d}", .{ i, length });
        return BinReadError.EOF;
    }

    const str = data[i .. i + length];
    offset.* = i + length;
    return str;
}

//noinline

//noinline
pub fn clone_slice(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return try allocator.dupe(u8, data);
}

//noinline
pub fn to_u64_or_default(s: []const u8, default: u64) u64 {
    return to_u64(s) catch default;
}

//noinline
pub fn mem_move(dst: []u8, src: []const u8) void {
    for (0..src.len) |i| {
        dst[i] = src[i];
    }
}

//noinline
pub fn mem_copy(dst: []u8, src: []const u8) void {
    for (0..src.len) |i| {
        dst[i] = src[i];
    }
}
