const std = @import("std");

const util = @import("util.zig");

const String = util.String;

var sig_lock = std.Thread.RwLock.DefaultRwLock{};

const SIGNER_DEVICE = "/srv/crypto/sign";
const VERIFIER_DEVICE = "/srv/crypto/verify";
var crypto_device_exists = false;

pub fn init() !void {
    // Check if the file exists
    const signer_exists = util.file_exists(SIGNER_DEVICE);
    const verifier_exists = util.file_exists(VERIFIER_DEVICE);
    if (!signer_exists or !verifier_exists) {
        util.puts("⚠️⚠️⚠️ Crypto devices not found, using mock signatures. The real target is using actual crypto! ⚠️⚠️⚠️");
        crypto_device_exists = false;
        std.fs.makeDirAbsolute("/srv/crypto") catch {};
        const signer_file = std.fs.createFileAbsolute(SIGNER_DEVICE, .{}) catch null;
        if (signer_file) |f| f.close();
        const verifier_file = std.fs.createFileAbsolute(VERIFIER_DEVICE, .{}) catch null;
        if (verifier_file) |f| f.close();
    } else {
        crypto_device_exists = true;
    }
}

const JSON_ERROR = error{JSONError};

const SignerResult = struct {
    result: []u8,

    //noinline
    pub fn result_from_json(allocator: std.mem.Allocator, json: []u8) !String {
        const result = try std.json.parseFromSlice(SignerResult, allocator, json, .{ .ignore_unknown_fields = true });
        defer result.deinit();
        var string = String.new(allocator);
        try string.appendSlice(result.value.result);
        return string;
    }
};

const VerifierResult = struct {
    result: []u8,

    //noinline
    pub fn result_from_json(allocator: std.mem.Allocator, json: []u8) !bool {
        const result = try std.json.parseFromSlice(VerifierResult, allocator, json, .{ .ignore_unknown_fields = true });
        defer result.deinit();
        return std.mem.eql(u8, result.value.result, "true");
    }
};

pub const Signer = struct {
    inner: struct {
        message: []u8,
    },
    allocator: std.mem.Allocator,

    //noinline
    pub fn from_data(allocator: std.mem.Allocator, data: []const u8) !Signer {
        const b64_data = try util.base64_encode(allocator, data);
        const signer = Signer{ .inner = .{ .message = b64_data }, .allocator = allocator };
        return signer;
    }
    //noinline
    pub fn deinit(self: *Signer) void {
        util.free_u8_slice(self.allocator, self.inner.message);
    }
    //noinline
    fn wait_for_response(self: *Signer) ![]u8 {
        if (!crypto_device_exists) {
            return try self.allocator.dupe(u8, "{\"result\": \"mockplaceholdersignature\", \"status\": \"success\"}");
        }
        std.time.sleep(500 * std.time.ns_per_ms);
        for (0..10) |_| {
            const response = try util.read_all_of_file(self.allocator, SIGNER_DEVICE);
            util.puts_debug(response);
            if (util.index_of(response, "success")) |_| {
                return response;
            }
            if (util.index_of(response, "error")) |_| {
                util.puts_debug(response);
                util.free_u8_slice(self.allocator, response);
                return error.Error;
            }
            util.free_u8_slice(self.allocator, response);
            std.time.sleep(1000 * std.time.ns_per_ms);
        }
        return error.Timeout;
    }
    //noinline
    pub fn sign(self: *Signer) !String {
        util.lock(&sig_lock);
        defer util.unlock(&sig_lock);
        return self.sign_impl();
    }
    //noinline
    pub fn sign_impl(self: *Signer) !String {
        var msg = try self.to_json();
        defer msg.deinit();
        util.puts_debug(msg.data.items);
        try util.write_all_of_file(SIGNER_DEVICE, msg.data.items);
        const response = try self.wait_for_response();
        util.puts_debug(response);
        const result = try SignerResult.result_from_json(self.allocator, response);
        util.free_u8_slice(self.allocator, response);
        return result;
    }
    //noinline
    fn to_json(self: *Signer) !String {
        var string = String.new(self.allocator);
        try std.json.stringify(self.inner, .{}, string.data.writer());
        return string;
    }
};

pub const Verifier = struct {
    inner: struct {
        message: []u8,
        signature: []u8,
    },
    allocator: std.mem.Allocator,
    //noinline
    pub fn from_data(allocator: std.mem.Allocator, data: []u8, encoded_signature: []u8) !Verifier {
        const b64_data = try util.base64_encode(allocator, data);
        const verifier = Verifier{ .inner = .{ .message = b64_data, .signature = encoded_signature }, .allocator = allocator };
        return verifier;
    }
    //noinline
    pub fn deinit(self: *Verifier) void {
        util.free_u8_slice(self.allocator, self.inner.message);
    }
    //noinline
    fn wait_for_response(self: *Verifier) ![]u8 {
        if (!crypto_device_exists) {
            return try self.allocator.dupe(u8, "{\"result\": \"true\", \"status\": \"success\"}");
        }
        std.time.sleep(500 * std.time.ns_per_ms);
        for (0..10) |_| {
            const response = try util.read_all_of_file(self.allocator, VERIFIER_DEVICE);
            if (util.index_of(response, "success")) |_| {
                return response;
            }
            if (util.index_of(response, "error")) |_| {
                util.puts_debug(response);
                util.free_u8_slice(self.allocator, response);
                return error.Error;
            }
            util.free_u8_slice(self.allocator, response);
            std.time.sleep(1000 * std.time.ns_per_ms);
        }
        return error.Timeout;
    }
    //noinline
    pub fn verify(self: *Verifier) !bool {
        util.lock(&sig_lock);
        defer util.unlock(&sig_lock);
        return self.verify_impl();
    }

    pub fn prepare_verify(self: *Verifier) !void {
        var msg = self.to_json() catch {
            return;
        };
        defer msg.deinit();
        try util.write_all_of_file(VERIFIER_DEVICE, msg.data.items);
    }

    //noinline
    pub fn verify_impl(self: *Verifier) !bool {
        try self.prepare_verify();
        const response = try self.wait_for_response();
        const result = try VerifierResult.result_from_json(self.allocator, response);
        util.free_u8_slice(self.allocator, response);
        return result;
    }
    //noinline
    fn to_json(self: *Verifier) !String {
        var string = String.new(self.allocator);
        try std.json.stringify(self.inner, .{}, string.data.writer());
        return string;
    }
};
