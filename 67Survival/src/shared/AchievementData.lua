--[[
	AchievementData - achievements (some secret), daily quests and weekly challenges.

	Achievements are checked by RewardManager from run results / profile stats:
	  Stat + Goal   -> profile.Stats[Stat] >= Goal (lifetime totals and bests)
	  Run + Goal    -> a single run's summary value >= Goal
	  Flag          -> set directly by a game event (secrets, special moments)
	Rewards: Coins, optional Fragments. `Unlocks` is shown on the card (a hero, an ability
	or a cosmetic that needs this achievement).
]]

export type AchievementDef = {
	Key: string,
	Name: string,
	Desc: string,
	Coins: number,
	Fragments: number?,
	Secret: boolean?,
	Stat: string?,
	Run: string?,
	Goal: number?,
	Flag: boolean?,
	Unlocks: string?,
}

local AchievementData = {}

AchievementData.List = {
	{ Key = "FirstBlood", Name = "First Blood", Desc = "Defeat your first enemy", Coins = 25, Fragments = 1, Stat = "Kills", Goal = 1 },
	{ Key = "Survivor5", Name = "Still Standing", Desc = "Survive 5 minutes", Coins = 100, Fragments = 2, Stat = "BestTime", Goal = 300 },
	{ Key = "Survivor10", Name = "Built Different", Desc = "Survive 10 minutes", Coins = 250, Fragments = 2, Stat = "BestTime", Goal = 600 },
	{ Key = "Victory", Name = "67 Survivor", Desc = "Win a run: defeat the main boss", Coins = 1000, Fragments = 5, Stat = "Wins", Goal = 1, Unlocks = "Survivor Crown" },
	{ Key = "Level20", Name = "Getting Stronger", Desc = "Reach level 20 in a run", Coins = 100, Fragments = 1, Stat = "BestLevel", Goal = 20 },
	{ Key = "Level35", Name = "Powerhouse", Desc = "Reach level 35 in a run", Coins = 250, Fragments = 2, Stat = "BestLevel", Goal = 35 },
	{ Key = "Level50", Name = "Unstoppable", Desc = "Reach level 50 in a run", Coins = 500, Fragments = 2, Stat = "BestLevel", Goal = 50 },
	{ Key = "Kills1k", Name = "Horde Handler", Desc = "Defeat 1,000 enemies", Coins = 150, Fragments = 2, Stat = "Kills", Goal = 1000 },
	{ Key = "Kills10k", Name = "Horde Breaker", Desc = "Defeat 10,000 enemies", Coins = 500, Fragments = 3, Stat = "Kills", Goal = 10000 },
	{ Key = "Kills100k", Name = "The Horde Fears You", Desc = "Defeat 100,000 enemies", Coins = 2500, Fragments = 10, Stat = "Kills", Goal = 100000 },
	{ Key = "Run1000", Name = "One-Man Army", Desc = "Defeat 1,000 enemies in one run", Coins = 200, Fragments = 2, Run = "Kills", Goal = 1000 },
	{ Key = "Run10000", Name = "Screen Full Of Enemies", Desc = "Defeat 10,000 enemies in one run", Coins = 1000, Fragments = 3, Run = "Kills", Goal = 10000 },
	{ Key = "BossSlayer", Name = "Boss Slayer", Desc = "Defeat a boss", Coins = 150, Fragments = 3, Stat = "Bosses", Goal = 1 },
	{ Key = "BossCollector", Name = "Boss Collector", Desc = "Defeat 8 different bosses", Coins = 1500, Fragments = 5, Stat = "BossKinds", Goal = 8 },
	{ Key = "EliteHunter", Name = "Elite Hunter", Desc = "Defeat 25 elites", Coins = 300, Fragments = 2, Stat = "Elites", Goal = 25 },
	{ Key = "SixSeven", Name = "67", Desc = "Witness a 67 EVENT", Coins = 67, Fragments = 1, Stat = "Events67", Goal = 1, Unlocks = "67 Headband" },
	{ Key = "Witness67", Name = "Seen It All", Desc = "Witness all 8 different 67 events", Coins = 670, Fragments = 6, Stat = "EventKinds", Goal = 8, Unlocks = "Hero THE 67, ability 67 Blast" },
	{ Key = "Evolved", Name = "Evolution", Desc = "Evolve an ability", Coins = 200, Fragments = 2, Run = "Evolved", Goal = 1 },
	{ Key = "FiveEvolutions", Name = "Fully Evolved", Desc = "Evolve 5 abilities in one run", Coins = 1000, Fragments = 5, Run = "Evolved", Goal = 5 },
	{ Key = "Arsenal", Name = "Arsenal", Desc = "Hold 6 abilities in one run", Coins = 150, Fragments = 1, Run = "Weapons", Goal = 6 },
	{ Key = "FullArsenal", Name = "Walking Armory", Desc = "Hold 10 abilities in one run", Coins = 1000, Fragments = 3, Run = "Weapons", Goal = 10 },
	{ Key = "RareTaste", Name = "Rare Taste", Desc = "Pick 5 rare (or better) cards in one run", Coins = 200, Fragments = 1, Run = "Rares", Goal = 5 },
	{ Key = "Rich", Name = "Coin Collector", Desc = "Earn 10,000 coins in total", Coins = 500, Fragments = 2, Stat = "LifetimeCoins", Goal = 10000 },
	{ Key = "Collector25", Name = "Collector", Desc = "Collect 25 entries in the Collection Book", Coins = 250, Fragments = 2, Stat = "Collected", Goal = 25 },
	{ Key = "Collector60", Name = "Archivist", Desc = "Collect 60 entries in the Collection Book", Coins = 600, Fragments = 3, Stat = "Collected", Goal = 60 },
	{ Key = "Collector100", Name = "Completionist", Desc = "Collect 100 entries in the Collection Book", Coins = 1500, Fragments = 8, Stat = "Collected", Goal = 100 },
	{ Key = "Heroes5", Name = "Squad", Desc = "Unlock 5 heroes", Coins = 300, Fragments = 3, Stat = "HeroCount", Goal = 5 },
	{ Key = "Together", Name = "Better Together", Desc = "Finish a run in a party", Coins = 150, Fragments = 2, Stat = "PartyRuns", Goal = 1 },
	{ Key = "Untouchable", Name = "Untouchable", Desc = "Survive the first 3 minutes without taking damage", Coins = 300, Fragments = 2, Flag = true, Unlocks = "Untouchable Halo" },
	{ Key = "Dedicated", Name = "One More Run", Desc = "Play 25 runs", Coins = 300, Fragments = 3, Stat = "Runs", Goal = 25 },
	-- difficulty: a win on each tier (HighestWin = the highest tier won)
	{ Key = "WinHunt", Name = "The Real Horde", Desc = "Win on HUNT (II)", Coins = 400, Fragments = 2, Stat = "HighestWin", Goal = 2 },
	{ Key = "WinHorde", Name = "Horde Master", Desc = "Win on HORDE (III)", Coins = 800, Fragments = 4, Stat = "HighestWin", Goal = 3, Unlocks = "Horde Ribbon trail" },
	{ Key = "WinNightmare", Name = "Nightmare Walker", Desc = "Win on NIGHTMARE (IV)", Coins = 1200, Fragments = 6, Stat = "HighestWin", Goal = 4, Unlocks = "Nightmare Shatter, title" },
	{ Key = "WinInferno", Name = "Inferno Walker", Desc = "Win on INFERNO (V)", Coins = 2000, Fragments = 8, Stat = "HighestWin", Goal = 5, Unlocks = "Inferno Crown aura, title" },
	{ Key = "WinOblivion", Name = "Beyond Oblivion", Desc = "Win on OBLIVION (VI)", Coins = 3000, Fragments = 12, Stat = "HighestWin", Goal = 6, Unlocks = "Oblivion hero skin, title" },
	{ Key = "WinThe67", Name = "THE 67", Desc = "Win on THE 67 (VII)", Coins = 6700, Fragments = 20, Stat = "HighestWin", Goal = 7, Unlocks = "Crown of 67, title" },
	-- secrets (the collection shows them as ??? until found)
	{ Key = "GoldenGoober", Name = "Golden Goober", Desc = "Defeat a Golden Goober", Coins = 250, Secret = true, Flag = true, Unlocks = "Golden Antenna" },
	{ Key = "SigmaStare", Name = "Sigma Stare", Desc = "Stand perfectly still for 6.7 seconds in a horde", Coins = 167, Secret = true, Flag = true, Unlocks = "Secret ability Sigma Stare" },
	{ Key = "Secret67", Name = "The Secret 67", Desc = "Be level 6 or 7 at exactly 1:07", Coins = 267, Secret = true, Flag = true },
	{ Key = "TouchGrass", Name = "Touch Grass", Desc = "Touch the grass in the lobby", Coins = 50, Secret = true, Flag = true, Unlocks = "Secret passive Touch Grass" },
	{ Key = "Backrooms", Name = "No-Clip", Desc = "Find the secret room in the arena", Coins = 200, Secret = true, Flag = true },
	{ Key = "OneHP", Name = "1 HP Club", Desc = "Survive 5 seconds at 1-2% HP", Coins = 167, Secret = true, Flag = true },
	{ Key = "DefeatThe67", Name = "It Was Real", Desc = "Defeat THE 67 before it leaves", Coins = 670, Fragments = 5, Secret = true, Flag = true, Unlocks = "Secret hero THE UNKNOWN" },
	-- secrets of 67 LAND (the lobby event map)
	{ Key = "Nowhere", Name = "Stairs to Nowhere", Desc = "Climb the stairs to nowhere in 67 LAND", Coins = 67, Secret = true, Flag = true },
	{ Key = "UnderBridge", Name = "Bridge Toll", Desc = "Find what lives under the bridge to THE 67", Coins = 67, Secret = true, Flag = true },
	{ Key = "Throne67", Name = "Not Your Throne", Desc = "Sit on the throne of 67", Coins = 67, Secret = true, Flag = true },
	{ Key = "Button67", Name = "Do Not Press", Desc = "Press the button. 67 times.", Coins = 67, Secret = true, Flag = true },
	-- secrets of 67 TOWN (the battle map)
	{ Key = "Parked67", Name = "Perfect Parking", Desc = "Find parking space 67 in the Horde Mart Lot", Coins = 67, Secret = true, Flag = true },
	{ Key = "RiftCrack", Name = "Mind the Gap", Desc = "Find the crack in THE RIFT", Coins = 167, Secret = true, Flag = true },
	{ Key = "OnTime", Name = "Right On Time", Desc = "Defeat TICK TOCK before its alarm rings", Coins = 167, Secret = true, Flag = true },
} :: { AchievementDef }

