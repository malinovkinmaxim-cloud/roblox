--[[
	Theme - colours and fonts. Dark glossy panels with loud neon accents: readable over a
	chaotic horde on a phone screen.
]]

local Theme = {}

local rgb = Color3.fromRGB

Theme.Colors = {
	Text = rgb(255, 255, 255),
	TextDim = rgb(190, 190, 220),
	TextDark = rgb(30, 25, 50),
	Outline = rgb(18, 14, 36),
	Panel = rgb(34, 28, 64),
	PanelLight = rgb(52, 44, 96),
	PanelDark = rgb(22, 18, 44),
	Overlay = rgb(10, 6, 24),
	Pink = rgb(255, 80, 190),
	PinkDark = rgb(190, 30, 130),
	Lime = rgb(120, 240, 80),
	LimeDark = rgb(50, 170, 40),
	Green = rgb(70, 220, 100),
	Blue = rgb(70, 170, 255),
	BlueDark = rgb(30, 100, 210),
	Purple = rgb(170, 100, 255),
	PurpleDark = rgb(110, 50, 200),
	Gold = rgb(255, 205, 50),
	GoldDark = rgb(215, 140, 20),
	Orange = rgb(255, 140, 40),
	Red = rgb(255, 60, 80),
	RedDark = rgb(170, 20, 45),
	Cyan = rgb(80, 230, 255),
	Gray = rgb(110, 110, 135),
	HP = rgb(255, 70, 90),
	XP = rgb(80, 200, 255),
	Coin = rgb(255, 205, 50),
}

Theme.Rarity = {
	Common = rgb(90, 170, 255),
	Rare = rgb(190, 100, 255),
	Legendary = rgb(255, 200, 40),
}

Theme.BannerStyles = {
	Info = { rgb(70, 170, 255), rgb(20, 60, 140) },
	Wave = { rgb(255, 150, 40), rgb(170, 60, 10) },
	Boss = { rgb(255, 60, 70), rgb(120, 10, 25) },
	Event = { rgb(255, 80, 200), rgb(110, 20, 130) },
	Secret = { rgb(255, 215, 60), rgb(150, 90, 10) },
	Victory = { rgb(255, 215, 60), rgb(160, 90, 10) },
	Reward = { rgb(120, 240, 80), rgb(30, 120, 30) },
	Sigma = { rgb(60, 60, 70), rgb(15, 15, 20) },
}

Theme.ToastColors = {
	Info = rgb(70, 170, 255),
	Success = rgb(70, 220, 100),
	Error = rgb(255, 70, 80),
	Reward = rgb(255, 205, 50),
	Achievement = rgb(255, 170, 40),
	Unlock = rgb(190, 100, 255),
}

Theme.Fonts = {
	Title = Enum.Font.LuckiestGuy,
	Bold = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamBold,
}

-- design resolution: everything is laid out for this size and scaled with UIScale
Theme.DesignSize = Vector2.new(1100, 620)

return Theme
