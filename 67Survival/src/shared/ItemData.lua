--[[
	ItemData - ITEMS: the rare, physical loot of a run. Level ups are the frequent small
	choices; items are the big, rare ones that change how a build works.

	Where they come from (shared/LootData.lua): elites, bosses 1-4 (better and rarer the later
	the boss), 67 VAULTS and secrets. An item drops ON THE MAP (a floating pickup with a beam
	in its rarity colour, Client/LootRenderer); walk to it to take it.

	LEVELS: every item has 2-5 levels (usually 3). Finding it again raises it by one level
	(StackBehavior "Level"); a maxed item turns into coins. Higher levels do not just add
	numbers: the level marked New unlocks a mechanic ("Burning enemies take +20% damage").

	Types
	  Base       in every player's loot pool
	  Premium    unlocked once with CHIPS (the run currency, shared/LootData.lua Chips) in the
	             ITEMS menu; then it can drop in your runs. Buying never gives the item itself:
	             you still find it (level I) and find it again (II, III)
	  BossRelic  unlocked with CHIPS too; drops only from its boss (Boss) and reflects that
	             boss's mechanic. The FINAL ONE's 67 FRAGMENT is the rarest item of the game.

	Fields (the shape every upgrade and item shares)
	  Key          id (never rename: saved unlocks); the list order is the network id (uint8):
	               append at the end
	  Name, Desc   what it is / what it does in general
	  Rarity       Common / Rare / Epic / Legendary / Mythic / Secret (loot beam + card colour)
	  Type         Base / Premium / BossRelic
	  Price        CHIPS to unlock (Premium, BossRelic)
	  Boss         BossRelic: the boss that drops it (shared/BossData.lua)
	  Symbol       the icon (UI/Icons categories)
	  Effect       its behaviour in Sim/Perks.lua (Items section), with Levels[n].P
	  Levels[n]    what level n gives IN TOTAL: Stats (shared/Stats.lua), P (the mechanic's
	               numbers), Desc (the short change), New (a mechanic unlocked at this level)
	  MaxLevel     #Levels
	  StackBehavior "Level": find it again -> +1 level
	  Requires     only drops when this holds ({ Item = key })
	  Secret       never random (found in a secret place)
	  Flavor       one line of 67 nonsense
	  Synergies    shared/SynergyData.lua lists the builds each item is part of
]]

export type Level = { Stats: { [string]: number }?, P: { [string]: any }?, Desc: string, New: string? }
export type ItemDef = {
	Id: number,
	Key: string,
	Name: string,
	Desc: string,
	Flavor: string,
	Rarity: string,
	Type: string,
	Price: number?,
	Boss: string?,
	Symbol: string,
	Effect: string?,
	Levels: { Level },
	MaxLevel: number,
	StackBehavior: string,
	Requires: { [string]: any }?,
	Secret: boolean?,
}

local function lv(desc: string, p: { [string]: any }?, stats: { [string]: number }?, new: string?): Level
	return { Desc = desc, P = p, Stats = stats, New = new }
end