AchievementData.ByKey = {} :: { [string]: AchievementDef }
for _, def in AchievementData.List do
	AchievementData.ByKey[def.Key] = def
end

-- secrets of the Collection Book (achievement keys)
AchievementData.Secrets = { "Secret67", "SigmaStare", "GoldenGoober", "TouchGrass", "Backrooms", "OneHP", "DefeatThe67", "Untouchable", "Nowhere", "UnderBridge", "Throne67", "Button67", "Parked67", "RiftCrack", "OnTime" }

--[[
	Daily quests: 3 per UTC day, picked deterministically from the pool per player.
	Kind is the run counter that advances them (see RewardManager.QuestProgress).
]]
export type QuestDef = { Key: string, Text: string, Kind: string, Goal: number, Coins: number, Fragments: number?, Single: boolean? }

AchievementData.Quests = {
	{ Key = "Kill300", Text = "Defeat 300 enemies", Kind = "Kills", Goal = 300, Coins = 100, Fragments = 1 },
	{ Key = "Kill1000", Text = "Defeat 1,000 enemies", Kind = "Kills", Goal = 1000, Coins = 200, Fragments = 1 },
	{ Key = "Kill2500", Text = "Defeat 2,500 enemies", Kind = "Kills", Goal = 2500, Coins = 350, Fragments = 2 },
	{ Key = "Survive5", Text = "Survive 5 minutes in one run", Kind = "Time", Goal = 300, Coins = 150, Fragments = 1, Single = true },
	{ Key = "Survive8", Text = "Survive 8 minutes in one run", Kind = "Time", Goal = 480, Coins = 250, Fragments = 2, Single = true },
	{ Key = "Boss1", Text = "Defeat a boss", Kind = "Bosses", Goal = 1, Coins = 200, Fragments = 2 },
	{ Key = "Level15", Text = "Reach level 15 in one run", Kind = "Level", Goal = 15, Coins = 150, Fragments = 1, Single = true },
	{ Key = "Level25", Text = "Reach level 25 in one run", Kind = "Level", Goal = 25, Coins = 250, Fragments = 2, Single = true },
	{ Key = "Rare2", Text = "Pick 2 rare (or better) cards", Kind = "Rares", Goal = 2, Coins = 150, Fragments = 1 },
	{ Key = "Gems500", Text = "Collect 500 XP crystals", Kind = "Gems", Goal = 500, Coins = 120, Fragments = 1 },
	{ Key = "Runs3", Text = "Play 3 runs", Kind = "Runs", Goal = 3, Coins = 120, Fragments = 2 },
	{ Key = "Crates5", Text = "Break 5 loot boxes", Kind = "Crates", Goal = 5, Coins = 120, Fragments = 1 },
	{ Key = "Event1", Text = "Witness a 67 event", Kind = "Events67", Goal = 1, Coins = 150, Fragments = 1 },
	{ Key = "Evolve1", Text = "Evolve an ability", Kind = "Evolved", Goal = 1, Coins = 200, Fragments = 2 },
} :: { QuestDef }

