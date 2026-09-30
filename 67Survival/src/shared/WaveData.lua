--[[
	WaveData - the run timeline (15 minutes) and the rare 67 EVENTS.

	Timeline entries are active from `At` (seconds) until the next entry:
	  Rate      - enemies spawned per second
	  MinAlive  - if fewer enemies are alive, they are spawned faster (never an empty screen)
	  Mix       - spawn weights by enemy key
	  Pack      - some enemies spawn in groups: { Key = count }
	  Burst     - one-shot formation when the entry starts ("Ring" around the player / "Wall")
	  Banner    - big text when the entry starts

	The BOSSES are not in here: shared/BossData.lua (3:00, 6:00, 9:00, 12:00 in their zones,
	15:00 THE FINAL ONE in the arena). The horde thins out a little around each boss so the
	walk to its lair and the fight stay readable, then grows past what it was before.

	  0-3    the basics: goobers, skitters, husks, chargers; the build takes shape
	  3-6    splitters, spitters, bombers, blinkers; the first elites
	  6-9    brutes, divers, leapers, summoners, ghosts; synergies come together
	  9-12   snipers, walls and rings of brutes; strong elites
	  12-15  the last waves: everything, as dense as it gets
	  15+    THE FINAL ONE; OVERTIME if it is still standing at 17:00
]]

local WaveData = {}

local LATE = { Goober = 1, Skitter = 2.6, Husk = 2, Charger = 2.2, Splitter = 1.6, Spitter = 1.4, Bomber = 1.6, Blinker = 1.6, Brute = 1.7, Diver = 1.5, Leaper = 1.4, Summoner = 0.7, Ghost = 1.4, Sniper = 1.1 }

