--[[
	WaveData - the run timeline and the random events.

	Timeline entries are active from `At` (seconds) until the next entry:
	  Rate      - enemies spawned per second
	  MinAlive  - if fewer enemies are alive, they are spawned faster (never an empty screen)
	  Mix       - spawn weights by enemy key
	  Burst     - one-shot formation when the entry starts ("Ring" around the player / "Wall")
	  Boss      - boss spawned when the entry starts ("Mid" = random from EnemyData.MidBosses)
	  Banner    - big text when the entry starts
]]

local WaveData = {}

WaveData.Timeline = {
	{ At = 0, Rate = 1.4, MinAlive = 8, Mix = { Goober = 1 } },
	{ At = 30, Rate = 2.0, MinAlive = 12, Mix = { Goober = 8, NPC = 2 } },
	{
		At = 60,
		Rate = 2.3,
		MinAlive = 18,
		Mix = { Goober = 6, NPC = 2.5, FastGuy = 1.5 },
		Burst = { Kind = "Ring", Key = "Goober", Count = 26, Radius = 34 },
		Banner = { Title = "HERE THEY COME", Sub = "They're surrounding you!" },
	},
	{ At = 120, Rate = 2.8, MinAlive = 28, Mix = { Goober = 5, NPC = 2.5, FastGuy = 2, DoubleGoober = 0.7 } },
	{
		At = 180,
		Rate = 3.3,
		MinAlive = 38,
		Mix = { Goober = 4, NPC = 2.5, FastGuy = 2, DoubleGoober = 1, ScreamingGuy = 1.6, TankNPC = 0.25 },
		Banner = { Title = "NEW ENEMIES", Sub = "Screaming Guy and Tank NPC joined the chat" },
	},
	{ At = 240, Rate = 3.8, MinAlive = 48, Mix = { Goober = 3.5, NPC = 2.5, FastGuy = 2, DoubleGoober = 1, ScreamingGuy = 1.6, TankNPC = 0.5, GlitchedNPC = 1 } },
	{
		At = 300,
		Rate = 2.8,
		MinAlive = 32,
		Mix = { Goober = 4, NPC = 2, FastGuy = 2, ScreamingGuy = 1, GlitchedNPC = 0.8 },
		Boss = "GiantBrainrot",
	},
	{
		At = 360,
		Rate = 4.6,
		MinAlive = 65,
		Mix = { Goober = 3, NPC = 2.5, FastGuy = 2, DoubleGoober = 1.2, ScreamingGuy = 1.6, TankNPC = 0.7, GlitchedNPC = 1.2, SigmaNPC = 0.9 },
	},
	{
		At = 420,
		Rate = 6.5,
		MinAlive = 90,
		Mix = { Goober = 3, NPC = 2.5, FastGuy = 2.2, DoubleGoober = 1.2, ScreamingGuy = 1.8, TankNPC = 0.9, GlitchedNPC = 1.2, SigmaNPC = 1 },
		Burst = { Kind = "Ring", Key = "NPC", Count = 40, Radius = 40 },
		Banner = { Title = "THE HORDE GROWS", Sub = "Enemies are getting stronger" },
	},
	{ At = 480, Rate = 7.5, MinAlive = 105, Mix = { Goober = 2.5, NPC = 2.5, FastGuy = 2.2, DoubleGoober = 1.4, ScreamingGuy = 1.8, TankNPC = 1.1, GlitchedNPC = 1.3, SigmaNPC = 1.1 } },
	{
		At = 540,
		Rate = 8.5,
		MinAlive = 120,
		Mix = { Goober = 2, NPC = 2.5, FastGuy = 2.4, DoubleGoober = 1.5, ScreamingGuy = 2, TankNPC = 1.3, GlitchedNPC = 1.4, SigmaNPC = 1.2 },
		Burst = { Kind = "Wall", Key = "FastGuy", Count = 30 },
	},
	{
		At = 600,
		Rate = 5,
		MinAlive = 80,
		Mix = { Goober = 2, NPC = 2.5, FastGuy = 2, ScreamingGuy = 1.5, TankNPC = 1, GlitchedNPC = 1.2, SigmaNPC = 1 },
		Boss = "Mid",
	},
	{ At = 660, Rate = 10, MinAlive = 145, Mix = { Goober = 2, NPC = 2.2, FastGuy = 2.4, DoubleGoober = 1.6, ScreamingGuy = 2.2, TankNPC = 1.5, GlitchedNPC = 1.5, SigmaNPC = 1.4 } },
	{
		At = 720,
		Rate = 12.5,
		MinAlive = 180,
		Mix = { Goober = 1.5, NPC = 2, FastGuy = 2.6, DoubleGoober = 1.8, ScreamingGuy = 2.4, TankNPC = 2, GlitchedNPC = 1.7, SigmaNPC = 1.6 },
		Burst = { Kind = "Ring", Key = "TankNPC", Count = 16, Radius = 42 },
		Banner = { Title = "EXTREME PHASE", Sub = "No thoughts. Only horde." },
	},
	{
		At = 780,
		Rate = 9,
		MinAlive = 140,
		Mix = { Goober = 2, NPC = 2, FastGuy = 2.4, DoubleGoober = 1.5, ScreamingGuy = 2, TankNPC = 1.6, GlitchedNPC = 1.5, SigmaNPC = 1.5 },
		Boss = "FinalGoober",
	},
	{
		At = 900,
		Rate = 16,
		MinAlive = 220,
		Mix = { NPC = 1.5, FastGuy = 2.5, DoubleGoober = 2, ScreamingGuy = 2.5, TankNPC = 2.5, GlitchedNPC = 2, SigmaNPC = 2 },
		Banner = { Title = "OVERTIME", Sub = "The brainrot consumes all" },
	},
}

