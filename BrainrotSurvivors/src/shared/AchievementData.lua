--[[
	AchievementData - achievements (some secret) and daily quests.

	Achievements are checked by RewardManager from run results / profile stats:
	  Stat + Goal   -> profile.Stats[Stat] >= Goal (lifetime totals and bests)
	  Run + Goal    -> a single run's result value >= Goal
	  Flag          -> set directly by a game event (secrets)
]]

export type AchievementDef = {
	Key: string,
	Name: string,
	Desc: string,
	Icon: string,
	Coins: number,
	Secret: boolean?,
	Stat: string?,
	Run: string?,
	Goal: number?,
	Flag: boolean?,
}

local AchievementData = {}

AchievementData.List = {
	{ Key = "FirstBlood", Name = "First Blood", Desc = "Defeat your first enemy", Icon = "🗡️", Coins = 25, Stat = "Kills", Goal = 1 },
	{ Key = "Survivor5", Name = "Still Standing", Desc = "Survive 5 minutes", Icon = "⏳", Coins = 100, Stat = "BestTime", Goal = 300 },
	{ Key = "Survivor10", Name = "Built Different", Desc = "Survive 10 minutes", Icon = "⌛", Coins = 250, Stat = "BestTime", Goal = 600 },
	{ Key = "Victory", Name = "Brainrot Survivor", Desc = "Defeat THE FINAL GOOBER", Icon = "🏆", Coins = 1000, Stat = "Wins", Goal = 1 },
	{ Key = "Level20", Name = "Getting Stronger", Desc = "Reach level 20 in a run", Icon = "📈", Coins = 100, Stat = "BestLevel", Goal = 20 },
	{ Key = "Level25", Name = "Galaxy Brain", Desc = "Reach level 25 in a run", Icon = "🧠", Coins = 200, Stat = "BestLevel", Goal = 25 },
	{ Key = "Level40", Name = "Unstoppable", Desc = "Reach level 40 in a run", Icon = "🚀", Coins = 500, Stat = "BestLevel", Goal = 40 },
	{ Key = "Kills1k", Name = "Horde Handler", Desc = "Defeat 1,000 enemies", Icon = "💀", Coins = 150, Stat = "Kills", Goal = 1000 },
	{ Key = "Kills10k", Name = "Goober Genocide", Desc = "Defeat 10,000 enemies", Icon = "☠️", Coins = 500, Stat = "Kills", Goal = 10000 },
	{ Key = "Kills100k", Name = "The Final Boss Of Goobers", Desc = "Defeat 100,000 enemies", Icon = "👑", Coins = 2500, Stat = "Kills", Goal = 100000 },
	{ Key = "Run1000", Name = "One Man Army", Desc = "Defeat 1,000 enemies in one run", Icon = "⚔️", Coins = 200, Run = "Kills", Goal = 1000 },
	{ Key = "BossSlayer", Name = "Boss Slayer", Desc = "Defeat a boss or mini-boss", Icon = "🐉", Coins = 150, Stat = "Bosses", Goal = 1 },
	{ Key = "BossCollector", Name = "Boss Collector", Desc = "Defeat all 4 bosses", Icon = "📚", Coins = 800, Stat = "BossKinds", Goal = 4 },
	{ Key = "SixSeven", Name = "67", Desc = "Witness a 67 EVENT", Icon = "6️⃣", Coins = 67, Stat = "Events67", Goal = 1 },
	{ Key = "Arsenal", Name = "Arsenal", Desc = "Hold 6 weapons in one run", Icon = "🎒", Coins = 150, Run = "Weapons", Goal = 6 },
	{ Key = "FullArsenal", Name = "Walking Armory", Desc = "Hold 10 weapons in one run", Icon = "🧨", Coins = 1000, Run = "Weapons", Goal = 10 },
	{ Key = "Awakened", Name = "Awakened", Desc = "Awaken a weapon", Icon = "⚜️", Coins = 300, Run = "Awakened", Goal = 1 },
	{ Key = "RareTaste", Name = "Rare Taste", Desc = "Pick 3 rare cards in one run", Icon = "💎", Coins = 200, Run = "Rares", Goal = 3 },
	{ Key = "Rich", Name = "Brain Millionaire", Desc = "Earn 10,000 coins in total", Icon = "💰", Coins = 500, Stat = "LifetimeCoins", Goal = 10000 },
	{ Key = "Untouchable", Name = "Untouchable", Desc = "Survive the first 3 minutes without taking damage", Icon = "🫥", Coins = 300, Flag = true },
	{ Key = "Dedicated", Name = "One More Run", Desc = "Play 25 runs", Icon = "🔁", Coins = 300, Stat = "Runs", Goal = 25 },
	-- secrets
	{ Key = "GoldenGoober", Name = "Golden Goober", Desc = "Defeat a Golden Goober", Icon = "🥇", Coins = 250, Secret = true, Flag = true },
	{ Key = "SigmaStare", Name = "Sigma Stare", Desc = "Stand perfectly still for 6.7 seconds in a horde", Icon = "🗿", Coins = 167, Secret = true, Flag = true },
	{ Key = "Secret67", Name = "The Secret 67", Desc = "Be level 6 or 7 at exactly 1:07", Icon = "🔢", Coins = 267, Secret = true, Flag = true },
	{ Key = "TouchGrass", Name = "Touch Grass", Desc = "Touch the grass in the lobby", Icon = "🌿", Coins = 50, Secret = true, Flag = true },
	{ Key = "JustStanding", Name = "It Was Just Standing There", Desc = "Defeat The NPC", Icon = "😐", Coins = 400, Secret = true, Flag = true },
	{ Key = "Backrooms", Name = "No-Clip", Desc = "Find the secret room in the arena", Icon = "🚪", Coins = 200, Secret = true, Flag = true },
} :: { AchievementDef }

