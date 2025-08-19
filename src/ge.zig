const std = @import("std");
const cards = @import("cards.zig");
const util = @import("util.zig");
const game = @import("game.zig");
const server = @import("server.zig");

const engine_base = @import("engine_base.zig");

var run_fn: ?(*const fn (game_state: *game.GameState, resources: *game.SetResources, active_card: *cards.Card, num_activations: u64, error_: *error{ EOF, InvalidTag }!u64) callconv(.c) bool) = null;

const GameEngine = struct {
    id: u64,
    run_fn: *const fn (game_state: *game.GameState, resources: *game.SetResources, active_card: *cards.Card, num_activations: u64, error_: *error{ EOF, InvalidTag }!u64) callconv(.c) bool,
    handle_request_fn: *const fn (serv: *server.GameServerRequestHandler, path: *const []const u8, card_manager: *cards.CardManager) callconv(.c) bool,

    //noinline
    pub fn run(self: *const GameEngine, game_state: *game.GameState, resources: *game.SetResources, active_card: *cards.Card, num_activations: u64) !bool {
        var error_out: error{ EOF, InvalidTag }!u64 = 0;

        const run_fn_: *const fn (game_state: *game.GameState, resources: *game.SetResources, active_card: *cards.Card, num_activations: u64, error_: *error{ EOF, InvalidTag }!u64) callconv(.c) bool = self.run_fn;

        var use_lib = false;
        use_lib = true;
        //DEBUGONLY
        use_lib = false;
        if (use_lib) {
            const res = run_fn_(game_state, resources, active_card, num_activations, &error_out);
            _ = error_out catch |err| {
                return err;
            };

            return res;
        } else {
            const res = engine_base.run(game_state, resources, active_card, num_activations, &error_out);
            _ = error_out catch |err| {
                return err;
            };

            return res;
        }
    }

    //noinline
    pub fn handle_request(self: *const GameEngine, serv: *server.GameServerRequestHandler, path: *const []const u8, card_manager: *cards.CardManager) callconv(.c) bool {
        const handle_request_fn_: *const fn (serv: *server.GameServerRequestHandler, path: *const []const u8, card_manager: *cards.CardManager) callconv(.c) bool = self.handle_request_fn;

        var use_lib = false;
        use_lib = true;
        //DEBUGONLY
        use_lib = false;
        if (use_lib) {
            return handle_request_fn_(serv, path, card_manager);
        } else {
            return engine_base.handle_request(serv, path, card_manager);
        }
    }
};

var game_engines: [2]?GameEngine = .{ null, null };

//noinline
pub fn init_engine(engine_path: []const u8, engine_id: u64) void {
    var dyn_lib = std.DynLib.open(engine_path) catch return;

    game_engines[engine_id] = GameEngine{
        .id = engine_id,
        .run_fn = dyn_lib.lookup(
            @TypeOf(game_engines[engine_id].?.run_fn),
            "run",
        ).?,
        .handle_request_fn = dyn_lib.lookup(
            @TypeOf(game_engines[engine_id].?.handle_request_fn),
            "handle_request",
        ).?,
    };
}

//noinline
pub fn init_engines() void {
    init_engine("./libengine_base.so", 0);
    init_engine("./libengine_advanced.so", 1);
}

pub fn get_engine_raw(engine_id: u64) ?*GameEngine {
    if (game_engines[engine_id] == null) {
        return null;
    }
    return &game_engines[engine_id].?;
}

pub fn get_latest_engine() *const GameEngine {
    const a = get_engine_raw(1);
    if (a == null) {
        return get_engine_raw(0).?;
    }
    return a.?;
}

pub fn get_engine(engine_id: u64) *const GameEngine {
    return &game_engines[engine_id].?;
}

pub fn run(game_state: *game.GameState, resources: *game.SetResources, active_card: *cards.Card, num_activations: u64) !bool {
    if (run_fn == null) {
        var dyn_lib = std.DynLib.open("./libengine_base.so") catch return false;
        run_fn = dyn_lib.lookup(
            @TypeOf(run_fn.?),
            "run",
        );
    }

    var error_out: error{ EOF, InvalidTag }!u64 = 0;

    const res = run_fn.?(game_state, resources, active_card, num_activations, &error_out);

    _ = error_out catch |err| {
        return err;
    };

    return res;
}
