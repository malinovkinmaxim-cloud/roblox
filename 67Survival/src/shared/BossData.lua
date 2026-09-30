--[[
	BossData - EVERY boss of a run and WHEN it comes. One system, no random extra bosses:

	  03:00  BOSS 1   in the ★ zone      (GOOBER GARDENS, the 2nd physical zone of 67 TOWN)
	  06:00  BOSS 2   in the ★★ zone     (HORDE MART LOT)
	  09:00  BOSS 3   in the ★★★ zone    (NEON STRIP)
	  12:00  BOSS 4   in the ★★★★ zone   (THE RIFT)
	  15:00  MAIN BOSS  THE FINAL ONE, in the 67 ARENA in the centre of the map

	Each slot draws ONE boss from its pool when the run starts (every run meets a different
	line-up). The code calls boss 1-4 "mini-bosses" / encounters (Sim/MiniBosses.lua): they
	guard the lair of their zone, come for you when you are close, walk home and heal when you
	run away, and LEAVE (no loot) when the next boss is announced. THE FINAL ONE waits in the
	arena; walking in seals it, and if you never come it pulls you in (Main.PullAfter).

	Every boss tests something different (Slots[i].Tests) and has:
	  Concept / Silhouette      what it is and how you recognise it from the run camera
	  Movement / Basic / Secondary / Special / AoE / Telegraphs   how it fights
	  Phases    HP thresholds: each one is announced and changes the fight
	  WeakPoint after one of its attacks it is EXPOSED for a moment (WeakPoint.Mult damage)
	  Relic     its BOSS RELIC (shared/ItemData.lua): unlocked with CHIPS, then it drops from it
	  Loot      shared/LootData.lua (Slot = the table, better for every slot)
	  HP        per body, HUNT difficulty at the slot's time; a stronger build than Slot.Level
	            meets a little more HP (Sim/MiniBosses), the tier's BossHP scales it too
	  Death     the death effect

	Combat numbers of each body (attack timings, damage) live in shared/EnemyData.lua Params;
	the fight code in Sim/MiniBosses.lua (lair bosses) and Sim/Bosses.lua (classic bosses and
	THE FINAL ONE).
	Adding a boss: an EnemyData body + an entry here + its key in a slot's Pool.
]]

export type Phase = { At: number, Name: string, Text: string, Speed: number?, Rate: number? }
export type Boss = {
	Key: string,
	Title: string,
	Slot: number, -- 1..4, or 5 = the main boss
	Bodies: { string },
	HP: number,
	XP: number,
	Coins: number,
	Hint: string,
	Concept: string,
	Silhouette: string,
	Movement: string,
	Basic: string,
	Secondary: string,
	Special: string,
	AoE: string,
	Telegraphs: string,
	Phases: { Phase },
	WeakPoint: { After: string, Time: number, Mult: number, Text: string },
	Relic: string?,
	Death: string,
	Timer: number?, -- TICK TOCK: seconds after the fight starts until it escapes
}

local BossData = {}

-- the timeline. At = spawn time (s); the warning comes WarnLead seconds before
-- Damage = the boss's damage multiplier (x the tier's BossDamage), fixed per slot: a boss hits
-- as hard as its place in the run says, not harder when you meet it late
BossData.Slots = {
	{ Index = 1, At = 180, Zone = "Gardens", Level = 15, Damage = 0.95, Tests = "damage · movement · positioning", Pool = { "BigQuack", "TheGoober", "TheGiant" } },
	{ Index = 2, At = 360, Zone = "Lot", Level = 28, Damage = 1.15, Tests = "area damage · pressure", Pool = { "Cartzilla", "TheMachine", "TickTock" } },
	{ Index = 3, At = 540, Zone = "Strip", Level = 42, Damage = 1.3, Tests = "mobility · repositioning", Pool = { "JackpotJimmy", "TheGlitch", "King67" } },
	{ Index = 4, At = 720, Zone = "Rift", Level = 55, Damage = 1.4, Tests = "the build itself", Pool = { "Twins", "TheVoid", "TheOverlord" } },
}

BossData.Main = {
	Key = "TheFinalOne",
	At = 900, -- 15:00
	X = 0,
	Z = 0,
	ArenaR = 44, -- the 67 ARENA (the round plaza of 67 SQUARE): room to circle around it
	PullAfter = 45, -- seconds: you never came in, THE FINAL ONE pulls you into its arena
	Level = 66,
	Damage = 1.15, -- lots of attacks at once: each one hurts a little less
	Tests = "everything",
}