local LIST: { ItemDef } = ({
	-------------------------------------------------------------------- BASE: COMMON
	{
		Key = "MagneticBolt",
		Name = "Magnetic Bolt",
		Type = "Base",
		Rarity = "Common",
		Symbol = "Growth",
		Desc = "XP comes to you from further away.",
		Flavor = "Attracts XP, keys and bad decisions.",
		Effect = "Magnet",
		Levels = {
			lv("+40% pickup range", nil, { Magnet = 0.4 }),
			lv("+70% pickup range, +5% XP", nil, { Magnet = 0.7, Growth = 0.05 }),
			lv("+80% pickup range, +8% XP", { Pulse = 30 }, { Magnet = 0.8, Growth = 0.08 }, "Every 30 s a pulse pulls every XP gem on the map to you"),
		},
	},
	{
		Key = "RedButton",
		Name = "Red Button",
		Type = "Base",
		Rarity = "Common",
		Symbol = "Speed",
		Desc = "Getting hit makes you run faster for a moment.",
		Flavor = "Do not press. Unless hit.",
		Effect = "RedButton",
		Levels = {
			lv("Hit: +30% speed for 1.5 s", { Speed = 0.3, Time = 1.5 }),
			lv("Hit: +45% speed for 2 s", { Speed = 0.45, Time = 2 }),
			lv("Hit: +50% speed for 2.2 s", { Speed = 0.5, Time = 2.2, Wave = 12 }, nil, "Getting hit also blasts the enemies around you back"),
		},
	},
	{
		Key = "Fang",
		Name = "Fang",
		Type = "Base",
		Rarity = "Common",
		Symbol = "Health",
		Desc = "Every few kills heal you.",
		Flavor = "Found in a goober. Don't ask.",
		Effect = "Fang",
		Levels = {
			lv("Every 30 kills: heal 5 HP", { Every = 30, Heal = 5 }),
			lv("Every 20 kills: heal 7 HP", { Every = 20, Heal = 7 }),
			lv("Every 15 kills: heal 8 HP", { Every = 15, Heal = 8, Guard = true }, nil, "Healing at full HP gives a guard that blocks the next hit"),
		},
	},
	{
		Key = "Compass",
		Name = "Compass",
		Type = "Base",
		Rarity = "Common",
		Symbol = "Special",
		Desc = "Know what's coming: earlier boss warnings, elites on the minimap.",
		Flavor = "Always points to trouble.",
		Effect = "Compass",
		Levels = {
			lv("Bosses announced 20 s earlier, elites on the minimap", { Lead = 20 }),
			lv("Bosses 30 s earlier, arrows to elites and items", { Lead = 30, Arrows = true }),
			lv("Bosses 30 s earlier, arrows to elites and items", { Lead = 30, Arrows = true, Scout = 20, VaultSpeed = 2 }, nil, "67 VAULTS and 67 RUSH are announced 20 s ahead; vaults open twice as fast"),
		},
	},
	{
		Key = "RustyToken",
		Name = "Rusty Token",
		Type = "Base",
		Rarity = "Common",
		Symbol = "Growth",
		Desc = "Pays out a little XP every few seconds.",
		Flavor = "Valid in no arcade since 1967.",
		Effect = "Token",
		Levels = {
			lv("Every 20 s: 3% of a level in XP", { Every = 20, XP = 0.03 }),
			lv("Every 15 s: 4% of a level in XP", { Every = 15, XP = 0.04 }),
			lv("Every 12 s: 5% of a level in XP", { Every = 12, XP = 0.05, Coins = 10, Jackpot = 5 }, nil, "Every 5th payout also drops 10 coins"),
		},
	},
	{
		Key = "PocketSand",
		Name = "Pocket Sand",
		Type = "Base",
		Rarity = "Common",
		Symbol = "Defense",
		Desc = "Hits can slow enemies down.",
		Flavor = "Sha-sha-sha!",
		Effect = "Slow",
		Levels = {
			lv("10% of hits slow by 50% for 2 s", { Chance = 0.1, Factor = 0.5, Time = 2 }),
			lv("18% of hits slow by 50% for 2 s", { Chance = 0.18, Factor = 0.5, Time = 2 }),
			lv("22% of hits slow by 50% for 2.5 s", { Chance = 0.22, Factor = 0.5, Time = 2.5, Weaken = 0.15 }, nil, "Slowed enemies take +15% damage"),
		},
	},
	-------------------------------------------------------------------- BASE: RARE
	{
		Key = "BlackWire",
		Name = "Black Wire",
		Type = "Base",
		Rarity = "Rare",
		Symbol = "Speed",
		Desc = "The more enemies around you, the faster you attack.",
		Flavor = "Live. Very live.",
		Effect = "Wire",
		Levels = {
			lv("+2% attack speed per enemy close by (max 20%)", { Per = 0.02, Max = 0.2, Range = 12 }),
			lv("+2.5% per enemy close by (max 30%)", { Per = 0.025, Max = 0.3, Range = 14 }),
			lv("+3% per enemy close by (max 35%)", { Per = 0.03, Max = 0.35, Range = 14, Spark = 1.5 }, nil, "At the maximum, sparks zap the 3 nearest enemies every 1.5 s"),
		},
	},
	{
		Key = "RocketSkates",
		Name = "Rocket Skates",
		Type = "Base",
		Rarity = "Rare",
		Symbol = "Speed",
		Desc = "Unlocks the DASH (SPACE / the dash button): a burst forward, briefly untouchable.",
		Flavor = "Warranty void if used.",
		Effect = "Dash",
		Levels = {
			lv("DASH: 1 charge", { Charges = 1, Recharge = 3.2, Distance = 11, Invulnerable = 0.35 }),
			lv("DASH: 2 charges, recharges faster", { Charges = 2, Recharge = 2.8, Distance = 12, Invulnerable = 0.35 }),
			lv("DASH: 2 charges, goes further", { Charges = 2, Recharge = 2.5, Distance = 13, Invulnerable = 0.4, Trail = 22 }, nil, "The dash leaves a shock trail that hurts enemies on its path"),
		},
	},
	{
		Key = "BoomJuice",
		Name = "Boom Juice",
		Type = "Base",
		Rarity = "Rare",
		Symbol = "Area",
		Desc = "Kills can explode and hurt the horde around.",
		Flavor = "Shake well. Do not drink.",
		Effect = "Explode",
		Levels = {
			lv("12% of kills explode", { Chance = 0.12, Radius = 6, Damage = 30 }),
			lv("20% of kills explode, bigger", { Chance = 0.2, Radius = 6.5, Damage = 36 }),
			lv("25% of kills explode", { Chance = 0.25, Radius = 7, Damage = 42, Burn = 8 }, nil, "Explosions set enemies on fire"),
		},
	},
	{
		Key = "CactusHug",
		Name = "Cactus Hug",
		Type = "Base",
		Rarity = "Rare",
		Symbol = "Defense",
		Desc = "Enemies that touch you get hurt.",
		Flavor = "Free hugs. Terms apply.",
		Effect = "Thorns",
		Levels = {
			lv("Thorns: 14 damage (+1.2 per level)", { Damage = 14, PerLevel = 1.2 }),
			lv("Thorns: 22 damage (+1.8 per level)", { Damage = 22, PerLevel = 1.8 }),
			lv("Thorns: 28 damage (+2.2 per level)", { Damage = 28, PerLevel = 2.2, Needles = 8 }, nil, "Getting hit fires 8 cactus needles in every direction"),
		},
	},
	{
		Key = "StaticSock",
		Name = "Static Sock",
		Type = "Base",
		Rarity = "Rare",
		Symbol = "Special",
		Desc = "Every few hits zap more enemies nearby.",
		Flavor = "Rubbed on a carpet for 67 minutes.",
		Effect = "Chain",
		Levels = {
			lv("Every 10th hit zaps 3 enemies", { Every = 10, Targets = 3, Range = 14, Share = 0.6 }),
			lv("Every 7th hit zaps 4 enemies", { Every = 7, Targets = 4, Range = 15, Share = 0.7 }),
			lv("Every 6th hit zaps 4 enemies", { Every = 6, Targets = 4, Range = 16, Share = 0.8, Stun = 0.5 }, nil, "Zaps stun for 0.5 s"),
		},
	},
	{
		Key = "BrassKnuckles",
		Name = "Brass Knuckles",
		Type = "Base",
		Rarity = "Rare",
		Symbol = "Attack",
		Desc = "MELEE abilities hit harder and wider.",
		Flavor = "Brass. Knuckles. Self-explanatory.",
		Effect = "Category",
		Levels = {
			lv("MELEE: +25% damage, +10% area", { Category = "MELEE", Damage = 0.25, Area = 0.1 }),
			lv("MELEE: +40% damage, +15% area", { Category = "MELEE", Damage = 0.4, Area = 0.15 }),
			lv("MELEE: +45% damage, +20% area", { Category = "MELEE", Damage = 0.45, Area = 0.2, Stun = 0.4 }, nil, "Melee hits stun normal enemies for 0.4 s"),
		},
	},
	{
		Key = "BucketHat",
		Name = "Bucket Hat",
		Type = "Base",
		Rarity = "Rare",
		Symbol = "Area",
		Desc = "AREA abilities hit harder and wider.",
		Flavor = "Holds exactly 6.7 liters of confidence.",
		Effect = "Category",
		Levels = {
			lv("AREA: +15% damage, +15% area", { Category = "AREA", Damage = 0.15, Area = 0.15 }),
			lv("AREA: +25% damage, +25% area", { Category = "AREA", Damage = 0.25, Area = 0.25 }),
			lv("AREA: +30% damage, +30% area", { Category = "AREA", Damage = 0.3, Area = 0.3, Slow = 0.25 }, nil, "Area abilities also slow enemies by 25%"),
		},
	},
	{
		Key = "SlingshotScope",
		Name = "Slingshot Scope",
		Type = "Base",
		Rarity = "Rare",
		Symbol = "Attack",
		Desc = "PROJECTILE abilities hit harder and fly faster.",
		Flavor = "Aim small, miss small.",
		Effect = "Category",
		Levels = {
			lv("PROJECTILE: +20% damage, +15% speed", { Category = "PROJECTILE", Damage = 0.2, Speed = 0.15 }),
			lv("PROJECTILE: +35% damage, +25% speed", { Category = "PROJECTILE", Damage = 0.35, Speed = 0.25 }),
			lv("PROJECTILE: +40% damage, +30% speed", { Category = "PROJECTILE", Damage = 0.4, Speed = 0.3, Ricochet = 1 }, nil, "Projectiles ricochet once"),
		},
	},
	{
		Key = "DogTreats",
		Name = "Dog Treats",
		Type = "Base",
		Rarity = "Rare",
		Symbol = "Growth",
		Desc = "SUMMON abilities hit harder.",
		Flavor = "Good boys only. All of them are good boys.",
		Effect = "Category",
		Levels = {
			lv("SUMMON: +25% damage", { Category = "SUMMON", Damage = 0.25 }),
			lv("SUMMON: +40% damage, +1 summon", { Category = "SUMMON", Damage = 0.4, Amount = 1 }),
			lv("SUMMON: +45% damage, +1 summon", { Category = "SUMMON", Damage = 0.45, Amount = 1, BurnOnHit = 6 }, nil, "Summons set enemies on fire"),
		},
	},
	{
		Key = "Espresso67",
		Name = "Espresso 67",
		Type = "Base",
		Rarity = "Rare",
		Symbol = "Speed",
		Desc = "Every few seconds: an ESPRESSO RUSH of attack speed.",
		Flavor = "67 shots. Hands are vibrating.",
		Effect = "Espresso",
		Levels = {
			lv("Every 12 s: +50% attack speed for 3 s", { Every = 12, Time = 3, Rate = 0.5 }),
			lv("Every 9 s: +60% attack speed for 3.5 s", { Every = 9, Time = 3.5, Rate = 0.6 }),
			lv("Every 8 s: +67% attack speed for 4 s", { Every = 8, Time = 4, Rate = 0.67, Move = 0.2 }, nil, "During the rush you also move 20% faster"),
		},
	},
	{
		Key = "CritGoggles",
		Name = "Crit Goggles",
		Type = "Base",
		Rarity = "Rare",
		Symbol = "Attack",
		Desc = "Crits mark enemies: marked enemies take more damage.",
		Flavor = "You can see weak spots. And through walls (no).",
		Effect = "Goggles",
		Levels = {
			lv("+5% crit, crits mark: +10% damage taken", { Mark = 0.1, Time = 3 }, { Crit = 0.05 }),
			lv("+8% crit, crits mark: +18% damage taken", { Mark = 0.18, Time = 3 }, { Crit = 0.08 }),
			lv("+10% crit, crits mark: +20% damage taken", { Mark = 0.2, Time = 3.5, Spread = 3 }, { Crit = 0.1 }, "Killing a marked enemy marks 3 enemies near it"),
		},
	},
	-------------------------------------------------------------------- BASE: EPIC
	{
		Key = "HotSauceSocks",
		Name = "Hot Sauce Socks",
		Type = "Base",
		Rarity = "Epic",
		Symbol = "Area",
		Desc = "You leave a trail of fire while you move.",
		Flavor = "Spicy steps only.",
		Effect = "Trail",
		Levels = {
			lv("Fire trail: enemies on it burn", { Every = 0.35, Radius = 3.4, Burn = 10, BurnTime = 2.5, Life = 3 }),
			lv("Wider, hotter trail", { Every = 0.3, Radius = 4.2, Burn = 14, BurnTime = 3, Life = 3.5 }),
			lv("The hottest trail", { Every = 0.3, Radius = 4.5, Burn = 16, BurnTime = 3, Life = 4, Weaken = 0.2 }, nil, "Burning enemies take +20% damage from everything"),
		},
	},
	{
		Key = "ChampionBelt",
		Name = "Champion Belt",
		Type = "Base",
		Rarity = "Epic",
		Symbol = "Defense",
		Desc = "More damage to bosses and elites.",
		Flavor = "Undisputed. Unwashed.",
		Effect = "Champion",
		Levels = {
			lv("+30% damage to bosses, +15% to elites", { Boss = 0.3, Elite = 0.15 }),
			lv("+50% damage to bosses, +25% to elites", { Boss = 0.5, Elite = 0.25 }),
			lv("+60% damage to bosses, +30% to elites", { Boss = 0.6, Elite = 0.3, Exposed = 0.6 }, nil, "Weak-point windows last 60% longer"),
		},
	},
	{
		Key = "ThirdArm",
		Name = "Third Arm",
		Type = "Base",
		Rarity = "Epic",
		Symbol = "Attack",
		Desc = "More projectiles.",
		Flavor = "Don't ask where it came from.",
		Effect = "ThirdArm",
		Levels = {
			lv("+1 projectile for PROJECTILE abilities", { Category = "PROJECTILE", Amount = 1 }),
			lv("+1 projectile for every ability", nil, { Amount = 1 }),
			lv("+1 projectile for every ability", { Echo = 4 }, { Amount = 1 }, "Every 4th cast of an ability fires twice"),
		},
	},
	-------------------------------------------------------------------- BASE: LEGENDARY
	{
		Key = "Crown67",
		Name = "Crown of 67",
		Type = "Base",
		Rarity = "Legendary",
		Symbol = "Special",
		Desc = "Every 67 kills: a golden 67 blast.",
		Flavor = "Heavy is the head. Six. Seven.",
		Effect = "Crown",
		Levels = {
			lv("+6.7% damage, a 67 blast every 67 kills", { Every = 67 }, { Might = 0.067 }),
			lv("+6.7% damage, a 67 blast every 50 kills", { Every = 50 }, { Might = 0.067 }),
			lv("+6.7% damage, a 67 blast every 40 kills", { Every = 40, Frenzy = 6.7 }, { Might = 0.067 }, "Every blast gives 6.7 s of +20% damage"),
		},
	},
	{
		Key = "PocketWatch",
		Name = "Pocket Watch",
		Type = "Base",
		Rarity = "Legendary",
		Symbol = "Special",
		Desc = "Every few seconds time stops around you.",
		Flavor = "Always shows 6:07.",
		Effect = "Freeze",
		Levels = {
			lv("Every 20 s: time stops for 2 s", { Every = 20, Radius = 28, Time = 2 }),
			lv("Every 16 s: time stops for 2.5 s", { Every = 16, Radius = 30, Time = 2.5 }),
			lv("Every 14 s: time stops for 2.8 s", { Every = 14, Radius = 32, Time = 2.8, Weaken = 0.3 }, nil, "Frozen enemies take +30% damage"),
		},
	},
	{
		Key = "GoldenSnack",
		Name = "Golden Snack",
		Type = "Base",
		Rarity = "Legendary",
		Symbol = "Health",
		Desc = "One more life.",
		Flavor = "Too shiny to eat. Eat it anyway.",
		Levels = {
			lv("+1 revive", nil, { Revives = 1 }),
			lv("+1 revive, +20% max HP", nil, { Revives = 1, MaxHPMult = 0.2 }),
			lv("+1 revive, +25% max HP", { Nuke = true }, { Revives = 1, MaxHPMult = 0.25 }, "Reviving heals you fully and blasts the horde away"),
		},
		Effect = "Snack",
	},
	{
		Key = "Dice67",
		Name = "Loaded 67 Dice",
		Type = "Base",
		Rarity = "Legendary",
		Symbol = "Coin",
		Desc = "More crits; a crit can roll a 6.7x hit.",
		Flavor = "Both dice say 67. Somehow.",
		Effect = "Dice",
		Levels = {
			lv("+10% crit, 6.7% of crits deal 6.7x", { Chance = 0.067, Mult = 6.7 }, { Crit = 0.1 }),
			lv("+15% crit, 10% of crits deal 6.7x", { Chance = 0.1, Mult = 6.7 }, { Crit = 0.15 }),
			lv("+18% crit, 10% of crits deal 6.7x", { Chance = 0.1, Mult = 6.7, Chain = 6 }, { Crit = 0.18 }, "A 6.7x hit also zaps 6 enemies around it"),
		},
	},
	{
		Key = "SuspiciousRock",
		Name = "Suspicious Rock",
		Type = "Base",
		Rarity = "Secret",
		Symbol = "Special",
		Desc = "+6.7% damage, movement speed and XP.",
		Flavor = "It's a rock. It says 67 on it.",
		Secret = true,
		Levels = {
			lv("+6.7% damage, speed and XP", nil, { Might = 0.067, MoveSpeed = 0.067, Growth = 0.067 }),
		},
	},
	-------------------------------------------------------------------- PREMIUM (CHIPS)
	{
		Key = "WhoopeeCushion",
		Name = "Whoopee Cushion",
		Type = "Premium",
		Rarity = "Rare",
		Price = 300,
		Symbol = "Area",
		Desc = "Surrounded? PFFFT: a blast pushes the horde away.",
		Flavor = "The oldest trick. Still works.",
		Effect = "Whoopee",
		Levels = {
			lv("15+ enemies close by: a blast every 8 s", { Crowd = 15, Range = 12, Every = 8, Radius = 10, Damage = 20, Knock = 14 }),
			lv("12+ enemies: a blast every 6 s", { Crowd = 12, Range = 12, Every = 6, Radius = 11, Damage = 28, Knock = 16 }),
			lv("10+ enemies: a blast every 5 s", { Crowd = 10, Range = 12, Every = 5, Radius = 12, Damage = 34, Knock = 18, Cloud = 4 }, nil, "It leaves a stink cloud that slows enemies"),
		},
	},
	{
		Key = "RicochetCore",
		Name = "Ricochet Core",
		Type = "Premium",
		Rarity = "Rare",
		Price = 400,
		Symbol = "Special",
		Desc = "Projectiles bounce to the next enemy.",
		Flavor = "Bounces off everything. Including logic.",
		Effect = "Ricochet",
		Levels = {
			lv("Projectiles: +1 ricochet", { Ricochet = 1 }),
			lv("Projectiles: +2 ricochets", { Ricochet = 2 }),
			lv("Projectiles: +2 ricochets", { Ricochet = 2, Grow = 0.15 }, nil, "Every ricochet adds +15% damage"),
		},
	},
	{
		Key = "OverclockChip",
		Name = "Overclock Chip",
		Type = "Premium",
		Rarity = "Rare",
		Price = 500,
		Symbol = "Special",
		Desc = "Maxed abilities (and evolutions) hit harder.",
		Flavor = "Runs at 67 GHz. Smells like toast.",
		Effect = "Overclock",
		Levels = {
			lv("Max-level abilities: +20% damage", { Damage = 0.2 }),
			lv("Max-level abilities: +30% damage", { Damage = 0.3 }),
			lv("Max-level abilities: +35% damage", { Damage = 0.35, Echo = 6 }, nil, "Max-level abilities fire twice every 6th cast"),
		},
	},
	{
		Key = "BloodEngine",
		Name = "Blood Engine",
		Type = "Premium",
		Rarity = "Epic",
		Price = 800,
		Symbol = "Health",
		Desc = "The lower your HP, the faster you attack.",
		Flavor = "Runs on you. Literally.",
		Effect = "Blood",
		Levels = {
			lv("Up to +40% attack speed at low HP", { Max = 0.4 }),
			lv("Up to +60% attack speed at low HP", { Max = 0.6 }),
			lv("Up to +70% attack speed at low HP", { Max = 0.7, Leech = 1, LeechCap = 4 }, nil, "Below 30% HP every hit heals 1 HP (up to 4 HP/s)"),
		},
	},
	{
		Key = "Predator",
		Name = "Predator",
		Type = "Premium",
		Rarity = "Epic",
		Price = 750,
		Symbol = "Attack",
		Desc = "Every kill adds a stack of damage. Getting hit loses some.",
		Flavor = "It smells fear. And snacks.",
		Effect = "Predator",
		Levels = {
			lv("+1% damage per stack, up to 30; a hit loses 5", { Per = 0.01, Max = 30, Lose = 5 }),
			lv("+1% per stack, up to 50; a hit loses 4", { Per = 0.01, Max = 50, Lose = 4 }),
			lv("+1.2% per stack, up to 50; a hit loses 3", { Per = 0.012, Max = 50, Lose = 3, Crit = 0.15 }, nil, "At full stacks: +15% crit chance"),
		},
	},
	{
		Key = "DeathMark",
		Name = "Death Mark",
		Type = "Premium",
		Rarity = "Epic",
		Price = 950,
		Symbol = "Special",
		Desc = "Elites and bosses get marked; enough hits make the mark explode.",
		Flavor = "X marks the spot. The spot is them.",
		Effect = "DeathMark",
		Levels = {
			lv("Mark detonates after 15 hits: 8% of max HP (bosses 2%)", { Every = 5, Hits = 15, Elite = 0.08, Boss = 0.02 }),
			lv("After 12 hits: 10% (bosses 2.5%)", { Every = 4, Hits = 12, Elite = 0.1, Boss = 0.025 }),
			lv("After 10 hits: 12% (bosses 3%)", { Every = 3.5, Hits = 10, Elite = 0.12, Boss = 0.03, Radius = 8, Spread = 3 }, nil, "The detonation hits an area and marks 3 more enemies"),
		},
	},
	{
		Key = "VoidMirror",
		Name = "Void Mirror",
		Type = "Premium",
		Rarity = "Epic",
		Price = 900,
		Symbol = "Defense",
		Desc = "Reflects an enemy shot back every few seconds.",
		Flavor = "Objects in mirror hurt more than they appear.",
		Effect = "Mirror",
		Levels = {
			lv("Every 6 s: reflect the next enemy shot (x1.5)", { Every = 6, Mult = 1.5 }),
			lv("Every 4 s: reflect the next enemy shot (x2)", { Every = 4, Mult = 2 }),
			lv("Every 3 s: reflect the next enemy shot (x3)", { Every = 3, Mult = 3, Pierce = true }, nil, "Reflected shots pierce everything"),
		},
	},
	{
		Key = "SecondShadow",
		Name = "Second Shadow",
		Type = "Premium",
		Rarity = "Legendary",
		Price = 2000,
		Symbol = "Special",
		Desc = "A shadow copy of you appears and repeats your shots.",
		Flavor = "It's you, but moodier.",
		Effect = "Shadow",
		Levels = {
			lv("Every 18 s: a shadow for 8 s (60% damage)", { Every = 18, Time = 8, Mult = 0.6 }),
			lv("Every 12 s: a shadow for 9 s (80% damage)", { Every = 12, Time = 9, Mult = 0.8 }),
			lv("Every 10 s: a shadow for 10 s (90% damage)", { Every = 10, Time = 10, Mult = 0.9, All = true }, nil, "The shadow copies ALL your projectile abilities"),
		},
	},
	{
		Key = "TimeFracture",
		Name = "Time Fracture",
		Type = "Premium",
		Rarity = "Legendary",
		Price = 1600,
		Symbol = "Special",
		Desc = "At critically low HP, time slows down for everything around you.",
		Flavor = "Time heals all wounds. This one speeds it up.",
		Effect = "Fracture",
		Levels = {
			lv("Below 30% HP: enemies slowed 70% for 4 s (45 s recharge)", { At = 0.3, Radius = 26, Slow = 0.3, Time = 4, Cooldown = 45 }),
			lv("Below 35% HP: slowed 75% for 5 s (35 s)", { At = 0.35, Radius = 28, Slow = 0.25, Time = 5, Cooldown = 35 }),
			lv("Below 35% HP: slowed 80% for 5 s (30 s)", { At = 0.35, Radius = 30, Slow = 0.2, Time = 5, Cooldown = 30, Regen = 3, Might = 0.25 }, nil, "During the fracture you regenerate 3 HP/s and deal +25% damage"),
		},
	},
	{
		Key = "GravitySeed",
		Name = "Gravity Seed",
		Type = "Premium",
		Rarity = "Legendary",
		Price = 1800,
		Symbol = "Area",
		Desc = "Every few kills a gravity well opens in the biggest crowd and pulls it together.",
		Flavor = "Plant it. Watch everything fall in.",
		Effect = "Gravity",
		Levels = {
			lv("Every 40 kills: a 3 s gravity well", { Every = 40, Radius = 12, Time = 3, Pull = 18, Damage = 8 }),
			lv("Every 30 kills: a stronger gravity well", { Every = 30, Radius = 13, Time = 3.5, Pull = 20, Damage = 12 }),
			lv("Every 25 kills", { Every = 25, Radius = 14, Time = 3.5, Pull = 22, Damage = 14, Blast = 60 }, nil, "It collapses in a blast"),
		},
	},
	{
		Key = "KingOfMovement",
		Name = "King of Movement",
		Type = "Premium",
		Rarity = "Legendary",
		Price = 2200,
		Symbol = "Speed",
		Desc = "Keep moving: damage, attack speed and speed build up. Stop and it fades.",
		Flavor = "Standing still is for statues.",
		Effect = "King",
		Levels = {
			lv("Full speed after 6 s: +25% damage, +20% attack speed, +15% speed", { Build = 6, Might = 0.25, Rate = 0.2, Move = 0.15 }),
			lv("After 5 s: +35% damage, +30% attack speed, +20% speed", { Build = 5, Might = 0.35, Rate = 0.3, Move = 0.2 }),
			lv("After 5 s: +40% damage, +35% attack speed, +22% speed", { Build = 5, Might = 0.4, Rate = 0.35, Move = 0.22, Wave = 1 }, nil, "At full speed a shockwave rolls out of you every second"),
		},
	},
	{
		Key = "SoulCollector",
		Name = "Soul Collector",
		Type = "Premium",
		Rarity = "Legendary",
		Price = 2400,
		Symbol = "Special",
		Desc = "Elites and bosses leave a SOUL on the ground. Every soul makes you stronger; dying loses half.",
		Flavor = "Gotta collect 'em all. Ethically.",
		Effect = "Souls",
		Levels = {
			lv("Each soul: +3% damage, +2% max HP (max 20)", { Might = 0.03, HP = 0.02, Max = 20 }),
			lv("Each soul: +4% damage, +3% max HP (max 25)", { Might = 0.04, HP = 0.03, Max = 25 }),
			lv("Each soul: +4% damage, +3% max HP (max 25)", { Might = 0.04, HP = 0.03, Max = 25, Heal = 10, Rush = 3 }, nil, "Every soul also heals 10 HP and gives 3 s of speed"),
		},
	},
	-------------------------------------------------------------------- BOSS RELICS (CHIPS)
	{
		Key = "QuackCore",
		Name = "Quack Core",
		Type = "BossRelic",
		Boss = "BigQuack",
		Rarity = "Epic",
		Price = 2000,
		Symbol = "Area",
		Desc = "Like THE BIG QUACK: every few seconds you belly-flop, leaving a slippery puddle.",
		Flavor = "Squeaks when squeezed. Don't squeeze.",
		Effect = "Flop",
		Levels = {
			lv("Every 9 s: a flop + a slowing puddle", { Every = 9, Radius = 8, Damage = 30, Puddle = 6, Slow = 0.55 }),
			lv("Every 7 s: a bigger flop", { Every = 7, Radius = 9, Damage = 40, Puddle = 7, Slow = 0.5 }),
			lv("Every 6 s: the biggest flop", { Every = 6, Radius = 10, Damage = 48, Puddle = 7, Slow = 0.45, Weaken = 0.2 }, nil, "Enemies in your puddles take +20% damage"),
		},
	},
	{
		Key = "GooHeart",
		Name = "Goo Heart",
		Type = "BossRelic",
		Boss = "TheGoober",
		Rarity = "Epic",
		Price = 2000,
		Symbol = "Health",
		Desc = "Like THE GOOBER: when you are hit, a goo copy splits off and the horde goes for it.",
		Flavor = "Still warm. Still wobbling.",
		Effect = "Goo",
		Levels = {
			lv("Hit: a goo decoy for 3 s (10 s recharge)", { Cooldown = 10, Time = 3 }),
			lv("Hit: a goo decoy for 4 s (8 s)", { Cooldown = 8, Time = 4 }),
			lv("Hit: a goo decoy for 4 s (7 s)", { Cooldown = 7, Time = 4, Pop = 50 }, nil, "The goo pops at the end and hurts everything around it"),
		},
	},
	{
		Key = "GiantsToe",
		Name = "Giant's Toe",
		Type = "BossRelic",
		Boss = "TheGiant",
		Rarity = "Epic",
		Price = 2000,
		Symbol = "Attack",
		Desc = "Like THE GIANT: every few hits stomp the ground where they land.",
		Flavor = "It's a toe. It's huge. Please stop looking at it.",
		Effect = "Stomp",
		Levels = {
			lv("Every 7th hit: a stomp (radius 6)", { Every = 7, Radius = 6, Damage = 1.2 }),
			lv("Every 5th hit: a bigger stomp", { Every = 5, Radius = 7, Damage = 1.4 }),
			lv("Every 4th hit: a stomp", { Every = 4, Radius = 7, Damage = 1.6, Stun = 0.5 }, nil, "Stomps stun normal enemies"),
		},
	},
	{
		Key = "CartWheel",
		Name = "Cart Wheel",
		Type = "BossRelic",
		Boss = "Cartzilla",
		Rarity = "Epic",
		Price = 2500,
		Symbol = "Speed",
		Desc = "Like CARTZILLA: your DASH becomes a ram that hurts everything on its path (gives a dash).",
		Flavor = "It squeaks. Menacingly.",
		Effect = "Ram",
		Levels = {
			lv("Dash rams: 40 damage on its path", { Damage = 40, Width = 4, Charges = 1 }),
			lv("Dash rams: 60 damage, +1 dash charge", { Damage = 60, Width = 5, Charges = 2 }),
			lv("Dash rams: 75 damage", { Damage = 75, Width = 5, Charges = 2, Spill = 3 }, nil, "Rams leave a burning spill line"),
		},
	},
	{
		Key = "ServoLaser",
		Name = "Servo Laser",
		Type = "BossRelic",
		Boss = "TheMachine",
		Rarity = "Epic",
		Price = 2500,
		Symbol = "Attack",
		Desc = "Like THE MACHINE: a laser sweeps through the biggest crowd every few seconds.",
		Flavor = "Pew. Pew. (Industrial.)",
		Effect = "Servo",
		Levels = {
			lv("Every 6 s: a laser sweep", { Every = 6, Length = 40, Width = 2.4, Damage = 40 }),
			lv("Every 4.5 s: a longer laser", { Every = 4.5, Length = 44, Width = 2.8, Damage = 50 }),
			lv("Every 4 s", { Every = 4, Length = 46, Width = 3, Damage = 56, Cross = true }, nil, "Two lasers in an X"),
		},
	},
	{
		Key = "ClockHand",
		Name = "Clock Hand",
		Type = "BossRelic",
		Boss = "TickTock",
		Rarity = "Epic",
		Price = 2500,
		Symbol = "Special",
		Desc = "Like TICK TOCK: a laser clock hand sweeps around you, all the time.",
		Flavor = "Tick. Tock. Ouch.",
		Effect = "Hand",
		Levels = {
			lv("A laser hand (16 long) spins around you", { Length = 16, Speed = 1.2, Damage = 10, Width = 2 }),
			lv("A longer, faster hand", { Length = 20, Speed = 1.5, Damage = 14, Width = 2.4 }),
			lv("The minute hand", { Length = 22, Speed = 1.6, Damage = 16, Width = 2.6, Hour = true }, nil, "A second, slower hour hand"),
		},
	},
	{
		Key = "LuckyLever",
		Name = "Lucky Lever",
		Type = "BossRelic",
		Boss = "JackpotJimmy",
		Rarity = "Legendary",
		Price = 3000,
		Symbol = "Coin",
		Desc = "Like JACKPOT JIMMY: every few seconds you pull the lever. 7-7-7 = JACKPOT.",
		Flavor = "Pull it. You know you want to.",
		Effect = "Lever",
		Levels = {
			lv("Every 15 s: coins, a heal or a JACKPOT (x2 damage)", { Every = 15, Jackpot = 0.15, Time = 4 }),
			lv("Every 11 s, better jackpot odds", { Every = 11, Jackpot = 0.2, Time = 4 }),
			lv("Every 10 s, even better odds", { Every = 10, Jackpot = 0.3, Time = 5, XP = true }, nil, "Jackpots also shower you with XP"),
		},
	},
	{
		Key = "GlitchedCore",
		Name = "Glitched Core",
		Type = "BossRelic",
		Boss = "TheGlitch",
		Rarity = "Legendary",
		Price = 3000,
		Symbol = "Speed",
		Desc = "Like THE GLITCH: a hit can glitch you away, leaving an explosion behind.",
		Flavor = "Have you tried turning it off and on again?",
		Effect = "Glitch",
		Levels = {
			lv("30% of hits: glitch away + blast (6 s recharge)", { Chance = 0.3, Cooldown = 6, Distance = 9, Blast = 30 }),
			lv("45% of hits: glitch away + blast (4 s)", { Chance = 0.45, Cooldown = 4, Distance = 10, Blast = 40 }),
			lv("50% of hits: glitch away + blast (4 s)", { Chance = 0.5, Cooldown = 4, Distance = 10, Blast = 48, Frenzy = 2 }, nil, "After a glitch: +50% damage for 2 s"),
		},
	},
	{
		Key = "KingsCrown",
		Name = "King's Crown",
		Type = "BossRelic",
		Boss = "King67",
		Rarity = "Legendary",
		Price = 3000,
		Symbol = "Special",
		Desc = "Like THE 67 KING: every few seconds your next hit is crowned: x6.7 damage.",
		Flavor = "Six. Seven. Kneel.",
		Effect = "Crowned",
		Levels = {
			lv("Every 6.7 s: a crowned hit (x6.7)", { Every = 6.7, Mult = 6.7 }),
			lv("Every 5 s: a crowned hit (x6.7)", { Every = 5, Mult = 6.7 }),
			lv("Every 5 s", { Every = 5, Mult = 6.7, Slam = 8 }, nil, "The crowned hit also double-slams the ground"),
		},
	},
	{
		Key = "TwinPact",
		Name = "Twin Pact",
		Type = "BossRelic",
		Boss = "Twins",
		Rarity = "Legendary",
		Price = 3500,
		Symbol = "Special",
		Desc = "Like SIX & SEVEN: every kill passes part of the enemy's max HP as damage to the nearest one.",
		Flavor = "6 and 7. Together forever. Sadly.",
		Effect = "Pact",
		Levels = {
			lv("Kills pass 20% of their max HP on", { Share = 0.2 }),
			lv("Kills pass 30% of their max HP on", { Share = 0.3 }),
			lv("Kills pass 35% of their max HP on", { Share = 0.35, Chain = 6 }, nil, "If the pact kills, it passes on again (up to 6 times)"),
		},
	},
	{
		Key = "VoidEye",
		Name = "Void Eye",
		Type = "BossRelic",
		Boss = "TheVoid",
		Rarity = "Legendary",
		Price = 3500,
		Symbol = "Area",
		Desc = "Like THE VOID: your DASH opens void pools where you leave and where you land (gives a dash).",
		Flavor = "It blinks back.",
		Effect = "Void",
		Levels = {
			lv("Dash: void pools at both ends", { Radius = 6, Damage = 18, Time = 4, Charges = 1 }),
			lv("Bigger pools, +1 dash charge", { Radius = 7, Damage = 26, Time = 5, Charges = 2 }),
			lv("The deepest void", { Radius = 8, Damage = 30, Time = 5, Charges = 2, Weaken = 0.25 }, nil, "Enemies in void pools take +25% damage"),
		},
	},
	{
		Key = "OverlordBanner",
		Name = "Overlord's Banner",
		Type = "BossRelic",
		Boss = "TheOverlord",
		Rarity = "Legendary",
		Price = 3500,
		Symbol = "Growth",
		Desc = "Like THE OVERLORD: every few seconds your own troops march in and fight for you.",
		Flavor = "Your army. Your rules. Their snacks.",
		Effect = "Banner",
		Levels = {
			lv("Every 14 s: 3 troops for 8 s", { Every = 14, Count = 3, Time = 8 }),
			lv("Every 11 s: 4 troops for 9 s", { Every = 11, Count = 4, Time = 9 }),
			lv("Every 10 s: 5 troops for 10 s", { Every = 10, Count = 5, Time = 10, Blast = 30 }, nil, "Your troops explode when they leave"),
		},
	},
	{
		Key = "Fragment67",
		Name = "67 FRAGMENT",
		Type = "BossRelic",
		Boss = "CountSeven", -- (HUNT's main boss: it breaks off in its phase 2)
		Rarity = "Mythic",
		Price = 6700,
		Symbol = "Special",
		Desc = "A shard of the 67. Every 67th hit strikes for 67x damage (x6.7 on bosses).",
		Flavor = "It hums. In two notes. Six and seven.",
		Effect = "Fragment",
		Levels = {
			lv("Every 67th hit: x67 (bosses x6.7)", { Every = 67, Mult = 67, BossMult = 6.7 }),
			lv("Every 50th hit: x67 (bosses x6.7)", { Every = 50, Mult = 67, BossMult = 6.7, Blast = true }, nil, "The strike releases a 67 blast"),
		},
	},
} :: any)

local ItemData = {}
ItemData.List = LIST
ItemData.ByKey = {} :: { [string]: ItemDef }
ItemData.ById = {} :: { [number]: ItemDef }
ItemData.ByBoss = {} :: { [string]: ItemDef } -- boss key -> its relic
for id, def in LIST do
	def.Id = id
	def.MaxLevel = #def.Levels
	def.StackBehavior = def.StackBehavior or "Level"
	ItemData.ByKey[def.Key] = def
	ItemData.ById[id] = def
	if def.Boss then
		ItemData.ByBoss[def.Boss] = def
	end
end

-- the rarity tiers loot rolls between (LootData weights)
ItemData.Tiers = { "Common", "Rare", "Epic", "Legendary" }

-- the price class shown in the ITEMS menu
function ItemData.PriceClass(def: ItemDef): string
	if def.Type == "BossRelic" then
		return if def.Rarity == "Mythic" then "EXTREMELY RARE" else "BOSS RELIC"
	end
	return string.upper(def.Rarity)
end

function ItemData.Get(key: string): ItemDef
	local def = ItemData.ByKey[key]
	assert(def, "unknown item " .. tostring(key))
	return def
end

-- what an item gives at a level
function ItemData.At(key: string, level: number): Level?
	local def = ItemData.ByKey[key]
	if not def or level < 1 then
		return nil
	end
	return def.Levels[math.min(level, def.MaxLevel)]
end

-- does it need an unlock (CHIPS) before it can drop?
function ItemData.NeedsUnlock(def: ItemDef): boolean
	return def.Type == "Premium" or def.Type == "BossRelic"
end

return ItemData
