--[[
	EventMap - builds the lobby: "67 LAND", the event map (what it shows: shared/EventMapData).

	A small floating island above the clouds. It reads like a real place first (a stone
	terrace, a plaza with a monument, a park, a fenced yard, a rocky plateau, a golden summit)
	and like a joke second: the monument is the 6-7 hand gesture carved in marble, the summit
	gate is shaped like the number 67, the clouds in the sky spell 67...

	Lobby space (y = 0 is the ground). The hub camera always looks towards +Z (screen-left is
	+X), so the route climbs away from it, and every sign faces -Z to stay readable:

	                            THE 67 SUMMIT (VII)         z 200, y 14
	                   floating bridge  /
	                             THE RIFT (V, VI)           z 154, y 6 (stairs up)
	      THE HORDE YARD (III, IV)          THE PARK (I, II)  z 110 / 84
	                     THE PLAZA: THE GREAT BALANCE       z 44
	                     welcome arch                       z 18
	                     SPAWN: the hub stage               z -6

	Kept from the old lobby (other systems look for them): the HubStage folder (the spawn
	pedestal), PlayPortal, AfkCamp, Leaderboard = "BestTime", SecretRegion "TouchGrass".
	New attributes: EventGate = tier (walk in to play it: GameManager), GateLock / GateLabel /
	GateFrame (styled per player: client EventMapController), NpcKey (speech bubbles),
	EventBoard (today's live events), Beacon (stands on your NEXT gate), Button67 (a prompt),
	Bob / BobPhase / BobSpeed (WorldController floats them).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local DifficultyData = require(Shared.DifficultyData)
local EventMapData = require(Shared.EventMapData)
local HeroModels = require(Shared.HeroModels)

local EventMap = {}

local rgb = Color3.fromRGB
local ang = CFrame.Angles
local UP = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis (X) turned up (Y)
local FRONT = CFrame.Angles(0, math.rad(90), 0) -- a cylinder's axis turned to face -Z / +Z
local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
local NEON, METAL, GLASS = Enum.Material.Neon, Enum.Material.Metal, Enum.Material.Glass

-- the island's palette
local COL = {
	Terrace = rgb(172, 160, 218), -- lavender stone
	Trim = rgb(112, 98, 176),
	Ink = rgb(38, 30, 68), -- sign boards
	Cream = rgb(236, 228, 210), -- plaza, paths
	Lawn = rgb(124, 196, 126),
	ParkLawn = rgb(134, 206, 122),
	Hedge = rgb(78, 160, 96),
	Rock = rgb(118, 104, 164),
	Under = rgb(96, 84, 140),
	Asphalt = rgb(74, 68, 94),
	Cliff = rgb(88, 76, 120),
	Ash = rgb(64, 56, 86),
	Marble = rgb(242, 228, 188),
	Gold = rgb(255, 200, 70),
	GlowGold = rgb(255, 208, 90),
	Wood = rgb(150, 108, 74),
	Text = rgb(255, 214, 96),
	Paper = rgb(246, 240, 226),
}

local ORIGIN = Vector3.zero
local current: Instance = workspace

local function L(x: number, y: number, z: number): CFrame
	return CFrame.new(ORIGIN + Vector3.new(x, y, z))
end

---------------------------------------------------------------------------
-- parts
---------------------------------------------------------------------------
local function part(name: string, size: Vector3, cf: CFrame, color: Color3, extra: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	if extra then
		for k, v in extra do
			if k == "Attributes" then
				for ak, av in v do
					p:SetAttribute(ak, av)
				end
			elseif k ~= "Mesh" then
				(p :: any)[k] = v
			end
		end
		if extra.Mesh then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
	end
	p.Parent = current
	return p
end

local function box(name: string, sx: number, sy: number, sz: number, cf: CFrame, color: Color3, extra: { [string]: any }?): Part
	return part(name, Vector3.new(sx, sy, sz), cf, color, extra)
end

-- an ellipsoid filling its box (the soft shapes of the island)
local function egg(name: string, sx: number, sy: number, sz: number, cf: CFrame, color: Color3, extra: { [string]: any }?): Part
	local e = extra or {}
	e.Mesh = true
	return part(name, Vector3.new(sx, sy, sz), cf, color, e)
end

local function ball(name: string, d: number, cf: CFrame, color: Color3, extra: { [string]: any }?): Part
	local e = extra or {}
	e.Shape = BALL
	return part(name, Vector3.new(d, d, d), cf, color, e)
end

-- a cylinder along cf's Y axis
local function rod(name: string, length: number, d: number, cf: CFrame, color: Color3, extra: { [string]: any }?): Part
	local e = extra or {}
	e.Shape = CYL
	return part(name, Vector3.new(length, d, d), cf * UP, color, e)
end

-- a flat round slab whose TOP is at y = top
local function disc(name: string, thick: number, d: number, x: number, top: number, z: number, color: Color3, extra: { [string]: any }?): Part
	local e = extra or {}
	e.Shape = CYL
	return part(name, Vector3.new(thick, d, d), L(x, top - thick / 2, z) * UP, color, e)
end

-- a round plate facing -Z (a medallion, a portal ring)
local function plate(name: string, depth: number, d: number, cf: CFrame, color: Color3, extra: { [string]: any }?): Part
	local e = extra or {}
	e.Shape = CYL
	return part(name, Vector3.new(depth, d, d), cf * FRONT, color, e)
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	current = f
	return f
end

local function light(p: BasePart, range: number, brightness: number, color: Color3)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = color
	l.Shadows = false
	l.Parent = p
	return l
end

-- floats up and down on the client (WorldController); a phase keeps groups apart
local function bob(p: BasePart, amount: number, phase: number?, speed: number?)
	p:SetAttribute("Bob", amount)
	if phase then
		p:SetAttribute("BobPhase", phase)
	end
	if speed then
		p:SetAttribute("BobSpeed", speed)
	end
end

-- a CFrame at (x, y, z) whose front (-Z) faces the point (tx, tz) (on the same height)
local function facing(x: number, y: number, z: number, tx: number, tz: number): CFrame
	local pos = ORIGIN + Vector3.new(x, y, z)
	return CFrame.lookAt(pos, ORIGIN + Vector3.new(tx, y, tz))
end

---------------------------------------------------------------------------
-- text
---------------------------------------------------------------------------
export type SignSpec = {
	Title: string,
	Sub: string?,
	Color: Color3?,
	SubColor: Color3?,
	Bg: Color3?,
	Glow: boolean?, -- ignores the lighting (bright text)
	SubFont: Enum.Font?,
	Split: number?, -- share of the height for the title (with a Sub)
}

-- text painted on one face of a part
local function sign(target: BasePart, face: Enum.NormalId, spec: SignSpec): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = if spec.Glow then 0 else 1
	gui.Parent = target
	if spec.Bg then
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = spec.Bg
		bg.BorderSizePixel = 0
		bg.Parent = gui
	end
	local split = if spec.Sub then (spec.Split or 0.6) else 1
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(0.92, 0, split * 0.9, 0)
	title.Position = UDim2.new(0.04, 0, split * 0.05, 0)
	title.Text = spec.Title
	title.TextScaled = true
	title.Font = Enum.Font.LuckiestGuy
	title.TextColor3 = spec.Color or COL.Text
	title.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = rgb(24, 18, 44)
	stroke.Transparency = if spec.Bg and spec.Bg.R > 0.7 then 1 else 0.2
	stroke.Parent = title
	if spec.Sub then
		local sub = Instance.new("TextLabel")
		sub.Name = "Sub"
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.new(0.9, 0, (1 - split) * 0.8, 0)
		sub.Position = UDim2.new(0.05, 0, split, 0)
		sub.Text = spec.Sub
		sub.TextScaled = true
		sub.Font = spec.SubFont or Enum.Font.BuilderSansBold
		sub.TextColor3 = spec.SubColor or rgb(236, 232, 250)
		sub.Parent = gui
	end
	return gui
end

-- a small board on two legs (or hanging from a post) with a painted sign, facing -Z
local function signboard(name: string, w: number, h: number, cf: CFrame, spec: SignSpec, legs: number?): Part
	local board = box(name, w, h, 0.35, cf, spec.Bg or COL.Paper)
	sign(board, Enum.NormalId.Front, spec)
	local legH = legs or 0
	if legH > 0 then
		for _, side in { -1, 1 } do
			rod(name .. "Leg", legH, 0.32, cf * CFrame.new(side * (w / 2 - 0.5), -(h / 2 + legH / 2) + 0.1, 0.25), COL.Wood)
		end
	end
	return board
end

-- a floating label (always faces the camera); lines are TextLabels named Line1..LineN
local function billboard(target: BasePart, name: string, width: number, height: number, lines: { { string | number | Color3 } }, maxDistance: number?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.new(width, 0, height, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 180
	gui.AlwaysOnTop = false
	gui.Parent = target
	local y = 0
	for i, line in lines do
		local text, share, color = line[1] :: string, line[2] :: number, line[3] :: Color3
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. i
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, share, 0)
		label.Position = UDim2.new(0, 0, y, 0)
		label.Text = text
		label.TextScaled = true
		label.Font = if i == 1 then Enum.Font.LuckiestGuy else Enum.Font.BuilderSansExtraBold
		label.TextColor3 = color
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = if i == 1 then 3 else 2
		stroke.Color = rgb(24, 18, 44)
		stroke.Parent = label
		y += share
	end
	return gui
end

---------------------------------------------------------------------------
-- the ground: one island made of round slabs, a rocky underside, clouds below
---------------------------------------------------------------------------
local function ground(lobby: Instance)
	folder("Ground", lobby)
	local grass = Enum.Material.Grass
	-- lawns that tie the zones together (tops a hair apart: no flicker)
	disc("Lawn", 2, 66, 24, 0, 36, COL.Lawn, { Material = grass })
	disc("Lawn", 2, 68, -30, -0.03, 76, COL.Lawn, { Material = grass })
	disc("Lawn", 2, 74, 10, -0.06, 106, COL.Lawn, { Material = grass })
	disc("CampLawn", 2, 28, 33, -0.02, 4, COL.Lawn, { Material = grass })
	disc("Lawn", 2, 40, -24, -0.09, 22, COL.Lawn, { Material = grass })
	disc("Lawn", 2, 26, 22, -0.12, 68, COL.Lawn, { Material = grass })
	disc("Lawn", 2, 32, -40, -0.15, 36, COL.Lawn, { Material = grass })
	disc("Lawn", 2, 22, 40, -0.18, 60, COL.Lawn, { Material = grass })
	-- the zones
	disc("SpawnTerrace", 2, 50, 0, 0.04, -4, COL.Terrace)
	disc("TerraceRing", 0.06, 34, 0, 0.12, -4, rgb(196, 186, 236), { CanCollide = false })
	disc("TerraceInner", 0.06, 31, 0, 0.2, -4, COL.Terrace, { CanCollide = false })
	for i, pl in { { -17, -18 }, { 19, -14 }, { -21, 8 } } do
		disc("Planter", 1.6, 5, pl[1], 1.6, pl[2], COL.Trim)
		egg("PlanterBush", 5, 2.8, 5, L(pl[1], 2.6, pl[2]), COL.Hedge, { CanCollide = false })
		ball("PlanterFlower", 1.1, L(pl[1] + 1, 4, pl[2] - 1), if i == 2 then rgb(255, 224, 90) else rgb(255, 130, 190), { CanCollide = false })
	end
	disc("PlazaFloor", 2, 56, 0, 0.08, 44, COL.Cream)
	disc("PlazaRing", 0.1, 50, 0, 0.16, 44, rgb(196, 184, 232), { CanCollide = false })
	disc("PlazaInner", 0.1, 46.5, 0, 0.24, 44, COL.Cream, { CanCollide = false })
	disc("ParkLawn", 2, 50, 50, 0.05, 84, COL.ParkLawn, { Material = grass })
	disc("YardFloor", 2, 50, -52, 0.1, 110, COL.Asphalt)
	-- the Rift: a plateau 6 studs up (its sides are the cliff)
	disc("RiftPlateau", 8, 54, 34, 6, 154, COL.Cliff, { Material = Enum.Material.Rock })
	disc("RiftFloor", 0.3, 51, 34, 6.12, 154, COL.Ash)
	-- the floating island's underside
	egg("Underside", 92, 26, 80, L(0, -15, 30), COL.Under, { CanCollide = false })
	egg("Underside", 100, 30, 92, L(-22, -17, 100), COL.Under, { CanCollide = false })
	egg("Underside", 80, 26, 80, L(42, -15, 92), COL.Under, { CanCollide = false })
	egg("Underside", 70, 24, 70, L(32, -14, 154), COL.Under, { CanCollide = false })
	-- a few rocks along the rim (soft, half buried)
	for _, r in {
		{ -19.7, -11.2, 5, 0.3 }, { -7.2, -23.7, 4, 1.1 }, { 7.2, -23.7, 4.5, 2 }, { 19.7, -11.2, 4, 0.6 },
		{ 39.5, -7.2, 4, 1.7 }, { 55, 41, 5, 0.2 }, { 72, 78, 4.5, 2.4 }, { 69.9, 95.5, 4, 0.9 },
		{ -60, 87, 5, 1.3 }, { -58, 60, 4, 2.8 },
	} do
		egg("RimRock", r[3] * 1.3, r[3] * 0.7, r[3], L(r[1], 0.4, r[2]) * ang(0, r[4], 0.08), COL.Rock)
	end
	-- the sea of clouds far below
	for _, c in { { 0, -46, 80, 150, 110 }, { 130, -52, 40, 120, 90 }, { -140, -50, 120, 130, 100 }, { 60, -56, 250, 160, 110 }, { -70, -44, -40, 110, 80 } } do
		egg("CloudSea", c[4], 14, c[5], L(c[1], c[2], c[3]), rgb(250, 246, 255), { CanCollide = false, Transparency = 0.25 })
	end
end

---------------------------------------------------------------------------
-- the spawn: the hub stage (the hub camera frames your hero on it), the camp, the map board
---------------------------------------------------------------------------
local function stage(lobby: Instance, s: Vector3)
	folder("HubStage", lobby)
	local sx, sz = s.X, s.Z
	disc("StageRug", 0.06, 26, sx, 0.28, sz + 3, rgb(58, 50, 104), { CanCollide = false })
	disc("PedestalBase", 0.3, 10, sx, 0.34, sz, rgb(76, 66, 132))
	disc("Pedestal", 0.5, 7.6, sx, 0.69, sz, rgb(112, 100, 178))
	local top = disc("PedestalTop", 0.08, 7.84, sx, 0.64, sz, rgb(255, 150, 210), { Material = NEON, Transparency = 0.1, CanCollide = false })
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "StageSparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Rate = 3
	sparkles.Lifetime = NumberRange.new(2.5, 3.5)
	sparkles.Speed = NumberRange.new(0.6, 1.2)
	sparkles.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis points up
	sparkles.SpreadAngle = Vector2.new(15, 15)
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.22), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	sparkles.LightEmission = 1
	sparkles.Color = ColorSequence.new(rgb(255, 170, 220), rgb(255, 214, 120))
	sparkles.Parent = top
	-- lights: a warm key light from the camera side, a cool rim light behind the hero
	local key = box("KeyLight", 0.5, 0.5, 0.5, L(sx + 5, 9, sz - 8), rgb(255, 255, 255), { Transparency = 1, CanCollide = false })
	light(key, 26, 1.1, rgb(255, 236, 214))
	local rim = box("RimLight", 0.5, 0.5, 0.5, L(sx - 1, 6, sz + 5), rgb(255, 255, 255), { Transparency = 1, CanCollide = false })
	light(rim, 14, 2.2, rgb(176, 128, 255))
end

local function spawnArea(lobby: Instance)
	-- the welcome sign by the road (just outside the hub picture: you meet it when you walk)
	folder("Welcome", lobby)
	local wcf = L(-30, 0, 12) * ang(0, -0.35, 0)
	for _, side in { -1, 1 } do
		rod("WelcomePost", 7.4, 0.6, wcf * CFrame.new(side * 5.2, 3.7, 0.2), COL.Wood)
	end
	local welcome = box("WelcomeBoard", 12, 4.2, 0.4, wcf * CFrame.new(0, 5.4, 0), COL.Paper)
	sign(welcome, Enum.NormalId.Front, { Title = "WELCOME TO 67 LAND", Sub = "POPULATION: 67 (APPROX.)", Color = rgb(96, 64, 196), SubColor = rgb(90, 80, 120), Split = 0.58 })
	box("WelcomeTrim", 12.6, 4.8, 0.3, wcf * CFrame.new(0, 5.4, 0.2), COL.Trim)
	ball("WelcomeStar", 1.2, wcf * CFrame.new(5.6, 7.7, -0.1), COL.Gold, { Material = METAL, CanCollide = false })

	-- YOU ARE HERE: the whole island drawn on a board (true to the layout, north is up)
	folder("MapBoard", lobby)
	local bx, by, bz = 20, 5.4, -16
	local board = box("MapBoard", 10, 7.2, 0.4, L(bx, by, bz), COL.Paper)
	box("MapFrame", 10.8, 8, 0.3, L(bx, by, bz + 0.25), COL.Trim)
	for _, side in { -1, 1 } do
		rod("MapLeg", 2.2, 0.4, L(bx + side * 4, 1.1, bz + 0.2), COL.Trim)
	end
	-- world -> board: x keeps its sign (seen from the south, +X is on the left), z goes up
	local function onBoard(wx: number, wz: number): (number, number)
		return bx + wx * 0.045, by - 3.1 + (wz + 30) * 0.0232
	end
	local zones = {
		{ "Spawn", 0, -4, 46, COL.Terrace },
		{ "Plaza", 0, 44, 56, COL.Cream },
		{ "Park", 50, 84, 50, COL.ParkLawn },
		{ "Yard", -52, 110, 50, COL.Asphalt },
		{ "Rift", 34, 154, 54, rgb(236, 84, 72) },
		{ "Summit", -48, 198, 36, COL.Gold },
	}
	for _, z in zones do
		local mx, my = onBoard(z[2], z[3])
		egg("Map" .. z[1], z[4] * 0.045, z[4] * 0.0232 + 0.25, 0.12, L(mx, my, bz - 0.22), z[5], { CanCollide = false })
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "MapText"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	gui.Parent = board
	local function text(t: string, wx: number, wz: number, w: number, color: Color3, font: Enum.Font?)
		local mx, my = onBoard(wx, wz)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		-- the SurfaceGui's x runs from the board's left edge as seen from the front
		label.Position = UDim2.new(0.5 - (mx - bx) / 10, 0, 0.5 - (my - by) / 7.2, 0)
		label.Size = UDim2.new(w, 0, 0.09, 0)
		label.Text = t
		label.TextScaled = true
		label.Font = font or Enum.Font.LuckiestGuy
		label.TextColor3 = color
		label.Parent = gui
	end
	local ink = rgb(52, 40, 90)
	text("67 LAND", 0, 226, 0.34, rgb(96, 64, 196))
	text("YOU ARE HERE", 0, -32, 0.4, rgb(220, 40, 90))
	text("PLAZA", 0, 44, 0.2, ink)
	text("PARK  I II", 50, 64, 0.26, ink)
	text("HORDE YARD  III IV", -52, 132, 0.38, ink)
	text("RIFT  V VI", 34, 128, 0.24, ink)
	text("THE 67", -48, 222, 0.2, ink)
	text("(not to scale. or is it?)", -46, 186, 0.36, rgb(120, 110, 150), Enum.Font.BuilderSansBold)
	local starX, starY = onBoard(0, -4)
	ball("MapStar", 0.5, L(starX, starY, bz - 0.3), rgb(220, 40, 90), { Material = NEON, CanCollide = false })

	-- QUICK PLAY: a round portal on the right of the spawn (your selected difficulty)
	folder("QuickPlay", lobby)
	local qp = facing(-22, 0, 0, -18, -40)
	box("QuickPlayBase", 8, 0.6, 3.4, qp * CFrame.new(0, 0.3, 0), COL.Trim)
	plate("QuickPlayRim", 1.2, 12, qp * CFrame.new(0, 7.2, 0), rgb(84, 72, 150))
	local field = plate("PlayPortal", 1.4, 10.4, qp * CFrame.new(0, 7.2, 0), rgb(255, 110, 200), {
		Material = Enum.Material.ForceField,
		Transparency = 0.1,
		CanCollide = false,
		CanTouch = true,
		Attributes = { PlayPortal = true },
	})
	light(field, 18, 1.4, rgb(255, 130, 210))
	local qsign = box("QuickPlaySign", 10, 2.2, 0.5, qp * CFrame.new(0, 14.3, 0), COL.Ink)
	sign(qsign, Enum.NormalId.Front, { Title = "QUICK PLAY", Glow = true })
	local qsub = box("QuickPlayPlate", 8.4, 1, 0.3, qp * CFrame.new(0, 12.6, -0.2), COL.Ink, { CanCollide = false })
	sign(qsub, Enum.NormalId.Front, { Title = "YOUR DIFFICULTY · ANY HERO", Color = rgb(236, 232, 250), Glow = true })
	-- TODAY IN 67 LAND: the limited-time events (the client writes them in)
	local ev = facing(-20, 0, -12, -16, -60)
	local eventBoard = box("EventBoard", 12, 6.4, 0.5, ev * CFrame.new(0, 5.6, 0), COL.Ink, { Attributes = { EventBoard = true } })
	box("EventBoardGlow", 12.8, 7.2, 0.3, ev * CFrame.new(0, 5.6, 0.25), COL.GlowGold, { Material = NEON })
	for _, side in { -1, 1 } do
		rod("EventBoardLeg", 2.4, 0.5, ev * CFrame.new(side * 4.5, 1.2, 0.1), COL.Trim)
	end
	local evGui = sign(eventBoard, Enum.NormalId.Front, { Title = "TODAY IN 67 LAND", Sub = "NO EVENTS TODAY\nSuspicious. Very suspicious.", Glow = true, Split = 0.3 })
	evGui.Name = "EventBoardGui"

	-- the AFK CAMP (step on the ground ring to open it)
	folder("AfkCamp", lobby)
	local cx, cz = 33, 4
	disc("CampGround", 0.3, 18, cx, 0.16, cz, rgb(132, 104, 80), { Material = Enum.Material.Ground })
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3
		box("Log", 4.5, 1, 1, L(cx, 0.7, cz) * ang(0, a, 0.25), rgb(110, 70, 40))
	end
	local fire = ball("Campfire", 2.4, L(cx, 2, cz), rgb(255, 150, 40), { Material = NEON, CanCollide = false })
	bob(fire, 0.25, 0, 3)
	light(fire, 22, 2, rgb(255, 170, 80))
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3 + math.pi / 3
		box("CampBench", 5, 1.2, 1.6, L(cx + math.cos(a) * 7.5, 0.6, cz + math.sin(a) * 7.5) * ang(0, -a + math.pi / 2, 0), rgb(130, 90, 55))
	end
	-- a tent (somebody is sleeping in it)
	local tent = egg("Tent", 8, 5.4, 7, L(cx + 7, 1.5, cz + 7) * ang(0, 0.6, 0), rgb(236, 104, 84))
	egg("TentDoor", 2.6, 3.2, 1, L(cx + 5.6, 1.6, cz + 4.6) * ang(0, 0.6, 0), rgb(70, 40, 60), { CanCollide = false })
	billboard(tent, "Snore", 3, 1.6, { { "z z z", 1, rgb(236, 232, 250) } }, 60).StudsOffset = Vector3.new(-1.5, 3.6, -1.5)
	local campSign = signboard("CampSign", 9, 3, L(cx - 6, 5.4, cz - 8), { Title = "AFK CAMP", Sub = "HEROES RESTING. DO NOT POKE.", Bg = COL.Ink, Glow = true }, 3.9)
	campSign.CanCollide = false
	disc("AfkCampPad", 0.3, 20, cx, 0.35, cz, rgb(255, 170, 80), { Transparency = 1, CanCollide = false, Attributes = { AfkCamp = true } })
end

---------------------------------------------------------------------------
-- the plaza: THE GREAT BALANCE, the events board, the signpost, the hall of survivors
---------------------------------------------------------------------------
local function greatBalance(lobby: Instance)
	local model = Instance.new("Model")
	model.Name = "GreatBalance"
	model.Parent = lobby
	current = model
	local cx, cz = 0, 44
	-- a round pool with a few wishes in it
	disc("PoolRim", 1, 20, cx, 1, cz, rgb(150, 136, 206))
	disc("PoolWater", 0.4, 18, cx, 0.95, cz, rgb(120, 200, 255), { Material = GLASS, Transparency = 0.3, CanCollide = false })
	for i, c in { { 5.5, 2 }, { -4, 5.8 }, { 1.5, -6.2 } } do
		disc("WishCoin", 0.1, 0.9, cx + c[1], 0.8, cz + c[2], COL.Gold, { Material = METAL, CanCollide = false, Orientation = Vector3.new(0, i * 30, 90) })
	end
	local pedestal = disc("Pedestal", 4, 9, cx, 4.5, cz, rgb(132, 118, 196))
	disc("PedestalCap", 0.6, 10.2, cx, 5.1, cz, COL.Cream)
	local plaque = box("Plaque", 6.4, 1.5, 0.3, L(cx, 2.9, cz - 4.6), COL.Ink, { CanCollide = false })
	sign(plaque, Enum.NormalId.Front, { Title = "THE GREAT BALANCE", Sub = "nobody knows which is heavier", Glow = true })
	pedestal:SetAttribute("Monument", "GreatBalance")
	-- two big cartoon gloves, palms up, weighing a 6 against a 7 (they bob in turn, like the
	-- meme): a purple sleeve, a gold cuff, a white glove with four fingers and a thumb. The
	-- palms tip towards you so the fingers read from the ground.
	local glove, sleeve = rgb(248, 246, 252), rgb(118, 84, 200)
	for _, side in { 1, -1 } do
		local digit = if side > 0 then "6" else "7"
		local phase = if side > 0 then 0 else math.pi
		local base = L(cx + side * 2.4, 5.1, cz) * ang(0, 0, -side * 0.28) -- the arm leans outwards
		local wrist = (base * CFrame.new(0, 7.2, 0)).Position
		local palm = CFrame.new(wrist + Vector3.new(side * 1.2, 1.4, -0.5)) * ang(-0.3, 0, -side * 0.1)
		local parts = {
			egg("Sleeve" .. digit, 3.6, 7.6, 3.6, base * CFrame.new(0, 3.4, 0), sleeve),
			rod("Cuff" .. digit, 1.4, 4.2, base * CFrame.new(0, 7, 0), COL.Gold, { Material = METAL }),
			egg("Palm" .. digit, 5.8, 2.6, 5.4, palm, glove),
			egg("Thumb" .. digit, 1.7, 1.7, 3.4, CFrame.new(wrist + Vector3.new(-side * 1.9, 2.8, -1.4)) * ang(0.85, 0, side * 0.45), glove),
		}
		-- four fingers across the front edge of the palm, tips curling up
		for f, x in { -1.95, -0.65, 0.65, 1.95 } do
			local long = if f == 2 or f == 3 then 3.8 else 3.3
			table.insert(parts, egg("Finger" .. digit, 1.4, 1.4, long, palm * CFrame.new(x, 0.35, -2.6 - long * 0.2) * ang(0.4, 0, 0), glove))
		end
		local orb = ball("Glow" .. digit, 1.8, palm * CFrame.new(0, 1.9, 0.4), COL.GlowGold, { Material = NEON, CanCollide = false })
		table.insert(parts, orb)
		light(orb, 16, 1.2, rgb(255, 214, 120))
		local label = billboard(orb, "Digit", 7, 7, { { digit, 1, COL.Text } }, 400)
		label.StudsOffset = Vector3.new(0, 4.2, 0)
		for _, p in parts do
			bob(p, 0.55, phase, 1.4)
		end
	end
end

local function plazaBoards(lobby: Instance)
	folder("Plaza", lobby)
	-- benches facing the monument, two round planters
	for _, b in { { 17, 50 }, { -17, 50 } } do
		local cf = facing(b[1], 0, b[2], 0, 44)
		box("PlazaBench", 6, 0.5, 1.8, cf * CFrame.new(0, 1.4, 0), COL.Wood)
		box("PlazaBenchBack", 6, 1.5, 0.4, cf * CFrame.new(0, 2.3, 0.8), COL.Wood)
	end
	for i, pl in { { 20, 34 }, { -20, 34 } } do
		disc("PlazaPlanter", 1.4, 5.4, pl[1], 1.5, pl[2], rgb(150, 136, 206))
		egg("PlazaBush", 5.2, 3, 5.2, L(pl[1], 2.6, pl[2]), COL.Hedge, { CanCollide = false })
		ball("PlazaFlower", 1.1, L(pl[1] - i + 1.5, 4.1, pl[2] - 1.2), if i == 1 then rgb(255, 130, 190) else rgb(255, 224, 90), { CanCollide = false })
	end

	-- the signpost (arrows are screen directions: the camera always looks north)
	local post = L(17, 0, 63)
	rod("SignPost", 11, 0.7, post * CFrame.new(0, 5.5, 0), COL.Wood)
	ball("SignPostTop", 1.1, post * CFrame.new(0, 11.2, 0), COL.Gold, { Material = METAL, CanCollide = false })
	for i, s in {
		{ "< THE PARK", -1, 0.05 },
		{ "HORDE YARD >", 1, -0.04 },
		{ "^ THE RIFT", -1, 0.03 },
		{ "^^ THE 67 (TRUST ME)", 1, -0.06 },
		{ "v NOWHERE", -1, 0.22 },
	} do
		local y = 10.2 - (i - 1) * 1.55
		local arrow = box("SignArrow", 7.6, 1.25, 0.3, post * CFrame.new(s[2] * 3.2, y, -0.45) * ang(0, 0, s[3]), COL.Paper, { CanCollide = false })
		sign(arrow, Enum.NormalId.Front, { Title = s[1] :: string, Color = rgb(52, 40, 90) })
	end

	-- HALL OF SURVIVORS: the lobby leaderboard (LeaderboardManager writes on its front)
	local hall = facing(-46, 0, 30, -30, -14)
	box("LeaderboardBoard", 15, 10, 0.6, hall * CFrame.new(0, 7.6, 0), rgb(30, 25, 50), { Attributes = { Leaderboard = "BestTime" } })
	box("HallFrame", 15.8, 10.8, 0.4, hall * CFrame.new(0, 7.6, 0.3), COL.Gold, { Material = METAL })
	local header = box("HallHeader", 15, 2, 0.6, hall * CFrame.new(0, 13.9, 0), COL.Ink)
	sign(header, Enum.NormalId.Front, { Title = "HALL OF SURVIVORS", Glow = true })
	for _, side in { -1, 1 } do
		rod("HallLeg", 2.8, 0.7, hall * CFrame.new(side * 6, 1.4, 0.2), COL.Trim)
	end
	rod("TrophyBase", 0.8, 1.8, hall * CFrame.new(0, 15.3, 0), COL.Gold, { Material = METAL })
	egg("Trophy", 2.4, 2.6, 2.4, hall * CFrame.new(0, 16.9, 0), COL.Gold, { Material = METAL })
end

-- stepping stones and lamps: the route (cream stones, warm lamps)
local function route(lobby: Instance)
	folder("Route", lobby)
	for _, s in {
		{ 24, 62 }, { 31, 67 }, { 37, 72 }, -- plaza -> park
		{ 26, 94 }, { 13, 99 }, { 0, 102 }, { -13, 105 }, { -26, 107 }, -- park -> yard
		{ -21, 120 }, { -12, 128 }, -- yard -> the stairs of the Rift
	} do
		disc("Stone", 0.3, 4.4, s[1], 0.18, s[2], COL.Cream)
	end
	-- the stairs up to the Rift (6 steps of 1 stud)
	local edge = Vector3.new(10, 0, 141.7)
	local dir = Vector3.new(0.93, 0, 0.37).Unit
	for k = 1, 6 do
		local c = edge - dir * (2.5 * (6.5 - k))
		local cf = CFrame.lookAt(ORIGIN + c + Vector3.new(0, k / 2 - 0.5, 0), ORIGIN + c + dir + Vector3.new(0, k / 2 - 0.5, 0))
		box("RiftStep", 8, k + 1, 2.7, cf, if k % 2 == 0 then COL.Cliff else rgb(98, 86, 132), { Material = Enum.Material.Rock })
	end
	-- lamps along the way
	for i, l in { { 26, 56 }, { 20, 98 }, { -20, 102 }, { -12, 134 }, { 12, 164, 6 } } do
		local y0 = l[3] or 0
		rod("LampPost", 7, 0.5, L(l[1], y0 + 3.5, l[2]), rgb(60, 52, 92))
		local bulb = ball("LampBulb", 1.3, L(l[1], y0 + 7.4, l[2]), rgb(255, 224, 170), { Material = NEON, CanCollide = false })
		if i % 2 == 1 then
			light(bulb, 16, 1.2, rgb(255, 220, 170))
		end
	end
end

---------------------------------------------------------------------------
-- event gates: one per difficulty tier, styled by its zone
---------------------------------------------------------------------------
export type GateStyle = "Park" | "Yard" | "Rift"

local function gate(index: number, cf: CFrame, style: GateStyle)
	local tier = DifficultyData.Get(index)
	local model = Instance.new("Model")
	model.Name = "Gate" .. tier.Key
	model.Parent = current
	local parent = current
	current = model
	local tag = { GateFrame = index }
	rod("GateStep", 0.4, 13, cf * CFrame.new(0, 0.2, 0), tier.Color:Lerp(rgb(40, 34, 60), 0.55))
	local portal = box("Portal", 8.4, 11, 0.5, cf * CFrame.new(0, 6.1, 0), tier.Color, {
		Material = NEON,
		Transparency = 0.35,
		CanCollide = false,
		CanTouch = true,
		Attributes = { EventGate = index },
	})
	light(portal, 14, 1, tier.Color)
	-- the lock (shown by the client while the gate is closed for you)
	local lock = box("Lock", 2.6, 2.2, 0.9, cf * CFrame.new(0, 5.8, -0.9), rgb(64, 60, 80), { Material = METAL, CanCollide = false, Attributes = { GateLock = index } })
	egg("Shackle", 1.9, 1.9, 0.4, cf * CFrame.new(0, 7.1, -0.85), rgb(64, 60, 80), { Material = METAL, CanCollide = false, Attributes = { GateLock = index } })
	sign(lock, Enum.NormalId.Front, { Title = tier.Numeral, Color = rgb(236, 232, 250), Glow = true })
	-- the label (three lines, written by the client for each player)
	local marker = box("GateMarker", 1, 1, 1, cf * CFrame.new(0, 15.6, 0), rgb(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false, Attributes = { GateMarker = index } })
	billboard(marker, "GateLabel", 14, 5, {
		{ tier.Numeral .. "  " .. tier.Name, 0.46, tier.Color },
		{ "LOCKED", 0.3, rgb(236, 232, 250) },
		{ if tier.Unlock then tier.Unlock.Text else "", 0.24, rgb(200, 194, 226) },
	}, 95)
	if style == "Park" then
		-- a garden arch: hedge pillars, a hedge top with flowers, a wooden plaque
		for _, side in { -1, 1 } do
			egg("Hedge", 2.8, 12.4, 2.8, cf * CFrame.new(side * 5.6, 6.2, 0), COL.Hedge, { Attributes = tag })
		end
		egg("HedgeTop", 15, 3.6, 3, cf * CFrame.new(0, 12.6, 0), COL.Hedge, { Attributes = tag })
		for k, f in { { -3.2, 14.1, rgb(255, 130, 190) }, { 0.6, 14.4, rgb(255, 224, 90) }, { 4.1, 13.9, rgb(255, 255, 255) } } do
			ball("Flower", 1.1, cf * CFrame.new(f[1], f[2], -1 - k * 0.1), f[3], { CanCollide = false })
		end
		local plaque = box("Plaque", 4, 1.7, 0.3, cf * CFrame.new(0, 10.1, -1.55), COL.Wood, { CanCollide = false })
		sign(plaque, Enum.NormalId.Front, { Title = tier.Numeral, Color = COL.Paper })
	elseif style == "Yard" then
		-- a steel frame with caution bands and a warning light
		for _, side in { -1, 1 } do
			box("Pillar", 2.4, 12, 2.4, cf * CFrame.new(side * 5.6, 6, 0), rgb(110, 112, 128), { Material = METAL, Attributes = tag })
			box("Caution", 2.6, 1.4, 2.6, cf * CFrame.new(side * 5.6, 9, 0), rgb(240, 200, 60), { CanCollide = false })
		end
		local top = box("Beam", 15, 2.4, 2.8, cf * CFrame.new(0, 12.4, 0), rgb(70, 72, 86), { Material = METAL, Attributes = tag })
		sign(top, Enum.NormalId.Front, { Title = tier.Numeral, Color = rgb(240, 200, 60) })
		ball("WarningLight", 1.3, cf * CFrame.new(0, 14.2, 0), rgb(255, 140, 40), { Material = NEON, CanCollide = false })
	else
		-- raw rock with glowing cracks
		for _, side in { -1, 1 } do
			egg("Rock", 3.2, 13, 3.2, cf * CFrame.new(side * 5.9, 6.4, 0) * ang(0, 0, side * 0.06), rgb(66, 56, 86), { Material = Enum.Material.Rock, Attributes = tag })
			box("Crack", 0.4, 8.6, 0.2, cf * CFrame.new(side * 5.9, 6.2, -1.52) * ang(0, 0, side * 0.12), tier.Color, { Material = NEON, CanCollide = false })
		end
		egg("RockTop", 16.5, 3.6, 3.6, cf * CFrame.new(0, 12.8, 0), rgb(66, 56, 86), { Material = Enum.Material.Rock, Attributes = tag })
		local plaque = box("Plaque", 4, 1.7, 0.3, cf * CFrame.new(0, 10.3, -1.7), rgb(40, 32, 56), { CanCollide = false })
		sign(plaque, Enum.NormalId.Front, { Title = tier.Numeral, Color = tier.Color, Glow = true })
	end
	current = parent
end

---------------------------------------------------------------------------
-- zone 1: THE PARK (I CALM, II HUNT) - soft, green, safe
---------------------------------------------------------------------------
local function tree(x: number, y: number, z: number, s: number)
	rod("Trunk", 6 * s, 1.6 * s, L(x, y + 3 * s, z), rgb(126, 88, 60))
	egg("Crown", 9 * s, 7.6 * s, 9 * s, L(x, y + 8 * s, z), rgb(88, 176, 104), { CanCollide = false, CastShadow = true })
	egg("CrownTop", 5.6 * s, 4.8 * s, 5.6 * s, L(x + 1.2 * s, y + 11 * s, z - 0.8 * s), rgb(116, 200, 118), { CanCollide = false })
end

local function park(lobby: Instance)
	folder("ThePark", lobby)
	gate(1, L(60, 0.05, 98), "Park")
	gate(2, L(38, 0.05, 98), "Park")
	for _, t in { { 74, 88, 1.1 }, { 27, 78, 0.9 }, { 49, 108, 1.2 }, { 28, 106, 1 }, { 68, 100, 0.95 } } do
		tree(t[1], 0.05, t[2], t[3])
	end
	-- the pond, with its lifeguard
	disc("PondRim", 0.5, 13, 63, 0.4, 72, rgb(200, 192, 222))
	disc("Pond", 0.4, 11.4, 63, 0.45, 72, rgb(110, 196, 255), { Material = GLASS, Transparency = 0.25, CanCollide = false })
	egg("DuckBody", 2.4, 1.7, 3, L(62, 0.9, 71), rgb(255, 214, 60), { CanCollide = false })
	ball("DuckHead", 1.5, L(62, 2.1, 70), rgb(255, 220, 70), { CanCollide = false })
	box("DuckBeak", 0.8, 0.35, 0.7, L(62, 2, 69.1), rgb(255, 140, 40), { CanCollide = false })
	signboard("PondSign", 4.6, 1.5, L(68, 2.8, 67.5), { Title = "LIFEGUARD ON DUTY", Color = rgb(52, 40, 90) }, 2)
	-- a practice dummy
	rod("DummyPost", 3, 0.6, L(35, 1.5, 82), COL.Wood)
	egg("DummyBody", 2.8, 3.2, 2.4, L(35, 4.2, 82), rgb(232, 206, 146))
	ball("DummyHead", 1.9, L(35, 6.6, 82), rgb(232, 206, 146), { CanCollide = false })
	plate("Target", 0.2, 2, L(35, 4.3, 80.75), rgb(230, 70, 80), { CanCollide = false })
	plate("TargetRing", 0.24, 1.2, L(35, 4.3, 80.7), rgb(255, 255, 255), { CanCollide = false })
	plate("TargetDot", 0.28, 0.5, L(35, 4.3, 80.66), rgb(230, 70, 80), { CanCollide = false })
	signboard("DummySign", 5.6, 1.9, L(29.5, 2.6, 80), { Title = "PRACTICE HORDE (1)", Sub = "please be gentle", Color = rgb(52, 40, 90), SubColor = rgb(90, 80, 120) }, 1.7)
	-- a bench and a few round bushes along the back
	box("BenchSeat", 5.4, 0.5, 1.6, L(46, 1.4, 70), COL.Wood)
	box("BenchBack", 5.4, 1.4, 0.4, L(46, 2.3, 70.8), COL.Wood)
	for _, b in { { 36, 108 }, { 56, 107 }, { 72, 92 }, { 22, 96 } } do
		egg("Bush", 5.2, 3.2, 4.4, L(b[1], 1.1, b[2]), COL.Hedge, { CanCollide = false })
	end
	-- the EMERGENCY EXIT: a door at the cliff's edge (behind it: the sky)
	local exit = L(62, 0.05, 64)
	for _, side in { -1, 1 } do
		box("ExitPost", 0.6, 8, 0.6, exit * CFrame.new(side * 2.3, 4, 0), rgb(236, 236, 240))
	end
	box("ExitTop", 5.2, 0.6, 0.6, exit * CFrame.new(0, 8.2, 0), rgb(236, 236, 240))
	local exitSign = box("ExitSign", 4.2, 1.1, 0.3, exit * CFrame.new(0, 9.2, -0.1), rgb(40, 170, 90), { CanCollide = false })
	sign(exitSign, Enum.NormalId.Front, { Title = "EMERGENCY EXIT", Color = rgb(255, 255, 255), Glow = true })
	sign(exitSign, Enum.NormalId.Back, { Title = "EMERGENCY EXIT", Color = rgb(255, 255, 255), Glow = true })
	-- the grass nobody touches (secret), hidden behind the bushes
	local grass = box("Grass", 5, 1, 5, L(63, 0.45, 104.5), rgb(70, 190, 80), { Material = Enum.Material.Grass })
	grass:SetAttribute("SecretRegion", "TouchGrass")
	signboard("GrassSign", 4, 1.6, L(63, 3, 101.4), { Title = "DO NOT TOUCH", Color = rgb(40, 40, 40) }, 1.4)
end

---------------------------------------------------------------------------
-- zone 2: THE HORDE YARD (III HORDE, IV NIGHTMARE) - fenced, industrial, tense
---------------------------------------------------------------------------
local function yard(lobby: Instance)
	folder("HordeYard", lobby)
	local yx, yz = -52, 110
	gate(3, L(-40, 0.1, 124), "Yard")
	gate(4, L(-64, 0.1, 124), "Yard")
	-- a chain-link fence around the back of the yard (behind the gates)
	local fence = {}
	for _, deg in { 160, 125, 90, 55, 20 } do
		local a = math.rad(deg)
		table.insert(fence, Vector3.new(yx + math.cos(a) * 23.5, 0, yz + math.sin(a) * 23.5))
	end
	for i, f in fence do
		rod("FencePost", 7, 0.5, L(f.X, 3.5, f.Z), rgb(150, 152, 168), { Material = METAL })
		local nextPost = fence[i + 1]
		if nextPost then
			local mid = (f + nextPost) / 2
			local cf = CFrame.lookAt(ORIGIN + mid + Vector3.new(0, 3.2, 0), ORIGIN + nextPost + Vector3.new(0, 3.2, 0)) * ang(0, math.rad(90), 0)
			box("FencePanel", (nextPost - f).Magnitude, 6, 0.12, cf, rgb(186, 188, 204), { Material = METAL, Transparency = 0.55 })
		end
	end
	-- caution stripes at the way in
	for k = 0, 2 do
		box("CautionStripe", 1.4, 0.06, 9, L(-29 - k * 2.8, 0.14, 111) * ang(0, 0.5, 0), if k % 2 == 0 then rgb(240, 200, 60) else rgb(40, 38, 50), { CanCollide = false })
	end
	-- crates (one of them is very clearly labelled)
	box("Crate", 3.6, 3.6, 3.6, L(-31, 1.9, 101) * ang(0, 0.1, 0), rgb(176, 130, 82))
	box("Crate", 3.6, 3.6, 3.6, L(-27.2, 1.9, 100.4) * ang(0, -0.06, 0), rgb(168, 124, 78))
	local fragile = box("Crate", 3.6, 3.6, 3.6, L(-29, 5.5, 100.8) * ang(0, 0.18, 0), rgb(182, 136, 88))
	sign(fragile, Enum.NormalId.Front, { Title = "FRAGILE", Sub = "CONTAINS HORDE", Color = rgb(200, 40, 50), SubColor = rgb(60, 40, 30), Split = 0.55 })
	box("Crate", 3.2, 3.2, 3.2, L(-34.5, 1.7, 104.5) * ang(0, 0.4, 0), rgb(160, 118, 74))
	-- traffic cones
	for _, c in { { -40, 98 }, { -43, 95.5 }, { -46, 99 } } do
		box("ConeBase", 1.8, 0.3, 1.8, L(c[1], 0.25, c[2]), rgb(255, 120, 40))
		egg("Cone", 1.4, 2.6, 1.4, L(c[1], 1.4, c[2]), rgb(255, 120, 40), { CanCollide = false })
	end
	-- a floodlight on the gates
	rod("FloodPole", 16, 0.8, L(-36, 8, 106), rgb(90, 92, 108), { Material = METAL })
	local head = CFrame.lookAt(ORIGIN + Vector3.new(-36.4, 15.8, 106.6), ORIGIN + Vector3.new(-52, 5, 124))
	box("FloodLight", 3.2, 2, 1.6, head, rgb(70, 72, 86), { Material = METAL })
	local lamp = box("FloodGlow", 2.8, 1.6, 0.2, head * CFrame.new(0, 0, -0.85), rgb(255, 250, 220), { Material = NEON, CanCollide = false })
	light(lamp, 30, 1.2, rgb(255, 246, 220))
	-- HORDE COUNTER
	local counter = signboard("HordeCounter", 8.4, 4.4, L(-62, 5.2, 92), {
		Title = "HORDE DEFEATED",
		Sub = "6,700,067\nTODAY: 67",
		Bg = rgb(20, 18, 28),
		Color = rgb(255, 80, 80),
		SubColor = rgb(255, 120, 110),
		SubFont = Enum.Font.Code,
		Glow = true,
		Split = 0.35,
	}, 3)
	counter.CanCollide = true
	-- a vending machine that is out of the one thing you need
	local vend = box("Vending", 4, 7, 3, L(-70, 3.6, 98) * ang(0, 0.5, 0), rgb(200, 44, 60))
	local panel = box("VendingPanel", 3, 3.8, 0.2, vend.CFrame * CFrame.new(0, 0.9, -1.55), rgb(210, 236, 255), { Material = NEON, CanCollide = false })
	sign(panel, Enum.NormalId.Front, { Title = "COURAGE", Sub = "SOLD OUT", Color = rgb(40, 60, 120), SubColor = rgb(220, 40, 60), Split = 0.55 })
	-- DO NOT PRESS (a prompt: the server counts the presses)
	rod("ButtonPedestal", 3, 2.4, L(-54, 1.6, 96), rgb(96, 98, 114), { Material = METAL })
	local button = disc("Button67", 0.6, 1.9, -54, 3.4, 96, rgb(240, 40, 60), { Material = NEON, Attributes = { Button67 = true } })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Press"
	prompt.ActionText = "Press"
	prompt.ObjectText = "DO NOT PRESS"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = button
	local label = box("ButtonLabel", 2.3, 0.8, 0.1, L(-54, 2.2, 94.78), rgb(240, 200, 60), { CanCollide = false })
	sign(label, Enum.NormalId.Front, { Title = "DO NOT PRESS", Bg = rgb(240, 200, 60), Color = rgb(40, 30, 20) })
	-- THE STAIRS TO NOWHERE (secret): steps off the west edge of the yard, into the sky
	for k = 1, 7 do
		box("NowhereStep", 2.4, 0.6, 3.4, L(-74 - 2.3 * k, 2.2 * k, 110), rgb(120, 122, 138), { Material = Enum.Material.DiamondPlate })
	end
	box("NowherePlatform", 5, 0.6, 5, L(-93.6, 17.2, 110), rgb(120, 122, 138), { Material = Enum.Material.DiamondPlate })
	box("NowhereChair", 1.6, 0.4, 1.6, L(-94.4, 18.6, 111), rgb(210, 70, 80))
	box("NowhereChairBack", 1.6, 1.8, 0.3, L(-94.4, 19.4, 111.8), rgb(210, 70, 80))
	signboard("NowhereSign", 5.2, 2, L(-92.4, 19.9, 112), { Title = "YOU MADE IT", Sub = "there is nothing here", Color = rgb(52, 40, 90), SubColor = rgb(90, 80, 120) }, 2.4)
	box("NowhereTrigger", 5, 6, 5, L(-93.6, 20.4, 110), rgb(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false, Attributes = { SecretRegion = "Nowhere" } })
end

---------------------------------------------------------------------------
-- zone 3: THE RIFT (V INFERNO, VI OBLIVION) - raised, dark, cracked, floating rocks
---------------------------------------------------------------------------
local function rift(lobby: Instance)
	folder("TheRift", lobby)
	local y = 6.12
	gate(5, L(48, y, 170), "Rift")
	gate(6, L(26, y, 172), "Rift")
	-- INFERNO side: glowing cracks, embers
	for i, c in { { 52, 150, 0.4, 7 }, { 46, 144, -0.9, 5 }, { 58, 158, 1.3, 6 }, { 42, 156, 2.2, 4 } } do
		local crack = box("LavaCrack", 0.7, 0.08, c[4], L(c[1], y + 0.02, c[2]) * ang(0, c[3], 0), rgb(255, 96, 40), { Material = NEON, CanCollide = false })
		if i == 1 then
			local embers = Instance.new("ParticleEmitter")
			embers.Name = "Embers"
			embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			embers.Rate = 4
			embers.Lifetime = NumberRange.new(1.5, 2.5)
			embers.Speed = NumberRange.new(1.5, 3)
			embers.EmissionDirection = Enum.NormalId.Top
			embers.SpreadAngle = Vector2.new(20, 20)
			embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
			embers.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			embers.LightEmission = 1
			embers.Color = ColorSequence.new(rgb(255, 200, 90), rgb(255, 80, 40))
			embers.Parent = crack
			light(crack, 18, 1.4, rgb(255, 110, 60))
		end
	end
	signboard("LavaSign", 6, 2, L(52, y + 3, 140), { Title = "THE FLOOR IS LAVA", Sub = "(it is)", Color = rgb(200, 50, 40), SubColor = rgb(90, 60, 60) }, 2.6)
	-- OBLIVION side: a hole in the world, shards drifting around it
	disc("VoidRim", 0.1, 9.4, 18, y + 0.03, 150, rgb(172, 96, 240), { Material = NEON, CanCollide = false })
	disc("Void", 0.12, 8.4, 18, y + 0.06, 150, rgb(10, 6, 18), { CanCollide = false })
	for i, s in { { 15, 10.5, 147, 0.4 }, { 21.5, 12, 152, -0.5 }, { 17, 14, 154.5, 0.2 } } do
		local shard = egg("VoidShard", 0.7, 2.2, 0.7, L(s[1], y + s[2] - 6, s[3]) * ang(s[4], 0, s[4] * 0.6), rgb(186, 110, 255), { Material = NEON, CanCollide = false })
		bob(shard, 0.8, i * 2.1, 1.1)
	end
	-- floating rocks around the plateau
	for i, r in { { 62, 14, 146, 5 }, { 6, 16, 160, 4 }, { 44, 20, 186, 6 }, { 60, 11, 170, 3.5 } } do
		local rock = egg("FloatingRock", r[4] * 1.2, r[4] * 0.8, r[4], L(r[1], r[2], r[3]) * ang(0.2 * i, i, 0.1), COL.Cliff, { Material = Enum.Material.Rock, CanCollide = false })
		bob(rock, 0.9, i * 1.3, 0.7)
	end
	-- LOST & FOUND (a box of hero hats)
	box("LostBox", 3, 2, 2.4, L(44, y + 1, 139), rgb(196, 160, 110))
	rod("LostTopHat", 1.2, 1, L(43.2, y + 2.6, 139), rgb(34, 34, 42), { CanCollide = false })
	egg("LostCone", 1, 1.6, 1, L(44.6, y + 2.7, 139.3), rgb(255, 120, 40), { CanCollide = false })
	rod("LostCrown", 0.5, 1, L(44.2, y + 2.2, 138.4), COL.Gold, { Material = METAL, CanCollide = false })
	local lost = box("LostLabel", 2.6, 0.7, 0.1, L(44, y + 1.1, 137.78), rgb(246, 240, 226), { CanCollide = false })
	sign(lost, Enum.NormalId.Front, { Title = "LOST & FOUND", Color = rgb(52, 40, 90) })
	-- a mailbox nobody uses
	rod("MailPost", 3, 0.4, L(16, y + 1.5, 164), COL.Wood)
	egg("Mailbox", 1.6, 1.5, 2.4, L(16, y + 3.4, 164), rgb(120, 70, 180))
	box("MailFlag", 0.15, 1, 0.5, L(16.9, y + 3.8, 164.4), rgb(220, 50, 60), { CanCollide = false })
	signboard("MailSign", 5, 1.5, L(16, y + 1.8, 161.8), { Title = "OBLIVION", Sub = "no mail since 1967", Color = rgb(120, 70, 180), SubColor = rgb(90, 80, 120) }, 0)
	-- a sign someone forgot to finish
	signboard("TodoSign", 5.6, 2.2, L(12, y + 3.2, 146), { Title = "sign_text_FINAL_v2 (1)", Color = rgb(60, 60, 60), Bg = rgb(236, 236, 236) }, 2.6)
end

---------------------------------------------------------------------------
-- THE 67 SUMMIT (VII) - a golden island, a floating bridge, a gate shaped like 67
---------------------------------------------------------------------------
local function summit(lobby: Instance)
	folder("Summit", lobby)
	local sx, sz, top = -48, 198, 14
	disc("SummitFloor", 3, 36, sx, top, sz, COL.Marble)
	disc("SummitTrim", 0.2, 36.6, sx, top - 0.6, sz, COL.Gold, { Material = METAL, CanCollide = false })
	egg("SummitRock", 34, 26, 34, L(sx, -2, sz), COL.Under, { CanCollide = false })
	egg("SummitRock", 9, 14, 9, L(sx + 4, -12, sz - 2), rgb(84, 72, 124), { CanCollide = false })
	-- the floating bridge: stones rising from the Rift to the summit
	local a, b = Vector3.new(10.2, 6, 166.8), Vector3.new(-32.1, top, 189.5)
	local count = 13
	for k = 1, count do
		local t = k / (count + 1)
		local p = a:Lerp(b, t)
		disc("BridgeStone", 1, 5, p.X + math.sin(k * 1.7) * 0.7, 6 + 8 * t, p.Z + math.cos(k * 2.3) * 0.5, if k % 2 == 0 then COL.Marble else rgb(226, 212, 176))
	end
	-- THE 67 GATE: a golden arch under a huge glowing 67 (it faces the route, like every sign)
	local g = L(sx - 2, top, sz + 8)
	local model = Instance.new("Model")
	model.Name = "Gate" .. DifficultyData.Get(7).Key
	model.Parent = current
	local parent = current
	current = model
	local tag = { GateFrame = 7 }
	local gold = { Material = METAL, Attributes = tag }
	box("GatePlinth", 24, 1.2, 8, g * CFrame.new(0, 0.6, 0), COL.Marble)
	for _, side in { -1, 1 } do
		egg("GatePillar", 3.4, 17, 3.4, g * CFrame.new(side * 6.8, 9, 0), COL.Gold, gold)
		ball("GateOrb", 2.2, g * CFrame.new(side * 6.8, 18.2, 0), rgb(255, 120, 190), { Material = NEON, CanCollide = false })
	end
	egg("GateArch", 17, 5.2, 3.4, g * CFrame.new(0, 17.4, 0), COL.Gold, gold)
	local portal = box("Portal", 10.2, 15, 0.6, g * CFrame.new(0, 8.8, 0), DifficultyData.Get(7).Color, {
		Material = NEON,
		Transparency = 0.35,
		CanCollide = false,
		CanTouch = true,
		Attributes = { EventGate = 7 },
	})
	light(portal, 24, 1.6, rgb(255, 210, 90))
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "GoldDust"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Rate = 5
	sparkles.Lifetime = NumberRange.new(2, 3.5)
	sparkles.Speed = NumberRange.new(0.5, 1.4)
	sparkles.SpreadAngle = Vector2.new(60, 60)
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	sparkles.LightEmission = 1
	sparkles.Color = ColorSequence.new(rgb(255, 236, 160), rgb(255, 190, 60))
	sparkles.Parent = portal
	-- the crown: 67, huge, gold on a dark shadow (the island's landmark, seen from the spawn)
	local crown = box("Crown67", 18, 11.5, 0.2, g * CFrame.new(0, 26, 0), rgb(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false })
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Crown" .. face.Name
		gui.Face = face
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 16
		gui.Parent = crown
		for i, layer in { { rgb(70, 30, 110), 0.035 }, { rgb(255, 206, 64), 0 } } do
			local t = Instance.new("TextLabel")
			t.Name = if i == 1 then "Shadow" else "Title"
			t.BackgroundTransparency = 1
			t.Size = UDim2.fromScale(1, 1)
			t.Position = UDim2.fromScale(layer[2], layer[2])
			t.Text = "67"
			t.TextScaled = true
			t.Font = Enum.Font.LuckiestGuy
			t.TextColor3 = layer[1]
			t.Parent = gui
		end
	end
	light(crown, 30, 1.2, rgb(255, 214, 110))
	-- chains and a big lock while it is closed for you
	for _, side in { -1, 1 } do
		box("Chain", 0.7, 17, 0.7, g * CFrame.new(0, 8.8, -0.9) * ang(0, 0, side * 0.55), rgb(70, 64, 86), { Material = METAL, CanCollide = false, Attributes = { GateLock = 7 } })
	end
	local lock = box("Lock", 3.6, 3, 1.2, g * CFrame.new(0, 8.2, -1.5), rgb(120, 96, 40), { Material = METAL, CanCollide = false, Attributes = { GateLock = 7 } })
	sign(lock, Enum.NormalId.Front, { Title = "VII", Color = COL.Text, Glow = true })
	egg("Shackle", 2.6, 2.6, 0.5, g * CFrame.new(0, 10, -1.4), rgb(120, 96, 40), { Material = METAL, CanCollide = false, Attributes = { GateLock = 7 } })
	local marker = box("GateMarker", 1, 1, 1, g * CFrame.new(0, 34.5, 0), rgb(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false, Attributes = { GateMarker = 7 } })
	local tier = DifficultyData.Get(7)
	billboard(marker, "GateLabel", 16, 5.6, {
		{ tier.Numeral .. "  " .. tier.Name, 0.46, tier.Color },
		{ "LOCKED", 0.3, rgb(236, 232, 250) },
		{ if tier.Unlock then tier.Unlock.Text else "", 0.24, rgb(200, 194, 226) },
	}, 130)
	current = parent
	-- the throne of 67 (reserved)
	local throne = L(sx - 14, top, sz - 4) * ang(0, math.rad(20), 0)
	box("ThroneSeat", 4, 1.4, 4, throne * CFrame.new(0, 1.9, 0), COL.Gold, { Material = METAL })
	box("ThroneBack", 4, 7, 1, throne * CFrame.new(0, 5, 1.6), COL.Gold, { Material = METAL })
	ball("ThroneTop", 1.6, throne * CFrame.new(0, 9, 1.6), rgb(255, 80, 140), { Material = NEON, CanCollide = false })
	local cushion = box("ThroneCushion", 3.4, 0.5, 3.2, throne * CFrame.new(0, 2.8, -0.1), rgb(150, 70, 200))
	sign(cushion, Enum.NormalId.Top, { Title = "RESERVED", Color = COL.Text })
	for _, side in { -1, 1 } do
		box("ThroneArm", 0.8, 2, 4, throne * CFrame.new(side * 2.2, 3, 0), COL.Gold, { Material = METAL })
	end
	box("ThroneTrigger", 3.4, 5, 3.4, throne * CFrame.new(0, 4.5, 0), rgb(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false, Attributes = { SecretRegion = "Throne67" } })
	-- under the bridge (secret): a lonely ledge with a toll
	local mid = a:Lerp(b, 0.5)
	egg("TollLedge", 10, 2.6, 7, L(mid.X, -0.4, mid.Z), COL.Rock)
	disc("TollGrass", 0.3, 6.4, mid.X, 0.95, mid.Z, COL.Lawn, { Material = Enum.Material.Grass })
	signboard("TollSign", 5.4, 2, L(mid.X, 3.2, mid.Z - 2), { Title = "BRIDGE TOLL: 67", Sub = "honor system", Color = rgb(52, 40, 90), SubColor = rgb(90, 80, 120) }, 2.2)
	box("TollTrigger", 8, 6, 6, L(mid.X, 3.5, mid.Z), rgb(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false, Attributes = { SecretRegion = "UnderBridge" } })
end

---------------------------------------------------------------------------
-- far away: islands and a cloud shaped like 67
---------------------------------------------------------------------------
local function sky(lobby: Instance)
	folder("Sky", lobby)
	for _, i in { { 150, 14, 250, 1 }, { -170, 28, 300, 1.3 }, { 70, 44, 380, 0.8 } } do
		local x, y, z, s = i[1], i[2], i[3], i[4]
		egg("Islet", 34 * s, 24 * s, 30 * s, L(x, y - 9 * s, z), COL.Under, { CanCollide = false })
		disc("IsletTop", 2, 32 * s, x, y + 1, z, COL.Lawn, { CanCollide = false, Material = Enum.Material.Grass })
		egg("IsletTree", 10 * s, 9 * s, 10 * s, L(x + 4 * s, y + 6 * s, z), rgb(88, 176, 104), { CanCollide = false })
	end
	-- 67, written in cloud (reads right from the island: +X is on the left)
	local cx, cy, cz = 8, 92, 420
	local puffs = {
		-- the 6
		{ 34, 26, 12 }, { 30, 32, 11 }, { 25, 36, 10 }, { 36, 16, 12 }, { 34, 5, 12 }, { 26, 0, 12 }, { 18, 5, 12 }, { 20, 14, 11 }, { 27, 17, 10 },
		-- the 7
		{ -6, 36, 12 }, { -16, 36, 12 }, { -26, 36, 12 }, { -22, 25, 11 }, { -17, 14, 11 }, { -12, 3, 12 },
	}
	for _, p in puffs do
		ball("Cloud67", p[3], L(cx + p[1], cy + p[2], cz), rgb(255, 255, 255), { CanCollide = false, Transparency = 0.12 })
	end
end

---------------------------------------------------------------------------
-- NPCs: real hero models, a marker for the speech bubble, a soft collider
---------------------------------------------------------------------------
local function npcs(lobby: Instance)
	local f = folder("Npcs", lobby)
	for _, n in {
		{ "Guide", 12, 0.08, 32, 0.3 },
		{ "Security", -30, 0.1, 114, -0.8 },
		{ "Starer", -52, 0.1, 131.6, math.pi },
		{ "Keeper", 37, 6.12, 157, 0.35 },
		{ "The67", -37, 14, 203, -0.4 },
	} do
		local key = n[1] :: string
		local def = EventMapData.NpcByKey[key]
		local model = Instance.new("Model")
		model.Name = "Npc" .. key
		model.Parent = f
		-- a hero stands with its root 3 studs above the ground and faces -Z; yaw 0 = facing south
		local root = L(n[2] :: number, (n[3] :: number) + 3, n[4] :: number) * ang(0, n[5] :: number, 0)
		HeroModels.Build(def.Hero, root, model, { Ring = false, Skin = def.Skin })
		current = model
		local top = HeroModels.Top(def.Hero)
		local marker = box("NpcMarker", 1, 1, 1, root * CFrame.new(0, top + 1, 0), rgb(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false, Attributes = { NpcKey = key } })
		local bubble = billboard(marker, "Bubble", 12, 3.4, {
			{ def.Name, 0.36, rgb(255, 214, 96) },
			{ "", 0.64, rgb(255, 255, 255) },
		}, 60)
		bubble.StudsOffset = Vector3.new(0, 1.6, 0)
		bubble.Enabled = false
		rod("NpcCollider", 5, 3.2, root, rgb(255, 255, 255), { Transparency = 1, CanQuery = false })
	end
end

---------------------------------------------------------------------------
-- the beacon: a column of light the client puts on your NEXT gate
---------------------------------------------------------------------------
local function beacon(lobby: Instance)
	folder("Guide", lobby)
	local b = rod("Beacon", 70, 3, L(0, -200, 0), rgb(255, 214, 120), { Material = NEON, Transparency = 0.7, CanCollide = false, CanQuery = false, CastShadow = false })
	b:SetAttribute("Beacon", true)
end

--[[
	Builds the whole lobby into `map` (a Model named "Lobby"). `origin` is the lobby centre,
	`stageOffset` where the hub stage (the spawn) goes.
]]
function EventMap.Build(map: Instance, origin: Vector3, stageOffset: Vector3): Model
	ORIGIN = origin
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	lobby.Parent = map
	current = lobby
	ground(lobby)
	stage(lobby, stageOffset)
	spawnArea(lobby)
	greatBalance(lobby)
	plazaBoards(lobby)
	route(lobby)
	park(lobby)
	yard(lobby)
	rift(lobby)
	summit(lobby)
	sky(lobby)
	npcs(lobby)
	beacon(lobby)
	current = workspace
	return lobby
end

-- the lobby-space position of a tier's gate (for tests and tools)
EventMap.GateSpots = {
	[1] = Vector3.new(60, 0.05, 98),
	[2] = Vector3.new(38, 0.05, 98),
	[3] = Vector3.new(-40, 0.1, 124),
	[4] = Vector3.new(-64, 0.1, 124),
	[5] = Vector3.new(48, 6.12, 170),
	[6] = Vector3.new(26, 6.12, 172),
	[7] = Vector3.new(-50, 14, 206),
}

return EventMap
