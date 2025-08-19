const std = @import("std");
const cards = @import("cards.zig");
const util = @import("util.zig");
const ge = @import("ge.zig");

var game_instances: ?std.AutoHashMap(u64, *GameInstance) = null;
pub var global_allocator: ?std.mem.Allocator = null;
pub var card_manager: ?cards.CardManager = null;

pub fn init(allocator: std.mem.Allocator) !void {
    game_instances = std.AutoHashMap(u64, *GameInstance).init(allocator);
    global_allocator = allocator;
    card_manager = cards.CardManager{
        .allocator = allocator,
        .card_collection = std.ArrayList(*cards.Card).init(allocator),
    };
    try card_manager.?.load_all_base_cards();
}

var uuid_counter: u64 = 0;

var game_instances_lock = std.Thread.RwLock.DefaultRwLock{};

//noinline
fn create_allocator() std.mem.Allocator {
    var ga = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = ga.allocator();
    return allocator;
}

//noinline
fn lock_game_instances() void {
    util.lock(&game_instances_lock);
}

//noinline
fn unlock_game_instances() void {
    util.unlock(&game_instances_lock);
}

//noinline
fn put_game_instance(uuid: u64, game_instance: *GameInstance) !void {
    try game_instances.?.put(uuid, game_instance);
}

//noinline
fn get_game_instance(uuid: u64) !?*GameInstance {
    util.rlock(&game_instances_lock);
    defer util.runlock(&game_instances_lock);
    return game_instances.?.get(uuid);
}

pub const max_num_resources: comptime_int = @intFromEnum(cards.ResourceType.undefined);

pub const PlayedCard = struct {
    card: *cards.Card,
    activations: u64,
};

