--[[
	LobbyController - the lobby screen: player card (Brain Level, coins), the menu
	(CHARACTERS, WEAPONS, UPGRADES, ACHIEVEMENTS, SHOP, LEADERBOARD, COLLECTION, DAILY,
	SETTINGS) and the big PLAY button. Panels (UI/Panels/*) are built on first open and
	refreshed whenever new data arrives.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local CharacterData = require(Shared.CharacterData)
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)
local PanelsFolder = script.Parent.Parent.UI.Panels

local LobbyController = {}

local C = Theme.Colors

local MENU = {
	{ Key = "Characters", Text = "CHARACTERS", Icon = "🙂", Color = C.Lime },
	{ Key = "Weapons", Text = "WEAPONS", Icon = "🔨", Color = C.Orange },
	{ Key = "Upgrades", Text = "UPGRADES", Icon = "💪", Color = C.Blue },
	{ Key = "Achievements", Text = "ACHIEVEMENTS", Icon = "🏆", Color = C.Gold },
	{ Key = "Daily", Text = "DAILY", Icon = "📅", Color = C.Pink },
	{ Key = "Collection", Text = "COLLECTION", Icon = "📚", Color = C.Cyan },
	{ Key = "Leaderboard", Text = "LEADERBOARD", Icon = "📊", Color = C.Purple },
	{ Key = "Shop", Text = "SHOP", Icon = "🛒", Color = C.Red },
	{ Key = "Settings", Text = "SETTINGS", Icon = "⚙️", Color = C.Gray },
}

function LobbyController:Init(controllers)
	self.C = controllers
	local gui, root = Kit.ScreenGui("BrainrotLobby", 20, Players.LocalPlayer:WaitForChild("PlayerGui"))
	self.Gui = gui
	self.Root = root
	self.Panels = {}
	self.Open = nil

	-- player card
	local card = Kit.Panel({
		Name = "PlayerCard",
		Size = UDim2.fromOffset(300, 92),
		Position = UDim2.fromOffset(12, 12),
		Radius = 16,
		Parent = root,
	})
	Kit.Gradient(card, C.PanelLight, C.PanelDark)
	self.LevelBadge = Kit.Label({
		Text = "1",
		Size = UDim2.fromOffset(62, 62),
		Position = UDim2.fromOffset(10, 14),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Pink,
		Font = Theme.Fonts.Title,
		Parent = card,
	})
	Kit.Corner(self.LevelBadge, 31)
	Kit.Stroke(self.LevelBadge, 3)
	self.NameLabel = Kit.Label({
		Text = Players.LocalPlayer.DisplayName,
		Size = UDim2.fromOffset(210, 26),
		Position = UDim2.fromOffset(82, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	self.TitleLabel = Kit.Label({
		Text = "Fresh Goober",
		Size = UDim2.fromOffset(210, 20),
		Position = UDim2.fromOffset(82, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.TextDim,
		Font = Theme.Fonts.Body,
		Parent = card,
	})
	self.BrainBar = Widgets.Bar(card, UDim2.fromOffset(200, 18), UDim2.fromOffset(82, 60), C.Pink)

	self.CoinsLabel = Kit.Label({
		Text = "🪙 0",
		Size = UDim2.fromOffset(220, 40),
		Position = UDim2.fromOffset(12, 110),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Panel,
		TextColor3 = C.Coin,
		Font = Theme.Fonts.Title,
		Parent = root,
	})
	Kit.Corner(self.CoinsLabel, 14)
	Kit.Stroke(self.CoinsLabel, 3)

	-- menu
	local menu = Kit.New("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(230, 440),
		Position = UDim2.fromOffset(12, 160),
		Parent = root,
	})
	Kit.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = menu })
	self.MenuButtons = {}
	for i, entry in MENU do
		local button = Kit.Button({
			Name = entry.Key,
			Text = entry.Icon .. " " .. entry.Text,
			Size = UDim2.fromOffset(220, 42),
			Color = entry.Color,
			LayoutOrder = i,
			OnClick = function()
				self:OpenPanel(entry.Key)
			end,
			Parent = menu,
		})
		local dot = Kit.New("Frame", {
			Name = "Dot",
			Size = UDim2.fromOffset(16, 16),
			Position = UDim2.new(1, -6, 0, -4),
			BackgroundColor3 = C.Red,
			Visible = false,
			ZIndex = 5,
			Parent = button,
		})
		Kit.Corner(dot, 8)
		Kit.Stroke(dot, 2)
		self.MenuButtons[entry.Key] = button
	end

	-- PLAY
	local play, playLabel = Kit.Button({
		Name = "Play",
		Text = "▶ PLAY",
		Size = UDim2.fromOffset(340, 96),
		Position = UDim2.new(0.5, 0, 1, -44),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = C.Lime,
		Radius = 24,
		OnClick = function()
			self:Play()
		end,
		Parent = root,
	})
	playLabel.Font = Theme.Fonts.Title
	self.PlayButton = play
	self.PlayingAs = Kit.Label({
		Text = "",
		Size = UDim2.fromOffset(420, 30),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
	})
	Kit.Label({
		Text = "BRAINROT SURVIVORS",
		Size = UDim2.fromOffset(520, 60),
		Position = UDim2.new(0.5, 0, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.Fonts.Title,
		TextColor3 = C.Gold,
		StrokeThickness = 4,
		Parent = root,
	})
	self.Status = Kit.Label({
		Text = "Loading...",
		Size = UDim2.fromOffset(400, 22),
		Position = UDim2.new(0.5, 0, 0, 72),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = C.TextDim,
		Font = Theme.Fonts.Body,
		Parent = root,
	})

	-- modal layer
	self.ModalLayer = Kit.New("Frame", {
		Name = "Modals",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = root,
	})
	-- panels opened from the run (settings) live in their own gui above the HUD
	local overlayGui, overlayRoot = Kit.ScreenGui("BrainrotOverlayPanels", 50, Players.LocalPlayer:WaitForChild("PlayerGui"))
	self.OverlayGui = overlayGui
	self.OverlayRoot = overlayRoot
end

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
		open.Modal.Frame.Visible = false
		self.Open = nil
	end
end

-- key = panel module name without "Panel"; overlay = show above everything (from the run)
function LobbyController:OpenPanel(key: string, overlay: boolean?)
	if self.Open and self.Open.Key == key then
		self:ClosePanel()
		return
	end
	self:ClosePanel()
	local panel = self.Panels[key]
	if not panel then
		local module = require(PanelsFolder:WaitForChild(key .. "Panel")) :: any
		local modal = Widgets.Modal(self.ModalLayer, module.Title, module.Size, function()
			self:ClosePanel()
		end)
		panel = { Key = key, Module = module, Modal = modal, State = nil }
		panel.State = module.Build(modal.Body, self.C)
		self.Panels[key] = panel
	end
	panel.Modal.Frame.Parent = if overlay then self.OverlayRoot else self.ModalLayer
	panel.Modal.Frame.Visible = true
	Kit.Pop(panel.Modal.Frame, 0.08)
	self.Open = panel
	local data = self.C.ClientData.Data
	if data then
		panel.Module.Refresh(panel.State, data, self.C)
	end
	if panel.Module.OnOpen then
		panel.Module.OnOpen(panel.State, self.C)
	end
end

function LobbyController:Refresh(data)
	self.LevelBadge.Text = tostring(data.BrainLevel)
	self.TitleLabel.Text = data.Title
	self.BrainBar:Set(data.BrainLevelXP / math.max(1, data.BrainLevelNeed), string.format("%d / %d", data.BrainLevelXP, data.BrainLevelNeed))
	self.CoinsLabel.Text = "🪙 " .. Format.Commas(data.Coins)
	local def = CharacterData.ByKey[data.Selected]
	self.PlayingAs.Text = if def then "Playing as " .. def.Icon .. " " .. def.Name else ""
	self.Status.Text = data.SaveStatus or ""
	-- red dots: something to claim
	local claimable = data.Daily and data.Daily.CanClaim
	for _, q in data.Quests or {} do
		if not q.Claimed and q.Progress >= q.Goal then
			claimable = true
		end
	end
	local daily = self.MenuButtons.Daily
	if daily then
		(daily:FindFirstChild("Dot") :: Frame).Visible = claimable == true
	end
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
	-- the PLAY button breathes
	task.spawn(function()
		local scale = self.PlayButton:FindFirstChild("PressScale") :: UIScale?
		while true do
			task.wait(1.6)
			if self.Gui.Enabled and scale and scale.Scale == 1 then
				Kit.Pop(self.PlayButton, 0.05)
			end
		end
	end)
end

return LobbyController
