--[[
	Theme - one small, consistent colour system.

	  neutral dark surfaces (semi-transparent, the world stays visible behind the UI)
	  white text
	  ONE primary accent  (Accent - hot pink by default: PLAY, XP, selected tabs, the important
	                       button; the UI THEME cosmetic swaps it, Theme.Apply)
	  ONE secondary accent (Gold - coins, rewards, legendary)
	  Red   only for danger / damage / locked / errors
	  Green only for success / owned / selected / claim

	Loud meme colours are reserved for special moments (67 EVENT, rare cards).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rarity = require(ReplicatedStorage:WaitForChild("Modules").Rarity)

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
	TextDim = rgb(206, 202, 228), -- secondary text (descriptions): ~11:1 on the dark glass
	TextMuted = rgb(164, 160, 192), -- captions and hints: ~6.5:1 (readable, still quieter)
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
	Rare = Rarity.Colors.Rare,
	Epic = Rarity.Colors.Epic,
	Mythic = Rarity.Colors.Mythic,
	Fragment = rgb(190, 130, 255),

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

Theme.Rarity = Rarity.Colors

Theme.BannerStyles = {
	Info = { Neutral, SurfaceDark },
	Wave = { AccentDark, SurfaceDark },
	Boss = { DangerDark, SurfaceDark },
	Event = { AccentDark, rgb(60, 20, 90) },
	Secret = { GoldDark, SurfaceDark },
	Victory = { GoldDark, SurfaceDark },
	Reward = { SuccessDark, SurfaceDark },
	Evolution = { rgb(0, 140, 130), SurfaceDark },
	Event67 = { rgb(150, 110, 20), rgb(60, 20, 90) },
	-- 67 TOWN
	MiniBoss = { rgb(200, 60, 30), SurfaceDark },
	Rush = { rgb(190, 120, 20), SurfaceDark },
	Vault = { rgb(150, 110, 30), rgb(40, 30, 60) },
	Rift = { rgb(110, 60, 190), SurfaceDark },
}

Theme.ToastColors = {
	Info = Theme.Colors.TextDim,
	Success = Success,
	Error = Danger,
	Reward = Gold,
	Achievement = Gold,
	Unlock = Accent,
	Cosmetic = Rarity.Colors.Mythic,
	Party = rgb(130, 210, 255),
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
	Small = 14, -- the smallest text for descriptions
	Caption = 12, -- only for short uppercase captions (COINS, LEVEL 2/5)
}

-- screen margin kept free on every side (design units)
Theme.Margin = 28

-- design resolution: everything is laid out for this size and scaled with UIScale
Theme.DesignSize = Vector2.new(1100, 620)
-- phones in landscape use a smaller canvas (bigger UI); screens that need more height scroll
-- or shrink to fit (Kit.FitScale)
Theme.CompactDesignSize = Vector2.new(1000, 520)

--[[
	UI THEMES (cosmetic): only the primary accent changes. Theme.Apply(key, roots) swaps the
	accent colours in Theme.Colors (new UI) and recolours existing UI under `roots`.
]]
Theme.Accents = {
	Default = { rgb(255, 64, 150), rgb(196, 30, 112), rgb(150, 44, 104) },
	Sunset = { rgb(255, 128, 60), rgb(200, 84, 30), rgb(150, 70, 40) },
	Mint = { rgb(60, 210, 150), rgb(30, 150, 104), rgb(40, 120, 96) },
	Ocean = { rgb(70, 150, 255), rgb(40, 100, 200), rgb(44, 80, 150) },
	Gold67 = { rgb(255, 196, 40), rgb(200, 140, 20), rgb(150, 110, 30) },
}
Theme.CurrentAccent = "Default"

local function same(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.004 and math.abs(a.G - b.G) < 0.004 and math.abs(a.B - b.B) < 0.004
end

function Theme.Apply(key: string, roots: { Instance }?)
	local new = Theme.Accents[key] or Theme.Accents.Default
	local old = Theme.Accents[Theme.CurrentAccent] or Theme.Accents.Default
	if key == Theme.CurrentAccent then
		return
	end
	Theme.CurrentAccent = key
	local C = Theme.Colors
	C.Accent, C.AccentDark, C.AccentSoft = new[1], new[2], new[3]
	C.XP, C.Pink, C.PinkDark = new[1], new[1], new[2]
	local function swap(color: Color3): Color3?
		for i = 1, 3 do
			if same(color, old[i]) then
				return new[i]
			end
		end
		return nil
	end
	local list: { Instance } = roots or {}
	for _, root in list do
		for _, d in root:GetDescendants() do
			if d:IsA("GuiObject") then
				local bg = swap(d.BackgroundColor3)
				if bg then
					d.BackgroundColor3 = bg
				end
				if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
					local tc = swap(d.TextColor3)
					if tc then
						d.TextColor3 = tc
					end
				end
			elseif d:IsA("UIStroke") then
				local sc = swap(d.Color)
				if sc then
					d.Color = sc
				end
			end
		end
	end
end

return Theme
