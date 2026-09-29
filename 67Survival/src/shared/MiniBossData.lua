--[[
	MiniBossData - the MINI-BOSSES of 67 TOWN and the rules of when they show up.

	A mini-boss is not a big enemy with more HP: each one has its own lair (shared/ArenaData),
	its own attacks and ONE mechanic that makes you move (Sim/MiniBosses.lua):
	  THE BIG QUACK  (Goober Gardens)  belly-flops where you stand: a ring of drops and a puddle
	                                    that slows you. Calls ducklings.
	  CARTZILLA      (Horde Mart Lot)  chains 3 charges along red lines, spilling hazards behind.
	                                    Prices drop from the sky.
	  JACKPOT JIMMY  (Neon Strip)      spins its reels: O = a ring of shots, X = lasers,
	                                    ! = bombs, 7 = JACKPOT (coins, and it is stunned).
	                                    Half-way down it TILTS: shielded until you break 3 coin stacks.
	  SIX & SEVEN    (The Rift)        twins. Kill one and the other revives it in 6.7 s:
	                                    kill them together.
	  TICK TOCK      (any 67 SPOT)     a clock hand of lasers sweeps around it. 67 seconds, then
	                                    the alarm rings and it escapes with its loot.

	Mini-bosses guard their lair: they come after you when you are close, walk home and heal when
	you leave. Each drops RELICS (shared/RelicData) on the ground, better in dangerous zones.

	WHEN (the run director, Sim/ArenaDirector):
	  * time      the first one lures you out after ~1:30, then one every ~1:40, always in a zone
	              you are NOT in (a reason to go somewhere)
	  * kills     every zone has a THREAT meter: kill enough there and its mini-boss wakes up
	  * level     reaching level 10 and 20 calls one right away
	  * special   TICK TOCK appears on a random 67 SPOT
	  never more than MaxAlive at once, each one rests (Cooldown) after it is beaten or leaves.
]]

local ArenaData = require(script.Parent.ArenaData)

export type MiniBoss = {
	Key: string,
	Title: string,
	Zone: string?, -- home zone (its lair); nil = roams to a 67 SPOT
	Bodies: { string }, -- EnemyData keys (the twins have two)
	MinTime: number,
	Tier: number, -- relic rarity tier (RelicData.TierWeights)
	Relics: number, -- relics dropped
	XP: number, -- XP gems burst
	Coins: number,
	Hint: string, -- one line: how to beat it
	Cooldown: number,
	Weight: number,
}

local MiniBossData = {}

MiniBossData.List = {
	{
		Key = "BigQuack",
		Title = "THE BIG QUACK",
		Zone = "Gardens",
		Bodies = { "BigQuack" },
		MinTime = 60,
		Tier = 1,
		Relics = 1,
		XP = 40,
		Coins = 30,
		Hint = "It flops where you stand. Stay off the puddles.",
		Cooldown = 80,
		Weight = 1,
	},
	{
		Key = "Cartzilla",
		Title = "CARTZILLA",
		Zone = "Lot",
		Bodies = { "Cartzilla" },
		MinTime = 60,
		Tier = 2,
		Relics = 1,
		XP = 50,
		Coins = 40,
		Hint = "Step off the red lines. Mind the spills.",
		Cooldown = 80,
		Weight = 1,
	},
	{
		Key = "JackpotJimmy",
		Title = "JACKPOT JIMMY",
		Zone = "Strip",
		Bodies = { "JackpotJimmy" },
		MinTime = 150,
		Tier = 3,
		Relics = 1,
		XP = 70,
		Coins = 67,
		Hint = "Read the reels: O ring · X lasers · ! bombs · 7 jackpot",
		Cooldown = 90,
		Weight = 1,
	},
	{
		Key = "Twins",
		Title = "SIX & SEVEN",
		Zone = "Rift",
		Bodies = { "Six", "Seven" },
		MinTime = ArenaData.RiftOpensAt + 15,
		Tier = 4,
		Relics = 2,
		XP = 100,
		Coins = 67,
		Hint = "Kill them together: 6.7 seconds or they revive.",
		Cooldown = 100,
		Weight = 1.2,
	},
	{
		Key = "TickTock",
		Title = "TICK TOCK",
		Zone = nil,
		Bodies = { "TickTock" },
		MinTime = 210,
		Tier = 3,
		Relics = 1,
		XP = 60,
		Coins = 0,
		Hint = "67 seconds. Then the alarm rings and it's gone.",
		Cooldown = 120,
		Weight = 0.6,
	},
} :: { MiniBoss }

MiniBossData.ByKey = {} :: { [string]: MiniBoss }
MiniBossData.ByZone = {} :: { [string]: MiniBoss }
for _, def in MiniBossData.List do
	MiniBossData.ByKey[def.Key] = def
	if def.Zone then
		MiniBossData.ByZone[def.Zone] = def
	end
end

-- the director (Sim/ArenaDirector)
MiniBossData.Director = {
	FirstLure = { 80, 100 }, -- seconds: the first mini-boss
	LureGap = { 85, 115 }, -- then one every ...
	MaxAlive = 2,
	WarnTime = 3, -- "MINI-BOSS APPEARED": the lair lights up, then it arrives
	LevelLures = { 10, 20 }, -- reaching these levels calls one right away
	QuietAfterBoss = 12, -- no new mini-boss this long around a big boss warning
}

-- lair behaviour (Sim/MiniBosses)
MiniBossData.Lair = {
	Aggro = 46, -- it comes for you inside this distance from it
	Leash = 30, -- ... but never further than this from its lair
	Reset = 85, -- you are this far from the lair: it walks home and heals
	Regen = 0.05, -- fraction of max HP per second while it heals at home
	LeaveAfter = 120, -- never fought for this long: it leaves
}

return MiniBossData
