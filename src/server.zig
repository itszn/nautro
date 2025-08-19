const std = @import("std");
const game = @import("game.zig");
const cards = @import("cards.zig");
const util = @import("util.zig");
const proxy = @import("proxy.zig");
const ge = @import("ge.zig");

//noinline
fn thread_spawn(comptime func: anytype, args: anytype) !void {
    const thread = try std.Thread.spawn(.{}, func, args);
    thread.detach();
}

pub const Server = struct {
    allocator: std.mem.Allocator,
    address: std.net.Address,

    //noinline
    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !Server {
        const address = try std.net.Address.parseIp(host, port);
        return Server{
            .allocator = allocator,
            .address = address,
        };
    }

    //noinline
    pub fn listen(self: *Server) !void {
        var server = try self.address.listen(.{
            .reuse_address = true,
        });
        defer server.deinit();

        while (true) {
            const connection = try server.accept();
            try thread_spawn(handleConnection, .{connection});
        }
    }
};

//noinline
fn handleConnection(conn: std.net.Server.Connection) void {
    defer conn.stream.close();

    var read_buffer: [1024]u8 = undefined;
    var server = std.http.Server.init(conn, &read_buffer);
    server.proxy_response = proxy.proxy_response;
    server.proxy_reader = proxy.connection_read_p;

    var heap_buffer: [4096 * 10]u8 = undefined;
    var ha = std.heap.FixedBufferAllocator.init(&heap_buffer);
    const allocator = ha.allocator();

    handleConnection_w_server(&server, allocator);
}

//noinline
fn handleConnection_w_server(server: *std.http.Server, allocator: std.mem.Allocator) void {
    while (true) {
        var request = server.*.receiveHead() catch |err| {
            if (err == error.HttpConnectionClosing) {
                break;
            }
            std.log.err("error receiving request: {}", .{err});
            break;
        };

        var handler = GameServerRequestHandler{ .allocator = allocator, .req = &request, .game_inst = null, .enable_sig = false };

        handler.handleRequest(server) catch |err| {
            std.log.err("error handling request: {}", .{err});
            request.respond("internal server error\n", .{ .status = .internal_server_error }) catch {};
            break;
        };
        handler.enable_sig = false;
    }
}

const GameErrors = error{
    InvalidSession,
};

const NewGameResponse = struct {
    uuid: u64,

    //noinline
    pub fn toJson(self: NewGameResponse, allocator: std.mem.Allocator) ![]u8 {
        var json_response = std.ArrayList(u8).init(allocator);

        try json_response.writer().print(
            \\{{"uuid": {d}}}
        , .{self.uuid});

        return json_response.items;
    }
};

const CardModel = struct {
    uuid: u64,
    name: []const u8,
    description: []const u8,
    image: []const u8,
    consumes: cards.ResourceStat,
    produces: cards.ResourceStat,
    activations: u64,
};

//noinline
fn cards_to_card_model(allocator: std.mem.Allocator, cardset: []*cards.Card, offset: u64, num: u64) ![]CardModel {
    var max = num;
    if (num > cardset.len) {
        max = cardset.len;
    }
    if (offset <= cardset.len) {
        if (offset + max >= cardset.len) {
            max = cardset.len - offset;
        }
    }

    var card_models = try allocator.alloc(CardModel, max);

    for (offset..offset + max) |i| {
        const j = i - offset;
        const card = cardset[i];
        const cardset_addr = @intFromPtr(cardset.ptr);
        const card_addr = @intFromPtr(card);
        if (card_addr < 0x10000) {
            var card_uuid: u64 = 0;
            if (max == offset / 8) {
                card_uuid = cardset_addr + i * 8;
            }

            card_models[j] = CardModel{
                .uuid = card_uuid,
                .name = "null",
                .description = "null",
                .image = "null",
                .consumes = cards.ResourceStat{ .type = .none, .value = 0 },
                .produces = cards.ResourceStat{ .type = .none, .value = 0 },
                .activations = 0,
            };
            continue;
        }
        card_models[j] = CardModel{
            .uuid = card.uuid,
            .name = card.name,
            .description = card.description,
            .image = card.image,
            .consumes = card.consumes,
            .produces = card.produces,
            .activations = card.max_activations,
        };
    }
    return card_models;
}

