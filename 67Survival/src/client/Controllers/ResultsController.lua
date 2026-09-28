--[[
	ResultsController - "YOU DIED" (with a limited Robux revive offer and a countdown) and the
	end screen: VICTORY / RUN OVER with your hero (its VICTORY pose when you won), time
	survived, enemies defeated, level, coins, FRAGMENTS, new Collection Book entries,
	achievements and unlocks, the final build (evolutions glow). One optional EXTRA CHEST
	(developer product). PLAY AGAIN is the big button: the "one more run" loop starts here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Format = require(Shared.Util.Format)
local WeaponData = require(Shared.WeaponData)
local AchievementData = require(Shared.AchievementData)
local MonetizationData = require(Shared.MonetizationData)
local CosmeticData = require(Shared.CosmeticData)
local RunService = game:GetService("RunService")

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)
local Icons = require(script.Parent.Parent.UI.Icons)
local Previews = require(script.Parent.Parent.UI.Previews)
local HeroAnimator = require(script.Parent.HeroAnimator)

local ResultsController = {}

local C = Theme.Colors
local F = Theme.Fonts

local STATS = {
	{ Key = "Time", Text = "TIME SURVIVED" },
	{ Key = "Kills", Text = "ENEMIES DEFEATED" },
	{ Key = "Level", Text = "LEVEL REACHED" },
	{ Key = "Coins", Text = "COINS EARNED" },
	{ Key = "Fragments", Text = "FRAGMENTS" },
	{ Key = "Collection", Text = "COLLECTION" },
}

function ResultsController:Init(controllers)
	self.C = controllers
	local gui, root = Kit.ScreenGui("S67Results", 35, Players.LocalPlayer:WaitForChild("PlayerGui"))
	self.Gui = gui
	self.Root = root

	-- death prompt
	local death = Kit.New("Frame", {
		Name = "Death",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(30, 4, 12),
		BackgroundTransparency = 0.35,
		Visible = false,
		Parent = root,
	})
	Kit.Label({
		Text = "YOU DIED",
		Size = UDim2.fromOffset(600, 70),
		Position = UDim2.new(0.5, 0, 0.5, -110),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = F.Title,
		MaxTextSize = 64,
		TextColor3 = C.Danger,
		Parent = death,
	})
	self.DeathTimer = Widgets.Bar(death, UDim2.fromOffset(300, 8), UDim2.new(0.5, -150, 0.5, -58), C.Danger)
	self.DeathTimer.Label.Visible = false
	local revive, reviveLabel = Kit.Button({
		Name = "Revive",
		Text = "REVIVE",
		Size = UDim2.fromOffset(300, 60),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = C.Accent,
		Dark = C.AccentDark,
		TextSize = 21,
		OnClick = function()
			self.C.ClientData:Fire("Revive")
		end,
		Parent = death,
	})
	self.ReviveLabel = reviveLabel
	self.ReviveButton = revive
	Kit.Button({
		Name = "GiveUp",
		Text = "GIVE UP",
		Size = UDim2.fromOffset(200, 46),
		Position = UDim2.new(0.5, 0, 0.5, 64),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = C.Neutral,
		TextSize = 16,
		OnClick = function()
			self.C.ClientData:Fire("GiveUp")
		end,
		Parent = death,
	})
	self.Death = death

	-- results (inside a fit frame that shrinks it on short screens)
	local fit = Kit.New("Frame", {
		Name = "ResultsFit",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(660, 540),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = root,
	})
	Kit.New("UIScale", { Name = "FitScale", Parent = fit })
	self.Fit = fit
	local panel = Kit.Panel({
		Name = "Results",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = Theme.GlassStrong,
		Visible = false,
		Radius = 22,
		Parent = fit,
	})
	self.PanelStroke = panel:FindFirstChildOfClass("UIStroke")
	self.ResultTitle = Kit.Label({
		Name = "ResultTitle",
		Text = "RUN OVER",
		Size = UDim2.new(1, -60, 0, 52),
		Position = UDim2.fromOffset(30, 26),
		Font = F.Title,
		MaxTextSize = 50,
		Parent = panel,
	})
	self.ResultSub = Kit.Label({
		Text = "",
		Size = UDim2.new(1, -60, 0, 20),
		Position = UDim2.fromOffset(30, 82),
		Font = F.Medium,
		MaxTextSize = 17,
		TextColor3 = C.TextDim,
		Parent = panel,
	})
	local grid = Kit.New("Frame", {
		Name = "Stats",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -60, 0, 142),
		Position = UDim2.fromOffset(30, 122),
		Parent = panel,
	})
	Kit.New("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -8, 0, 66),
		CellPadding = UDim2.fromOffset(12, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	self.StatLabels = {}
	self.NewTags = {}
	for i, entry in STATS do
		local cell = Kit.Panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.SurfaceLight, BackgroundTransparency = 0.45, Radius = 12, LayoutOrder = i, Parent = grid })
		Widgets.Caption(cell, entry.Text, UDim2.fromOffset(14, 11), 150)
		self.StatLabels[entry.Key] = Kit.Label({
			Text = "",
			Size = UDim2.new(1, -28, 0, 26),
			Position = UDim2.fromOffset(14, 30),
			Font = F.Title,
			MaxTextSize = 23,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = cell,
		})
		if entry.Key == "Time" or entry.Key == "Level" then
			local tag = Widgets.Tag(cell, "BEST", C.Gold, UDim2.new(1, -10, 0, 10), UDim2.fromOffset(46, 20))
			tag.AnchorPoint = Vector2.new(1, 0)
			self.NewTags[entry.Key] = tag
		end
	end
	Widgets.Caption(panel, "FINAL BUILD", UDim2.fromOffset(30, 290))
	self.Build = Kit.New("Frame", {
		Name = "Build",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -60, 0, 44),
		Position = UDim2.fromOffset(30, 318),
		Parent = panel,
	})
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = self.Build,
	})
	-- your hero (victory pose)
	self.HeroHolder = Kit.New("Frame", {
		Name = "Hero",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(120, 130),
		Position = UDim2.new(1, -18, 0, 10),
		AnchorPoint = Vector2.new(1, 0),
		Parent = panel,
	})
	-- one optional extra chest (never pushed: a small button)
	self.ChestButton, self.ChestLabel = Kit.Button({
		Name = "ExtraChest",
		Text = "",
		Size = UDim2.fromOffset(210, 34),
		Position = UDim2.new(1, -30, 0, 280),
		AnchorPoint = Vector2.new(1, 0),
		Color = C.Neutral,
		TextSize = 13,
		OnClick = function()
			self.C.ClientData:Fire("Buy", "Product", "ExtraChest")
			self.ChestButton.Visible = false
		end,
		Parent = panel,
	})
	self.Extra = Kit.Label({
		Name = "Extra",
		Text = "",
		Size = UDim2.new(1, -60, 0, 54),
		Position = UDim2.fromOffset(30, 372),
		TextWrapped = true,
		Font = F.Bold,
		MaxTextSize = 16,
		TextColor3 = C.Gold,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = panel,
	})
	Kit.Button({
		Name = "PlayAgain",
		Text = "PLAY AGAIN",
		Size = UDim2.fromOffset(280, 60),
		Position = UDim2.new(0.5, -6, 1, -28),
		AnchorPoint = Vector2.new(1, 1),
		Color = C.Accent,
		Dark = C.AccentDark,
		TextSize = 22,
		Font = F.Title,
		OnClick = function()
			self:Hide()
			self.C.ClientData:Fire("StartRun")
			-- safety net: if the server did not start a run, go back to the lobby
			task.delay(4, function()
				if not self.C.RunClient.Active and not self:IsOpen() then
					self.C.RunClient:Leave()
					self.C.ClientData:Fire("ReturnToLobby")
				end
			end)
		end,
		Parent = panel,
	})
	Kit.Button({
		Name = "Lobby",
		Text = "LOBBY",
		Size = UDim2.fromOffset(200, 60),
		Position = UDim2.new(0.5, 6, 1, -28),
		AnchorPoint = Vector2.new(0, 1),
		Color = C.Neutral,
		TextSize = 19,
		OnClick = function()
			self:Hide()
			self.C.RunClient:Leave()
			self.C.ClientData:Fire("ReturnToLobby")
		end,
		Parent = panel,
	})
	self.Panel = panel