pub const GameState = struct {
    epoch: u64,
    escape: u64,

    sets_left: u64,
    discards_left: u64,

    hand: std.ArrayList(*cards.Card),
    resources: [max_num_resources]cards.ResourceStat,
    num_resource_entries: usize,
    remaining_deck: std.ArrayList(*cards.Card),
    persistent_cards: std.ArrayList(*cards.Card),
    hand_size: usize,
    max_set_size: usize,
    ready_for_next_stage: bool,

    //noinline
    pub fn update_resources(self: *GameState, resources: []cards.ResourceStat) void {
        var i: usize = 0;
        var j: usize = 0;
        while (i < max_num_resources and j < resources.len) : (j += 1) {
            const input_resource = resources[j];
            if (input_resource.type == .none or input_resource.value == 0 and input_resource.type != .energy) {
                continue;
            }

            self.resources[i] = input_resource;
            i += 1;
        }
        self.num_resource_entries = i;
    }

    //noinline
    pub fn next_level(self: *GameState, energy: u64, result: *CardProcessResult) void {
        var remaining_energy = energy;
        _ = result;

        while (remaining_energy > self.escape) {
            remaining_energy -= self.escape;
            self.epoch += 1;
            self.escape *= 2;
            self.sets_left = 4;
            self.discards_left = 3;
            self.hand_size += 1;
            if (self.epoch > 32) {
                break;
            }
        }

        self.ready_for_next_stage = true;

        self.resources[0].value = remaining_energy;

        self.clear_deck();
        self.clear_hand();
    }

    //noinline
    pub fn clear_deck(self: *GameState) void {
        self.remaining_deck.clearAndFree();
    }

    //noinline
    pub fn reset_deck(self: *GameState, deck: []*cards.Card) void {
        self.clear_deck();
        self.clear_hand();
        for (deck) |card| {
            try self.add_to_deck(card);
        }
        self.shuffle_deck();
        try self.refill_hand();
    }

    //noinline
    fn append_card_to_hand(self: *GameState, card: *cards.Card) !void {
        try self.hand.append(card);
    }

    //noinline
    fn get_card_index(self: *GameState, card: *cards.Card) ?usize {
        for (0..self.hand.items.len) |i| {
            if (self.hand.items[i] == card) {
                return i;
            }
        }
        return null;
    }
    //noinline
    fn remove_card_index_from_hand(self: *GameState, i: usize) void {
        _ = self.hand.orderedRemove(i);
    }

    //noinline
    pub fn remove_card_from_hand(self: *GameState, card: *cards.Card) bool {
        const i = self.get_card_index(card);
        if (i != null) {
            self.remove_card_index_from_hand(i.?);
            return true;
        }
        return false;
    }

    //noinline
    pub fn remove_cards_from_hand(self: *GameState, card_set: []PlayedCard) void {
        for (card_set) |card_info| {
            _ = self.remove_card_from_hand(card_info.card);
        }
    }

    //noinline
    pub fn get_resource_value(self: *GameState, resource_type: cards.ResourceType) u64 {
        for (0..self.num_resource_entries) |i| {
            if (self.resources[i].type == resource_type) {
                return self.resources[i].value;
            }
        }
        return 0;
    }

    //noinline
    pub fn pop_card_from_deck(self: *GameState) ?*cards.Card {
        return self.remaining_deck.pop();
    }

    //noinline
    pub fn add_to_deck(self: *GameState, card: *cards.Card) !void {
        try self.remaining_deck.append(card);
    }

    //noinline
    pub fn init_from_deck(self: *GameState, deck: []*cards.Card) !void {
        self.clear_deck();
        self.clear_hand();
        for (deck) |card| {
            try self.add_to_deck(card);
        }
    }

    //noinline
    pub fn shuffle_deck(self: *GameState) void {
        if (self.remaining_deck.items.len == 0) {
            return;
        }
        var prng = std.Random.DefaultPrng.init(self.epoch + uuid_counter);
        const rand = prng.random();
        for (0..100) |_| {
            const i = rand.intRangeAtMost(usize, 0, self.remaining_deck.items.len - 1);
            const j = rand.intRangeAtMost(usize, 0, self.remaining_deck.items.len - 1);
            const temp = self.remaining_deck.items[i];
            self.remaining_deck.items[i] = self.remaining_deck.items[j];
            self.remaining_deck.items[j] = temp;
        }
    }
    //noinline
    pub fn clear_hand(self: *GameState) void {
        self.hand.clearAndFree();
    }

    //noinline
    pub fn refill_hand(self: *GameState) !void {
        while (self.hand.items.len < self.hand_size and self.remaining_deck.items.len > 0) {
            const card = self.pop_card_from_deck();
            if (card != null) {
                try self.append_card_to_hand(card.?);
            } else {
                break;
            }
        }
    }

    //noinline
    pub fn add_persistent_card(self: *GameState, card: *cards.Card) !void {
        try self.persistent_cards.append(card);
    }

    //noinline
    pub fn remove_persistent_card(self: *GameState, card: *cards.Card) bool {
        for (0..self.persistent_cards.items.len) |i| {
            if (self.persistent_cards.items[i] == card) {
                self.persistent_cards.orderedRemove(i);
                return true;
            }
        }
        return false;
    }
};

pub const SetResources = struct {
    resources: [max_num_resources]cards.ResourceStat,
    //noinline
    fn init(self: *SetResources) void {
        for (0..max_num_resources) |i| {
            self.resources[i] = cards.ResourceStat{
                .type = cards.ResourceType.from_int(i),
                .value = 0,
            };
        }
    }
    //noinline
    pub fn set_base_resources(self: *SetResources, resources: []cards.ResourceStat) void {
        for (0..resources.len) |i| {
            const resource_num = resources[i].type.to_int();
            self.resources[resource_num] = resources[i];
        }
    }
    //noinline
    pub fn get_resource(self: *SetResources, resource_type: cards.ResourceType) cards.ResourceStat {
        const resource_num = resource_type.to_int();
        return self.resources[resource_num];
    }
    //noinline
    pub fn consume_resource(self: *SetResources, resource: cards.ResourceStat) bool {
        const resource_num = resource.type.to_int();
        const req_value = resource.value;
        if (req_value > self.resources[resource_num].value) {
            return false;
        }
        const before = self.resources[resource_num].value;
        self.resources[resource_num].value -= req_value;
        _ = before;
        return true;
    }
    //noinline
    pub fn consume_resource_max(self: *SetResources, resource: cards.ResourceStat, max_applies: u64) u64 {
        const resource_num = resource.type.to_int();
        const resource_value = self.resources[resource_num].value;
        const req_value = resource.value;

        if (req_value > resource_value) {
            return 0;
        }

        var num_applies = resource_value / req_value;
        if (max_applies > 0 and num_applies > max_applies) {
            num_applies = max_applies;
        }
        self.resources[resource_num].value -= num_applies * req_value;

        return num_applies;
    }
    //noinline
    pub fn consume_resource_value(self: *SetResources, resource_type: cards.ResourceType, value: u32) bool {
        const resource_num = resource_type.to_int();
        if (value > self.resources[resource_num].value) {
            return false;
        }
        const before = self.resources[resource_num].value;
        self.resources[resource_num].value -= value;
        _ = before;
        return true;
    }
    //noinline
    pub fn add_resource(self: *SetResources, resource: cards.ResourceStat) void {
        const resource_num = resource.type.to_int();
        const before = self.resources[resource_num].value;
        self.resources[resource_num].value += resource.value;
        _ = before;
    }
    //noinline
    pub fn add_resource_value(self: *SetResources, resource_type: cards.ResourceType, value: u64) void {
        const resource_num = resource_type.to_int();
        const before = self.resources[resource_num].value;
        self.resources[resource_num].value += value;
        _ = before;
    }
};