WaveData.Timeline = {
	{ At = 0, Rate = 1.4, MinAlive = 8, Mix = { Goober = 1 } },
	{ At = 25, Rate = 1.9, MinAlive = 12, Mix = { Goober = 6, Skitter = 1.5 }, Pack = { Skitter = 3 } },
	{
		At = 55,
		Rate = 2.2,
		MinAlive = 18,
		Mix = { Goober = 5, Skitter = 1.5, Husk = 2 },
		Pack = { Skitter = 3 },
		Burst = { Kind = "Ring", Key = "Goober", Count = 22, Radius = 34 },
		Banner = { Title = "HERE THEY COME", Sub = "They're surrounding you" },
	},
	{ At = 90, Rate = 2.5, MinAlive = 22, Mix = { Goober = 4, Skitter = 1.6, Husk = 2.2, Charger = 1.2 }, Pack = { Skitter = 4 } },
	{
		At = 125,
		Rate = 2.9,
		MinAlive = 28,
		Mix = { Goober = 3.5, Skitter = 1.8, Husk = 2.4, Charger = 1.3, Splitter = 0.8, Spitter = 0.4 },
		Pack = { Skitter = 4 },
		Banner = { Title = "NEW ENEMIES", Sub = "Spitters keep their distance" },
	},
	{ At = 150, Rate = 3.0, MinAlive = 30, Mix = { Goober = 3, Skitter = 1.8, Husk = 2.4, Charger = 1.3, Splitter = 0.9, Spitter = 0.5, Bomber = 0.6 }, Pack = { Skitter = 4 } },
	-- BOSS 1 (3:00): a calmer minute to walk to the gardens
	{ At = 170, Rate = 2.4, MinAlive = 24, Mix = { Goober = 3, Skitter = 1.8, Husk = 2, Charger = 1, Bomber = 0.5 }, Pack = { Skitter = 4 } },
	{ At = 225, Rate = 3.6, MinAlive = 44, Mix = { Goober = 2.6, Skitter = 2, Husk = 2.4, Charger = 1.4, Splitter = 1, Spitter = 0.7, Bomber = 0.8, Blinker = 0.8 }, Pack = { Skitter = 5 } },
	{
		At = 260,
		Rate = 4.2,
		MinAlive = 55,
		Mix = { Goober = 2.5, Skitter = 2, Husk = 2.4, Charger = 1.5, Splitter = 1, Spitter = 0.8, Bomber = 0.9, Blinker = 1, Brute = 0.4, Diver = 0.8 },
		Pack = { Skitter = 5 },
		Burst = { Kind = "Ring", Key = "Husk", Count = 30, Radius = 38 },
		Banner = { Title = "THE HORDE GROWS", Sub = "Brutes and divers joined" },
	},
	{ At = 300, Rate = 4.8, MinAlive = 66, Mix = { Goober = 2, Skitter = 2.2, Husk = 2.4, Charger = 1.6, Splitter = 1.1, Spitter = 0.9, Bomber = 1, Blinker = 1.1, Brute = 0.6, Diver = 1, Leaper = 0.6, Summoner = 0.25 }, Pack = { Skitter = 6 } },
	{
		At = 330,
		Rate = 5.2,
		MinAlive = 74,
		Mix = { Goober = 2, Skitter = 2.2, Husk = 2.4, Charger = 1.7, Splitter = 1.1, Spitter = 0.9, Bomber = 1.1, Blinker = 1.1, Brute = 0.7, Diver = 1, Leaper = 0.8, Summoner = 0.3, Ghost = 0.8, Mimic = 0.1 },
		Pack = { Skitter = 6 },
		Burst = { Kind = "Wall", Key = "Charger", Count = 20 },
	},
	-- BOSS 2 (6:00)
	{ At = 350, Rate = 4, MinAlive = 60, Mix = { Goober = 2, Skitter = 2, Husk = 2.4, Charger = 1.3, Spitter = 0.8, Bomber = 0.9, Blinker = 1, Ghost = 0.7 }, Pack = { Skitter = 5 } },
	{
		At = 420,
		Rate = 6.5,
		MinAlive = 95,
		Mix = { Goober = 1.6, Skitter = 2.3, Husk = 2.4, Charger = 1.9, Splitter = 1.2, Spitter = 1, Bomber = 1.2, Blinker = 1.2, Brute = 0.9, Diver = 1.1, Leaper = 1, Summoner = 0.4, Ghost = 1, Mimic = 0.1, Sniper = 0.7 },
		Pack = { Skitter = 7 },
		Banner = { Title = "SNIPERS", Sub = "Step off the red lines" },
	},
	{
		At = 480,
		Rate = 7.5,
		MinAlive = 110,
		Mix = { Goober = 1.4, Skitter = 2.4, Husk = 2.2, Charger = 2, Splitter = 1.3, Spitter = 1.1, Bomber = 1.3, Blinker = 1.3, Brute = 1.1, Diver = 1.2, Leaper = 1.1, Summoner = 0.5, Ghost = 1.1, Mimic = 0.1, Sniper = 0.9 },
		Pack = { Skitter = 7 },
		Burst = { Kind = "Ring", Key = "Brute", Count = 10, Radius = 42 },
	},
	-- BOSS 3 (9:00)
	{ At = 530, Rate = 5, MinAlive = 80, Mix = { Goober = 1.5, Skitter = 2.2, Husk = 2.2, Charger = 1.5, Spitter = 1, Bomber = 1.1, Blinker = 1.1, Brute = 0.8, Ghost = 1, Sniper = 0.7 }, Pack = { Skitter = 6 } },
	{
		At = 600,
		Rate = 9,
		MinAlive = 135,
		Mix = { Goober = 1.2, Skitter = 2.6, Husk = 2, Charger = 2.2, Splitter = 1.5, Spitter = 1.3, Bomber = 1.5, Blinker = 1.5, Brute = 1.4, Diver = 1.4, Leaper = 1.3, Summoner = 0.6, Ghost = 1.3, Mimic = 0.1, Sniper = 1 },
		Pack = { Skitter = 8 },
		Burst = { Kind = "Wall", Key = "Brute", Count = 14 },
		Banner = { Title = "EXTREME PHASE", Sub = "Only the horde" },
	},
	{ At = 660, Rate = 10.5, MinAlive = 155, Mix = LATE, Pack = { Skitter = 9 } },
	-- BOSS 4 (12:00)
	{ At = 710, Rate = 7, MinAlive = 120, Mix = { Goober = 1.5, Skitter = 2.4, Husk = 2, Charger = 2, Splitter = 1.4, Spitter = 1.2, Bomber = 1.4, Blinker = 1.4, Brute = 1.3, Diver = 1.3, Ghost = 1.2, Sniper = 0.9 }, Pack = { Skitter = 7 } },
	{
		At = 780,
		Rate = 11.5,
		MinAlive = 170,
		Mix = LATE,
		Pack = { Skitter = 10 },
		Burst = { Kind = "Ring", Key = "Brute", Count = 12, Radius = 44 },
		Banner = { Title = "THE LAST WAVES", Sub = "Get ready for THE FINAL ONE" },
	},
	{ At = 840, Rate = 12.5, MinAlive = 180, Mix = LATE, Pack = { Skitter = 10 } },
	-- MAIN BOSS (15:00): the arena is sealed, the horde outside waits
	{ At = 890, Rate = 5, MinAlive = 60, Mix = LATE, Pack = { Skitter = 6 } },
	{
		At = 1020,
		Rate = 15,
		MinAlive = 200,
		Mix = { Skitter = 2.5, Husk = 1.5, Charger = 2.5, Splitter = 2, Spitter = 2, Bomber = 2, Blinker = 2, Brute = 2.5, Diver = 2, Leaper = 2, Ghost = 2, Sniper = 1.5 },
		Pack = { Skitter = 12 },
		Banner = { Title = "OVERTIME", Sub = "The horde never ends" },
	},
}

