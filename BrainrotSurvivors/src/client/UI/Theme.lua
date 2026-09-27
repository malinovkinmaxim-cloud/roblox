--[[
	Theme - one small, consistent colour system.

	  neutral dark surfaces (semi-transparent, the world stays visible behind the UI)
	  white text
	  ONE primary accent  (Accent - hot pink: PLAY, XP, selected tabs, the important button)
	  ONE secondary accent (Gold - coins, rewards, legendary)
	  Red   only for danger / damage / locked / errors
	  Green only for success / owned / selected / claim

	Loud meme colours are reserved for special moments (67 EVENT, rare cards).
]]

local Theme = {}

local rgb = Color3.fromRGB

local Accent = rgb(255, 64, 150)
local AccentDark = rgb(196, 30, 112)
local Gold = rgb(255, 196, 64)
local GoldDark = rgb(204, 146, 30)
local Success = rgb(70, 214, 120)
local SuccessDark = rgb(40, 150, 82)
local Danger = rgb(255, 70, 86)
local DangerDark = rgb(170, 30, 50)
local Surface = rgb(20, 18, 32)
local SurfaceLight = rgb(38, 35, 58)
local SurfaceDark = rgb(12, 11, 20)
local Neutral = rgb(52, 49, 76) -- secondary buttons

Theme.Colors = {
	-- semantic
	Text = rgb(255, 255, 255),
	TextDim = rgb(172, 168, 198),
	TextMuted = rgb(118, 114, 146),
	Surface = Surface,
	SurfaceLight = SurfaceLight,
	SurfaceDark = SurfaceDark,
	Border = rgb(255, 255, 255),
	Overlay = rgb(6, 5, 14),
	Accent = Accent,
	AccentDark = AccentDark,
	-- calmer accent for the many "buy" buttons in a grid (PLAY keeps the loud one)
	AccentSoft = rgb(150, 44, 104),
	Gold = Gold,
	GoldDark = GoldDark,
	Success = Success,
	SuccessDark = SuccessDark,
	Danger = Danger,
	DangerDark = DangerDark,
	Neutral = Neutral,
	HP = Danger,
	XP = Accent,
	Coin = Gold,
	Rare = rgb(168, 118, 255),

	-- older names used around the code, mapped onto the palette above
	Outline = SurfaceDark,
	Panel = Surface,
	PanelLight = SurfaceLight,
	PanelDark = SurfaceDark,
	Pink = Accent,
	PinkDark = AccentDark,
	Lime = Success,
	LimeDark = SuccessDark,
	Green = Success,
	Blue = Neutral,
	BlueDark = SurfaceLight,
	Purple = rgb(168, 118, 255),
	PurpleDark = rgb(96, 60, 170),
	Orange = Gold,
	Red = Danger,
	RedDark = DangerDark,
	Cyan = rgb(130, 210, 255),
	Gray = Neutral,
}

-- surface transparency: panels let the world show through
Theme.Glass = 0.18
Theme.GlassStrong = 0.08
Theme.BorderTransparency = 0.86

Theme.Rarity = {
	Common = rgb(150, 158, 190),
	Rare = rgb(168, 118, 255),
	Epic = Accent,
	Legendary = Gold,
	Secret = Gold,
}

Theme.BannerStyles = {
	Info = { Neutral, SurfaceDark },
	Wave = { AccentDark, SurfaceDark },
	Boss = { DangerDark, SurfaceDark },
	Event = { AccentDark, rgb(60, 20, 90) },
	Secret = { GoldDark, SurfaceDark },
	Victory = { GoldDark, SurfaceDark },
	Reward = { SuccessDark, SurfaceDark },
	Sigma = { rgb(30, 30, 36), SurfaceDark },
}

Theme.ToastColors = {
	Info = Theme.Colors.TextDim,
	Success = Success,
	Error = Danger,
	Reward = Gold,
	Achievement = Gold,
	Unlock = Accent,
}

Theme.Fonts = {
	Title = Enum.Font.BuilderSansExtraBold,
	Bold = Enum.Font.BuilderSansBold,
	Medium = Enum.Font.BuilderSansMedium,
	Body = Enum.Font.BuilderSans,
	Meme = Enum.Font.LuckiestGuy, -- only for meme moments (67!)
}

-- text sizes (design units)
Theme.Text = {
	Hero = 48,
	Title = 30,
	Heading = 22,
	Button = 20,
	Body = 16,
	Small = 13,
}

-- screen margin kept free on every side (design units)
Theme.Margin = 28

-- design resolution: everything is laid out for this size and scaled with UIScale
Theme.DesignSize = Vector2.new(1100, 620)
-- phones in landscape use a smaller canvas (bigger UI); screens that need more height scroll
-- or shrink to fit (Kit.FitScale)
Theme.CompactDesignSize = Vector2.new(1000, 520)

return Theme
