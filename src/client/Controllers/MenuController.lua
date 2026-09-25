--[[
	MenuController - MainUI in the lobby:
	  THE DOPPELGÄNGER
	  PLAY  DUO  SHOP  COLLECTION  QUESTS  SETTINGS
	Each button opens a centered panel. The menu hides while you are in a level.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CosmeticsConfig = require(ReplicatedStorage.Shared.CosmeticsConfig)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)

local MenuController = {}

local C = Theme.Colors
local player = Players.LocalPlayer

local PANEL_SIZE = UDim2.fromOffset(760, 500)

function MenuController:Init(controllers)
	self.Controllers = controllers
	self.Panels = {}
	self.Open = nil
end

function MenuController:Start()
	local gui = Kit.Screen("MainUI", 20)
	self.Gui = gui
	self:_buildSidebar()
	self:_buildPanels()

	local state = self.Controllers.ClientState
	state.Changed:Connect(function(key)
		if key == "Run" then
			self:_refreshVisibility()
		elseif key == "Profile" or key == "GlobalBests" or key == "Duo" then
			self:_refreshOpenPanel()
		end
	end)
	state:WhenReady(function()
		self:_refreshVisibility()
		if not state.Run and state.Profile and (state.Profile.Stats.LevelsCompleted or 0) == 0 then
			-- first time: show the level list right away
			self:OpenPanel("Play")
		end
	end)
	Players.PlayerAdded:Connect(function()
		self:_refreshOpenPanel()
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			self:_refreshOpenPanel()
		end)
	end)
end

---------------------------------------------------------------------------
-- Sidebar
---------------------------------------------------------------------------

function MenuController:_buildSidebar()
	local sidebar = Kit.Panel({
		Name = "Sidebar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 20),
		Size = UDim2.fromOffset(230, 470),
		Parent = self.Gui,
	})
	self.Sidebar = sidebar
	Kit.Text({
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 26),
		Font = Theme.Fonts.Title,
		TextSize = 20,
		TextColor3 = C.TextDim,
		Text = "THE",
		Parent = sidebar,
	})
	Kit.Text({
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 36),
		Font = Theme.Fonts.Title,
		TextSize = 26,
		TextColor3 = C.Cyan,
		Text = "DOPPELGÄNGER",
		Parent = sidebar,
	})
	local list = Kit.New("Frame", {
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 1, -96),
		BackgroundTransparency = 1,
		Parent = sidebar,
	}, { Kit.List(Enum.FillDirection.Vertical, 8) })

	local entries = {
		{ "PLAY", "Play", C.Yellow },
		{ "DUO", "Duo", C.Orange },
		{ "SHOP", "Shop", C.Purple },
		{ "COLLECTION", "Collection", C.Cyan },
		{ "QUESTS", "Quests", C.Green },
		{ "SETTINGS", "Settings", C.PanelLight },
	}
	for index, entry in entries do
		local label, panelName, color = entry[1], entry[2], entry[3]
		local isPlay = index == 1
		Kit.Button({
			Text = label,
			Size = UDim2.fromOffset(196, if isPlay then 58 else 46),
			TextSize = if isPlay then 26 else 19,
			Color = if isPlay then color else C.PanelLight,
			TextColor = if isPlay then C.Background else C.Text,
			StrokeColor = color,
			LayoutOrder = index,
			Parent = list,
		}, function()
			self:TogglePanel(panelName)
		end)
	end
	-- collapse toggle (useful on small phones)
	self.MenuToggle = Kit.Button({
		Text = "MENU",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(90, 44),
		Color = C.Yellow,
		TextColor = C.Background,
		Parent = self.Gui,
	}, function()
		self.Collapsed = false
		self:_refreshVisibility()
	end)
	self.MenuToggle.Visible = false
	Kit.Button({
		Text = "<",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(32, 32),
		TextSize = 18,
		Parent = sidebar,
	}, function()
		self.Collapsed = true
		self:ClosePanel()
		self:_refreshVisibility()
	end)
end

function MenuController:_refreshVisibility()
	local inRun = self.Controllers.ClientState.Run ~= nil
	self.Sidebar.Visible = not inRun and not self.Collapsed
	self.MenuToggle.Visible = not inRun and self.Collapsed == true
	if inRun then
		self:ClosePanel()
	end
