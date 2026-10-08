--[[
	BossData - EVERY boss of a run and WHEN it comes. One system, no random extra bosses:

	  03:00  BOSS 1   in the ★ zone      (GOOBER GARDENS, the 2nd physical zone of 67 TOWN)
	  06:00  BOSS 2   in the ★★ zone     (HORDE MART LOT)
	  09:00  BOSS 3   in the ★★★ zone    (NEON STRIP)
	  12:00  BOSS 4   in the ★★★★ zone   (THE RIFT)
	  15:00  MAIN BOSS  of the tier, in the 67 ARENA in the centre of the map

	Each slot draws ONE boss from its pool when the run starts (every run meets a different
	line-up). The code calls boss 1-4 "mini-bosses" / encounters (Sim/MiniBosses.lua): they
	guard the lair of their zone, come for you when you are close, walk home and heal when you
	run away, and LEAVE (no loot) when the next boss is announced. The MAIN boss waits in the
	arena; walking in seals it, and if you never come it pulls you in (Main.PullAfter).

	TIERS (shared/DifficultyData.lua index): a boss with MinTier joins its slot's pool from that
	tier on (tier III adds one new boss per slot, tier V another; tiers I-II keep the classic
	three). Every tier has its OWN main boss from the BESTIARY (Mains / MainFor, the entry's Tier):
	  I CALM MEGA SIX · II HUNT COUNT SEVEN · III HORDE PHARAOH SIXSEVEN · IV NIGHTMARE EMPEROR
	  PENGUIN PRIME · V INFERNO DRAKO 67 · VI OBLIVION OVERCLOCK-6 · VII THE 67 THE 67
	(the main bosses before it - MAMA GOOBER, THE FINAL ONE, THE HORDEMASTER, THE DREAD, THE
	FURNACE, THE ERASER, THE 67 PRIME - are still defined: a roll-back is one line in Mains)
	They share the arena, 15:00, the seal and the pull (Main).

	Every boss tests something different (Slots[i].Tests) and has:
	  Concept / Silhouette      what it is and how you recognise it from the run camera
	  Movement / Basic / Secondary / Special / AoE / Telegraphs   how it fights
	  Phases    HP thresholds: each one is announced and changes the fight
	  WeakPoint after one of its attacks it is EXPOSED for a moment (WeakPoint.Mult damage);
	            After = "*": after any of its attack series
	  Relic     its BOSS RELIC (shared/ItemData.lua): unlocked with CHIPS, then it drops from it
	            (the bosses of the harder tiers have none: Relic = nil)
	  Loot      shared/LootData.lua (Slot = the table, better for every slot)
	  HP        per body, HUNT difficulty at the slot's time; a stronger build than Slot.Level
	            meets a little more HP (Sim/MiniBosses), the tier's BossHP scales it too
	  Death     the death effect

	Combat numbers of each body (attack timings, damage) live in shared/EnemyData.lua Params;
	the fight code in Sim/MiniBosses.lua (lair bosses) and Sim/Bosses.lua (classic bosses and
	the main bosses).
	Adding a boss: an EnemyData body + an entry here + its key in a slot's Pool (+ MinTier).
]]

export type Phase = { At: number, Name: string, Text: string, Speed: number?, Rate: number? }
export type Boss = {
	Key: string,
	Title: string,
	Slot: number, -- 1..4, or 5 = a main boss
	MinTier: number?, -- lair bosses: the first tier it can be drawn on (nil = every tier)
	Tier: number?, -- main bosses: the tier it is the main boss of
	Bodies: { string },
	HP: number,
	Fused: string?, -- THE 67 PRIME: the body its twins fuse into
	FuseHP: number?, -- ... with HP x FuseHP
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
	FusePhase: { Name: string, Text: string }?,
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
	-- (the pool's harder-tier bosses are only drawn from their MinTier on)
	{ Index = 1, At = 180, Zone = "Gardens", Level = 15, Damage = 0.95, Tests = "damage · movement · positioning", Pool = { "BigQuack", "TheGoober", "TheGiant", "SirSnailsalot", "Scarecrow" } },
	{ Index = 2, At = 360, Zone = "Lot", Level = 28, Damage = 1.15, Tests = "area damage · pressure", Pool = { "Cartzilla", "TheMachine", "TickTock", "SelfCheckout", "Mannequin" } },
	{ Index = 3, At = 540, Zone = "Strip", Level = 42, Damage = 1.3, Tests = "mobility · repositioning", Pool = { "JackpotJimmy", "TheGlitch", "King67", "DJDrop", "RouletteRoller" } },
	{ Index = 4, At = 720, Zone = "Rift", Level = 55, Damage = 1.4, Tests = "the build itself", Pool = { "Twins", "TheVoid", "TheOverlord", "TheMirror", "EventHorizon" } },
}

-- the arena of the main bosses (all tiers); Key = the classic main boss (HUNT)
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

-- the main boss of each tier (shared/DifficultyData.lua index)
-- (the bestiary; the older main bosses stay in the list below for a roll-back:
--  { "MamaGoober", "TheFinalOne", "TheHordemaster", "TheDread", "TheFurnace", "TheEraser", "The67Prime" })
BossData.Mains = { "MegaSix", "CountSeven", "PharaohSixseven", "PenguinPrime", "Drako67", "Overclock6", "Final67" }

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
	---------------------------------------------------------------- THE HARDER TIERS: one more boss per slot from tier III, another from tier V
	{
		Key = "SirSnailsalot",
		Title = "SIR SNAILSALOT",
		Slot = 1,
		MinTier = 3,
		Bodies = { "SirSnailsalot" },
		HP = 2600,
		XP = 45,
		Coins = 40,
		Hint = "It rolls along the red line. Hit it when it peeks out of its shell.",
		Concept = "A knight of a snail that guards the garden beds. Slow, until it isn't.",
		Silhouette = "A huge spiral shell on a pale green slug body, two eye stalks on top.",
		Movement = "Creeps after you, then tucks in and rolls its shell down a straight line.",
		Basic = "Contact bump.",
		Secondary = "Slime spit: a fan of five slow globs.",
		Special = "Shell roll: a long straight charge; it takes half damage while tucked in.",
		AoE = "The roll leaves a slime trail that slows you.",
		Telegraphs = "Red line for every roll (1.1 s); slime stays visible (blue).",
		Phases = TWO_PHASES("Rolls twice in a row, the slime lasts longer."),
		WeakPoint = { After = "Peek", Time = 2.2, Mult = 1.6, Text = "PEEKING OUT" },
		Death = "Its shell cracks open; it slides off into the grass.",
	},
	{
		Key = "Scarecrow",
		Title = "THE SCARECROW",
		Slot = 1,
		MinTier = 5,
		Bodies = { "Scarecrow" },
		HP = 2700,
		XP = 45,
		Coins = 40,
		Hint = "Stand between its spinning arms. Its pumpkin head is soft after a spin.",
		Concept = "The gardens' scarecrow. The crows stopped being scared of it; you shouldn't.",
		Silhouette = "A wide cross of stick arms, a straw body and a glowing pumpkin head.",
		Movement = "Hops after you on its single pole.",
		Basic = "Contact bump.",
		Secondary = "Spin: its stick arms sweep a wide fan, twice.",
		Special = "Calls crows that circle and dive at you.",
		AoE = "The fan covers half of the ground around it: find the gaps between the arms.",
		Telegraphs = "Red fans (1.1 s), the second spin turned a little; crows show their dive line.",
		Phases = TWO_PHASES("Four arms, more crows."),
		WeakPoint = { After = "Spin", Time = 2.0, Mult = 1.6, Text = "PUMPKIN SOFT" },
		Death = "The straw falls out, the pumpkin rolls away.",
	},
	{
		Key = "SelfCheckout",
		Title = "SELF-CHECKOUT",
		Slot = 2,
		MinTier = 3,
		Bodies = { "SelfCheckout" },
		HP = 7200,
		XP = 70,
		Coins = 60,
		Hint = "Step off the scanner beams. UNEXPECTED ITEM: leave the circle. It errors after a scan.",
		Concept = "The Horde Mart's self-checkout. Please place the item in the bagging area.",
		Silhouette = "A white checkout pillar with a big blue screen and a scanner window.",
		Movement = "Slides after you on its little base.",
		Basic = "Contact bump.",
		Secondary = "Scanner: parallel beams sweep across the lot, one after the other.",
		Special = "UNEXPECTED ITEM: a mark under you explodes 1.5 s later and scatters items.",
		AoE = "Beams cover lanes of the lot; the mark scatters shots in every direction.",
		Telegraphs = "Red lines for the beams (1.1 s), a red circle for the mark (1.5 s).",
		Phases = TWO_PHASES("Two scanners at once, marks come faster."),
		WeakPoint = { After = "Error", Time = 2.0, Mult = 1.6, Text = "ERROR · SCREEN OPEN" },
		Death = "\"Thank you for shopping.\" The screen goes blue.",
	},
	{
		Key = "Mannequin",
		Title = "THE MANNEQUIN",
		Slot = 2,
		MinTier = 5,
		Bodies = { "Mannequin" },
		HP = 7000,
		XP = 70,
		Coins = 60,
		Hint = "Red light, green light: keep moving and it freezes. Stand still and it dashes. It topples after a dash.",
		Concept = "A store mannequin that only moves when nobody is moving.",
		Silhouette = "A tall faceless beige figure with black joints and a stiff pose.",
		Movement = "Frozen while you move. The moment you stand still it lunges at you.",
		Basic = "Contact bump.",
		Secondary = "Pose change: a ring of shots when it strikes a new pose.",
		Special = "The lunge: a long dash at you when you stop.",
		AoE = "Pose rings fill the lot while you keep moving.",
		Telegraphs = "Its plate says WATCHING / FROZEN; a red line before every lunge (1.0 s).",
		Phases = TWO_PHASES("Lunges twice, poses more often."),
		WeakPoint = { After = "Topple", Time = 2.2, Mult = 1.6, Text = "TOPPLED" },
		Death = "It falls apart into stiff limbs.",
	},
	{
		Key = "DJDrop",
		Title = "DJ DROP",
		Slot = 3,
		MinTier = 3,
		Bodies = { "DJDrop" },
		HP = 12500,
		XP = 100,
		Coins = 90,
		Hint = "Everything is on the beat: its speakers flash two beats before a ring. Stand in the gap. Hit it after the drop.",
		Concept = "The Neon Strip's DJ. The beat never stops.",
		Silhouette = "A dark DJ booth on legs with two big flashing speakers and headphones.",
		Movement = "Bobs after you, always on the beat.",
		Basic = "Contact bump.",
		Secondary = "A ring of notes with one gap, every four beats; the gap turns a little every time.",
		Special = "THE DROP: a build-up, then four rings in a row with their gaps lined up.",
		AoE = "Rings cover the whole strip: you move with the music.",
		Telegraphs = "The speakers flash two beats (1.0 s) before every ring; DROP IN 3-2-1 on its plate.",
		Phases = TWO_PHASES("Faster tempo, more drops."),
		WeakPoint = { After = "Drop", Time = 2.4, Mult = 1.6, Text = "OUT OF BREATH" },
		Death = "The record scratches. Silence.",
	},
	{
		Key = "RouletteRoller",
		Title = "ROULETTE ROLLER",
		Slot = 3,
		MinTier = 5,
		Bodies = { "RouletteRoller" },
		HP = 13000,
		XP = 100,
		Coins = 90,
		Hint = "It calls the safe colour before every spin: stand in a sector that does NOT burn. ZERO stuns it.",
		Concept = "A roulette wheel that rolls the strip looking for players to bet on.",
		Silhouette = "A big black-and-gold wheel standing on its edge with a ball on top.",
		Movement = "Rolls after you, stops to spin.",
		Basic = "Contact bump.",
		Secondary = "The ball: shots bounce out of the wheel in a spiral.",
		Special = "The spin: red or black, half of the sectors around it burn.",
		AoE = "Sectors cover the ground all around it: read, then move.",
		Telegraphs = "SAFE: RED / SAFE: BLACK on its plate (1.4 s), then the burning sectors fill red (1.3 s).",
		Phases = TWO_PHASES("Twelve sectors, faster spins."),
		WeakPoint = { After = "Zero", Time = 3.0, Mult = 2, Text = "ZERO! HIT IT" },
		Death = "The ball drops into ZERO one last time; the wheel falls flat.",
	},
	{
		Key = "TheMirror",
		Title = "THE MIRROR",
		Slot = 4,
		MinTier = 3,
		Bodies = { "TheMirror" },
		HP = 23000,
		XP = 140,
		Coins = 134,
		Hint = "It walks your path two seconds late and shoots along it: don't walk back. It cracks after its dash.",
		Concept = "A mirror from the Rift that wants to be you.",
		Silhouette = "A tall oval mirror on legs, a silver frame and a cyan glare.",
		Movement = "Follows the exact path you walked, two seconds behind you.",
		Basic = "A fan of three shards at you.",
		Secondary = "Echo: circles drop along the path you just walked.",
		Special = "The reflection dash: a long dash at you along a red line.",
		AoE = "Your own path turns dangerous behind you.",
		Telegraphs = "Circles along your path (1.1 s), a red line before the dash (1.1 s).",
		Phases = {
			{ At = 0.5, Name = "REFLECTED", Text = "Longer echoes, faster shards.", Speed = 1.2, Rate = 1.35 },
			{ At = 0.2, Name = "SHATTERING", Text = "Everything at once.", Speed = 1.3, Rate = 1.6 },
		},
		WeakPoint = { After = "Crack", Time = 2.2, Mult = 1.6, Text = "CRACKED" },
		Death = "It shatters into a thousand silver pieces.",
	},
	{
		Key = "EventHorizon",
		Title = "THE EVENT HORIZON",
		Slot = 4,
		MinTier = 5,
		Bodies = { "EventHorizon" },
		HP = 24500,
		XP = 140,
		Coins = 134,
		Hint = "It pulls gently: walking away is slow. Waves come in from the edge with a gap. On COLLAPSE, stand in a white circle.",
		Concept = "The edge of the Rift's black hole. Nothing that walks away walks fast.",
		Silhouette = "A black sphere inside a wide pale-violet ring.",
		Movement = "Drifts slowly after you; its pull pulses.",
		Basic = "Contact bump.",
		Secondary = "Ring waves roll in from the edge of its field, each with a gap.",
		Special = "COLLAPSE: everything around it burns except a few white safe circles.",
		AoE = "The pull + the waves + the collapse: you have to plan where to stand.",
		Telegraphs = "The pull shows its ring; waves are slow; COLLAPSE shows the safe circles for 1.6 s.",
		Phases = {
			{ At = 0.5, Name = "SPAGHETTIFIED", Text = "Stronger pull, more waves.", Speed = 1.2, Rate = 1.35 },
			{ At = 0.2, Name = "SINGULARITY", Text = "Fewer safe spots.", Speed = 1.3, Rate = 1.6 },
		},
		WeakPoint = { After = "Collapse", Time = 2.2, Mult = 1.6, Text = "CORE EXPOSED" },
		Death = "It folds into itself and blinks out.",
	},
	---------------------------------------------------------------- MAIN BOSSES (one per tier: BossData.Mains)
	{
		Key = "TheFinalOne",
		Title = "THE FINAL ONE",
		Slot = 5,
		Tier = 2,
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
		-- (its 67 FRAGMENT drops from HUNT's main boss now: shared/ItemData.lua Fragment67.Boss)
		Death = "The core bursts; golden 6s and 7s rain over the arena. VICTORY.",
	},
	{
		Key = "MamaGoober",
		Title = "MAMA GOOBER",
		Slot = 5,
		Tier = 1,
		Bodies = { "MamaGoober" },
		HP = 70000,
		XP = 0, -- the run is won
		Coins = 400,
		Hint = "Leave the circle before she lands. Break her eggs before they hatch. Hit her while she wobbles.",
		Concept = "The mother of every goober in 67 TOWN, waiting in the arena for whoever hurt her babies.",
		Silhouette = "A huge round green blob with pink cheeks, a tiny golden crown and a nest of eggs.",
		Movement = "Bounces after you, then belly-flops onto where you stand.",
		Basic = "Belly-flop: lands on your spot and splashes goo drops out.",
		Secondary = "Goober rain: goobers fall out of the sky all over the arena.",
		Special = "The nest: three eggs hatch into goobers in 4 s unless you break them.",
		AoE = "Phase 2: goo rings.",
		Telegraphs = "Red circle under every flop (1.4 s); the eggs shake before they hatch.",
		Phases = {
			{ At = 0.5, Name = "PHASE 2 · MAMA'S MAD", Text = "Faster flops, goo rings.", Speed = 1.15, Rate = 1.35 },
		},
		WeakPoint = { After = "BellyFlop", Time = 2.2, Mult = 1.5, Text = "WOBBLING" },
		Death = "She deflates with a long sigh; a hundred tiny goobers bounce away. VICTORY.",
	},
	{
		Key = "TheHordemaster",
		Title = "THE HORDEMASTER",
		Slot = 5,
		Tier = 3,
		Bodies = { "TheHordemaster" },
		HP = 80000,
		XP = 0,
		Coins = 400,
		Hint = "Step off the stampede lanes. Leave the formation through its gap. Break the banner: the megaphone opens.",
		Concept = "The general who shouts the horde into shape. Every wave you ever met was its order.",
		Silhouette = "A broad red-and-gold commander with a megaphone for a head and a war banner.",
		Movement = "Marches after you, stops to shout orders.",
		Basic = "Slam on your position.",
		Secondary = "Stampede lanes: herds of stampeders run down red lines.",
		Special = "Banner call: a war banner makes the horde faster until you break it.",
		AoE = "Phase 2: a shrinking ring of shielders with one gap. Phase 3: lanes from four sides, the cross in the middle is safe.",
		Telegraphs = "Red lines for every lane (1.3 s); the gap of the formation is marked; the full charge shows its lanes (1.5 s).",
		Phases = {
			{ At = 0.66, Name = "PHASE 2 · FORMATION", Text = "The horde forms a wall around you. Find the gap.", Speed = 1.15, Rate = 1.3 },
			{ At = 0.33, Name = "PHASE 3 · FULL CHARGE", Text = "Lanes from every side. The cross in the middle is safe.", Speed = 1.25, Rate = 1.55 },
		},
		WeakPoint = { After = "Banner", Time = 3.0, Mult = 1.6, Text = "MEGAPHONE OPEN" },
		Death = "Its megaphone squeals one last order; the horde scatters. VICTORY.",
	},
	{
		Key = "TheDread",
		Title = "THE DREAD",
		Slot = 5,
		Tier = 4,
		Bodies = { "TheDread" },
		HP = 80000,
		XP = 0,
		Coins = 400,
		Hint = "Shadow hands grab where you stand. Its eye sweeps the arena, then stays open. In the dark, trust the red.",
		Concept = "The nightmare under 67 TOWN's bed. It eats the light first.",
		Silhouette = "A tall indigo shadow with one pale yellow moon eye and long thin arms.",
		Movement = "Glides after you, never in a hurry.",
		Basic = "Shadow hands: circles grab at you.",
		Secondary = "Eye sweep: a beam turns across the arena.",
		Special = "Dread echoes: your own path is followed by shadows. Lights out: the arena goes dark.",
		AoE = "Phase 3: doom rings with one gap.",
		Telegraphs = "Every attack glows red even in the dark: hands (1.2 s), the sweep (1.2 s per line), echoes (1.2 s).",
		Phases = {
			{ At = 0.66, Name = "PHASE 2 · LIGHTS OUT", Text = "The arena goes dark. Your path is followed.", Speed = 1.15, Rate = 1.3 },
			{ At = 0.33, Name = "PHASE 3 · THE DREAD", Text = "Doom rings. Find the gap.", Speed = 1.25, Rate = 1.55 },
		},
		WeakPoint = { After = "EyeSweep", Time = 2.0, Mult = 1.6, Text = "EYE OPEN" },
		Death = "The moon eye closes; the lights come back on. VICTORY.",
	},
	{
		Key = "TheFurnace",
		Title = "THE FURNACE",
		Slot = 5,
		Tier = 5,
		Bodies = { "TheFurnace" },
		HP = 82000,
		XP = 0,
		Coins = 400,
		Hint = "The arena heats one sector at a time: watch the colour, step into a cold one. The door opens after it vents steam.",
		Concept = "The furnace that keeps the INFERNO burning. It brought the heat to the arena.",
		Silhouette = "A black iron golem with a chimney crown and a glowing furnace door for a chest.",
		Movement = "Stomps after you, heavy and slow.",
		Basic = "Piston slam on your position.",
		Secondary = "Ember rings with a gap.",
		Special = "The arena is split in 8 sectors: some heat up (1.5 s warning), then burn. Safe sectors change.",
		AoE = "Phase 2: a meteor shower. Phase 3: MELTDOWN, the sectors switch faster.",
		Telegraphs = "Sectors fill red for 1.5 s before they burn; slams and meteors show their circles.",
		Phases = {
			{ At = 0.66, Name = "PHASE 2 · OVERHEAT", Text = "More sectors burn. Meteors fall.", Speed = 1.15, Rate = 1.3 },
			{ At = 0.33, Name = "PHASE 3 · MELTDOWN", Text = "The door is open. Everything switches faster.", Speed = 1.25, Rate = 1.6 },
		},
		WeakPoint = { After = "Steam", Time = 2.4, Mult = 1.6, Text = "DOOR OPEN" },
		Death = "The fire goes out with a hiss; the iron cools and cracks. VICTORY.",
	},
	{
		Key = "TheEraser",
		Title = "THE ERASER",
		Slot = 5,
		Tier = 6,
		Bodies = { "TheEraser" },
		HP = 82000,
		XP = 0,
		Coins = 400,
		Hint = "White means erased: don't stand in it. Every phase eats the edge of the arena. Its tip wears out after a long swipe.",
		Concept = "OBLIVION itself: it erases whatever it touches, the arena first, then you.",
		Silhouette = "A giant white eraser with a graphite-smudged tip and sketchy lines around it.",
		Movement = "Glides after you, swipes across the arena.",
		Basic = "Erase swipe: a long wide line, then it slides along it.",
		Secondary = "Erase: white circles stay on the floor.",
		Special = "Redraw: sketched copies of elite enemies.",
		AoE = "Each phase erases the edge of the arena. Phase 3+: doom rings with one gap.",
		Telegraphs = "Swipes show their line (1.1 s), erasing circles fill first (1.2 s).",
		Phases = {
			{ At = 0.75, Name = "PHASE 2 · REDRAW", Text = "The edge is erased. Sketches join in.", Speed = 1.1, Rate = 1.2 },
			{ At = 0.5, Name = "PHASE 3 · BLANK PAGE", Text = "Less arena. Doom rings.", Speed = 1.2, Rate = 1.4 },
			{ At = 0.25, Name = "PHASE 4 · OBLIVION", Text = "Almost nothing left.", Speed = 1.3, Rate = 1.6 },
		},
		WeakPoint = { After = "Swipe", Time = 2.0, Mult = 1.6, Text = "TIP WORN" },
		Death = "It rubs itself out, crumb by crumb. VICTORY.",
	},
	{
		Key = "The67Prime",
		Title = "THE 67 PRIME",
		Slot = 5,
		Tier = 7,
		Bodies = { "PrimeSix", "PrimeSeven" },
		Fused = "The67Prime", -- both down within 6.7 s: they fuse into this body
		HP = 12000, -- SIX and SEVEN each; the fused 67 PRIME has HP x FuseHP
		FuseHP = 4.67,
		XP = 0,
		Coins = 400,
		Hint = "SIX and SEVEN must fall within 6.7 s of each other. Then they fuse: every boss you met, in one. Its 67 core opens after every series.",
		Concept = "The end of THE 67: six and seven, fused into gold, with a piece of every boss in it.",
		Silhouette = "A golden 6 and a black 7, then one huge fused golden 67 with a purple core.",
		Movement = "Phase 1: two digits. Then one giant fused 67 that holds the centre.",
		Basic = "Phase 1: fans of sixes and seven mines. Fused: belly-flops and stampede lanes.",
		Secondary = "Phase 3: shadow hands, the eye sweep, the burning sectors and the dark.",
		Special = "Phase 4: erasing, doom rings and the final 6... 7... series.",
		AoE = "Every arena mechanic of the main bosses, one after the other.",
		Telegraphs = "The same clear telegraphs as every main boss; the 6... 7... series is on a beat.",
		Phases = {
			{ At = 0.66, Name = "PHASE 3 · DARK FIRE", Text = "The dark and the burning sectors.", Speed = 1.15, Rate = 1.3 },
			{ At = 0.33, Name = "PHASE 4 · 6... 7...", Text = "Erased edges, doom rings, the final series.", Speed = 1.25, Rate = 1.55 },
		},
		FusePhase = { Name = "PHASE 2 · 67 FUSED", Text = "Six and seven become one." },
		WeakPoint = { After = "*", Time = 1.8, Mult = 1.5, Text = "67 CORE OPEN" },
		Death = "The 67 cracks down the middle; golden digits rain over the arena. VICTORY.",
	},
	---------------------------------------------------------------- THE BESTIARY's MAIN BOSSES (BossData.Mains)
	{
		Key = "MegaSix",
		Title = "MEGA SIX",
		Slot = 5,
		Tier = 1,
		Bodies = { "MegaSix" },
		HP = 140000,
		XP = 0, -- the run is won
		Coins = 400,
		Hint = "Leave the circle before it lands. Knock out the three orbiting slimes: while they live it takes 30% less damage.",
		Concept = "The king of the Meadow slimes, grown so big it curled into a 6.",
		Silhouette = "A huge green slime shaped like a fat 6, a curled tail on top, three little slimes circling it.",
		Movement = "Bounces after you, crouches, then jumps onto where you stand.",
		Basic = "Belly slam: lands on your spot, a ring of slime drops splashes out.",
		Secondary = "Slime fan: five slime balls in a fan.",
		Special = "Orbiting slimes: -30% damage taken while any of the three lives (they come back).",
		AoE = "Phase 2: SWELL: faster, calls six Gloopies.",
		Telegraphs = "Red circle under every slam (1.3 s); it crouches and flashes before a fan (1 s).",
		Phases = {
			{ At = 0.5, Name = "PHASE 2 · SWELL", Text = "It swells up: faster, and the Gloopies come.", Speed = 1.2, Rate = 1.3 },
		},
		WeakPoint = { After = "BellyFlop", Time = 2.2, Mult = 1.5, Text = "WOBBLING" },
		Death = "It pops like a balloon; a shower of tiny slimes bounces away. VICTORY.",
	},
	{
		Key = "CountSeven",
		Title = "COUNT SEVEN",
		Slot = 5,
		Tier = 2,
		Bodies = { "CountSeven" },
		HP = 140000,
		XP = 0,
		Coins = 400,
		Hint = "When it fades, it comes back BEHIND you: keep moving. Under the BLOOD MOON the bats stop only when you hurt it enough.",
		Concept = "The vampire count of the Graveyard: the 7 on his chest is the last thing his guests see.",
		Silhouette = "A huge pale chibi head, black hair swoop, a tall collar and a red-lined cape.",
		Movement = "Glides after you; vanishes into bats and steps out of the night behind you.",
		Basic = "Night step: a cape strike in an arc behind you.",
		Secondary = "Bat swarm: a ring of twelve Buzz Bats.",
		Special = "BLOOD MOON: the arena turns red, bats keep coming until you deal enough damage.",
		AoE = "Cape arcs and slams.",
		Telegraphs = "The arc of the cape strike (1.1 s), slams (1.1 s).",
		Phases = {
			{ At = 0.5, Name = "PHASE 2 · BLOOD MOON", Text = "The moon turns red. Hurt him to make it set.", Speed = 1.15, Rate = 1.3 },
		},
		WeakPoint = { After = "NightStep", Time = 1.8, Mult = 1.5, Text = "CAPE OPEN" },
		Relic = "Fragment67", -- (it breaks off in phase 2, like it did from THE FINAL ONE)
		Death = "He bursts into a cloud of bats that flutter off into the morning. VICTORY.",
	},
	{
		Key = "PharaohSixseven",
		Title = "PHARAOH SIXSEVEN",
		Slot = 5,
		Tier = 3,
		Bodies = { "PharaohSixseven" },
		HP = 80000,
		XP = 0,
		Coins = 400,
		Hint = "Dodge the whirlwinds, step out of the clap. When the tile ring spins fast, the tiles come one by one.",
		Concept = "The golden ruler of the Desert: a mask with no body, two hands and a ring of 6 and 7 tiles.",
		Silhouette = "A floating golden mask with black-and-turquoise stripes, two giant hands under it, a ring of tiles.",
		Movement = "Floats after you; the hands follow it.",
		Basic = "Clap: the hands slam together where you stand, twice.",
		Secondary = "Sandstorm: three whirlwinds sweep the arena.",
		Special = "Raises three small Sand Golems.",
		AoE = "Phase 2: the tile ring fires its tiles at you one after another.",
		Telegraphs = "Each clap shows its circle (1.1 s); the whirlwinds are visible.",
		Phases = {
			{ At = 0.5, Name = "PHASE 2 · THE RING SPINS", Text = "The tiles fly one by one.", Speed = 1.15, Rate = 1.35 },
		},
		WeakPoint = { After = "Clap", Time = 1.6, Mult = 1.5, Text = "HANDS DOWN" },
		Death = "The mask cracks; the tiles fall into the sand like dominoes. VICTORY.",
	},
	{
		Key = "PenguinPrime",
		Title = "EMPEROR PENGUIN PRIME",
		Slot = 5,
		Tier = 4,
		Bodies = { "PenguinPrime" },
		HP = 80000,
		XP = 0,
		Coins = 400,
		Hint = "The slide shows its whole path, bounces included. Step between the spikes. Icy patches slow you down.",
		Concept = "The emperor of the Frostbite: a penguin with an ice crown and a very slippery belly.",
		Silhouette = "A giant round black penguin, white belly with a blue 6, yellow beak, a crown of ice crystals.",
		Movement = "Waddles after you; slides on its belly across the arena.",
		Basic = "Belly slide: a long strip across the arena, bouncing off the edge twice.",
		Secondary = "Ice spikes in a grid.",
		Special = "FREEZE: icy patches on the ground and Snowy Pals at the edge.",
		AoE = "Spike grids and long slides.",
		Telegraphs = "The slide shows every leg (1.2 s); spikes fill their circles (1.2 s).",
		Phases = {
			{ At = 0.5, Name = "PHASE 2 · FREEZE", Text = "The arena freezes over.", Speed = 1.15, Rate = 1.3 },
		},
		WeakPoint = { After = "BellySlide", Time = 2.0, Mult = 1.5, Text = "DIZZY" },
		Death = "Its crown shatters; it slides away into the snow, spinning. VICTORY.",
	},
	{
		Key = "Drako67",
		Title = "DRAKO 67",
		Slot = 5,
		Tier = 5,
		Bodies = { "Drako67" },
		HP = 110000,
		XP = 0,
		Coins = 400,
		Hint = "Get out of the cone before it breathes. Meteors land 1.2 s after their circle. When it takes off, it lands on you.",
		Concept = "The dragon of the Volcano, with 67 scorched into its scales.",
		Silhouette = "A chibi red dragon: a huge head, three horns, small wings, a yellow belly and a fiery tail tip.",
		Movement = "Stomps after you; takes off and lands on you.",
		Basic = "Fire breath in a 90° cone.",
		Secondary = "Meteor rain all around you.",
		Special = "Take-off: lands where you stand with a shockwave ring.",
		AoE = "Phase 2: Imp Pops join, everything speeds up.",
		Telegraphs = "The cone fills before the breath (1 s), meteor circles (1.2 s), the landing circle (1.6 s).",
		Phases = {
			{ At = 0.5, Name = "PHASE 2 · WILDFIRE", Text = "Imps join the fight. Everything gets faster.", Speed = 1.25, Rate = 1.4 },
		},
		WeakPoint = { After = "Takeoff", Time = 2.0, Mult = 1.5, Text = "GROUNDED" },
		Death = "It lets out one last puff of smoke and topples over. VICTORY.",
	},
	{
		Key = "Overclock6",
		Title = "OVERCLOCK-6",
		Slot = 5,
		Tier = 6,
		Bodies = { "Overclock6" },
		HP = 82000,
		XP = 0,
		Coins = 400,
		Hint = "Follow the turning laser. Columns light up before the pixels fall. Only one OVERCLOCK has a green core: the red ones are fakes.",
		Concept = "The machine at the heart of the Cyber Glitch, running at 67 GHz.",
		Silhouette = "A giant chibi robot with a square screen face, neon ring antennas and a floating diamond core.",
		Movement = "Walks after you; teleports when it makes its holograms.",
		Basic = "Laser sweep: a line that turns round the arena.",
		Secondary = "Digital rain: a grid of columns, then falling pixels.",
		Special = "Holograms: two fakes with red cores; the real one has a green core.",
		AoE = "OVERCLOCK at 50%: +40% attack speed, the screen turns red.",
		Telegraphs = "Every laser line shows first (1.1 s), every column (1.2 s).",
		Phases = {
			{ At = 0.5, Name = "PHASE 2 · OVERCLOCK", Text = "Attack speed +40%.", Speed = 1.15, Rate = 1.4 },
		},
		WeakPoint = { After = "LaserSweep", Time = 2.0, Mult = 1.5, Text = "CORE COOLING" },
		Death = "Its screen shows a blue error, then a smiley; it powers down. VICTORY.",
	},
	{
		Key = "Final67",
		Title = "THE 67",
		Slot = 5,
		Tier = 7,
		Bodies = { "Final67" },
		HP = 140000,
		XP = 0,
		Coins = 400,
		Hint = "The 6 smashes, the 7 shoots beams, black holes pull at the edge. Then every boss comes back as an echo. At the end the digits fuse and the arena shrinks.",
		Concept = "The end of everything: the two digits that started it all, and the void face between them.",
		Silhouette = "Two giant floating digits, a 6 and a 7, around a crowned dark sphere face with huge eyes.",
		Movement = "Holds the centre; the digits drift around it.",
		Basic = "Six smash: the 6 slams where you stand.",
		Secondary = "Seven beams: lines from the 7.",
		Special = "Black holes at the edge (walking away from them is slower). Phase 2: echoes of the earlier bosses.",
		AoE = "Phase 3: the digits fuse into 67, every attack at once, the arena shrinks.",
		Telegraphs = "Every smash and beam shows first (1.1-1.2 s); the edge is erased before it hurts.",
		Phases = {
			{ At = 0.66, Name = "PHASE 2 · ECHOES", Text = "Every boss you beat comes back.", Speed = 1.1, Rate = 1.25 },
			{ At = 0.33, Name = "PHASE 3 · 67", Text = "The digits fuse. The arena shrinks.", Speed = 1.25, Rate = 1.5 },
		},
		WeakPoint = { After = "SixSmash", Time = 1.8, Mult = 1.5, Text = "67 CORE OPEN" },
		Death = "The digits crack apart; golden 6s and 7s rain over the arena. VICTORY.",
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
	if def.Fused then
		BossData.ByBody[def.Fused] = def
	end
	BossData.BySlot[def.Slot] = BossData.BySlot[def.Slot] or {}
	table.insert(BossData.BySlot[def.Slot], def)
end

function BossData.Get(key: string): Boss
	local def = BossData.ByKey[key]
	assert(def, "unknown boss " .. tostring(key))
	return def
end

-- the main boss of a tier (default: HUNT's)
function BossData.MainFor(tier: number?): Boss
	local key = BossData.Mains[math.clamp(math.floor(tier or 2), 1, #BossData.Mains)]
	return BossData.Get(key)
end

-- can this boss be drawn on this tier?
function BossData.OnTier(def: Boss, tier: number): boolean
	return (def.MinTier or 1) <= tier
end

-- the pool of a slot on a tier
function BossData.PoolFor(slot, tier: number): { string }
	local out = {}
	for _, key in slot.Pool do
		if BossData.OnTier(BossData.Get(key), tier) then
			table.insert(out, key)
		end
	end
	return out
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
