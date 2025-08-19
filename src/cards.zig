const std = @import("std");
const crypto = @import("crypto.zig");
const util = @import("util.zig");

const String = util.String;

pub const ResourceType = enum {
    none, // 0
    water, // 1
    food, // 2
    stone, // 3
    tool, // 4
    knowledge, // 5
    copper, // 6
    tin, // 7
    bronze, // 8
    iron, // 9
    gold, // 10
    concrete, // 11
    skill, // 12
    mechanical, // 13
    steel, // 14
    navigation, // 15
    gunpowder, // 16
    printing, // 17
    ships, // 18
    exotic_goods, // 19
    culture, // 20
    coal, // 21
    steam, // 22
    transport, // 23
    electricity, // 24
    chemistry, // 25
    oil, // 26
    plastics, // 27
    uranium, // 28
    electronics, // 29
    computers, // 30
    rockets, // 31
    advanced_materials, // 32
    energy, // 33
    bandwidth, // 34
    personalization, // 35
    ai_cores, // 36
    nanotech, // 37
    fusion, // 38

    undefined,

    //noinline
    pub fn from_int(value: u64) ResourceType {
        return @enumFromInt(value);
    }

    //noinline
    pub fn to_int(self: ResourceType) u64 {
        return @intFromEnum(self);
    }
};

pub const CardError = error{
    CardNotFound,
};

pub const ResourceStat = struct {
    type: ResourceType,
    value: u64,
};

pub const Card = struct {
    uuid: u64,
    name: []const u8,
    description: []const u8,
    image: []const u8,
    consumes: ResourceStat,
    produces: ResourceStat,
    max_activations: u64,
    code: ?[]u8,
    perm_code: ?[]u8,

    //noinline
    fn to_json(self: *Card, allocator: std.mem.Allocator) !String {
        var string = String.new(allocator);
        try std.json.stringify(self, .{}, string.data.writer());
        return string;
    }
    //noinline
    pub fn serialize(self: *Card, allocator: std.mem.Allocator) ![]u8 {
        var s = String.new(allocator);

        try s.data.append(0x30);
        try util.bin_write_u64(&s, self.uuid);

        try s.data.append(0x31);
        try util.bin_write_str(&s, self.name);

        try s.data.append(0x32);
        try util.bin_write_str(&s, self.description);

        try s.data.append(0x33);
        try util.bin_write_str(&s, self.image);

        try s.data.append(0x34);
        const consumes_type = self.consumes.type.to_int();
        try util.bin_write_u64(&s, consumes_type);
        try util.bin_write_u64(&s, self.consumes.value);

        try s.data.append(0x35);
        const produces_type = self.produces.type.to_int();
        try util.bin_write_u64(&s, produces_type);
        try util.bin_write_u64(&s, self.produces.value);

        try s.data.append(0x36);
        try util.bin_write_u64(&s, self.max_activations);

        if (self.code != null) {
            try s.data.append(0x37);
            try util.bin_write_str(&s, self.code.?);
        }
        if (self.perm_code != null) {
            try s.data.append(0x38);
            try util.bin_write_str(&s, self.perm_code.?);
        }

        return s.data.items;
    }

    //noinline
    pub fn create(allocator: std.mem.Allocator) !*Card {
        return try allocator.create(Card);
    }

    //noinline
    pub fn deserialize(allocator: std.mem.Allocator, data: []u8) !*Card {
        var card = try Card.create(allocator);

        card.code = null;
        card.perm_code = null;
        card.consumes.type = ResourceType.none;
        card.consumes.value = 0;
        card.produces.type = ResourceType.none;
        card.produces.value = 0;

        var i: usize = 0;
        while (i < data.len) {
            var v = data[i];
            i += 1;
            if (v < 0x30) {
                continue;
            }
            v -= 0x30;

            if (v == 0) {
                card.uuid = try util.bin_read_u64(data, &i);
                continue;
            }
            if (v == 1) {
                const name_slice = try util.bin_read_str(data, &i);
                card.name = try util.clone_slice(allocator, name_slice);
                continue;
            }
            if (v == 2) {
                const description_slice = try util.bin_read_str(data, &i);
                card.description = try util.clone_slice(allocator, description_slice);
                continue;
            }
            if (v == 3) {
                const image_slice = try util.bin_read_str(data, &i);
                card.image = try util.clone_slice(allocator, image_slice);
                continue;
            }
            if (v == 4) {
                var type_value = try util.bin_read_u64(data, &i);
                type_value = type_value & 0x3f;
                card.consumes.type = ResourceType.from_int(type_value);
                card.consumes.value = try util.bin_read_u64(data, &i);
                continue;
            }
            if (v == 5) {
                var type_value = try util.bin_read_u64(data, &i);
                type_value = type_value & 0x3f;
                card.produces.type = ResourceType.from_int(type_value);
                card.produces.value = try util.bin_read_u64(data, &i);
                continue;
            }
            if (v == 6) {
                card.max_activations = try util.bin_read_u64(data, &i);
                continue;
            }
            if (v == 7) {
                const code_slice = try util.bin_read_str(data, &i);
                card.code = try util.clone_slice(allocator, code_slice);
                continue;
            }
            if (v == 8) {
                const perm_code_slice = try util.bin_read_str(data, &i);
                card.perm_code = try util.clone_slice(allocator, perm_code_slice);
                continue;
            }
        }
        return card;
    }
};

