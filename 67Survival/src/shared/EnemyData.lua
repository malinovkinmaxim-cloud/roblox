--[[
	EnemyData - THE ENEMY CONFIG: the horde (15 classic enemy types), the BESTIARY of every
	difficulty (2 regulars + 1 elite + 1 main boss per difficulty, at the end of the list), the
	older tier enemies, rare specials, ELITE affixes and the bodies of every boss (who and when:
	shared/BossData.lua). One place for every number: the AI reads its Params, the waves read
	Spawn (shared/WaveData.lua TierPools), the client reads Model / AnimType / colours.
	  config name    field here
	  Health         HP            ContactDamage  Damage       Coins  CoinChance (+ boss Coins)
	  SpawnWeight    Spawn.Weight  MinTime        Spawn.From   Size   Scale (model) / Radius
	  attacks        Attacks (+ Params)            phase thresholds  Phases (elites) / BossData
	Lair bosses have Champion = true (their fights: Sim/MiniBosses.lua), classic bosses and the
	MAIN bosses use Behavior "Boss" (attack patterns: Sim/Bosses.lua).

	Stats are the values at minute 0; WaveManager scales HP / damage with run time.
	  HP, Speed (studs/s), Damage (contact, per hit), XP (gem value), Radius (collision, studs)
	  (a BOSS body's HP is the number of shared/BossData.lua: that is what every boss fight
	  uses, through Sim/MiniBosses.BodyHP. The same number is written here only for a body
	  spawned on its own: debug commands and tests)
	  MinTier   - the first difficulty tier (shared/DifficultyData.lua index) it shows up on;
	              nil = every tier (the classic horde). WaveData.TierPools says when
	  Model     - client model style (Render/EnemyModels.lua): every enemy looks different
	  Scale     - visual size multiplier of that model
	  Behavior  - server AI (Sim/EnemyManager.lua): every enemy moves / attacks differently
	  Mass      - knockback resistance (knockback / Mass)
	  Params    - behaviour specific numbers

	The list order is the network id (uint8) - append new enemies at the end.
]]

export type EnemyDef = {
	Id: number,
	Key: string,
	Name: string,
	Desc: string,
	HP: number,
	Speed: number,
	Damage: number,
	XP: number,
	Radius: number,
	Scale: number,
	Model: string,
	Color: Color3,
	Accent: Color3,
	Behavior: string,
	Mass: number,
	CoinChance: number,
	ItemChance: number,
	Boss: boolean?,
	MiniBoss: boolean?,
	Champion: boolean?, -- a lair boss of 67 TOWN with its own fight (Sim/MiniBosses.lua)
	Rare: boolean?,
	Secret: boolean?,
	MinTier: number?, -- first difficulty tier it appears on (nil = every tier)
	Role: string?, -- the bestiary: "Regular" / "Elite" / "Boss" / "Minion"
	Theme: string?, -- the bestiary: the difficulty's theme (Meadow, Graveyard...)
	AnimType: string?, -- client procedural animation (Render/EnemyAnimator.lua)
	Spawn: { Weight: number, From: number, Pack: number?, Pair: string? }?, -- a bestiary regular in the horde
	Attacks: { string }?, -- what an elite / a boss does (the collection book shows it)
	Phases: { { At: number, Rate: number, Name: string } }?, -- an elite: below At of its HP it attacks Rate x faster
	NoContact: boolean?,
	Collection: boolean?,
	Params: { [string]: any },
}

local rgb = Color3.fromRGB

local function enemy(t: { [string]: any })
	t.Scale = t.Scale or 1
	t.Mass = t.Mass or 1
	t.CoinChance = t.CoinChance or 0.008
	t.ItemChance = t.ItemChance or 1
	t.Params = t.Params or {}
	if t.Collection == nil then
		t.Collection = true
	end
	return t
end