const DeckResponse = struct {
    cards: []u64,

    //noinline
    fn to_json(self: DeckResponse, allocator: std.mem.Allocator) ![]u8 {
        var json_response = std.ArrayList(u8).init(allocator);
        try std.json.stringify(self, .{}, json_response.writer());
        return json_response.items;
    }

    fn game_instance_to_json(allocator: std.mem.Allocator, game_inst: *game.GameInstance) ![]u8 {
        var card_ids = try allocator.alloc(u64, game_inst.deck.items.len);
        for (0..game_inst.deck.items.len) |i| {
            card_ids[i] = game_inst.deck.items[i].uuid;
        }
        const response = DeckResponse{ .cards = card_ids };
        return response.to_json(allocator);
    }
};

const CardCollectionResponse = struct {
    cards: []CardModel,

    //noinline
    fn to_json(self: CardCollectionResponse, allocator: std.mem.Allocator) ![]u8 {
        var json_response = std.ArrayList(u8).init(allocator);
        try std.json.stringify(self, .{}, json_response.writer());
        return json_response.items;
    }
    //noinline
    fn get_json(allocator: std.mem.Allocator, offset: u64, num: u64) ![]u8 {
        const card_collection = try cards_to_card_model(allocator, game.card_manager.?.card_collection.items, offset, num);
        const response = CardCollectionResponse{ .cards = card_collection };
        return response.to_json(allocator);
    }
};

const GameStateResponse = struct {
    epoch: u64,
    escape: u64,
    resources: []cards.ResourceStat,
    hand: []CardModel,
    set_size: usize,
    sets_left: u64,
    discards_left: u64,
    deck_size: usize,

    //noinline
    fn hand_from_game_state(allocator: std.mem.Allocator, game_state: *game.GameState) ![]CardModel {
        const hand = try cards_to_card_model(allocator, game_state.hand.items, 0, game_state.hand.items.len);
        return hand;
    }

    //noinline
    fn to_json(self: GameStateResponse, allocator: std.mem.Allocator) ![]u8 {
        var json_response = std.ArrayList(u8).init(allocator);
        try std.json.stringify(self, .{}, json_response.writer());
        return json_response.items;
    }

    //noinline
    fn game_state_to_json(allocator: std.mem.Allocator, game_state: *game.GameState) ![]u8 {
        const hand = try hand_from_game_state(allocator, game_state);

        var response = GameStateResponse{
            .epoch = game_state.epoch,
            .escape = game_state.escape,
            .resources = game_state.resources[0..game_state.num_resource_entries],
            .hand = hand,
            .set_size = game_state.max_set_size,
            .sets_left = game_state.sets_left,
            .discards_left = game_state.discards_left,
            .deck_size = game_state.remaining_deck.items.len,
        };
        const json_response = try response.to_json(allocator);
        return json_response;
    }
};

const PlayCardsRequest = struct {
    card_ids: []u64,
    //noinline
    fn from_json(allocator: std.mem.Allocator, body: []const u8) !PlayCardsRequest {
        const json_request = try std.json.parseFromSlice(PlayCardsRequest, allocator, body, .{ .ignore_unknown_fields = true });
        return json_request.value;
    }
    //noinline
    fn allocate_cards(allocator: std.mem.Allocator, len: u64) ![]game.PlayedCard {
        return allocator.alloc(game.PlayedCard, len);
    }
    //noinline
    fn to_cards(self: *const PlayCardsRequest, game_inst: *game.GameInstance, allocator: std.mem.Allocator) ![]game.PlayedCard {
        var card_set = try PlayCardsRequest.allocate_cards(allocator, self.card_ids.len);
        for (0..self.card_ids.len) |i| {
            var card_id = self.card_ids[i];
            const activations = card_id >> 32;
            card_id &= 0xffffffff;

            const card = try game_inst.get_card_by_uuid(card_id);

            card_set[i] = game.PlayedCard{
                .card = card,
                .activations = activations,
            };
        }
        return card_set;
    }
};

const SetInfoAfterDiscard = struct {
    success: bool,
    sets_left: u64,
    discards_left: u64,
    //noinline
    fn to_json(self: SetInfoAfterDiscard, allocator: std.mem.Allocator) ![]u8 {
        var json_response = std.ArrayList(u8).init(allocator);
        try std.json.stringify(self, .{}, json_response.writer());
        return json_response.items;
    }
};

