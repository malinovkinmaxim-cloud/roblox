--[[
	BattleMap - builds the battle map "67 TOWN" (where runs happen). The layout, lairs, vaults
	and spots come from shared/ArenaData.lua (the simulation and the minimap use the same table).

	A pinwheel of zones around the start square (-Z is north: up the screen in a run):
	  67 SQUARE       the start: the 67 fountain, a clock stuck at 6:07, benches, a hot dog cart
	  GOOBER GARDENS  lawns, ponds, a giant rubber duck, hedges that spell 67 from above, the
	                  DUCK POND lair
	  HORDE MART LOT  a parking lot and the store (the Backrooms hide behind it), space no. 67,
	                  the CHECKOUT 67 lair
	  NEON STRIP      a neon boulevard with a casino, a diner, an arcade and a back alley,
	                  THE JACKPOT lair
	  THE RIFT        cracked violet ground behind crystal cliffs with three sealed gates, a
	                  broken floating obelisk, a crack worth squeezing into, THE TWIN ALTARS
	67 VAULTS stand in the four far corners; small painted "67 SPOTS" mark where roaming
	mini-bosses show up.

	Everything a run needs to read is flat at y = 0 (the simulation is 2D). Height is for
	looking at: cliffs, towers, floating rocks, arches over the roads. Signs meant to be read in
	a run are tilted to face the run camera (CAM).

	Attributes for the rest of the game:
	  EnemyBlocker   solid for the horde (MapBuilder.ExtractColliders)
	  Water          ponds: slower for everyone
	  SecretRegion   Backrooms / Parked67 / RiftCrack (server checks positions)
	  RiftSeal       the force fields in the rift gates (client: solid only while sealed for you)
	  RiftLabel      the gate labels (client: "OPENS 4:30" / "OPEN")
	  LairRing / LairBeam = lair key, VaultRing / VaultBeam / VaultSafe = vault index,
	  Spot67 = spot index: lit up per run by the client (ArenaController)
	  Spin / Bob     WorldController moves them
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local ArenaData = require(Shared.ArenaData)
local GameConfig = require(Shared.GameConfig)

local BattleMap = {}

local rgb = Color3.fromRGB
local ang = CFrame.Angles
local rad = math.rad
local UP = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis (X) turned up (Y)
local FRONT = CFrame.Angles(0, math.rad(90), 0) -- a cylinder's axis turned to face -Z / +Z
local CAM = CFrame.Angles(math.rad(-56), 0, 0) -- a board whose Back face looks at the run camera
-- flat on the ground, reading north-up from above (local +Y -> world -Z)
local FLAT = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, -Vector3.zAxis, Vector3.yAxis)
local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
local M = Enum.Material

local HALF = GameConfig.Arena.HalfSize

local COL = {
	Ink = rgb(30, 24, 52),
	Cream = rgb(240, 230, 206),
	Stone = rgb(206, 196, 178),
	Avenue = rgb(226, 214, 190),
	Gold = rgb(255, 204, 64),
	Pink = rgb(255, 128, 196),
	Water = rgb(92, 178, 255),
	Hedge = rgb(72, 160, 90),
	Leaf = rgb(92, 194, 104),
	LeafLight = rgb(122, 214, 118),
	Trunk = rgb(128, 88, 58),
	Path = rgb(222, 206, 164),
	Wood = rgb(160, 112, 72),
	Asphalt = rgb(70, 72, 90),
	Line = rgb(236, 238, 245),
	Store = rgb(120, 176, 255),
	StoreRoof = rgb(56, 92, 196),
	Metal = rgb(150, 156, 170),
	Orange = rgb(255, 130, 40),
	NightRoad = rgb(40, 32, 60),
	NeonPink = rgb(255, 72, 200),
	NeonCyan = rgb(0, 226, 255),
	Casino = rgb(120, 60, 190),
	Rock = rgb(78, 62, 116),
	RockDark = rgb(56, 44, 86),
	Crystal = rgb(196, 120, 255),
	CrystalPink = rgb(255, 110, 220),
	Basalt = rgb(52, 44, 72),
	Paper = rgb(248, 242, 228),
}

local ORIGIN = GameConfig.Arena.Center
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
	p.Material = M.SmoothPlastic
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
			elseif k == "Blocker" then
				if v then
					p:SetAttribute("EnemyBlocker", true)
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

local function with(extra: { [string]: any }?, key: string, value: any): { [string]: any }
	local e = if extra then table.clone(extra) else {}
	e[key] = value
	return e
end

local function box(name: string, sx: number, sy: number, sz: number, cf: CFrame, color: Color3, extra: { [string]: any }?): Part
	return part(name, Vector3.new(sx, sy, sz), cf, color, extra)
end

local function egg(name: string, sx: number, sy: number, sz: number, cf: CFrame, color: Color3, extra: { [string]: any }?): Part
	return part(name, Vector3.new(sx, sy, sz), cf, color, with(extra, "Mesh", true))
end

local function ball(name: string, d: number, cf: CFrame, color: Color3, extra: { [string]: any }?): Part
	return part(name, Vector3.new(d, d, d), cf, color, with(extra, "Shape", BALL))
end

-- a cylinder along cf's Y axis
local function rod(name: string, length: number, d: number, cf: CFrame, color: Color3, extra: { [string]: any }?): Part
	return part(name, Vector3.new(length, d, d), cf * UP, color, with(extra, "Shape", CYL))
end

-- a flat round slab whose TOP is at y = top
local function disc(name: string, thick: number, d: number, x: number, top: number, z: number, color: Color3, extra: { [string]: any }?): Part
	return part(name, Vector3.new(thick, d, d), L(x, top - thick / 2, z) * UP, color, with(extra, "Shape", CYL))
end

-- a round plate facing -Z / +Z
local function plate(name: string, depth: number, d: number, cf: CFrame, color: Color3, extra: { [string]: any }?): Part
	return part(name, Vector3.new(depth, d, d), cf * FRONT, color, with(extra, "Shape", CYL))
end

-- a flat strip on the ground from (x0, z0) to (x1, z1), its top at y = top
local function strip(name: string, x0: number, z0: number, x1: number, z1: number, width: number, top: number, color: Color3, extra: { [string]: any }?): Part
	local dx, dz = x1 - x0, z1 - z0
	local length = math.sqrt(dx * dx + dz * dz)
	local cf = CFrame.lookAt(ORIGIN + Vector3.new((x0 + x1) / 2, top - 0.05, (z0 + z1) / 2), ORIGIN + Vector3.new(x1, top - 0.05, z1))
	return part(name, Vector3.new(width, 0.1, length), cf, color, extra)
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

local function bob(p: BasePart, amount: number, phase: number?, speed: number?)
	p:SetAttribute("Bob", amount)
	if phase then
		p:SetAttribute("BobPhase", phase)
	end
	if speed then
		p:SetAttribute("BobSpeed", speed)
	end
end

---------------------------------------------------------------------------
-- text
---------------------------------------------------------------------------
type SignSpec = { Title: string, Sub: string?, Color: Color3?, SubColor: Color3?, Bg: Color3?, Glow: boolean? }

local function sign(target: BasePart, face: Enum.NormalId, spec: SignSpec): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = if spec.Glow then 0 else 1
	gui.Parent = target
	if spec.Bg then
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = spec.Bg
		bg.BorderSizePixel = 0
		bg.Parent = gui
	end
	local split = if spec.Sub then 0.62 else 1
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(0.92, 0, split * 0.9, 0)
	title.Position = UDim2.new(0.04, 0, split * 0.05, 0)
	title.Text = spec.Title
	title.TextScaled = true
	title.Font = Enum.Font.LuckiestGuy
	title.TextColor3 = spec.Color or COL.Gold
	title.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = rgb(24, 18, 44)
	stroke.Transparency = 0.2
	stroke.Parent = title
	if spec.Sub then
		local sub = Instance.new("TextLabel")
		sub.Name = "Sub"
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.new(0.9, 0, (1 - split) * 0.8, 0)
		sub.Position = UDim2.new(0.05, 0, split, 0)
		sub.Text = spec.Sub
		sub.TextScaled = true
		sub.Font = Enum.Font.BuilderSansBold
		sub.TextColor3 = spec.SubColor or rgb(236, 232, 250)
		sub.Parent = gui
	end
	return gui
end

-- a board facing the run camera (readable while you fight)
local function camBoard(name: string, w: number, h: number, x: number, y: number, z: number, spec: SignSpec, extra: { [string]: any }?): Part
	local board = box(name, w, h, 0.4, L(x, y, z) * CAM, spec.Bg or COL.Ink, extra)
	sign(board, Enum.NormalId.Back, spec)
	return board
end

-- a floating label; lines are TextLabels named Line1..LineN
local function billboard(target: BasePart, name: string, width: number, height: number, lines: { { any } }, maxDistance: number?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.new(width, 0, height, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 140
	gui.Parent = target
	local y = 0
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. i
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, line[2], 0)
		label.Position = UDim2.new(0, 0, y, 0)
		label.Text = line[1]
		label.TextScaled = true
		label.Font = if i == 1 then Enum.Font.LuckiestGuy else Enum.Font.BuilderSansExtraBold
		label.TextColor3 = line[3]
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = rgb(24, 18, 44)
		stroke.Parent = label
		y += line[2]
	end
	return gui
end

-- seven-segment digits: `frame` has local +X to the viewer's right, +Y up, the viewer on +Z;
-- the digit's bottom centre sits at the frame's origin
local SEGMENTS = {
	["0"] = "abcdef",
	["1"] = "bc",
	["2"] = "abged",
	["3"] = "abgcd",
	["4"] = "fgbc",
	["5"] = "afgcd",
	["6"] = "afgedc",
	["7"] = "abc",
	["8"] = "abcdefg",
	["9"] = "abcdfg",
}
local function digit(ch: string, frame: CFrame, size: number, thick: number, depth: number, color: Color3, extra: { [string]: any }?)
	local s = size
	local spots = {
		a = { 0, 2 * s, true },
		b = { s / 2, 1.5 * s, false },
		c = { s / 2, 0.5 * s, false },
		d = { 0, 0, true },
		e = { -s / 2, 0.5 * s, false },
		f = { -s / 2, 1.5 * s, false },
		g = { 0, s, true },
	}
	for seg in string.gmatch(SEGMENTS[ch] or "", ".") do
		local spot = spots[seg]
		local sx, sy = if spot[3] then s + thick else thick, if spot[3] then thick else s
		box("Seg" .. seg, sx, sy, depth, frame * CFrame.new(spot[1], spot[2], 0), color, extra)
	end
end

-- "67" (or any digits) centred on `frame`
local function number(text: string, frame: CFrame, size: number, thick: number, depth: number, color: Color3, extra: { [string]: any }?)
	local gap = size * 1.55
	local n = #text
	for i = 1, n do
		local x = (i - (n + 1) / 2) * gap
		digit(string.sub(text, i, i), frame * CFrame.new(x, 0, 0), size, thick, depth, color, extra)
	end
end

---------------------------------------------------------------------------
-- props
---------------------------------------------------------------------------
local function tree(x: number, z: number, scale: number)
	local trunkH = 6 * scale
	rod("Trunk", trunkH, 2.2 * scale, L(x, trunkH / 2, z), COL.Trunk, { Blocker = true })
	ball("Leaves", 10 * scale, L(x, trunkH + 2.6 * scale, z), COL.Leaf, { CanCollide = false })
	ball("LeavesTop", 6.5 * scale, L(x + 1.4 * scale, trunkH + 6 * scale, z - 1 * scale), COL.LeafLight, { CanCollide = false })
end

local function lamp(x: number, z: number, height: number, color: Color3, lit: boolean)
	rod("LampPole", height, 0.8, L(x, height / 2, z), rgb(58, 56, 74), { Blocker = true })
	local bulb = ball("LampBulb", 2.2, L(x, height + 0.8, z), color, { Material = M.Neon, CanCollide = false })
	if lit then
		light(bulb, 20, 1.2, color)
	end
end

local function bench(x: number, z: number)
	box("BenchSeat", 7, 0.6, 2.2, L(x, 1.3, z), COL.Wood, { Blocker = true })
	box("BenchBack", 7, 1.6, 0.5, L(x, 2.4, z - 1), COL.Wood)
end

local function flowerBed(x: number, z: number, r: number, color: Color3, rng: Random)
	disc("FlowerBed", 0.3, r * 2, x, 0.12, z, rgb(96, 148, 72), { Material = M.Grass, CanCollide = false })
	for k = 1, 5 do
		local a = k * (math.pi * 2 / 5) + rng:NextNumber(-0.3, 0.3)
		local d = r * (if k % 2 == 0 then 0.35 else 0.62)
		ball("Flower", 1.8, L(x + math.cos(a) * d, 0.8, z + math.sin(a) * d), color, { CanCollide = false })
	end
end

-- a crystal: a tall neon shard, tilted
local function crystal(x: number, y: number, z: number, h: number, w: number, tilt: number, spin: number, color: Color3, extra: { [string]: any }?)
	return box("Crystal", w, h, w, L(x, y + h / 2 - 0.5, z) * ang(0, spin, 0) * ang(tilt, 0, tilt * 0.6), color, with(extra, "Material", M.Neon))
end

---------------------------------------------------------------------------
-- the ground: 40-stud tiles in the colours of their zone (movement reads from above)
---------------------------------------------------------------------------
local ZONE_MATERIAL = { Square = M.Pavement, Gardens = M.Grass, Lot = M.Asphalt, Strip = M.Asphalt, Rift = M.Slate }

local function ground(arena: Instance)
	folder("Ground", arena)
	local tile = 40
	local n = math.ceil(HALF * 2 / tile)
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local x = -HALF + tile / 2 + i * tile
			local z = -HALF + tile / 2 + j * tile
			local zone = ArenaData.ZoneAt(x, z)
			box("Tile", tile, 2, tile, L(x, -1, z), zone.Ground[(i + j) % 2 + 1], { Material = ZONE_MATERIAL[zone.Key] })
		end
	end
end

-- the edge of the map: every zone closes its own side (plus invisible walls)
local function borders(arena: Instance)
	folder("Border", arena)
	local e = HALF + 3
	local function wall(name: string, x0: number, z0: number, x1: number, z1: number, h: number, color: Color3, extra: { [string]: any }?)
		local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
		local sx, sz = math.max(4, math.abs(x1 - x0)), math.max(4, math.abs(z1 - z0))
		return box(name, sx, h, sz, L(cx, h / 2, cz), color, extra)
	end
	-- west: rift cliffs, garden hedge
	wall("RiftCliff", -e, -e, -e, -80, 10, COL.Rock, { Material = M.Slate })
	wall("Hedge", -e, -80, -e, e, 5, COL.Hedge, { Material = M.Grass })
	-- south: garden hedge, lot fence
	wall("Hedge", -e, e, -80, e, 5, COL.Hedge, { Material = M.Grass })
	wall("Fence", -80, e, e, e, 5, COL.Metal, { Material = M.DiamondPlate })
	-- east: lot fence, strip wall with a neon trim
	wall("Fence", e, 80, e, e, 5, COL.Metal, { Material = M.DiamondPlate })
	wall("StripWall", e, -e, e, 80, 8, rgb(46, 36, 70))
	box("StripNeon", 0.6, 0.5, 80 + e, L(e - 1.7, 8.2, (80 - e) / 2), COL.NeonPink, { Material = M.Neon, CanCollide = false })
	-- north: rift cliffs, strip wall
	wall("RiftCliff", -e, -e, 80, -e, 10, COL.Rock, { Material = M.Slate })
	wall("StripWall", 80, -e, e, -e, 8, rgb(46, 36, 70))
	-- nobody leaves
	local h = 40
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local sx, sz = side[1], side[2]
		local len = HALF * 2 + 8
		box("InvisibleWall", if sx ~= 0 then 4 else len, h, if sz ~= 0 then 4 else len, L(sx * e, h / 2, sz * e), rgb(255, 255, 255), { Transparency = 1 })
	end
end

---------------------------------------------------------------------------
-- 67 SQUARE (the start)
---------------------------------------------------------------------------
local function arch(name: string, x: number, z: number, alongX: boolean, title: string, color: Color3)
	-- two pillars across the road, a lintel, the zone's name facing the camera
	local span = 26
	for _, s in { -1, 1 } do
		local px, pz = if alongX then x else x + s * span / 2, if alongX then z + s * span / 2 else z
		box(name .. "Pillar", 3, 13, 3, L(px, 6.5, pz), COL.Stone, { Blocker = true })
		ball(name .. "Cap", 3.4, L(px, 13.6, pz), color, { Material = M.Neon, CanCollide = false })
	end
	box(name .. "Lintel", if alongX then 3 else span + 3, 2.2, if alongX then span + 3 else 3, L(x, 12.4, z), COL.Stone, { CanCollide = false })
	camBoard(name .. "Sign", 20, 4.4, x, 16.6, z, { Title = title, Color = color, Bg = COL.Ink, Glow = true }, { CanCollide = false })
end

local function square(arena: Instance)
	folder("Square", arena)
	-- the plaza and the four avenues out of it
	disc("Plaza", 0.2, 76, 0, 0.1, 0, COL.Cream, { Material = M.Pebble })
	disc("PlazaRing", 0.05, 64, 0, 0.13, 0, COL.Gold, { CanCollide = false })
	disc("PlazaInner", 0.05, 61, 0, 0.16, 0, COL.Cream, { Material = M.Pebble, CanCollide = false })
	strip("Avenue", 0, -38, 0, -80, 14, 0.08, COL.Avenue, { Material = M.Pebble })
	strip("Avenue", 0, 38, 0, 80, 14, 0.08, COL.Avenue, { Material = M.Pebble })
	strip("Avenue", -38, 0, -80, 0, 14, 0.08, COL.Avenue, { Material = M.Pebble })
	strip("Avenue", 38, 0, 80, 0, 14, 0.08, COL.Avenue, { Material = M.Pebble })

	-- THE 67 FOUNTAIN: a stone basin, a pillar, a golden 6 and 7 spraying water
	disc("FountainRim", 2.6, 22, 0, 2.6, 0, COL.Stone, { Blocker = true, Material = M.Pebble })
	disc("FountainWater", 0.3, 19.4, 0, 2.3, 0, COL.Water, { Material = M.Glass, Transparency = 0.25, CanCollide = false })
	local pillar = rod("FountainPillar", 4.2, 5, L(0, 4.1, 0), COL.Stone)
	number("67", L(0, 6.2, 0), 3.6, 1.2, 1.2, COL.Gold, { Material = M.Neon, CanCollide = false })
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Color = ColorSequence.new(rgb(190, 230, 255))
	spray.LightEmission = 0.4
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.1) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(1, 1.4)
	spray.Rate = 26
	spray.Speed = NumberRange.new(10, 13)
	spray.SpreadAngle = Vector2.new(16, 16)
	spray.Acceleration = Vector3.new(0, -22, 0)
	spray.EmissionDirection = Enum.NormalId.Right -- the rod's axis points up
	spray.Parent = pillar

	-- benches and lamps around the plaza
	for _, b in { { -44, -26 }, { 44, -26 }, { -44, 30 }, { 44, 30 } } do
		bench(b[1], b[2])
	end
	for _, l in { { -12, -42 }, { 12, 42 }, { 42, -12 }, { -42, 12 } } do
		lamp(l[1], l[2], 11, rgb(255, 232, 170), true)
	end

	-- the clock tower (always 6:07)
	local tx, tz = -58, -58
	box("ClockTower", 10, 26, 10, L(tx, 13, tz), rgb(218, 196, 160), { Blocker = true, Material = M.Brick })
	box("ClockTowerTop", 12, 3, 12, L(tx, 27.5, tz), rgb(140, 80, 70))
	rod("ClockSpire", 8, 1.2, L(tx, 33, tz), rgb(140, 80, 70), { CanCollide = false })
	ball("ClockSpireBall", 2.4, L(tx, 37.4, tz), COL.Gold, { Material = M.Neon, CanCollide = false })
	local face = L(tx, 20, tz + 5.2)
	plate("ClockFace", 0.4, 8, face, rgb(250, 246, 232), { CanCollide = false })
	-- 6:07 (the hour hand just past 6, the minute hand on 7 minutes)
	box("HourHand", 0.5, 2.6, 0.3, face * CFrame.new(0, 0, 0.35) * ang(0, 0, rad(-183.5)) * CFrame.new(0, 1.3, 0), COL.Ink, { CanCollide = false })
	box("MinuteHand", 0.4, 3.5, 0.3, face * CFrame.new(0, 0, 0.4) * ang(0, 0, rad(-42)) * CFrame.new(0, 1.75, 0), COL.Ink, { CanCollide = false })
	camBoard("ClockSign", 9, 2.2, tx, 13.5, tz + 5.6, { Title = "67 O'CLOCK", Bg = rgb(140, 80, 70), Color = COL.Paper })

	-- YOU ARE HERE (probably)
	local board = camBoard("MapBoard", 11, 7, 24, 5.2, 54, { Title = "67 TOWN", Sub = "YOU ARE HERE (probably)", Bg = COL.Ink })
	board.CanCollide = false
	rod("MapBoardPost", 3, 0.6, L(24, 1.5, 54.6), rgb(58, 56, 74), { Blocker = true })

	-- a hot dog cart: 67 DOGS
	box("DogCart", 6, 3.4, 3.4, L(-46, 2.3, 46), rgb(236, 72, 72), { Blocker = true })
	rod("DogUmbrellaPole", 5, 0.3, L(-46, 6, 46), COL.Metal, { CanCollide = false })
	disc("DogUmbrella", 0.6, 9, -46, 8.8, 46, rgb(255, 214, 80), { CanCollide = false })
	camBoard("DogSign", 5.6, 1.6, -46, 5, 47.9, { Title = "67 DOGS", Bg = rgb(255, 214, 80), Color = rgb(200, 40, 40) }, { CanCollide = false })

	-- planters at the corners of the square
	for _, p in { { 66, -66 }, { 66, 66 }, { -66, 66 } } do
		box("Planter", 10, 2, 10, L(p[1], 1, p[2]), rgb(180, 160, 130), { Blocker = true })
		egg("PlanterBush", 9, 5, 9, L(p[1], 3.6, p[2]), COL.Hedge, { CanCollide = false })
	end

	-- arches out to the zones (the rift gate is a crystal gate)
	arch("GardenArch", -80, 0, true, "GOOBER GARDENS", ArenaData.ByKey.Gardens.Color)
	arch("LotArch", 0, 80, false, "HORDE MART LOT", ArenaData.ByKey.Lot.Color)
	arch("StripArch", 80, 0, true, "NEON STRIP", ArenaData.ByKey.Strip.Color)
end

---------------------------------------------------------------------------
-- THE RIFT's crystal cliffs and gates
---------------------------------------------------------------------------
local function riftWall(arena: Instance)
	folder("RiftWall", arena)
	local rng = Random.new(6707)
	local thick = 7
	-- one run of cliff between a and b along an axis, broken into jagged pieces
	local function run(axis: string, fixed: number, a: number, b: number)
		local length = b - a
		local pieces = math.max(1, math.floor(length / 18 + 0.5))
		local step = length / pieces
		for i = 0, pieces - 1 do
			local c = a + step * (i + 0.5)
			local h = rng:NextNumber(6, 10)
			local x, z = if axis == "X" then c else fixed, if axis == "X" then fixed else c
			local sx, sz = if axis == "X" then step + 0.4 else thick, if axis == "X" then thick else step + 0.4
			box("Cliff", sx, h, sz, L(x, h / 2, z), if i % 2 == 0 then COL.Rock else COL.RockDark, { Blocker = true, Material = M.Slate })
			-- crystals on top
			local cx = x + (if axis == "X" then rng:NextNumber(-step * 0.3, step * 0.3) else rng:NextNumber(-1.5, 1.5))
			local cz = z + (if axis == "X" then rng:NextNumber(-1.5, 1.5) else rng:NextNumber(-step * 0.3, step * 0.3))
			crystal(cx, h, cz, rng:NextNumber(5, 9), rng:NextNumber(1.8, 2.8), rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), if i % 3 == 0 then COL.CrystalPink else COL.Crystal, { CanCollide = false })
		end
	end
	-- the south cliffs (z = -80) and the east cliffs (x = 80), with the gates' gaps
	local gates = ArenaData.RiftGates
	local southGaps, eastGaps = {}, {}
	for _, g in gates do
		if g.Axis == "X" then
			table.insert(southGaps, { g.X - g.Width / 2, g.X + g.Width / 2 })
		else
			table.insert(eastGaps, { g.Z - g.Width / 2, g.Z + g.Width / 2 })
		end
	end
	table.sort(southGaps, function(p, q)
		return p[1] < q[1]
	end)
	table.sort(eastGaps, function(p, q)
		return p[1] < q[1]
	end)
	local x = -HALF
	for _, gap in southGaps do
		run("X", -80, x, gap[1])
		x = gap[2]
	end
	run("X", -80, x, 80 + thick / 2)
	local z = -HALF
	for _, gap in eastGaps do
		run("Z", 80, z, gap[1])
		z = gap[2]
	end
	run("Z", 80, z, -80 - thick / 2)

	-- the gates: two tall crystals, a force field (sealed until the rift opens)
	for _, g in gates do
		local alongX = g.Axis == "X"
		for _, s in { -1, 1 } do
			local px = if alongX then g.X + s * (g.Width / 2 + 1.5) else g.X
			local pz = if alongX then g.Z else g.Z + s * (g.Width / 2 + 1.5)
			box("GatePillar", 4, 16, 4, L(px, 8, pz) * ang(0, rad(45), 0), COL.Crystal, { Blocker = true, Material = M.Neon, Transparency = 0.1 })
		end
		local seal = box("RiftSeal", if alongX then g.Width else 1, 12, if alongX then 1 else g.Width, L(g.X, 6, g.Z), COL.Crystal, {
			Material = M.ForceField,
			Transparency = 0.2,
			CanCollide = false,
			Attributes = { RiftSeal = g.Key },
		})
		billboard(seal, "RiftLabel", 12, 3.6, {
			{ "THE RIFT", 0.55, COL.Crystal },
			{ "OPENS AT 4:30", 0.45, rgb(236, 232, 250) },
		}, 150).StudsOffset = Vector3.new(0, 10, 0)
		seal:SetAttribute("RiftLabel", true)
	end
