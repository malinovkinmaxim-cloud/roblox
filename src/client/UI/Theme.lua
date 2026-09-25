--[[
	Theme - colours and fonts for all UI. Clean, modern, high contrast.
]]

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(16, 18, 28),
	Panel = Color3.fromRGB(22, 25, 38),
	PanelLight = Color3.fromRGB(34, 38, 56),
	Stroke = Color3.fromRGB(70, 80, 110),
	Text = Color3.fromRGB(245, 247, 252),
	TextDim = Color3.fromRGB(160, 168, 190),
	Cyan = Color3.fromRGB(60, 225, 255),
	Orange = Color3.fromRGB(255, 150, 50),
	Yellow = Color3.fromRGB(255, 210, 70),
	Purple = Color3.fromRGB(170, 120, 255),
	Green = Color3.fromRGB(80, 230, 140),
	Red = Color3.fromRGB(255, 70, 80),
	Pink = Color3.fromRGB(255, 80, 200),
	Coin = Color3.fromRGB(255, 205, 60),
}

Theme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Mono = Enum.Font.RobotoMono,
}

Theme.ToastColors = {
	Info = Theme.Colors.Cyan,
	Hint = Theme.Colors.Yellow,
	Success = Theme.Colors.Green,
	Error = Theme.Colors.Red,
	Debug = Theme.Colors.Purple,
}

return Theme