end

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------

function MenuController:_panel(name: string, title: string, color: Color3)
	local panel = Kit.Panel({
		Name = name .. "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 120, 0.5, 20),
		Size = PANEL_SIZE,
		Visible = false,
		Parent = self.Gui,
	})
	Kit.Text({
		Position = UDim2.fromOffset(24, 14),
		Size = UDim2.new(1, -100, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.Title,
		TextSize = 32,
		TextColor3 = color,
		Text = title,
		Parent = panel,
	})
	Kit.Button({
		Text = "X",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		Parent = panel,
	}, function()
		self:ClosePanel()
	end)
	local body = Kit.New("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(20, 66),
		Size = UDim2.new(1, -40, 1, -84),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = panel,
	})
	self.Panels[name] = { Frame = panel, Body = body }
	return panel, body
end

function MenuController:_buildPanels()
	self:_panel("Play", "CHOOSE A LEVEL", C.Yellow)
	self:_panel("Duo", "DUO MODE", C.Orange)
	self:_panel("Shop", "DOPPELGÄNGER SKINS", C.Purple)
	self:_panel("Collection", "COLLECTION", C.Cyan)
	self:_panel("Quests", "QUESTS", C.Green)
	self:_panel("Settings", "SETTINGS", C.Text)
end

function MenuController:OpenPanel(name: string)
	if self.Controllers.ClientState.Run then
		return
	end
	self:ClosePanel()
	local panel = self.Panels[name]
	if not panel then
		return
	end
	self.Open = name
	self:_fill(name)
	panel.Frame.Visible = true
	local scale = panel.Frame:FindFirstChildOfClass("UIScale") or Kit.New("UIScale", { Parent = panel.Frame })
	scale.Scale = 0.92
	Kit.Tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
end

function MenuController:TogglePanel(name: string)
	if self.Open == name then
		self:ClosePanel()
	else
		self:OpenPanel(name)
	end
end

function MenuController:ClosePanel()
	if self.Open and self.Panels[self.Open] then
		self.Panels[self.Open].Frame.Visible = false
	end
	self.Open = nil
end

function MenuController:_refreshOpenPanel()
	if self.Open then
		self:_fill(self.Open)
	end
end

local function clear(body: Instance)
	body:ClearAllChildren()
end

function MenuController:_fill(name: string)
	local panel = self.Panels[name]
	if not panel then
		return
	end
	clear(panel.Body)
	if name == "Play" then
		self:_fillPlay(panel.Body)
	elseif name == "Duo" then
		self:_fillDuo(panel.Body)
	elseif name == "Shop" then
		self:_fillShop(panel.Body, false)
	elseif name == "Collection" then
		self:_fillShop(panel.Body, true)
	elseif name == "Quests" then
		self:_fillQuests(panel.Body)
	elseif name == "Settings" then
		self:_fillSettings(panel.Body)
	end
end

---------------------------------------------------------------------------
-- PLAY: level grid
---------------------------------------------------------------------------

