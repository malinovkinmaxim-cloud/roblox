--[[
	EventConfig - short random server events ("clip moments").

	One event at a time, for everybody in the server. Everyone who taps during an event gets
	ParticipationGems when it ends.
	Visual = "Giant" / "Tiny": every client scales ALL bodies (purely visual, see BodyController).
]]

local EventConfig = {}

EventConfig.FirstDelay = 120 -- seconds after server start
EventConfig.MinInterval = 240
EventConfig.MaxInterval = 420
EventConfig.ParticipationGems = 3

EventConfig.Events = {
	MegaGrowth = {
		Name = "MEGA GROWTH",
		Icon = "🚀",
		Text = "Everyone gets x10 GROWTH!",
		Duration = 60,
		Height = 10,
		Weight = 30,
		Color = Color3.fromRGB(80, 230, 120),
	},
	GoldenMinute = {
		Name = "GOLDEN MINUTE",
		Icon = "🪙",
		Text = "x5 COINS for everyone!",
		Duration = 60,
		Coins = 5,
		Weight = 25,
		Color = Color3.fromRGB(255, 205, 50),
	},
	GiantMode = {
		Name = "GIANT MODE",
		Icon = "🗿",
		Text = "EVERYONE IS HUGE! (and x2 growth)",
		Duration = 45,
		Height = 2,
		Visual = "Giant",
		Weight = 20,
		Color = Color3.fromRGB(255, 120, 60),
	},
	TinyMode = {
		Name = "TINY MODE",
		Icon = "🐜",
		Text = "Everyone is tiny... but GROWTH x100!",
		Duration = 20,
		Height = 100,
		Visual = "Tiny",
		Weight = 10,
		Color = Color3.fromRGB(120, 200, 255),
	},
	DoubleTap = {
		Name = "DOUBLE TAP",
		Icon = "👆👆",
		Text = "Every tap counts as TWO!",
		Duration = 60,
		TapCount = 2,
		Weight = 25,
		Color = Color3.fromRGB(200, 120, 255),
	},
}

EventConfig.Order = { "MegaGrowth", "GoldenMinute", "GiantMode", "TinyMode", "DoubleTap" }

return EventConfig