end

function ResultsController:ShowDeath(p)
	self.Death.Visible = true
	self.ReviveButton.Visible = p.CanBuyRevive == true
	local product = MonetizationData.ProductByKey.Revive
	self.ReviveLabel.Text = string.format("REVIVE  ·  R$ %d", product.Price)
	self.C.SoundController:Play("Death")
	self.C.CameraController:ZoomPunch(0.6, 1)
	local window = p.Window or 10
	local started = os.clock()
	self.DeathToken = (self.DeathToken or 0) + 1
	local token = self.DeathToken
	task.spawn(function()
		while self.Death.Visible and self.DeathToken == token do
			local left = window - (os.clock() - started)
			self.DeathTimer:Set(left / window)
			if left <= 0 then
				break
			end
			task.wait(0.1)
		end
	end)
end

function ResultsController:HideDeath()
	self.Death.Visible = false
end

function ResultsController:ShowResults(p)
	self:HideDeath()
	local s, r = p.Summary, p.Rewards
	local victory = s.Victory
	self.ResultTitle.Text = if victory then "VICTORY" elseif s.Reason == "Quit" then "RUN ENDED" else "RUN OVER"
	self.ResultTitle.TextColor3 = if victory then C.Gold else C.Text
	self.ResultSub.Text = if victory then "You survived the horde. Legend." else "The horde got you. One more run?"
	if self.PanelStroke then
		self.PanelStroke.Color = if victory then C.Gold else C.Border
		self.PanelStroke.Transparency = if victory then 0.3 else Theme.BorderTransparency
	end
	local L = self.StatLabels
	L.Time.Text = Format.Time(s.Time)
	L.Kills.Text = Format.Commas(s.Kills)
	L.Level.Text = tostring(s.Level)
	L.Coins.Text = "+" .. Format.Commas(r.Coins)
	L.Coins.TextColor3 = C.Gold
	L.Fragments.Text = "+" .. Format.Commas(r.Fragments or 0)
	L.Fragments.TextColor3 = C.Fragment
	L.Collection.Text = string.format("%d/%d", r.CollectionCount or 0, r.CollectionTotal or 0) .. (if (r.NewCollection or 0) > 0 then string.format("  +%d", r.NewCollection) else "")
	self.NewTags.Time.Visible = r.Best.Time == true
	self.NewTags.Level.Visible = r.Best.Level == true

	Widgets.Clear(self.Build)
	local order = 0
	for _, w in s.Build.Weapons do
		local def = WeaponData.ByKey[w.Key]
		if def and order < 11 then
			order += 1
			local slot = Kit.Panel({ Size = UDim2.fromOffset(40, 40), LayoutOrder = order, Radius = 10, Parent = self.Build })
			if w.Evolved then
				local stroke = slot:FindFirstChildOfClass("UIStroke") :: UIStroke
				stroke.Color = C.Mythic
				stroke.Transparency = 0.1
				stroke.Thickness = 2
			end
			Icons.Make(slot, "Weapon", w.Key, 36, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
		end
	end
	for _, p in s.Build.Passives or {} do
		if order < 11 then
			order += 1
			Icons.Make(self.Build, "Stat", p.Key, 40, { LayoutOrder = order })
		end
	end

	-- the hero: victory pose when you won
	Widgets.Clear(self.HeroHolder)
	local data = self.C.ClientData.Data
	local equipped = data and data.Cosmetics and data.Cosmetics.Equipped
	local vf = Previews.Hero(self.HeroHolder, s.Hero or "Rookie", {
		Skin = CosmeticData.Style(equipped, "HeroSkin"),
		Hat = CosmeticData.Style(equipped, "Hat"),
		Turn = -10,
	})
	self:AnimateHero(vf, if victory then CosmeticData.Style(equipped, "VictoryAnim") else nil)

	-- extra chest: once, and only if coins were earned
	self.ChestButton.Visible = (r.Coins or 0) > 0
	self.ChestLabel.Text = string.format("EXTRA CHEST  ·  R$ %d", MonetizationData.ProductByKey.ExtraChest.Price)

	-- the most important news first, at most 4 items (the rest as "+N more")
	local lines = {}
	if r.LevelAfter > r.LevelBefore then
		table.insert(lines, "Account level " .. r.LevelAfter .. "!")
	end
	if (r.NewCollection or 0) > 0 then
		table.insert(lines, string.format("+%d in the Collection Book", r.NewCollection))
	end
	if (s.Evolved or 0) > 0 then
		table.insert(lines, string.format("%d evolution%s", s.Evolved, if s.Evolved == 1 then "" else "s"))
	end
	for _, name in r.Unlocks do
		table.insert(lines, "Unlocked: " .. name)
	end
	for _, key in r.Achievements do
		local def = AchievementData.ByKey[key]
		if def then
			table.insert(lines, "Achievement: " .. def.Name)
		end
	end
	if r.FirstToday then
		table.insert(lines, "First run of the day bonus")
	end
	if r.Multiplier and r.Multiplier > 1 then
		table.insert(lines, string.format("Bonus x%.2f", r.Multiplier))
	end
	local shown = table.move(lines, 1, math.min(4, #lines), 1, {})
	if #lines > 4 then
		table.insert(shown, string.format("+%d more", #lines - 4))
	end
	self.Extra.Text = table.concat(shown, "   ·   ")

	Widgets.Fit(self.Fit, 540)
	self.Panel.Visible = true
	Kit.Appear(self.Panel)
	Kit.Blur("results", 12)
	self.C.HudController:SetCovered(true)
	self.C.BannerController:ClearRewardToasts()
	self.C.BannerController:ClearRun()
	self.C.SoundController:Play(if victory then "Victory" else "RunOver")
end

-- the hero model in the results picture: a victory pose (or a calm idle)
function ResultsController:AnimateHero(vf: ViewportFrame, pose: string?)
	if self.HeroConn then
		self.HeroConn:Disconnect()
		self.HeroConn = nil
	end
	local parts = {}
	for _, p in vf:GetChildren() do
		if p:IsA("BasePart") then
			table.insert(parts, { Part = p, Base = p.CFrame })
		end
	end
	local started = os.clock()
	self.HeroConn = RunService.RenderStepped:Connect(function()
		if not vf.Parent or not self.Panel.Visible then
			if self.HeroConn then
				self.HeroConn:Disconnect()
				self.HeroConn = nil
			end
			return
		end
		local t = os.clock() - started
		local offset = if pose then HeroAnimator.Pose(pose, t % 2.6) else CFrame.new(0, math.sin(t * 2) * 0.08, 0)
		for _, entry in parts do
			entry.Part.CFrame = offset * entry.Base
		end
	end)
end

function ResultsController:Hide()
	if self.Panel.Visible then
		Kit.Blur("results", 0)
	end
	self.Panel.Visible = false
	self:HideDeath()
end

function ResultsController:IsOpen(): boolean
	return self.Panel.Visible
end

function ResultsController:Start() end

return ResultsController