function MenuController:_levelGrid(body: Instance, onPick: (number) -> (), requireUnlock: boolean)
	local state = self.Controllers.ClientState
	Kit.New("UIGridLayout", {
		CellSize = UDim2.fromOffset(170, 150),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = body,
	})
	for index, entry in state.Catalog do
		local unlocked = state:IsUnlocked(entry.Id)
		local completed = state:IsCompleted(entry.Id)
		local best = state:BestTime(entry.Id)
		local color = if completed then C.Green elseif unlocked then C.Yellow else C.Stroke
		local card = Kit.Button({
			Text = "",
			Size = UDim2.fromOffset(170, 150),
			Color = if unlocked then C.PanelLight else C.Panel,
			StrokeColor = color,
			LayoutOrder = index,
			Parent = body,
		}, function()
			if unlocked or not requireUnlock then
				onPick(entry.Id)
			else
				self.Controllers.HudController:Toast("Complete the previous level first!", "Error")
			end
		end)
		Kit.Text({
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(1, -20, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.Fonts.Title,
			TextSize = 36,
			TextColor3 = color,
			Text = Format.LevelNumber(entry.Id),
			Parent = card,
		})
		Kit.Text({
			Position = UDim2.fromOffset(10, 50),
			Size = UDim2.new(1, -20, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 16,
			Text = entry.Name,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Parent = card,
		})
		Kit.Text({
			Position = UDim2.fromOffset(10, 72),
			Size = UDim2.new(1, -20, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.Fonts.Body,
			TextSize = 13,
			TextColor3 = C.TextDim,
			Text = "DOPPELGÄNGER: " .. tostring(entry.RoleHint),
			Parent = card,
		})
		local global = state.GlobalBests[Progression.LevelKey(entry.Id)]
		local timeText
		if not unlocked then
			timeText = "LOCKED"
		elseif best then
			timeText = "BEST " .. Format.Time(best, true)
		else
			timeText = "PAR " .. Format.Time(entry.ParTime)
		end
		Kit.Text({
			Position = UDim2.fromOffset(10, 96),
			Size = UDim2.new(1, -20, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 15,
			TextColor3 = if best and best <= entry.ParTime then C.Cyan else C.Text,
			Text = timeText,
			Parent = card,
		})
		if global then
			Kit.Text({
				Position = UDim2.fromOffset(10, 118),
				Size = UDim2.new(1, -20, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Theme.Fonts.Body,
				TextSize = 12,
				TextColor3 = C.TextDim,
				Text = "WORLD " .. Format.Time(global.Time, true),
				Parent = card,
			})
		end
	end
end

function MenuController:_fillPlay(body: Instance)
	self:_levelGrid(body, function(levelId)
		self:ClosePanel()
		Net.Event("RequestPlay"):FireServer(levelId)
	end, true)
end

---------------------------------------------------------------------------
-- DUO
---------------------------------------------------------------------------

function MenuController:_fillDuo(body: Instance)
	local state = self.Controllers.ClientState
	local duo = state.Duo
	Kit.List(Enum.FillDirection.Vertical, 10).Parent = body
	local function line(text: string, color: Color3?, size: number?, order: number)
		return Kit.Text({
			Size = UDim2.new(1, -10, 0, (size or 18) + 12),
			TextSize = size or 18,
			TextColor3 = color or C.Text,
			Text = text,
			LayoutOrder = order,
			Parent = body,
		})
	end

	if not duo then
		line("Two players. One is the player, the other IS the doppelgänger.", C.TextDim, 17, 1)
		line("CYAN buttons and plates only work for the doppelgänger.", C.Cyan, 17, 2)
		local others = {}
		for _, other in Players:GetPlayers() do
			if other ~= player then
				table.insert(others, other)
			end
		end
		if #others == 0 then
			line("No other players in this server yet. Invite a friend!", C.Orange, 18, 3)
			return
		end
		for index, other in others do
			local row = Kit.New("Frame", {
				Size = UDim2.new(1, -20, 0, 50),
				BackgroundColor3 = C.PanelLight,
				LayoutOrder = 10 + index,
				Parent = body,
			}, { Kit.Corner(10) })
			Kit.Text({
				Position = UDim2.fromOffset(14, 0),
				Size = UDim2.new(1, -180, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = 19,
				Text = other.DisplayName,
				Parent = row,
			})
			Kit.Button({
				Text = "INVITE",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(140, 38),
				Color = C.Orange,
				TextColor = C.Background,
				Parent = row,
			}, function()
				Net.Event("DuoAction"):FireServer("Invite", other.UserId)
			end)
		end
		return
	end

	line(string.format("PLAYER: %s     DOPPELGÄNGER: %s", duo.Host, duo.Partner), C.Orange, 20, 1)
	if duo.IsHost then
		local modes = Kit.New("Frame", {
			Size = UDim2.new(1, -20, 0, 50),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Parent = body,
		}, { Kit.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
		for _, mode in { "Trust", "Betrayal" } do
			local selected = duo.Mode == mode
			Kit.Button({
				Text = string.upper(mode) .. " MODE",
				Size = UDim2.fromOffset(220, 44),
				Color = if selected then (if mode == "Trust" then C.Green else C.Red) else C.PanelLight,
				TextColor = if selected then C.Background else C.Text,
				Parent = modes,
			}, function()
				Net.Event("DuoAction"):FireServer("SetMode", mode)
			end)
		end
		line(if duo.Mode == "Betrayal" then "Your doppelgänger MIGHT secretly try to make you fail..." else "Work together to reach the finish.", C.TextDim, 16, 3)
		local grid = Kit.New("Frame", {
			Size = UDim2.new(1, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 4,
			Parent = body,
		})
		self:_levelGrid(grid, function(levelId)
			self:ClosePanel()
			Net.Event("DuoAction"):FireServer("Start", levelId)
		end, true)
	else
		line("Waiting for " .. duo.Host .. " to choose a level...", C.TextDim, 18, 2)
		line("Mode: " .. string.upper(duo.Mode), if duo.Mode == "Betrayal" then C.Red else C.Green, 18, 3)
	end
	Kit.Button({
		Text = "LEAVE DUO",
		Size = UDim2.fromOffset(200, 44),
		Color = Color3.fromRGB(120, 40, 50),
		LayoutOrder = 100,
		Parent = body,
	}, function()
		Net.Event("DuoAction"):FireServer("Leave")
	end)
end

---------------------------------------------------------------------------
-- SHOP / COLLECTION
---------------------------------------------------------------------------

function MenuController:_fillShop(body: Instance, ownedOnly: boolean)
	local profile = self.Controllers.ClientState.Profile
	if not profile then
		return
	end
	if ownedOnly then
		-- a short stats header for the collection
		local stats = profile.Stats or {}
		local header = Kit.Text({
			Size = UDim2.new(1, -10, 0, 50),
			TextSize = 16,
			TextColor3 = C.TextDim,
			LayoutOrder = 0,
			Text = string.format(
				"LEVELS CLEARED %d   ·   RIVAL WINS %d   ·   FLAWLESS %d   ·   DOPPEL PRESSES %d   ·   DEATHS %d",
				stats.UniqueLevelsCompleted or 0,
				stats.RivalWins or 0,
				stats.NoDeathClears or 0,
				stats.DoppelPresses or 0,
				stats.Deaths or 0
			),
		})
		local holder = Kit.New("Frame", {
			Size = UDim2.new(1, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = body,
		}, { Kit.List(Enum.FillDirection.Vertical, 8) })
		header.Parent = holder
		local grid = Kit.New("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Parent = holder,
		})
		body = grid
	end
	Kit.New("UIGridLayout", {
		CellSize = UDim2.fromOffset(165, 190),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = body,
	})
	for index, id in CosmeticsConfig.Order do
		local item = CosmeticsConfig.Items[id]
		local owned = profile.OwnedCosmetics[id] == true
		local equipped = profile.EquippedCosmetic == id
		if ownedOnly and not owned then
			continue
		end
		local card = Kit.New("Frame", {
			Size = UDim2.fromOffset(165, 190),
			BackgroundColor3 = C.PanelLight,
			LayoutOrder = index,
			Parent = body,
		}, { Kit.Corner(14), Kit.Stroke(if equipped then C.Green else item.Color, 2, if equipped then 0 else 0.5) })
		local swatch = Kit.New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 12),
			Size = UDim2.fromOffset(64, 64),
			BackgroundColor3 = item.Color,
			Parent = card,
		}, { Kit.Corner(32) })
		Kit.Text({
			Size = UDim2.fromScale(1, 1),
			Font = Theme.Fonts.Title,
			TextSize = 26,
			TextColor3 = C.Background,
			Text = string.sub(item.DisplayName, 1, 1),
			Parent = swatch,
		})
		Kit.Text({
			Position = UDim2.fromOffset(6, 82),
			Size = UDim2.new(1, -12, 0, 22),
			TextSize = 18,
			Text = item.DisplayName,
			Parent = card,
		})
		Kit.Text({
			Position = UDim2.fromOffset(6, 104),
			Size = UDim2.new(1, -12, 0, 34),
			Font = Theme.Fonts.Body,
			TextSize = 12,
			TextColor3 = C.TextDim,
			Text = item.Description,
			Parent = card,
		})
		local label, color, action
		if equipped then
			label, color = "EQUIPPED", C.Green
		elseif owned then
			label, color, action = "EQUIP", C.Cyan, "Equip"
		else
			label = item.Price .. " COINS"
			color = if (profile.Coins or 0) >= item.Price then C.Yellow else C.Stroke
			action = "Buy"
		end
		local button = Kit.Button({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -20, 0, 36),
			Text = label,
			TextSize = 16,
			Color = color,
			TextColor = C.Background,
			Parent = card,
		}, function()
			if action then
				Net.Event("ShopAction"):FireServer(action, id)
			end
		end)
		button.AutoButtonColor = false
	end
end

---------------------------------------------------------------------------
-- QUESTS
---------------------------------------------------------------------------

function MenuController:_fillQuests(body: Instance)
	local profile = self.Controllers.ClientState.Profile
	if not profile then
		return
	end
	Kit.List(Enum.FillDirection.Vertical, 8).Parent = body
	for index, id in QuestConfig.Order do
		local quest = QuestConfig.Quests[id]
		local progress = math.min((profile.Stats or {})[quest.Stat] or 0, quest.Goal)
		local claimed = profile.ClaimedQuests[id] == true
		local done = progress >= quest.Goal
		local row = Kit.New("Frame", {
			Size = UDim2.new(1, -16, 0, 62),
			BackgroundColor3 = C.PanelLight,
			LayoutOrder = index,
			Parent = body,
		}, { Kit.Corner(10) })
		Kit.Text({
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.new(1, -200, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 17,
			Text = quest.Text,
			Parent = row,
		})
		Kit.Text({
			Position = UDim2.fromOffset(14, 32),
			Size = UDim2.new(1, -200, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.Fonts.Body,
			TextSize = 14,
			TextColor3 = C.TextDim,
			Text = string.format("%d / %d   ·   +%d coins  +%d XP", progress, quest.Goal, quest.Reward.Coins, quest.Reward.XP),
			Parent = row,
		})
		local barBack = Kit.New("Frame", {
			Position = UDim2.new(0, 14, 1, -8),
			Size = UDim2.new(1, -200, 0, 4),
			BackgroundColor3 = C.Panel,
			Parent = row,
		}, { Kit.Corner(2) })
		Kit.New("Frame", {
			Size = UDim2.fromScale(progress / quest.Goal, 1),
			BackgroundColor3 = if done then C.Green else C.Cyan,
			Parent = barBack,
		}, { Kit.Corner(2) })
		Kit.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(150, 40),
			Text = if claimed then "CLAIMED" elseif done then "CLAIM" else "IN PROGRESS",
			TextSize = 15,
			Color = if claimed then C.Panel elseif done then C.Green else C.Panel,
			TextColor = if done and not claimed then C.Background else C.TextDim,
			Parent = row,
		}, function()
			if done and not claimed then
				Net.Event("ClaimQuest"):FireServer(id)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------------

local SETTINGS = {
	{ Key = "Sfx", Label = "Sound effects" },
	{ Key = "Hints", Label = "Show hints & tips" },
	{ Key = "ReducedEffects", Label = "Reduced effects (low-end devices)" },
}

function MenuController:_fillSettings(body: Instance)
	local profile = self.Controllers.ClientState.Profile
	if not profile then
		return
	end
	Kit.List(Enum.FillDirection.Vertical, 10).Parent = body
	for index, setting in SETTINGS do
		local value = profile.Settings[setting.Key] == true
		local row = Kit.New("Frame", {
			Size = UDim2.new(1, -16, 0, 56),
			BackgroundColor3 = C.PanelLight,
			LayoutOrder = index,
			Parent = body,
		}, { Kit.Corner(10) })
		Kit.Text({
			Position = UDim2.fromOffset(16, 0),
			Size = UDim2.new(1, -180, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 19,
			Text = setting.Label,
			Parent = row,
		})
		Kit.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(110, 40),
			Text = if value then "ON" else "OFF",
			Color = if value then C.Green else C.Panel,
			TextColor = if value then C.Background else C.TextDim,
			Parent = row,
		}, function()
			Net.Event("UpdateSettings"):FireServer(setting.Key, not value)
		end)
	end
	local state = self.Controllers.ClientState
	Kit.Text({
		Size = UDim2.new(1, -16, 0, 60),
		TextSize = 14,
		Font = Theme.Fonts.Body,
		TextColor3 = C.TextDim,
		LayoutOrder = 99,
		Text = "Controls:  PC  Q = ability, E = interact   ·   Gamepad  Y = ability, X = interact   ·   Mobile  on-screen buttons"
			.. (if state.MemoryOnly then "\n(Studio: DataStore disabled - progress is not saved. Enable API Services to test saving.)" else ""),
		Parent = body,
	})
end

return MenuController
