--[[
	HudController - the in-run HUD. Minimal: the arena is the show.

	  top centre   level chip + thin XP bar, timer under it, the ZONE you are in under that
	               (danger stars, what it pays), the BOSS TIMELINE under that ("BOSS 2 IN 0:42",
	               "BOSS 2 OUT: CARTZILLA · HORDE MART LOT")
	  top left     HP (+ the Plating shield), the run's difficulty, your ITEMS with their level
	               (I, II, III), your SYNERGIES and SOULS under them
	  top right    coins (small) + pause; the minimap under them (MinimapController)
	  right        THE FINAL ONE's HP under the minimap - only while it is out (bosses 1-4 have
	               their bars over their heads)
	  centre       "ITEM ACQUIRED" / "ITEM LEVEL UP  I -> II" card with the new mechanic
	  bottom right DASH (only with the Rocket Skates item): charges, recharge, tap to dash
	  bottom       small ability icons (level, MAX, EVO) + active buffs above them
	               + "EVOLUTION AVAILABLE" when an evolution can be picked
	  pause menu   RESUME / SETTINGS / GIVE UP + your current build

	Values are read from RunClient once per frame and only written when they change.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local WeaponData = require(Shared.WeaponData)
local UpgradeData = require(Shared.UpgradeData)
local DifficultyData = require(Shared.DifficultyData)
local ArenaData = require(Shared.ArenaData)
local ItemData = require(Shared.ItemData)
local BossData = require(Shared.BossData)
local SynergyData = require(Shared.SynergyData)
local GameConfig = require(Shared.GameConfig)
local Rarity = require(Shared.Rarity)
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)
local Icons = require(script.Parent.Parent.UI.Icons)

local HudController = {}

local C = Theme.Colors
local F = Theme.Fonts
local M = Theme.Margin
local BUFF_NAMES = {
	P67 = "67%",
	Luck67 = "67 LUCK",
	TurboMode = "TURBO",
	GlassMode = "GLASS",
	GiantMode = "GIANT",
	TinyMode = "TINY",
	XPStorm = "XP STORM",
}
local SLOT = 42
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII" }

