--[[
	LobbyController - the hub. One screen, one purpose: PLAY.

	  top-left      logo
	  top-right     coins · fragments · profile · settings (small)
	  centre        PLAY (the biggest thing on screen) + one line of tagline, and under it
	                small chips only when they matter: AFK rewards ready, party, live event
	  left          one small card: today's quest
	  right         current hero (CHANGE) + daily reward
	  bottom        HEROES · ABILITIES · SHOP · MORE

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
local GameConfig = require(Shared.GameConfig)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)
local Previews = require(script.Parent.Parent.UI.Previews)
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
	self:BuildRightColumn(safe)
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
function LobbyController:BuildTop(safe: Frame)
	-- logo (top-left)
	local logo = Kit.New("Frame", { Name = "Logo", BackgroundTransparency = 1, Size = UDim2.fromOffset(300, 74), Parent = safe })
	Kit.Label({
		Name = "Mark",
		Text = "67",
		Size = UDim2.fromOffset(84, 70),
		Font = F.Meme,
		MaxTextSize = 64,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		StrokeThickness = 2,
		StrokeTransparency = 0.3,
		Parent = logo,
	})
	Kit.Label({
		Name = "Word",
		Text = "SURVIVAL",
		Size = UDim2.fromOffset(200, 34),
		Position = UDim2.new(0, 86, 0.5, 2),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = F.Title,
		MaxTextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = logo,
	})

	-- small items (top-right): coins · fragments · profile · settings
	local bar = Kit.New("Frame", {
		Name = "TopRight",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(470, 46),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Parent = safe,
	})
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bar,
	})

	local coins = Kit.New("TextButton", {
		Name = "Coins",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(150, 42),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.Glass,
		LayoutOrder = 1,
		Parent = bar,
	})
	Kit.Corner(coins, 21)
	Kit.Stroke(coins)
	Kit.Interactive(coins)
	Widgets.Coin(coins, 22, { Position = UDim2.new(0, 12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	self.CoinsLabel = Kit.Label({
		Name = "Amount",
		Text = "0",
		Size = UDim2.new(1, -78, 0, 22),
		Position = UDim2.new(0, 42, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = F.Bold,
		MaxTextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = coins,
	})
	local plus = Kit.Label({
		Text = "+",
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Accent,
		Font = F.Title,
		MaxTextSize = 20,
		Parent = coins,
	})
	Kit.Corner(plus, 13)
	coins.Activated:Connect(function()
		self:OpenPanel("Shop", false, "Upgrades")
	end)

	-- fragments: unlock heroes and abilities
	local fragments = Kit.New("TextButton", {
		Name = "Fragments",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(100, 42),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.Glass,
		LayoutOrder = 1,
		Parent = bar,
	})
	Kit.Corner(fragments, 21)
	Kit.Stroke(fragments)
	Kit.Interactive(fragments)
	Widgets.Fragment(fragments, 20, { Position = UDim2.new(0, 12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	self.FragmentsLabel = Kit.Label({
		Name = "Amount",
		Text = "0",
		Size = UDim2.new(1, -48, 0, 22),
		Position = UDim2.new(0, 40, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = F.Bold,
		MaxTextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = fragments,
	})
	fragments.Activated:Connect(function()
		self:OpenPanel("Heroes")
	end)

	local profile = Kit.New("TextButton", {
		Name = "Profile",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = C.SurfaceLight,
		LayoutOrder = 3,
		Parent = bar,
	})
	Kit.Corner(profile, 21)
	Kit.Stroke(profile, 2, C.Accent, 0.2)
	Kit.Interactive(profile)
	local avatar = Kit.New("ImageLabel", {
		Name = "Avatar",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", Players.LocalPlayer.UserId),
		Parent = profile,
	})
	Kit.Corner(avatar, 21)
	self.LevelChip = Kit.Label({
		Name = "Level",
		Text = "1",
		Size = UDim2.fromOffset(24, 18),
		Position = UDim2.new(1, 4, 1, 4),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Accent,
		Font = F.Title,
		MaxTextSize = 12,
		ZIndex = 3,
		Parent = profile,
	})
	Kit.Corner(self.LevelChip, 9)
	profile.Activated:Connect(function()
		self:OpenPanel("Profile")
	end)

	local settings = Kit.New("TextButton", {
		Name = "Settings",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.Glass,
		LayoutOrder = 4,
		Parent = bar,
	})
	Kit.Corner(settings, 12)
	Kit.Stroke(settings)
	Kit.Interactive(settings)
	Widgets.Gear(settings, 22, C.TextDim, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	settings.Activated:Connect(function()
		self:OpenPanel("Settings")
	end)
end

function LobbyController:BuildCentre(safe: Frame)
	local group = Kit.New("Frame", {
		Name = "PlayGroup",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(360, 140),
		Position = UDim2.fromScale(0.5, 0.6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = safe,
	})
	local play, label = Kit.Button({
		Name = "Play",
		Text = "PLAY",
		Size = UDim2.fromOffset(320, 92),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = C.Accent,
		Dark = C.AccentDark,
		Radius = 22,
		TextSize = 46,
		Font = F.Title,
		OnClick = function()
			self:Play()
		end,
		Parent = group,
	})
	label.Size = UDim2.new(1, -40, 1, -24)
	Kit.Interactive(play, 1.05)
	self.PlayButton = play
	self.Tagline = Kit.Label({
		Name = "Tagline",
		Text = LobbyController.Tagline,
		Size = UDim2.fromOffset(420, 22),
		Position = UDim2.new(0.5, 0, 0, 106),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = F.Medium,
		MaxTextSize = 17,
		TextColor3 = C.Text,
		StrokeThickness = 1,
		StrokeTransparency = 0.75,
		Parent = group,
	})

	-- small chips under the tagline: only shown when they matter
	local chips = Kit.New("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(560, 30),
		Position = UDim2.new(0.5, 0, 0, 138),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = group,
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
		local label = Kit.New("TextLabel", {
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
		return button, label
	end
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
	local card = Widgets.Card(safe, UDim2.fromOffset(250, 112), 0, "QuestCard")
	card.Position = UDim2.fromScale(0, 0.5)
	card.AnchorPoint = Vector2.new(0, 0.5)
	card.BackgroundColor3 = C.Surface
	card.BackgroundTransparency = Theme.Glass
	smallCaps(card, "DAILY QUEST", UDim2.fromOffset(16, 12))
	self.QuestText = Kit.Label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -32, 0, 20),
		Position = UDim2.fromOffset(16, 32),
		Font = F.Bold,
		MaxTextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	self.QuestBar = Widgets.Bar(card, UDim2.new(1, -96, 0, 8), UDim2.fromOffset(16, 64), C.Accent)
	self.QuestBar.Label.Visible = false
	self.QuestCount = Kit.Label({
		Text = "",
		Size = UDim2.fromOffset(56, 16),
		Position = UDim2.new(1, -16, 0, 60),
		AnchorPoint = Vector2.new(1, 0),
		Font = F.Bold,
		MaxTextSize = 14,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	Widgets.Coin(card, 16, { Position = UDim2.fromOffset(16, 82) })
	self.QuestReward = Kit.Label({
		Text = "",
		Size = UDim2.new(1, -56, 0, 16),
		Position = UDim2.fromOffset(38, 82),
		Font = F.Bold,
		MaxTextSize = 14,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	card.Activated:Connect(function()
		self:OpenPanel("Daily")
	end)
	self.QuestCard = card
end

function LobbyController:BuildRightColumn(safe: Frame)
	local column = Kit.New("Frame", {
		Name = "Right",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(250, 322),
		Position = UDim2.fromScale(1, 0.5),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = safe,
	})
	Kit.New("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = column })

	-- current hero
	local card = Kit.Panel({ Name = "HeroCard", Size = UDim2.fromOffset(250, 222), LayoutOrder = 1, Radius = 16, Parent = column })
	smallCaps(card, "HERO", UDim2.fromOffset(16, 12), 90)
	self.HeroRarity = Kit.Label({
		Name = "Rarity",
		Text = "",
		Size = UDim2.fromOffset(110, 16),
		Position = UDim2.new(1, -16, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		Font = F.Bold,
		MaxTextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	self.PreviewHolder = Kit.New("Frame", {
		Name = "PreviewHolder",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 0, 120),
		Position = UDim2.fromOffset(12, 30),
		Parent = card,
	})
	self.CharacterName = Kit.Label({
		Text = "",
		Size = UDim2.new(1, -32, 0, 22),
		Position = UDim2.fromOffset(16, 150),
		Font = F.Title,
		MaxTextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Kit.Button({
		Name = "Change",
		Text = "CHANGE",
		Size = UDim2.new(1, -32, 0, 34),
		Position = UDim2.fromOffset(16, 178),
		Color = C.Neutral,
		TextSize = 15,
		OnClick = function()
			self:OpenPanel("Heroes")
		end,
		Parent = card,
	})

	-- daily reward
	local reward = Kit.Panel({ Name = "RewardCard", Size = UDim2.fromOffset(250, 88), LayoutOrder = 2, Radius = 16, Parent = column })
	smallCaps(reward, "DAILY REWARD", UDim2.fromOffset(16, 12))
	Widgets.Coin(reward, 18, { Position = UDim2.fromOffset(16, 38) })
	self.RewardText = Kit.Label({
		Text = "",
		Size = UDim2.fromOffset(94, 20),
		Position = UDim2.fromOffset(40, 37),
		Font = F.Bold,
		MaxTextSize = 17,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = reward,
	})
	self.RewardDay = Kit.Label({
		Text = "",
		Size = UDim2.fromOffset(110, 16),
		Position = UDim2.fromOffset(16, 62),
		Font = F.Medium,
		MaxTextSize = 13,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = reward,
	})
	local claim, claimLabel = Kit.Button({
		Name = "Claim",
		Text = "CLAIM",
		Size = UDim2.fromOffset(96, 40),
		Position = UDim2.new(1, -14, 0.5, 6),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.Success,
		TextSize = 15,
		OnClick = function()
			local data = self.C.ClientData.Data
			if data and data.Daily and data.Daily.CanClaim then
				self.C.ClientData:Fire("ClaimDaily")
			end
		end,
		Parent = reward,
	})
	self.ClaimButton, self.ClaimLabel = claim, claimLabel
end

function LobbyController:BuildNav(safe: Frame)
	local nav = Kit.New("Frame", {
		Name = "Nav",
		Size = UDim2.fromOffset(4 * 148 + 16, 60),
		Position = UDim2.fromScale(0.5, 1),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.Glass,
		Parent = safe,
	})
	Kit.Corner(nav, 30)
	Kit.Stroke(nav)
	Kit.Padding(nav, 8, 6)
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
			TextSize = 16,
			TextColor3 = C.TextDim,
			BackgroundColor3 = C.SurfaceLight,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(148, 48),
			LayoutOrder = i,
			Parent = nav,
		})
		Kit.Corner(button, 24)
		Kit.Interactive(button, 1.03)
		button.MouseEnter:Connect(function()
			button.BackgroundTransparency = 0.2
			button.TextColor3 = C.Text
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundTransparency = 1
			button.TextColor3 = C.TextDim
		end)
		button.Activated:Connect(function()
			if Kit.ClickSound then
				Kit.ClickSound()
			end
			self:OpenPanel(entry.Key)
		end)
		local dot = Kit.New("Frame", {
			Name = "Dot",
			Size = UDim2.fromOffset(8, 8),
			Position = UDim2.new(0.5, #entry.Text * 5 + 6, 0, 12), -- just after the label
			BackgroundColor3 = C.Accent,
			Visible = false,
			ZIndex = 3,
			Parent = button,
		})
		Kit.Corner(dot, 5)
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
	self.C.ClientData:Fire("StartRun") -- the server uses the active loadout
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
	Profile, Daily, Credits)
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
	local equipped = data.Cosmetics and data.Cosmetics.Equipped
	local skin = CosmeticData.Style(equipped, "HeroSkin")
	local hat = CosmeticData.Style(equipped, "Hat")
	local key = data.Selected .. "|" .. skin .. "|" .. hat
	if self.PreviewKey ~= key then
		self.PreviewKey = key
		Widgets.Clear(self.PreviewHolder)
		Previews.Hero(self.PreviewHolder, data.Selected, { Skin = skin, Hat = hat })
	end
	local def = HeroData.ByKey[data.Selected]
	self.CharacterName.Text = if def then def.Name else ""
	self.HeroRarity.Text = if def then string.upper(def.Rarity) else ""
	self.HeroRarity.TextColor3 = if def then (Theme.Rarity[def.Rarity] or C.TextDim) else C.TextDim
end

-- the small chips under PLAY
function LobbyController:RefreshChips(data)
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

function LobbyController:RefreshReward(data)
	local daily = data.Daily
	if not daily then
		return
	end
	self.RewardText.Text = "+" .. Widgets.Commas(daily.Reward)
	self.RewardDay.Text = "Day " .. tostring(daily.Streak) .. " streak"
	if daily.CanClaim then
		self.ClaimLabel.Text = "CLAIM"
		Kit.SetButtonColor(self.ClaimButton, C.Success)
	else
		self.ClaimLabel.Text = "TOMORROW"
		Kit.SetButtonColor(self.ClaimButton, C.Neutral)
		self.RewardText.Text = "Claimed"
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
	self.LevelChip.Text = tostring(data.Level)
	self:ApplyTheme(data)
	self:RefreshQuest(data)
	self:RefreshHero(data)
	self:RefreshReward(data)
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
