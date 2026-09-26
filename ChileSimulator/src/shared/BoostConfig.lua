--[[
	BoostConfig - timed boosts.

	Boosts are items: you collect them (daily reward, playtime gifts, chests, quests,
	achievements, events, Robux) and activate them from the BOOSTS menu whenever you like.
	Activating the same boost again ADDS its duration. Timers only run while you are online.
	Different active boosts multiply each other.
]]

local BoostConfig = {}

BoostConfig.Boosts = {
	Height2x = {
		Name = "2x Height",
		Icon = "📏",
		Duration = 15 * 60,
		Height = 2,
		Color = Color3.fromRGB(90, 220, 120),
		Description = "Double growth from everything.",
	},
	Coins2x = {
		Name = "2x Coins",
		Icon = "🪙",
		Duration = 15 * 60,
		Coins = 2,
		Color = Color3.fromRGB(255, 205, 60),
		Description = "Double coins.",
	},
	Height4x = {
		Name = "4x Height",
		Icon = "🚀",
		Duration = 10 * 60,
		Height = 4,
		Color = Color3.fromRGB(60, 200, 255),
		Description = "QUADRUPLE growth.",
	},
	AutoTap = {
		Name = "Auto Tap",
		Icon = "🤖",
		Duration = 10 * 60,
		AutoTap = true,
		Color = Color3.fromRGB(180, 120, 255),
		Description = "Taps for you. Go get a snack.",
	},
	SuperGrowth = {
		Name = "Super Growth",
		Icon = "💥",
		Duration = 5 * 60,
		Height = 10,
		Coins = 3,
		Color = Color3.fromRGB(255, 80, 120),
		Description = "x10 growth and x3 coins. Absolute chaos.",
	},
}

BoostConfig.Order = { "Height2x", "Coins2x", "Height4x", "AutoTap", "SuperGrowth" }

-- A boost can hold at most this much time (so stacking 50 boosts doesn't make sense)
BoostConfig.MaxStackedSeconds = 6 * 60 * 60

return BoostConfig
