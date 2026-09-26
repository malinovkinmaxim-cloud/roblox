--[[
	HudController - the always-on screen. Understandable in 3 seconds:

	  top      [🪙 coins]  [📏 HEIGHT  1.25K m  (title)]  [💎 gems]
	           [♻️ REBIRTH ██████░░ 72%]   world • multiplier • "taller than X% of players"
	  left     FREE, PETS, SHOP, REBIRTH, BOOSTS, QUESTS, DAILY   (red badges when something waits)
	  right    TOP, WORLDS, SETTINGS  + active boost timers
	  bottom   [TAP POWER]  [   TAP TO GROW   ]  [AUTO GROW]
	           (phone: huge TAP button bottom-right, away from the thumbstick)

	The HEIGHT number follows the visual body (same smoothing), so number and body grow together.

	ONE-BUTTON MODE (default): the upgrade buttons and menus fold away (a single ☰ opens them),
	the server buys / claims / hatches by itself (a line above the button shows what it does),
	and when a rebirth is ready the TAP button itself turns into "♻️ REBIRTH!" - the whole
	game is played with that one button (or Space / click).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local ZoneConfig = require(Shared.ZoneConfig)
local BoostConfig = require(Shared.BoostConfig)
local EventConfig = require(Shared.EventConfig)
local RewardConfig = require(Shared.RewardConfig)

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Widgets = require(UI.Widgets)

local LocalPlayer = Players.LocalPlayer

local HudController = {}

function HudController:Init(controllers)
	self.Controllers = controllers
	self.Touch = Kit.IsTouch()
	self.DisplayCoins = 0
	self.DisplayGems = 0
	self.Badges = {}
	self.MenuOpen = false
	self.RebirthArmed = false
	self.RebirthReadySince = 0
	self.OneButton = true
end

function HudController:IsOneButton(): boolean
	return self.Controllers.ClientData:Setting("OneButton")
end

function HudController:IsRebirthArmed(): boolean
	return self.RebirthArmed == true
end

-- after the REBIRTH press: stop treating presses as rebirths until the next data update
function HudController:Disarm()
	self.RebirthReady = false
	self.RebirthArmed = false
	self:UpdatePrimary()
end

---------------------------------------------------------------------------
-- building
---------------------------------------------------------------------------
function HudController:BuildTop(root: Frame)
	-- height card
	local card = Kit.Panel({
		Name = "HeightCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(330, 88),
		Parent = root,
	})
	Kit.Gradient(card, Color3.fromRGB(120, 80, 255), Color3.fromRGB(60, 40, 170))
	Kit.Label({
		Position = UDim2.fromOffset(12, 5),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "📏 HEIGHT",
		TextColor3 = Theme.Colors.TextDim,
		Parent = card,
	})
	self.HeightLabel = Kit.Label({
		Position = UDim2.fromOffset(10, 25),
		Size = UDim2.new(1, -20, 0, 44),
		Text = "0.01 m",
		Font = Theme.Fonts.Title,
		StrokeThickness = 3,
		Parent = card,
	})
	self.TitleLabel = Kit.Label({
		Position = UDim2.fromOffset(10, 67),
		Size = UDim2.new(1, -20, 0, 18),
		Text = "Tiny",
		Parent = card,
	})
	self.HeightCard = card

	local function pill(icon: string, color: Color3, anchorX: number, x: number): TextLabel
		local frame = Kit.Panel({
			AnchorPoint = Vector2.new(anchorX, 0),
			Position = UDim2.new(0.5, x, 0, 16),
			Size = UDim2.fromOffset(190, 50),
			BackgroundColor3 = Theme.Colors.PanelDark,
			Radius = 25,
			Parent = root,
		})
		Kit.Label({
			Position = UDim2.fromOffset(6, 5),
			Size = UDim2.fromOffset(40, 40),
			Text = icon,
			StrokeThickness = 0,
			Parent = frame,
		})
		return Kit.Label({
			Position = UDim2.fromOffset(48, 7),
			Size = UDim2.new(1, -58, 1, -14),
			Text = "0",
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.Fonts.Title,
			Parent = frame,
		})
	end
	self.CoinsLabel = pill("🪙", Theme.Colors.Coin, 1, -175)
	self.GemsLabel = pill("💎", Theme.Colors.Gem, 0, 175)

	-- rebirth progress (click = open rebirth)
	local barButton = Kit.New("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 102),
		Size = UDim2.fromOffset(330, 26),
		Parent = root,
	})
	self.RebirthBar = Widgets.ProgressBar(barButton, UDim2.fromScale(1, 1), UDim2.new(), Theme.Colors.Green)
	barButton.Activated:Connect(function()
		self.Controllers.PanelController:Toggle("Rebirth")
	end)

	self.ZoneLabel = Kit.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 132),
		Size = UDim2.fromOffset(560, 20),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		Parent = root,
	})

	-- server event banner
	local event = Kit.Panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 158),
		Size = UDim2.fromOffset(440, 34),
		Visible = false,
		Radius = 17,
		Parent = root,
	})
	self.EventFrame = event
	self.EventLabel = Kit.Label({
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 1, -8),
		Text = "",
		Font = Theme.Fonts.Title,
		Parent = event,
	})
