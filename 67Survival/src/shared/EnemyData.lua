--[[
	EnemyData - the horde (15 enemy types), rare specials, ELITE affixes and the bodies of every
	boss (who and when: shared/BossData.lua). Lair bosses have Champion = true (their fights:
	Sim/MiniBosses.lua), classic bosses and THE FINAL ONE use Behavior "Boss" (Sim/Bosses.lua).

	Stats are the values at minute 0; WaveManager scales HP / damage with run time.
	  HP, Speed (studs/s), Damage (contact, per hit), XP (gem value), Radius (collision, studs)
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
		HP = 2600, Speed = 7.5, Damage = 16, XP = 150, Radius = 5,
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
		HP = 2600, Speed = 9, Damage = 16, XP = 150, Radius = 5,
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
		HP = 9000, Speed = 10, Damage = 18, XP = 300, Radius = 4.5,
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
		HP = 9000, Speed = 8, Damage = 18, XP = 300, Radius = 5,
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
		HP = 18000, Speed = 9, Damage = 20, XP = 400, Radius = 5,
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
		HP = 18000, Speed = 10, Damage = 20, XP = 400, Radius = 4.6,
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
		HP = 12000, Speed = 9.5, Damage = 20, XP = 400, Radius = 4.8,
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
		HP = 65000, Speed = 8.5, Damage = 24, XP = 1000, Radius = 7,
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
		HP = 1500, Speed = 8, Damage = 14, XP = 0, Radius = 4.4,
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
		HP = 1800, Speed = 9, Damage = 16, XP = 0, Radius = 4.2,
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
		HP = 2000, Speed = 6.5, Damage = 16, XP = 0, Radius = 4.4,
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
		HP = 1300, Speed = 10, Damage = 14, XP = 0, Radius = 3.4,
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
		HP = 1300, Speed = 8.5, Damage = 16, XP = 0, Radius = 3.6,
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
		HP = 1600, Speed = 6.2, Damage = 15, XP = 0, Radius = 3.8,
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
	into something dangerous and worth hunting: much tougher (GameConfig.Elite), a ring and a
	name plate, and 1-2 AFFIXES that change how it fights. Only these kinds can be elites.
]]
EnemyData.ElitePool = { "Husk", "Charger", "Spitter", "Splitter", "Blinker", "Brute", "Diver", "Leaper", "Summoner", "Ghost", "Sniper" }

EnemyData.EliteAffixes = {
	{ Key = "Swift", Name = "SWIFT", Desc = "Much faster", Speed = 1.45 },
	{ Key = "Armored", Name = "ARMORED", Desc = "Takes 35% less damage", Armor = 0.35 },
	{ Key = "Volatile", Name = "VOLATILE", Desc = "Explodes when it dies: step away", Blast = { Radius = 7, Delay = 1, Damage = 26 } },
	{ Key = "Summoner", Name = "SUMMONER", Desc = "Calls skitters", Summon = { Every = 6, Count = 3, Key = "Skitter" } },
	{ Key = "Vampiric", Name = "VAMPIRIC", Desc = "Heals when it hurts you", Leech = 0.12, Regen = 0.01 },
	{ Key = "Frost", Name = "FROST", Desc = "Its hits slow you", Chill = { Factor = 0.6, Time = 2 } },
}
EnemyData.AffixByKey = {}
for i, a in EnemyData.EliteAffixes do
	a.Id = i
	EnemyData.AffixByKey[a.Key] = a
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
