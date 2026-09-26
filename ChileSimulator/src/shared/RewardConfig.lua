--[[
	RewardConfig - daily rewards, playtime gifts, daily quests, achievements, random chests.

	A reward is a table:
	  { Kind = "Coins", Taps = 300 }          coins worth 300 of YOUR taps (scales with progress)
	  { Kind = "Gems", Amount = 25 }
	  { Kind = "Boost", Id = "Height2x", Count = 1 }
	  { Kind = "Pet", Rarity = "Rare" }       a pet of that rarity from the best egg you unlocked
	  { Kind = "Pet" }                        a normal roll from the best egg you unlocked
	A list of rewards is also a reward: { {...}, {...} }.
]]

local RewardConfig = {}

-- 7 day streak. Claim once per UTC day; missing a whole day restarts from Day 1.
RewardConfig.Daily = {
	{ Day = 1, Label = "Coins", Reward = { Kind = "Coins", Taps = 400 } },
	{ Day = 2, Label = "2x Coins Boost", Reward = { Kind = "Boost", Id = "Coins2x", Count = 1 } },
	{ Day = 3, Label = "Pet", Reward = { Kind = "Pet" } },
	{ Day = 4, Label = "Gems", Reward = { Kind = "Gems", Amount = 50 } },
	{ Day = 5, Label = "2x Height Boost", Reward = { Kind = "Boost", Id = "Height2x", Count = 2 } },
	{ Day = 6, Label = "Rare Pet", Reward = { Kind = "Pet", Rarity = "Rare" } },
	{
		Day = 7,
		Label = "LEGENDARY Pet",
		Reward = { { Kind = "Pet", Rarity = "Legendary" }, { Kind = "Gems", Amount = 100 } },
	},
}

-- Session playtime gifts (minutes online in this server)
RewardConfig.Playtime = {
	{ Minutes = 5, Label = "Coins", Reward = { Kind = "Coins", Taps = 300 } },
	{ Minutes = 10, Label = "2x Height", Reward = { Kind = "Boost", Id = "Height2x", Count = 1 } },
	{ Minutes = 20, Label = "25 Gems", Reward = { Kind = "Gems", Amount = 25 } },
	{ Minutes = 30, Label = "Random Pet", Reward = { Kind = "Pet" } },
	{ Minutes = 60, Label = "Super Growth + 60 Gems", Reward = { { Kind = "Boost", Id = "SuperGrowth", Count = 1 }, { Kind = "Gems", Amount = 60 } } },
}

-- 3 daily quests. Reset every UTC day.
RewardConfig.Quests = {
	{ Id = "Taps", Text = "Make %s taps", Stat = "Taps", Goal = 1000, Reward = { Kind = "Coins", Taps = 600 }, RewardLabel = "Coins" },
	{ Id = "Grow", Text = "Grow %s", Stat = "Grown", Goal = 100000, IsLength = true, Reward = { Kind = "Gems", Amount = 20 }, RewardLabel = "20 Gems" },
	{ Id = "Rebirth", Text = "Rebirth %s time", Stat = "Rebirths", Goal = 1, Reward = { Kind = "Boost", Id = "Height2x", Count = 1 }, RewardLabel = "2x Height" },
}

