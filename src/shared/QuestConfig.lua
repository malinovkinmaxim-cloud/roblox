--[[
	QuestConfig
	Milestone quests. Progress = a value in profile.Stats reaching Goal.
	Each quest can be claimed once.
]]

local QuestConfig = {}

QuestConfig.Order = {
	"FirstSteps",
	"ChapterOne",
	"BeatTheRival",
	"Flawless",
	"DoppelHelper",
	"IceCold",
	"Speedrunner",
	"Survivor",
}

QuestConfig.Quests = {
	FirstSteps = {
		Text = "Complete your first level",
		Stat = "LevelsCompleted",
		Goal = 1,
		Reward = { Coins = 50, XP = 50 },
	},
	ChapterOne = {
		Text = "Complete 10 different levels",
		Stat = "UniqueLevelsCompleted",
		Goal = 10,
		Reward = { Coins = 400, XP = 300 },
	},
	BeatTheRival = {
		Text = "Beat your Rival to the finish 3 times",
		Stat = "RivalWins",
		Goal = 3,
		Reward = { Coins = 150, XP = 120 },
	},
	Flawless = {
		Text = "Finish 5 levels without dying",
		Stat = "NoDeathClears",
		Goal = 5,
		Reward = { Coins = 200, XP = 150 },
	},
	DoppelHelper = {
		Text = "Let your doppelgänger press 25 buttons",
		Stat = "DoppelPresses",
		Goal = 25,
		Reward = { Coins = 120, XP = 100 },
	},
	IceCold = {
		Text = "Freeze your Shadow 10 times",
		Stat = "Freezes",
		Goal = 10,
		Reward = { Coins = 100, XP = 80 },
	},
	Speedrunner = {
		Text = "Beat the par time on 5 levels",
		Stat = "TimeBonuses",
		Goal = 5,
		Reward = { Coins = 200, XP = 150 },
	},
	Survivor = {
		Text = "Fall, burn and respawn 50 times",
		Stat = "Deaths",
		Goal = 50,
		Reward = { Coins = 75, XP = 50 },
	},
}

return QuestConfig