end

function HudController:BuildSides(root: Frame)
	local panels = self.Controllers.PanelController
	local size = if self.Touch then 58 else 66
	-- one-button mode: a single MENU button unfolds all the other buttons
	local menuButton = Widgets.IconButton(root, "☰", "MENU", Theme.Colors.PanelLight, size, 0, function()
		self.MenuOpen = not self.MenuOpen
		self:ApplyMode()
	end)
	menuButton.Position = UDim2.new(0, 10, 0, if self.Touch then 70 else 150)
	local _, setMenuBadge = Widgets.Badge(menuButton)
	self.MenuButton, self.SetMenuBadge = menuButton, setMenuBadge
	local columnTop = (if self.Touch then 70 else 150) + size + 8

	local left = Kit.New("Frame", {
		Name = "Left",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 10, 0, columnTop),
		Size = UDim2.fromOffset(if self.Touch then size * 2 + 8 else size, 560),
		Parent = root,
	})
	self.LeftColumn = left
	if self.Touch then
		Kit.New("UIGridLayout", {
			CellSize = UDim2.fromOffset(size, size),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = left,
		})
	else
		Kit.New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = left })
	end
	local items = {
		{ "Free", "🎁", "FREE", Theme.Colors.Yellow },
		{ "Pets", "🐾", "PETS", Theme.Colors.Orange },
		{ "Shop", "🛒", "SHOP", Theme.Colors.Green },
		{ "Rebirth", "♻️", "REBIRTH", Theme.Colors.Purple },
		{ "Boosts", "⚡", "BOOSTS", Theme.Colors.Blue },
		{ "Quests", "📜", "QUESTS", Theme.Colors.Pink },
		{ "Daily", "📅", "DAILY", Theme.Colors.Red },
	}
	for i, item in items do
		local button = Widgets.IconButton(left, item[2], item[3], item[4], size, i, function()
			panels:Toggle(item[1])
		end)
		local _, setBadge = Widgets.Badge(button)
		self.Badges[item[1]] = setBadge
		if item[1] == "Free" then
			self.FreeButton = button
		elseif item[1] == "Rebirth" then
			self.RebirthButton = button
		end
	end

	local right = Kit.New("Frame", {
		Name = "Right",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, if self.Touch then 70 else 150),
		Size = UDim2.fromOffset(size, 300),
		Parent = root,
	})
	self.RightColumn = right
	Kit.New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = right })
	for i, item in {
		{ "Leaderboard", "🏆", "TOP", Theme.Colors.Yellow },
		{ "Worlds", "🌍", "WORLDS", Theme.Colors.Green },
		{ "Settings", "⚙️", "SETTINGS", Theme.Colors.GrayDark },
	} do
		Widgets.IconButton(right, item[2], item[3], item[4], size, i, function()
			panels:Toggle(item[1])
		end)
	end

	-- active boosts (right, under the buttons)
	self.BoostList = Kit.New("Frame", {
		Name = "Boosts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, (if self.Touch then 70 else 150) + 3 * (size + 8) + 6),
		Size = UDim2.fromOffset(150, 240),
		Parent = root,
	})
	Kit.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right, Parent = self.BoostList })
	self.BoostPills = {}
end

