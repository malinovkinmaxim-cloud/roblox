--[[
	ResultsController - "YOU DIED" (with a limited Robux revive offer and a countdown) and the
	end screen: VICTORY / RUN OVER with time survived, enemies defeated, level, coins earned,
	bests, achievements and unlocks, the final build. PLAY AGAIN is the big button: the
	"one more run" loop starts from here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Format = require(Shared.Util.Format)
local WeaponData = require(Shared.WeaponData)
local AchievementData = require(Shared.AchievementData)
local MonetizationData = require(Shared.MonetizationData)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)
local Icons = require(script.Parent.Parent.UI.Icons)

local ResultsController = {}

local C = Theme.Colors
local F = Theme.Fonts

local STATS = {
	{ Key = "Time", Text = "TIME SURVIVED" },
	{ Key = "Kills", Text = "ENEMIES DEFEATED" },
	{ Key = "Level", Text = "LEVEL REACHED" },
	{ Key = "Coins", Text = "COINS EARNED" },
	{ Key = "BestTime", Text = "BEST TIME" },
	{ Key = "BestLevel", Text = "BEST LEVEL" },
}

function ResultsController:Init(controllers)
	self.C = controllers
	local gui, root = Kit.ScreenGui("BrainrotResults", 35, Players.LocalPlayer:WaitForChild("PlayerGui"))
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
		if entry.Key == "BestTime" or entry.Key == "BestLevel" then
			local tag = Widgets.Tag(cell, "NEW", C.Gold, UDim2.new(1, -10, 0, 10), UDim2.fromOffset(46, 20))
			tag.AnchorPoint = Vector2.new(1, 0)
			self.NewTags[entry.Key] = tag
		end
	end
	Widgets.Caption(panel, "FINAL BUILD", UDim2.fromOffset(30, 282))
	self.Build = Kit.New("Frame", {
		Name = "Build",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -60, 0, 44),
		Position = UDim2.fromOffset(30, 304),
		Parent = panel,
	})
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = self.Build,
	})
	self.Extra = Kit.Label({
		Name = "Extra",
		Text = "",
		Size = UDim2.new(1, -60, 0, 60),
		Position = UDim2.fromOffset(30, 362),
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
			local data = self.C.ClientData.Data
			self.C.ClientData:Fire("StartRun", data and data.Selected or "Goober", data and data.StartWeapon or "")
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
	self.ResultSub.Text = if victory then "You survived the brainrot. Legend." else "The horde got you. One more run?"
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
	L.BestTime.Text = Format.Time(r.BestTime)
	L.BestLevel.Text = tostring(r.BestLevel)
	self.NewTags.BestTime.Visible = r.Best.Time == true
	self.NewTags.BestLevel.Visible = r.Best.Level == true

	Widgets.Clear(self.Build)
	for i, w in s.Build.Weapons do
		local def = WeaponData.ByKey[w.Key]
		if def then
			local slot = Kit.Panel({ Size = UDim2.fromOffset(44, 44), LayoutOrder = i, Radius = 10, Parent = self.Build })
			if w.Awakened then
				local stroke = slot:FindFirstChildOfClass("UIStroke") :: UIStroke
				stroke.Color = C.Gold
				stroke.Transparency = 0.2
			end
			Icons.Make(slot, "Weapon", w.Key, 40, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
		end
	end

	-- the most important news first, at most 4 items (the rest as "+N more")
	local lines = {}
	if r.BrainLevelAfter > r.BrainLevelBefore then
		table.insert(lines, "Brain Level " .. r.BrainLevelAfter .. "!")
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
		table.insert(lines, string.format("Coin bonus x%.1f", r.Multiplier))
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
	self.C.SoundController:Play(if victory then "Victory" else "RunOver")
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