local LIST: { EnemyDef } = ({
	-------------------------------------------------------------------- the horde
	enemy({
		Key = "Goober",
		Name = "Goober",
		Desc = "A wobbly little blob. Weak alone, annoying in groups.",
		HP = 8, Speed = 10, Damage = 5, XP = 1, Radius = 1.3,
		Model = "Blob", Color = rgb(120, 220, 90), Accent = rgb(70, 160, 50),
		Behavior = "Chase",
	}),
	enemy({
		Key = "Skitter",
		Name = "Skitter",
		Desc = "Tiny, fast and never alone. Comes in packs.",
		HP = 4, Speed = 17, Damage = 4, XP = 1, Radius = 0.9,
		Model = "Bug", Color = rgb(255, 80, 70), Accent = rgb(60, 20, 20),
		Behavior = "Chase", Mass = 0.6,
	}),
	enemy({
		Key = "Husk",
		Name = "Husk",
		Desc = "Walks slowly. Stares. There is nothing behind the eyes.",
		HP = 20, Speed = 7.5, Damage = 7, XP = 2, Radius = 1.4,
		Model = "Npc", Color = rgb(163, 162, 165), Accent = rgb(13, 105, 172),
		Behavior = "Chase", Mass = 1.5, CoinChance = 0.012,
	}),
	enemy({
		Key = "Charger",
		Name = "Charger",
		Desc = "Stops, stamps, then charges in a straight line. Step aside.",
		HP = 14, Speed = 9, Damage = 8, XP = 2, Radius = 1.4,
		Model = "Charger", Color = rgb(255, 150, 60), Accent = rgb(90, 50, 30),
		Behavior = "Charge", Mass = 1.2,
		Params = { Trigger = 18, Windup = 0.75, DashTime = 0.55, DashSpeed = 32, Rest = 1.4 },
	}),
	enemy({
		Key = "Spitter",
		Name = "Spitter",
		Desc = "Keeps its distance and spits slime at you.",
		HP = 30, Speed = 8, Damage = 6, XP = 3, Radius = 1.4,
		Model = "Spitter", Color = rgb(150, 230, 90), Accent = rgb(90, 60, 160),
		Behavior = "Strafe", Mass = 1.4, CoinChance = 0.02,
		Params = { Orbit = 22, ShootEvery = 3.2, ProjSpeed = 17, ProjRadius = 1.1, ProjDamage = 6, ProjLife = 3.2 },
	}),
	enemy({
		Key = "Splitter",
		Name = "Splitter",
		Desc = "Two blobs pretending to be one. Splits into three when popped.",
		HP = 36, Speed = 8.5, Damage = 7, XP = 3, Radius = 1.8,
		Model = "Splitter", Color = rgb(90, 200, 255), Accent = rgb(40, 110, 200),
		Behavior = "Chase", Mass = 1.6,
		Params = { SplitInto = "Goober", SplitCount = 3 },
	}),
	enemy({
		Key = "Bomber",
		Name = "Bomber",
		Desc = "Runs at you with a lit fuse. Get out of the red circle.",
		HP = 18, Speed = 12, Damage = 0, XP = 2, Radius = 1.3,
		Model = "Bomber", Color = rgb(40, 40, 50), Accent = rgb(255, 90, 40),
		Behavior = "Bomber", NoContact = true,
		Params = { Trigger = 5.5, Fuse = 1.0, BlastRadius = 6, BlastDamage = 18 },
	}),
	enemy({
		Key = "Blinker",
		Name = "Blinker",
		Desc = "A glitch in the arena. Teleports closer when you look away.",
		HP = 26, Speed = 9, Damage = 8, XP = 3, Radius = 1.3,
		Model = "Glitch", Color = rgb(0, 255, 200), Accent = rgb(255, 0, 170),
		Behavior = "Blink", Mass = 1.2, CoinChance = 0.015,
		Params = { Every = 2.6, Distance = 12, MinRange = 4 },
	}),
	enemy({
		Key = "Brute",
		Name = "Brute",
		Desc = "Huge, slow, hits hard and shrugs off knockback.",
		HP = 140, Speed = 6.5, Damage = 14, XP = 8, Radius = 2.6,
		Model = "Brute", Color = rgb(110, 115, 135), Accent = rgb(60, 60, 75),
		Behavior = "Chase", Mass = 6, CoinChance = 0.06, ItemChance = 6,
	}),
	enemy({
		Key = "Diver",
		Name = "Diver",
		Desc = "Circles overhead, then dives straight at you.",
		HP = 22, Speed = 12, Damage = 9, XP = 3, Radius = 1.2,
		Model = "Diver", Color = rgb(120, 80, 200), Accent = rgb(255, 220, 90),
		Behavior = "Dive", Mass = 0.8,
		Params = { Radius = 15, Circle = 2.6, DiveTime = 0.7, DiveSpeed = 34 },
	}),
	enemy({
		Key = "Summoner",
		Name = "Summoner",
		Desc = "Stays in the back and keeps calling more skitters.",
		HP = 60, Speed = 7, Damage = 6, XP = 6, Radius = 1.6,
		Model = "Summoner", Color = rgb(70, 40, 110), Accent = rgb(255, 80, 200),
		Behavior = "Summoner", Mass = 2, CoinChance = 0.05, ItemChance = 3,
		Params = { Keep = 26, Every = 6, Count = 3, SummonKey = "Skitter" },
	}),
	enemy({
		Key = "Ghost",
		Name = "Ghost",
		Desc = "Fades in and out. While faded it can't hurt you, or be hurt.",
		HP = 40, Speed = 9.5, Damage = 9, XP = 4, Radius = 1.4,
		Model = "Ghost", Color = rgb(225, 235, 255), Accent = rgb(120, 140, 200),
		Behavior = "Phase", Mass = 0.9,
		Params = { Solid = 2.2, Phased = 1.4 },
	}),
	enemy({
		Key = "Leaper",
		Name = "Leaper",
		Desc = "Crouches, jumps, lands where you were. Keep moving.",
		HP = 45, Speed = 8, Damage = 10, XP = 5, Radius = 1.6,
		Model = "Leaper", Color = rgb(70, 190, 120), Accent = rgb(255, 240, 120),
		Behavior = "Leap", Mass = 2,
		Params = { Trigger = 20, Windup = 0.7, JumpTime = 0.45, LandRadius = 4, LandDamage = 16, Rest = 1.8 },
	}),
	enemy({
		Key = "Mimic",
		Name = "Mimic",
		Desc = "Looks like a loot box. It is not a loot box.",
		HP = 90, Speed = 15, Damage = 12, XP = 10, Radius = 1.8,
		Model = "Mimic", Color = rgb(170, 110, 60), Accent = rgb(255, 230, 90),
		Behavior = "Mimic", Mass = 3, CoinChance = 1,
		Params = { Wake = 8, Coins = 6 },
	}),
	enemy({
		Key = "Sniper",
		Name = "Sniper",
		Desc = "Aims a red line at you, then fires down it. Move off the line.",
		HP = 35, Speed = 7, Damage = 6, XP = 5, Radius = 1.4,
		Model = "Sniper", Color = rgb(60, 70, 90), Accent = rgb(255, 60, 60),
		Behavior = "Sniper", Mass = 1.4, CoinChance = 0.03,
		Params = { Keep = 32, Every = 4.6, Aim = 1.2, ProjSpeed = 55, ProjDamage = 9, ProjRadius = 1.0 },
	}),
	-------------------------------------------------------------------- specials
	enemy({
		Key = "GoldenGoober",
		Name = "Golden Goober",
		Desc = "Secret. 1 in 500 goobers is made of pure gold.",
		HP = 40, Speed = 9, Damage = 5, XP = 1, Radius = 1.3,
		Model = "Blob", Color = rgb(255, 205, 50), Accent = rgb(255, 245, 170),
		Behavior = "Chase", CoinChance = 1, ItemChance = 0, Secret = true,
		Params = { Coins = 25 },
	}),
	enemy({
		Key = "Goblin67",
		Name = "67 Goblin",
		Desc = "Rare. Carries a sack of coins and runs. Catch it before it escapes!",
		HP = 67, Speed = 13, Damage = 0, XP = 20, Radius = 1.2,
		Model = "Goblin", Color = rgb(90, 200, 70), Accent = rgb(255, 215, 50),
		Behavior = "Flee", Mass = 1, CoinChance = 1, ItemChance = 0, Rare = true, NoContact = true,
		Params = { Lifetime = 16, Coins = 30, Chest = true },
	}),
	enemy({
		Key = "The67",
		Name = "THE 67",
		Desc = "Very rare. It circles you and throws sixes and sevens. Defeat it.",
		HP = 6700, Speed = 12, Damage = 12, XP = 67, Radius = 2.2,
		Model = "The67", Color = rgb(255, 205, 50), Accent = rgb(120, 60, 200),
		Behavior = "Sixty", Mass = 20, CoinChance = 1, ItemChance = 0, Rare = true,
		Params = { Lifetime = 50, Radius = 18, Every = 6.7, Shots = 7, ProjSpeed = 18, ProjDamage = 12, Coins = 167, Chest = true },
	}),
	enemy({
		Key = "Crate",
		Name = "Loot Box",
		Desc = "Break it for snacks, magnets and bombs.",
		HP = 1, Speed = 0, Damage = 0, XP = 0, Radius = 1.6,
		Model = "Crate", Color = rgb(170, 110, 60), Accent = rgb(255, 230, 90),
		Behavior = "Static", Mass = 999, CoinChance = 0, ItemChance = 0, NoContact = true, Collection = false,
		Params = { Lifetime = 60 },
	}),
	-------------------------------------------------------------------- bosses
	enemy({
		Key = "TheGiant",
		Name = "THE GIANT",
		Desc = "Boss 1 of Goober Gardens (sometimes). Slams the ground, sends out shockwaves, calls husks.",
		HP = 2500, Speed = 7.5, Damage = 16, XP = 150, Radius = 5,
		Model = "Giant", Color = rgb(190, 150, 120), Accent = rgb(90, 70, 60),
		Behavior = "Boss", Mass = 40, CoinChance = 1, ItemChance = 0, MiniBoss = true,
		Params = {
			Title = "THE GIANT",
			Patterns = { "Slam", "Ring", "Summon" },
			SlamEvery = 5.5, SlamRadius = 12, SlamDelay = 1.1, SlamDamage = 24,
			RingEvery = 7, RingCount = 14, RingSpeed = 17, RingDamage = 12,
			SummonEvery = 10, SummonKey = "Husk", SummonCount = 5,
			Coins = 60,
		},
	}),
	enemy({
		Key = "TheGoober",
		Name = "THE GOOBER",
		Desc = "Boss 1 of Goober Gardens (sometimes). The biggest blob. Bounces onto you and rains goobers.",
		HP = 2500, Speed = 9, Damage = 16, XP = 150, Radius = 5,
		Model = "GooberBoss", Color = rgb(120, 220, 90), Accent = rgb(255, 110, 190),
		Behavior = "Boss", Mass = 40, CoinChance = 1, ItemChance = 0, MiniBoss = true,
		Params = {
			Title = "THE GOOBER",
			Patterns = { "Leap", "Rain", "Summon" },
			LeapEvery = 4.8, LeapDelay = 1.0, LeapRadius = 9, LeapDamage = 24,
			RainEvery = 10, RainCount = 12,
			SummonEvery = 12, SummonKey = "Splitter", SummonCount = 3,
			Coins = 60,
		},
	}),
	enemy({
		Key = "TheGlitch",
		Name = "THE GLITCH",
		Desc = "Boss 3 of the Neon Strip (sometimes). Teleports next to you, cuts the street with lasers, calls blinkers.",
		HP = 12000, Speed = 10, Damage = 18, XP = 300, Radius = 4.5,
		Model = "GlitchBoss", Color = rgb(0, 255, 210), Accent = rgb(255, 0, 170),
		Behavior = "Boss", Mass = 50, CoinChance = 1, ItemChance = 0, Boss = true,
		Params = {
			Title = "THE GLITCH",
			Patterns = { "Teleport", "Sweep", "Summon" },
			TeleportEvery = 5, TeleportDelay = 0.8, TeleportRadius = 9, TeleportDamage = 26,
			SweepEvery = 7, SweepCount = 4, SweepLength = 60, SweepWidth = 4, SweepDelay = 1.1, SweepDamage = 22,
			SummonEvery = 11, SummonKey = "Blinker", SummonCount = 4,
			Coins = 120,
		},
	}),
	enemy({
		Key = "TheMachine",
		Name = "THE MACHINE",
		Desc = "Boss 2 of the Horde Mart Lot (sometimes). A walking weapons factory: missiles, lasers, bullet rings.",
		HP = 7800, Speed = 8, Damage = 18, XP = 300, Radius = 5,
		Model = "Machine", Color = rgb(150, 160, 175), Accent = rgb(255, 80, 40),
		Behavior = "Boss", Mass = 60, CoinChance = 1, ItemChance = 0, Boss = true,
		Params = {
			Title = "THE MACHINE",
			Patterns = { "Barrage", "Sweep", "Ring" },
			BarrageEvery = 6, BarrageCount = 9, BarrageRadius = 5, BarrageSpread = 18, BarrageDelay = 1.2, BarrageDamage = 20,
			SweepEvery = 8, SweepCount = 3, SweepLength = 70, SweepWidth = 4.5, SweepDelay = 1.2, SweepDamage = 24,
			RingEvery = 6.5, RingCount = 18, RingSpeed = 20, RingDamage = 13,
			Coins = 120,
		},
	}),
	enemy({
		Key = "TheVoid",
		Name = "THE VOID",
		Desc = "Boss 4 of the Rift (sometimes). Opens void pools under your feet and spins dark energy.",
		HP = 24000, Speed = 9, Damage = 20, XP = 400, Radius = 5,
		Model = "VoidBoss", Color = rgb(30, 20, 50), Accent = rgb(170, 90, 255),
		Behavior = "Boss", Mass = 60, CoinChance = 1, ItemChance = 0, Boss = true,
		Params = {
			Title = "THE VOID",
			Patterns = { "Hazard", "Spiral", "Teleport" },
			HazardEvery = 6, HazardCount = 3, HazardRadius = 7, HazardDelay = 1.1, HazardTime = 4, HazardDamage = 10,
			SpiralEvery = 8, SpiralCount = 22, SpiralSpeed = 19, SpiralDamage = 13,
			TeleportEvery = 9, TeleportDelay = 0.9, TeleportRadius = 10, TeleportDamage = 28,
			SweepEvery = 7, SweepCount = 3, SweepLength = 60, SweepWidth = 4, SweepDelay = 1.2, SweepDamage = 24,
			PhasePatterns = { [3] = { "Sweep" } },
			Coins = 150,
		},
	}),
	enemy({
		Key = "TheOverlord",
		Name = "THE OVERLORD",
		Desc = "Boss 4 of the Rift (sometimes). Charges across the altars, fires rings and calls spitters.",
		HP = 24000, Speed = 10, Damage = 20, XP = 400, Radius = 4.6,
		Model = "Overlord", Color = rgb(25, 25, 32), Accent = rgb(255, 205, 60),
		Behavior = "Boss", Mass = 60, CoinChance = 1, ItemChance = 0, Boss = true,
		Params = {
			Title = "THE OVERLORD",
			Patterns = { "Dash", "Ring", "Summon" },
			DashEvery = 6, DashWindup = 1.0, DashSpeed = 58, DashLength = 55, DashDamage = 30,
			RingEvery = 7, RingCount = 16, RingSpeed = 20, RingDamage = 14,
			SummonEvery = 12, SummonKey = "Spitter", SummonCount = 4,
			BarrageEvery = 7, BarrageCount = 7, BarrageRadius = 5, BarrageSpread = 16, BarrageDelay = 1.2, BarrageDamage = 22,
			PhasePatterns = { [3] = { "Barrage" } },
			Coins = 150,
		},
	}),
	enemy({
		Key = "King67",
		Name = "THE 67 KING",
		Desc = "Boss 3 of the Neon Strip (sometimes). Six. Seven. Six. Seven.",
		HP = 13000, Speed = 9.5, Damage = 20, XP = 400, Radius = 4.8,
		Model = "King", Color = rgb(255, 200, 40), Accent = rgb(170, 60, 255),
		Behavior = "Boss", Mass = 60, CoinChance = 1, ItemChance = 0, Boss = true, Rare = true,
		Params = {
			Title = "THE 67 KING",
			Patterns = { "DoubleSlam", "Spiral", "Summon" },
			SlamEvery = 6.7, SlamRadius = 11, SlamDelay = 1.0, SlamDamage = 26,
			SpiralEvery = 8, SpiralCount = 20, SpiralSpeed = 19, SpiralDamage = 13,
			SummonEvery = 13, SummonKey = "Goblin67", SummonCount = 1,
			Coins = 267,
		},
	}),
	enemy({
		Key = "TheFinalOne",
		Name = "THE FINAL ONE",
		Desc = "The main boss: waits in the 67 ARENA at 15:00. Three phases. Beat it to win the run.",
		HP = 80000, Speed = 8.5, Damage = 24, XP = 1000, Radius = 7,
		Model = "FinalOne", Color = rgb(40, 30, 60), Accent = rgb(255, 64, 150),
		Behavior = "Boss", Mass = 120, CoinChance = 1, ItemChance = 0, Boss = true,
		Params = {
			Title = "THE FINAL ONE",
			Final = true,
			Patterns = { "Slam", "Ring", "Barrage" },
			PhasePatterns = { [2] = { "Spiral", "Hazard", "Sweep" }, [3] = { "DoomRing", "Summon" } },
			SlamEvery = 5, SlamRadius = 14, SlamDelay = 1.0, SlamDamage = 30,
			RingEvery = 6.5, RingCount = 20, RingSpeed = 21, RingDamage = 12,
			BarrageEvery = 8, BarrageCount = 8, BarrageRadius = 5, BarrageSpread = 18, BarrageDelay = 1.2, BarrageDamage = 22,
			SpiralEvery = 9, SpiralCount = 24, SpiralSpeed = 20, SpiralDamage = 11,
			HazardEvery = 10, HazardCount = 3, HazardRadius = 7, HazardDelay = 1.1, HazardTime = 4, HazardDamage = 12,
			SweepEvery = 7, SweepCount = 4, SweepLength = 70, SweepWidth = 4.5, SweepDelay = 1.1, SweepDamage = 26,
			DoomRingEvery = 6.5, DoomCount = 40, DoomGap = 5, DoomSpeed = 15, DoomDamage = 22, DoomDelay = 1.2,
			SummonEvery = 11, SummonKey = "Skitter", SummonCount = 8,
			Coins = 400,
		},
	}),
	-------------------------------------------------------------------- mini-bosses of 67 TOWN
	-- (shared/MiniBossData.lua: who, where and when; Sim/MiniBosses.lua: how they fight)
	enemy({
		Key = "BigQuack",
		Name = "THE BIG QUACK",
		Desc = "Mini-boss of Goober Gardens. Belly-flops where you stand and leaves slippery puddles.",
		HP = 2400, Speed = 8, Damage = 14, XP = 0, Radius = 4.4,
		Model = "Quack", Color = rgb(255, 214, 60), Accent = rgb(255, 136, 40),
		Behavior = "Champion", Mass = 30, CoinChance = 0, ItemChance = 0, Champion = true,
		Params = {
			Title = "THE BIG QUACK",
			FlopEvery = 5.2, FlopDelay = 1.1, FlopRadius = 9, FlopDamage = 22,
			DropCount = 12, DropSpeed = 15, DropDamage = 9,
			PuddleRadius = 8, PuddleTime = 6, PuddleSlow = 0.55,
			DucklingEvery = 11, DucklingCount = 4,
		},
	}),
	enemy({
		Key = "Duckling",
		Name = "Duckling",
		Desc = "Follows THE BIG QUACK. Follows you. Bites ankles.",
		HP = 10, Speed = 15.5, Damage = 5, XP = 1, Radius = 1.0,
		Model = "Duckling", Color = rgb(255, 226, 90), Accent = rgb(255, 140, 40),
		Behavior = "Chase", Mass = 0.6, CoinChance = 0.004, ItemChance = 0,
	}),
	enemy({
		Key = "Cartzilla",
		Name = "CARTZILLA",
		Desc = "Mini-boss of the Horde Mart Lot. Charges in straight lines and spills everywhere.",
		HP = 7000, Speed = 9, Damage = 16, XP = 0, Radius = 4.2,
		Model = "Cart", Color = rgb(196, 204, 220), Accent = rgb(255, 72, 72),
		Behavior = "Champion", Mass = 34, CoinChance = 0, ItemChance = 0, Champion = true,
		Params = {
			Title = "CARTZILLA",
			ChargeEvery = 6.5, Dashes = 3, DashWindup = 0.85, DashSpeed = 62, DashLength = 46, DashDamage = 26,
			SpillEvery = 8, SpillRadius = 3.4, SpillTime = 4, SpillDamage = 6,
			PriceEvery = 9.5, PriceCount = 7, PriceRadius = 4.5, PriceSpread = 16, PriceDelay = 1.3, PriceDamage = 18,
		},
	}),
	enemy({
		Key = "JackpotJimmy",
		Name = "JACKPOT JIMMY",
		Desc = "Mini-boss of the Neon Strip. Its reels decide the attack. Tilts behind a shield of coin stacks.",
		HP = 13000, Speed = 6.5, Damage = 16, XP = 0, Radius = 4.4,
		Model = "Slots", Color = rgb(235, 60, 100), Accent = rgb(255, 205, 60),
		Behavior = "Champion", Mass = 40, CoinChance = 0, ItemChance = 0, Champion = true,
		Params = {
			Title = "JACKPOT JIMMY",
			SpinEvery = 6, SpinTime = 1.3,
			Reels = { Ring = 3, Cross = 3, Bombs = 3, Jackpot = 1 },
			RingCount = 16, RingSpeed = 17, RingDamage = 11,
			CrossCount = 3, CrossLength = 64, CrossWidth = 4, CrossDelay = 1.0, CrossDamage = 22,
			BombCount = 6, BombRadius = 5, BombSpread = 16, BombDelay = 1.2, BombDamage = 20,
			JackpotCoins = 8, StunTime = 3.5,
			ShieldAt = 0.5, PylonCount = 3, PylonDistance = 19,
		},
	}),
	enemy({
		Key = "CoinStack",
		Name = "Coin Stack",
		Desc = "Holds up JACKPOT JIMMY's shield. Break all three.",
		HP = 160, Speed = 0, Damage = 0, XP = 2, Radius = 1.8,
		Model = "CoinStack", Color = rgb(255, 205, 60), Accent = rgb(200, 140, 30),
		Behavior = "Static", Mass = 999, CoinChance = 1, ItemChance = 0, NoContact = true, Collection = false,
		Params = { Coins = 3 },
	}),
	enemy({
		Key = "Six",
		Name = "SIX",
		Desc = "Mini-boss of the Rift (with SEVEN). Keeps its distance and fans out sixes.",
		HP = 11000, Speed = 10, Damage = 14, XP = 0, Radius = 3.4,
		Model = "Six", Color = rgb(255, 205, 50), Accent = rgb(130, 70, 220),
		Behavior = "Champion", Mass = 30, CoinChance = 0, ItemChance = 0, Champion = true,
		Params = {
			Title = "SIX", Twin = "Seven",
			Keep = 15, FanEvery = 3.2, FanShots = 6, FanSpread = 0.9, FanSpeed = 20, FanDamage = 10,
			ReviveTime = 6.7,
		},
	}),
	enemy({
		Key = "Seven",
		Name = "SEVEN",
		Desc = "Mini-boss of the Rift (with SIX). Walks up to you and lays seven mines.",
		HP = 11000, Speed = 8.5, Damage = 16, XP = 0, Radius = 3.6,
		Model = "Seven", Color = rgb(140, 80, 230), Accent = rgb(255, 205, 50),
		Behavior = "Champion", Mass = 30, CoinChance = 0, ItemChance = 0, Champion = true,
		Params = {
			Title = "SEVEN", Twin = "Six",
			MineEvery = 5.5, MineCount = 7, MineRadius = 4, MineDelay = 1.6, MineDamage = 20,
			ReviveTime = 6.7,
		},
	}),
	enemy({
		Key = "TickTock",
		Name = "TICK TOCK",
		Desc = "Roaming mini-boss. A laser clock hand sweeps around it. 67 seconds, then it rings and runs.",
		HP = 6200, Speed = 6.2, Damage = 15, XP = 0, Radius = 3.8,
		Model = "Clock", Color = rgb(240, 80, 80), Accent = rgb(250, 248, 240),
		Behavior = "Champion", Mass = 30, CoinChance = 0, ItemChance = 0, Champion = true,
		Params = {
			Title = "TICK TOCK",
			Timer = 67,
			HandEvery = 0.3, HandLength = 30, HandWidth = 3, HandDelay = 0.55, HandSpeed = 0.95, HandDamage = 16,
			TockEvery = 8, TockRadius = 8, TockDelay = 1, TockDamage = 20,
			AlarmCount = 24, AlarmSpeed = 20, AlarmDamage = 14,
			OnTimeCoins = 67,
		},
	}),
	-------------------------------------------------------------------- the horde of the harder tiers
	-- (appended: the list order is the network id). MinTier = the first tier it joins the horde
	-- on; WaveData.TierPools says from when and how often.
	enemy({
		Key = "Snoozer",
		Name = "Snoozer",
		Desc = "Sleeps where it lands. Walk too close and it wakes up, blinks, and comes running.",
		HP = 14, Speed = 10, Damage = 6, XP = 2, Radius = 1.4,
		Model = "Snoozer", Color = rgb(150, 160, 235), Accent = rgb(60, 62, 125),
		Behavior = "Sleep", MinTier = 1,
		Params = { Wake = 9, Blink = 0.8, Rush = 1.2 },
	}),
	enemy({
		Key = "Shielder",
		Name = "Shielder",
		Desc = "Hides behind a big shield: hits from the front barely hurt and the shield covers the horde behind it. Flank it or break the shield.",
		HP = 32, Speed = 7, Damage = 8, XP = 4, Radius = 1.7,
		Model = "Shielder", Color = rgb(90, 130, 190), Accent = rgb(232, 236, 245),
		Behavior = "Shield", Mass = 3, CoinChance = 0.015, MinTier = 2,
		Params = { GuardHP = 1.2, GuardCut = 0.7, GuardArc = 1.25 },
	}),
	enemy({
		Key = "Stampeder",
		Name = "Stampeder",
		Desc = "Stamps, then runs a straight lane, faster and faster. It can't turn: step aside.",
		HP = 22, Speed = 9, Damage = 9, XP = 3, Radius = 1.4,
		Model = "Stampeder", Color = rgb(186, 128, 76), Accent = rgb(250, 236, 205),
		Behavior = "Stampede", Mass = 2, MinTier = 3,
		Params = { Trigger = 42, Windup = 0.8, RunTime = 2.4, TopSpeed = 27, Accel = 1.4, Turn = 0.45, Rest = 1.1 },
	}),
	enemy({
		Key = "Bannerman",
		Name = "Bannerman",
		Desc = "Waves its banner behind the horde: everything inside its ring runs faster. Take it out first.",
		HP = 50, Speed = 7.5, Damage = 6, XP = 6, Radius = 1.5,
		Model = "Bannerman", Color = rgb(120, 72, 165), Accent = rgb(255, 205, 60),
		Behavior = "Banner", Mass = 2, CoinChance = 0.04, ItemChance = 3, MinTier = 3,
		Params = { Keep = 22, Aura = 12, Haste = 1.2 },
	}),
	enemy({
		Key = "Wailer",
		Name = "Wailer",
		Desc = "Keeps its distance and wails: a slow ring wave with one gap. Find the gap.",
		HP = 32, Speed = 8, Damage = 6, XP = 4, Radius = 1.4,
		Model = "Wailer", Color = rgb(200, 210, 240), Accent = rgb(72, 60, 140),
		Behavior = "Wail", Mass = 1.2, CoinChance = 0.02, MinTier = 4,
		Params = { Keep = 20, Every = 4.6, Windup = 0.8, Count = 16, Gap = 3, ProjSpeed = 13, ProjDamage = 7, ProjRadius = 1.1, ProjLife = 3.4 },
	}),
	enemy({
		Key = "Hexer",
		Name = "Hexer",
		Desc = "Draws a curse circle under your feet. It explodes 1.2 s later: keep walking.",
		HP = 30, Speed = 7.5, Damage = 6, XP = 4, Radius = 1.4,
		Model = "Hexer", Color = rgb(72, 52, 132), Accent = rgb(250, 240, 150),
		Behavior = "Hex", Mass = 1.2, CoinChance = 0.02, MinTier = 4,
		Params = { Keep = 22, Every = 5.5, Delay = 1.2, Radius = 4.5, HexDamage = 14 },
	}),
	enemy({
		Key = "Cinder",
		Name = "Cinder",
		Desc = "A walking ember. Leaves a trail of fire for a few seconds: don't follow it.",
		HP = 26, Speed = 10, Damage = 7, XP = 3, Radius = 1.3,
		Model = "Cinder", Color = rgb(48, 42, 44), Accent = rgb(255, 236, 150),
		Behavior = "Cinder", MinTier = 5,
		Params = { TrailEvery = 0.7, TrailRadius = 2.2, TrailTime = 3, TrailDamage = 5 },
	}),
	enemy({
		Key = "Eruptor",
		Name = "Eruptor",
		Desc = "Barely moves. Lobs lava onto where you stand: the circle shows where it lands.",
		HP = 45, Speed = 3, Damage = 8, XP = 5, Radius = 1.8,
		Model = "Eruptor", Color = rgb(58, 52, 58), Accent = rgb(255, 222, 120),
		Behavior = "Mortar", Mass = 4, CoinChance = 0.03, ItemChance = 2, MinTier = 5,
		Params = { Keep = 30, Every = 4, Delay = 1.3, Radius = 4, LavaDamage = 15 },
	}),
	enemy({
		Key = "Predator",
		Name = "Predator",
		Desc = "Doesn't run at you: runs at where you WILL be, then pounces. Change direction.",
		HP = 34, Speed = 12.5, Damage = 10, XP = 5, Radius = 1.4,
		Model = "Predator", Color = rgb(100, 108, 128), Accent = rgb(150, 235, 255),
		Behavior = "Predator", Mass = 1.4, MinTier = 6,
		Params = { Lead = 0.8, Trigger = 14, Windup = 0.75, PounceTime = 0.45, PounceSpeed = 34, Rest = 1.2 },
	}),
	enemy({
		Key = "Warden",
		Name = "Warden",
		Desc = "Slow. Its bubble protects the horde inside (-40% damage taken). Pop the Warden first.",
		HP = 70, Speed = 6, Damage = 8, XP = 7, Radius = 1.8,
		Model = "Warden", Color = rgb(222, 226, 236), Accent = rgb(120, 172, 255),
		Behavior = "Ward", Mass = 4, CoinChance = 0.04, ItemChance = 3, MinTier = 6,
		Params = { Keep = 14, Aura = 9, Ward = 0.4 },
	}),
	enemy({
		Key = "Sixlet",
		Name = "Sixlet",
		Desc = "A little 6. Always with a little 7. Kill one and the other goes mad, unless both fall within 3 s.",
		HP = 30, Speed = 11, Damage = 8, XP = 4, Radius = 1.3,
		Model = "Sixlet", Color = rgb(255, 205, 50), Accent = rgb(130, 70, 220),
		Behavior = "Chase", MinTier = 7,
		Params = { Pair = "Sevenlet", RageDelay = 3, RageTime = 5, RageSpeed = 1.6, RageDamage = 1.3 },
	}),
	enemy({
		Key = "Sevenlet",
		Name = "Sevenlet",
		Desc = "A little 7. Always with a little 6. Kill one and the other goes mad, unless both fall within 3 s.",
		HP = 30, Speed = 11, Damage = 8, XP = 4, Radius = 1.3,
		Model = "Sevenlet", Color = rgb(140, 80, 230), Accent = rgb(255, 205, 50),
		Behavior = "Chase", MinTier = 7,
		Params = { Pair = "Sixlet", RageDelay = 3, RageTime = 5, RageSpeed = 1.6, RageDamage = 1.3 },
	}),
	-------------------------------------------------------------------- boss minions
	enemy({
		Key = "Crow",
		Name = "Crow",
		Desc = "THE SCARECROW's crows. Circle, aim, dive.",
		HP = 12, Speed = 13, Damage = 7, XP = 1, Radius = 1.0,
		Model = "Crow", Color = rgb(38, 38, 48), Accent = rgb(255, 214, 80),
		Behavior = "Dive", Mass = 0.6, CoinChance = 0.004, ItemChance = 0,
		Params = { Radius = 13, Circle = 2.2, DiveTime = 0.6, DiveSpeed = 34, Windup = 0.75, Lifetime = 18 },
	}),
	enemy({
		Key = "GooEgg",
		Name = "Goo Egg",
		Desc = "MAMA GOOBER's eggs. Break them before they hatch.",
		HP = 60, Speed = 0, Damage = 0, XP = 1, Radius = 1.6,
		Model = "GooEgg", Color = rgb(206, 240, 176), Accent = rgb(255, 128, 196),
		Behavior = "Egg", Mass = 999, CoinChance = 0, ItemChance = 0, NoContact = true, Collection = false,
		Params = { Hatch = 4, HatchKey = "Goober", HatchCount = 4 },
	}),
	enemy({
		Key = "WarBanner",
		Name = "War Banner",
		Desc = "THE HORDEMASTER's banner: the horde runs faster while it stands. Break the pole.",
		HP = 400, Speed = 0, Damage = 0, XP = 2, Radius = 1.8,
		Model = "WarBanner", Color = rgb(178, 40, 52), Accent = rgb(255, 205, 60),
		Behavior = "Rally", Mass = 999, CoinChance = 0, ItemChance = 0, NoContact = true, Collection = false,
		Params = { Aura = 22, Haste = 1.3 },
	}),
	-------------------------------------------------------------------- lair bosses of the harder tiers
	-- (shared/BossData.lua: MinTier, slot; Sim/MiniBosses.lua AI: how they fight)
	enemy({
		Key = "SirSnailsalot",
		Name = "SIR SNAILSALOT",
		Desc = "Boss 1 of Goober Gardens (tier III+). Rolls its shell down a line, leaves slime. Hit it when it peeks out.",
		HP = 2600, Speed = 6, Damage = 14, XP = 0, Radius = 4.2,
		Model = "Snail", Color = rgb(176, 214, 120), Accent = rgb(168, 112, 72),
		Behavior = "Champion", Mass = 32, CoinChance = 0, ItemChance = 0, Champion = true, MinTier = 3,
		Params = {
			Title = "SIR SNAILSALOT",
			RollEvery = 6, RollWindup = 1.1, RollSpeed = 40, RollLength = 44, RollDamage = 24, ShellArmor = 0.5,
			SlimeEvery = 5, SlimeRadius = 4, SlimeTime = 6, SlimeSlow = 0.6,
			SpitEvery = 7, SpitShots = 5, SpitSpread = 0.8, SpitSpeed = 16, SpitDamage = 9,
		},
	}),
	enemy({
		Key = "Scarecrow",
		Name = "THE SCARECROW",
		Desc = "Boss 1 of Goober Gardens (tier V+). Spins its stick arms in a wide fan and sends crows. Its head is soft after a spin.",
		HP = 2700, Speed = 7, Damage = 15, XP = 0, Radius = 4.0,
		Model = "Scarecrow", Color = rgb(226, 196, 112), Accent = rgb(255, 186, 56),
		Behavior = "Champion", Mass = 30, CoinChance = 0, ItemChance = 0, Champion = true, MinTier = 5,
		Params = {
			Title = "THE SCARECROW",
			SpinEvery = 6.5, SpinDelay = 1.1, SpinArms = 3, SpinArc = 1.0, SpinRadius = 18, SpinTurn = 1.05, SpinDamage = 22,
			CrowEvery = 10, CrowCount = 3,
		},
	}),
	enemy({
		Key = "SelfCheckout",
		Name = "SELF-CHECKOUT",
		Desc = "Boss 2 of the Horde Mart Lot (tier III+). Scanner beams, and an UNEXPECTED ITEM in your bagging area.",
		HP = 7200, Speed = 6, Damage = 16, XP = 0, Radius = 4.4,
		Model = "Checkout", Color = rgb(222, 226, 232), Accent = rgb(80, 205, 255),
		Behavior = "Champion", Mass = 40, CoinChance = 0, ItemChance = 0, Champion = true, MinTier = 3,
		Params = {
			Title = "SELF-CHECKOUT",
			ScanEvery = 6.5, ScanCount = 3, ScanLength = 64, ScanWidth = 4, ScanDelay = 1.1, ScanGap = 0.35, ScanSpacing = 9, ScanDamage = 22,
			MarkEvery = 8.5, MarkDelay = 1.5, MarkRadius = 7, MarkDamage = 24, MarkShots = 10, MarkSpeed = 14, MarkShotDamage = 9,
		},
	}),
	enemy({
		Key = "Mannequin",
		Name = "THE MANNEQUIN",
		Desc = "Boss 2 of the Horde Mart Lot (tier V+). Red light, green light: it freezes while you move and dashes when you stand still.",
		HP = 7000, Speed = 7, Damage = 16, XP = 0, Radius = 3.8,
		Model = "Mannequin", Color = rgb(236, 222, 204), Accent = rgb(32, 32, 38),
		Behavior = "Champion", Mass = 34, CoinChance = 0, ItemChance = 0, Champion = true, MinTier = 5,
		Params = {
			Title = "THE MANNEQUIN",
			Still = 0.45, DashWindup = 1.0, DashSpeed = 60, DashLength = 40, DashDamage = 26, DashRest = 1.4,
			PoseEvery = 7, PoseShots = 12, PoseSpeed = 15, PoseDamage = 10,
		},
	}),
	enemy({
		Key = "DJDrop",
		Name = "DJ DROP",
		Desc = "Boss 3 of the Neon Strip (tier III+). Everything happens on the beat: rings with a gap, and then... the DROP.",
		HP = 12500, Speed = 5.5, Damage = 16, XP = 0, Radius = 4.4,
		Model = "DJ", Color = rgb(52, 42, 74), Accent = rgb(80, 240, 255),
		Behavior = "Champion", Mass = 40, CoinChance = 0, ItemChance = 0, Champion = true, MinTier = 3,
		Params = {
			Title = "DJ DROP",
			Beat = 0.5, RingBeats = 4, RingWindup = 2, RingCount = 24, RingGap = 4, RingSpeed = 15, RingDamage = 12, GapStep = 0.785,
			DropEvery = 14, DropBuild = 1.5, DropRings = 4, DropDamage = 12,
		},
	}),
	enemy({
		Key = "RouletteRoller",
		Name = "ROULETTE ROLLER",
		Desc = "Boss 3 of the Neon Strip (tier V+). Red or black? It tells you the safe colour, then the other one burns.",
		HP = 13000, Speed = 7, Damage = 16, XP = 0, Radius = 4.6,
		Model = "Roulette", Color = rgb(30, 30, 38), Accent = rgb(255, 205, 60),
		Behavior = "Champion", Mass = 40, CoinChance = 0, ItemChance = 0, Champion = true, MinTier = 5,
		Params = {
			Title = "ROULETTE ROLLER",
			SpinEvery = 6.5, SpinTime = 1.4, Sectors = 8, SectorRadius = 24, SectorDelay = 1.3, SectorDamage = 26,
			ZeroChance = 0.12, ZeroEvery = 4, StunTime = 3,
			BallEvery = 9, BallShots = 10, BallSpeed = 16, BallDamage = 10,
		},
	}),
	enemy({
		Key = "TheMirror",
		Name = "THE MIRROR",
		Desc = "Boss 4 of the Rift (tier III+). Walks the path you walked, fires along it. Cracks after its dash.",
		HP = 23000, Speed = 9, Damage = 18, XP = 0, Radius = 4.0,
		Model = "Mirror", Color = rgb(200, 210, 226), Accent = rgb(120, 230, 255),
		Behavior = "Champion", Mass = 40, CoinChance = 0, ItemChance = 0, Champion = true, MinTier = 3,
		Params = {
			Title = "THE MIRROR",
			Behind = 2.0, EchoEvery = 6, EchoCount = 6, EchoRadius = 4.5, EchoDelay = 1.1, EchoDamage = 22,
			DashEvery = 9, DashWindup = 1.1, DashSpeed = 62, DashLength = 44, DashDamage = 28,
			ShotEvery = 3.5, ShotCount = 3, ShotSpread = 0.35, ShotSpeed = 20, ShotDamage = 11,
		},
	}),
	enemy({
		Key = "EventHorizon",
		Name = "THE EVENT HORIZON",
		Desc = "Boss 4 of the Rift (tier V+). Pulls gently, sends ring waves in from the edge, then collapses everything but a few safe spots.",
		HP = 24500, Speed = 4.5, Damage = 18, XP = 0, Radius = 4.6,
		Model = "Horizon", Color = rgb(22, 18, 32), Accent = rgb(190, 150, 255),
		Behavior = "Champion", Mass = 60, CoinChance = 0, ItemChance = 0, Champion = true, MinTier = 5,
		Params = {
			Title = "THE EVENT HORIZON",
			PullRadius = 34, PullSlow = 0.78, PullEvery = 7, PullTime = 3.5,
			WaveEvery = 7, WaveCount = 28, WaveGap = 4, WaveRadius = 30, WaveSpeed = 12, WaveDamage = 13,
			CollapseEvery = 11, CollapseRadius = 30, SafeCount = 3, SafeRadius = 5, CollapseDelay = 1.6, CollapseDamage = 30,
		},
	}),
	-------------------------------------------------------------------- MAIN bosses (one per tier: BossData.Mains)
	enemy({
		Key = "MamaGoober",
		Name = "MAMA GOOBER",
		Desc = "Main boss of tier I CALM: waits in the 67 ARENA at 15:00. Belly-flops, goober rain, a nest of eggs.",
		HP = 70000, Speed = 7.5, Damage = 18, XP = 1000, Radius = 7.5,
		Model = "MamaGoober", Color = rgb(124, 222, 96), Accent = rgb(255, 132, 192),
		Behavior = "Boss", Mass = 120, CoinChance = 1, ItemChance = 0, Boss = true, MinTier = 1,
		Params = {
			Title = "MAMA GOOBER",
			Final = true,
			ShotRoom = 60, -- (Sim/EnemyManager.Shoot: room for its rings)
			Patterns = { "BellyFlop", "GooRain", "Nest" },
			PhasePatterns = { [2] = { "Ring" } },
			BellyFlopEvery = 6, FlopDelay = 1.4, FlopRadius = 11, FlopDamage = 26, FlopDrops = 12, FlopDropSpeed = 13, FlopDropDamage = 9,
			GooRainEvery = 9, RainCount = 8,
			NestEvery = 14, EggCount = 3, EggKey = "GooEgg",
			RingEvery = 7, RingCount = 18, RingSpeed = 16, RingDamage = 10,
			Coins = 400,
		},
	}),
	enemy({
		Key = "TheHordemaster",
		Name = "THE HORDEMASTER",
		Desc = "Main boss of tier III HORDE. Commands the horde through a megaphone: stampede lanes, formation walls, a war banner.",
		HP = 80000, Speed = 8, Damage = 24, XP = 1000, Radius = 7,
		Model = "Hordemaster", Color = rgb(150, 34, 46), Accent = rgb(255, 205, 60),
		Behavior = "Boss", Mass = 120, CoinChance = 1, ItemChance = 0, Boss = true, MinTier = 3,
		Params = {
			Title = "THE HORDEMASTER",
			Final = true,
			ShotRoom = 60, -- (Sim/EnemyManager.Shoot: room for its rings)
			Patterns = { "Lanes", "Slam", "BannerCall" },
			PhasePatterns = { [2] = { "Formation" }, [3] = { "FullCharge" } },
			LanesEvery = 7, LaneCount = 3, LaneLength = 84, LaneWidth = 6, LaneDelay = 1.3, LaneDamage = 24, LaneKey = "Stampeder", LaneHerd = 3,
			SlamEvery = 6, SlamRadius = 12, SlamDelay = 1.1, SlamDamage = 26,
			BannerCallEvery = 16, BannerKey = "WarBanner",
			FormationEvery = 15, FormationCount = 18, FormationRadius = 26, FormationGap = 3, FormationKey = "Shielder", FormationSpeed = 3.5, FormationLife = 9,
			FullChargeEvery = 13, ChargeDelay = 1.5, ChargeDamage = 28, ChargeSafe = 7,
			Coins = 400,
		},
	}),
	enemy({
		Key = "TheDread",
		Name = "THE DREAD",
		Desc = "Main boss of tier IV NIGHTMARE. A tall shadow with a moon eye. Turns the lights out.",
		HP = 80000, Speed = 8, Damage = 24, XP = 1000, Radius = 6.5,
		Model = "Dread", Color = rgb(64, 54, 124), Accent = rgb(252, 240, 160),
		Behavior = "Boss", Mass = 120, CoinChance = 1, ItemChance = 0, Boss = true, MinTier = 4,
		Params = {
			Title = "THE DREAD",
			Final = true,
			ShotRoom = 60, -- (Sim/EnemyManager.Shoot: room for its rings)
			Patterns = { "Hands", "EyeSweep", "Ring" },
			PhasePatterns = { [2] = { "Echoes", "LightsOut" }, [3] = { "DoomRing" } },
			HandsEvery = 6, HandCount = 5, HandRadius = 5, HandSpread = 14, HandDelay = 1.2, HandDamage = 22,
			EyeSweepEvery = 9, SweepLines = 7, SweepLength = 60, SweepWidth = 5, SweepDelay = 1.2, SweepStep = 0.22, SweepGap = 0.18, SweepDamage = 26,
			RingEvery = 7, RingCount = 20, RingSpeed = 18, RingDamage = 11,
			EchoesEvery = 8, EchoCount = 6, EchoRadius = 4.5, EchoDelay = 1.2, EchoDamage = 20,
			LightsOutEvery = 18, DarkTime = 9,
			DoomRingEvery = 7, DoomCount = 40, DoomGap = 5, DoomSpeed = 14, DoomDamage = 20, DoomDelay = 1.3,
			Coins = 400,
		},
	}),
	enemy({
		Key = "TheFurnace",
		Name = "THE FURNACE",
		Desc = "Main boss of tier V INFERNO. A furnace golem that heats the arena one sector at a time.",
		HP = 82000, Speed = 7, Damage = 24, XP = 1000, Radius = 7.5,
		Model = "Furnace", Color = rgb(40, 38, 44), Accent = rgb(255, 214, 90),
		Behavior = "Boss", Mass = 140, CoinChance = 1, ItemChance = 0, Boss = true, MinTier = 5,
		Params = {
			Title = "THE FURNACE",
			Final = true,
			ShotRoom = 60, -- (Sim/EnemyManager.Shoot: room for its rings)
			Patterns = { "Sectors", "Slam", "EmberRing" },
			PhasePatterns = { [2] = { "Meteors" }, [3] = { "Steam" } },
			SectorsEvery = 5, SectorCount = 8, SectorHot = 3, SectorDelay = 1.5, SectorDamage = 26,
			SlamEvery = 6.5, SlamRadius = 12, SlamDelay = 1.1, SlamDamage = 28,
			EmberRingEvery = 7.5, EmberCount = 22, EmberGap = 4, EmberSpeed = 15, EmberDamage = 11,
			MeteorsEvery = 10, MeteorCount = 8, MeteorRadius = 5, MeteorSpread = 18, MeteorDelay = 1.3, MeteorDamage = 22,
			SteamEvery = 9, SteamRadius = 11, SteamDelay = 1.2, SteamDamage = 18,
			Coins = 400,
		},
	}),
	enemy({
		Key = "TheEraser",
		Name = "THE ERASER",
		Desc = "Main boss of tier VI OBLIVION. Erases the floor and the arena with it, then redraws the horde.",
		HP = 82000, Speed = 8.5, Damage = 24, XP = 1000, Radius = 7,
		Model = "Eraser", Color = rgb(240, 238, 232), Accent = rgb(70, 72, 82),
		Behavior = "Boss", Mass = 120, CoinChance = 1, ItemChance = 0, Boss = true, MinTier = 6,
		Params = {
			Title = "THE ERASER",
			Final = true,
			ShotRoom = 60, -- (Sim/EnemyManager.Shoot: room for its rings)
			Patterns = { "Swipe", "Erase" },
			PhasePatterns = { [2] = { "Redraw" }, [3] = { "DoomRing" } },
			EdgeErase = 7, -- studs of arena erased at every new phase (Sim/Bosses.EraseEdge)
			SwipeEvery = 7, SwipeWindup = 1.1, SwipeLength = 64, SwipeWidth = 9, SwipeSpeed = 60, SwipeDamage = 28,
			EraseEvery = 8, EraseCount = 3, EraseRadius = 6, EraseDelay = 1.2, EraseTime = 24, EraseDamage = 10,
			RedrawEvery = 15, RedrawCount = 3, RedrawLife = 14,
			DoomRingEvery = 7, DoomCount = 40, DoomGap = 5, DoomSpeed = 14, DoomDamage = 20, DoomDelay = 1.3,
			Coins = 400,
		},
	}),
	enemy({
		Key = "PrimeSix",
		Name = "SIX",
		Desc = "THE 67 PRIME, phase 1: a golden six. Its twin SEVEN must fall within 6.7 s of it.",
		HP = 12000, Speed = 10, Damage = 20, XP = 0, Radius = 4.4,
		Model = "PrimeSix", Color = rgb(255, 205, 50), Accent = rgb(150, 80, 240),
		Behavior = "Champion", Mass = 60, CoinChance = 0, ItemChance = 0, Champion = true, MinTier = 7, Collection = false,
		Params = {
			Title = "SIX", Twin = "PrimeSeven", Fuse = "The67Prime", NoPhases = true,
			Keep = 16, FanEvery = 2.8, FanShots = 7, FanSpread = 1.0, FanSpeed = 21, FanDamage = 12,
			ReviveTime = 6.7,
		},
	}),
	enemy({
		Key = "PrimeSeven",
		Name = "SEVEN",
		Desc = "THE 67 PRIME, phase 1: a golden seven. Its twin SIX must fall within 6.7 s of it.",
		HP = 12000, Speed = 9, Damage = 22, XP = 0, Radius = 4.6,
		Model = "PrimeSeven", Color = rgb(30, 26, 36), Accent = rgb(255, 205, 50),
		Behavior = "Champion", Mass = 60, CoinChance = 0, ItemChance = 0, Champion = true, MinTier = 7, Collection = false,
		Params = {
			Title = "SEVEN", Twin = "PrimeSix", Fuse = "The67Prime", NoPhases = true,
			MineEvery = 5, MineCount = 7, MineRadius = 4.5, MineDelay = 1.5, MineDamage = 24,
			ReviveTime = 6.7,
		},
	}),
	enemy({
		Key = "The67Prime",
		Name = "THE 67 PRIME",
		Desc = "Main boss of tier VII THE 67. Six and seven, fused into gold. Every boss you ever met, in one.",
		HP = 56000, Speed = 8, Damage = 26, XP = 1000, Radius = 7.5,
		Model = "Prime67", Color = rgb(255, 200, 40), Accent = rgb(140, 70, 230),
		Behavior = "Boss", Mass = 140, CoinChance = 1, ItemChance = 0, Boss = true, MinTier = 7,
		Params = {
			Title = "THE 67 PRIME",
			Final = true,
			ShotRoom = 60, -- (Sim/EnemyManager.Shoot: room for its rings)
			Patterns = { "BellyFlop", "Lanes", "Nest" },
			PhaseSets = { [2] = { "Hands", "EyeSweep", "Sectors", "LightsOut" }, [3] = { "Erase", "DoomRing", "SixSeven" } },
			BellyFlopEvery = 6.5, FlopDelay = 1.3, FlopRadius = 11, FlopDamage = 28, FlopDrops = 14, FlopDropSpeed = 14, FlopDropDamage = 10,
			NestEvery = 15, EggCount = 3, EggKey = "GooEgg",
			LanesEvery = 7, LaneCount = 4, LaneLength = 84, LaneWidth = 6, LaneDelay = 1.3, LaneDamage = 26, LaneKey = "Stampeder", LaneHerd = 3,
			HandsEvery = 6, HandCount = 5, HandRadius = 5, HandSpread = 14, HandDelay = 1.2, HandDamage = 24,
			EyeSweepEvery = 9, SweepLines = 7, SweepLength = 60, SweepWidth = 5, SweepDelay = 1.2, SweepStep = 0.22, SweepGap = 0.18, SweepDamage = 28,
			SectorsEvery = 6, SectorCount = 8, SectorHot = 3, SectorDelay = 1.5, SectorDamage = 28,
			LightsOutEvery = 20, DarkTime = 10,
			EraseEvery = 8, EraseCount = 3, EraseRadius = 6, EraseDelay = 1.2, EraseTime = 24, EraseDamage = 12,
			DoomRingEvery = 8, DoomCount = 40, DoomGap = 5, DoomSpeed = 14, DoomDamage = 22, DoomDelay = 1.3,
			SixSevenEvery = 12, SeriesBeat = 0.67, SeriesCount = 24, SeriesGap = 4, SeriesSpeed = 15, SeriesDamage = 14,
			EdgeErase = 7, EdgeFrom = 3, -- phase 4 (its third own phase) erases the edge
			Coins = 400,
		},
	}),
	---------------------------------------------------------------------------------------------
	-- THE BESTIARY: every difficulty's own enemies (appended: the list order is the network id).
	-- Per difficulty: 2 regulars (Spawn = { Weight next to the classic mix, From seconds, Pack };
	-- shared/WaveData.lua builds its TierPools from these), 1 ELITE (Role = "Elite": only the
	-- elite director brings it, Sim/Elites) and its MAIN BOSS (shared/BossData.lua Mains).
	-- Their AI: Sim/Bestiary.lua (horde, elites) and Sim/BossPatterns.lua (the bosses).
	-- AnimType: the client's procedural animation (Render/EnemyAnimator.lua).
	-- Attacks / Phases: what an elite or a boss does (Phases: HP fraction -> attacks speed up).
	---------------------------------------------------------------- I CALM · Meadow
	enemy({
		Key = "Gloopy",
		Name = "Gloopy",
		Desc = "A wobbly little slime. Hops at you in a swarm.",
		HP = 8, Speed = 9, Damage = 4, XP = 1, Radius = 1.4,
		Model = "Gloopy", Color = rgb(123, 224, 106), Accent = rgb(58, 140, 50),
		Behavior = "Hop", MinTier = 1, Role = "Regular", Theme = "Meadow", AnimType = "Hop",
		Spawn = { Weight = 1.4, From = 20, Pack = 3 },
		Params = { HopEvery = 0.8, HopTime = 0.4, HopBoost = 2.1, Rest = 0.15 },
	}),
	enemy({
		Key = "BuzzBat",
		Name = "Buzz Bat",
		Desc = "Zigzags through the air, flashes, then darts at you.",
		HP = 6, Speed = 12, Damage = 4, XP = 1, Radius = 1.1,
		Model = "BuzzBat", Color = rgb(139, 92, 246), Accent = rgb(91, 52, 196),
		Behavior = "Zigzag", Mass = 0.7, MinTier = 1, Role = "Regular", Theme = "Meadow", AnimType = "Flap",
		Spawn = { Weight = 0.7, From = 75 },
		Params = { Fly = true, Weave = 0.85, WeaveSpeed = 3.4, Every = 5, Trigger = 15, Windup = 0.7, DashTime = 0.35, DashSpeed = 32, Rest = 0.5 },
	}),
	enemy({
		Key = "KingGloop",
		Name = "King Gloop",
		Desc = "ELITE. A royal slime with a paper crown. Jumps onto you (red circle), and pops into three Gloopies.",
		HP = 40, Speed = 6, Damage = 7, XP = 4, Radius = 2.4,
		Model = "KingGloop", Color = rgb(123, 224, 106), Accent = rgb(250, 204, 21),
		Behavior = "Jumper", Mass = 3, CoinChance = 0.05, ItemChance = 2, MinTier = 1, Role = "Elite", Theme = "Meadow", AnimType = "Hop",
		Attacks = { "Jump slam every 6 s: red circle 0.8 s, a shockwave where it lands", "Pops into 3 Gloopies that fly out" },
		Phases = { { At = 0.5, Rate = 1.3, Name = "ANGRY" } },
		Params = {
			Every = 6, Trigger = 28, Windup = 0.8, JumpTime = 0.55, JumpRadius = 6.5, JumpDamage = 14, Rest = 0.8,
			SplitInto = "Gloopy", SplitCount = 3, SplitFling = 16,
		},
	}),
	enemy({
		Key = "MiniGloop",
		Name = "Mini Gloop",
		Desc = "MEGA SIX's orbiting slimes. While any of them is alive, MEGA SIX takes 30% less damage.",
		HP = 60, Speed = 0, Damage = 8, XP = 2, Radius = 1.7,
		Model = "MiniGloop", Color = rgb(182, 245, 160), Accent = rgb(58, 140, 50),
		Behavior = "Orbit", Mass = 999, CoinChance = 0, ItemChance = 0, Role = "Minion", Theme = "Meadow", AnimType = "Hop", Collection = false,
		Params = {},
	}),
	enemy({
		Key = "MegaSix",
		Name = "MEGA SIX",
		Desc = "Main boss of I CALM. A giant slime shaped like a 6: belly slams, slime fans, three orbiting slimes that shield it.",
		HP = 140000, Speed = 7, Damage = 18, XP = 1000, Radius = 7.5,
		Model = "MegaSix", Color = rgb(123, 224, 106), Accent = rgb(58, 140, 50),
		Behavior = "Boss", Mass = 120, CoinChance = 1, ItemChance = 0, Boss = true, MinTier = 1, Role = "Boss", Theme = "Meadow", AnimType = "Boss",
		Attacks = { "Jump slam + a ring of slime drops", "Slime fan: 5 balls", "SWELL at 50%: faster, 6 Gloopies", "3 orbiting slimes: -30% damage while any lives" },
		Params = {
			Title = "MEGA SIX",
			Final = true,
			ShotRoom = 60, -- (Sim/EnemyManager.Shoot: room for its rings)
			Patterns = { "Orbiters", "BellyFlop", "SlimeFan" },
			PhasePatterns = { [2] = { "Swell" } },
			BellyFlopEvery = 6.5, FlopDelay = 1.3, FlopRadius = 11, FlopDamage = 24, FlopDrops = 12, FlopDropSpeed = 13, FlopDropDamage = 8,
			SlimeFanEvery = 4.5, FanDelay = 1.0, FanShots = 5, FanSpread = 0.9, FanSpeed = 17, FanDamage = 10,
			OrbitersEvery = 3, OrbitBack = 20, OrbitKey = "MiniGloop", OrbitCount = 3, OrbitRadius = 12, OrbitSpin = 1.1, OrbitCut = 0.3,
			SwellEvery = 999, SwellKey = "Gloopy", SwellCount = 6,
			Coins = 400,
		},
	}),
	---------------------------------------------------------------- II HUNT · Graveyard
	enemy({
		Key = "BooSheet",
		Name = "Boo Sheet",
		Desc = "A shy ghost in a sheet. Floats through walls. Face it and it slows down; turn your back and it speeds up.",
		HP = 13, Speed = 8, Damage = 5, XP = 2, Radius = 1.5,
		Model = "BooSheet", Color = rgb(232, 241, 255), Accent = rgb(96, 130, 200),
		Behavior = "Shy", MinTier = 2, Role = "Regular", Theme = "Graveyard", AnimType = "Float",
		Spawn = { Weight = 0.8, From = 45 },
		Params = { Seen = 0.6, Behind = 1.35, SeenArc = 0.52, BehindArc = 2.0, Ghost = true },
	}),
	enemy({
		Key = "BonkSkull",
		Name = "Bonk Skull",
		Desc = "Rolls at you. Every few seconds it stops, opens its jaw (a line on the ground) and bonks straight ahead, bouncing off walls.",
		HP = 15, Speed = 8.5, Damage = 6, XP = 2, Radius = 1.4,
		Model = "BonkSkull", Color = rgb(245, 240, 224), Accent = rgb(70, 58, 58),
		Behavior = "Bonk", Mass = 1.5, MinTier = 2, Role = "Regular", Theme = "Graveyard", AnimType = "Roll",
		Spawn = { Weight = 0.7, From = 110 },
		Params = { Every = 5, Trigger = 24, Windup = 0.7, DashLength = 18, DashSpeed = 34, Bounces = 1, Rest = 0.6 },
	}),
	enemy({
		Key = "PumpkinKnight",
		Name = "Pumpkin Knight",
		Desc = "ELITE. Its round shield blocks hits from the front: go round it. Throws a fan of three sparks.",
		HP = 45, Speed = 6.5, Damage = 8, XP = 5, Radius = 2.1,
		Model = "PumpkinKnight", Color = rgb(249, 115, 22), Accent = rgb(107, 33, 168),
		Behavior = "Knight", Mass = 3, CoinChance = 0.05, ItemChance = 2, MinTier = 2, Role = "Elite", Theme = "Graveyard", AnimType = "Bob",
		Attacks = { "Front shield: blocks 70% of a hit from the front (it turns slowly: go round it)", "Spark fan: 3 sparks every 7 s after a 0.8 s flash" },
		Phases = { { At = 0.5, Rate = 1.3, Name = "FURIOUS" } },
		Params = { BlockArc = 1.0, BlockCut = 0.7, Turn = 1.6, Every = 7, Windup = 0.8, FanShots = 3, FanSpread = 0.45, ProjSpeed = 17, ProjDamage = 9, ProjRadius = 1.1, ProjLife = 2.2 },
	}),
	enemy({
		Key = "CountSeven",
		Name = "COUNT SEVEN",
		Desc = "Main boss of II HUNT. A chibi vampire: steps out of the night behind you, sends bat swarms, and at half HP raises the BLOOD MOON.",
		HP = 140000, Speed = 8.5, Damage = 22, XP = 1000, Radius = 6.5,
		Model = "CountSeven", Color = rgb(241, 228, 243), Accent = rgb(185, 28, 28),
		Behavior = "Boss", Mass = 120, CoinChance = 1, ItemChance = 0, Boss = true, MinTier = 2, Role = "Boss", Theme = "Graveyard", AnimType = "Boss",
		Attacks = { "Night step: fades out, reappears behind you, cape strike in an arc", "Bat swarm: a ring of 12 Buzz Bats", "BLOOD MOON at 50%: bats keep coming until you deal enough damage" },
		Params = {
			Title = "COUNT SEVEN",
			Final = true,
			ShotRoom = 60,
			Patterns = { "NightStep", "BatSwarm", "Slam" },
			PhasePatterns = { [2] = { "BloodMoon" } },
			NightStepEvery = 7, StepFade = 0.3, StepBehind = 7, CapeDelay = 1.1, CapeRadius = 13, CapeArc = 1.1, CapeDamage = 26,
			BatSwarmEvery = 11, BatCount = 12, BatKey = "BuzzBat",
			SlamEvery = 6, SlamRadius = 9, SlamDelay = 1.1, SlamDamage = 22,
			BloodMoonEvery = 999, MoonShare = 0.12, MoonBats = 4, MoonBatEvery = 3.5,
			Coins = 400,
		},
	}),
	---------------------------------------------------------------- III HORDE · Desert
	enemy({
		Key = "Wrappy",
		Name = "Wrappy",
		Desc = "A mummy that never stops walking. When it falls it unwraps: stepping on its bandages slows you.",
		HP = 20, Speed = 7.5, Damage = 6, XP = 3, Radius = 1.4,
		Model = "Wrappy", Color = rgb(231, 217, 176), Accent = rgb(74, 222, 128),
		Behavior = "Chase", MinTier = 3, Role = "Regular", Theme = "Desert", AnimType = "Bob",
		Spawn = { Weight = 0.9, From = 40 },
		Params = { Unwrap = { Count = 3, Radius = 2.2, Spread = 3.5, Time = 1.2, Slow = 0.88 } },
	}),
	enemy({
		Key = "Scorp",
		Name = "Scorp",
		Desc = "Keeps its distance; its tail flashes, then it shoots a slow stinger.",
		HP = 18, Speed = 8.5, Damage = 5, XP = 3, Radius = 1.4,
		Model = "Scorp", Color = rgb(217, 119, 6), Accent = rgb(120, 60, 10),
		Behavior = "Stinger", MinTier = 3, Role = "Regular", Theme = "Desert", AnimType = "Bob",
		Spawn = { Weight = 0.55, From = 130 },
		Params = { Keep = 12, Every = 3.4, Windup = 0.7, ProjSpeed = 14, ProjDamage = 7, ProjRadius = 1.0, ProjLife = 2.4 },
	}),
	enemy({
		Key = "SandGolem",
		Name = "Sand Golem",
		Desc = "ELITE. Floating sandstone blocks. Raises its fists and slams an 8-stud circle; the ground stays cracked.",
		HP = 60, Speed = 5, Damage = 9, XP = 6, Radius = 2.4,
		Model = "SandGolem", Color = rgb(194, 163, 107), Accent = rgb(45, 212, 191),
		Behavior = "Golem", Mass = 5, CoinChance = 0.05, ItemChance = 2, MinTier = 3, Role = "Elite", Theme = "Desert", AnimType = "Float",
		Attacks = { "Fist slam every 6 s: an 8-stud circle (1 s), cracked ground for 3 s" },
		Phases = { { At = 0.5, Rate = 1.3, Name = "CRUMBLING" } },
		Params = { Every = 6, Trigger = 18, Windup = 1.0, SlamRadius = 8, SlamDamage = 16, Crack = { Count = 3, Radius = 2.6, Time = 3, Damage = 4 } },
	}),
	enemy({
		Key = "SandSpout",
		Name = "Sand Spout",
		Desc = "PHARAOH SIXSEVEN's whirlwinds. They sweep the arena for a few seconds.",
		HP = 120, Speed = 9, Damage = 8, XP = 1, Radius = 2.2,
		Model = "SandSpout", Color = rgb(222, 196, 140), Accent = rgb(160, 120, 70),
		Behavior = "Roam", Mass = 999, CoinChance = 0, ItemChance = 0, Role = "Minion", Theme = "Desert", AnimType = "Spin", Collection = false,
		Params = { Fly = true, Lifetime = 9 },
	}),
	enemy({
		Key = "PharaohSixseven",
		Name = "PHARAOH SIXSEVEN",
		Desc = "Main boss of III HORDE. A floating golden mask with two giant hands and a ring of 6 and 7 tiles.",
		HP = 80000, Speed = 7.5, Damage = 22, XP = 1000, Radius = 7,
		Model = "PharaohSixseven", Color = rgb(250, 204, 21), Accent = rgb(20, 184, 166),
		Behavior = "Boss", Mass = 140, CoinChance = 1, ItemChance = 0, Boss = true, MinTier = 3, Role = "Boss", Theme = "Desert", AnimType = "Boss",
		Attacks = { "Sandstorm: 3 whirlwinds sweep the arena", "Clap: the hands slam where you stand, twice", "3 small Sand Golems rise", "Phase 2: the tile ring fires its tiles one by one" },
		Params = {
			Title = "PHARAOH SIXSEVEN",
			Final = true,
			ShotRoom = 60,
			Patterns = { "Sandstorm", "Clap", "RaiseGolems" },
			PhasePatterns = { [2] = { "TileVolley" } },
			SandstormEvery = 13, SpoutCount = 3, SpoutKey = "SandSpout",
			ClapEvery = 5.5, ClapDelay = 1.1, ClapRadius = 7, ClapDamage = 26, ClapGap = 0.6,
			RaiseGolemsEvery = 16, GolemCount = 3, GolemKey = "SandGolem",
			TileVolleyEvery = 7, TileCount = 6, TileGap = 0.35, TileSpeed = 22, TileDamage = 12,
			Coins = 400,
		},
	}),
	---------------------------------------------------------------- IV NIGHTMARE · Frostbite
	enemy({
		Key = "SnowyPal",
		Name = "Snowy Pal",
		Desc = "A friendly-looking snowman that throws snowballs from afar, and rolls into you up close.",
		HP = 18, Speed = 7.5, Damage = 6, XP = 3, Radius = 1.5,
		Model = "SnowyPal", Color = rgb(244, 248, 252), Accent = rgb(239, 68, 68),
		Behavior = "Lobber", MinTier = 4, Role = "Regular", Theme = "Frostbite", AnimType = "Bob",
		Spawn = { Weight = 0.7, From = 60 },
		Params = { Keep = 14, Every = 3.4, Windup = 0.7, ProjSpeed = 15, ProjDamage = 6, ProjRadius = 1.2, ProjLife = 1.5, RollTrigger = 5, RollTime = 0.45, RollSpeed = 22, Rest = 0.6 },
	}),
	enemy({
		Key = "FrostWisp",
		Name = "Frost Wisp",
		Desc = "A fast ice crystal. Its trail slows you; it bursts into a ring of ice when it breaks.",
		HP = 12, Speed = 13.5, Damage = 5, XP = 2, Radius = 1.1,
		Model = "FrostWisp", Color = rgb(125, 211, 252), Accent = rgb(224, 242, 254),
		Behavior = "Wisp", Mass = 0.8, MinTier = 4, Role = "Regular", Theme = "Frostbite", AnimType = "Spin",
		Spawn = { Weight = 0.6, From = 150 },
		Params = { Fly = true, TrailEvery = 0.6, TrailRadius = 2.2, TrailTime = 1.2, Slow = 0.8, BurstCount = 6, BurstSpeed = 11, BurstDamage = 4, BurstLife = 1.0 },
	}),
	enemy({
		Key = "YetiChonk",
		Name = "Yeti Chonk",
		Desc = "ELITE. A big fluffy yeti with an ice club. Crouches, charges, and smashes a line of ice spikes ahead of it.",
		HP = 70, Speed = 5.5, Damage = 9, XP = 7, Radius = 2.6,
		Model = "YetiChonk", Color = rgb(248, 250, 252), Accent = rgb(56, 189, 248),
		Behavior = "Yeti", Mass = 5, CoinChance = 0.05, ItemChance = 2, MinTier = 4, Role = "Elite", Theme = "Frostbite", AnimType = "Bob",
		Attacks = { "Charge every 5 s after a 0.9 s crouch", "Ice spikes: a 14-stud line ahead (0.8 s)" },
		Phases = { { At = 0.5, Rate = 1.3, Name = "FURIOUS" } },
		Params = { Every = 5, Trigger = 22, Windup = 0.9, DashTime = 0.45, DashSpeed = 26, SpikeLength = 14, SpikeWidth = 4, SpikeDelay = 0.8, SpikeDamage = 16, Rest = 0.8 },
	}),
	enemy({
		Key = "PenguinPrime",
		Name = "EMPEROR PENGUIN PRIME",
		Desc = "Main boss of IV NIGHTMARE. A giant penguin with an ice crown: belly slides that bounce off the arena, ice spikes in a grid, a frozen arena.",
		HP = 80000, Speed = 7.5, Damage = 22, XP = 1000, Radius = 7,
		Model = "PenguinPrime", Color = rgb(30, 41, 59), Accent = rgb(125, 211, 252),
		Behavior = "Boss", Mass = 140, CoinChance = 1, ItemChance = 0, Boss = true, MinTier = 4, Role = "Boss", Theme = "Frostbite", AnimType = "Boss",
		Attacks = { "Belly slide across the arena, bouncing off the edge twice", "Ice spikes in a grid", "FREEZE at 50%: icy patches and Snowy Pals at the edge" },
		Params = {
			Title = "EMPEROR PENGUIN PRIME",
			Final = true,
			ShotRoom = 60,
			Patterns = { "BellySlide", "SpikeGrid" },
			PhasePatterns = { [2] = { "IceArena" } },
			BellySlideEvery = 7.5, SlideWindup = 1.2, SlideWidth = 9, SlideSpeed = 46, SlideBounces = 2, SlideDamage = 28,
			SpikeGridEvery = 6, GridSize = 5, GridStep = 7, GridRadius = 2.8, GridDelay = 1.2, GridDamage = 22, GridFill = 0.45,
			IceArenaEvery = 18, IcePatches = 6, IceRadius = 7, IceTime = 14, IceSlow = 0.6, IcePals = 4, IcePalKey = "SnowyPal",
			Coins = 400,
		},
	}),
	---------------------------------------------------------------- V INFERNO · Volcano
	enemy({
		Key = "MagmaBun",
		Name = "Magma Bun",
		Desc = "A cracked lava bun. Leaves little fire puddles behind it: don't follow it.",
		HP = 21, Speed = 8, Damage = 6, XP = 3, Radius = 1.5,
		Model = "MagmaBun", Color = rgb(63, 29, 20), Accent = rgb(251, 146, 60),
		Behavior = "Cinder", MinTier = 5, Role = "Regular", Theme = "Volcano", AnimType = "Bob",
		Spawn = { Weight = 0.8, From = 50 },
		Params = { TrailEvery = 0.9, TrailRadius = 2.3, TrailTime = 2, TrailDamage = 3 },
	}),
	enemy({
		Key = "ImpPop",
		Name = "Imp Pop",
		Desc = "A little red imp with a trident. Shoots fireballs one at a time, and pops when it dies (step out of the circle).",
		HP = 15, Speed = 10, Damage = 5, XP = 2, Radius = 1.3,
		Model = "ImpPop", Color = rgb(239, 68, 68), Accent = rgb(30, 20, 24),
		Behavior = "Imp", MinTier = 5, Role = "Regular", Theme = "Volcano", AnimType = "Hop",
		Spawn = { Weight = 0.55, From = 150 },
		Params = { Keep = 13, Every = 2.8, Windup = 0.7, ProjSpeed = 19, ProjDamage = 5, ProjRadius = 0.9, ProjLife = 2, PopRadius = 4.5, PopDelay = 0.7, PopDamage = 5 },
	}),
	enemy({
		Key = "ObsidianCrab",
		Name = "Obsidian Crab",
		Desc = "ELITE. Walks sideways. Its shell takes 60% off every hit until it cracks open (10 hits): then 5 s of full damage.",
		HP = 70, Speed = 6, Damage = 9, XP = 7, Radius = 2.6,
		Model = "ObsidianCrab", Color = rgb(24, 24, 27), Accent = rgb(251, 146, 60),
		Behavior = "Crab", Mass = 6, CoinChance = 0.05, ItemChance = 2, MinTier = 5, Role = "Elite", Theme = "Volcano", AnimType = "Bob",
		Attacks = { "Obsidian shell: -60% damage, breaks after 10 hits for 5 s", "Claw pinch up close (0.75 s)" },
		Phases = { { At = 0.5, Rate = 1.3, Name = "SNAPPY" } },
		Params = { Side = 0.8, ShellHits = 10, ShellCut = 0.6, ShellBroken = 5, Every = 4, Trigger = 6, Windup = 0.75, PinchRadius = 4.5, PinchDamage = 15 },
	}),
	enemy({
		Key = "Drako67",
		Name = "DRAKO 67",
		Desc = "Main boss of V INFERNO. A chibi dragon: fire breath in a cone, meteor rain, take-off and a shockwave landing.",
		HP = 110000, Speed = 7.5, Damage = 24, XP = 1000, Radius = 7,
		Model = "Drako67", Color = rgb(220, 38, 38), Accent = rgb(250, 204, 21),
		Behavior = "Boss", Mass = 140, CoinChance = 1, ItemChance = 0, Boss = true, MinTier = 5, Role = "Boss", Theme = "Volcano", AnimType = "Boss",
		Attacks = { "Fire breath: a 90° cone (1 s)", "Meteor rain: 8 circles, 1.2 s", "Take-off: lands on you with a shockwave ring", "Phase 2: Imp Pops, everything faster" },
		Params = {
			Title = "DRAKO 67",
			Final = true,
			ShotRoom = 60,
			Patterns = { "FireBreath", "Meteors", "Takeoff" },
			PhasePatterns = { [2] = { "Summon" } },
			FireBreathEvery = 5.5, BreathDelay = 1.0, BreathRadius = 24, BreathHalf = 0.785, BreathDamage = 26,
			MeteorsEvery = 9, MeteorCount = 8, MeteorRadius = 5, MeteorSpread = 20, MeteorDelay = 1.2, MeteorDamage = 22,
			TakeoffEvery = 11, TakeoffTime = 1.6, LandRadius = 10, LandDamage = 28, LandRing = 18, LandRingSpeed = 15, LandRingDamage = 10,
			SummonEvery = 13, SummonCount = 4, SummonKey = "ImpPop",
			Coins = 400,
		},
	}),
	---------------------------------------------------------------- VI OBLIVION · Cyber Glitch
	enemy({
		Key = "PixelBit",
		Name = "Pixel Bit",
		Desc = "Eight neon cubes in a trench coat. Glitches 5 studs sideways every 2 s.",
		HP = 13, Speed = 9, Damage = 5, XP = 2, Radius = 1.3,
		Model = "PixelBit", Color = rgb(34, 211, 238), Accent = rgb(244, 114, 182),
		Behavior = "Glitchy", MinTier = 6, Role = "Regular", Theme = "Cyber", AnimType = "Jitter",
		Spawn = { Weight = 0.8, From = 50 },
		Params = { Every = 2, Jump = 5 },
	}),
	enemy({
		Key = "DronePod",
		Name = "Drone Pod",
		Desc = "Hovers out of reach, draws a thin red line at you, then fires a laser down it.",
		HP = 16, Speed = 9, Damage = 5, XP = 3, Radius = 1.3,
		Model = "DronePod", Color = rgb(241, 245, 249), Accent = rgb(59, 130, 246),
		Behavior = "Sniper", MinTier = 6, Role = "Regular", Theme = "Cyber", AnimType = "Float",
		Spawn = { Weight = 0.5, From = 160 },
		Params = { Fly = true, Keep = 14, Every = 4, Aim = 0.8, ProjSpeed = 60, ProjRadius = 0.8, ProjDamage = 7 },
	}),
	enemy({
		Key = "FirewallBot",
		Name = "Firewall Bot",
		Desc = "ELITE. A monitor-headed robot behind a holo shield that blocks your shots from the front. Calls Pixel Bits.",
		HP = 70, Speed = 5.5, Damage = 8, XP = 7, Radius = 2.6,
		Model = "FirewallBot", Color = rgb(30, 41, 59), Accent = rgb(45, 212, 191),
		Behavior = "Firewall", Mass = 5, CoinChance = 0.05, ItemChance = 2, MinTier = 6, Role = "Elite", Theme = "Cyber", AnimType = "Bob",
		Attacks = { "Holo shield in front: blocks 75% until it breaks (it turns slowly)", "Calls 3 Pixel Bits every 10 s" },
		Phases = { { At = 0.5, Rate = 1.3, Name = "ANGRY" } },
		Params = { GuardHP = 0.6, GuardCut = 0.75, GuardArc = 1.1, Turn = 1.2, Every = 10, SummonKey = "PixelBit", SummonCount = 3 },
	}),
	enemy({
		Key = "OverclockHolo",
		Name = "Hologram",
		Desc = "OVERCLOCK-6's decoys: a red core means fake. One hit pops them.",
		HP = 1, Speed = 6, Damage = 8, XP = 0, Radius = 3.2,
		Model = "OverclockHolo", Color = rgb(150, 220, 255), Accent = rgb(255, 80, 90),
		Behavior = "Holo", Mass = 999, CoinChance = 0, ItemChance = 0, Role = "Minion", Theme = "Cyber", AnimType = "Float", Collection = false,
		Params = { Fly = true, OneHit = true, Lifetime = 9, Every = 2.4, Count = 10, ProjSpeed = 14, ProjDamage = 9 },
	}),
	enemy({
		Key = "Overclock6",
		Name = "OVERCLOCK-6",
		Desc = "Main boss of VI OBLIVION. A giant screen-faced robot: a laser that sweeps the arena, digital rain, hologram decoys, then OVERCLOCK.",
		HP = 82000, Speed = 7.5, Damage = 24, XP = 1000, Radius = 7,
		Model = "Overclock6", Color = rgb(51, 65, 85), Accent = rgb(34, 211, 238),
		Behavior = "Boss", Mass = 140, CoinChance = 1, ItemChance = 0, Boss = true, MinTier = 6, Role = "Boss", Theme = "Cyber", AnimType = "Boss",
		Attacks = { "Laser sweep: lines turn round the arena", "Digital rain: columns light up, then pixels fall", "Holograms: two fakes with red cores", "OVERCLOCK at 50%: +40% attack speed" },
		Params = {
			Title = "OVERCLOCK-6",
			Final = true,
			ShotRoom = 60,
			Patterns = { "LaserSweep", "DigitalRain", "Hologram" },
			PhasePatterns = { [2] = { "Overclock" } },
			LaserSweepEvery = 8, LaserLines = 8, LaserStep = 0.42, LaserGap = 0.28, LaserDelay = 1.1, LaserLength = 60, LaserWidth = 4.5, LaserDamage = 26,
			DigitalRainEvery = 7, RainCols = 4, RainRows = 4, RainStep = 8, RainRadius = 3.4, RainDelay = 1.2, RainDamage = 22,
			HologramEvery = 16, HoloCount = 2, HoloKey = "OverclockHolo",
			OverclockEvery = 999, OverclockRate = 1.4,
			Coins = 400,
		},
	}),
	---------------------------------------------------------------- VII THE 67 · Void
	enemy({
		Key = "Voidling",
		Name = "Voidling",
		Desc = "A fast little piece of the void. Up close it pulls at you: walking away is slower.",
		HP = 21, Speed = 11, Damage = 7, XP = 3, Radius = 1.3,
		Model = "Voidling", Color = rgb(15, 10, 31), Accent = rgb(192, 132, 252),
		Behavior = "Voidling", MinTier = 7, Role = "Regular", Theme = "Void", AnimType = "Float",
		Spawn = { Weight = 0.8, From = 60 },
		Params = { Fly = true, PullRadius = 8, PullSlow = 0.88 },
	}),
	enemy({
		Key = "StarEater",
		Name = "Star Eater",
		Desc = "A one-eyed black planet with three moons. Throws its moons at you; each one flies back 3 s later.",
		HP = 30, Speed = 7, Damage = 7, XP = 4, Radius = 1.8,
		Model = "StarEater", Color = rgb(17, 24, 39), Accent = rgb(168, 85, 247),
		Behavior = "Moons", Mass = 2, MinTier = 7, Role = "Regular", Theme = "Void", AnimType = "Float",
		Spawn = { Weight = 0.5, From = 150 },
		Params = { Fly = true, Keep = 15, Every = 2, Moons = 3, Return = 3, Windup = 0.7, ProjSpeed = 14, ProjDamage = 8, ProjRadius = 1.2, ProjLife = 1.6 },
	}),
	enemy({
		Key = "EclipseKnight",
		Name = "Eclipse Knight",
		Desc = "ELITE. A dark knight with a golden halo. Eclipses the ground around it (you walk slower inside) and lunges with its spear.",
		HP = 75, Speed = 7, Damage = 9, XP = 8, Radius = 2.4,
		Model = "EclipseKnight", Color = rgb(46, 16, 101), Accent = rgb(250, 204, 21),
		Behavior = "Eclipse", Mass = 4, CoinChance = 0.05, ItemChance = 2, MinTier = 7, Role = "Elite", Theme = "Void", AnimType = "Bob",
		Attacks = { "Eclipse every 8 s: an 8-stud dark circle, -15% speed inside for 3 s", "Spear lunge (0.8 s line)" },
		Phases = { { At = 0.5, Rate = 1.3, Name = "TOTALITY" } },
		Params = {
			EclipseEvery = 8, EclipseRadius = 8, EclipseDelay = 0.8, EclipseTime = 3, EclipseSlow = 0.85,
			Every = 6, Trigger = 14, Windup = 0.8, DashTime = 0.4, DashSpeed = 30, Rest = 0.8,
		},
	}),
	enemy({
		Key = "Final67",
		Name = "THE 67",
		Desc = "The final boss of VII THE 67: two giant floating digits and a crowned void face. Every boss you met comes back as an echo.",
		HP = 224000, Speed = 7, Damage = 26, XP = 1000, Radius = 8, -- (the finale: a 2-4 minute fight)
		Model = "Final67", Color = rgb(15, 10, 31), Accent = rgb(192, 132, 252),
		Behavior = "Boss", Mass = 160, CoinChance = 1, ItemChance = 0, Boss = true, MinTier = 7, Role = "Boss", Theme = "Void", AnimType = "Boss",
		Attacks = {
			"Phase 1: the 6 smashes where you stand, the 7 fires beams, black holes pull at the edge",
			"Phase 2 (<66%): echoes of the earlier bosses, star meteors",
			"Phase 3 (<33%): the digits fuse into 67; everything at once, the arena shrinks",
		},
		Params = {
			Title = "THE 67",
			Final = true,
			ShotRoom = 70,
			Patterns = { "SixSmash", "SevenBeams", "BlackHoles" },
			PhasePatterns = { [2] = { "EchoCall", "Meteors" } },
			PhaseSets = { [3] = { "SixSmash", "SevenBeams", "BlackHoles", "EchoCall", "Meteors", "DoomRing" } },
			EdgeErase = 6, EdgeFrom = 3,
			SixSmashEvery = 6, SmashDelay = 1.2, SmashRadius = 12, SmashDamage = 30, SmashDrops = 16, SmashDropSpeed = 13, SmashDropDamage = 9,
			SevenBeamsEvery = 7, BeamCount = 3, BeamLength = 70, BeamWidth = 5, BeamDelay = 1.1, BeamGap = 0.35, BeamDamage = 26,
			BlackHolesEvery = 14, HoleCount = 2, HoleRadius = 22, HoleSlow = 0.7, HoleTime = 9,
			EchoCallEvery = 14, EchoKeys = { "EchoMegaSix", "EchoCount", "EchoPharaoh", "EchoPenguin", "EchoDrako", "EchoOverclock" },
			MeteorsEvery = 10, MeteorCount = 9, MeteorRadius = 5, MeteorSpread = 20, MeteorDelay = 1.2, MeteorDamage = 24,
			DoomRingEvery = 8, DoomCount = 40, DoomGap = 5, DoomSpeed = 14, DoomDamage = 22, DoomDelay = 1.3,
			EraseDamage = 12,
			Coins = 400,
		},
	}),
	-- the echoes THE 67 calls back in its phase 2: shrunken earlier bosses, one signature move each
	enemy({
		Key = "EchoMegaSix", Name = "Echo of MEGA SIX", Desc = "An echo of MEGA SIX: it jumps onto you.",
		HP = 260, Speed = 8, Damage = 12, XP = 4, Radius = 3,
		Model = "MegaSix", Scale = 0.36, Color = rgb(150, 236, 136), Accent = rgb(58, 140, 50),
		Behavior = "EchoBoss", Mass = 20, CoinChance = 0, ItemChance = 0, Role = "Minion", Theme = "Void", AnimType = "Hop", Collection = false,
		Params = { Echo = "Jump", Every = 5, Windup = 1.0, AttackRadius = 7, AttackDamage = 20, Lifetime = 22 },
	}),
	enemy({
		Key = "EchoCount", Name = "Echo of COUNT SEVEN", Desc = "An echo of COUNT SEVEN: it calls bats.",
		HP = 260, Speed = 8, Damage = 12, XP = 4, Radius = 2.8,
		Model = "CountSeven", Scale = 0.36, Color = rgb(241, 228, 243), Accent = rgb(185, 28, 28),
		Behavior = "EchoBoss", Mass = 20, CoinChance = 0, ItemChance = 0, Role = "Minion", Theme = "Void", AnimType = "Float", Collection = false,
		Params = { Echo = "Bats", Every = 6, Count = 5, Key = "BuzzBat", Lifetime = 22 },
	}),
	enemy({
		Key = "EchoPharaoh", Name = "Echo of PHARAOH SIXSEVEN", Desc = "An echo of PHARAOH SIXSEVEN: its hands clap.",
		HP = 260, Speed = 7, Damage = 12, XP = 4, Radius = 3,
		Model = "PharaohSixseven", Scale = 0.36, Color = rgb(250, 204, 21), Accent = rgb(20, 184, 166),
		Behavior = "EchoBoss", Mass = 20, CoinChance = 0, ItemChance = 0, Role = "Minion", Theme = "Void", AnimType = "Float", Collection = false,
		Params = { Echo = "Clap", Every = 4.5, Windup = 1.0, AttackRadius = 6, AttackDamage = 20, Lifetime = 22 },
	}),
	enemy({
		Key = "EchoPenguin", Name = "Echo of EMPEROR PENGUIN PRIME", Desc = "An echo of the penguin: it slides at you.",
		HP = 260, Speed = 7, Damage = 12, XP = 4, Radius = 3,
		Model = "PenguinPrime", Scale = 0.36, Color = rgb(30, 41, 59), Accent = rgb(125, 211, 252),
		Behavior = "EchoBoss", Mass = 20, CoinChance = 0, ItemChance = 0, Role = "Minion", Theme = "Void", AnimType = "Bob", Collection = false,
		Params = { Echo = "Slide", Every = 4.5, Windup = 1.0, DashTime = 0.6, DashSpeed = 36, AttackDamage = 18, Lifetime = 22 },
	}),
	enemy({
		Key = "EchoDrako", Name = "Echo of DRAKO 67", Desc = "An echo of DRAKO 67: it breathes fire.",
		HP = 260, Speed = 7, Damage = 12, XP = 4, Radius = 3,
		Model = "Drako67", Scale = 0.36, Color = rgb(220, 38, 38), Accent = rgb(250, 204, 21),
		Behavior = "EchoBoss", Mass = 20, CoinChance = 0, ItemChance = 0, Role = "Minion", Theme = "Void", AnimType = "Bob", Collection = false,
		Params = { Echo = "Breath", Every = 5, Windup = 1.0, AttackRadius = 15, Half = 0.6, AttackDamage = 20, Lifetime = 22 },
	}),
	enemy({
		Key = "EchoOverclock", Name = "Echo of OVERCLOCK-6", Desc = "An echo of OVERCLOCK-6: it fires a laser.",
		HP = 260, Speed = 7, Damage = 12, XP = 4, Radius = 3,
		Model = "Overclock6", Scale = 0.36, Color = rgb(51, 65, 85), Accent = rgb(34, 211, 238),
		Behavior = "EchoBoss", Mass = 20, CoinChance = 0, ItemChance = 0, Role = "Minion", Theme = "Void", AnimType = "Float", Collection = false,
		Params = { Echo = "Laser", Every = 4.5, Windup = 1.0, Length = 50, Width = 4, AttackDamage = 20, Lifetime = 22 },
	}),
} :: any)