function HudController:BuildBottom(root: Frame)
	local tapController = self.Controllers.TapController
	local touch = self.Touch

	local tap = Kit.Button({
		Name = "TapButton",
		Text = "TAP TO GROW",
		Color = Theme.Colors.Green,
		Font = Theme.Fonts.Title,
		AnchorPoint = if touch then Vector2.new(1, 1) else Vector2.new(0.5, 1),
		Position = if touch then UDim2.new(1, -16, 1, -16) else UDim2.new(0.5, 0, 1, -16),
		Size = if touch then UDim2.fromOffset(310, 150) else UDim2.fromOffset(340, 104),
		Radius = 24,
		Parent = root,
	})
	local label = tap:FindFirstChild("Label") :: TextLabel
	label.Size = UDim2.new(1, -24, 0.62, 0)
	label.Position = UDim2.fromOffset(12, 6)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 4
	end
	self.TapInfo = Kit.Label({
		Name = "Info",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -24, 0.3, 0),
		Text = "+1 cm",
		TextColor3 = Color3.fromRGB(230, 255, 230),
		Parent = tap,
	})
	-- every finger / click that lands on the button is a tap (multi-touch friendly)
	tap.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			tapController:Press(Vector2.new(input.Position.X, input.Position.Y))
			Kit.Pop(tap, 0.06)
		end
	end)
	self.TapButton = tap
	self.TapLabel = label
	self.TapSizes = {
		Classic = if touch then Vector2.new(310, 150) else Vector2.new(340, 104),
		OneButton = if touch then Vector2.new(340, 180) else Vector2.new(420, 128),
	}
	self.TapBaseSize = self.TapSizes.OneButton

	-- idle "breathing" so the button begs to be pressed (size, so it never fights the press UIScale);
	-- a ready REBIRTH breathes faster and bigger
	RunService.Heartbeat:Connect(function()
		local armed = self.RebirthArmed
		local k = 1 + math.sin(os.clock() * (if armed then 8 else 3)) * (if armed then 0.05 else 0.025)
		tap.Size = UDim2.fromOffset(self.TapBaseSize.X * k, self.TapBaseSize.Y * k)
	end)

	-- one-button mode: what the autopilot is doing, right above the button
	self.AutoLine = Kit.Label({
		Name = "AutoLine",
		AnchorPoint = if touch then Vector2.new(1, 1) else Vector2.new(0.5, 1),
		Position = if touch then UDim2.new(1, -16, 1, -202) else UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(if touch then 340 else 520, 26),
		Text = "",
		TextColor3 = Color3.fromRGB(230, 240, 255),
		Visible = false,
		Parent = root,
	})

	local function upgradeButton(kind: string, anchor: Vector2, position: UDim2): (TextButton, TextLabel, TextLabel)
		local button = Kit.Button({
			Name = kind,
			Color = Theme.Colors.Blue,
			AnchorPoint = anchor,
			Position = position,
			Size = if touch then UDim2.fromOffset(150, 84) else UDim2.fromOffset(176, 86),
			Radius = 16,
			Parent = root,
			OnClick = function()
				self.Controllers.ClientData:Fire("BuyUpgrade", kind)
			end,
		})
		local main = button:FindFirstChild("Label") :: TextLabel
		main.Size = UDim2.new(1, -12, 0.5, 0)
		main.Position = UDim2.fromOffset(6, 4)
		local price = Kit.Label({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -5),
			Size = UDim2.new(1, -12, 0.38, 0),
			Text = "",
			TextColor3 = Theme.Colors.Coin,
			Parent = button,
		})
		return button, main, price
	end
	if touch then
		self.TapUpgrade, self.TapUpgradeLabel, self.TapUpgradePrice = upgradeButton("TapPower", Vector2.new(1, 1), UDim2.new(1, -172, 1, -176))
		self.AutoUpgrade, self.AutoUpgradeLabel, self.AutoUpgradePrice = upgradeButton("AutoGrow", Vector2.new(1, 1), UDim2.new(1, -16, 1, -176))
	else
		self.TapUpgrade, self.TapUpgradeLabel, self.TapUpgradePrice = upgradeButton("TapPower", Vector2.new(1, 1), UDim2.new(0.5, -186, 1, -16))
		self.AutoUpgrade, self.AutoUpgradeLabel, self.AutoUpgradePrice = upgradeButton("AutoGrow", Vector2.new(0, 1), UDim2.new(0.5, 186, 1, -16))
	end

	-- auto tap switch (only when owned via pass or active via boost)
	local autoButton, autoLabel = Kit.Button({
		Name = "AutoTap",
		Color = Theme.Colors.Purple,
		AnchorPoint = if touch then Vector2.new(1, 1) else Vector2.new(0.5, 1),
		Position = if touch then UDim2.new(1, -16, 1, -232) else UDim2.new(0.5, 0, 1, -180),
		Size = UDim2.fromOffset(170, 36),
		Radius = 18,
		Parent = root,
		OnClick = function()
			local data = self.Controllers.ClientData
			local passes = data:Get("Passes") or {}
			if passes.AutoTap then
				data:Fire("SetAutoTap", not data:Setting("AutoTap"))
			end
		end,
	})
	autoButton.Visible = false
	self.AutoTapButton, self.AutoTapLabel = autoButton, autoLabel
