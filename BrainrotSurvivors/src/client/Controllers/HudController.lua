--[[
	HudController - the in-run HUD.

	  top:     XP bar (full width) + level badge, HP bar, timer, kills, coins, pause
	  bottom:  weapons (icon + level pips), passives, active buffs
	  right:   boss HP panel
	  pause:   menu with RESUME / SETTINGS / GIVE UP

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

local HudController = {}

local C = Theme.Colors
local BUFF_ICONS = { Sigma = "🗿", Storm = "🌩️", XP67 = "📈", Damage67 = "💥" }
local BUFF_NAMES = { Sigma = "SIGMA", Storm = "STORM", XP67 = "+67% XP", Damage67 = "+67% DMG" }

function HudController:Init(controllers)
	self.C = controllers
	local gui, root = Kit.ScreenGui("BrainrotHUD", 10, Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	self.Gui = gui
	self.Root = root
	self.Buffs = {}
	self.Last = {}

	-- XP bar + level badge
	self.XPBar = Widgets.Bar(root, UDim2.new(1, -110, 0, 20), UDim2.fromOffset(92, 10), C.XP)
	local badge = Kit.Panel({
		Size = UDim2.fromOffset(74, 50),
		Position = UDim2.fromOffset(12, 4),
		BackgroundColor3 = C.Blue,
		Radius = 14,
		ZIndex = 4,
		Parent = root,
	})
	Kit.Gradient(badge, C.Blue, C.BlueDark)
	self.LevelLabel = Kit.Label({ Text = "LV 1", Size = UDim2.fromScale(1, 1), Font = Theme.Fonts.Title, ZIndex = 5, Parent = badge })
	self.Badge = badge

	-- HP
	self.HPBar = Widgets.Bar(root, UDim2.fromOffset(280, 28), UDim2.fromOffset(92, 38), C.HP)
	self.HPOrigin = self.HPBar.Frame.Position

	-- timer
	self.Timer = Kit.Label({
		Text = "0:00",
		Size = UDim2.fromOffset(200, 50),
		Position = UDim2.new(0.5, 0, 0, 34),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.Fonts.Title,
		StrokeThickness = 3,
		Parent = root,
	})

	-- kills + coins
	self.Kills = Kit.Label({
		Text = "💀 0",
		Size = UDim2.fromOffset(170, 30),
		Position = UDim2.new(1, -150, 0, 38),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	})
	self.CoinsLabel = Kit.Label({
		Text = "🪙 0",
		Size = UDim2.fromOffset(120, 30),
		Position = UDim2.new(1, -20, 0, 38),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Coin,
		Parent = root,
	})

	-- pause
	Kit.Button({
		Name = "Pause",
		Text = "II",
		Size = UDim2.fromOffset(48, 44),
		Position = UDim2.new(1, -12, 0, 76),
		AnchorPoint = Vector2.new(1, 0),
		Color = C.PanelLight,
		OnClick = function()
			self:TogglePause()
		end,
		Parent = root,
	})

	-- bottom: weapons + passives + buffs
	local bottom = Kit.New("Frame", {
		Name = "Loadout",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(560, 110),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
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
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = f,
		})
		return f
	end
	self.WeaponRow = row("Weapons", 52, 0)
	self.PassiveRow = row("Passives", 32, -58)
	self.BuffRow = row("Buffs", 30, -94)

	-- boss panel (right side)
	local boss = Kit.Panel({
		Name = "Boss",
		Size = UDim2.fromOffset(290, 84),
		Position = UDim2.new(1, -12, 0.42, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = root,
	})
	Kit.Gradient(boss, C.RedDark, C.PanelDark)
	self.BossName = Kit.Label({
		Text = "BOSS",
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(8, 6),
		Font = Theme.Fonts.Title,
		TextColor3 = C.Gold,
		Parent = boss,
	})
	self.BossBar = Widgets.Bar(boss, UDim2.new(1, -20, 0, 28), UDim2.fromOffset(10, 44), C.Red)
	self.BossPanel = boss

	-- pause menu
	local pause = Kit.Panel({
		Name = "PauseMenu",
		Size = UDim2.fromOffset(360, 300),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	Kit.Gradient(pause, C.PanelLight, C.PanelDark)
	Kit.Label({ Text = "PAUSED", Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 12), Font = Theme.Fonts.Title, Parent = pause })
	Kit.Button({
		Text = "▶ RESUME",
		Size = UDim2.fromOffset(280, 56),
		Position = UDim2.new(0.5, 0, 0, 82),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = C.Lime,
		OnClick = function()
			self:TogglePause()
		end,
		Parent = pause,
	})
	Kit.Button({
		Text = "⚙ SETTINGS",
		Size = UDim2.fromOffset(280, 50),
		Position = UDim2.new(0.5, 0, 0, 150),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = C.Blue,
		OnClick = function()
			self.C.LobbyController:OpenPanel("Settings", true)
		end,
		Parent = pause,
	})
	Kit.Button({
		Text = "🏳 GIVE UP",
		Size = UDim2.fromOffset(280, 50),
		Position = UDim2.new(0.5, 0, 0, 212),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = C.Red,
		OnClick = function()
			self:TogglePause(false)
			self.C.ClientData:Fire("GiveUp")
		end,
		Parent = pause,
	})
	self.PauseMenu = pause
end

function HudController:Show()
	self.Gui.Enabled = true
	self.PauseMenu.Visible = false
	for key in self.Buffs do
		self:SetBuff(key, 0)
	end
	local touch = Kit.IsTouch()
	-- keep the bottom-left corner free for the thumbstick on phones
	self.Bottom.AnchorPoint = if touch then Vector2.new(1, 1) else Vector2.new(0.5, 1)
	self.Bottom.Position = if touch then UDim2.new(1, -8, 1, -8) else UDim2.new(0.5, 0, 1, -8)
end

function HudController:Hide()
	self.Gui.Enabled = false
	self:HideBoss()
end

function HudController:TogglePause(force: boolean?)
	local show = if force ~= nil then force else not self.PauseMenu.Visible
	self.PauseMenu.Visible = show
	self.C.ClientData:Fire("Pause", show)
end

function HudController:TogglePauseMenuOff()
	if self.PauseMenu.Visible then
		self:TogglePause(false)
	end
end

function HudController:SetLoadout(loadout)
	Widgets.Clear(self.WeaponRow)
	for i, w in loadout.Weapons do
		local def = WeaponData.ByKey[w.Key]
		if def then
			local frame, icon, level = Widgets.Slot(self.WeaponRow, 52, i)
			icon.Text = def.Icon
			level.Text = if w.Awakened then "★" elseif w.Level >= def.MaxLevel then "MAX" else "Lv" .. w.Level
			level.TextColor3 = if w.Awakened or w.Level >= def.MaxLevel then C.Gold else C.Text
			frame.BackgroundColor3 = if w.Awakened then C.GoldDark else C.PanelLight
		end
	end
	for i = #loadout.Weapons + 1, loadout.Slots do
		local frame = Widgets.Slot(self.WeaponRow, 52, i)
		frame.BackgroundTransparency = 0.6
	end
	Widgets.Clear(self.PassiveRow)
	for i, p in loadout.Passives do
		local def = UpgradeData.PassiveByKey[p.Key]
		if def then
			local _, icon, level = Widgets.Slot(self.PassiveRow, 32, i)
			icon.Text = def.Icon
			level.Text = tostring(p.Stacks)
		end
	end
	for i, r in loadout.Rares do
		local def = UpgradeData.RareByKey[r.Key]
		if def and r.Key ~= "Awaken" then
			local frame, icon, level = Widgets.Slot(self.PassiveRow, 32, 100 + i)
			frame.BackgroundColor3 = C.PurpleDark
			icon.Text = def.Icon
			level.Text = if r.Stacks > 1 then tostring(r.Stacks) else ""
		end
	end
	Kit.Pop(self.WeaponRow, 0.06)
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
		local frame = Kit.Panel({
			Size = UDim2.fromOffset(120, 30),
			BackgroundColor3 = C.Purple,
			Radius = 10,
			Parent = self.BuffRow,
		})
		local label = Kit.Label({ Text = "", Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), Parent = frame })
		existing = { Frame = frame, Label = label }
		self.Buffs[key] = existing
		Kit.Pop(frame, 0.3)
	end
	existing.Until = os.clock() + duration
	existing.Name = (BUFF_ICONS[key] or "✨") .. " " .. (BUFF_NAMES[key] or key)
end

function HudController:ShowBoss(boss)
	self.BossName.Text = boss.Title
	self.BossPanel.Visible = true
	self.BossBar:Set(1, "")
	Kit.Pop(self.BossPanel, 0.2)
end

function HudController:HideBoss()
	self.BossPanel.Visible = false
end

function HudController:CoinPop(_n: number)
	Kit.Pop(self.CoinsLabel, 0.25)
end

function HudController:HurtShake()
	local bar = self.HPBar.Frame
	local origin = self.HPOrigin
	bar.Position = origin + UDim2.fromOffset(math.random(-6, 6), math.random(-3, 3))
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
		Kit.Pop(self.Badge, 0.3)
	end
	self.XPBar:Set(run.XPFrac)
	local hpText = string.format("❤ %d / %d", math.max(0, math.ceil(run.HP)), run.MaxHP)
	if last.HP ~= hpText then
		last.HP = hpText
		self.HPBar:Set(run.HP / math.max(1, run.MaxHP), hpText)
	end
	local timeText = Format.Time(run:Now())
	if last.Time ~= timeText then
		last.Time = timeText
		self.Timer.Text = timeText
	end
	if last.Kills ~= run.Kills then
		last.Kills = run.Kills
		self.Kills.Text = "💀 " .. Format.Commas(run.Kills)
	end
	if last.Coins ~= run.Coins then
		last.Coins = run.Coins
		self.CoinsLabel.Text = "🪙 " .. Format.Commas(run.Coins)
	end
	local boss = run.Boss
	if boss and self.BossPanel.Visible then
		self.BossBar:Set(boss.HP / math.max(1, boss.MaxHP), Format.Number(boss.HP))
	end
	local now = os.clock()
	for key, b in self.Buffs do
		local left = b.Until - now
		if left <= 0 then
			self:SetBuff(key, 0)
		else
			b.Label.Text = string.format("%s %ds", b.Name, math.ceil(left))
		end
	end
end

function HudController:Start()
	RunService.RenderStepped:Connect(function()
		self:Update()
	end)
end

return HudController