-- enemy stat multipliers by run time (seconds)
function WaveData.HPScale(t: number): number
	local m = t / 60
	return 1 + 0.2 * m + 0.035 * m * m
end

function WaveData.DamageScale(t: number): number
	local m = t / 60
	return 0.75 + 0.1 * m
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
	Random events: rare on purpose. The first one comes between FirstAt[1] and FirstAt[2],
	then one every Gap[1]..Gap[2] seconds, never during a boss fight, never the same twice
	in a row.
]]
WaveData.Events = {
	{ Key = "GooberRain", Title = "GOOBER RAIN", Sub = "Free XP is falling from the sky", Weight = 3, Duration = 6 },
	{ Key = "NPCInvasion", Title = "NPC INVASION", Sub = "WHY ARE THEY WALKING?", Weight = 3, Duration = 14 },
	{ Key = "SigmaMoment", Title = "SIGMA MOMENT", Sub = "+50% damage, +40% speed", Weight = 2, Duration = 15 },
	{ Key = "BrainrotStorm", Title = "BRAINROT STORM", Sub = "x2 XP and lightning everywhere", Weight = 2, Duration = 18 },
	{ Key = "WhyRunning", Title = "WHY IS HE RUNNING?", Sub = "Catch him before he leaves!", Weight = 1.5, Duration = 16 },
	{ Key = "Event67", Title = "67", Sub = "", Weight = 1.1, Duration = 20 },
}
WaveData.EventByKey = {}
for _, e in WaveData.Events do
	WaveData.EventByKey[e.Key] = e
end
WaveData.EventFirstAt = { 85, 135 }
WaveData.EventGap = { 75, 125 }

-- the 67 EVENT picks one of these
WaveData.Variants67 = {
	{ Key = "Shrink", Title = "67% OF ENEMIES SHRANK", Weight = 3 },
	{ Key = "MoreXP", Title = "67% MORE XP", Weight = 2 },
	{ Key = "Damage", Title = "67% MORE DAMAGE", Weight = 2 },
	{ Key = "The67", Title = "A WILD 67 GOBLIN APPEARED", Weight = 1.5 },
}

return WaveData