end

---------------------------------------------------------------------------
-- refreshing
---------------------------------------------------------------------------
function HudController:RefreshStats()
	local data = self.Controllers.ClientData
	local stats = data:Get("Stats")
	local rates = data:Get("Rates")
	if not stats or not rates then
		return
	end

	-- upgrades
	local tapCost = Formulas.TapCost(stats.TapLevel)
	self.TapUpgradeLabel.Text = string.format("👆 TAP %s ➜ %s", Format.Mult(Formulas.TapPower(stats.TapLevel)), Format.Mult(Formulas.TapPower(stats.TapLevel + 1)))
	self.TapUpgradePrice.Text = if tapCost then "🪙 " .. Format.Number(tapCost) else "MAX"
	local canTap = tapCost ~= nil and stats.Coins >= tapCost
	Kit.SetButtonColor(self.TapUpgrade, if canTap then Theme.Colors.Blue else Theme.Colors.GrayDark)

	local autoCost = Formulas.AutoCost(stats.AutoLevel)
	local autoNow = Formulas.AutoRate(stats.AutoLevel)
	local autoNext = Formulas.AutoRate(stats.AutoLevel + 1)
	self.AutoUpgradeLabel.Text = if stats.AutoLevel == 0 then "🌱 AUTO GROW" else string.format("🌱 %s/s ➜ %s", Format.Gain(autoNow), Format.Gain(autoNext))
	self.AutoUpgradePrice.Text = if autoCost then "🪙 " .. Format.Number(autoCost) else "MAX"
	local canAuto = autoCost ~= nil and stats.Coins >= autoCost
	Kit.SetButtonColor(self.AutoUpgrade, if canAuto then Theme.Colors.Blue else Theme.Colors.GrayDark)
	self.CanUpgrade = canTap or canAuto

	-- tap info
	self.TapInfoText = string.format("%s  •  🪙 +%s", Format.Gain(rates.TapGain or 1), Format.Number(rates.TapCoins or 1))

	-- rebirth progress
	local cost = stats.RebirthCost or Formulas.RebirthCost(stats.Rebirths)
	local fraction = math.clamp(stats.Height / cost, 0, 1)
	local ready = stats.Height >= cost
	if ready and not self.RebirthReady then
		self.RebirthReadySince = os.clock()
	end
	self.RebirthReady = ready
	self.RebirthInfo = string.format(
		"%s ➜ %s GROWTH  •  +%s 💎",
		Format.Mult(Formulas.RebirthMultiplier(stats.Rebirths)),
		Format.Mult(Formulas.RebirthMultiplier(stats.Rebirths + 1)),
		Format.Number(Formulas.RebirthGems(stats.Rebirths + 1))
	)
	local pets = data:Get("Pets")
	self.AutoLine.Text = string.format(
		"🤖 AUTO:  👆 %s   🌱 %s/s   🐾 %s",
		Format.Mult(Formulas.TapPower(stats.TapLevel)),
		Format.Gain(rates.AutoGain or 0),
		Format.Mult(pets and pets.Multiplier or 1)
	)
	self.RebirthBar.Set(fraction, if ready then "♻️ REBIRTH READY! (click)" else string.format("♻️ REBIRTH  %s / %s", Format.Length(stats.Height), Format.Length(cost)))

	-- zone line
	local zone = ZoneConfig.Zones[stats.ZoneIndex or 1] or ZoneConfig.Zones[1]
	local line = string.format("🌍 %s  •  %s growth", zone.Name, Format.Mult(rates.Height or 1))
	if stats.Percentile then
		line ..= string.format("  •  taller than %d%% of players", math.floor(stats.Percentile * 100))
	end
	if stats.InVIPArea then
		line ..= "  •  👑 VIP +20%"
	end
	self.ZoneLabel.Text = line