pub const CardProcessResult = struct {
    failed_on: usize,
    success: bool,
    failed_reason: ?[]const u8,
    reward: ?[]const u8,
    win: bool,

    //noinline
    pub fn to_json(self: *const CardProcessResult, allocator: std.mem.Allocator) ![]u8 {
        var json_response = std.ArrayList(u8).init(allocator);
        try std.json.stringify(self, .{}, json_response.writer());
        return json_response.items;
    }
};

pub const GameInstance = struct {
    allocator: std.mem.Allocator,
    engine_id: u64,
    sandbox_mode: bool,
    lock: *std.Thread.RwLock.DefaultRwLock,
    uuid: u64,
    deck: std.ArrayList(*cards.Card),
    game_state: ?GameState,

    //noinline
    fn create_uninitialized(allocator: std.mem.Allocator) !*GameInstance {
        return try allocator.create(GameInstance);
    }

    //noinline
    pub fn take_lock(self: *GameInstance) void {
        util.lock(self.lock);
    }

    //noinline
    pub fn release_lock(self: *GameInstance) void {
        util.unlock(self.lock);
    }

    //noinline
    pub fn add_to_deck(self: *GameInstance, card: *cards.Card) !void {
        try self.deck.append(card);
    }

    //noinline
    pub fn clear_deck(self: *GameInstance) void {
        self.deck.clearAndFree();
    }

    //noinline
    pub fn make_deck_from_ids(self: *GameInstance, card_ids: []u64) !void {
        self.clear_deck();
        for (card_ids) |card_id| {
            const card = try card_manager.?.get_card_by_uuid(card_id);
            try self.add_to_deck(card);
        }
    }

    //noinline
    pub fn init_ptr(self: *GameInstance, allocator: std.mem.Allocator, uuid: u64) !void {
        const locker = try allocator.create(std.Thread.RwLock.DefaultRwLock);
        locker.* = std.Thread.RwLock.DefaultRwLock{};
        self.allocator = allocator;
        self.lock = locker;
        self.uuid = uuid;
        self.deck = std.ArrayList(*cards.Card).init(allocator);
        self.sandbox_mode = false;

        self.game_state = GameState{
            .epoch = 1,
            .escape = 5,
            .sets_left = 4,
            .discards_left = 3,
            .hand = std.ArrayList(*cards.Card).init(allocator),
            .resources = [_]cards.ResourceStat{.{ .type = .none, .value = 0 }} ** max_num_resources,
            .num_resource_entries = 1,
            .remaining_deck = std.ArrayList(*cards.Card).init(allocator),
            .hand_size = 10,
            .max_set_size = 5,
            .ready_for_next_stage = true,
            .persistent_cards = std.ArrayList(*cards.Card).init(allocator),
        };
        self.game_state.?.resources[0] = cards.ResourceStat{
            .type = .energy,
            .value = 1,
        };
        self.game_state.?.resources[1] = cards.ResourceStat{
            .type = .water,
            .value = 2,
        };
        self.game_state.?.resources[2] = cards.ResourceStat{
            .type = .food,
            .value = 2,
        };
        self.game_state.?.resources[3] = cards.ResourceStat{
            .type = .tool,
            .value = 2,
        };
        self.game_state.?.resources[4] = cards.ResourceStat{
            .type = .knowledge,
            .value = 1,
        };
        self.game_state.?.resources[5] = cards.ResourceStat{
            .type = .stone,
            .value = 1,
        };
        self.game_state.?.num_resource_entries = 6;

        try self.create_basic_deck();
    }

    //noinline
    pub fn add_card_to_deck_by_name(self: *GameInstance, name: []const u8) !void {
        const card = try card_manager.?.get_card_by_name(name);
        try self.add_to_deck(card);
    }

    //noinline
    pub fn create_basic_deck(self: *GameInstance) !void {
        // BASIC RESOURCE EXTRACTION (multiple food sources for reliability)
        try self.add_card_to_deck_by_name("Foraging");
        try self.add_card_to_deck_by_name("Fishing");
        try self.add_card_to_deck_by_name("Scavenging");
        try self.add_card_to_deck_by_name("Stone Quarry");
        try self.add_card_to_deck_by_name("Spring Water");
        try self.add_card_to_deck_by_name("Stone Gathering"); // backup stone source

        // TOOL CREATION & EARLY PROCESSING
        try self.add_card_to_deck_by_name("Tool Making");
        try self.add_card_to_deck_by_name("Stone Working");
        try self.add_card_to_deck_by_name("Composite Tools"); // multi-input efficiency

        // ENERGY GENERATION (multiple paths)
        try self.add_card_to_deck_by_name("Fire Making");
        try self.add_card_to_deck_by_name("Food Preparation");
        try self.add_card_to_deck_by_name("Cooked Meals"); // efficient multi-input
        try self.add_card_to_deck_by_name("Manual Labor"); // food→energy alternative

        // FOOD AMPLIFICATION
        try self.add_card_to_deck_by_name("Hunting"); // tools→food
        try self.add_card_to_deck_by_name("Farming"); // water→food scaling
        try self.add_card_to_deck_by_name("Herding"); // food→more food

        // KNOWLEDGE & SKILL DEVELOPMENT
        try self.add_card_to_deck_by_name("Observation"); // tools→knowledge
        try self.add_card_to_deck_by_name("Teaching"); // knowledge multiplication
        try self.add_card_to_deck_by_name("Cave Paintings"); // alternative knowledge
    }

    //noinline
    pub fn continue_new_epoch(self: *GameInstance) !void {
        if (!self.game_state.?.ready_for_next_stage) {
            return;
        }

        self.game_state.?.ready_for_next_stage = false;

        try self.game_state.?.init_from_deck(self.deck.items);

        self.game_state.?.shuffle_deck();

        try self.game_state.?.refill_hand();
    }

    //noinline
    pub fn create_new_game(engine_id: u64) !*GameInstance {
        lock_game_instances();
        defer unlock_game_instances();

        uuid_counter += 1;

        const allocator = global_allocator.?;

        const game_instance = try create_uninitialized(allocator);
        game_instance.engine_id = engine_id;

        try game_instance.init_ptr(allocator, uuid_counter);

        try put_game_instance(uuid_counter, game_instance);

        return game_instance;
    }

    //noinline
    pub fn get(uuid: u64) !?*GameInstance {
        return try get_game_instance(uuid);
    }

    //noinline
    pub fn deinit(self: *GameInstance) void {
        self.allocator.free(self.deck);
    }

    //noinline
    pub fn get_card_by_uuid(self: *GameInstance, uuid: u64) !*cards.Card {
        for (self.deck.items) |card| {
            if (card.uuid == uuid) {
                return card;
            }
        }
        return cards.CardError.CardNotFound;
    }

    //noinline
    pub fn discard_cards(self: *GameInstance, set: []PlayedCard) !void {
        self.take_lock();
        defer self.release_lock();

        if (self.game_state.?.discards_left == 0) {
            return;
        }

        for (set) |card| {
            const removed = self.game_state.?.remove_card_from_hand(card.card);
            if (removed) {
                try self.game_state.?.add_to_deck(card.card);
            }
        }
        self.game_state.?.shuffle_deck();
        try self.game_state.?.refill_hand();
        self.game_state.?.discards_left -= 1;
    }

    //noinline
    pub fn process_set(self: *GameInstance, set: []PlayedCard, result: *CardProcessResult) !void {
        self.take_lock();
        defer self.release_lock();

        for (0..set.len) |i| {
            for (0..set.len) |j| {
                if (i == j) {
                    continue;
                }
                if (set[i].card.uuid == set[j].card.uuid) {
                    result.failed_on = i;
                    result.success = false;
                    result.failed_reason = "Duplicate card in set";
                    return;
                }
            }
            var in_hand = false;
            for (0..self.game_state.?.hand.items.len) |j| {
                if (set[i].card.uuid == self.game_state.?.hand.items[j].uuid) {
                    in_hand = true;
                    break;
                }
            }
            if (!in_hand) {
                result.failed_on = i;
                result.success = false;
                result.failed_reason = "Card not in hand";
                return;
            }
        }

        if (self.game_state.?.sets_left == 0) {
            result.failed_on = 0;
            result.success = false;
            result.failed_reason = "GAME OVER";
            return;
        }

        if (set.len > self.game_state.?.max_set_size) {
            result.failed_on = 0;
            result.success = false;
            result.failed_reason = "Set size exceeds max set size";
            return;
        }

        var set_resources = SetResources{ .resources = undefined };
        set_resources.init();
        set_resources.set_base_resources(self.game_state.?.resources[0..self.game_state.?.num_resource_entries]);

        for (0..set.len) |i| {
            const card = set[i];

            try self.process_card(i, &set_resources, card, result);

            if (!result.success) {
                return;
            }
        }

        self.game_state.?.sets_left -= 1;

        self.game_state.?.update_resources(set_resources.resources[0..]);

        if (self.game_state.?.sets_left == 0) {
            self.game_state.?.clear_hand();
        } else {
            self.game_state.?.remove_cards_from_hand(set);

            try self.game_state.?.refill_hand();
        }

        const energy = self.game_state.?.get_resource_value(cards.ResourceType.energy);

        if (energy > self.game_state.?.escape) {
            result.win = true;
            self.game_state.?.next_level(energy, result);
            if (self.game_state.?.epoch > 32) {
                if (self.sandbox_mode == false) {
                    const flag_str = try util.read_all_of_file(self.allocator, "/flag");
                    result.reward = flag_str;
                } else {
                    result.reward = "You won sandbox mode, now win the game for real!";
                }
            }
        }
    }

    //noinline
    pub fn process_card(self: *GameInstance, i: usize, resources: *SetResources, card_info: PlayedCard, result: *CardProcessResult) !void {
        const card = card_info.card;
        const played_activations = card_info.activations;

        var num_applies: u64 = 1;
        var max_activations = card.max_activations;

        if (played_activations > 0 and (max_activations == 0 or played_activations < max_activations)) {
            max_activations = played_activations;
        }

        if (max_activations > 0) {
            num_applies = max_activations;
        }

        if (card.consumes.type != .none and card.consumes.value > 0) {
            num_applies = resources.consume_resource_max(card.consumes, max_activations);
        }

        if (num_applies == 0) {
            result.failed_on = i;
            result.success = false;
            result.failed_reason = "Not enough resources to activate card";
            return;
        }

        if (card.code != null or self.game_state.?.persistent_cards.items.len > 0) {
            const engine = ge.get_engine(self.engine_id);
            const is_ok = try engine.run(&self.game_state.?, resources, card, num_applies);
            if (!is_ok) {
                result.failed_on = i;
                result.success = false;
                result.failed_reason = "Card failed during ability activation";
                return;
            }
        }

        if (card.produces.type != .none and card.produces.value > 0) {
            const resource_value = card.produces.value * num_applies;
            resources.add_resource_value(card.produces.type, resource_value);
        }
    }
};