local EnemyData = {}
EnemyData.List = LIST
EnemyData.ByKey = {} :: { [string]: EnemyDef }
EnemyData.ById = {} :: { [number]: EnemyDef }

for id, def in LIST do
	def.Id = id
	EnemyData.ByKey[def.Key] = def
	EnemyData.ById[id] = def
end

--[[
	ELITES: a normal enemy of the current wave that the elite director (Sim/Elites.lua) turns
	into something dangerous and worth hunting: much tougher (GameConfig.Elite), a ring, a
	crest and a name plate, and 1-2 AFFIXES that change how it fights. Only these kinds can be
	elites (the harder tiers' kinds only once they are part of the wave).

	Affixes join the pool tier by tier (MinTier, shared/DifficultyData.lua index):
	  I    SWIFT, ARMORED
	  II   + VOLATILE, SUMMONER, VAMPIRIC, FROST           (the classic six)
	  III  + SHIELDED    IV + CURSED, BERSERK    V + BURNING, GRAVITY
	  VI   + THORNED, ECHO                                 VII + GILDED 67
	Kinds = the only kinds it may land on (an affix that needs attacks to repeat, ...).
]]
EnemyData.ElitePool = {
	"Husk", "Charger", "Spitter", "Splitter", "Blinker", "Brute", "Diver", "Leaper", "Summoner", "Ghost", "Sniper",
	-- harder tiers (only when they are in the wave)
	"Shielder", "Stampeder", "Wailer", "Hexer", "Cinder", "Eruptor", "Predator", "Warden",
	-- the bestiary's regulars (only when they are in the wave)
	"BooSheet", "BonkSkull", "Wrappy", "Scorp", "SnowyPal", "MagmaBun", "ImpPop", "DronePod", "StarEater",
}

-- the bestiary's own ELITE of a difficulty (Role = "Elite", its MinTier): the elite director
-- brings it next to the affix elites of the pool above (Sim/Elites)
EnemyData.TierElite = {} :: { [number]: string }
for _, def in LIST do
	if def.Role == "Elite" and def.MinTier then
		EnemyData.TierElite[def.MinTier] = def.Key
	end
end

local ECHO_KINDS = { "Charger", "Spitter", "Diver", "Leaper", "Sniper", "Stampeder", "Wailer", "Hexer", "Eruptor", "Predator", "Scorp", "SnowyPal", "ImpPop", "DronePod", "StarEater" }

EnemyData.EliteAffixes = {
	{ Key = "Swift", Name = "SWIFT", Desc = "Much faster", Speed = 1.45, MinTier = 1 },
	{ Key = "Armored", Name = "ARMORED", Desc = "Takes 35% less damage", Armor = 0.35, MinTier = 1 },
	{ Key = "Volatile", Name = "VOLATILE", Desc = "Explodes when it dies: step away", Blast = { Radius = 7, Delay = 1, Damage = 26 }, MinTier = 2 },
	{ Key = "Summoner", Name = "SUMMONER", Desc = "Calls skitters", Summon = { Every = 6, Count = 3, Key = "Skitter" }, MinTier = 2 },
	{ Key = "Vampiric", Name = "VAMPIRIC", Desc = "Heals when it hurts you", Leech = 0.12, Regen = 0.01, MinTier = 2 },
	{ Key = "Frost", Name = "FROST", Desc = "Its hits slow you", Chill = { Factor = 0.6, Time = 2 }, MinTier = 2 },
	-- the harder tiers
	{ Key = "Shielded", Name = "SHIELDED", Desc = "A shield eats the first hits; it comes back when left alone", HitShield = { Hits = 6, Recharge = 4, Every = 1 }, MinTier = 3 },
	{ Key = "Cursed", Name = "CURSED", Desc = "Draws curse circles under you", Curse = { Every = 6, Delay = 1.2, Radius = 4.5, Damage = 16, Range = 30 }, MinTier = 4 },
	{ Key = "Berserk", Name = "BERSERK", Desc = "Faster and angrier below half HP", Berserk = { At = 0.5, Speed = 1.4, Damage = 1.3 }, MinTier = 4 },
	{ Key = "Burning", Name = "BURNING", Desc = "Leaves a trail of fire", Burning = { Every = 0.8, Radius = 2.6, Time = 3, Damage = 6 }, MinTier = 5 },
	{ Key = "Gravity", Name = "GRAVITY", Desc = "Pulls at you: walking away is slower", Gravity = { Radius = 16, Slow = 0.8 }, MinTier = 5 },
	{ Key = "Thorned", Name = "THORNED", Desc = "Hitting it up close hurts you a little", Thorns = { Range = 7, Damage = 6, Every = 0.8 }, MinTier = 6 },
	{ Key = "Echo", Name = "ECHO", Desc = "Every attack comes twice", Echo = { Delay = 0.8 }, Kinds = ECHO_KINDS, MinTier = 6 },
	{ Key = "Gilded67", Name = "GILDED 67", Desc = "Golden: two more affixes at once, double coins", Gilded = { Extra = 2, Coins = 2 }, MinTier = 7 },
}
EnemyData.AffixByKey = {}
for i, a in EnemyData.EliteAffixes do
	a.Id = i
	EnemyData.AffixByKey[a.Key] = a
end

-- the affixes an elite of this kind may get on this tier
function EnemyData.AffixesFor(tier: number, kind: string?): { any }
	local out = {}
	for _, a in EnemyData.EliteAffixes do
		if (a.MinTier or 1) <= tier and (not a.Kinds or (kind ~= nil and table.find(a.Kinds, kind) ~= nil)) then
			table.insert(out, a)
		end
	end
	return out
end

-- does this enemy belong on this tier (its MinTier)?
function EnemyData.OnTier(def, tier: number): boolean
	return (def.MinTier or 1) <= tier
end

function EnemyData.Get(key: string): EnemyDef
	local def = EnemyData.ByKey[key]
	assert(def, "unknown enemy " .. tostring(key))
	return def
end

function EnemyData.IsBoss(key: string): boolean
	local def = EnemyData.ByKey[key]
	return def ~= nil and (def.Boss == true or def.MiniBoss == true)
end

-- a mini-boss of 67 TOWN (not a timeline boss)
function EnemyData.IsChampion(key: string): boolean
	local def = EnemyData.ByKey[key]
	return def ~= nil and def.Champion == true
end

return EnemyData
