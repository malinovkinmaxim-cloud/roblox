--[[
	Theme - colours and fonts. Bright, bold, readable on a phone.
]]

local Theme = {}

Theme.Colors = {
	Text = Color3.fromRGB(255, 255, 255),
	TextDark = Color3.fromRGB(35, 30, 60),
	TextDim = Color3.fromRGB(200, 205, 225),
	Outline = Color3.fromRGB(25, 20, 45),
	Panel = Color3.fromRGB(40, 36, 72),
	PanelLight = Color3.fromRGB(58, 52, 100),
	PanelDark = Color3.fromRGB(28, 25, 52),
	Green = Color3.fromRGB(70, 220, 90),
	GreenDark = Color3.fromRGB(30, 150, 55),
	Blue = Color3.fromRGB(60, 170, 255),
	BlueDark = Color3.fromRGB(30, 100, 200),
	Yellow = Color3.fromRGB(255, 210, 50),
	YellowDark = Color3.fromRGB(220, 150, 20),
	Orange = Color3.fromRGB(255, 140, 40),
	Red = Color3.fromRGB(255, 70, 80),
	RedDark = Color3.fromRGB(190, 30, 50),
	Purple = Color3.fromRGB(170, 100, 255),
	PurpleDark = Color3.fromRGB(110, 50, 200),
	Pink = Color3.fromRGB(255, 90, 190),
	Gem = Color3.fromRGB(90, 230, 255),
	Coin = Color3.fromRGB(255, 205, 60),
	Gray = Color3.fromRGB(120, 120, 140),
	GrayDark = Color3.fromRGB(80, 80, 100),
}

Theme.Fonts = {
	Title = Enum.Font.LuckiestGuy,
	Bold = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamBold,
}

Theme.ToastColors = {
	Info = Theme.Colors.Blue,
	Success = Theme.Colors.Green,
	Error = Theme.Colors.Red,
	Reward = Theme.Colors.Yellow,
	Big = Theme.Colors.Pink,
}

-- design resolution: everything is laid out for this size and scaled with UIScale
Theme.DesignSize = Vector2.new(1100, 620)

return Theme
