--[[
	MinimapController - the minimap of 67 TOWN. Only in a run (never in the lobby).

	North is up, like the run camera, so the map and the screen always agree.
	Shows what helps you decide where to go, not everything:
	  * the five zones in their colours; a zone you have not been to is dim with a "?"
	  * THE RIFT: locked (a lock + when it opens) until it opens
	  * you (an arrow), your party (blue dots)
	  * BOSSES: a big red marker with the boss number (1-4), blinking at its lair while it is
	    announced, pulsing where it fights; THE FINAL ONE: a huge "67" marker in the centre
	  * the 67 ARENA ring in the centre (from 14:30, bright while it is sealed)
	  * ELITES (purple), items on the ground (rarity colour), souls, chests, an awake 67
	    VAULT (gold)
	  * the 67 RUSH zone (a gold frame)
	  * lairs (rings; the lair of the next boss always)
	Never enemies, gems or secrets. Static shapes are built once; markers come from a small
	pool and move GameConfig.Map.MinimapHz times a second; your arrow every frame.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local ArenaData = require(Shared.ArenaData)
local GameConfig = require(Shared.GameConfig)
local Rarity = require(Shared.Rarity)
local BossData = require(Shared.BossData)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)

local MinimapController = {}

local C = Theme.Colors
local F = Theme.Fonts
local M = Theme.Margin
local HALF = GameConfig.Arena.HalfSize
local MAX_MARKERS = 28
local BOSS_RED = Color3.fromRGB(255, 70, 60)
local ELITE = Color3.fromRGB(190, 110, 255)
local PAD = 6

-- the minimap's size in design units (the HUD lays the right column out around it)
function MinimapController.SizeFor(touch: boolean): number
	return if touch then 124 else 150
end
MinimapController.Top = 48 -- under the coins / pause row

-- arena (x, z) -> position on the map (0..1)
local function uv(x: number, z: number): UDim2
	return UDim2.fromScale((x + HALF) / (HALF * 2), (z + HALF) / (HALF * 2))
end

function MinimapController:Init(controllers)
	self.C = controllers
	local gui, root = Kit.ScreenGui("S67Minimap", 10, Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	self.Gui = gui
	local safe = Kit.New("Frame", { Name = "Safe", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
	Kit.Padding(safe, M - 8, M - 14)
	local size = MinimapController.SizeFor(Kit.IsTouch())
	local panel = Kit.Panel({
		Name = "Minimap",
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.new(1, 0, 0, MinimapController.Top),
		AnchorPoint = Vector2.new(1, 0),
		Radius = 14,
		Parent = safe,
	})
	self.Panel = panel
	local map = Kit.New("Frame", {
		Name = "Map",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -PAD * 2, 1, -PAD * 2),
		Position = UDim2.fromOffset(PAD, PAD),
		ClipsDescendants = true,
		Parent = panel,
	})
	Kit.Corner(map, 9)
	self.Map = map
	self.MapSize = size - PAD * 2
	self.Zones = {} :: { [string]: { Frame: Frame, Unknown: TextLabel, Stroke: UIStroke } }
	self.LairRings = {} :: { [string]: Frame }
	self.Markers = {}
	self.Next = 0

	-- zones
	for _, zone in ArenaData.Zones do
		local r = zone.Rect
		local frame = Kit.New("Frame", {
			Name = zone.Key,
			BackgroundColor3 = zone.Color,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			Position = uv(r.MinX, r.MinZ),
			Size = UDim2.fromScale((r.MaxX - r.MinX) / (HALF * 2), (r.MaxZ - r.MinZ) / (HALF * 2)),
			ZIndex = 1,
			Parent = map,
		})
		local stroke = Kit.Stroke(frame, 1, C.SurfaceDark, 0.3)
		local unknown = Kit.Label({
			Name = "Unknown",
			Text = "?",
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Font = F.Title,
			MaxTextSize = 16,
			TextColor3 = zone.Color:Lerp(C.Text, 0.4),
			ZIndex = 2,
			Parent = frame,
		})
		self.Zones[zone.Key] = { Frame = frame, Unknown = unknown, Stroke = stroke }
	end
	-- the rift's cliffs (a line) and its lock
	local rift = ArenaData.ByKey.Rift.Rect
	for _, line in { { rift.MinX, rift.MaxZ, rift.MaxX, rift.MaxZ }, { rift.MaxX, rift.MinZ, rift.MaxX, rift.MaxZ } } do
		local horizontal = line[2] == line[4]
		Kit.New("Frame", {
			Name = "RiftWall",
			BackgroundColor3 = ArenaData.ByKey.Rift.Color,
			BorderSizePixel = 0,
			Position = uv(line[1], line[2]),
			Size = if horizontal then UDim2.new((line[3] - line[1]) / (HALF * 2), 0, 0, 2) else UDim2.new(0, 2, (line[4] - line[2]) / (HALF * 2), 0),
			AnchorPoint = if horizontal then Vector2.new(0, 0.5) else Vector2.new(0.5, 0),
			ZIndex = 3,
			Parent = map,
		})
	end
	local lockAt = uv((rift.MinX + rift.MaxX) / 2, (rift.MinZ + rift.MaxZ) / 2)
	self.Lock = Widgets.Lock(map, 16, C.Text, { Position = lockAt - UDim2.fromOffset(0, 6), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4 })
	self.LockText = Kit.Label({
		Name = "LockText",
		Text = string.format("%d:%02d", math.floor(ArenaData.RiftOpensAt / 60), ArenaData.RiftOpensAt % 60),
		Size = UDim2.fromOffset(40, 12),
		Position = lockAt + UDim2.fromOffset(0, 10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = F.Bold,
		MaxTextSize = 11,
		TextColor3 = C.Text,
		ZIndex = 4,
		Parent = map,
	})
	-- landmarks: tiny dots to find your way
	for _, lm in ArenaData.Landmarks do
		local dot = Kit.New("Frame", {
			Name = lm.Key,
			BackgroundColor3 = C.Text,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(4, 4),
			Position = uv(lm.X, lm.Z),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 3,
			Parent = map,
		})
		Kit.Corner(dot, 2)
	end
	-- lairs (shown once you have been in their zone)
	for _, lair in ArenaData.Lairs do
		local d = math.max(8, lair.R * 2 / (HALF * 2) * self.MapSize)
		local ring = Kit.New("Frame", {
			Name = lair.Key,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(d, d),
			Position = uv(lair.X, lair.Z),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = false,
			ZIndex = 3,
			Parent = map,
		})
		Kit.Corner(ring, d)
		Kit.Stroke(ring, 1.5, C.Text, 0.35)
		self.LairRings[lair.Key] = ring
	end
	-- THE FINAL ONE's arena in the centre
	do
		local main = BossData.Main
		local d = math.max(10, main.ArenaR * 2 / (HALF * 2) * self.MapSize)
		local ring = Kit.New("Frame", {
			Name = "Arena67",
			BackgroundColor3 = BOSS_RED,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(d, d),
			Position = uv(main.X, main.Z),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = false,
			ZIndex = 3,
			Parent = map,
		})
		Kit.Corner(ring, d)
		self.ArenaStroke = Kit.Stroke(ring, 2, BOSS_RED, 0.2)
		self.ArenaRing = ring
	end
	-- north
	Kit.Label({
		Name = "North",
		Text = "N",
		Size = UDim2.fromOffset(14, 12),
		Position = UDim2.new(0.5, 0, 0, 1),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = F.Title,
		MaxTextSize = 11,
		TextColor3 = C.TextDim,
		ZIndex = 6,
		Parent = map,
	})
	-- you
	self.Arrow = Kit.Label({
		Name = "You",
		Text = "▲",
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = F.Title,
		MaxTextSize = 14,
		TextColor3 = C.Text,
		StrokeThickness = 1.5,
		StrokeTransparency = 0,
		ZIndex = 8,
		Parent = map,
	})
end

---------------------------------------------------------------------------
-- markers (pooled)
---------------------------------------------------------------------------
function MinimapController:Marker(i: number)
	local m = self.Markers[i]
	if not m then
		local frame = Kit.New("Frame", {
			Name = "Marker" .. i,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = false,
			ZIndex = 6,
			Parent = self.Map,
		})
		local corner = Kit.Corner(frame, 8)
		local stroke = Kit.Stroke(frame, 1.5, C.SurfaceDark, 0)
		local label = Kit.Label({
			Name = "Glyph",
			Text = "",
			Size = UDim2.fromScale(1, 1),
			Font = F.Title,
			MaxTextSize = 11,
			TextColor3 = C.Text,
			ZIndex = 7,
			Parent = frame,
		})
		m = { Frame = frame, Corner = corner, Stroke = stroke, Glyph = label }
		self.Markers[i] = m
	end
	return m
end

-- markers: { X, Z, Size, Color, Glyph?, Round?, Diamond?, Blink? }
function MinimapController:Targets(now: number): { any }
	local run = self.C.RunClient
	local out = {}
	-- the 67 RUSH zone and awake vaults
	for i, v in run.Map.Vaults do
		if v.State == 1 then
			local def = ArenaData.Vaults[i]
			table.insert(out, { X = def.X, Z = def.Z, Size = 11, Color = C.Gold, Glyph = "", Round = false, Blink = true })
		end
	end
	-- items, souls, chests
	for _, item in self.C.LootRenderer.Items do
		if item.Soul then
			table.insert(out, { X = item.X, Z = item.Z, Size = 5, Color = Color3.fromRGB(170, 220, 255), Round = true })
		else
			table.insert(out, { X = item.X, Z = item.Z, Size = 9, Color = Rarity.Colors[item.Def.Rarity] or C.Text, Diamond = true })
		end
	end
	-- elites
	for id, elite in run.Elites do
		local e = run.Enemies[id]
		if e then
			table.insert(out, { X = e.RX or e.X1, Z = e.RZ or e.Z1, Size = 10, Color = ELITE, Glyph = "E", Diamond = true })
		elseif now - elite.Since < 4 then
			table.insert(out, { X = elite.X, Z = elite.Z, Size = 10, Color = ELITE, Glyph = "E", Diamond = true, Blink = true })
		end
	end
	for _, item in self.C.PickupRenderer.Items do
		if item.Kind == "Chest" or item.Kind == "Chest67" then
			table.insert(out, { X = item.X, Z = item.Z, Size = 8, Color = C.Gold })
		end
	end
	-- party members
	for _, name in run.Party or {} do
		for _, player in Players:GetPlayers() do
			if player.DisplayName == name and player:GetAttribute("InRun") then
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					local c = run.Center
					table.insert(out, { X = root.Position.X - c.X, Z = root.Position.Z - c.Z, Size = 7, Color = Color3.fromRGB(110, 190, 255), Round = true })
				end
			end
		end
	end
	-- BOSSES (last = drawn on top): arriving (blinking at the lair / the arena) or out
	for _, enc in run.Encounters do
		local size = if enc.Main then 22 else 17
		local glyph = if enc.Main then "67" else tostring(enc.Slot or "!")
		local color = if enc.Crowned then C.Gold else BOSS_RED
		local shown = false
		for _, id in enc.Ids do
			local e = run.Enemies[id]
			if e then
				table.insert(out, { X = e.RX or e.X1, Z = e.RZ or e.Z1, Size = size, Color = color, Glyph = glyph, Round = true, Pulse = true })
				shown = true
			end
		end
		if not shown then
			table.insert(out, { X = enc.X, Z = enc.Z, Size = size, Color = color, Glyph = glyph, Round = true, Blink = true })
		end
	end
	return out
end

function MinimapController:UpdateMarkers(now: number)
	local run = self.C.RunClient
	-- zones: visited / unknown, the 67 RUSH frame, the lock
	local hot = run.Map.Hot
	for key, z in self.Zones do
		local visited = run.Map.Visited[key] == true
		local isHot = hot == key
		z.Frame.BackgroundTransparency = if isHot then 0.15 + math.sin(now * 5) * 0.1 elseif visited then 0.4 else 0.74
		z.Unknown.Visible = not visited
		z.Stroke.Color = if isHot then C.Gold else C.SurfaceDark
		z.Stroke.Thickness = if isHot then 2 else 1
		z.Stroke.Transparency = if isHot then 0 else 0.3
	end
	local riftOpen = run.Map.Rift == true
	self.Lock.Visible = not riftOpen
	self.LockText.Visible = not riftOpen
	-- lairs: the ones you have seen, the next boss's always
	local runTime = run:Now()
	local nextZone = nil
	for _, slot in BossData.Slots do
		if slot.At > runTime - 5 then
			nextZone = slot.Zone
			break
		end
	end
	for _, lair in ArenaData.Lairs do
		local ring = self.LairRings[lair.Key]
		ring.Visible = run.Map.Visited[lair.Zone] == true or lair.Zone == nextZone
	end
	-- the 67 ARENA: from 14:30 (or when THE FINAL ONE is out), bright while sealed
	local main = BossData.Main
	local mainOut = false
	for _, enc in run.Encounters do
		mainOut = mainOut or enc.Main
	end
	self.ArenaRing.Visible = mainOut or run.Arena ~= nil or runTime >= main.At - 30
	self.ArenaRing.BackgroundTransparency = if run.Arena then 0.55 + math.sin(now * 5) * 0.1 else 1
	self.ArenaStroke.Transparency = if run.Arena or mainOut then 0 else 0.4
	-- markers
	local targets = self:Targets(now)
	for i = 1, MAX_MARKERS do
		local t = targets[i]
		local m = if t or self.Markers[i] then self:Marker(i) else nil
		if m then
			if t then
				local s = t.Size
				if t.Pulse then
					s *= 1 + math.sin(now * 6) * 0.12
				end
				m.Frame.Size = UDim2.fromOffset(s, s)
				m.Frame.Position = uv(math.clamp(t.X, -HALF, HALF), math.clamp(t.Z, -HALF, HALF))
				m.Frame.BackgroundColor3 = t.Color
				m.Frame.BackgroundTransparency = if t.Blink and math.floor(now * 4) % 2 == 0 then 0.6 else 0
				m.Frame.Rotation = if t.Diamond then 45 else 0
				m.Corner.CornerRadius = UDim.new(0, if t.Round then math.ceil(s / 2) else 2)
				m.Glyph.Text = t.Glyph or ""
				m.Glyph.Rotation = if t.Diamond then -45 else 0
				m.Frame.Visible = true
			else
				m.Frame.Visible = false
			end
		end
	end
end

function MinimapController:UpdateArrow()
	local run = self.C.RunClient
	local x, z = run:LocalXZ()
	if not x or not z then
		self.Arrow.Visible = false
		return
	end
	self.Arrow.Visible = true
	self.Arrow.Position = uv(math.clamp(x, -HALF, HALF), math.clamp(z, -HALF, HALF))
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local look = root.CFrame.LookVector
		-- screen up is -Z (north): rotate the arrow to where the hero faces
		self.Arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))
	end
end

function MinimapController:Update()
	local run = self.C.RunClient
	-- only in a run, and only while the HUD shows (level-up cards, death and results cover it)
	local hud = self.C.HudController
	local active = run.Active and hud.Gui.Enabled and hud.Safe.Visible
	self.Gui.Enabled = active
	if not active then
		return
	end
	self:UpdateArrow()
	local now = os.clock()
	if now >= self.Next then
		self.Next = now + 1 / GameConfig.Map.MinimapHz
		self:UpdateMarkers(now)
	end
end

function MinimapController:Start()
	RunService.RenderStepped:Connect(function()
		self:Update()
	end)
end

return MinimapController