end

function HudController:RefreshBadges()
	local data = self.Controllers.ClientData
	local rewards = data:Get("Rewards")
	local boosts = data:Get("Boosts")
	local attention = false -- anything waiting -> the one-button MENU gets a badge too
	if rewards then
		local daily = rewards.Daily and rewards.Daily.CanClaim == true
		self.Badges.Daily(daily)
		local elapsed = (rewards.PlaytimeElapsed or 0) + (os.clock() - data.RewardsClock)
		local ready = 0
		for i, gift in RewardConfig.Playtime do
			if not (rewards.PlaytimeClaimed and rewards.PlaytimeClaimed[tostring(i)]) and elapsed >= gift.Minutes * 60 then
				ready += 1
			end
		end
		self.Badges.Free(ready)
		local quests = 0
		for _, quest in RewardConfig.Quests do
			local progress = rewards.Quests and rewards.Quests.Progress[quest.Stat] or 0
			if progress >= quest.Goal and not (rewards.Quests.Claimed and rewards.Quests.Claimed[quest.Id]) then
				quests += 1
			end
		end
		self.Badges.Quests(quests)
		attention = daily or ready > 0 or quests > 0
	end
	if boosts then
		local count = 0
		for _, n in boosts.Inventory or {} do
			count += n
		end
		self.Badges.Boosts(count)
		attention = attention or count > 0
	end
	self.Badges.Rebirth(self.RebirthReady == true)
	self.SetMenuBadge(attention and not self.MenuOpen)
end

function HudController:RefreshBoosts()
	local data = self.Controllers.ClientData
	local boosts = data:Get("Boosts")
	local active = boosts and boosts.Active or {}
	for id, pill in self.BoostPills do
		if not active[id] or data:BoostLeft(id) <= 0 then
			pill.Frame:Destroy()
			self.BoostPills[id] = nil
		end
	end
	for order, id in BoostConfig.Order do
		local left = data:BoostLeft(id)
		if left > 0 then
			local pill = self.BoostPills[id]
			if not pill then
				local def = BoostConfig.Boosts[id]
				local frame = Kit.Panel({
					Size = UDim2.fromOffset(150, 34),
					BackgroundColor3 = def.Color,
					LayoutOrder = order,
					Radius = 17,
					Parent = self.BoostList,
				})
				local label = Kit.Label({
					Position = UDim2.fromOffset(8, 4),
					Size = UDim2.new(1, -16, 1, -8),
					Text = "",
					Parent = frame,
				})
				pill = { Frame = frame, Label = label, Icon = def.Icon }
				self.BoostPills[id] = pill
			end
			pill.Label.Text = pill.Icon .. " " .. Format.Time(left)
		end
	end
	-- auto tap button
	local passes = data:Get("Passes") or {}
	local boostTap = data:BoostLeft("AutoTap") > 0
	if passes.AutoTap or boostTap then
		self.AutoTapButton.Visible = true
		local on = boostTap or data:Setting("AutoTap")
		self.AutoTapLabel.Text = if boostTap then "🤖 AUTO TAP (boost)" elseif on then "🤖 AUTO TAP: ON" else "🤖 AUTO TAP: OFF"
		Kit.SetButtonColor(self.AutoTapButton, if on then Theme.Colors.Purple else Theme.Colors.GrayDark)
	else
		self.AutoTapButton.Visible = false
	end
end

function HudController:RefreshEvent()
	local id = Workspace:GetAttribute("EventId")
	local def = type(id) == "string" and EventConfig.Events[id] or nil
	if not def then
		self.EventFrame.Visible = false
		return
	end
	local endsAt = Workspace:GetAttribute("EventEndsAt")
	local left = if type(endsAt) == "number" then endsAt - Workspace:GetServerTimeNow() else 0
	if left <= 0 then
		self.EventFrame.Visible = false
		return
	end
	self.EventFrame.Visible = true
	self.EventFrame.BackgroundColor3 = def.Color
	self.EventLabel.Text = string.format("%s %s  —  %s", def.Icon, def.Name, Format.Time(left))
end

