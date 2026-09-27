--[[
	LobbyController - the hub. One screen, one purpose: PLAY.

	  top-left      logo
	  top-right     coins · profile · settings (small)
	  centre        PLAY (the biggest thing on screen) + one line of tagline
	  left          one small card: today's quest
	  right         current character (CHANGE) + daily reward
	  bottom        CHARACTERS · WEAPONS · SHOP · MORE

	Everything else lives behind MORE (a 2x3 grid) or in its own full-screen menu. Panels
	(UI/Panels/*) are built on first open: Kind = "Screen" (full screen, world blurred) or
	"Window" (compact modal). One panel is open at a time.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local CharacterData = require(Shared.CharacterData)
local MetaData = require(Shared.MetaData)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)
local Previews = require(script.Parent.Parent.UI.Previews)
local PanelsFolder = script.Parent.Parent.UI.Panels

local LobbyController = {}

local C = Theme.Colors
local F = Theme.Fonts
local M = Theme.Margin

LobbyController.Tagline = "Survive. Level up. Become unstoppable."

local NAV = {
	{ Key = "Characters", Text = "CHARACTERS" },
	{ Key = "Weapons", Text = "WEAPONS" },
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
	local gui, root = Kit.ScreenGui("BrainrotLobby", 20, playerGui)
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
	local overlayGui, overlayRoot = Kit.ScreenGui("BrainrotOverlayPanels", 50, playerGui)
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
		Text = "BRAINROT",
		Size = UDim2.fromOffset(300, 44),
		Font = F.Title,
		MaxTextSize = 42,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = logo,
	})
	Kit.Label({
		Text = "SURVIVORS",
		Size = UDim2.fromOffset(300, 24),
		Position = UDim2.fromOffset(2, 42),
		Font = F.Bold,
		MaxTextSize = 20,
		TextColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = logo,
	})

	-- small items (top-right): coins · profile · settings
	local bar = Kit.New("Frame", {
		Name = "TopRight",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(360, 46),
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
		self:OpenPanel("Shop", false, "Coins")
	end)

	local profile = Kit.New("TextButton", {
		Name = "Profile",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = C.SurfaceLight,
		LayoutOrder = 2,
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
		LayoutOrder = 3,
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

	-- current character
	local card = Kit.Panel({ Name = "CharacterCard", Size = UDim2.fromOffset(250, 222), LayoutOrder = 1, Radius = 16, Parent = column })
	smallCaps(card, "CHARACTER", UDim2.fromOffset(16, 12))
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
			self:OpenPanel("Characters")
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
	self.C.ClientData:Fire("StartRun", data.Selected, data.StartWeapon)
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
	key: panel module name without "Panel" (Characters, Weapons, Shop, More, Achievements,
	Leaderboard, Statistics, Collection, Codes, Settings, Profile, Daily)
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

function LobbyController:RefreshCharacter(data)
	local key = data.Selected .. "|" .. tostring(data.EquippedSkin)
	if self.PreviewKey ~= key then
		self.PreviewKey = key
		Widgets.Clear(self.PreviewHolder)
		Previews.Character(self.PreviewHolder, data.Selected, data.EquippedSkin)
	end
	local def = CharacterData.ByKey[data.Selected]
	self.CharacterName.Text = if def then def.Name else ""
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

-- a dot on SHOP when a permanent upgrade is affordable
function LobbyController:RefreshBadges(data)
	local affordable = false
	for key, level in data.Meta or {} do
		local cost = MetaData.Cost(key, level)
		if cost and data.Coins >= cost then
			affordable = true
			break
		end
	end
	local shop = self.NavButtons.Shop
	if shop then
		(shop:FindFirstChild("Dot") :: Frame).Visible = affordable
	end
end

function LobbyController:Refresh(data)
	self.CoinsLabel.Text = Widgets.Commas(data.Coins)
	self.LevelChip.Text = tostring(data.BrainLevel)
	self:RefreshQuest(data)
	self:RefreshCharacter(data)
	self:RefreshReward(data)
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
end

return LobbyController