AchievementData.QuestByKey = {} :: { [string]: QuestDef }
for _, def in AchievementData.Quests do
	AchievementData.QuestByKey[def.Key] = def
end

AchievementData.QuestsPerDay = 3

--[[
	Weekly challenges: 3 per week (weeks start Monday 00:00 UTC), bigger goals, the main
	steady source of FRAGMENTS besides runs.
]]
AchievementData.Weekly = {
	{ Key = "WKills", Text = "Defeat 15,000 enemies", Kind = "Kills", Goal = 15000, Coins = 500, Fragments = 4 },
	{ Key = "WBosses", Text = "Defeat 8 bosses", Kind = "Bosses", Goal = 8, Coins = 500, Fragments = 4 },
	{ Key = "WEvents", Text = "Witness 6 67 events", Kind = "Events67", Goal = 6, Coins = 400, Fragments = 4 },
	{ Key = "WEvolve", Text = "Evolve 4 abilities", Kind = "Evolved", Goal = 4, Coins = 500, Fragments = 5 },
	{ Key = "WLong", Text = "Survive 10 minutes in 2 runs", Kind = "LongRuns", Goal = 2, Coins = 600, Fragments = 5 },
	{ Key = "WHeroes", Text = "Play runs with 3 different heroes", Kind = "Heroes", Goal = 3, Coins = 400, Fragments = 3 },
	{ Key = "WFragments", Text = "Pick up 6 fragments in runs", Kind = "Fragments", Goal = 6, Coins = 400, Fragments = 3 },
	{ Key = "WRuns", Text = "Play 12 runs", Kind = "Runs", Goal = 12, Coins = 500, Fragments = 4 },
	{ Key = "WWin", Text = "Win a run", Kind = "Wins", Goal = 1, Coins = 800, Fragments = 6 },
	{ Key = "WParty", Text = "Finish 3 runs in a party", Kind = "PartyRuns", Goal = 3, Coins = 400, Fragments = 3 },
} :: { QuestDef }

AchievementData.WeeklyByKey = {} :: { [string]: QuestDef }
for _, def in AchievementData.Weekly do
	AchievementData.WeeklyByKey[def.Key] = def
end

AchievementData.WeeklyPerWeek = 3

return AchievementData
