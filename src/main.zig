const std = @import("std");
const util = @import("util.zig");
const crypto = @import("crypto.zig");
const cards = @import("cards.zig");
const server = @import("server.zig");
const game = @import("game.zig");
const ge = @import("ge.zig");

const String = util.String;
//
//
//
//

//noinline
pub fn main() !void {
    const allocator = std.heap.c_allocator;

    try game.init(allocator);
    ge.init_engines();

    try crypto.init();

    var game_server = try server.Server.init(allocator, "0.0.0.0", 8080);
    try game_server.listen();
}
