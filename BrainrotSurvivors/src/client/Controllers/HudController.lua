--[[
	HudController - the in-run HUD. Minimal: the arena is the show.

	  top centre   level chip + thin XP bar, timer under it
	  top left     HP
	  top right    coins (small) + pause
	  right        boss HP - only while a boss is alive
	  bottom       small weapon icons (level pips) + active buffs above them
	  pause menu   RESUME / SETTINGS / GIVE UP + your current build

	Values are read from RunClient once per frame and only written when they change.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local WeaponData = require(Shared.WeaponData)
local UpgradeData = require(Shared.UpgradeData)
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)
local Icons = require(script.Parent.Parent.UI.Icons)

local HudController = {}

local C = Theme.Colors
local F = Theme.Fonts
local M = Theme.Margin
local BUFF_NAMES = { Sigma = "SIGMA MODE", Storm = "STORM", XP67 = "+67% XP", Damage67 = "+67% DMG" }
local SLOT = 42

function HudController:Init(controllers)
	self.C = controllers
	local gui, root = Kit.ScreenGui("BrainrotHUD", 10, Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	self.Gui = gui
	self.Root = root
	self.Buffs = {}
	self.Last = {}

	local safe = Kit.New("Frame", { Name = "Safe", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
	Kit.Padding(safe, M - 8, M - 14)
	self.Safe = safe

	-- top centre: LV chip + XP bar, timer below
	local top = Kit.New("Frame", {
		Name = "Top",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(460, 64),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = safe,
	})
	local badge = Kit.Label({
		Name = "Level",
		Text = "LV 1",
		Size = UDim2.fromOffset(62, 24),
		Font = F.Title,
		MaxTextSize = 15,
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Accent,
		Parent = top,
	})
	Kit.Corner(badge, 12)
	self.LevelLabel = badge
	self.Badge = badge
	self.XPBar = Widgets.Bar(top, UDim2.new(1, -72, 0, 10), UDim2.new(0, 72, 0, 7), C.XP)
	self.XPBar.Label.Visible = false
	self.Timer = Kit.Label({
		Name = "Timer",
		Text = "0:00",
		Size = UDim2.fromOffset(160, 34),
		Position = UDim2.new(0.5, 0, 0, 28),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = F.Title,
		MaxTextSize = 30,
		StrokeThickness = 1.5,
		StrokeTransparency = 0.5,
		Parent = top,
	})

	-- top left: HP
	local hp = Kit.New("Frame", { Name = "HP", BackgroundTransparency = 1, Size = UDim2.fromOffset(240, 40), Parent = safe })
	local hpTag = Kit.Label({
		Text = "HP",
		Size = UDim2.fromOffset(28, 22),
		Font = F.Title,
		MaxTextSize = 13,
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Danger,
		Parent = hp,
	})
	Kit.Corner(hpTag, 11)
	self.HPBar = Widgets.Bar(hp, UDim2.new(1, -32, 0, 22), UDim2.fromOffset(32, 0), C.HP)
	self.HPBar.Label.TextXAlignment = Enum.TextXAlignment.Right
	self.HPOrigin = self.HPBar.Frame.Position

	-- top right: coins + pause
	local right = Kit.New("Frame", {
		Name = "TopRight",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 38),
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
		Parent = right,
	})
	local coins = Kit.Panel({ Name = "Coins", Size = UDim2.fromOffset(104, 32), LayoutOrder = 1, Radius = 16, Parent = right })
	Widgets.Coin(coins, 18, { Position = UDim2.new(0, 9, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	self.CoinsLabel = Kit.Label({
		Name = "Amount",
		Text = "0",
		Size = UDim2.new(1, -42, 0, 18),
		Position = UDim2.new(0, 34, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = F.Bold,
		MaxTextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = coins,
	})
	self.CoinsPill = coins
	local pause = Kit.New("TextButton", {
		Name = "Pause",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(38, 38),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.Glass,
		LayoutOrder = 2,
		Parent = right,
	})
	Kit.Corner(pause, 19)
	Kit.Stroke(pause)
	Kit.Interactive(pause)
	Widgets.Pause(pause, 16, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	pause.Activated:Connect(function()
		if Kit.ClickSound then
			Kit.ClickSound()
		end
		self:TogglePause()
	end)

	-- right: boss HP (only while a boss is alive)
	local boss = Kit.Panel({
		Name = "Boss",
		Size = UDim2.fromOffset(270, 62),
		Position = UDim2.new(1, 0, 0, 56),
		AnchorPoint = Vector2.new(1, 0),
		Visible = false,
		Radius = 14,
		Parent = safe,
	})
	local bossStroke = boss:FindFirstChildOfClass("UIStroke") :: UIStroke
	bossStroke.Color = C.Danger
	bossStroke.Transparency = 0.45
	Kit.Label({
		Text = "BOSS",
		Size = UDim2.fromOffset(40, 14),
		Position = UDim2.fromOffset(14, 10),
		Font = F.Title,
		MaxTextSize = 12,
		TextColor3 = C.Danger,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = boss,
	})
	self.BossName = Kit.Label({
		Name = "BossName",
		Text = "",
		Size = UDim2.new(1, -142, 0, 16),
		Position = UDim2.fromOffset(54, 9),
		Font = F.Bold,
		MaxTextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = boss,
	})
	self.BossHP = Kit.Label({
		Name = "BossHP",
		Text = "",
		Size = UDim2.fromOffset(70, 16),
		Position = UDim2.new(1, -14, 0, 9),
		AnchorPoint = Vector2.new(1, 0),
		Font = F.Bold,
		MaxTextSize = 13,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = boss,
	})
	self.BossBar = Widgets.Bar(boss, UDim2.new(1, -28, 0, 12), UDim2.fromOffset(14, 36), C.Danger)
	self.BossBar.Label.Visible = false
	self.BossPanel = boss

	-- bottom: weapons, buffs above
	local bottom = Kit.New("Frame", {
		Name = "Loadout",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(10 * (SLOT + 6), SLOT + 40),
		Position = UDim2.fromScale(0.5, 1),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = safe,
	})
	self.Bottom = bottom
	local function row(name: string, height: number, y: number): Frame
		local f = Kit.New("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, height),
			Position = UDim2.new(0, 0, 1, y),
			AnchorPoint = Vector2.new(0, 1),
			Parent = bottom,
		})
		Kit.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = f,
		})
		return f
	end
	self.WeaponRow = row("Weapons", SLOT, 0)
	self.BuffRow = row("Buffs", 26, -(SLOT + 10))

	self:BuildPauseMenu(root)
end

function HudController:BuildPauseMenu(root: Frame)
	local backdrop = Kit.New("Frame", {
		Name = "PauseMenu",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Overlay,
		BackgroundTransparency = 0.4,
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	local panel = Kit.Panel({
		Name = "Panel",
		Size = UDim2.fromOffset(380, 400),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = Theme.GlassStrong,
		Radius = 20,
		Parent = backdrop,
	})
	Kit.Label({
		Text = "PAUSED",
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 22),
		Font = F.Title,
		MaxTextSize = 30,
		Parent = panel,
	})
	-- your build: every weapon + passive, small
	Widgets.Caption(panel, "YOUR BUILD", UDim2.fromOffset(30, 72))
	local build = Kit.New("Frame", { Name = "Build", BackgroundTransparency = 1, Size = UDim2.new(1, -60, 0, 72), Position = UDim2.fromOffset(30, 94), Parent = panel })
	Kit.New("UIGridLayout", { CellSize = UDim2.fromOffset(32, 32), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = build })
	self.BuildGrid = build
	local y = 184
	for i, entry in { { "RESUME", C.Accent }, { "SETTINGS", C.Neutral }, { "GIVE UP", C.Neutral } } do
		local button, label = Kit.Button({
			Name = string.gsub(entry[1], " ", ""),
			Text = entry[1],
			Size = UDim2.new(1, -60, 0, if i == 1 then 54 else 46),
			Position = UDim2.fromOffset(30, y),
			Color = entry[2],
			TextSize = if i == 1 then 20 else 17,
			OnClick = function()
				if i == 1 then
					self:TogglePause()
				elseif i == 2 then
					self.C.LobbyController:OpenPanel("Settings", true)
				else
					self:TogglePause(false)
					self.C.ClientData:Fire("GiveUp")
				end
			end,
			Parent = panel,
		})
		if i == 3 then
			label.TextColor3 = C.Danger
			button.Size = UDim2.new(1, -60, 0, 46)
		end
		y += (if i == 1 then 54 else 46) + 12
	end
	self.PauseMenu = backdrop
	self.PausePanel = panel
end

function HudController:Show()
	self.Gui.Enabled = true
	self:SetCovered(false)
	self.PauseMenu.Visible = false
	for key in self.Buffs do
		self:SetBuff(key, 0)
	end
	local touch = Kit.IsTouch()
	-- keep the bottom-left corner free for the thumbstick on phones
	self.Bottom.AnchorPoint = if touch then Vector2.new(1, 1) else Vector2.new(0.5, 1)
	self.Bottom.Position = if touch then UDim2.fromScale(1, 1) else UDim2.fromScale(0.5, 1)
	for _, row in { self.WeaponRow, self.BuffRow } do
		(row:FindFirstChildOfClass("UIListLayout") :: UIListLayout).HorizontalAlignment = if touch then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Center
	end
end

function HudController:Hide()
	self.Gui.Enabled = false
	self:SetCovered(false)
	self:HideBoss()
end

-- level-up and results screens take the whole screen: the HUD steps aside
function HudController:SetCovered(covered: boolean)
	self.Safe.Visible = not covered
end

function HudController:TogglePause(force: boolean?)
	local show = if force ~= nil then force else not self.PauseMenu.Visible
	self.PauseMenu.Visible = show
	if show then
		Kit.Appear(self.PausePanel)
	end
	Kit.Blur("pause", if show then 8 else 0)
	self.C.ClientData:Fire("Pause", show)
end

function HudController:TogglePauseMenuOff()
	if self.PauseMenu.Visible then
		self:TogglePause(false)
	end
end

-- one weapon slot: small 3D icon, level in the corner, gold border when awakened / max
local function weaponSlot(parent: Instance, order: number, key: string?, level: number, maxLevel: number, awakened: boolean): Frame
	local frame = Kit.Panel({
		Name = key or "Empty",
		Size = UDim2.fromOffset(SLOT, SLOT),
		LayoutOrder = order,
		Radius = 10,
		BackgroundTransparency = if key then Theme.Glass else 0.7,
		Parent = parent,
	})
	if not key then
		return frame
	end
	local top = awakened or level >= maxLevel
	if top then
		local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = C.Gold
		stroke.Transparency = 0.2
	end
	Icons.Make(frame, "Weapon", key, SLOT - 4, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	Kit.Label({
		Name = "Level",
		Text = if awakened then "A" elseif level >= maxLevel then "MAX" else tostring(level),
		Size = UDim2.fromOffset(if top then 26 else 14, 13),
		Position = UDim2.new(1, -3, 1, -2),
		AnchorPoint = Vector2.new(1, 1),
		Font = F.Title,
		MaxTextSize = 11,
		TextColor3 = if top then C.Gold else C.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
		StrokeThickness = 1,
		StrokeTransparency = 0.3,
		ZIndex = 3,
		Parent = frame,
	})
	return frame
end

function HudController:SetLoadout(loadout)
	Widgets.Clear(self.WeaponRow)
	for i, w in loadout.Weapons do
		local def = WeaponData.ByKey[w.Key]
		if def then
			weaponSlot(self.WeaponRow, i, w.Key, w.Level, def.MaxLevel, w.Awakened == true)
		end
	end
	for i = #loadout.Weapons + 1, loadout.Slots do
		weaponSlot(self.WeaponRow, i, nil, 0, 1, false)
	end
	-- the full build (weapons + passives + rares) is shown in the pause menu only
	Widgets.Clear(self.BuildGrid)
	local order = 0
	for _, w in loadout.Weapons do
		order += 1
		Icons.Make(self.BuildGrid, "Weapon", w.Key, 32, { LayoutOrder = order })
	end
	for _, p in loadout.Passives do
		if UpgradeData.PassiveByKey[p.Key] then
			order += 1
			Icons.Make(self.BuildGrid, "Stat", p.Key, 32, { LayoutOrder = order })
		end
	end
	for _, r in loadout.Rares do
		if UpgradeData.RareByKey[r.Key] and r.Key ~= "Awaken" then
			order += 1
			Icons.Make(self.BuildGrid, "Rare", r.Key, 32, { LayoutOrder = order })
		end
	end
	Kit.Pop(self.WeaponRow, 0.05)
end

function HudController:SetBuff(key: string, duration: number)
	local existing = self.Buffs[key]
	if duration <= 0 then
		if existing then
			existing.Frame:Destroy()
			self.Buffs[key] = nil
		end
		return
	end
	if not existing then
		local frame = Kit.Panel({ Name = key, Size = UDim2.fromOffset(128, 26), Radius = 13, Parent = self.BuffRow })
		local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = C.Accent
		stroke.Transparency = 0.4
		local label = Kit.Label({
			Text = "",
			Size = UDim2.new(1, -16, 1, -8),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Font = F.Bold,
			MaxTextSize = 13,
			Parent = frame,
		})
		existing = { Frame = frame, Label = label }
		self.Buffs[key] = existing
		Kit.Pop(frame, 0.15)
	end
	existing.Until = os.clock() + duration
	existing.Name = BUFF_NAMES[key] or string.upper(key)
end

function HudController:ShowBoss(boss)
	self.BossName.Text = boss.Title
	self.BossPanel.Visible = true
	self.BossBar:Set(1)
	Kit.Appear(self.BossPanel)
end

function HudController:HideBoss()
	self.BossPanel.Visible = false
end

function HudController:CoinPop(_n: number)
	Kit.Pop(self.CoinsPill, 0.08)
end

function HudController:HurtShake()
	local bar = self.HPBar.Frame
	local origin = self.HPOrigin
	bar.Position = origin + UDim2.fromOffset(math.random(-3, 3), math.random(-2, 2))
	task.delay(0.08, function()
		bar.Position = origin
	end)
end

function HudController:Update()
	if not self.Gui.Enabled then
		return
	end
	local run = self.C.RunClient
	local last = self.Last
	if last.Level ~= run.Level then
		last.Level = run.Level
		self.LevelLabel.Text = "LV " .. run.Level
		Kit.Pop(self.Badge, 0.15)
	end
	self.XPBar:Set(run.XPFrac)
	local hpText = string.format("%d / %d", math.max(0, math.ceil(run.HP)), run.MaxHP)
	if last.HP ~= hpText then
		last.HP = hpText
		self.HPBar:Set(run.HP / math.max(1, run.MaxHP), hpText)
	end
	local timeText = Format.Time(run:Now())
	if last.Time ~= timeText then
		last.Time = timeText
		self.Timer.Text = timeText
	end
	if last.Coins ~= run.Coins then
		last.Coins = run.Coins
		self.CoinsLabel.Text = Format.Commas(run.Coins)
	end
	local boss = run.Boss
	if boss and self.BossPanel.Visible then
		self.BossBar:Set(boss.HP / math.max(1, boss.MaxHP))
		self.BossHP.Text = Format.Number(math.max(0, boss.HP))
	end
	local now = os.clock()
	for key, b in self.Buffs do
		local left = b.Until - now
		if left <= 0 then
			self:SetBuff(key, 0)
		else
			b.Label.Text = string.format("%s  %ds", b.Name, math.ceil(left))
		end
	end
end

function HudController:Start()
	RunService.RenderStepped:Connect(function()
		self:Update()
	end)
end

return HudController