BossData.WarnLead = 10 -- "BOSS 1 IN 10": marker, arrow and minimap before it spawns
BossData.CompassLead = 20 -- extra warning with the Compass item

-- lair behaviour of bosses 1-4 (Sim/MiniBosses)
BossData.Lair = {
	Aggro = 46, -- it comes for you inside this distance
	Leash = 30, -- ... but never further than this from its lair
	Reset = 85, -- you are this far from the lair: it walks home and heals
	Regen = 0.05, -- fraction of max HP per second while it heals at home
}

local TWO_PHASES = function(text: string): { Phase }
	return {
		{ At = 0.5, Name = "ENRAGED", Text = text, Speed = 1.2, Rate = 1.35 },
	}
end

BossData.List = {
	---------------------------------------------------------------- SLOT 1: THE GARDENS
	{
		Key = "BigQuack",
		Title = "THE BIG QUACK",
		Slot = 1,
		Bodies = { "BigQuack" },
		HP = 2400,
		XP = 45,
		Coins = 40,
		Hint = "It flops where you stand. Hit it while it's belly-up.",
		Concept = "A bath duck the size of a house that guards the duck pond.",
		Silhouette = "Round yellow body, orange beak, a tiny crown of pond weed.",
		Movement = "Waddles after you, then belly-flops onto the spot you stood on.",
		Basic = "Contact bump.",
		Secondary = "Belly-flop: a ring of pond drops flies out from the landing.",
		Special = "Calls a line of ducklings that rush you.",
		AoE = "The landing leaves a slippery puddle that slows you.",
		Telegraphs = "Red circle under the flop (1.1 s), puddles stay visible.",
		Phases = TWO_PHASES("Flops faster, calls ducklings more often."),
		WeakPoint = { After = "Flop", Time = 2.2, Mult = 1.6, Text = "BELLY UP" },
		Relic = "QuackCore",
		Death = "Deflates with a squeak into a pile of feathers and a splash.",
	},
	{
		Key = "TheGoober",
		Title = "THE GOOBER",
		Slot = 1,
		Bodies = { "TheGoober" },
		HP = 2500,
		XP = 45,
		Coins = 40,
		Hint = "It leaps at you. Hit it while it wobbles after landing.",
		Concept = "The mother of all goobers: the gardens are its nursery.",
		Silhouette = "A huge green blob with googly eyes, splitters bouncing around it.",
		Movement = "Chases you, then leaps onto your position.",
		Basic = "Contact bump.",
		Secondary = "Leap: lands on the spot you stood on.",
		Special = "Spits out splitters (they split into goobers).",
		AoE = "The landing hurts everything in its circle.",
		Telegraphs = "Red circle where it will land (1.0 s).",
		Phases = TWO_PHASES("Leaps twice as often and spits more splitters."),
		WeakPoint = { After = "Leap", Time = 1.8, Mult = 1.5, Text = "WOBBLING" },
		Relic = "GooHeart",
		Death = "Pops into a rain of tiny goobers that melt away.",
	},
	{
		Key = "TheGiant",
		Title = "THE GIANT",
		Slot = 1,
		Bodies = { "TheGiant" },
		HP = 2500,
		XP = 45,
		Coins = 40,
		Hint = "Stay out of the slams. Its fist gets stuck in the ground.",
		Concept = "A stone giant woken up by the noise in the gardens.",
		Silhouette = "Tall, broad shoulders, huge fists, moss on its back.",
		Movement = "Slow, heavy steps straight at you.",
		Basic = "Contact bump.",
		Secondary = "Shockwave ring: a circle of stones rolls outwards.",
		Special = "Calls husks out of the ground.",
		AoE = "Ground slam on your position.",
		Telegraphs = "Red circle before every slam (1.1 s).",
		Phases = TWO_PHASES("Slams faster, rings get denser."),
		WeakPoint = { After = "Slam", Time = 1.8, Mult = 1.5, Text = "FIST STUCK" },
		Relic = "GiantsToe",
		Death = "Crumbles into a pile of boulders.",
	},
	---------------------------------------------------------------- SLOT 2: THE LOT
	{
		Key = "Cartzilla",
		Title = "CARTZILLA",
		Slot = 2,
		Bodies = { "Cartzilla" },
		HP = 7000,
		XP = 70,
		Coins = 60,
		Hint = "Step off the red lines. It's dizzy after a charge.",
		Concept = "A shopping cart that ate the whole Horde Mart.",
		Silhouette = "A giant red cart with a scowling bumper and flashing price tags.",
		Movement = "Chains three charges along red lines, then turns around.",
		Basic = "Contact ram.",
		Secondary = "Spills: every charge leaves puddles of spilled goods that hurt.",
		Special = "PRICE DROP: price tags crash down all around you.",
		AoE = "Spills + the price barrage cover the lot: you have to keep moving.",
		Telegraphs = "Red lines for charges (0.85 s), circles for price tags.",
		Phases = TWO_PHASES("Four charges in a row, more price tags."),
		WeakPoint = { After = "Charge", Time = 2.0, Mult = 1.6, Text = "DIZZY" },
		Relic = "CartWheel",
		Death = "Its wheels fly off; the goods scatter everywhere.",
	},
	{
		Key = "TheMachine",
		Title = "THE MACHINE",
		Slot = 2,
		Bodies = { "TheMachine" },
		HP = 7800,
		XP = 70,
		Coins = 60,
		Hint = "Lasers and missiles. It overheats after a sweep.",
		Concept = "The Horde Mart's delivery robot. It delivers pain.",
		Silhouette = "A boxy robot with a laser eye and a missile rack on its back.",
		Movement = "Rolls after you at a steady pace.",
		Basic = "Contact bump.",
		Secondary = "Missile barrage around your position.",
		Special = "Laser sweep: several beams cross the lot.",
		AoE = "Bullet ring from its chassis.",
		Telegraphs = "Circles for missiles (1.2 s), lines for lasers (1.2 s).",
		Phases = TWO_PHASES("Everything fires faster."),
		WeakPoint = { After = "Sweep", Time = 2.0, Mult = 1.5, Text = "OVERHEATED" },
		Relic = "ServoLaser",
		Death = "Sparks, smoke, a sad beep.",
	},
	{
		Key = "TickTock",
		Title = "TICK TOCK",
		Slot = 2,
		Bodies = { "TickTock" },
		HP = 6200,
		XP = 70,
		Coins = 67,
		Hint = "67 seconds from the first hit. Then the alarm rings and it runs.",
		Concept = "An alarm clock that has been late for 67 years and blames you.",
		Silhouette = "A red twin-bell alarm clock with a white face and laser hands.",
		Movement = "Walks slowly towards you while its hands spin.",
		Basic = "Contact bump.",
		Secondary = "Laser hands sweep around it (minute + hour).",
		Special = "TOCK: a slam on your position.",
		AoE = "When the alarm rings: a ring of shots in every direction.",
		Telegraphs = "The hands' lines and the TOCK circle.",
		Timer = 67,
		Phases = TWO_PHASES("The hands spin faster."),
		WeakPoint = { After = "Tock", Time = 1.6, Mult = 1.5, Text = "WOUND DOWN" },
		Relic = "ClockHand",
		Death = "Rings one last time and falls apart into gears.",
	},
	---------------------------------------------------------------- SLOT 3: THE STRIP
	{
		Key = "JackpotJimmy",
		Title = "JACKPOT JIMMY",
		Slot = 3,
		Bodies = { "JackpotJimmy" },
		HP = 13000,
		XP = 100,
		Coins = 90,
		Hint = "Read the reels: O ring · X lasers · ! bombs · 7 jackpot (it's stunned).",
		Concept = "The Neon Strip's slot machine. The house always wins.",
		Silhouette = "A tall slot machine with three spinning reels and a lever arm.",
		Movement = "Slides around its casino, spins its reels.",
		Basic = "Contact bump.",
		Secondary = "The reels decide: ring of shots, laser cross or bombs.",
		Special = "TILT: at half HP it hides behind a shield until you break 3 coin stacks.",
		AoE = "Bombs rain all around you; you must keep switching spots.",
		Telegraphs = "The reel shows what comes next; circles and lines on the ground.",
		Phases = TWO_PHASES("TILT: shielded, coin stacks appear around the casino."),
		WeakPoint = { After = "Jackpot", Time = 3.5, Mult = 2, Text = "JACKPOT!" },
		Relic = "LuckyLever",
		Death = "Pays out: coins everywhere, the lights go off.",
	},
	{
		Key = "TheGlitch",
		Title = "THE GLITCH",
		Slot = 3,
		Bodies = { "TheGlitch" },
		HP = 12000,
		XP = 100,
		Coins = 90,
		Hint = "It teleports on top of you. Move, then hit it while it buffers.",
		Concept = "A corrupted pixel monster that leaked out of the arcade.",
		Silhouette = "A flickering pink-and-cyan block creature, never quite in one place.",
		Movement = "Blinks around you; always shows up where you are.",
		Basic = "Contact bump.",
		Secondary = "Laser sweeps across the strip.",
		Special = "Teleports on top of you with a slam.",
		AoE = "Calls blinkers that flank you.",
		Telegraphs = "Circle where it will appear (0.8 s), lines for lasers.",
		Phases = TWO_PHASES("Teleports and sweeps more often."),
		WeakPoint = { After = "Teleport", Time = 1.6, Mult = 1.6, Text = "BUFFERING" },
		Relic = "GlitchedCore",
		Death = "Freezes into a blue screen, then shatters into pixels.",
	},
	{
		Key = "King67",
		Title = "THE 67 KING",
		Slot = 3,
		Bodies = { "King67" },
		HP = 13000,
		XP = 100,
		Coins = 90,
		Hint = "Double slams and spirals. Its crown slips after a double slam.",
		Concept = "The self-crowned ruler of the Strip. Six. Seven. Bow.",
		Silhouette = "A golden robot king with a giant 67 crown and a cape.",
		Movement = "Strides after you, stops to slam twice.",
		Basic = "Contact bump.",
		Secondary = "Double spiral of shots.",
		Special = "Double slam: two circles, the second one bigger.",
		AoE = "Calls a golden goblin that runs off with loot.",
		Telegraphs = "Two circles in a row (1.0 s and 0.67 s later).",
		Phases = TWO_PHASES("Spirals turn into double spirals, slams speed up."),
		WeakPoint = { After = "DoubleSlam", Time = 2.0, Mult = 1.5, Text = "CROWN SLIPPED" },
		Relic = "KingsCrown",
		Death = "The crown rolls away; the king turns to gold dust.",
	},
	---------------------------------------------------------------- SLOT 4: THE RIFT
	{
		Key = "Twins",
		Title = "SIX & SEVEN",
		Slot = 4,
		Bodies = { "Six", "Seven" },
		HP = 11000, -- each
		XP = 140,
		Coins = 134,
		Hint = "Kill them together: the other one revives its twin in 6.7 s.",
		Concept = "Two living digits that guard the altars of the Rift.",
		Silhouette = "A giant orange 6 and a purple 7 with googly eyes.",
		Movement = "6 keeps its distance and shoots, 7 walks up and lays mines.",
		Basic = "6: a fan of shots.",
		Secondary = "7: seven mines along its path.",
		Special = "The bond: a fallen twin comes back in 6.7 s at half HP.",
		AoE = "Mines + fans fill the altars: split damage or burst them down.",
		Telegraphs = "Mines show their circle before they blow (1.6 s).",
		Phases = {
			{ At = 0.5, Name = "BONDED", Text = "They fight faster together.", Speed = 1.15, Rate = 1.3 },
			{ At = 0.2, Name = "LAST DIGITS", Text = "Everything at once.", Speed = 1.25, Rate = 1.6 },
		},
		WeakPoint = { After = "Bond", Time = 6.7, Mult = 1.5, Text = "ALONE" },
		Relic = "TwinPact",
		Death = "6 and 7 fade out one after the other: 6... 7...",
	},
	{
		Key = "TheVoid",
		Title = "THE VOID",
		Slot = 4,
		Bodies = { "TheVoid" },
		HP = 24000,
		XP = 140,
		Coins = 134,
		Hint = "Stay out of the void pools. Its core opens after a spiral.",
		Concept = "The thing that lives inside the Rift. It wants the rest of the town.",
		Silhouette = "A dark purple orb with a ring of floating shards and one eye.",
		Movement = "Floats after you, teleports when you run.",
		Basic = "Contact bump.",
		Secondary = "Spiral of void shots.",
		Special = "Teleports next to you with a slam.",
		AoE = "Void pools that stay on the ground and hurt.",
		Telegraphs = "Circles for pools and the teleport.",
		Phases = {
			{ At = 0.5, Name = "UNBOUND", Text = "More pools, faster spirals.", Speed = 1.2, Rate = 1.35 },
			{ At = 0.2, Name = "COLLAPSE", Text = "It tears the Rift open.", Speed = 1.3, Rate = 1.6 },
		},
		WeakPoint = { After = "Spiral", Time = 2.0, Mult = 1.6, Text = "CORE OPEN" },
		Relic = "VoidEye",
		Death = "Implodes into a single point of light.",
	},
	{
		Key = "TheOverlord",
		Title = "THE OVERLORD",
		Slot = 4,
		Bodies = { "TheOverlord" },
		HP = 24000,
		XP = 140,
		Coins = 134,
		Hint = "It charges in a line. After a charge it's open.",
		Concept = "The general of the horde. It commands from the Rift.",
		Silhouette = "An armoured warlord with a tall helmet and a banner.",
		Movement = "Marches at you, charges in a straight line.",
		Basic = "Contact bump.",
		Secondary = "Ring of shots.",
		Special = "Calls spitters from the Rift.",
		AoE = "Charge lines cross the whole altar area.",
		Telegraphs = "Red line before every charge (1.0 s).",
		Phases = {
			{ At = 0.5, Name = "WAR CRY", Text = "It calls more of the horde.", Speed = 1.2, Rate = 1.35 },
			{ At = 0.2, Name = "LAST STAND", Text = "Relentless charges.", Speed = 1.3, Rate = 1.6 },
		},
		WeakPoint = { After = "Dash", Time = 2.0, Mult = 1.5, Text = "OPEN GUARD" },
		Relic = "OverlordBanner",
		Death = "Its banner falls; the horde around it scatters.",
	},
	---------------------------------------------------------------- MAIN BOSS
	{
		Key = "TheFinalOne",
		Title = "THE FINAL ONE",
		Slot = 5,
		Bodies = { "TheFinalOne" },
		HP = 80000,
		XP = 0, -- the run is won
		Coins = 400,
		Hint = "Three phases. Find the gap in the rings. Grab the 67 FRAGMENT if you dare.",
		Concept = "The end of every run: the horde's final form, waiting in the heart of 67 TOWN.",
		Silhouette = "A towering dark figure with a pink core and a halo of floating 6s and 7s.",
		Movement = "Holds the centre of the arena; teleports when you kite it too long.",
		Basic = "Slam on your position.",
		Secondary = "Bullet rings and spirals.",
		Special = "Phase 2: THE 67 FRAGMENT breaks off. Phase 3: DOOM RINGS with one gap.",
		AoE = "Barrages, void pools and laser sweeps across the whole arena.",
		Telegraphs = "Every attack: circles, lines, zones; doom rings show their gap.",
		Phases = {
			{ At = 0.66, Name = "PHASE 2 · THE 67", Text = "The fragment breaks off. Lasers sweep the arena.", Speed = 1.15, Rate = 1.3 },
			{ At = 0.33, Name = "PHASE 3 · THE END", Text = "Doom rings. Find the gap.", Speed = 1.3, Rate = 1.6 },
		},
		WeakPoint = { After = "Slam", Time = 1.6, Mult = 1.4, Text = "CORE EXPOSED" },
		Relic = "Fragment67",
		Death = "The core bursts; golden 6s and 7s rain over the arena. VICTORY.",
	},
} :: { Boss }

BossData.ByKey = {} :: { [string]: Boss }
BossData.ByBody = {} :: { [string]: Boss } -- EnemyData key -> its boss
BossData.BySlot = {} :: { [number]: { Boss } }
for _, def in BossData.List do
	BossData.ByKey[def.Key] = def
	for _, body in def.Bodies do
		BossData.ByBody[body] = def
	end
	BossData.BySlot[def.Slot] = BossData.BySlot[def.Slot] or {}
	table.insert(BossData.BySlot[def.Slot], def)
end

function BossData.Get(key: string): Boss
	local def = BossData.ByKey[key]
	assert(def, "unknown boss " .. tostring(key))
	return def
end

-- the slot of a zone (nil for the square)
function BossData.SlotOfZone(zoneKey: string)
	for _, slot in BossData.Slots do
		if slot.Zone == zoneKey then
			return slot
		end
	end
	return nil
end

-- "3:00" etc.
function BossData.Clock(seconds: number): string
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

return BossData