end

---------------------------------------------------------------------------
-- GOOBER GARDENS
---------------------------------------------------------------------------
local function topiary(x: number, z: number, scale: number)
	-- a hedge goober with googly eyes
	egg("Topiary", 7 * scale, 6 * scale, 7 * scale, L(x, 3 * scale, z), COL.Hedge, { Blocker = true, Material = M.Grass })
	for _, s in { -1, 1 } do
		local eye = L(x + s * 1.4 * scale, 4.2 * scale, z + 3.1 * scale)
		ball("TopiaryEye", 1.9 * scale, eye, rgb(255, 255, 255), { CanCollide = false })
		ball("TopiaryPupil", 0.9 * scale, eye * CFrame.new(0.15 * s, -0.2, 0.7 * scale), COL.Ink, { CanCollide = false })
	end
end

local function gardens(arena: Instance)
	folder("Gardens", arena)
	local rng = Random.new(1667)
	-- paths: from the square to the rift gate, down to the duck pond, over to the lot
	strip("GardenPath", -80, 0, -160, 0, 12, 0.09, COL.Path, { Material = M.Pebble })
	strip("GardenPath", -160, -80, -160, 0, 12, 0.09, COL.Path, { Material = M.Pebble })
	strip("GardenPath", -160, 0, -163, 126, 12, 0.09, COL.Path, { Material = M.Pebble })
	strip("GardenPath", -141, 160, -80, 160, 12, 0.09, COL.Path, { Material = M.Pebble })
	disc("PathCircle", 0.1, 20, -160, 0.1, 0, COL.Path, { Material = M.Pebble, CanCollide = false })

	-- the giant rubber duck in its pond
	local dx, dz = -196, 70
	disc("PondRim", 0.3, 50, dx, 0.14, dz, rgb(206, 196, 164), { Material = M.Pebble })
	local pond = disc("Pond", 0.35, 45, dx, 0.2, dz, COL.Water, { Material = M.Glass, Transparency = 0.15 })
	pond:SetAttribute("Water", true)
	egg("DuckBody", 15, 11, 19, L(dx, 5, dz + 2), rgb(255, 220, 50), { Blocker = true })
	ball("DuckHead", 9.5, L(dx, 12.5, dz - 5), rgb(255, 226, 64), { CanCollide = false })
	box("DuckBeak", 4.6, 1.8, 3.6, L(dx, 12, dz - 10.4), COL.Orange, { CanCollide = false })
	for _, s in { -1, 1 } do
		ball("DuckEye", 1.6, L(dx + s * 2.3, 14.2, dz - 8.7), COL.Ink, { CanCollide = false })
	end
	for _, lp in { { 12, -9, 4 }, { -13, 8, 3 }, { 8, 14, 3.4 } } do
		disc("LilyPad", 0.2, lp[3], dx + lp[1], 0.3, dz + lp[2], rgb(96, 200, 96), { CanCollide = false })
	end

	-- the hedges spell 67 from above (you have to look down to see it)
	local maze = FLAT
	number("67", L(-196, 1.7, -17) * maze, 17, 3, 3.4, COL.Hedge, { Blocker = true, Material = M.Grass })

	-- a gazebo
	local gx, gz = -112, 68
	disc("GazeboFloor", 0.5, 15, gx, 0.5, gz, rgb(236, 226, 206))
	for k = 1, 4 do
		local a = k * (math.pi / 2) + math.pi / 4
		rod("GazeboPost", 7, 0.8, L(gx + math.cos(a) * 5.6, 4, gz + math.sin(a) * 5.6), rgb(250, 248, 240), { Blocker = true })
	end
	disc("GazeboRoof", 1, 17, gx, 8.5, gz, rgb(236, 110, 150), { CanCollide = false })
	disc("GazeboRoofTop", 1.4, 9, gx, 9.9, gz, rgb(236, 110, 150), { CanCollide = false })
	ball("GazeboFinial", 2, L(gx, 10.8, gz), COL.Gold, { CanCollide = false })

	-- topiary goobers, flower beds, trees, lamps
	topiary(-120, -46, 1)
	topiary(-218, 168, 1.2)
	topiary(-108, 206, 0.9)
	local colors = { rgb(255, 110, 190), rgb(255, 215, 60), rgb(180, 110, 255), rgb(255, 140, 70), rgb(255, 255, 255) }
	for i, f in { { -104, 30 }, { -132, 106 }, { -222, 116 }, { -124, 232 }, { -226, 18 } } do
		flowerBed(f[1], f[2], rng:NextNumber(4.5, 6), colors[i], rng)
	end
	for _, t in {
		{ -96, -58 }, { -136, -62 }, { -228, -62 }, { -98, 96 }, { -132, 36 }, { -226, 82 },
		{ -150, 232 }, { -186, 228 }, { -100, 176 }, { -206, 140 },
	} do
		tree(t[1], t[2], rng:NextNumber(0.9, 1.25))
	end
	for _, l in { { -150, 40 }, { -172, 100 }, { -120, 170 } } do
		lamp(l[1], l[2], 9, rgb(255, 236, 190), false)
	end
	-- a picnic: 67 sandwiches (don't count them)
	box("Blanket", 9, 0.12, 7, L(-96, 0.1, 132), rgb(236, 80, 80), { CanCollide = false })
	box("BlanketStripe", 9, 0.14, 1.6, L(-96, 0.12, 132), rgb(255, 255, 255), { CanCollide = false })
	box("Basket", 2.4, 1.6, 1.8, L(-93, 0.9, 131), COL.Wood, { Blocker = true })
	camBoard("PicnicSign", 6, 1.5, -99, 1.4, 136, { Title = "67 SANDWICHES", Bg = COL.Paper, Color = rgb(200, 60, 60) }, { CanCollide = false })
end

---------------------------------------------------------------------------
-- HORDE MART LOT
---------------------------------------------------------------------------
local function cart(x: number, z: number, turn: number)
	local cf = L(x, 1.5, z) * ang(0, turn, 0)
	box("Cart", 3, 2, 4.2, cf, COL.Metal, { Blocker = true, Material = M.DiamondPlate })
	box("CartHandle", 3.4, 0.35, 0.35, cf * CFrame.new(0, 1.4, 2.4), rgb(236, 60, 60), { CanCollide = false })
end

local function lot(arena: Instance)
	folder("Lot", arena)
	-- two rows of parking spaces; space 67 is special
	for _, row in { 112, 142 } do
		strip("StallRow", -52, row + 8, 116, row + 8, 0.5, 0.06, COL.Line, { CanCollide = false })
		for x = -52, 116, 12 do
			strip("StallLine", x, row - 8, x, row + 8, 0.5, 0.06, COL.Line, { CanCollide = false })
		end
	end
	-- spaces 66, 67, 68 (the lines are every 12 studs from x = -52)
	local numbers = { { 14, 142, "66" }, { 26, 142, "67" }, { 38, 142, "68" } }
	for _, nb in numbers do
		local flat = box("StallNumber", 7, 0.1, 5, L(nb[1], 0.08, nb[2] + 3), COL.Asphalt, { CanCollide = false, Transparency = 1 })
		local gui = sign(flat, Enum.NormalId.Top, { Title = nb[3], Color = if nb[3] == "67" then COL.Gold else COL.Line, Glow = nb[3] == "67" })
		gui.Name = "StallNumber"
	end
	box("Reserved67", 10.5, 0.08, 15, L(26, 0.05, 142), COL.Gold, { CanCollide = false, Transparency = 0.55, Material = M.Neon })
	camBoard("ReservedSign", 5, 2.6, 26, 4, 133, { Title = "RESERVED", Sub = "FOR 67 ONLY", Bg = rgb(40, 100, 220), Color = COL.Paper }, { CanCollide = false })
	rod("ReservedPost", 3.5, 0.4, L(26, 1.75, 133.6), COL.Metal)
	local parked = box("Parked67Trigger", 9, 8, 13, L(26, 4, 142), rgb(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false })
	parked:SetAttribute("SecretRegion", "Parked67")

	-- HORDE MART (the Backrooms are behind it)
	box("Store", 70, 16, 30, L(40, 8, 201), COL.Store, { Blocker = true, Material = M.Concrete })
	box("StoreStripe", 70.4, 2, 30.4, L(40, 12, 201), COL.StoreRoof)
	box("StoreRoof", 72, 1.5, 32, L(40, 16.75, 201), COL.StoreRoof)
	box("StoreDoors", 12, 7, 0.4, L(40, 3.5, 185.8), rgb(170, 220, 255), { Material = M.Glass, Transparency = 0.25 })
	camBoard("StoreSign", 34, 7, 40, 22, 196, { Title = "HORDE MART", Sub = "OPEN 6 TO 7 · EVERYTHING MUST GO", Bg = rgb(255, 255, 255), Color = COL.StoreRoof, SubColor = rgb(236, 72, 72) })

	-- The Backrooms: a yellow box behind the store; its north wall has no collision
	local bx, bz = 40, 231
	local wallColor = rgb(222, 205, 130)
	box("BackroomsFloor", 16, 1, 14, L(bx, 0.5, bz), rgb(190, 170, 100))
	box("BackroomsCeiling", 16, 1, 14, L(bx, 11, bz), rgb(235, 225, 170))
	box("BackroomsWallW", 1, 10, 14, L(bx - 8, 6, bz), wallColor, { Blocker = true })
	box("BackroomsWallE", 1, 10, 14, L(bx + 8, 6, bz), wallColor, { Blocker = true })
	box("BackroomsWallS", 16, 10, 1, L(bx, 6, bz + 7), wallColor, { Blocker = true })
	box("NoClipWall", 16, 10, 1, L(bx, 6, bz - 7), wallColor, { CanCollide = false })
	light(box("Buzz", 4, 0.3, 1, L(bx, 10.4, bz), rgb(255, 255, 230), { Material = M.Neon }), 14, 1, rgb(255, 250, 210))
	local trigger = box("SecretTrigger", 12, 8, 10, L(bx, 5, bz), rgb(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false })
	trigger:SetAttribute("SecretRegion", "Backrooms")

	-- carts, corrals, lights, cones, containers, a taco truck
	for _, c in { { 64, 128 }, { 96, 124 } } do
		box("CorralRail", 12, 1.4, 0.4, L(c[1], 1.8, c[2] - 2), COL.Metal, { Blocker = true })
		box("CorralRail", 12, 1.4, 0.4, L(c[1], 1.8, c[2] + 2), COL.Metal, { Blocker = true })
	end
	for _, c in { { 58, 100, 0.3 }, { -10, 188, 1.4 }, { 120, 186, 2.6 }, { 8, 124, -0.6 }, { 140, 100, 1 } } do
		cart(c[1], c[2], c[3])
	end
	for _, l in { { -40, 100 }, { 100, 100 }, { -40, 160 }, { 100, 160 } } do
		lamp(l[1], l[2], 14, rgb(255, 244, 214), false)
	end
	for _, c in { { 134, 132 }, { 138, 138 }, { 142, 130 }, { -64, 124 }, { 184, 100 }, { 190, 104 } } do
		rod("Cone", 2.4, 1.6, L(c[1], 1.2, c[2]), COL.Orange, { CanCollide = false })
		rod("ConeBand", 0.5, 1.7, L(c[1], 1.4, c[2]), rgb(255, 255, 255), { CanCollide = false })
	end
	box("Container", 8, 8, 20, L(226, 4, 104), rgb(210, 70, 60), { Blocker = true, Material = M.CorrodedMetal })
	box("Container", 8, 8, 20, L(226, 4, 128), rgb(60, 130, 200), { Blocker = true, Material = M.CorrodedMetal })
	box("Container", 8, 8, 20, L(226, 12, 116), rgb(240, 180, 50), { CanCollide = false, Material = M.CorrodedMetal })
	box("Container", 20, 8, 8, L(120, 4, 228), rgb(80, 170, 110), { Blocker = true, Material = M.CorrodedMetal })
	-- 67 TACOS
	box("TacoTruck", 12, 7, 6, L(-44, 4.2, 206), rgb(250, 250, 250), { Blocker = true })
	box("TacoCab", 4, 5, 6, L(-36, 3.2, 206), rgb(255, 200, 60))
	plate("TacoWheel", 1, 2.4, L(-47, 1.2, 209.2), COL.Ink, { CanCollide = false })
	plate("TacoWheel", 1, 2.4, L(-38, 1.2, 209.2), COL.Ink, { CanCollide = false })
	camBoard("TacoSign", 11, 2.6, -44, 9.4, 207, { Title = "67 TACOS", Bg = rgb(255, 200, 60), Color = rgb(200, 40, 40) }, { CanCollide = false })
	-- speed bumps
	box("SpeedBump", 18, 0.3, 1.4, L(0, 0.15, 170), rgb(255, 214, 40), { CanCollide = false })
	box("SpeedBump", 18, 0.3, 1.4, L(150, 0.15, 214), rgb(255, 214, 40), { CanCollide = false })
end

---------------------------------------------------------------------------
-- NEON STRIP
---------------------------------------------------------------------------
local function shop(name: string, x: number, z: number, w: number, d: number, h: number, color: Color3, trim: Color3, title: string, sub: string?)
	box(name, w, h, d, L(x, h / 2, z), color, { Blocker = true, Material = M.Concrete })
	-- a neon band round the top of the walls (under the roof edge: the roof keeps its colour)
	box(name .. "Trim", w + 0.4, 0.6, d + 0.4, L(x, h - 0.9, z), trim, { Material = M.Neon, CanCollide = false })
	camBoard(name .. "Sign", math.min(w - 2, 22), 4.6, x, h + 3, z + d / 2 - 2, { Title = title, Sub = sub, Bg = COL.Ink, Color = trim, Glow = true }, { CanCollide = false })
end

local function palm(x: number, z: number, color: Color3, lit: boolean)
	rod("PalmTrunk", 10, 1.2, L(x, 5, z), rgb(150, 110, 80), { Blocker = true })
	box("PalmLeaf", 8, 0.5, 2, L(x, 10.4, z) * ang(0, 0.4, 0.3), rgb(60, 180, 100), { CanCollide = false })
	local top = ball("PalmNeon", 2, L(x, 10.8, z), color, { Material = M.Neon, CanCollide = false })
	if lit then
		light(top, 22, 1.4, color)
	end
end

local function neonStrip(arena: Instance)
	folder("Strip", arena)
	-- the boulevard (north to THE JACKPOT), the street from the square, the back alley
	strip("Boulevard", 160, 76, 160, -134, 22, 0.08, COL.NightRoad, { Material = M.Asphalt })
	strip("BoulevardEdge", 149.5, 76, 149.5, -134, 0.6, 0.1, COL.NeonCyan, { Material = M.Neon, CanCollide = false })
	strip("BoulevardEdge", 170.5, 76, 170.5, -134, 0.6, 0.1, COL.NeonCyan, { Material = M.Neon, CanCollide = false })
	for z = 66, -126, -32 do
		strip("BoulevardDash", 160, z, 160, z - 10, 0.8, 0.11, COL.NeonPink, { Material = M.Neon, CanCollide = false })
	end
	strip("StripStreet", 80, 0, 149, 0, 14, 0.08, COL.NightRoad, { Material = M.Asphalt })
	strip("BackAlley", 100, -8, 100, -166, 10, 0.08, rgb(34, 28, 50), { Material = M.Asphalt })
	strip("BackAlley", 80, -160, 104, -160, 10, 0.09, rgb(34, 28, 50), { Material = M.Asphalt })

	-- 67 CASINO with its neon 67 and marquee lights
	shop("Casino", 214, -40, 36, 60, 20, COL.Casino, COL.Gold, "67 CASINO", "67% WIN RATE (NOT REALLY)")
	number("67", L(214, 27, -18) * CAM, 3.2, 1.1, 0.8, COL.Gold, { Material = M.Neon, CanCollide = false })
	for k = 0, 7 do
		ball("Marquee", 1.4, L(197.5 + k * 4.7, 20.8, -10.5), if k % 2 == 0 then COL.Gold else COL.NeonPink, { Material = M.Neon, CanCollide = false })
	end
	-- 67 DINER, ARCADE, the shops by the alley
	shop("Diner", 214, 42, 32, 34, 12, rgb(246, 246, 250), rgb(236, 60, 80), "67 DINER", "OPEN 6 TO 7")
	shop("Arcade", 215, -112, 30, 36, 14, rgb(40, 40, 80), COL.NeonCyan, "ARCADE", "INSERT 67 CENTS")
	shop("Pawn", 126, -40, 28, 40, 10, rgb(90, 70, 120), COL.NeonPink, "PAWN 67", "WE BUY SIXES")
	shop("Laundry", 126, -110, 28, 30, 10, rgb(70, 110, 140), COL.NeonCyan, "LUCKY LAUNDRY", "SOCKS GO IN. SOCKS DON'T COME OUT.")
	-- the back alley: dumpsters and a very suspicious door
	box("Dumpster", 6, 4, 3.4, L(96, 2, -58), rgb(40, 120, 70), { Blocker = true })
	box("Dumpster", 6, 4, 3.4, L(96, 2, -128), rgb(40, 120, 70), { Blocker = true })
	box("SuspiciousDoor", 0.4, 7, 4, L(111.8, 3.5, -110), rgb(120, 60, 40))
	camBoard("DoorSign", 5, 1.4, 108, 8.4, -110, { Title = "DEFINITELY NOT A DOOR", Bg = COL.Ink, Color = COL.NeonPink, Glow = true }, { CanCollide = false })

	-- arches of light over the boulevard
	for _, a in { { 60, "NEON STRIP" }, { -84, "LUCKY MILE" } } do
		local z = a[1] :: number
		for _, s in { -1, 1 } do
			box("NeonArchPillar", 2, 16, 2, L(160 + s * 14, 8, z), rgb(46, 36, 70), { Blocker = true })
		end
		box("NeonArchBar", 30, 1.2, 1.2, L(160, 16.2, z), COL.NeonPink, { Material = M.Neon, CanCollide = false })
		camBoard("NeonArchSign", 18, 3.6, 160, 19, z, { Title = a[2] :: string, Bg = COL.Ink, Color = COL.NeonCyan, Glow = true }, { CanCollide = false })
	end
	-- palm lamps along the road
	for i, p in { { 144, 40 }, { 176, 18 }, { 144, -20 }, { 176, -44 }, { 144, -76 }, { 176, -102 } } do
		palm(p[1], p[2], if i % 2 == 0 then COL.NeonPink else COL.NeonCyan, i <= 3)
	end
	-- giant dice (one shows 6, the other 7... somehow)
	for _, d in { { 188, 22, 0.4 }, { 190, 4, -0.3 } } do
		local cf = L(d[1], 3, d[2]) * ang(0, d[3], 0)
		box("Die", 6, 6, 6, cf, rgb(250, 250, 250), { Blocker = true })
		for k = -1, 1 do
			disc("Pip", 0.1, 1.1, 0, 0, 0, COL.Ink, { CanCollide = false }).CFrame = cf * CFrame.new(k * 1.6, 3.02, k * 1.6) * UP
		end
	end
	-- 67 FOR SALE
	box("SaleStall", 7, 3.2, 3, L(186, 1.6, -86), rgb(236, 72, 150), { Blocker = true })
	box("SaleAwning", 8, 0.4, 4, L(186, 5.6, -86) * ang(0.2, 0, 0), COL.Paper, { CanCollide = false })
	camBoard("SaleSign", 7, 2, 186, 7.4, -84.4, { Title = "67 FOR SALE", Sub = "ASK INSIDE (THERE IS NO INSIDE)", Bg = COL.Paper, Color = rgb(236, 72, 150), SubColor = COL.Ink }, { CanCollide = false })
end

---------------------------------------------------------------------------
-- THE RIFT
---------------------------------------------------------------------------
local function rift(arena: Instance)
	folder("Rift", arena)
	local rng = Random.new(767)
	-- dark paths from the gates
	strip("RiftPath", 0, -80, 0, -128, 11, 0.09, COL.Basalt, { Material = M.Basalt })
	strip("RiftPath", 0, -128, -52, -164, 11, 0.09, COL.Basalt, { Material = M.Basalt })
	strip("RiftPath", -160, -80, -168, -136, 11, 0.09, COL.Basalt, { Material = M.Basalt })
	strip("RiftPath", 80, -160, -52, -176, 11, 0.09, COL.Basalt, { Material = M.Basalt })

	-- glowing cracks in the ground
	for _, c in {
		{ -120, -110, -84, -128 }, { -84, -128, -70, -112 }, { -30, -200, 10, -186 }, { 10, -186, 40, -204 },
		{ -220, -170, -196, -196 }, { -196, -196, -176, -186 }, { 40, -110, 60, -140 }, { -130, -214, -100, -226 },
		{ -60, -96, -30, -104 }, { -236, -98, -214, -118 },
	} do
		strip("Crack", c[1], c[2], c[3], c[4], 0.7, 0.1, COL.CrystalPink, { Material = M.Neon, CanCollide = false })
	end

	-- crystal clusters
	for _, k in {
		{ -40, -112 }, { -118, -198 }, { -210, -150 }, { 30, -220 }, { 52, -122 }, { -136, -120 }, { -200, -104 }, { 10, -150 },
	} do
		local x, z = k[1], k[2]
		egg("CrystalRock", 7, 3.4, 6, L(x, 1.3, z), COL.RockDark, { Blocker = true, Material = M.Slate })
		crystal(x - 1, 1.5, z, rng:NextNumber(6, 9), 2.2, 0.2, rng:NextNumber(0, 6), COL.Crystal, { CanCollide = false })
		crystal(x + 1.6, 1.2, z + 0.8, rng:NextNumber(4, 6), 1.6, -0.3, rng:NextNumber(0, 6), COL.CrystalPink, { CanCollide = false })
	end

	-- floating rocks overhead
	for i, f in { { -60, -140, 22 }, { -150, -210, 26 }, { -210, -120, 20 }, { 40, -170, 24 }, { -110, -100, 28 }, { 0, -228, 20 } } do
		local rock = egg("FloatingRock", 10, 5, 8, L(f[1], f[3], f[2]) * ang(0, i, 0), COL.Rock, { CanCollide = false, Material = M.Slate })
		bob(rock, 1.2, i * 1.1, 0.8)
		local shard = crystal(f[1], f[3] + 2, f[2], 5, 1.6, 0.1, i, COL.Crystal, { CanCollide = false })
		bob(shard, 1.2, i * 1.1, 0.8)
	end

	-- THE OBELISK: broken, the top half floats, a 67 glows on it
	local ox, oz = -170, -150
	box("ObeliskBase", 8, 16, 8, L(ox, 8, oz), rgb(24, 20, 36), { Blocker = true, Material = M.Slate })
	local top = box("ObeliskTop", 7, 14, 7, L(ox, 27, oz) * ang(0, 0.2, 0.08), rgb(24, 20, 36), { CanCollide = false, Material = M.Slate })
	bob(top, 1.5, 0, 0.6)
	local glyph = box("ObeliskGlyph", 5, 5, 0.3, L(ox, 26, oz + 3.6) * CAM, COL.Ink, { CanCollide = false, Transparency = 1 })
	bob(glyph, 1.5, 0, 0.6)
	sign(glyph, Enum.NormalId.Back, { Title = "67", Color = COL.CrystalPink, Glow = true })
	for k = 1, 3 do
		local a = k * 2.1
		local shard = crystal(ox + math.cos(a) * 7, 17, oz + math.sin(a) * 7, 3, 1.2, 0.4, k, COL.Crystal, { CanCollide = false })
		bob(shard, 2, k, 1)
	end

	-- void pools (slow like water)
	for _, v in { { -40, -142, 10 }, { -214, -122, 11 } } do
		disc("VoidRim", 0.3, v[3] * 2 + 3, v[1], 0.14, v[2], COL.CrystalPink, { Material = M.Neon, CanCollide = false })
		local pool = disc("VoidPool", 0.35, v[3] * 2, v[1], 0.2, v[2], rgb(40, 20, 70), { Material = M.Glass, Transparency = 0.1 })
		pool:SetAttribute("Water", true)
	end

	-- MIND THE GAP: a crack between two crystals at the north edge; one of them isn't there
	-- two crystals reach back to the edge of the map; the one between them is a fake
	local cx = -20
	box("GapCrystal", 6, 14, 18, L(cx - 7, 7, -231), COL.Crystal, { Blocker = true, Material = M.Neon, Transparency = 0.15 })
	box("GapCrystal", 6, 14, 18, L(cx + 7, 7, -231), COL.Crystal, { Blocker = true, Material = M.Neon, Transparency = 0.15 })
	box("GapFake", 8, 14, 4, L(cx, 7, -224), COL.Crystal, { CanCollide = false, Material = M.Neon, Transparency = 0.15 })
	local glow = box("GapGlow", 2.4, 2.4, 0.4, L(cx, 3, -236) * CAM, COL.Ink, { CanCollide = false, Transparency = 1 })
	sign(glow, Enum.NormalId.Back, { Title = "67", Color = COL.Gold, Glow = true })
	local gapTrigger = box("GapTrigger", 6, 8, 10, L(cx, 4, -233), rgb(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false })
	gapTrigger:SetAttribute("SecretRegion", "RiftCrack")
end

---------------------------------------------------------------------------
-- lairs, vaults, 67 spots
---------------------------------------------------------------------------
local LAIR_STYLE = {
	DuckPond = { Floor = rgb(150, 214, 120), Ring = rgb(255, 214, 60), Post = rgb(90, 160, 90), Material = M.Grass },
	Checkout = { Floor = rgb(110, 116, 140), Ring = rgb(255, 214, 40), Post = rgb(255, 214, 40), Material = M.Asphalt },
	Jackpot = { Floor = rgb(150, 30, 60), Ring = COL.Gold, Post = COL.Gold, Material = M.Fabric },
	Altars = { Floor = rgb(60, 44, 96), Ring = COL.Crystal, Post = COL.Crystal, Material = M.Slate },
}

local function lairs(arena: Instance)
	folder("Lairs", arena)
	for _, lair in ArenaData.Lairs do
		local style = LAIR_STYLE[lair.Key]
		local x, z, r = lair.X, lair.Z, lair.R
		local ring = disc("LairRing", 0.1, r * 2, x, 0.1, z, style.Ring, { CanCollide = false, Material = M.SmoothPlastic })
		ring:SetAttribute("LairRing", lair.Key)
		disc("LairFloor", 0.12, r * 2 - 2.4, x, 0.2, z, style.Floor, { CanCollide = false, Material = style.Material })
		for k = 1, 4 do
			local a = k * (math.pi / 2) + math.pi / 4
			rod("LairPost", 3, 1.2, L(x + math.cos(a) * (r + 1.5), 1.5, z + math.sin(a) * (r + 1.5)), style.Post, { Blocker = true })
			ball("LairPostTop", 1.6, L(x + math.cos(a) * (r + 1.5), 3.4, z + math.sin(a) * (r + 1.5)), style.Ring, { Material = M.Neon, CanCollide = false })
		end
		camBoard("LairSign", 14, 3.4, x, 7, z - r - 3, { Title = lair.Name, Bg = COL.Ink, Color = style.Ring, Glow = true }, { CanCollide = false })
		-- a column of light, shown by the client while a mini-boss is there
		local beam = rod("LairBeam", 44, 2.6, L(x, 22, z), style.Ring, { Material = M.Neon, Transparency = 1, CanCollide = false })
		beam:SetAttribute("LairBeam", lair.Key)
		if lair.Pads then
			for i, pad in lair.Pads do
				local digitText = if i == 1 then "6" else "7"
				disc("AltarPad", 1.2, 12, pad[1], 1.2, pad[2], rgb(40, 30, 64), { Blocker = true, Material = M.Slate })
				local glyph = box("AltarGlyph", 6, 0.1, 6, L(pad[1], 1.26, pad[2]), COL.Ink, { CanCollide = false, Transparency = 1 })
				sign(glyph, Enum.NormalId.Top, { Title = digitText, Color = if i == 1 then COL.Gold else COL.Crystal, Glow = true })
			end
		end
	end
	-- the duck pond lair has a real pond on its side, the checkout a conveyor belt
	local duck = ArenaData.LairByKey.DuckPond
	local pond = disc("LairPond", 0.35, 18, duck.X - 30, 0.2, duck.Z + 26, COL.Water, { Material = M.Glass, Transparency = 0.15 })
	pond:SetAttribute("Water", true)
	for k = 1, 3 do
		rod("Cattail", 5, 0.4, L(duck.X - 22 + k * 1.4, 2.5, duck.Z + 20 - k), rgb(110, 170, 80), { CanCollide = false })
	end
	local checkout = ArenaData.LairByKey.Checkout
	box("Conveyor", 14, 2.4, 4, L(checkout.X + 34, 1.2, checkout.Z), rgb(40, 40, 50), { Blocker = true })
	box("Register", 3, 3, 3, L(checkout.X + 34, 3.9, checkout.Z + 5), rgb(236, 72, 72), { Blocker = true })
end

local function vaults(arena: Instance)
	folder("Vaults", arena)
	for i, v in ArenaData.Vaults do
		local pad = ArenaData.VaultPad
		local ring = disc("VaultRing", 0.12, pad * 2, v.X, 0.14, v.Z, rgb(120, 110, 90), { CanCollide = false })
		ring:SetAttribute("VaultRing", i)
		disc("VaultPad", 0.12, pad * 2 - 2, v.X, 0.17, v.Z, rgb(64, 58, 72), { CanCollide = false, Material = M.DiamondPlate })
		box("VaultPedestal", 5, 1.6, 5, L(v.X, 0.8, v.Z), rgb(90, 84, 104), { Blocker = true })
		local safe = box("VaultSafe", 4, 4, 4, L(v.X, 3.6, v.Z), rgb(150, 130, 70), { Material = M.Metal })
		safe:SetAttribute("VaultSafe", i)
		local dial = plate("VaultDial", 0.3, 2.4, CFrame.new(safe.Position + Vector3.new(0, 0, 2.1)), COL.Ink, { CanCollide = false })
		sign(dial, Enum.NormalId.Left, { Title = "67", Color = COL.Gold, Glow = true }) -- faces +Z (the camera)
		local beam = rod("VaultBeam", 40, 1.8, L(v.X, 20, v.Z), COL.Gold, { Material = M.Neon, Transparency = 1, CanCollide = false })
		beam:SetAttribute("VaultBeam", i)
	end
end

local function spots(arena: Instance)
	folder("Spots", arena)
	for i, s in ArenaData.Spots do
		local mark = disc("Spot67", 0.1, 8, s[1], 0.12, s[2], rgb(255, 255, 255), { CanCollide = false, Transparency = 0.8 })
		mark:SetAttribute("Spot67", i)
		local flat = box("Spot67Text", 5, 0.1, 5, L(s[1], 0.14, s[2]), COL.Ink, { CanCollide = false, Transparency = 1 })
		sign(flat, Enum.NormalId.Top, { Title = "67", Color = rgb(255, 255, 255) })
	end
end

---------------------------------------------------------------------------
-- build
---------------------------------------------------------------------------
function BattleMap.Build(map: Instance): Model
	local arena = Instance.new("Model")
	arena.Name = "Arena"
	arena:SetAttribute("MapName", "67 TOWN")
	arena.Parent = map
	ground(arena)
	borders(arena)
	square(arena)
	riftWall(arena)
	gardens(arena)
	lot(arena)
	neonStrip(arena)
	rift(arena)
	lairs(arena)
	vaults(arena)
	spots(arena)
	current = workspace
	return arena
end

return BattleMap