-- classic <-> one-button layout
function HudController:ApplyMode()
	local one = self:IsOneButton()
	self.OneButton = one
	self.TapUpgrade.Visible = not one
	self.AutoUpgrade.Visible = not one
	self.AutoLine.Visible = one
	self.MenuButton.Visible = one
	local columns = not one or self.MenuOpen
	self.LeftColumn.Visible = columns
	self.RightColumn.Visible = columns
	self.TapBaseSize = if one then self.TapSizes.OneButton else self.TapSizes.Classic
	self:UpdatePrimary()
end

-- the big button is TAP TO GROW, or REBIRTH! when a rebirth is ready (one-button mode only)
function HudController:UpdatePrimary()
	local armed = self.OneButton and self.RebirthReady == true and os.clock() - self.RebirthReadySince >= 0.8
	if armed ~= self.RebirthArmed then
		self.RebirthArmed = armed
		if armed then
			self.Controllers.SoundController:Play("Achievement")
			Kit.Pop(self.TapButton, 0.2)
		end
	end
	if armed then
		self.TapLabel.Text = "♻️ REBIRTH!"
		self.TapInfo.Text = self.RebirthInfo or ""
		Kit.SetButtonColor(self.TapButton, Theme.Colors.Purple)
	else
		self.TapLabel.Text = "TAP TO GROW"
		self.TapInfo.Text = self.TapInfoText or ""
		Kit.SetButtonColor(self.TapButton, Theme.Colors.Green)
	end
end

-- per frame: animated numbers that count up, and height synced with the visual body
function HudController:Step(dt: number)
	local data = self.Controllers.ClientData
	local stats = data:Get("Stats")
	if not stats then
		return
	end
	-- the number animates together with the body, and lands exactly on the server value
	local bodies = self.Controllers.BodyController
	local body = bodies:GetBody(LocalPlayer)
	local exact = stats.Height + bodies.LocalPending
	local height = exact
	if body then
		local shown = 10 ^ body.LogH
		if math.abs(shown - exact) > exact * 0.005 then
			height = shown
		end
	end
	self.HeightLabel.Text = Format.Length(height)
	local title = Formulas.Title(height)
	if self.LastTitle ~= title.Name then
		self.LastTitle = title.Name
		self.TitleLabel.Text = title.Name
		self.TitleLabel.TextColor3 = title.Color
		if self.TitleShown then
			Kit.Pop(self.HeightCard, 0.15)
		end
		self.TitleShown = true
	end

	local function approach(current: number, target: number): number
		if math.abs(target - current) < 0.5 or target < current * 0.5 or target > current * 1e6 then
			return target
		end
		return current + (target - current) * (1 - math.exp(-dt * 10))
	end
	self.DisplayCoins = approach(self.DisplayCoins, stats.Coins)
	self.DisplayGems = approach(self.DisplayGems, stats.Gems)
	self.CoinsLabel.Text = Format.Number(math.floor(self.DisplayCoins + 0.5))
	self.GemsLabel.Text = Format.Number(math.floor(self.DisplayGems + 0.5))
	self:UpdatePrimary()
end

function HudController:Start()
	local gui, root = Kit.ScreenGui("ChileHud", 1, LocalPlayer:WaitForChild("PlayerGui"))
	self.Gui = gui
	self.Root = root
	gui.Enabled = false
	self:BuildTop(root)
	self:BuildSides(root)
	self:BuildBottom(root)

	local data = self.Controllers.ClientData
	local function onLoaded()
		gui.Enabled = true
		self:ApplyMode()
		self:RefreshStats()
		self:RefreshBadges()
		self:RefreshBoosts()
	end
	if data.Loaded then
		onLoaded()
	else
		data.LoadedSignal:Connect(onLoaded)
	end
	data.Changed:Connect(function(section)
		if section == "Stats" or section == "Rates" then
			self:RefreshStats()
		elseif section == "Boosts" or section == "Passes" or section == "Settings" then
			self:RefreshBoosts()
			if section == "Settings" then
				self:ApplyMode()
			end
		end
		self:RefreshBadges()
	end)

	RunService.RenderStepped:Connect(function(dt)
		if gui.Enabled then
			self:Step(dt)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if gui.Enabled then
				self:RefreshEvent()
				self:RefreshBoosts()
				self:RefreshBadges()
				-- ready-to-claim things wiggle
				if self.RebirthReady then
					Kit.Pop(self.RebirthButton, 0.06)
				end
			end
		end
	end)
end

return HudController
