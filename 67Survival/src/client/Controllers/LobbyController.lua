--[[
	LobbyController - the hub. One screen, one purpose: PLAY.

	The 3D hub stage fills the screen: your hero stands on a pedestal on the right (the hub
	camera, CameraController). The UI keeps a calm central column and lots of free space:

	  top centre    LOGO, the short subtitle under it
	  top right     coins · fragments · profile · settings (small)
	  centre        the DIFFICULTY pill, then PLAY (a little below the middle of the screen,
	                the biggest and brightest thing), small chips under it only when they
	                matter (AFK rewards, daily reward, party, live event)
	  left          one small card: today's quest
	  right         your hero in 3D, a compact name plate under it (loadout, CHANGE)
	  bottom        HEROES · ABILITIES · SHOP · MORE (quiet, secondary)

	HERO -> DIFFICULTY -> PLAY: the pill's arrows switch between opened tiers, the pill itself
	opens the difficulty screen (cards with rules, rewards and unlocks).

	Everything else lives behind MORE (a 3x3 grid) or in its own full-screen menu. Panels
	(UI/Panels/*) are built on first open: Kind = "Screen" (full screen, world blurred) or
	"Window" (compact modal). One panel is open at a time.
	Stepping onto the AFK CAMP in the lobby opens the camp window.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local HeroData = require(Shared.HeroData)
local WeaponData = require(Shared.WeaponData)
local MetaData = require(Shared.MetaData)
local CosmeticData = require(Shared.CosmeticData)
local DifficultyData = require(Shared.DifficultyData)
local GameConfig = require(Shared.GameConfig)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)
local PanelsFolder = script.Parent.Parent.UI.Panels

local LobbyController = {}

local C = Theme.Colors
local F = Theme.Fonts
local M = Theme.Margin

LobbyController.Tagline = GameConfig.Tagline

local NAV = {
	{ Key = "Heroes", Text = "HEROES" },
	{ Key = "Abilities", Text = "ABILITIES" },
	{ Key = "Shop", Text = "SHOP" },
	{ Key = "More", Text = "MORE" },
}

-- PLAY sits a little below the middle of the screen (fraction of the safe area height)
local PLAY_Y = 0.62

local function smallCaps(parent: Instance, text: string, position: UDim2, width: number?): TextLabel
	return Kit.Label({
		Text = text,
		Size = UDim2.new(0, width or 200, 0, 16),
		Position = position,
		Font = F.Bold,
		TextColor3 = C.TextMuted,
		MaxTextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
end

function LobbyController:Init(controllers)
	self.C = controllers
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui, root = Kit.ScreenGui("S67Lobby", 20, playerGui)
	self.Gui = gui
	self.Root = root
	self.Panels = {}
	self.Open = nil

	-- safe area: nothing touches the screen edges
	local safe = Kit.New("Frame", { Name = "Safe", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
	Kit.Padding(safe, M, M - 6)
	self.Safe = safe

	self:BuildTop(safe)
	self:BuildCentre(safe)
	self:BuildQuestCard(safe)
	self:BuildHeroPlate(safe)
	self:BuildNav(safe)

	-- panels: modal layer inside the lobby gui; an overlay gui for panels opened from a run
	self.ModalLayer = Kit.New("Frame", { Name = "Panels", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = root })
	local overlayGui, overlayRoot = Kit.ScreenGui("S67OverlayPanels", 50, playerGui)
	self.OverlayGui = overlayGui
	self.OverlayRoot = overlayRoot
end

---------------------------------------------------------------------------
-- layout
---------------------------------------------------------------------------
local function pill(name: string, width: number, order: number, parent: Instance): TextButton
	local button = Kit.New("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(width, 40),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.Glass,
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.Corner(button, 20)
	Kit.Stroke(button)
	Kit.Interactive(button)
	return button
end

function LobbyController:BuildTop(safe: Frame)
	-- the logo, centred, with the subtitle under it
	local logo = Kit.New("Frame", {
		Name = "Logo",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(480, 84),
		Position = UDim2.new(0.5, 0, 0, 30),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = safe,
	})
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = logo,
	})
	-- both words size to their text (no TextScaled): the pair is centred as one group
	Kit.Label({
		Name = "Mark",
		Text = "67",
		Size = UDim2.fromOffset(0, 84),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = F.Meme,
		TextScaled = false,
		TextSize = 76,
		TextColor3 = C.Gold,
		StrokeThickness = 2.5,
		StrokeTransparency = 0.25,
		LayoutOrder = 1,
		Parent = logo,
	})
	Kit.Label({
		Name = "Word",
		Text = "SURVIVAL",
		Size = UDim2.fromOffset(0, 56),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = F.Title,
		TextScaled = false,
		TextSize = 48,
		StrokeThickness = 1.5,
		StrokeTransparency = 0.6,
		LayoutOrder = 2,
		Parent = logo,
	})
	self.Tagline = Kit.Label({
		Name = "Tagline",
		Text = LobbyController.Tagline,
		Size = UDim2.fromOffset(560, 26),
		Position = UDim2.new(0.5, 0, 0, 118),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = F.Bold,
		TextScaled = false,
		TextSize = 20,
		TextColor3 = C.TextDim,
		StrokeThickness = 1.5,
		StrokeTransparency = 0.45,
		Parent = safe,
	})

	-- small items (top-right): coins · fragments · profile · settings
	local bar = Kit.New("Frame", {
		Name = "TopRight",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(420, 44),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Parent = safe,
	})
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bar,
	})
	-- a currency pill: icon, the amount, and the name of the currency under it
	local function amount(parent: Instance, x: number, right: number, caption: string, color: Color3): TextLabel
		Kit.Label({
			Name = "Caption",
			Text = caption,
			Size = UDim2.new(1, -(x + right), 0, 12),
			Position = UDim2.fromOffset(x, 23),
			Font = F.Bold,
			TextScaled = false,
			TextSize = 11,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = parent,
		})
		return Kit.Label({
			Name = "Amount",
			Text = "0",
			Size = UDim2.new(1, -(x + right), 0, 18),
			Position = UDim2.fromOffset(x, 4),
			Font = F.Bold,
			TextScaled = false,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = parent,
		})
	end

	local coins = pill("Coins", 138, 1, bar)
	Widgets.Coin(coins, 20, { Position = UDim2.new(0, 11, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	self.CoinsLabel = amount(coins, 38, 36, "COINS", C.Gold)
	local plus = Kit.Label({
		Text = "+",
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Accent,
		Font = F.Title,
		MaxTextSize = 18,
		Parent = coins,
	})
	Kit.Corner(plus, 12)
	coins.Activated:Connect(function()
		self:OpenPanel("Shop", false, "Upgrades")
	end)

	-- fragments: unlock heroes and abilities (the tooltip says where they come from)
	local fragments = pill("Fragments", 124, 2, bar)
	Widgets.Fragment(fragments, 18, { Position = UDim2.new(0, 11, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	self.FragmentsLabel = amount(fragments, 36, 10, "FRAGMENTS", C.Fragment)
	self.FragmentsTip = Widgets.Tooltip(fragments, GameConfig.FragmentsHelp, 280)
	fragments.Activated:Connect(function()
		self:OpenPanel("Heroes")
	end)

	-- profile: your avatar + your account level ("LV 3")
	local profile = Kit.New("TextButton", {
		Name = "Profile",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = C.SurfaceLight,
		LayoutOrder = 3,
		Parent = bar,
	})
	Kit.Corner(profile, 20)
	Kit.Stroke(profile, 2, C.Gold, 0.35)
	Kit.Interactive(profile)
	local initial = Kit.Label({
		Name = "Initial",
		Text = string.upper(string.sub(Players.LocalPlayer.DisplayName ~= "" and Players.LocalPlayer.DisplayName or Players.LocalPlayer.Name, 1, 1)),
		Size = UDim2.fromScale(0.6, 0.6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = F.Title,
		TextColor3 = C.TextDim,
		Parent = profile,
	})
	local avatar = Kit.New("ImageLabel", {
		Name = "Avatar",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = "",
		Parent = profile,
	})
	Kit.Corner(avatar, 20)
	-- the head shot loads in the background; until then (or if it can't load, e.g. test
	-- players in Studio) the first letter of your name shows
	task.spawn(function()
		local userId = Players.LocalPlayer.UserId
		if userId <= 0 then
			return
		end
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and type(content) == "string" and content ~= "" then
			avatar.Image = content
			initial.Visible = false
		end
	end)
	self.LevelChip = Kit.Label({
		Name = "Level",
		Text = "LV 1",
		Size = UDim2.fromOffset(34, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0.5, 0, 1, 7),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.SurfaceDark,
		Font = F.Title,
		TextScaled = false,
		TextSize = 11,
		TextColor3 = C.Gold,
		ZIndex = 3,
		Parent = profile,
	})
	Kit.Corner(self.LevelChip, 8)
	Kit.Stroke(self.LevelChip, 1, C.Gold, 0.4)
	Kit.New("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = self.LevelChip })
	Widgets.Tooltip(profile, "Your profile. LV = your account level (it grows with every run).", 230)
	profile.Activated:Connect(function()
		self:OpenPanel("Profile")
	end)

	local settings = Kit.New("TextButton", {
		Name = "Settings",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.Glass,
		LayoutOrder = 4,
		Parent = bar,
	})
	Kit.Corner(settings, 12)
	Kit.Stroke(settings)
	Kit.Interactive(settings)
	Widgets.Gear(settings, 20, C.TextDim, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	settings.Activated:Connect(function()
		self:OpenPanel("Settings")
	end)
end

function LobbyController:BuildCentre(safe: Frame)
	-- DIFFICULTY (above PLAY): ‹  III  HORDE  ›
	local diff = Kit.New("Frame", {
		Name = "Difficulty",
		Size = UDim2.fromOffset(340, 48),
		Position = UDim2.new(0.5, 0, PLAY_Y, -80),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.Glass,
		Parent = safe,
	})
	Kit.Corner(diff, 24)
	self.DiffStroke = Kit.Stroke(diff, 1.5, C.TextDim, 0.3)
	local function arrow(name: string, text: string, x: number, anchor: number, step: number)
		-- big round arrows (easy to hit with a mouse or a thumb)
		local b = Kit.New("TextButton", {
			Name = name,
			Text = text,
			AutoButtonColor = false,
			Font = F.Title,
			TextSize = 32,
			TextColor3 = C.Text,
			BackgroundColor3 = C.SurfaceLight,
			BackgroundTransparency = 0.35,
			Size = UDim2.fromOffset(40, 40),
			Position = UDim2.new(x, if anchor == 0 then 4 else -4, 0.5, 0),
			AnchorPoint = Vector2.new(anchor, 0.5),
			Parent = diff,
		})
		Kit.Corner(b, 20)
		Kit.Interactive(b, 1.1)
		b.Activated:Connect(function()
			if Kit.ClickSound then
				Kit.ClickSound()
			end
			self:StepDifficulty(step)
		end)
		return b
	end
	self.DiffPrev = arrow("Prev", "‹", 0, 0, -1)
	self.DiffNext = arrow("Next", "›", 1, 1, 1)
	local open = Kit.New("TextButton", {
		Name = "Open",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -96, 1, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = diff,
	})
	open.Activated:Connect(function()
		if Kit.ClickSound then
			Kit.ClickSound()
		end
		self:OpenPanel("Difficulty")
	end)
	-- "III  HORDE  x1.6": numeral in the tier colour, the name, the reward multiplier in gold
	local row = Kit.New("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = open })
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local function part(name: string, order: number, font: Enum.Font, size: number, color: Color3): TextLabel
		return Kit.New("TextLabel", {
			Name = name,
			Text = "",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 22),
			BackgroundTransparency = 1,
			Font = font,
			TextSize = size,
			TextColor3 = color,
			LayoutOrder = order,
			Parent = row,
		})
	end
	self.DiffNumeral = part("Numeral", 1, F.Title, 20, C.TextDim)
	self.DiffName = part("Name", 2, F.Title, 19, C.Text)
	self.DiffReward = part("Reward", 3, F.Bold, 13, C.Gold)
	self.DiffPill = diff

	-- PLAY: big, clean, a soft halo and a lift under the mouse
	local halo = Kit.New("Frame", {
		Name = "PlayHalo",
		Size = UDim2.fromOffset(340, 106),
		Position = UDim2.fromScale(0.5, PLAY_Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = 1,
		Parent = safe,
	})
	Kit.Corner(halo, 34)
	local shadow = Kit.New("Frame", {
		Name = "PlayShadow",
		Size = UDim2.fromOffset(310, 84),
		Position = UDim2.new(0.5, 0, PLAY_Y, 7),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.SurfaceDark,
		BackgroundTransparency = 0.55,
		Parent = safe,
	})
	Kit.Corner(shadow, 24)
	local play, label = Kit.Button({
		Name = "Play",
		Text = "PLAY",
		Size = UDim2.fromOffset(320, 88),
		Position = UDim2.fromScale(0.5, PLAY_Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = C.Accent,
		Dark = C.AccentDark,
		Radius = 26,
		TextSize = 46,
		Font = F.Title,
		OnClick = function()
			self:Play()
		end,
		Parent = safe,
	})
	label.Size = UDim2.new(1, -40, 1, -26)
	Kit.Interactive(play, 1.04)
	play.MouseEnter:Connect(function()
		Kit.Tween(halo, 0.25, { BackgroundTransparency = 0.78 })
	end)
	play.MouseLeave:Connect(function()
		Kit.Tween(halo, 0.3, { BackgroundTransparency = 1 })
	end)
	self.PlayButton = play
	self.PlayHalo = halo

	-- small chips under PLAY: only shown when they matter
	local chips = Kit.New("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(600, 30),
		Position = UDim2.new(0.5, 0, PLAY_Y, 62),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = safe,
	})
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chips,
	})
	local function chip(name: string, order: number, color: Color3, onClick: () -> ()): (TextButton, TextLabel)
		local button = Kit.New("TextButton", {
			Name = name,
			Text = "",
			AutoButtonColor = false,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 28),
			BackgroundColor3 = C.Surface,
			BackgroundTransparency = Theme.Glass,
			LayoutOrder = order,
			Visible = false,
			Parent = chips,
		})
		Kit.Corner(button, 14)
		Kit.Stroke(button, 1.5, color, 0.3)
		Kit.Padding(button, 12, 0)
		Kit.Interactive(button, 1.04)
		local text = Kit.New("TextLabel", {
			Name = "Text",
			Text = "",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			BackgroundTransparency = 1,
			Font = F.Bold,
			TextSize = 13,
			TextColor3 = color,
			Parent = button,
		})
		button.Activated:Connect(function()
			if Kit.ClickSound then
				Kit.ClickSound()
			end
			onClick()
		end)
		return button, text
	end
	self.DailyChip, self.DailyChipText = chip("Daily", 0, C.Gold, function()
		local data = self.C.ClientData.Data
		if data and data.Daily and data.Daily.CanClaim then
			self.C.ClientData:Fire("ClaimDaily")
		else
			self:OpenPanel("Daily")
		end
	end)
	self.AfkChip, self.AfkChipText = chip("Afk", 1, C.Gold, function()
		self:OpenPanel("AfkCamp")
	end)
	self.PartyChip, self.PartyChipText = chip("Party", 2, Theme.ToastColors.Party, function()
		self:OpenPanel("Party")
	end)
	self.EventChip, self.EventChipText = chip("Event", 3, C.Mythic, function()
		self:OpenPanel("Challenges")
	end)
	self.ChipRow = chips
end

function LobbyController:BuildQuestCard(safe: Frame)
	local card = Widgets.Card(safe, UDim2.fromOffset(244, 100), 0, "QuestCard")
	card.Position = UDim2.new(0, 0, 0.5, -16)
	card.AnchorPoint = Vector2.new(0, 0.5)
	card.BackgroundColor3 = C.Surface
	card.BackgroundTransparency = Theme.Glass
	smallCaps(card, "DAILY QUEST", UDim2.fromOffset(16, 12))
	self.QuestText = Kit.Label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -32, 0, 20),
		Position = UDim2.fromOffset(16, 31),
		Font = F.Bold,
		MaxTextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	self.QuestBar = Widgets.Bar(card, UDim2.new(1, -92, 0, 7), UDim2.fromOffset(16, 61), C.Accent)
	self.QuestBar.Label.Visible = false
	self.QuestCount = Kit.Label({
		Text = "",
		Size = UDim2.fromOffset(56, 16),
		Position = UDim2.new(1, -16, 0, 57),
		AnchorPoint = Vector2.new(1, 0),
		Font = F.Bold,
		MaxTextSize = 13,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	Widgets.Coin(card, 15, { Position = UDim2.fromOffset(16, 77) })
	self.QuestReward = Kit.Label({
		Text = "",
		Size = UDim2.new(1, -56, 0, 15),
		Position = UDim2.fromOffset(37, 77),
		Font = F.Bold,
		MaxTextSize = 13,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	card.Activated:Connect(function()
		self:OpenPanel("Daily")
	end)
	self.QuestCard = card
end

-- the name plate under the 3D hero (bottom right): name, rarity + loadout, CHANGE
function LobbyController:BuildHeroPlate(safe: Frame)
	local plate = Kit.Panel({
		Name = "HeroCard",
		Size = UDim2.fromOffset(250, 62),
		Position = UDim2.new(1, 0, 1, if Kit.IsTouch() then -70 else 0),
		AnchorPoint = Vector2.new(1, 1),
		Radius = 16,
		Parent = safe,
	})
	self.CharacterName = Kit.Label({
		Name = "Name",
		Text = "",
		Size = UDim2.new(1, -120, 0, 22),
		Position = UDim2.fromOffset(16, 9),
		Font = F.Title,
		MaxTextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = plate,
	})
	self.HeroRarity = Kit.Label({
		Name = "Rarity",
		Text = "",
		Size = UDim2.new(1, -120, 0, 15),
		Position = UDim2.fromOffset(16, 35),
		Font = F.Bold,
		MaxTextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = plate,
	})
	Kit.Button({
		Name = "Change",
		Text = "CHANGE",
		Size = UDim2.fromOffset(92, 38),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.Neutral,
		TextSize = 14,
		OnClick = function()
			self:OpenPanel("Heroes")
		end,
		Parent = plate,
	})
	self.HeroPlate = plate
end

function LobbyController:BuildNav(safe: Frame)
	local nav = Kit.New("Frame", {
		Name = "Nav",
		Size = UDim2.fromOffset(4 * 116 + 12, 48),
		Position = UDim2.fromScale(0.5, 1),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = 0.35,
		Parent = safe,
	})
	Kit.Corner(nav, 24)
	Kit.Stroke(nav)
	Kit.Padding(nav, 6, 5)
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = nav,
	})
	self.NavButtons = {}
	for i, entry in NAV do
		local button = Kit.New("TextButton", {
			Name = entry.Key,
			Text = entry.Text,
			AutoButtonColor = false,
			Font = F.Bold,
			TextSize = 14,
			TextColor3 = C.TextDim,
			BackgroundColor3 = C.SurfaceLight,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(116, 38),
			LayoutOrder = i,
			Parent = nav,
		})
		Kit.Corner(button, 19)
		Kit.Interactive(button, 1.03)
		button.MouseEnter:Connect(function()
			Kit.Tween(button, 0.15, { BackgroundTransparency = 0.2, TextColor3 = C.Text })
		end)
		button.MouseLeave:Connect(function()
			Kit.Tween(button, 0.2, { BackgroundTransparency = 1, TextColor3 = C.TextDim })
		end)
		button.Activated:Connect(function()
			if Kit.ClickSound then
				Kit.ClickSound()
			end
			self:OpenPanel(entry.Key)
		end)
		local dot = Kit.New("Frame", {
			Name = "Dot",
			Size = UDim2.fromOffset(7, 7),
			Position = UDim2.new(0.5, #entry.Text * 4.5 + 5, 0, 9), -- just after the label
			BackgroundColor3 = C.Accent,
			Visible = false,
			ZIndex = 3,
			Parent = button,
		})
		Kit.Corner(dot, 4)
		self.NavButtons[entry.Key] = button
	end
end

---------------------------------------------------------------------------
-- actions
---------------------------------------------------------------------------
function LobbyController:Play()
	local data = self.C.ClientData.Data
	if not data then
		return
	end
	self:ClosePanel()
	self.C.SoundController:Play("Banner")
	self.C.ClientData:Fire("StartRun") -- the server uses the active loadout and difficulty
end

-- the pill's arrows: the next / previous OPEN tier (a locked one opens the difficulty screen)
function LobbyController:StepDifficulty(step: number)
	local data = self.C.ClientData.Data
	local diff = data and data.Difficulty
	if not diff then
		return
	end
	local target = diff.Selected + step
	if target < 1 then
		return
	end
	if target > diff.Unlocked then
		self:OpenPanel("Difficulty")
		return
	end
	self.C.ClientData:Fire("SelectDifficulty", target)
end

function LobbyController:Show()
	self.Gui.Enabled = true
end

function LobbyController:Hide()
	self.Gui.Enabled = false
	self:ClosePanel()
end

function LobbyController:ClosePanel()
	local open = self.Open
	if open then
		open.Frame.Visible = false
		self.Open = nil
		self.Safe.Visible = true
		Kit.Blur("menu", 0)
	end
end

--[[
	key: panel module name without "Panel" (Heroes, Abilities, Shop, More, Achievements,
	Collection, Challenges, AfkCamp, Party, Leaderboard, Statistics, Codes, Settings,
	Profile, Daily, Credits, Difficulty)
	overlay: show above the run HUD (settings from the pause menu); arg: passed to OnOpen
]]
function LobbyController:OpenPanel(key: string, overlay: boolean?, arg: any?)
	if self.Open and self.Open.Key == key and arg == nil then
		self:ClosePanel()
		return
	end
	self:ClosePanel()
	local panel = self.Panels[key]
	if not panel then
		local module = require(PanelsFolder:WaitForChild(key .. "Panel")) :: any
		local close = function()
			self:ClosePanel()
		end
		local container
		if module.Kind == "Screen" then
			container = Widgets.Screen(self.ModalLayer, module.Title, close)
		else
			container = Widgets.Window(self.ModalLayer, module.Title, module.Size or Vector2.new(560, 420), close)
		end
		panel = { Key = key, Module = module, Frame = container.Frame, Container = container, State = nil }
		panel.State = module.Build(container.Body, self.C, container)
		self.Panels[key] = panel
	end
	panel.Frame.Parent = if overlay then self.OverlayRoot else self.ModalLayer
	panel.Frame.Visible = true
	-- a full-screen menu replaces the hub (one screen = one purpose); a window floats over it
	self.Safe.Visible = panel.Module.Kind ~= "Screen" or overlay == true
	if panel.Container.Fit then
		Widgets.Fit(panel.Container.Fit, panel.Container.Height)
	end
	local inner = if panel.Container.Panel then panel.Container.Panel else panel.Frame
	Kit.Appear(inner)
	self.Open = panel
	Kit.Blur("menu", if panel.Module.Kind == "Screen" then 14 else 8)
	local data = self.C.ClientData.Data
	if data then
		panel.Module.Refresh(panel.State, data, self.C)
	end
	if panel.Module.OnOpen then
		panel.Module.OnOpen(panel.State, self.C, arg)
	end
end

---------------------------------------------------------------------------
-- data
---------------------------------------------------------------------------
function LobbyController:RefreshQuest(data)
	-- show a finished (claimable) quest first, else the first open one
	local best, done = nil, 0
	for _, q in data.Quests or {} do
		if q.Claimed then
			done += 1
		elseif q.Progress >= q.Goal then
			best = q
			break
		elseif not best then
			best = q
		end
	end
	if best then
		local ready = best.Progress >= best.Goal
		self.QuestText.Text = best.Text
		self.QuestBar:Set(best.Progress / math.max(1, best.Goal))
		self.QuestCount.Text = if ready then "DONE" else string.format("%s/%s", Widgets.Commas(best.Progress), Widgets.Commas(best.Goal))
		self.QuestCount.TextColor3 = if ready then C.Success else C.TextDim
		self.QuestReward.Text = (if ready then "Claim +" else "+") .. Widgets.Commas(best.Coins) .. " COINS"
		self.QuestCard.BackgroundColor3 = if ready then C.SuccessDark else C.Surface
	else
		self.QuestText.Text = if done > 0 then "All done for today" else "New quests tomorrow"
		self.QuestBar:Set(1)
		self.QuestCount.Text = "DONE"
		self.QuestCount.TextColor3 = C.Success
		self.QuestReward.Text = "Come back tomorrow"
		self.QuestCard.BackgroundColor3 = C.Surface
	end
end

function LobbyController:RefreshHero(data)
	local def = HeroData.ByKey[data.Selected]
	self.CharacterName.Text = if def then def.Name else ""
	local slot = if (data.LoadoutSlots or 1) > 1 then "  ·  LOADOUT " .. tostring(data.Loadout or 1) else ""
	self.HeroRarity.Text = if def then string.upper(def.Rarity) .. slot else ""
	self.HeroRarity.TextColor3 = if def then (Theme.Rarity[def.Rarity] or C.TextDim) else C.TextDim
end

-- the difficulty pill: tier numeral + name in the tier's colour, the reward multiplier
function LobbyController:RefreshDifficulty(data)
	local diff = data.Difficulty
	if not diff then
		return
	end
	local tier = DifficultyData.Get(diff.Selected)
	self.DiffNumeral.Text = tier.Numeral
	self.DiffNumeral.TextColor3 = tier.Color
	self.DiffName.Text = tier.Name
	self.DiffReward.Text = if tier.Reward > 1 then "x" .. tostring(tier.Reward) .. " REWARDS" else ""
	self.DiffReward.Visible = tier.Reward > 1
	self.DiffStroke.Color = tier.Color
	self.DiffPrev.TextTransparency = if diff.Selected > 1 then 0 else 0.7
	self.DiffNext.TextTransparency = if diff.Selected < DifficultyData.Count then 0 else 0.7
end

-- the small chips under PLAY
function LobbyController:RefreshChips(data)
	local daily = data.Daily
	self.DailyChip.Visible = daily ~= nil and daily.CanClaim == true
	if daily and daily.CanClaim then
		self.DailyChipText.Text = "DAILY REWARD +" .. Widgets.Commas(daily.Reward)
	end
	local afk = data.Afk
	local ready = afk and afk.Heroes > 0 and (afk.Coins > 0 or afk.Fragments > 0)
	self.AfkChip.Visible = ready == true
	if ready then
		self.AfkChipText.Text = if afk.Full then "AFK CAMP FULL - CLAIM" else "AFK REWARDS READY"
	end
	local party = data.Party
	self.PartyChip.Visible = party ~= nil and (party.InParty or #party.Invites > 0)
	if party then
		self.PartyChipText.Text = if party.InParty then string.format("PARTY %d/%d", #party.Members, party.MaxSize) else "PARTY INVITE"
	end
	local event = data.LiveEvents and data.LiveEvents[1]
	self.EventChip.Visible = event ~= nil
	if event then
		self.EventChipText.Text = event.Title
	end
end

-- small dots: something new or affordable behind a button
function LobbyController:RefreshBadges(data)
	local shop = false
	for key, level in data.Meta or {} do
		local cost = MetaData.Cost(key, level)
		if cost and data.Coins >= cost then
			shop = true
			break
		end
	end
	if data.Cosmetics and next(data.Cosmetics.New or {}) then
		shop = true
	end
	local heroes = false
	for _, def in HeroData.List do
		if not data.Heroes[def.Key] and def.Unlock.Fragments and data.Fragments >= def.Unlock.Fragments then
			heroes = true
		end
	end
	local abilities = false
	for _, def in WeaponData.List do
		if def.Evolution == nil and not data.Weapons[def.Key] and def.Unlock.Fragments and data.Fragments >= def.Unlock.Fragments then
			abilities = true
		end
	end
	local more = false
	for _, q in (data.Weekly and data.Weekly.List) or {} do
		if not q.Claimed and q.Progress >= q.Goal then
			more = true
		end
	end
	if data.Afk and data.Afk.Full and data.Afk.Heroes > 0 then
		more = true
	end
	for key, on in { Shop = shop, Heroes = heroes, Abilities = abilities, More = more } do
		local button = self.NavButtons[key]
		if button then
			(button:FindFirstChild("Dot") :: Frame).Visible = on
		end
	end
end

-- the UI THEME cosmetic recolours the whole interface
function LobbyController:ApplyTheme(data)
	local style = CosmeticData.Style(data.Cosmetics and data.Cosmetics.Equipped, "UITheme")
	if style ~= Theme.CurrentAccent then
		Theme.Apply(style, { Players.LocalPlayer:WaitForChild("PlayerGui") })
	end
end

-- the AFK CAMP in the lobby: stepping onto it opens the camp window (once per visit)
function LobbyController:WatchCamp()
	local Workspace = game:GetService("Workspace")
	task.spawn(function()
		local pad = nil
		local inside = false
		while true do
			task.wait(0.4)
			if not pad or not pad.Parent then
				local map = Workspace:FindFirstChild("Map")
				pad = nil
				if map then
					for _, d in map:GetDescendants() do
						if d:IsA("BasePart") and d:GetAttribute("AfkCamp") then
							pad = d
							break
						end
					end
				end
			end
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if pad and root and self.Gui.Enabled then
				local offset = root.Position - pad.Position
				local now = Vector3.new(offset.X, 0, offset.Z).Magnitude < pad.Size.Y / 2 and math.abs(offset.Y) < 8
				if now and not inside and not self.Open then
					self:OpenPanel("AfkCamp")
				end
				inside = now
			end
		end
	end)
end

function LobbyController:Refresh(data)
	self.CoinsLabel.Text = Widgets.Commas(data.Coins)
	self.FragmentsLabel.Text = Widgets.Commas(data.Fragments or 0)
	self.LevelChip.Text = "LV " .. tostring(data.Level)
	self:ApplyTheme(data)
	self:RefreshQuest(data)
	self:RefreshHero(data)
	self:RefreshDifficulty(data)
	self:RefreshChips(data)
	self:RefreshBadges(data)
	local open = self.Open
	if open then
		open.Module.Refresh(open.State, data, self.C)
	end
end

function LobbyController:Start()
	local ClientData = self.C.ClientData
	ClientData.Changed:Connect(function(data)
		self:Refresh(data)
	end)
	if ClientData.Data then
		self:Refresh(ClientData.Data)
	end
	self:WatchCamp()
end

return LobbyController
