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

local ResultsController = {}

local C = Theme.Colors

function ResultsController:Init(controllers)
	self.C = controllers
	local gui, root = Kit.ScreenGui("BrainrotResults", 35, Players.LocalPlayer:WaitForChild("PlayerGui"))
	self.Gui = gui
	self.Root = root

	-- death prompt
	local death = Kit.New("Frame", {
		Name = "Death",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(40, 0, 10),
		BackgroundTransparency = 0.35,
		Visible = false,
		Parent = root,
	})
	Kit.Label({
		Text = "YOU DIED",
		Size = UDim2.fromOffset(700, 110),
		Position = UDim2.new(0.5, 0, 0.26, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = Theme.Fonts.Title,
		TextColor3 = C.Red,
		StrokeThickness = 5,
		Parent = death,
	})
	self.DeathTimer = Widgets.Bar(death, UDim2.fromOffset(360, 22), UDim2.new(0.5, -180, 0.36, 0), C.Red)
	local _, reviveLabel = Kit.Button({
		Name = "Revive",
		Text = "💖 REVIVE",
		Size = UDim2.fromOffset(300, 70),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = C.Pink,
		OnClick = function()
			self.C.ClientData:Fire("Revive")
		end,
		Parent = death,
	})
	self.ReviveLabel = reviveLabel
	self.ReviveButton = reviveLabel.Parent :: GuiObject
	Kit.Button({
		Name = "GiveUp",
		Text = "GIVE UP",
		Size = UDim2.fromOffset(220, 54),
		Position = UDim2.new(0.5, 0, 0.5, 70),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = C.Gray,
		OnClick = function()
			self.C.ClientData:Fire("GiveUp")
		end,
		Parent = death,
	})
	self.Death = death

	-- results
	local panel = Kit.Panel({
		Name = "Results",
		Size = UDim2.fromOffset(760, 560),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Radius = 22,
		Parent = root,
	})
	self.PanelGradient = Kit.Gradient(panel, C.PanelLight, C.PanelDark)
	self.ResultTitle = Kit.Label({
		Text = "RUN OVER",
		Size = UDim2.new(1, -40, 0, 80),
		Position = UDim2.fromOffset(20, 10),
		Font = Theme.Fonts.Title,
		StrokeThickness = 5,
		Parent = panel,
	})
	self.ResultSub = Kit.Label({
		Text = "",
		Size = UDim2.new(1, -40, 0, 26),
		Position = UDim2.fromOffset(20, 86),
		TextColor3 = C.TextDim,
		Parent = panel,
	})
	local grid = Kit.New("Frame", {
		Name = "Stats",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -40, 0, 170),
		Position = UDim2.fromOffset(20, 122),
		Parent = panel,
	})
	Kit.New("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, 50),
		CellPadding = UDim2.fromOffset(12, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	self.StatLabels = {}
	for i, key in { "Time", "Kills", "Level", "Coins", "BestTime", "BestLevel" } do
		local cell = Kit.Panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Panel, Radius = 12, LayoutOrder = i, Parent = grid })
		self.StatLabels[key] = Kit.Label({ Text = "", Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), TextXAlignment = Enum.TextXAlignment.Left, Parent = cell })
	end
	self.Build = Kit.New("Frame", {
		Name = "Build",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -40, 0, 50),
		Position = UDim2.fromOffset(20, 300),
		Parent = panel,
	})
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = self.Build,
	})
	self.Extra = Kit.Label({
		Text = "",
		Size = UDim2.new(1, -40, 0, 90),
		Position = UDim2.fromOffset(20, 356),
		TextWrapped = true,
		Font = Theme.Fonts.Bold,
		TextColor3 = C.Gold,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = panel,
	})
	Kit.Button({
		Name = "PlayAgain",
		Text = "▶ PLAY AGAIN",
		Size = UDim2.fromOffset(330, 70),
		Position = UDim2.new(0.5, -175, 1, -20),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = C.Lime,
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
		Text = "🏠 LOBBY",
		Size = UDim2.fromOffset(250, 70),
		Position = UDim2.new(0.5, 185, 1, -20),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = C.Blue,
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
	self.ReviveLabel.Text = string.format("💖 REVIVE  (R$ %d)", product.Price)
	self.C.SoundController:Play("Death")
	self.C.CameraController:ZoomPunch(0.6, 1)
	local window = p.Window or 10
	local started = os.clock()
	self.DeathToken = (self.DeathToken or 0) + 1
	local token = self.DeathToken
	task.spawn(function()
		while self.Death.Visible and self.DeathToken == token do
			local left = window - (os.clock() - started)
			self.DeathTimer:Set(left / window, string.format("%ds", math.max(0, math.ceil(left))))
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
	self.ResultTitle.TextColor3 = if victory then C.Gold else C.Red
	self.ResultSub.Text = if victory then "You survived the brainrot. Legend." else "The horde got you. One more run?"
	self.PanelGradient.Color = ColorSequence.new(if victory then C.GoldDark:Lerp(C.Panel, 0.5) else C.PanelLight, C.PanelDark)
	local L = self.StatLabels
	L.Time.Text = "⏱ Time survived: " .. Format.Time(s.Time)
	L.Kills.Text = "💀 Enemies: " .. Format.Commas(s.Kills)
	L.Level.Text = "⭐ Level: " .. s.Level
	L.Coins.Text = string.format("🪙 Coins: +%s", Format.Commas(r.Coins))
	L.BestTime.Text = "🏆 Best time: " .. Format.Time(r.BestTime) .. (if r.Best.Time then "  NEW!" else "")
	L.BestLevel.Text = "🏆 Best level: " .. r.BestLevel .. (if r.Best.Level then "  NEW!" else "")
	L.BestTime.TextColor3 = if r.Best.Time then C.Gold else C.Text
	L.BestLevel.TextColor3 = if r.Best.Level then C.Gold else C.Text

	Widgets.Clear(self.Build)
	for i, w in s.Build.Weapons do
		local def = WeaponData.ByKey[w.Key]
		if def then
			local frame, icon, level = Widgets.Slot(self.Build, 48, i)
			icon.Text = def.Icon
			level.Text = if w.Awakened then "★" else "Lv" .. w.Level
			if w.Awakened then
				frame.BackgroundColor3 = C.GoldDark
			end
		end
	end

	local lines = {}
	if r.FirstToday then
		table.insert(lines, "First run of the day bonus!")
	end
	if r.Multiplier and r.Multiplier > 1 then
		table.insert(lines, string.format("Coin bonus x%.1f", r.Multiplier))
	end
	if r.BrainLevelAfter > r.BrainLevelBefore then
		table.insert(lines, "🧠 BRAIN LEVEL UP! -> " .. r.BrainLevelAfter)
	end
	for _, key in r.Achievements do
		local def = AchievementData.ByKey[key]
		if def then
			table.insert(lines, "🏆 " .. def.Name)
		end
	end
	for _, name in r.Unlocks do
		table.insert(lines, "🔓 " .. name)
	end
	self.Extra.Text = table.concat(lines, "   ")

	self.Panel.Visible = true
	Kit.Pop(self.Panel, 0.2)
	self.C.SoundController:Play(if victory then "Victory" else "RunOver")
end

function ResultsController:Hide()
	self.Panel.Visible = false
	self:HideDeath()
end

function ResultsController:IsOpen(): boolean
	return self.Panel.Visible
end

function ResultsController:Start() end

return ResultsController
