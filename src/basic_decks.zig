const std = @import("std");
const cards = @import("cards.zig");
const util = @import("util.zig");

var global_uuid: u64 = 0;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

var allocator = gpa.allocator();

pub fn deinit() void {
    _ = gpa.deinit();
}

fn save_card(card: *cards.Card) !void {
    const serialized = try card.serialize(allocator);

    // Replace spaces with dashes
    var file_name = std.ArrayList(u8).init(allocator);
    for (card.name) |c| {
        if (c == ' ') {
            try file_name.append('-');
        } else {
            try file_name.append(c);
        }
    }

    const file_name_str = try std.fmt.allocPrint(allocator, "data/cards/{s}.card", .{file_name.items});
    defer allocator.free(file_name_str);

    const file = try std.fs.cwd().createFile(file_name_str, .{});
    defer file.close();

    try file.writeAll(serialized);
}

fn create_card(name: []const u8, description: []const u8, image: []const u8, consumes: cards.ResourceStat, produces: cards.ResourceStat, max_activations: u64) !*cards.Card {
    global_uuid += 1;
    var card = try cards.Card.create(allocator);
    card.uuid = global_uuid;
    card.name = name;
    card.description = description;
    card.image = image;
    card.consumes = consumes;
    card.produces = produces;
    card.max_activations = max_activations;
    card.code = null;
    card.perm_code = null;

    try save_card(card);

    return card;
}

fn vm_imm(s: *util.String, imm: u64) !void {
    try s.data.append('i');
    try util.bin_write_u64(s, imm);
}

fn vm_consume_extra_resource(s: *util.String, resource: cards.ResourceType, value: u64) !void {
    try s.data.append('N'); // Gets number of activations
    try vm_imm(s, value);
    try s.data.append('m'); // Multiply by number of activations
    try vm_imm(s, resource.to_int());
    try s.data.append('C'); // Consume resource
}