AchievementData.ByKey = {} :: { [string]: AchievementDef }
for _, def in AchievementData.List do
	AchievementData.ByKey[def.Key] = def
end

--[[
	Daily quests: 3 per UTC day, picked deterministically from the pool per player.
	Kind is the run counter that advances them (see RewardManager).
]]
export type QuestDef = { Key: string, Text: string, Kind: string, Goal: number, Coins: number, Single: boolean? }

AchievementData.Quests = {
	{ Key = "Kill300", Text = "Defeat 300 enemies", Kind = "Kills", Goal = 300, Coins = 100 },
	{ Key = "Kill1000", Text = "Defeat 1,000 enemies", Kind = "Kills", Goal = 1000, Coins = 200 },
	{ Key = "Kill2500", Text = "Defeat 2,500 enemies", Kind = "Kills", Goal = 2500, Coins = 350 },
	{ Key = "Survive5", Text = "Survive 5 minutes in one run", Kind = "Time", Goal = 300, Coins = 150, Single = true },
	{ Key = "Survive8", Text = "Survive 8 minutes in one run", Kind = "Time", Goal = 480, Coins = 250, Single = true },
	{ Key = "Boss1", Text = "Defeat a boss", Kind = "Bosses", Goal = 1, Coins = 200 },
	{ Key = "Level15", Text = "Reach level 15 in one run", Kind = "Level", Goal = 15, Coins = 150, Single = true },
	{ Key = "Level25", Text = "Reach level 25 in one run", Kind = "Level", Goal = 25, Coins = 250, Single = true },
	{ Key = "Rare2", Text = "Pick 2 rare cards", Kind = "Rares", Goal = 2, Coins = 150 },
	{ Key = "Gems500", Text = "Collect 500 XP gems", Kind = "Gems", Goal = 500, Coins = 120 },
	{ Key = "Runs3", Text = "Play 3 runs", Kind = "Runs", Goal = 3, Coins = 120 },
	{ Key = "Crates5", Text = "Break 5 Sus Boxes", Kind = "Crates", Goal = 5, Coins = 120 },
} :: { QuestDef }

AchievementData.QuestByKey = {} :: { [string]: QuestDef }
for _, def in AchievementData.Quests do
	AchievementData.QuestByKey[def.Key] = def
end

AchievementData.QuestsPerDay = 3

return AchievementData