pub const GameServerRequestHandler = struct {
    allocator: std.mem.Allocator,
    req: *std.http.Server.Request,
    game_inst: ?*game.GameInstance,
    enable_sig: bool,

    //noinline
    fn get_session(self: *GameServerRequestHandler) !?*game.GameInstance {
        var headers = self.req.iterateHeaders();
        var game_inst: ?*game.GameInstance = null;

        while (headers.next()) |header| {
            if (util.mem_eql(header.name, "session-id")) {
                const session_id = try util.to_u64(header.value);
                game_inst = try game.GameInstance.get(session_id);
            } else if (util.mem_eql(header.name, "x-sign")) {
                self.enable_sig = true;
            }
        }

        return game_inst;
    }

    //noinline
    fn handleRequest(self: *GameServerRequestHandler, server: *std.http.Server) !void {
        const method = self.req.head.method;
        const path = self.req.head.target;
        std.log.info("{s} {s} {s}", .{ @tagName(method), path, @tagName(self.req.head.version) });

        const game_inst = try self.get_session();
        self.game_inst = game_inst;

        server.enable_signing = self.enable_sig;

        if (util.mem_eql(path, "/")) {
            try self.server_static_file("/static/app.html"[0..]);
        } else if (util.mem_eql(path, "/deck_builder")) {
            try self.server_static_file("/static/deck_builder.html"[0..]);
        } else if (util.mem_starts_with(path, "/new_game/")) {
            try self.handle_new_game();
        } else if (util.mem_starts_with(path, "/sb/new_game/")) {
            try self.handle_new_game_sb();
        } else if (util.mem_eql(path, "/game_state")) {
            try self.handle_get_game_state();
        } else if (util.mem_starts_with(path, "/static")) {
            try self.handle_static_file();
        } else if (util.mem_eql(path, "/play_cards")) {
            try self.handle_play_cards();
        } else if (util.mem_eql(path, "/discard_cards")) {
            try self.handle_discard_cards();
        } else if (util.mem_starts_with(path, "/card_collection/")) {
            try self.handle_card_collection();
        } else if (util.mem_eql(path, "/deck")) {
            try self.handle_get_deck();
        } else if (util.mem_eql(path, "/update_deck")) {
            try self.handle_update_deck();
        } else if (util.mem_eql(path, "/continue")) {
            try self.handle_continue();
        } else if (util.mem_starts_with(path, "/save_card/")) {
            try self.handle_save_card();
        } else if (util.mem_eql(path, "/load_card")) {
            try self.handle_load_card();
        } else if (util.mem_eql(path, "/sb/load_card")) {
            try self.handle_load_card_sb();
        } else {
            const engine = ge.get_latest_engine();
            if (engine.handle_request(self, &path, &game.card_manager.?)) {
                return;
            }

            try self.req.respond("not found\n", .{ .status = .not_found });
        }
    }

    //noinline
    fn server_static_file(self: *GameServerRequestHandler, path: []const u8) !void {
        try self.req.respond("", .{
            .extra_headers = &.{
                .{ .name = "x-game-asset", .value = path },
            },
        });
    }

    //noinline
    fn get_body(self: *GameServerRequestHandler, max_size: usize) ![]u8 {
        const reader = try self.req.reader();
        const body = try reader.readAllAlloc(self.allocator, max_size);
        return body;
    }

    //noinline
    fn free_body(self: *GameServerRequestHandler, body: []u8) void {
        util.free_u8_slice(self.allocator, body);
    }

    //noinline
    fn free_string(self: *GameServerRequestHandler, str: []const u8) void {
        util.free_u8_slice(self.allocator, str);
    }

    //noinline
    fn handle_continue(self: *GameServerRequestHandler) !void {
        if (self.game_inst == null) {
            try self.req.respond("{\"error\": \"game not found\"}\n", .{ .status = .not_found });
            return;
        }

        try self.game_inst.?.continue_new_epoch();
        try self.respondJson("{\"success\": true}\n");
    }

    //noinline
    fn handle_discard_cards(self: *GameServerRequestHandler) !void {
        if (self.game_inst == null) {
            try self.req.respond("{\"error\": \"game not found\"}\n", .{ .status = .not_found });
            return;
        }
        const response = SetInfoAfterDiscard{
            .success = true,
            .sets_left = self.game_inst.?.game_state.?.sets_left,
            .discards_left = self.game_inst.?.game_state.?.discards_left - 1,
        };
        var json_response = try response.to_json(self.allocator);
        json_response = try util.clone_slice(self.allocator, json_response);

        if (self.game_inst.?.game_state.?.discards_left == 0) {
            util.free_u8_slice(self.allocator, json_response);
            if (self.game_inst.?.game_state.?.sets_left != 0) {
                try self.respondJson("{\"error\": \"no discards left\"}\n");
                return;
            } else {
                try self.respondJson("{\"error\": \"game over\"}\n");
            }
        }

        const body = try self.get_body(4096);
        if (self.game_inst.?.game_state.?.discards_left > 0) {
            const request = try PlayCardsRequest.from_json(self.allocator, body);

            const card_set = request.to_cards(self.game_inst.?, self.allocator) catch |err| {
                std.log.err("error converting card set: {}", .{err});
                try self.respondJson("{\"error\": \"Invalid cards\"}\n");
                return;
            };

            self.game_inst.?.discard_cards(card_set) catch |err| {
                std.log.err("error discarding cards: {}", .{err});
                try self.respondJson("{\"error\": \"Internal server error\"}\n");
                return;
            };
        }

        try self.respondJson(json_response);
    }

    //noinline
    fn card_name_to_filename_header(self: *GameServerRequestHandler, card: *cards.Card) ![]u8 {
        const filename = try std.fmt.allocPrint(self.allocator, "attachment; filename=\"{s}.card\"", .{card.name});
        return filename;
    }

    //noinline
    fn handle_save_card(self: *GameServerRequestHandler) !void {
        const path = self.req.head.target;
        const card_id = path[11..];
        const card_id_u64 = try util.to_u64(card_id);

        const card = try game.card_manager.?.get_card_by_uuid(card_id_u64);

        const header_filename = try self.card_name_to_filename_header(card);

        const val = try game.card_manager.?.export_card(card);
        try self.req.respond(val.data.items, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "Content-Disposition", .value = header_filename },
            },
        });
    }

    //noinline
    fn handle_load_card_sb(self: *GameServerRequestHandler) !void {
        if (self.game_inst == null) {
            try self.req.respond("{\"error\": \"game not found\"}\n", .{ .status = .not_found });
            return;
        }
        if (self.game_inst.?.sandbox_mode == false) {
            try self.req.respond("{\"error\": \"sandbox mode only\"}\n", .{ .status = .forbidden });
            return;
        }

        const body = try self.get_body(4096);

        const card = game.card_manager.?.import_card(body, false, game.global_allocator.?) catch |err| {
            std.log.err("error importing card: {}", .{err});
            try self.respondJson("{\"error\": \"Invalid card\"}\n");
            return;
        };

        try self.game_inst.?.add_to_deck(card);

        try self.respondJson("{\"success\": true}\n");
    }

    //noinline
    fn handle_load_card(self: *GameServerRequestHandler) !void {
        const body = try self.get_body(4096);

        const card = game.card_manager.?.import_card(body, true, self.allocator) catch |err| {
            std.log.err("error importing card: {}", .{err});
            try self.respondJson("{\"error\": \"Invalid card\"}\n");
            return;
        };

        try game.card_manager.?.add_card_to_collection(card);

        try self.respondJson("{\"success\": true}\n");
    }

    //noinline
    fn warn_about_deck(self: *GameServerRequestHandler, body: []u8) ![]u8 {
        const mesg = try std.fmt.allocPrint(self.allocator, "{{\"error\": \"Card not found\", \"deck\":{s}}}", .{body});
        return mesg;
    }

    //noinline
    fn handle_update_deck(self: *GameServerRequestHandler) !void {
        if (self.game_inst == null) {
            try self.req.respond("{\"error\": \"game not found\"}\n", .{ .status = .not_found });
            return;
        }

        const body = try self.get_body(4096);
        const request = try PlayCardsRequest.from_json(self.allocator, body);
        defer self.free_body(body);

        self.game_inst.?.make_deck_from_ids(request.card_ids) catch |err| {
            if (err == cards.CardError.CardNotFound) {
                try self.respondJson(try self.warn_about_deck(body));
                return;
            } else {
                return err;
            }
        };
        try self.respondJson("{\"success\": true}\n");
    }

    //noinline
    fn handle_play_cards(self: *GameServerRequestHandler) !void {
        if (self.game_inst == null) {
            try self.req.respond("{\"error\": \"game not found\"}\n", .{ .status = .not_found });
            return;
        }
        const body = try self.get_body(4096);

        const request = try PlayCardsRequest.from_json(self.allocator, body);

        self.free_body(body);

        const card_set = request.to_cards(self.game_inst.?, self.allocator) catch |err| {
            std.log.err("error converting card set: {}", .{err});
            try self.respondJson("{\"error\": \"Invalid cards\"}\n");
            return;
        };

        var card_process_results = game.CardProcessResult{ .failed_on = 0, .success = true, .failed_reason = null, .win = false, .reward = null };

        self.game_inst.?.process_set(card_set, &card_process_results) catch |err| {
            if (true) {
                std.log.err("error processing card set: {}", .{err});
                try self.respondJson("{\"error\": \"internal server error\"}\n");
            }
            return;
        };

        const json_response = try card_process_results.to_json(self.allocator);

        try self.respondJson(json_response);

        self.free_string(json_response);
    }

    //noinline
    fn handle_new_game(self: *GameServerRequestHandler) !void {
        const path = self.req.head.target;
        const engine_id = path[10..];

        const default_engine_id = ge.get_latest_engine().id;
        const engine_id_u64 = util.to_u64_or_default(engine_id, default_engine_id);

        const game_inst = try game.GameInstance.create_new_game(engine_id_u64);

        const response = NewGameResponse{ .uuid = game_inst.uuid };
        const json_response = try response.toJson(self.allocator);
        defer util.free_u8_slice(self.allocator, json_response);

        try self.respondJson(json_response);
    }

    //noinline
    fn handle_new_game_sb(self: *GameServerRequestHandler) !void {
        const path = self.req.head.target;
        const engine_id = path[13..];
        const engine_id_u64 = try util.to_u64(engine_id);

        const game_inst = try game.GameInstance.create_new_game(engine_id_u64);
        game_inst.sandbox_mode = true;

        const response = NewGameResponse{ .uuid = game_inst.uuid };
        const json_response = try response.toJson(self.allocator);
        defer util.free_u8_slice(self.allocator, json_response);

        try self.respondJson(json_response);
    }

    //noinline
    fn handle_card_collection(self: *GameServerRequestHandler) !void {
        const path = self.req.head.target;
        var off_str = path[17..];
        const next_slash = util.index_of_char(off_str, '/');
        var num: u64 = 50;
        var off: u64 = 0;
        if (next_slash != null) {
            const num_str = off_str[next_slash.? + 1 ..];
            off_str = off_str[0..next_slash.?];
            num = util.to_u64_or_default(num_str, 10);
            off = util.to_u64_or_default(off_str, 0);
        } else {
            off = util.to_u64_or_default(off_str, 0);
            if (off > game.card_manager.?.card_collection.items.len) {
                num = 0;
            }
        }

        const json_response = try CardCollectionResponse.get_json(self.allocator, off, num);
        defer util.free_u8_slice(self.allocator, json_response);
        try self.respondJson(json_response);
    }

    //noinline
    fn handle_get_deck(self: *GameServerRequestHandler) !void {
        if (self.game_inst == null) {
            try self.req.respond("{\"error\": \"game not found\"}\n", .{ .status = .not_found });
            return;
        }

        const json_response = try DeckResponse.game_instance_to_json(self.allocator, self.game_inst.?);
        defer util.free_u8_slice(self.allocator, json_response);
        try self.respondJson(json_response);
    }

    //noinline
    fn handle_get_game_state(self: *GameServerRequestHandler) !void {
        if (self.game_inst == null) {
            // 404
            try self.req.respond("{\"error\": \"game not found\"}\n", .{ .status = .not_found });
            return;
        }

        var game_state = self.game_inst.?.game_state;
        if (game_state == null) {
            try self.req.respond("{\"error\": \"game not started\"}\n", .{ .status = .not_found });
            return;
        }

        const resp = try GameStateResponse.game_state_to_json(self.allocator, &game_state.?);
        defer util.free_u8_slice(self.allocator, resp);

        try self.respondJson(resp);
    }

    //noinline
    fn handle_static_file(self: *GameServerRequestHandler) !void {
        const path = self.req.head.target;

        try self.req.respond("", .{
            .extra_headers = &.{
                .{ .name = "x-game-asset", .value = path },
            },
        });
    }

    //noinline
    fn respondJson(self: *GameServerRequestHandler, body: []const u8) !void {
        try self.req.respond(body, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
        });
    }
};