-- Achievements: Stat is compared with Goal. Height goals are in cm (BestHeight).
local M = 100 -- cm per metre
RewardConfig.Achievements = {
	{ Id = "H1", Name = "First Step", Text = "Reach 1 m", Stat = "BestHeight", Goal = 1 * M, Gems = 5 },
	{ Id = "H10", Name = "Look At Me", Text = "Reach 10 m", Stat = "BestHeight", Goal = 10 * M, Gems = 10 },
	{ Id = "H100", Name = "Getting Tall", Text = "Reach 100 m", Stat = "BestHeight", Goal = 100 * M, Gems = 15 },
	{ Id = "H1K", Name = "Giant", Text = "Reach 1,000 m", Stat = "BestHeight", Goal = 1e3 * M, Gems = 25 },
	{ Id = "H10K", Name = "Head In The Clouds", Text = "Reach 10K m", Stat = "BestHeight", Goal = 1e4 * M, Gems = 35 },
	{ Id = "H1M", Name = "Sky High", Text = "Reach 1M m", Stat = "BestHeight", Goal = 1e6 * M, Gems = 50, Boost = "Coins2x" },
	{ Id = "HCL", Name = "As Long As Chile", Text = "Reach 4,300 km (the length of Chile)", Stat = "BestHeight", Goal = 4.3e6 * M, Gems = 60 },
	{ Id = "H10M", Name = "Bigger Than The City", Text = "Reach 10M m", Stat = "BestHeight", Goal = 1e7 * M, Gems = 75 },
	{ Id = "H1B", Name = "Touch The Moon", Text = "Reach 1B m", Stat = "BestHeight", Goal = 1e9 * M, Gems = 120, Boost = "Height2x" },
	{ Id = "H1T", Name = "WHAT", Text = "Reach 1T m", Stat = "BestHeight", Goal = 1e12 * M, Gems = 250 },
	{ Id = "H1Qa", Name = "Stop. Please.", Text = "Reach 1Qa m", Stat = "BestHeight", Goal = 1e15 * M, Gems = 400 },
	{ Id = "H1Sx", Name = "UNREAL", Text = "Reach 1Sx m", Stat = "BestHeight", Goal = 1e21 * M, Gems = 750 },

	{ Id = "T100", Name = "Tapper", Text = "Perform 100 taps", Stat = "Taps", Goal = 100, Gems = 3 },
	{ Id = "T1K", Name = "Warmed Up", Text = "Perform 1,000 taps", Stat = "Taps", Goal = 1e3, Gems = 10 },
	{ Id = "T10K", Name = "HOW", Text = "Perform 10,000 taps", Stat = "Taps", Goal = 1e4, Gems = 30, Boost = "AutoTap" },
	{ Id = "T100K", Name = "Finger Of Steel", Text = "Perform 100,000 taps", Stat = "Taps", Goal = 1e5, Gems = 80 },
	{ Id = "T1M", Name = "Addicted", Text = "Perform 1,000,000 taps", Stat = "Taps", Goal = 1e6, Gems = 250 },

	{ Id = "R1", Name = "Reborn", Text = "Rebirth once", Stat = "Rebirths", Goal = 1, Gems = 10 },
	{ Id = "R5", Name = "Again!", Text = "Rebirth 5 times", Stat = "Rebirths", Goal = 5, Gems = 25 },
	{ Id = "R10", Name = "Rebirth Master", Text = "Rebirth 10 times", Stat = "Rebirths", Goal = 10, Gems = 50 },
	{ Id = "R25", Name = "Loop Enjoyer", Text = "Rebirth 25 times", Stat = "Rebirths", Goal = 25, Gems = 100 },
	{ Id = "R50", Name = "Infinite Loop", Text = "Rebirth 50 times", Stat = "Rebirths", Goal = 50, Gems = 200 },
	{ Id = "R100", Name = "Beyond Rebirth", Text = "Rebirth 100 times", Stat = "Rebirths", Goal = 100, Gems = 500 },

	{ Id = "P1", Name = "First Friend", Text = "Hatch a pet", Stat = "Hatched", Goal = 1, Gems = 5 },
	{ Id = "P25", Name = "Pet Lover", Text = "Hatch 25 pets", Stat = "Hatched", Goal = 25, Gems = 20 },
	{ Id = "P250", Name = "Zookeeper", Text = "Hatch 250 pets", Stat = "Hatched", Goal = 250, Gems = 75 },
	{ Id = "PL", Name = "Shiny!", Text = "Hatch a Legendary pet", Stat = "Legendaries", Goal = 1, Gems = 25 },
	{ Id = "PS", Name = "WHAT ARE THE ODDS", Text = "Hatch a Secret pet", Stat = "Secrets", Goal = 1, Gems = 500 },

	{ Id = "Z7", Name = "Explorer", Text = "Unlock the Galaxy", Stat = "BestHeight", Goal = 1e9 * M, Gems = 50 },
	{ Id = "E1", Name = "Party Time", Text = "Take part in a server event", Stat = "Events", Goal = 1, Gems = 10 },
	{ Id = "E10", Name = "Event Hunter", Text = "Take part in 10 events", Stat = "Events", Goal = 10, Gems = 40 },
	{ Id = "C1", Name = "Treasure!", Text = "Open a random chest", Stat = "Chests", Goal = 1, Gems = 5 },
	{ Id = "C20", Name = "Chest Goblin", Text = "Open 20 chests", Stat = "Chests", Goal = 20, Gems = 40 },
}

-- Random chests spawned in the world
RewardConfig.Chest = {
	MinInterval = 150,
	MaxInterval = 240,
	Lifetime = 120, -- despawns if nobody grabs it
	GrabRange = 14,
	Table = {
		{ Weight = 40, Label = "Coins", Reward = { Kind = "Coins", Taps = 250 } },
		{ Weight = 25, Label = "10 Gems", Reward = { Kind = "Gems", Amount = 10 } },
		{ Weight = 10, Label = "2x Height", Reward = { Kind = "Boost", Id = "Height2x", Count = 1 } },
		{ Weight = 7, Label = "2x Coins", Reward = { Kind = "Boost", Id = "Coins2x", Count = 1 } },
		{ Weight = 7, Label = "Auto Tap", Reward = { Kind = "Boost", Id = "AutoTap", Count = 1 } },
		{ Weight = 8, Label = "Pet", Reward = { Kind = "Pet" } },
		{ Weight = 3, Label = "Super Growth", Reward = { Kind = "Boost", Id = "SuperGrowth", Count = 1 } },
	},
}

return RewardConfig