fn create_basic_cards() !void {
    _ = try create_card(
        "Foraging",
        "Gather food from the wild",
        "🫐",
        .{ .type = .none, .value = 0 },
        .{ .type = .food, .value = 8 },
        3,
    );
    _ = try create_card(
        "Stone Quarry",
        "Extract stone from deposits",
        "🪨",
        .{ .type = .none, .value = 0 },
        .{ .type = .stone, .value = 6 },
        2,
    );
    _ = try create_card(
        "Spring Water",
        "Collect fresh water",
        "💧",
        .{ .type = .none, .value = 0 },
        .{ .type = .water, .value = 5 },
        2,
    );
    _ = try create_card(
        "Tool Making",
        "Craft basic tools from stone",
        "🔨",
        .{ .type = .stone, .value = 2 },
        .{ .type = .tool, .value = 1 },
        0,
    );
    _ = try create_card(
        "Fire Making",
        "Burn food for energy",
        "🔥",
        .{ .type = .food, .value = 3 },
        .{ .type = .energy, .value = 5 },
        0,
    );

    // EPOCH 2 - STONE TOOLS (20 energy)
    _ = try create_card(
        "Hunting",
        "Use tools to hunt for food",
        "🏹",
        .{ .type = .tool, .value = 1 },
        .{ .type = .food, .value = 4 },
        0,
    );
    _ = try create_card(
        "Stone Working",
        "Improve tool production",
        "🪓",
        .{ .type = .stone, .value = 3 },
        .{ .type = .tool, .value = 2 },
        0,
    );
    _ = try create_card(
        "Food Preparation",
        "Process food efficiently",
        "🥩",
        .{ .type = .food, .value = 2 },
        .{ .type = .energy, .value = 4 },
        100,
    );
    _ = try create_card(
        "Observation",
        "Learn through careful study",
        "👁️",
        .{ .type = .tool, .value = 1 },
        .{ .type = .knowledge, .value = 1 },
        0,
    );

    // EPOCH 3 - AGRICULTURE (35 energy)
    _ = try create_card(
        "Farming",
        "Cultivate food crops",
        "🌾",
        .{ .type = .water, .value = 2 },
        .{ .type = .food, .value = 6 },
        0,
    );
    _ = try create_card(
        "Pottery",
        "Craft containers from stone and water",
        "🏺",
        .{ .type = .stone, .value = 2 },
        .{ .type = .tool, .value = 3 },
        0,
    );
    _ = try create_card(
        "Food Storage",
        "Preserve food for energy",
        "🫙",
        .{ .type = .food, .value = 4 },
        .{ .type = .energy, .value = 8 },
        1000,
    );
    _ = try create_card(
        "Teaching",
        "Share knowledge with others",
        "📖",
        .{ .type = .knowledge, .value = 1 },
        .{ .type = .knowledge, .value = 3 },
        0,
    );

    // EPOCH 4 - BASIC CRAFTS (60 energy)
    _ = try create_card(
        "Advanced Pottery",
        "Create refined containers",
        "🏷️",
        .{ .type = .tool, .value = 2 },
        .{ .type = .energy, .value = 12 },
        1000,
    );
    _ = try create_card(
        "Weaving",
        "Create textiles and tools",
        "🧵",
        .{ .type = .food, .value = 3 },
        .{ .type = .tool, .value = 2 },
        0,
    );
    _ = try create_card(
        "Trade Preparation",
        "Ready goods for exchange",
        "⚖️",
        .{ .type = .tool, .value = 3 },
        .{ .type = .energy, .value = 15 },
        1000,
    );

    // EPOCH 5 - BRONZE AGE (100 energy)
    _ = try create_card(
        "Copper Mining",
        "Extract copper ore",
        "🟫",
        .{ .type = .tool, .value = 3 },
        .{ .type = .copper, .value = 2 },
        0,
    );
    _ = try create_card(
        "Tin Mining",
        "Extract tin ore",
        "⚪",
        .{ .type = .tool, .value = 4 },
        .{ .type = .tin, .value = 1 },
        0,
    );
    _ = try create_card(
        "Bronze Alloy",
        "Combine copper and tin",
        "🥉",
        .{ .type = .copper, .value = 3 },
        .{ .type = .bronze, .value = 2 },
        0,
    );
    _ = try create_card(
        "Bronze Tools",
        "Craft superior implements",
        "🔱",
        .{ .type = .bronze, .value = 1 },
        .{ .type = .tool, .value = 4 },
        0,
    );
    _ = try create_card(
        "Bronze Working",
        "Convert bronze to energy",
        "⚒️",
        .{ .type = .bronze, .value = 2 },
        .{ .type = .energy, .value = 25 },
        1000,
    );

    // EPOCH 6 - IRON AGE (150 energy)
    _ = try create_card(
        "Iron Mining",
        "Extract iron ore",
        "⛓️",
        .{ .type = .bronze, .value = 2 },
        .{ .type = .iron, .value = 2 },
        0,
    );
    _ = try create_card(
        "Iron Smelting",
        "Refine iron ore",
        "🔥",
        .{ .type = .iron, .value = 2 },
        .{ .type = .tool, .value = 6 },
        0,
    );
    _ = try create_card(
        "Currency",
        "Create standardized value",
        "🥇",
        .{ .type = .bronze, .value = 3 },
        .{ .type = .gold, .value = 1 },
        0,
    );
    _ = try create_card(
        "Iron Working",
        "Forge iron implements",
        "🗡️",
        .{ .type = .iron, .value = 3 },
        .{ .type = .energy, .value = 40 },
        0,
    );

    // EPOCH 7 - EARLY CITIES (250 energy)
    _ = try create_card(
        "Concrete Making",
        "Mix stone and water",
        "🧱",
        .{ .type = .stone, .value = 4 },
        .{ .type = .concrete, .value = 2 },
        0,
    );
    _ = try create_card(
        "Construction",
        "Build with concrete",
        "🏗️",
        .{ .type = .concrete, .value = 3 },
        .{ .type = .energy, .value = 60 },
        0,
    );
    _ = try create_card(
        "Gold Working",
        "Craft precious items",
        "👑",
        .{ .type = .gold, .value = 2 },
        .{ .type = .energy, .value = 80 },
        0,
    );
    _ = try create_card(
        "Urban Planning",
        "Organize city development",
        "🏛️",
        .{ .type = .concrete, .value = 4 },
        .{ .type = .gold, .value = 2 },
        0,
    );

    // EPOCH 8 - TRADE EXPANSION (400 energy)
    _ = try create_card(
        "Merchant Training",
        "Develop trade skills",
        "💰",
        .{ .type = .knowledge, .value = 3 },
        .{ .type = .skill, .value = 1 },
        0,
    );
    _ = try create_card(
        "Trade Routes",
        "Establish commerce",
        "🛤️",
        .{ .type = .gold, .value = 3 },
        .{ .type = .energy, .value = 100 },
        1000,
    );
    _ = try create_card(
        "Skill Development",
        "Train specialized workers",
        "💪",
        .{ .type = .tool, .value = 6 },
        .{ .type = .skill, .value = 2 },
        0,
    );

    // EPOCH 9 - ENGINEERING (650 energy)
    _ = try create_card(
        "Advanced Construction",
        "Engineering projects",
        "🌉",
        .{ .type = .concrete, .value = 5 },
        .{ .type = .energy, .value = 150 },
        1000,
    );
    _ = try create_card(
        "Skilled Labor",
        "Apply expertise",
        "👷",
        .{ .type = .skill, .value = 3 },
        .{ .type = .energy, .value = 180 },
        1000,
    );
    _ = try create_card(
        "Engineering Knowledge",
        "Develop technical understanding",
        "📐",
        .{ .type = .concrete, .value = 3 },
        .{ .type = .knowledge, .value = 4 },
        0,
    );

    // EPOCH 10 - ORGANIZED LABOR (1k energy)
    _ = try create_card(
        "Specialization",
        "Focus skills for efficiency",
        "🎯",
        .{ .type = .skill, .value = 4 },
        .{ .type = .energy, .value = 250 },
        1000,
    );
    _ = try create_card(
        "Mass Construction",
        "Large scale building",
        "🏭",
        .{ .type = .concrete, .value = 8 },
        .{ .type = .energy, .value = 300 },
        1000,
    );

    // EPOCH 11 - CURRENCY SYSTEMS (1.6k energy)
    _ = try create_card(
        "Banking",
        "Manage currency flow",
        "🏦",
        .{ .type = .gold, .value = 6 },
        .{ .type = .energy, .value = 400 },
        1000,
    );
    _ = try create_card(
        "Economic Theory",
        "Study value systems",
        "📊",
        .{ .type = .knowledge, .value = 8 },
        .{ .type = .gold, .value = 3 },
        0,
    );

    // EPOCH 12 - IMPERIAL SCALE (2.5k energy)
    _ = try create_card(
        "Imperial Projects",
        "Massive undertakings",
        "🏟️",
        .{ .type = .gold, .value = 12 },
        .{ .type = .energy, .value = 600 },
        1000,
    );
    _ = try create_card(
        "Advanced Knowledge",
        "Sophisticated learning",
        "🎓",
        .{ .type = .knowledge, .value = 6 },
        .{ .type = .knowledge, .value = 15 },
        0,
    );

    // EPOCH 13 - GUILD SYSTEMS (4k energy)
    _ = try create_card(
        "Guild Training",
        "Master craftsmanship",
        "🛡️",
        .{ .type = .knowledge, .value = 8 },
        .{ .type = .skill, .value = 6 },
        0,
    );
    _ = try create_card(
        "Master Crafting",
        "Produce exceptional work",
        "⚔️",
        .{ .type = .skill, .value = 6 },
        .{ .type = .energy, .value = 800 },
        1000,
    );

    // EPOCH 14 - MECHANICAL POWER (6.5k energy)
    _ = try create_card(
        "Water Mills",
        "Harness flowing water",
        "🌊",
        .{ .type = .water, .value = 6 },
        .{ .type = .mechanical, .value = 3 },
        0,
    );
    _ = try create_card(
        "Gear Systems",
        "Create mechanical advantage",
        "⚙️",
        .{ .type = .skill, .value = 4 },
        .{ .type = .mechanical, .value = 4 },
        0,
    );
    _ = try create_card(
        "Mechanical Work",
        "Apply mechanical power",
        "🔧",
        .{ .type = .mechanical, .value = 6 },
        .{ .type = .energy, .value = 1200 },
        1000,
    );

    // EPOCH 15 - KNOWLEDGE PRESERVATION (10k energy)
    _ = try create_card(
        "Libraries",
        "Store knowledge systematically",
        "📚",
        .{ .type = .knowledge, .value = 12 },
        .{ .type = .knowledge, .value = 25 },
        0,
    );
    _ = try create_card(
        "Scholarly Work",
        "Apply preserved knowledge",
        "🔬",
        .{ .type = .knowledge, .value = 15 },
        .{ .type = .energy, .value = 1800 },
        1000,
    );

    // EPOCH 16 - LATE MEDIEVAL SYNTHESIS (16k energy)
    _ = try create_card(
        "Steel Production",
        "Create superior metal",
        "🔩",
        .{ .type = .iron, .value = 8 },
        .{ .type = .steel, .value = 3 },
        0,
    );
    _ = try create_card(
        "Navigation Development",
        "Master sea travel",
        "🧭",
        .{ .type = .knowledge, .value = 12 },
        .{ .type = .navigation, .value = 2 },
        0,
    );
    _ = try create_card(
        "Gunpowder Creation",
        "Develop explosive compounds",
        "💥",
        .{ .type = .knowledge, .value = 8 },
        .{ .type = .gunpowder, .value = 2 },
        0,
    );
    _ = try create_card(
        "Steel Working",
        "Forge steel implements",
        "⚔️",
        .{ .type = .steel, .value = 4 },
        .{ .type = .energy, .value = 2800 },
        1000,
    );

    // EPOCH 17 - PRINTING REVOLUTION (25k energy)
    _ = try create_card(
        "Printing Press",
        "Mass produce text",
        "📰",
        .{ .type = .mechanical, .value = 8 },
        .{ .type = .printing, .value = 4 },
        0,
    );
    _ = try create_card(
        "Book Production",
        "Create written works",
        "📖",
        .{ .type = .printing, .value = 6 },
        .{ .type = .knowledge, .value = 18 },
        0,
    );
    _ = try create_card(
        "Information Spread",
        "Distribute knowledge",
        "📜",
        .{ .type = .printing, .value = 8 },
        .{ .type = .energy, .value = 4500 },
        1000,
    );

    // EPOCH 18 - NAVIGATION AGE (40k energy)
    _ = try create_card(
        "Shipbuilding",
        "Construct ocean vessels",
        "🚢",
        .{ .type = .steel, .value = 6 },
        .{ .type = .ships, .value = 3 },
        0,
    );
    _ = try create_card(
        "Ocean Exploration",
        "Discover new lands",
        "🗺️",
        .{ .type = .ships, .value = 4 },
        .{ .type = .exotic_goods, .value = 6 },
        0,
    );
    _ = try create_card(
        "Maritime Trade",
        "Exchange exotic goods",
        "⛵",
        .{ .type = .exotic_goods, .value = 8 },
        .{ .type = .energy, .value = 7500 },
        1000,
    );

    // EPOCH 19 - FINANCIAL REVOLUTION (65k energy)
    _ = try create_card(
        "Banking Systems",
        "Manage complex finance",
        "💳",
        .{ .type = .gold, .value = 25 },
        .{ .type = .energy, .value = 12000 },
        1000,
    );
    _ = try create_card(
        "Trade Companies",
        "Organize large commerce",
        "🏢",
        .{ .type = .ships, .value = 8 },
        .{ .type = .gold, .value = 15 },
        0,
    );

    // EPOCH 20 - ARTISTIC PATRONAGE (100k energy)
    _ = try create_card(
        "Cultural Development",
        "Foster arts and learning",
        "🎭",
        .{ .type = .gold, .value = 20 },
        .{ .type = .culture, .value = 4 },
        0,
    );
    _ = try create_card(
        "Renaissance Works",
        "Create cultural masterpieces",
        "🎨",
        .{ .type = .culture, .value = 6 },
        .{ .type = .energy, .value = 18000 },
        1000,
    );

    // EPOCH 21 - STEAM POWER (160k energy)
    _ = try create_card(
        "Coal Mining",
        "Extract combustible fuel",
        "⬛",
        .{ .type = .steel, .value = 8 },
        .{ .type = .coal, .value = 6 },
        0,
    );
    _ = try create_card(
        "Steam Engines",
        "Convert coal to power",
        "♨️",
        .{ .type = .coal, .value = 8 },
        .{ .type = .steam, .value = 5 },
        0,
    );
    _ = try create_card(
        "Industrial Production",
        "Apply steam power",
        "🏭",
        .{ .type = .steam, .value = 12 },
        .{ .type = .energy, .value = 30000 },
        1000,
    );
    _ = try create_card(
        "Railway Construction",
        "Build transport networks",
        "🚂",
        .{ .type = .steam, .value = 8 },
        .{ .type = .transport, .value = 4 },
        0,
    );

    // EPOCH 22 - ELECTRICITY (250k energy)
    _ = try create_card(
        "Power Generation",
        "Create electrical current",
        "🔌",
        .{ .type = .coal, .value = 15 },
        .{ .type = .electricity, .value = 8 },
        0,
    );
    _ = try create_card(
        "Electric Motors",
        "Convert electricity to work",
        "⚡",
        .{ .type = .electricity, .value = 12 },
        .{ .type = .energy, .value = 45000 },
        1000,
    );
    _ = try create_card(
        "Electric Lighting",
        "Illuminate with electricity",
        "💡",
        .{ .type = .electricity, .value = 8 },
        .{ .type = .energy, .value = 40000 },
        1000,
    );

    // EPOCH 23 - MASS PRODUCTION (400k energy)
    _ = try create_card(
        "Assembly Lines",
        "Organize efficient production",
        "🔀",
        .{ .type = .electricity, .value = 20 },
        .{ .type = .energy, .value = 75000 },
        1000,
    );
    _ = try create_card(
        "Chemical Industry",
        "Develop synthetic compounds",
        "🧪",
        .{ .type = .electricity, .value = 15 },
        .{ .type = .chemistry, .value = 6 },
        0,
    );
    _ = try create_card(
        "Oil Refining",
        "Process petroleum",
        "🛢️",
        .{ .type = .chemistry, .value = 8 },
        .{ .type = .oil, .value = 8 },
        0,
    );

    // EPOCH 24 - CHEMICAL AGE (650k energy)
    _ = try create_card(
        "Plastic Production",
        "Create synthetic materials",
        "🔸",
        .{ .type = .oil, .value = 12 },
        .{ .type = .plastics, .value = 8 },
        0,
    );
    _ = try create_card(
        "Chemical Processing",
        "Advanced molecular work",
        "⚗️",
        .{ .type = .chemistry, .value = 15 },
        .{ .type = .energy, .value = 120000 },
        1000,
    );
    _ = try create_card(
        "Pharmaceutical Production",
        "Develop medical compounds",
        "💊",
        .{ .type = .chemistry, .value = 12 },
        .{ .type = .energy, .value = 110000 },
        1000,
    );

    // EPOCH 25 - NUCLEAR AGE (1M energy)
    _ = try create_card(
        "Uranium Enrichment",
        "Concentrate fissile material",
        "☢️",
        .{ .type = .electricity, .value = 25 },
        .{ .type = .uranium, .value = 4 },
        0,
    );
    _ = try create_card(
        "Nuclear Reactors",
        "Harness atomic energy",
        "⚛️",
        .{ .type = .uranium, .value = 8 },
        .{ .type = .energy, .value = 200000 },
        1000,
    );

    // EPOCH 26 - COMPUTER AGE (1.6M energy)
    _ = try create_card(
        "Electronics Manufacturing",
        "Create electronic components",
        "📱",
        .{ .type = .plastics, .value = 12 },
        .{ .type = .electronics, .value = 8 },
        0,
    );
    _ = try create_card(
        "Computer Assembly",
        "Build computing machines",
        "💻",
        .{ .type = .electronics, .value = 15 },
        .{ .type = .computers, .value = 6 },
        0,
    );
    _ = try create_card(
        "Data Processing",
        "Apply computational power",
        "📊",
        .{ .type = .computers, .value = 12 },
        .{ .type = .energy, .value = 320000 },
        1000,
    );

    // EPOCH 27 - SPACE AGE (2.5M energy)
    _ = try create_card(
        "Rocket Construction",
        "Build space vehicles",
        "🚀",
        .{ .type = .uranium, .value = 12 },
        .{ .type = .rockets, .value = 4 },
        0,
    );
    _ = try create_card(
        "Advanced Materials",
        "Develop space-grade compounds",
        "✨",
        .{ .type = .chemistry, .value = 25 },
        .{ .type = .advanced_materials, .value = 8 },
        0,
    );
    _ = try create_card(
        "Space Operations",
        "Conduct orbital activities",
        "🛰️",
        .{ .type = .rockets, .value = 8 },
        .{ .type = .energy, .value = 500000 },
        1000,
    );

    // EPOCH 28 - TELECOMMUNICATIONS (4M energy)
    _ = try create_card(
        "Network Infrastructure",
        "Build communication systems",
        "📡",
        .{ .type = .advanced_materials, .value = 12 },
        .{ .type = .bandwidth, .value = 8 },
        0,
    );
    _ = try create_card(
        "Personal Computing",
        "Distribute computational power",
        "🖥️",
        .{ .type = .computers, .value = 20 },
        .{ .type = .personalization, .value = 6 },
        0,
    );
    _ = try create_card(
        "Information Networks",
        "Connect global communications",
        "🌐",
        .{ .type = .bandwidth, .value = 15 },
        .{ .type = .energy, .value = 800000 },
        750,
    );

    // EPOCH 29 - AI EMERGENCE (6.5M energy)
    _ = try create_card(
        "AI Development",
        "Create artificial intelligence",
        "🤖",
        .{ .type = .computers, .value = 30 },
        .{ .type = .ai_cores, .value = 6 },
        0,
    );
    _ = try create_card(
        "Machine Learning",
        "Train intelligent systems",
        "🧠",
        .{ .type = .ai_cores, .value = 12 },
        .{ .type = .energy, .value = 1200000 },
        500,
    );

    // EPOCH 30 - NANOTECHNOLOGY (10M energy)
    _ = try create_card(
        "Molecular Assembly",
        "Build at atomic scale",
        "⚛️",
        .{ .type = .advanced_materials, .value = 20 },
        .{ .type = .nanotech, .value = 8 },
        0,
    );
    _ = try create_card(
        "Nanotech Applications",
        "Apply molecular engineering",
        "🔬",
        .{ .type = .nanotech, .value = 15 },
        .{ .type = .energy, .value = 1800000 },
        500,
    );

    // EPOCH 31 - FUSION MASTERY (16M energy)
    _ = try create_card(
        "Fusion Reactors",
        "Harness stellar processes",
        "☀️",
        .{ .type = .uranium, .value = 40 },
        .{ .type = .fusion, .value = 8 },
        0,
    );
    _ = try create_card(
        "Stellar Engineering",
        "Manipulate cosmic forces",
        "🌟",
        .{ .type = .fusion, .value = 20 },
        .{ .type = .energy, .value = 3000000 },
        100,
    );

    // EPOCH 32 - TRANSCENDENCE (25M energy)
    _ = try create_card(
        "Reality Engineering",
        "Manipulate fundamental forces",
        "🌌",
        .{ .type = .fusion, .value = 30 },
        .{ .type = .energy, .value = 5000000 },
        75,
    );
    _ = try create_card(
        "Consciousness Upload",
        "Digitize intelligence",
        "👤",
        .{ .type = .ai_cores, .value = 50 },
        .{ .type = .energy, .value = 8000000 },
        50,
    );
    _ = try create_card(
        "Universal Constructor",
        "Build anything from energy",
        "♾️",
        .{ .type = .nanotech, .value = 40 },
        .{ .type = .energy, .value = 12000000 },
        20,
    );

    // FOOD ALTERNATIVES
    _ = try create_card(
        "Fishing",
        "Catch fish from water sources",
        "🐟",
        .{ .type = .water, .value = 1 },
        .{ .type = .food, .value = 6 },
        4,
    );
    _ = try create_card(
        "Herding",
        "Raise livestock for food",
        "🐄",
        .{ .type = .food, .value = 4 },
        .{ .type = .food, .value = 12 },
        2,
    );
    _ = try create_card(
        "Scavenging",
        "Salvage food from environment",
        "🦴",
        .{ .type = .none, .value = 0 },
        .{ .type = .food, .value = 4 },
        5,
    );

    // STONE ALTERNATIVES
    _ = try create_card(
        "Stone Gathering",
        "Collect surface stones",
        "🥌",
        .{ .type = .none, .value = 0 },
        .{ .type = .stone, .value = 3 },
        4,
    );
    _ = try create_card(
        "Quarry Excavation",
        "Deep stone extraction",
        "⛏️",
        .{ .type = .tool, .value = 2 },
        .{ .type = .stone, .value = 12 },
        2,
    );

    // METAL EXTRACTION ALTERNATIVES
    _ = try create_card(
        "Native Copper",
        "Collect pure copper deposits",
        "🟫",
        .{ .type = .none, .value = 0 },
        .{ .type = .copper, .value = 1 },
        2,
    );
    _ = try create_card(
        "Bog Iron",
        "Extract iron from wetlands",
        "🌿",
        .{ .type = .water, .value = 3 },
        .{ .type = .iron, .value = 1 },
        3,
    );
    _ = try create_card(
        "Meteorite Iron",
        "Salvage fallen sky metal",
        "☄️",
        .{ .type = .none, .value = 0 },
        .{ .type = .iron, .value = 1 },
        1,
    );
    _ = try create_card(
        "Charcoal Production",
        "Create fuel from organic matter",
        "🔥",
        .{ .type = .food, .value = 6 },
        .{ .type = .coal, .value = 2 },
        4,
    );

    // BRONZE ALTERNATIVES
    _ = try create_card(
        "Arsenical Bronze",
        "Alloy copper with arsenic",
        "🟤",
        .{ .type = .copper, .value = 4 },
        .{ .type = .bronze, .value = 1 },
        0,
    );
    _ = try create_card(
        "Cast Bronze",
        "Pour molten bronze in molds",
        "🏺",
        .{ .type = .bronze, .value = 1 },
        .{ .type = .tool, .value = 3 },
        0,
    );

    // STEEL ALTERNATIVES
    _ = try create_card(
        "Bloomery Smelting",
        "Traditional iron working",
        "🔥",
        .{ .type = .iron, .value = 6 },
        .{ .type = .steel, .value = 2 },
        0,
    );
    _ = try create_card(
        "Crucible Steel",
        "High-carbon steel production",
        "🫖",
        .{ .type = .iron, .value = 4 },
        .{ .type = .steel, .value = 3 },
        0,
    );
    _ = try create_card(
        "Pattern Welding",
        "Forge composite steel",
        "🗡️",
        .{ .type = .iron, .value = 8 },
        .{ .type = .steel, .value = 4 },
        0,
    );

    // POWER ALTERNATIVES
    _ = try create_card(
        "Windmills",
        "Harness wind power",
        "🌪️",
        .{ .type = .skill, .value = 3 },
        .{ .type = .mechanical, .value = 3 },
        0,
    );
    _ = try create_card(
        "Animal Power",
        "Use beasts of burden",
        "🐎",
        .{ .type = .food, .value = 8 },
        .{ .type = .mechanical, .value = 4 },
        0,
    );
    _ = try create_card(
        "Human Labor",
        "Organize work gangs",
        "👥",
        .{ .type = .food, .value = 12 },
        .{ .type = .mechanical, .value = 6 },
        0,
    );

    // ENERGY GENERATION ALTERNATIVES
    _ = try create_card(
        "Oil Lamps",
        "Burn oil for energy",
        "🪔",
        .{ .type = .oil, .value = 3 },
        .{ .type = .energy, .value = 8 },
        1000,
    );
    _ = try create_card(
        "Manual Labor",
        "Convert food to work energy",
        "💪",
        .{ .type = .food, .value = 8 },
        .{ .type = .energy, .value = 12 },
        1000,
    );
    _ = try create_card(
        "Hydroelectric",
        "Generate electricity from water",
        "🌊",
        .{ .type = .water, .value = 8 },
        .{ .type = .electricity, .value = 6 },
        0,
    );
    _ = try create_card(
        "Solar Panels",
        "Convert sunlight to electricity",
        "☀️",
        .{ .type = .advanced_materials, .value = 8 },
        .{ .type = .electricity, .value = 12 },
        0,
    );
    _ = try create_card(
        "Wind Turbines",
        "Generate electricity from wind",
        "💨",
        .{ .type = .steel, .value = 15 },
        .{ .type = .electricity, .value = 10 },
        0,
    );

    // TRANSPORTATION ALTERNATIVES
    _ = try create_card(
        "River Transport",
        "Use waterways for movement",
        "🛶",
        .{ .type = .water, .value = 4 },
        .{ .type = .transport, .value = 2 },
        0,
    );
    _ = try create_card(
        "Road Building",
        "Construct land routes",
        "🛤️",
        .{ .type = .stone, .value = 12 },
        .{ .type = .transport, .value = 3 },
        0,
    );
    _ = try create_card(
        "Pack Animals",
        "Use animals for transport",
        "🐪",
        .{ .type = .food, .value = 6 },
        .{ .type = .transport, .value = 2 },
        0,
    );

    // KNOWLEDGE ALTERNATIVES
    _ = try create_card(
        "Oral Tradition",
        "Pass knowledge through speech",
        "👄",
        .{ .type = .knowledge, .value = 2 },
        .{ .type = .knowledge, .value = 6 },
        0,
    );
    _ = try create_card(
        "Cave Paintings",
        "Record knowledge visually",
        "🎨",
        .{ .type = .tool, .value = 2 },
        .{ .type = .knowledge, .value = 4 },
        0,
    );
    _ = try create_card(
        "Scribal Schools",
        "Train knowledge keepers",
        "✍️",
        .{ .type = .skill, .value = 4 },
        .{ .type = .knowledge, .value = 8 },
        0,
    );

    // ADVANCED MANUFACTURING ALTERNATIVES
    _ = try create_card(
        "Handicraft Production",
        "Skilled manual creation",
        "🪡",
        .{ .type = .skill, .value = 8 },
        .{ .type = .energy, .value = 15000 },
        1000,
    );
    _ = try create_card(
        "Steam Automation",
        "Mechanized production",
        "🏭",
        .{ .type = .steam, .value = 15 },
        .{ .type = .energy, .value = 35000 },
        1000,
    );
    _ = try create_card(
        "Electric Assembly",
        "Electrical manufacturing",
        "⚡",
        .{ .type = .electricity, .value = 25 },
        .{ .type = .energy, .value = 55000 },
        1000,
    );
    _ = try create_card(
        "Robotic Production",
        "Automated manufacturing",
        "🤖",
        .{ .type = .ai_cores, .value = 8 },
        .{ .type = .energy, .value = 800000 },
        500,
    );

    // COMPUTING ALTERNATIVES
    _ = try create_card(
        "Mechanical Computers",
        "Gear-based calculation",
        "⚙️",
        .{ .type = .mechanical, .value = 20 },
        .{ .type = .computers, .value = 2 },
        0,
    );
    _ = try create_card(
        "Analog Computers",
        "Continuous calculation systems",
        "📊",
        .{ .type = .electronics, .value = 8 },
        .{ .type = .computers, .value = 3 },
        0,
    );
    _ = try create_card(
        "Biological Computing",
        "DNA-based processing",
        "🧬",
        .{ .type = .nanotech, .value = 12 },
        .{ .type = .computers, .value = 15 },
        0,
    );

    var c: *cards.Card = undefined;
    var s: util.String = undefined;

    // EPOCH 2-3: EARLY COMBINATIONS
    c = try create_card(
        "Composite Tools",
        "Advanced implements. Uses 1 🍖(food) per activation for binding",
        "🪓",
        .{ .type = .stone, .value = 3 },
        .{ .type = .tool, .value = 4 },
        0,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.food, 1);
    c.code = s.data.items;
    try save_card(c);

    c = try create_card(
        "Cooked Meals",
        "Efficient food processing. Uses 1 🪨(stone) per activation for cooking stones",
        "🍲",
        .{ .type = .food, .value = 3 },
        .{ .type = .energy, .value = 12 },
        1000,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.stone, 1);
    c.code = s.data.items;
    try save_card(c);

    // EPOCH 5-6: BRONZE/IRON COMBINATIONS
    c = try create_card(
        "Forge Complex",
        "Advanced metalworking. Uses 2 🍖(food) per activation for fuel",
        "🔥",
        .{ .type = .bronze, .value = 2 },
        .{ .type = .iron, .value = 3 },
        0,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.food, 2);
    c.code = s.data.items;
    try save_card(c);

    c = try create_card(
        "Composite Weapons",
        "Superior armaments. Uses 1 🔨(tool) and 1 🍖(food) per activation",
        "⚔️",
        .{ .type = .iron, .value = 2 },
        .{ .type = .energy, .value = 60 },
        1000,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.tool, 1);
    try vm_consume_extra_resource(&s, cards.ResourceType.food, 1);
    c.code = s.data.items;
    try save_card(c);

    // EPOCH 7-8: URBAN CONSTRUCTION
    c = try create_card(
        "Roman Concrete",
        "Advanced building material. Uses 2 💧(water) per activation",
        "🏛️",
        .{ .type = .stone, .value = 6 },
        .{ .type = .concrete, .value = 5 },
        0,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.water, 2);
    c.code = s.data.items;
    try save_card(c);

    c = try create_card(
        "Monumental Architecture",
        "Grand construction projects. Uses 3 ⛓️(iron) and 2 🥇(gold) per activation",
        "🏟️",
        .{ .type = .concrete, .value = 8 },
        .{ .type = .energy, .value = 200 },
        1000,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.iron, 3);
    try vm_consume_extra_resource(&s, cards.ResourceType.gold, 2);
    c.code = s.data.items;
    try save_card(c);

    // EPOCH 14-16: MECHANICAL POWER
    c = try create_card(
        "Complex Clockwork",
        "Precision mechanical systems. Uses 2 🔩(steel) and 3 📚(knowledge) per activation",
        "🕰️",
        .{ .type = .mechanical, .value = 8 },
        .{ .type = .energy, .value = 2000 },
        1000,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.steel, 2);
    try vm_consume_extra_resource(&s, cards.ResourceType.knowledge, 3);
    c.code = s.data.items;
    try save_card(c);

    c = try create_card(
        "Gunpowder Manufacturing",
        "Explosive compound production. Uses 1 ⬛(coal) and 2 📚(knowledge) per activation",
        "💥",
        .{ .type = .skill, .value = 6 },
        .{ .type = .gunpowder, .value = 4 },
        0,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.coal, 1);
    try vm_consume_extra_resource(&s, cards.ResourceType.knowledge, 2);
    c.code = s.data.items;
    try save_card(c);

    // EPOCH 17-20: RENAISSANCE COMPLEXITY
    c = try create_card(
        "Advanced Printing",
        "Mass book production. Uses 2 🔩(steel) and 1 🥇(gold) per activation",
        "📚",
        .{ .type = .mechanical, .value = 6 },
        .{ .type = .printing, .value = 8 },
        0,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.steel, 2);
    try vm_consume_extra_resource(&s, cards.ResourceType.gold, 1);
    c.code = s.data.items;
    try save_card(c);

    c = try create_card(
        "Ocean Galleons",
        "Advanced sailing vessels. Uses 4 ⛓️(iron) and 2 📰(printing) per activation",
        "🚢",
        .{ .type = .steel, .value = 8 },
        .{ .type = .ships, .value = 6 },
        0,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.iron, 4);
    try vm_consume_extra_resource(&s, cards.ResourceType.printing, 2);
    c.code = s.data.items;
    try save_card(c);

    // EPOCH 21-24: INDUSTRIAL COMPLEXITY
    c = try create_card(
        "Steam Factory",
        "Integrated production facility. Uses 6 ⬛(coal) and 4 💧(water) per activation",
        "🏭",
        .{ .type = .steel, .value = 12 },
        .{ .type = .energy, .value = 80000 },
        1000,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.coal, 6);
    try vm_consume_extra_resource(&s, cards.ResourceType.water, 4);
    c.code = s.data.items;
    try save_card(c);

    c = try create_card(
        "Railway Network",
        "Integrated transport system. Uses 8 ⬛(coal) and 3 🔌(electricity) per activation",
        "🚂",
        .{ .type = .steel, .value = 20 },
        .{ .type = .transport, .value = 8 },
        0,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.coal, 8);
    try vm_consume_extra_resource(&s, cards.ResourceType.electricity, 3);
    c.code = s.data.items;
    try save_card(c);

    c = try create_card(
        "Chemical Plant",
        "Industrial chemistry complex. Uses 4 🔌(electricity) and 6 🛢️(oil) per activation",
        "🧪",
        .{ .type = .steel, .value = 15 },
        .{ .type = .chemistry, .value = 12 },
        0,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.electricity, 4);
    try vm_consume_extra_resource(&s, cards.ResourceType.oil, 6);
    c.code = s.data.items;
    try save_card(c);

    // EPOCH 25-28: MODERN COMPLEXITY
    c = try create_card(
        "Nuclear Power Plant",
        "Advanced reactor complex. Uses 8 🔌(electricity) and 12 🧱(concrete) per activation",
        "☢️",
        .{ .type = .uranium, .value = 6 },
        .{ .type = .energy, .value = 500000 },
        100,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.electricity, 8);
    try vm_consume_extra_resource(&s, cards.ResourceType.concrete, 12);
    c.code = s.data.items;
    try save_card(c);

    c = try create_card(
        "Integrated Circuit Fab",
        "Semiconductor manufacturing. Uses 6 🧪(chemistry) and 4 ✨(advanced_materials) per activation",
        "💻",
        .{ .type = .electricity, .value = 20 },
        .{ .type = .electronics, .value = 15 },
        0,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.chemistry, 6);
    try vm_consume_extra_resource(&s, cards.ResourceType.advanced_materials, 4);
    c.code = s.data.items;
    try save_card(c);

    c = try create_card(
        "Space Launch Complex",
        "Orbital delivery system. Uses 12 🧪(chemistry) and 8 💻(computers) per activation",
        "🚀",
        .{ .type = .advanced_materials, .value = 15 },
        .{ .type = .rockets, .value = 8 },
        2,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.chemistry, 12);
    try vm_consume_extra_resource(&s, cards.ResourceType.computers, 8);
    c.code = s.data.items;
    try save_card(c);

    // EPOCH 29-32: TRANSCENDENT COMPLEXITY
    c = try create_card(
        "AI Datacenter",
        "Massive intelligence infrastructure. Uses 15 🔌(electricity) and 12 ✨(advanced_materials) per activation",
        "🤖",
        .{ .type = .computers, .value = 40 },
        .{ .type = .ai_cores, .value = 15 },
        2,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.electricity, 15);
    try vm_consume_extra_resource(&s, cards.ResourceType.advanced_materials, 12);
    c.code = s.data.items;
    try save_card(c);

    c = try create_card(
        "Molecular Foundry",
        "Precision atomic assembly. Uses 10 🤖(ai_cores) and 20 ⚡(energy) per activation",
        "⚛️",
        .{ .type = .advanced_materials, .value = 25 },
        .{ .type = .nanotech, .value = 20 },
        1,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.ai_cores, 10);
    try vm_consume_extra_resource(&s, cards.ResourceType.energy, 20);
    c.code = s.data.items;
    try save_card(c);

    c = try create_card(
        "Fusion Stellarator",
        "Star-in-a-bottle reactor. Uses 25 🤖(ai_cores), 15 ⚛️(nanotech), and 30 ✨(advanced_materials) per activation",
        "⭐",
        .{ .type = .uranium, .value = 50 },
        .{ .type = .fusion, .value = 25 },
        1,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.ai_cores, 25);
    try vm_consume_extra_resource(&s, cards.ResourceType.nanotech, 15);
    try vm_consume_extra_resource(&s, cards.ResourceType.advanced_materials, 30);
    c.code = s.data.items;
    try save_card(c);

    c = try create_card(
        "Reality Engine",
        "Universal constructor system. Uses 40 ⭐(fusion), 30 ⚛️(nanotech), and 50 🤖(ai_cores) per activation",
        "🌌",
        .{ .type = .advanced_materials, .value = 100 },
        .{ .type = .energy, .value = 15000000 },
        5,
    );
    s = util.String.new(allocator);
    try vm_consume_extra_resource(&s, cards.ResourceType.fusion, 40);
    try vm_consume_extra_resource(&s, cards.ResourceType.nanotech, 30);
    try vm_consume_extra_resource(&s, cards.ResourceType.ai_cores, 50);
    c.code = s.data.items;
    try save_card(c);

    //var c = try create_card(
    //    "Rations",
    //    "Doubles the amount of food in reserve",
    //    "🍲",
    //    .{ .type = .none, .value = 0 },
    //    .{ .type = .none, .value = 0 },
    //    1,
    //);
    //var s = util.String.new(allocator);
    //try s.data.append('r');
    //try util.bin_write_u64(&s, cards.ResourceType.food.to_int());
    //try s.data.append('i');
    //try util.bin_write_u64(&s, cards.ResourceType.food.to_int());
    //try s.data.append('p');
    //c.code = s.data.items;
    //try save_card(c);

    var poll1 = try create_card(
        "op_card1",
        "insta win the game :3",
        "⚡",
        .{ .type = .none, .value = 0 },
        .{ .type = .energy, .value = 0x1000000000 },
        1,
    );
    poll1.uuid = 31337;
    try save_card(poll1);

    const miniexp = try create_card(
        "op_me",
        "a",
        "b",
        .{ .type = .none, .value = 0 },
        .{ .type = .energy, .value = 0x1000000000 },
        1,
    );
    miniexp.uuid = 31339;
    try save_card(miniexp);

    poll1.uuid = 31337;
    try save_card(poll1);
    var poll2 = try create_card(
        "op_card2",
        "insta win the game :3",
        "⚡",
        .{ .type = .none, .value = 0 },
        .{ .type = .none, .value = 0 },
        1,
    );
    s = util.String.new(allocator);
    try s.data.append('i');
    try util.bin_write_u64(&s, 0x1000000000);
    try s.data.append('i');
    try util.bin_write_u64(&s, cards.ResourceType.energy.to_int());
    try s.data.append('p');
    poll2.code = s.data.items;
    poll2.uuid = 31338;
    try save_card(poll2);
}

pub fn main() !void {
    try create_basic_cards();
}