pub const CardManager = struct {
    allocator: std.mem.Allocator,
    card_collection: std.ArrayList(*Card),

    //noinline
    pub fn export_card(self: *CardManager, card: *Card) !String {
        const data = try card.serialize(self.allocator);
        var signer = try crypto.Signer.from_data(self.allocator, data);
        defer signer.deinit();
        var sig_data = try signer.sign();
        defer sig_data.deinit();

        var output = String.new(self.allocator);
        const b64_data = try util.base64_encode(self.allocator, data);
        defer util.free_u8_slice(self.allocator, b64_data);
        try output.appendSlice(b64_data);
        try output.appendSlice("|");
        try output.appendSlice(sig_data.data.items);
        return output;
    }

    //noinline
    pub fn import_card(self: *CardManager, data: []u8, verify: bool, allocator: std.mem.Allocator) !*Card {
        const indx_ = util.index_of(data, "|");
        if (indx_ == null) {
            return error.InvalidData;
        }
        const indx = indx_.?;
        const b64_data = data[0..indx];
        const sig_data = data[indx + 1 ..];

        const decoded_data = try util.base64_decode(self.allocator, b64_data);
        defer util.free_u8_slice(self.allocator, decoded_data);

        if (verify) {
            var verifier = try crypto.Verifier.from_data(allocator, decoded_data, sig_data);
            defer verifier.deinit();

            const result = try verifier.verify();
            if (!result) {
                return error.VerificationFailed;
            }
            util.puts_debug("Verification successful");
            return try Card.deserialize(self.allocator, decoded_data);
        } else {
            const data__ = try util.clone_slice(allocator, decoded_data);
            return try Card.deserialize(self.allocator, data__);
        }
    }

    //noinline
    pub fn load_all_base_cards(self: *CardManager) !void {
        var dir = try std.fs.cwd().openDir("data/cards", .{ .iterate = true });
        defer dir.close();

        var files = dir.iterate();
        while (try files.next()) |file| {
            const file_name = file.name;
            const file_path = try dir.openFile(file_name, .{});
            defer file_path.close();

            const file_data = try util.read_all_of_file_in_dir(self.allocator, dir, file_name);
            defer util.free_u8_slice(self.allocator, file_data);

            const card = try Card.deserialize(self.allocator, file_data);

            try self.add_card_to_collection(card);
        }
    }

    //noinline
    pub fn add_card_to_collection(self: *CardManager, card: *Card) !void {
        try self.add_or_replace_card(card);
    }

    //noinline
    pub fn add_card_to_collection_no_replace(self: *CardManager, card: *Card) !void {
        try self.card_collection.append(card);
    }

    //noinline
    pub fn add_or_replace_card(self: *CardManager, card: *Card) !void {
        const uuid = card.uuid;
        for (0..self.card_collection.items.len) |i| {
            const excard = self.card_collection.items[i];
            if (excard.uuid == uuid) {
                self.card_collection.items[i] = card;
                return;
            }
        }
        try self.add_card_to_collection_no_replace(card);
    }

    //noinline
    pub fn get_card_by_uuid(self: *CardManager, uuid: u64) !*Card {
        const card_flags = uuid >> 32;
        const uuid_ = uuid & 0xffffffff;

        if (card_flags != 0 and (card_flags & uuid_) < self.card_collection.items.len) {
            const res = self.card_collection.items[card_flags & (uuid_ - 1)];
            const res_addr = @intFromPtr(res);
            if (res_addr < 0x10000) {
                return error.CardNotFound;
            }
            return res;
        }

        for (self.card_collection.items) |card| {
            if (card.uuid == uuid_) {
                return card;
            }
        }
        return CardError.CardNotFound;
    }

    //noinline
    pub fn get_card_by_name(self: *CardManager, name: []const u8) !*Card {
        for (self.card_collection.items) |card| {
            if (std.mem.eql(u8, card.name, name)) {
                return card;
            }
        }
        return CardError.CardNotFound;
    }
};