-- enemy stat multipliers by run time (seconds)
function WaveData.HPScale(t: number): number
	local m = t / 60
	return 1 + 0.2 * m + 0.035 * m * m
end

function WaveData.DamageScale(t: number): number
	local m = t / 60
	return 0.7 + 0.09 * m
end

function WaveData.EntryAt(t: number): (number, any)
	local index = 1
	for i, entry in WaveData.Timeline do
		if t >= entry.At then
			index = i
		end
	end
	return index, WaveData.Timeline[index]
end

--[[
	67 EVENTS: rare on purpose. "6... 7... 67 EVENT" then something unusual happens.
	The first one comes between FirstAt[1] and FirstAt[2] seconds, then one every
	Gap[1]..Gap[2] seconds, never during a boss fight, never the same twice in a row.
	MinTime: not before this run time.
]]
WaveData.Events = {
	{ Key = "Percent67", Title = "67% EVENT", Sub = "+67% damage, +67% XP, +67% enemies", Weight = 3, Duration = 20 },
	{ Key = "Chest67", Title = "67 CHEST", Sub = "A golden chest appeared. Grab it!", Weight = 2.5, Duration = 20 },
	{ Key = "Invasion67", Title = "67 INVASION", Sub = "The whole horde at once. They are weaker!", Weight = 2, Duration = 22, MinTime = 240 },
	{ Key = "Luck67", Title = "67 LUCK", Sub = "Rare cards and drops everywhere", Weight = 2, Duration = 25 },
	{ Key = "Chaos67", Title = "67 CHAOS", Sub = "Anything can happen", Weight = 2, Duration = 20 },
	{ Key = "Mode67", Title = "67 MODE", Sub = "", Weight = 2, Duration = 25, MinTime = 100 },
	{ Key = "Boss67", Title = "67 BOSS", Sub = "The next boss wears a golden crown: tougher, double loot", Weight = 0.6, Duration = 5, MinTime = 150 },
	{ Key = "The67", Title = "THE 67", Sub = "It's here. Defeat it before it leaves.", Weight = 0.5, Duration = 50, MinTime = 300 },
}
WaveData.EventByKey = {}
for _, e in WaveData.Events do
	WaveData.EventByKey[e.Key] = e
end
WaveData.EventFirstAt = { 70, 110 }
WaveData.EventGap = { 65, 105 }

-- 67 MODE picks one rule change for its duration
WaveData.Modes67 = {
	{ Key = "Tiny", Title = "TINY MODE", Sub = "Every enemy is 67% smaller and weaker", Weight = 3 },
	{ Key = "Turbo", Title = "TURBO MODE", Sub = "Everything is 67% faster", Weight = 2 },
	{ Key = "Glass", Title = "GLASS MODE", Sub = "You deal x2 damage and take x2 damage", Weight = 2 },
	{ Key = "Giant", Title = "GIANT MODE", Sub = "Enemies are huge, XP is doubled", Weight = 2 },
}

return WaveData