function HudController:Init(controllers)
	self.C = controllers
	local gui, root = Kit.ScreenGui("S67HUD", 10, Players.LocalPlayer:WaitForChild("PlayerGui"))
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
	-- PLATING (an upgrade): a shield bar under the HP bar, only when you have it
	self.PlatingBar = Widgets.Bar(hp, UDim2.new(1, -32, 0, 5), UDim2.fromOffset(32, 24), Color3.fromRGB(140, 220, 255))
	self.PlatingBar.Label.Visible = false
	self.PlatingBar.Frame.Visible = false

	-- under the HP: the difficulty of this run (tier numeral + name in the tier's colour)
	local diff = Kit.New("Frame", {
		Name = "Difficulty",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		Position = UDim2.fromOffset(0, 30),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.Glass,
		Parent = safe,
	})
	Kit.Corner(diff, 11)
	self.DiffStroke = Kit.Stroke(diff, 1.5, C.TextDim, 0.35)
	Kit.Padding(diff, 10, 0)
	self.DiffLabel = Kit.New("TextLabel", {
		Name = "Text",
		Text = "",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		BackgroundTransparency = 1,
		Font = F.Bold,
		TextSize = 12,
		TextColor3 = C.TextDim,
		Parent = diff,
	})
	self.DiffChip = diff

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

	-- EVOLUTION AVAILABLE: a small glowing pill above the abilities
	local evo = Kit.Panel({
		Name = "EvolutionReady",
		Size = UDim2.fromOffset(230, 28),
		Position = UDim2.new(0.5, 0, 1, -(SLOT + 44)),
		AnchorPoint = Vector2.new(0.5, 1),
		Radius = 14,
		Visible = false,
		Parent = bottom,
	})
	local evoStroke = evo:FindFirstChildOfClass("UIStroke") :: UIStroke
	evoStroke.Color = C.Mythic
	evoStroke.Transparency = 0.1
	evoStroke.Thickness = 2
	self.EvoLabel = Kit.Label({
		Name = "Text",
		Text = "EVOLUTION AVAILABLE",
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = F.Title,
		MaxTextSize = 14,
		TextColor3 = C.Mythic,
		Parent = evo,
	})
	self.EvoPill = evo

	-- +1 FRAGMENT pop under the coins
	self.FragmentToast = Kit.Label({
		Name = "FragmentToast",
		Text = "",
		Size = UDim2.fromOffset(160, 22),
		Position = UDim2.new(1, 0, 0, 44),
		AnchorPoint = Vector2.new(1, 0),
		Font = F.Title,
		MaxTextSize = 15,
		TextColor3 = C.Epic,
		TextXAlignment = Enum.TextXAlignment.Right,
		StrokeThickness = 1.5,
		StrokeTransparency = 0.4,
		Visible = false,
		Parent = safe,
	})

	self:BuildTown(safe)
	self:BuildPauseMenu(root)
end

---------------------------------------------------------------------------
-- 67 TOWN: zone chip, boss timeline, items, synergies, item card, dash
---------------------------------------------------------------------------
function HudController:BuildTown(safe: Frame)
	-- the zone you are in (under the timer)
	local zone = Kit.Panel({
		Name = "Zone",
		Size = UDim2.fromOffset(260, 24),
		Position = UDim2.new(0.5, 0, 0, 66),
		AnchorPoint = Vector2.new(0.5, 0),
		Radius = 12,
		Parent = safe,
	})
	self.ZoneStroke = zone:FindFirstChildOfClass("UIStroke") :: UIStroke
	self.ZoneName = Kit.Label({
		Name = "ZoneName",
		Text = "",
		Size = UDim2.new(0.62, -12, 0, 16),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = F.Title,
		MaxTextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = zone,
	})
	self.ZoneInfo = Kit.Label({
		Name = "ZoneInfo",
		Text = "",
		Size = UDim2.new(0.38, -12, 0, 16),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Font = F.Bold,
		MaxTextSize = 12,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = zone,
	})
	self.ZoneChip = zone

	-- the boss timeline (under the zone chip): the next boss, or the one that is out
	self.BossLine = Kit.Label({
		Name = "BossLine",
		Text = "",
		Size = UDim2.fromOffset(360, 18),
		Position = UDim2.new(0.5, 0, 0, 94),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = F.Bold,
		MaxTextSize = 13,
		TextColor3 = C.TextDim,
		StrokeThickness = 1.5,
		StrokeTransparency = 0.45,
		Parent = safe,
	})

	-- your items (under the difficulty chip), your synergies under them
	local items = Kit.New("Frame", {
		Name = "Items",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(330, 28),
		Position = UDim2.fromOffset(0, 58),
		Parent = safe,
	})
	Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = items })
	self.ItemRow = items
	local synergies = Kit.New("Frame", {
		Name = "Synergies",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(330, 18),
		Position = UDim2.fromOffset(0, 90),
		Parent = safe,
	})
	Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = synergies })
	self.SynergyRow = synergies
	-- a short word from the build ("PANIC BUTTON!", "7-7-7 JACKPOT!") under the synergies
	self.PerkLabel = Kit.Label({
		Name = "Perk",
		Text = "",
		Size = UDim2.fromOffset(260, 18),
		Position = UDim2.fromOffset(0, 112),
		Font = F.Title,
		MaxTextSize = 14,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		StrokeThickness = 1.5,
		StrokeTransparency = 0.35,
		Visible = false,
		Parent = safe,
	})

	-- ITEM ACQUIRED: the card of an item you just picked up (or levelled up)
	local card = Kit.Panel({
		Name = "ItemCard",
		Size = UDim2.fromOffset(380, 104),
		Position = UDim2.new(0.5, 0, 1, -(SLOT + 104)),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = Theme.GlassStrong,
		Radius = 16,
		Visible = false,
		Parent = safe,
	})
	self.ItemCardStroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	self.ItemCardIcon = Kit.New("Frame", { Name = "IconHolder", BackgroundTransparency = 1, Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(12, 14), Parent = card })
	self.ItemCardTag = Kit.Label({
		Name = "Tag",
		Text = "",
		Size = UDim2.new(1, -84, 0, 14),
		Position = UDim2.fromOffset(74, 8),
		Font = F.Bold,
		MaxTextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	self.ItemCardName = Kit.Label({
		Name = "ItemName",
		Text = "",
		Size = UDim2.new(1, -84, 0, 20),
		Position = UDim2.fromOffset(74, 22),
		Font = F.Title,
		MaxTextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	self.ItemCardDesc = Kit.Label({
		Name = "Desc",
		Text = "",
		Size = UDim2.new(1, -84, 0, 30),
		Position = UDim2.fromOffset(74, 44),
		Font = F.Medium,
		TextScaled = false,
		TextSize = 13,
		TextWrapped = true,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	self.ItemCardNew = Kit.Label({
		Name = "NewMechanic",
		Text = "",
		Size = UDim2.new(1, -24, 0, 18),
		Position = UDim2.new(0, 12, 1, -8),
		AnchorPoint = Vector2.new(0, 1),
		Font = F.Bold,
		MaxTextSize = 13,
		TextColor3 = C.Mythic,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = card,
	})
	self.ItemCard = card

	-- DASH (Rocket Skates): a round button with its charges and recharge
	local dash = Kit.New("TextButton", {
		Name = "Dash",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(62, 62),
		Position = UDim2.new(1, 0, 1, -(SLOT + 56)),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.Glass,
		Visible = false,
		Parent = safe,
	})
	Kit.Corner(dash, 31)
	self.DashStroke = Kit.Stroke(dash, 2, Color3.fromRGB(150, 230, 255), 0.1)
	self.DashFill = Kit.New("Frame", {
		Name = "Recharge",
		BackgroundColor3 = Color3.fromRGB(150, 230, 255),
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		Parent = dash,
	})
	Kit.Corner(self.DashFill, 31)
	self.DashLabel = Kit.Label({ Name = "Label", Text = "DASH", Size = UDim2.new(1, -10, 0, 18), Position = UDim2.fromScale(0.5, 0.36), AnchorPoint = Vector2.new(0.5, 0.5), Font = F.Title, MaxTextSize = 15, Parent = dash })
	self.DashDots = Kit.Label({ Name = "Charges", Text = "", Size = UDim2.new(1, -10, 0, 14), Position = UDim2.fromScale(0.5, 0.68), AnchorPoint = Vector2.new(0.5, 0.5), Font = F.Bold, MaxTextSize = 12, TextColor3 = Color3.fromRGB(150, 230, 255), Parent = dash })
	dash.Activated:Connect(function()
		self.C.RunClient:RequestDash()
	end)
	self.DashButton = dash
end

-- the zone chip: name + stars, what it pays, a boss in it
function HudController:UpdateZone(now: number)
	local run = self.C.RunClient
	local x, z = run:LocalXZ()
	if not x or not z then
		return
	end
	local zone = ArenaData.ZoneAt(x, z)
	local last = self.Last
	if last.Zone ~= zone.Key then
		last.Zone = zone.Key
		local stars = if zone.Stars > 0 then "  " .. string.rep("★", zone.Stars) else "  SAFE"
		self.ZoneName.Text = zone.Name .. stars
		self.ZoneName.TextColor3 = zone.Color
		self.ZoneStroke.Color = zone.Color
	end
	-- what the zone pays right now (the square pays less after a while; the 67 RUSH pays more)
	local xp = zone.XP
	if zone.Decay and run:Now() >= zone.Decay.After then
		xp = zone.Decay.XP
	end
	local rush = run.Map.Hot == zone.Key
	local here = nil
	for _, enc in run.Encounters do
		if enc.Zone == zone.Key and not enc.Main then
			here = enc
		end
	end
	local info
	if here then
		info = "⚠ BOSS " .. tostring(here.Slot or "") .. " HERE"
	elseif rush then
		info = "RUSH  XP x" .. tostring(math.floor(xp * GameConfig.Map.HotXP * 100 + 0.5) / 100)
	else
		info = "XP x" .. tostring(math.floor(xp * 100 + 0.5) / 100)
	end
	if last.ZoneInfo ~= info then
		last.ZoneInfo = info
		self.ZoneInfo.Text = info
		self.ZoneInfo.TextColor3 = if here then Color3.fromRGB(255, 130, 90) elseif rush then C.Gold else C.TextDim
	end
	self:UpdateBossLine(now)
end

-- the boss timeline: "BOSS 2 IN 0:42 · HORDE MART LOT ★★" / "BOSS 2 OUT: CARTZILLA · ..."
function HudController:UpdateBossLine(now: number)
	local run = self.C.RunClient
	local t = run:Now()
	local text, color, pulse = "", C.TextDim, false
	local out = nil
	for _, enc in run.Encounters do
		if not out or (enc.Main and not out.Main) then
			out = enc
		end
	end
	if out then
		if out.Main then
			text = if out.Stage == "Warn" then "THE FINAL ONE IS COMING · 67 ARENA" else "THE FINAL ONE · 67 ARENA (CENTRE)"
			color, pulse = C.Danger, true
		else
			local zone = ArenaData.ByKey[out.Zone]
			local what = if out.Stage == "Warn" then "BOSS " .. out.Slot .. " COMING" else "BOSS " .. out.Slot .. " OUT: " .. out.Title
			text = what .. "  ·  " .. (if zone then zone.Name .. " " .. string.rep("★", zone.Stars) else "")
			color, pulse = if zone then zone.Color else C.Danger, out.Stage == "Warn"
		end
	else
		local nextSlot = nil
		for _, slot in BossData.Slots do
			if slot.At - BossData.WarnLead > t then
				nextSlot = slot
				break
			end
		end
		if nextSlot then
			local zone = ArenaData.ByKey[nextSlot.Zone]
			text = string.format("BOSS %d IN %s  ·  %s %s", nextSlot.Index, Format.Time(math.max(0, nextSlot.At - t)), zone.Name, string.rep("★", zone.Stars))
			color = if nextSlot.At - t < 30 then zone.Color else C.TextDim
		elseif t < BossData.Main.At then
			text = "THE FINAL ONE IN " .. Format.Time(math.max(0, BossData.Main.At - t)) .. "  ·  67 ARENA"
			color = if BossData.Main.At - t < 60 then C.Danger else C.TextDim
		end
	end
	if self.Last.BossLine ~= text then
		self.Last.BossLine = text
		self.BossLine.Text = text
	end
	self.BossLine.TextColor3 = if pulse then color:Lerp(C.Text, (math.sin(now * 6) + 1) * 0.25) else color
end

-- walking into a zone: the zone chip pops; the first time, a toast with its tagline (and the
-- server drops a little XP). Never over the level-up cards.
function HudController:ZoneEntered(zone, first: boolean)
	Kit.Pop(self.ZoneChip, 0.12)
	if first and not self.C.LevelUpController:IsOpen() then
		local stars = if zone.Stars > 0 then " " .. string.rep("★", zone.Stars) else ""
		self.C.BannerController:Toast("NEW ZONE: " .. zone.Name .. stars, "Reward", zone.Tagline)
	end
end

-- your items: their icon and level (I, II, III); the souls of the Soul Collector
function HudController:SetItems(items: { any })
	Widgets.Clear(self.ItemRow)
	for i, it in items do
		local def = ItemData.ByKey[it.Key]
		if def then
			local tile = Icons.Make(self.ItemRow, "Item", it.Key, 26, { LayoutOrder = i })
			local maxed = it.Level >= def.MaxLevel
			Kit.Label({
				Name = "Level",
				Text = if maxed then "MAX" else ROMAN[it.Level] or tostring(it.Level),
				Size = UDim2.fromOffset(26, 11),
				Position = UDim2.new(1, 3, 1, 2),
				AnchorPoint = Vector2.new(1, 1),
				Font = F.Title,
				MaxTextSize = 10,
				TextColor3 = if maxed then C.Gold else C.Text,
				TextXAlignment = Enum.TextXAlignment.Right,
				StrokeThickness = 1,
				StrokeTransparency = 0.2,
				ZIndex = 3,
				Parent = tile,
			})
		end
	end
	local souls = self.C.RunClient.Souls
	if souls and souls.Max and souls.Max > 0 then
		local pill = Kit.Panel({ Name = "Souls", Size = UDim2.fromOffset(66, 26), LayoutOrder = 99, Radius = 13, Parent = self.ItemRow })
		local stroke = pill:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = Color3.fromRGB(170, 220, 255)
		Kit.Label({ Text = string.format("◆ %d/%d", souls.Count or 0, souls.Max), Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Font = F.Bold, MaxTextSize = 12, TextColor3 = Color3.fromRGB(170, 220, 255), Parent = pill })
	end
end

-- your synergies: small pills with their names
function HudController:SetSynergies(keys: { string })
	Widgets.Clear(self.SynergyRow)
	for i, key in keys do
		local syn = SynergyData.ByKey[key]
		if syn then
			local pill = Kit.New("Frame", {
				Name = key,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 18),
				BackgroundColor3 = C.Surface,
				BackgroundTransparency = Theme.Glass,
				LayoutOrder = i,
				Parent = self.SynergyRow,
			})
			Kit.Corner(pill, 9)
			Kit.Stroke(pill, 1.5, C.Mythic, 0.25)
			Kit.Padding(pill, 8, 0)
			Kit.New("TextLabel", {
				Text = syn.Name,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromScale(0, 1),
				BackgroundTransparency = 1,
				Font = F.Bold,
				TextSize = 11,
				TextColor3 = C.Mythic,
				Parent = pill,
			})
		end
	end
end

-- ITEM ACQUIRED / ITEM LEVEL UP (old -> new level) and the mechanic it unlocked
function HudController:ItemGained(p)
	local def = ItemData.ByKey[p.Key]
	if not def then
		return
	end
	if p.Maxed then
		self.C.BannerController:Toast(def.Name .. " is maxed: +25 coins", "Reward")
		return
	end
	local color = Rarity.Colors[def.Rarity] or C.Text
	local level = p.Level or 1
	local old = p.Old or (level - 1)
	Widgets.Clear(self.ItemCardIcon)
	Icons.Make(self.ItemCardIcon, "Item", def.Key, 52)
	local tag = string.upper(def.Rarity) .. (if def.Type == "BossRelic" then " BOSS RELIC" elseif def.Type == "Premium" then " PREMIUM ITEM" else " ITEM")
	if old <= 0 then
		self.ItemCardTag.Text = "ITEM ACQUIRED  ·  " .. tag
	else
		self.ItemCardTag.Text = string.format("ITEM LEVEL UP  %s → %s  ·  %s", ROMAN[old] or tostring(old), ROMAN[level] or tostring(level), tag)
	end
	self.ItemCardTag.TextColor3 = color
	self.ItemCardName.Text = def.Name .. "  " .. (ROMAN[level] or tostring(level)) .. (if level >= def.MaxLevel then "  (MAX)" else "")
	local at = ItemData.At(def.Key, level)
	self.ItemCardDesc.Text = if old <= 0 then def.Desc .. (if at then "  " .. at.Desc else "") else (if at then at.Desc else def.Desc)
	self.ItemCardNew.Text = if p.New then "NEW: " .. p.New else ""
	self.ItemCardNew.Visible = p.New ~= nil
	self.ItemCardStroke.Color = color
	self.ItemCardStroke.Transparency = 0.1
	self.ItemCard.Visible = true
	Kit.Appear(self.ItemCard)
	self.ItemCardUntil = os.clock() + (if p.New then 4.6 else 3.6)
	self.C.EffectsController:Flash(color, 0.12)
end

function HudController:SynergyOn(_p)
	self:SetSynergies(self.C.RunClient.Synergies)
	Kit.Pop(self.SynergyRow, 0.2)
end

-- a short word from the build under the synergies
function HudController:PerkPop(p)
	self.PerkLabel.Text = p.Text or ""
	self.PerkLabel.Visible = true
	Kit.Pop(self.PerkLabel, 0.2)
	self.PerkUntil = os.clock() + math.max(1.6, math.min(p.Duration or 0, 4))
end

function HudController:SetSouls(_souls, lost: boolean?)
	self:SetItems(self.C.RunClient.Items)
	if lost then
		self.C.BannerController:Toast("THE SOULS SAVED YOU", "Reward")
	end
end

function HudController:SetPlating(plating)
	local bar = self.PlatingBar
	bar.Frame.Visible = plating ~= nil
	if plating then
		bar:Set(plating.HP / math.max(1, plating.Max))
	end
end

function HudController:SetDash(dash)
	local has = dash ~= nil and dash.Max > 0
	self.DashButton.Visible = has
	if has then
		local dots = string.rep("●", dash.Charges) .. string.rep("○", dash.Max - dash.Charges)
		self.DashDots.Text = if Kit.IsTouch() then dots else "SPACE " .. dots
	end
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
	-- the right column: the minimap under the coins, the boss bar under the minimap
	local Minimap = self.C.MinimapController
	local mapSize = Minimap.SizeFor(touch)
	self.BossPanel.Position = UDim2.new(1, 0, 0, Minimap.Top + mapSize + 10)
	self.FragmentToast.Position = UDim2.new(1, -(mapSize + 12), 0, Minimap.Top + 2)
	-- the dash button sits above the abilities (the stick keeps the left side on phones)
	self.DashButton.Position = UDim2.new(1, 0, 1, -(SLOT + if touch then 76 else 56))
	self.ItemCard.Visible = false
	self.PerkLabel.Visible = false
	self:SetDash(nil)
	self:SetPlating(nil)
	Widgets.Clear(self.ItemRow)
	Widgets.Clear(self.SynergyRow)
	table.clear(self.Last)
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

-- one ability slot: small icon, level in the corner, gold border at max, teal when evolved,
-- pulsing teal when its evolution is ready
local function weaponSlot(parent: Instance, order: number, key: string?, level: number, maxLevel: number, evolved: boolean, ready: boolean?): Frame
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
	local top = evolved or level >= maxLevel
	if top or ready then
		local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = if evolved or ready then C.Mythic else C.Gold
		stroke.Transparency = 0.1
		stroke.Thickness = if ready then 2.5 else 1.5
	end
	Icons.Make(frame, "Weapon", key, SLOT - 4, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	Kit.Label({
		Name = "Level",
		Text = if evolved then "EVO" elseif level >= maxLevel then "MAX" else tostring(level),
		Size = UDim2.fromOffset(if top then 26 else 14, 13),
		Position = UDim2.new(1, -3, 1, -2),
		AnchorPoint = Vector2.new(1, 1),
		Font = F.Title,
		MaxTextSize = 11,
		TextColor3 = if evolved then C.Mythic elseif top then C.Gold else C.Text,
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
	local ready = {}
	for _, key in loadout.EvoReady or {} do
		ready[key] = true
	end
	for i, w in loadout.Weapons do
		local def = WeaponData.ByKey[w.Key]
		if def then
			weaponSlot(self.WeaponRow, i, w.Key, w.Level, def.MaxLevel, w.Evolved == true, ready[w.Key])
		end
	end
	for i = #loadout.Weapons + 1, loadout.Slots do
		weaponSlot(self.WeaponRow, i, nil, 0, 1, false)
	end
	self.EvoPill.Visible = next(ready) ~= nil
	self:SetItems(loadout.Items or {})
	self:SetSynergies(loadout.Synergies or {})
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
	for _, it in loadout.Items or {} do
		order += 1
		Icons.Make(self.BuildGrid, "Item", it.Key, 32, { LayoutOrder = order })
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

-- the difficulty chip of this run
function HudController:SetDifficulty(index: number)
	local tier = DifficultyData.Get(index)
	self.DiffLabel.Text = tier.Numeral .. "  " .. tier.Name
	self.DiffLabel.TextColor3 = tier.Color
	self.DiffStroke.Color = tier.Color
end

-- an evolution became available: the pill pops (the level-up screen offers it first)
function HudController:EvolutionReady(p)
	self.EvoLabel.Text = "EVOLUTION AVAILABLE"
	self.EvoPill.Visible = true
	Kit.Pop(self.EvoPill, 0.25)
	-- when the level-up screen is already up, its first card is the evolution itself
	if not self.C.LevelUpController:IsOpen() then
		self.C.BannerController:Show("EVOLUTION AVAILABLE", (p.Title or "") .. " - level up to evolve", "Evolution")
	end
end

function HudController:FragmentPop(total: number)
	local toast = self.FragmentToast
	toast.Text = "+1 FRAGMENT (" .. total .. ")"
	toast.Visible = true
	Kit.Pop(toast, 0.2)
	self.FragmentUntil = os.clock() + 2.5
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
	if self.FragmentUntil and now >= self.FragmentUntil then
		self.FragmentUntil = nil
		self.FragmentToast.Visible = false
	end
	if self.EvoPill.Visible then
		local stroke = self.EvoPill:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Transparency = 0.1 + (math.sin(now * 6) + 1) * 0.25
	end
	for key, b in self.Buffs do
		local left = b.Until - now
		if left <= 0 then
			self:SetBuff(key, 0)
		else
			b.Label.Text = string.format("%s  %ds", b.Name, math.ceil(left))
		end
	end
	-- 67 TOWN
	self:UpdateZone(now)
	if self.ItemCardUntil and now >= self.ItemCardUntil then
		self.ItemCardUntil = nil
		self.ItemCard.Visible = false
	end
	if self.PerkUntil and now >= self.PerkUntil then
		self.PerkUntil = nil
		self.PerkLabel.Visible = false
	end
	local dash = run.Dash
	if dash and self.DashButton.Visible then
		local charging = dash.Charges < dash.Max
		local frac = if charging then math.clamp(1 - (dash.ReadyAt - now) / math.max(0.1, dash.Recharge), 0, 1) else 1
		self.DashFill.Size = UDim2.fromScale(1, frac)
		self.DashStroke.Transparency = if dash.Charges > 0 then 0.1 else 0.6
	end
end

function HudController:Start()
	RunService.RenderStepped:Connect(function()
		self:Update()
	end)
end

return HudController
