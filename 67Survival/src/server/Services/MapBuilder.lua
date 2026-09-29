--[[
	MapBuilder - builds the world from code: the LOBBY ("67 LAND", the event map: Map/EventMap)
	and the arena "67 PARK".

	If Workspace already has a "Map" model (made by hand in Studio), it is used as is.
	Rules for a custom map:
	  * Map.Arena: parts with attribute EnemyBlocker = true block enemies (their XZ bounding
	    boxes become colliders for the server simulation)
	  * parts with attribute SecretRegion = "<key>" are secret areas (server checks positions)
	  * Workspace.SpawnPoints: "Lobby" + "Arena1".."ArenaN"

	The arena is flat and open in the middle (hordes need space), with readable ground tiles
	(so movement is visible from the top-down camera), roads, small buildings, trees and a few
	landmarks near the edges, plus a hidden room.
	The lobby spawn is the HUB STAGE of 67 LAND: the player's hero on a pedestal, framed by the
	hub camera (client CameraController). Also sets the base lighting (haze, soft bloom).
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Shared.GameConfig)
local EventMap = require(script.Parent.Parent.Map.EventMap)

local MapBuilder = {}

local rgb = Color3.fromRGB
local CENTER = GameConfig.Arena.Center
local HALF = GameConfig.Arena.HalfSize
local LOBBY = GameConfig.Lobby.Center

local current: Instance = Workspace

local function part(props: { [string]: any }): BasePart
	local className = props.ClassName or "Part"
	local p = Instance.new(className) :: any
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CanTouch = false
	p.CastShadow = false
	for key, value in props do
		if key ~= "ClassName" and key ~= "Parent" and key ~= "Blocker" and key ~= "Attributes" then
			p[key] = value
		end
	end
	if props.Blocker then
		p:SetAttribute("EnemyBlocker", true)
	end
	if props.Attributes then
		for k, v in props.Attributes do
			p:SetAttribute(k, v)
		end
	end
	p.Parent = props.Parent or current
	return p
end

local function block(name: string, size: Vector3, cf: CFrame, color: Color3, extra: { [string]: any }?): BasePart
	local props = { Name = name, Size = size, CFrame = cf, Color = color }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return part(props)
end

local function sign(target: BasePart, face: Enum.NormalId, text: string, color: Color3?, bg: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bg or rgb(30, 25, 50)
	label.BackgroundTransparency = if bg then 0 else 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.LuckiestGuy
	label.TextColor3 = color or rgb(255, 255, 255)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = rgb(25, 20, 45)
	stroke.Parent = label
	return label
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(CENTER + Vector3.new(x, y, z))
end

---------------------------------------------------------------------------
-- arena pieces
---------------------------------------------------------------------------
local function tree(x: number, z: number, scale: number, parent: Instance)
	current = parent
	local trunkH = 7 * scale
	block("Trunk", Vector3.new(2.4, trunkH, 2.4) * Vector3.new(scale, 1, scale), at(x, trunkH / 2, z), rgb(120, 80, 50), { Blocker = true })
	local leaves = block("Leaves", Vector3.new(11, 9, 11) * scale, at(x, trunkH + 3 * scale, z), rgb(70, 190, 90), { Shape = Enum.PartType.Ball, CastShadow = true })
	leaves.CanCollide = false
	local top = block("LeavesTop", Vector3.new(7, 6, 7) * scale, at(x + 1.5 * scale, trunkH + 7 * scale, z - 1 * scale), rgb(95, 215, 105), { Shape = Enum.PartType.Ball })
	top.CanCollide = false
end

local NORMALS = {
	Right = Vector3.new(1, 0, 0),
	Left = Vector3.new(-1, 0, 0),
	Back = Vector3.new(0, 0, 1),
	Front = Vector3.new(0, 0, -1),
}

local function building(name: string, title: string, x: number, z: number, size: Vector3, color: Color3, roof: Color3, parent: Instance)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	current = model
	local body = block("Body", size, at(x, size.Y / 2, z), color, { Blocker = true, CastShadow = true })
	block("Roof", Vector3.new(size.X + 2, 1.5, size.Z + 2), at(x, size.Y + 0.75, z), roof)
	block("RoofTrim", Vector3.new(size.X + 2.6, 0.6, size.Z + 2.6), at(x, size.Y + 0.1, z), rgb(40, 35, 60))
	-- door and windows on the side facing the park center
	local toCenter = Vector3.new(-x, 0, -z).Unit
	local face = if math.abs(toCenter.X) > math.abs(toCenter.Z)
		then (if toCenter.X > 0 then Enum.NormalId.Right else Enum.NormalId.Left)
		else (if toCenter.Z > 0 then Enum.NormalId.Back else Enum.NormalId.Front)
	local signPart = block("Sign", Vector3.new(size.X * 0.8, 5, size.Z * 0.8), at(x, size.Y + 4.5, z), rgb(30, 25, 50))
	signPart.CanCollide = false
	signPart.Transparency = 1
	for _, f in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		sign(signPart, f, title, rgb(255, 230, 90))
	end
	local offset = NORMALS[face.Name]
	local half = size / 2
	local doorPos = Vector3.new(x, 0, z) + Vector3.new(offset.X * (half.X + 0.1), 5, offset.Z * (half.Z + 0.1))
	block("Door", Vector3.new(if offset.X ~= 0 then 0.4 else 6, 10, if offset.Z ~= 0 then 0.4 else 6), at(doorPos.X, 5, doorPos.Z), rgb(60, 45, 35))
	for i = -1, 1, 2 do
		local side = Vector3.new(offset.Z, 0, offset.X) * i * (math.max(half.X, half.Z) * 0.55)
		local w = Vector3.new(x, 0, z) + Vector3.new(offset.X * (half.X + 0.1), 0, offset.Z * (half.Z + 0.1)) + side
		block("Window", Vector3.new(if offset.X ~= 0 then 0.4 else 5, 5, if offset.Z ~= 0 then 0.4 else 5), at(w.X, size.Y * 0.55, w.Z), rgb(150, 220, 255), { Material = Enum.Material.Glass, Transparency = 0.2 })
	end
	return model, body
end

-- seven-segment digits for the giant 67 monument
local SEGMENTS = {
	["6"] = { "a", "c", "d", "e", "f", "g" },
	["7"] = { "a", "b", "c" },
}
local function digit(ch: string, origin: Vector3, parent: Instance, mirror: boolean?)
	current = parent
	local L, T = 6, 1.8
	local m = if mirror then -1 else 1 -- mirrored: reads right for a viewer looking towards +Z
	local spots = {
		a = { Vector3.new(0, 2 * L, 0), true },
		b = { Vector3.new(m * L / 2, 1.5 * L, 0), false },
		c = { Vector3.new(m * L / 2, 0.5 * L, 0), false },
		d = { Vector3.new(0, 0, 0), true },
		e = { Vector3.new(-m * L / 2, 0.5 * L, 0), false },
		f = { Vector3.new(-m * L / 2, 1.5 * L, 0), false },
		g = { Vector3.new(0, L, 0), true },
	}
	for _, seg in SEGMENTS[ch] do
		local spot = spots[seg]
		local size = if spot[2] then Vector3.new(L, T, T) else Vector3.new(T, L, T)
		block("Seg" .. seg, size, CFrame.new(origin + spot[1]), rgb(255, 205, 40), { Material = Enum.Material.Neon })
	end
end

local function landmarks(parent: Instance)
	local lm = folder("Landmarks", parent)

	-- THE 67 MONUMENT (north of the center, off the main road)
	current = lm
	block("Pedestal67", Vector3.new(22, 3, 8), at(-60, 1.5, -95), rgb(60, 50, 90), { Blocker = true })
	digit("6", CENTER + Vector3.new(-66, 4, -95), lm)
	digit("7", CENTER + Vector3.new(-54, 4, -95), lm)

	-- giant rubber duck
	current = lm
	block("DuckBody", Vector3.new(16, 12, 20), at(95, 6, 70), rgb(255, 220, 50), { Shape = Enum.PartType.Ball, Blocker = true, CastShadow = true })
	block("DuckHead", Vector3.new(10, 10, 10), at(95, 14, 62), rgb(255, 225, 60), { Shape = Enum.PartType.Ball })
	block("DuckBeak", Vector3.new(5, 2, 4), at(95, 13.5, 56.5), rgb(255, 140, 30))
	block("DuckEyeL", Vector3.new(1.6, 1.6, 1.6), at(92.5, 16, 58), rgb(20, 20, 20), { Shape = Enum.PartType.Ball })
	block("DuckEyeR", Vector3.new(1.6, 1.6, 1.6), at(97.5, 16, 58), rgb(20, 20, 20), { Shape = Enum.PartType.Ball })

	-- floating orb (spun by the client)
	block("OrbStand", Vector3.new(6, 8, 6), at(-110, 4, 80), rgb(80, 70, 110), { Blocker = true })
	local orb = block("FloatingOrb", Vector3.new(11, 11, 11), at(-110, 17, 80), rgb(255, 205, 60), { Shape = Enum.PartType.Ball, Material = Enum.Material.Neon })
	orb.CanCollide = false
	orb:SetAttribute("Spin", 0.6)
	orb:SetAttribute("Bob", 1.5)

	-- giant traffic cone
	for i = 0, 4 do
		local r = 10 - i * 2
		block("Cone" .. i, Vector3.new(4, r, r), at(40, 2 + i * 4, 120) * CFrame.Angles(0, 0, math.rad(90)), if i % 2 == 0 then rgb(255, 120, 30) else rgb(255, 255, 255), { Shape = Enum.PartType.Cylinder, Blocker = i == 0 })
	end

	-- the staring statue (huge, always facing the park center)
	local look = CFrame.lookAt(CENTER + Vector3.new(135, 0, 45), CENTER)
	local function statue(name, size, offset, color)
		block(name, size, look * CFrame.new(offset), color, { Blocker = name == "Legs" })
	end
	statue("Legs", Vector3.new(6, 8, 3), Vector3.new(0, 4, 0), rgb(40, 127, 71))
	statue("Torso", Vector3.new(6, 6, 3), Vector3.new(0, 11, 0), rgb(13, 105, 172))
	statue("ArmL", Vector3.new(3, 6, 3), Vector3.new(-4.5, 11, 0), rgb(245, 205, 48))
	statue("ArmR", Vector3.new(3, 6, 3), Vector3.new(4.5, 11, 0), rgb(245, 205, 48))
	local head = block("Head", Vector3.new(4, 4, 4), look * CFrame.new(0, 16, 0), rgb(245, 205, 48))
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	-- snack vending machine
	local vend = block("SnackMachine", Vector3.new(6, 10, 4), at(-30, 5, 150), rgb(220, 40, 60), { Blocker = true })
	sign(vend, Enum.NormalId.Front, "SNACKS", rgb(255, 255, 255))
	sign(vend, Enum.NormalId.Back, "SNACKS", rgb(255, 255, 255))

	-- benches and lamps along the roads
	for i = -3, 3 do
		if i ~= 0 then
			local z = i * 55
			block("Bench", Vector3.new(2, 1.2, 7), at(17, 1.2, z), rgb(150, 100, 60))
			block("Lamp", Vector3.new(1, 12, 1), at(-17, 6, z), rgb(60, 60, 75))
			local bulb = block("Bulb", Vector3.new(2.2, 2.2, 2.2), at(-17, 12.5, z), rgb(255, 240, 180), { Shape = Enum.PartType.Ball, Material = Enum.Material.Neon })
			local light = Instance.new("PointLight")
			light.Range = 18
			light.Brightness = 1
			light.Color = rgb(255, 230, 170)
			light.Parent = bulb
		end
	end
end

local function secretRoom(parent: Instance)
	-- The Backrooms: a plain yellow box behind HORDE MART. Its north wall has no collision.
	local model = Instance.new("Model")
	model.Name = "Backrooms"
	model.Parent = parent
	current = model
	local cx, cz = 150, -196
	local wall = rgb(222, 205, 130)
	block("Floor", Vector3.new(16, 1, 14), at(cx, 0.5, cz), rgb(190, 170, 100))
	block("Ceiling", Vector3.new(16, 1, 14), at(cx, 11, cz), rgb(235, 225, 170))
	block("WallW", Vector3.new(1, 10, 14), at(cx - 8, 6, cz), wall, { Blocker = true })
	block("WallE", Vector3.new(1, 10, 14), at(cx + 8, 6, cz), wall, { Blocker = true })
	block("WallS", Vector3.new(16, 10, 1), at(cx, 6, cz - 7), wall, { Blocker = true })
	-- the "no-clip" wall: looks solid, isn't
	local fake = block("NoClipWall", Vector3.new(16, 10, 1), at(cx, 6, cz + 7), wall)
	fake.CanCollide = false
	local lamp = block("Buzz", Vector3.new(4, 0.3, 1), at(cx, 10.4, cz), rgb(255, 255, 230), { Material = Enum.Material.Neon })
	local light = Instance.new("PointLight")
	light.Range = 14
	light.Parent = lamp
	local trigger = block("SecretTrigger", Vector3.new(12, 8, 10), at(cx, 5, cz), rgb(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false })
	trigger:SetAttribute("SecretRegion", "Backrooms")
end

-- flower beds are flat colour; ponds are WATER (attribute Water): everyone wades through
-- slower (GameConfig.Water), except bosses and flyers.
-- spot(radius, margin) returns a free position (or nil) and marks it as taken.
local function decorations(arena: Instance, spot: (number, number) -> (number?, number?))
	local deco = folder("Decorations", arena)
	local flat = CFrame.Angles(0, 0, math.rad(90))
	local rng = Random.new(76)
	for _, r in { 26, 22 } do
		local x, z = spot(r + 3, 40)
		if x and z then
			current = deco
			block("PondRim", Vector3.new(0.3, r * 2 + 4, r * 2 + 4), at(x, 0.15, z) * flat, rgb(200, 190, 160), { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Pebble })
			local pond = block("Pond", Vector3.new(0.35, r * 2, r * 2), at(x, 0.2, z) * flat, rgb(80, 170, 255), { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Glass, Transparency = 0.15 })
			pond:SetAttribute("Water", true)
			block("LilyPad", Vector3.new(0.4, 4, 4), at(x + r * 0.3, 0.25, z - r * 0.2) * flat, rgb(90, 200, 90), { Shape = Enum.PartType.Cylinder })
			block("LilyPad", Vector3.new(0.4, 3, 3), at(x - r * 0.4, 0.25, z + r * 0.3) * flat, rgb(90, 200, 90), { Shape = Enum.PartType.Cylinder })
		end
	end
	local colors = { rgb(255, 110, 190), rgb(255, 215, 60), rgb(180, 110, 255), rgb(255, 140, 70), rgb(255, 255, 255) }
	for _ = 1, 16 do
		local r = rng:NextNumber(4, 6.5)
		local x, z = spot(r, 20)
		if x and z then
			current = deco
			block("FlowerBed", Vector3.new(0.3, r * 2, r * 2), at(x, 0.15, z) * flat, rgb(95, 150, 70), { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Grass })
			local color = colors[rng:NextInteger(1, #colors)]
			for k = 1, 8 do
				local a = k * (math.pi * 2 / 8) + rng:NextNumber(-0.3, 0.3)
				local d = r * (if k % 2 == 0 then 0.35 else 0.7)
				block("Flower", Vector3.new(1.9, 1.9, 1.9), at(x + math.cos(a) * d, 0.7, z + math.sin(a) * d), color, { Shape = Enum.PartType.Ball })
			end
		end
	end
end

local function buildArena(map: Model)
	local arena = Instance.new("Model")
	arena.Name = "Arena"
	arena.Parent = map
	current = arena

	-- ground: big readable tiles
	local ground = folder("Ground", arena)
	current = ground
	local tile = 40
	local n = math.ceil(HALF * 2 / tile)
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local x = -HALF + tile / 2 + i * tile
			local z = -HALF + tile / 2 + j * tile
			local light = (i + j) % 2 == 0
			block("Tile", Vector3.new(tile, 2, tile), at(x, -1, z), if light then rgb(125, 205, 105) else rgb(110, 190, 95), { Material = Enum.Material.Grass })
		end
	end
	-- roads (cross through the park) with dashed center lines
	block("RoadNS", Vector3.new(24, 0.2, HALF * 2), at(0, 0.1, 0), rgb(70, 70, 85), { Material = Enum.Material.Asphalt })
	block("RoadEW", Vector3.new(HALF * 2, 0.2, 24), at(0, 0.11, 0), rgb(70, 70, 85), { Material = Enum.Material.Asphalt })
	for k = -HALF + 10, HALF - 10, 20 do
		if math.abs(k) > 16 then
			block("Dash", Vector3.new(1, 0.1, 8), at(0, 0.25, k), rgb(255, 215, 60))
			block("Dash", Vector3.new(8, 0.1, 1), at(k, 0.25, 0), rgb(255, 215, 60))
		end
	end
	block("Plaza", Vector3.new(0.3, 50, 50), at(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(235, 225, 200), { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Pebble })
	block("PlazaRing", Vector3.new(0.35, 44, 44), at(0, 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(255, 170, 200), { Shape = Enum.PartType.Cylinder })
	block("PlazaInner", Vector3.new(0.4, 40, 40), at(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(240, 232, 210), { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Pebble })

	-- border: hedges + invisible walls
	local border = folder("Border", arena)
	current = border
	local wallH = 40
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local sx, sz = side[1], side[2]
		local len = HALF * 2 + 8
		local size = if sx ~= 0 then Vector3.new(4, 5, len) else Vector3.new(len, 5, 4)
		block("Hedge", size, at(sx * (HALF + 3), 2.5, sz * (HALF + 3)), rgb(60, 150, 70), { Material = Enum.Material.Grass })
		local wsize = if sx ~= 0 then Vector3.new(4, wallH, len) else Vector3.new(len, wallH, 4)
		block("InvisibleWall", wsize, at(sx * (HALF + 3), wallH / 2, sz * (HALF + 3)), rgb(255, 255, 255), { Transparency = 1 })
	end

	-- buildings in the four quadrants (enemies walk around them)
	local buildings = folder("Buildings", arena)
	building("HordeMart", "HORDE MART", 150, -150, Vector3.new(34, 16, 26), rgb(120, 170, 255), rgb(60, 90, 200), buildings)
	building("HeroGym", "HERO GYM", -150, -150, Vector3.new(30, 14, 30), rgb(255, 150, 90), rgb(200, 80, 50), buildings)
	building("Casino67", "67 CASINO", 150, 150, Vector3.new(30, 18, 30), rgb(170, 110, 255), rgb(255, 205, 40), buildings)
	building("Diner67", "67 DINER", -150, 150, Vector3.new(28, 14, 28), rgb(235, 235, 240), rgb(35, 35, 45), buildings)
	secretRoom(buildings) -- hidden behind HORDE MART

	-- free spots: away from roads, the spawn plaza, buildings and everything placed before
	local occupied = {
		{ -60, -95, 25 }, -- 67 monument
		{ 95, 70, 25 }, -- duck
		{ -110, 80, 16 }, -- floating orb
		{ 135, 45, 16 }, -- statue
		{ 40, 120, 14 }, -- traffic cone
		{ 150, -196, 20 }, -- backrooms
		{ -30, 150, 10 }, -- snack machine
	}
	local rng = Random.new(67)
	local function free(x: number, z: number, r: number): boolean
		if math.abs(x) < 22 + r or math.abs(z) < 22 + r or math.sqrt(x * x + z * z) < 70 then
			return false
		end
		if math.abs(math.abs(x) - 150) < 26 + r and math.abs(math.abs(z) - 150) < 26 + r then
			return false
		end
		for _, o in occupied do
			if (x - o[1]) ^ 2 + (z - o[2]) ^ 2 < (o[3] + r) ^ 2 then
				return false
			end
		end
		return true
	end
	local function spot(r: number, margin: number): (number?, number?)
		for _ = 1, 200 do
			local x = rng:NextNumber(-HALF + margin, HALF - margin)
			local z = rng:NextNumber(-HALF + margin, HALF - margin)
			if free(x, z, r) then
				table.insert(occupied, { x, z, r })
				return x, z
			end
		end
		return nil, nil
	end

	decorations(arena, spot)

	local trees = folder("Trees", arena)
	for _ = 1, 42 do
		local scale = rng:NextNumber(0.8, 1.3)
		local x, z = spot(6 * scale, 12)
		if x and z then
			tree(x, z, scale, trees)
		end
	end

	landmarks(arena)
	return arena
end

---------------------------------------------------------------------------
-- lobby: "67 LAND", the event map (Map/EventMap)
---------------------------------------------------------------------------
local STAGE = Vector3.new(0, 0, -6) -- lobby offset of the hero spot (= the lobby spawn)
MapBuilder.StageOffset = STAGE

-- the look of the whole place: soft daylight, a light haze, a little bloom for the neon
local function applyLighting()
	local Lighting = game:GetService("Lighting")
	if Lighting:FindFirstChild("S67Atmosphere") then
		return
	end
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.2
	Lighting.Ambient = rgb(72, 66, 98)
	Lighting.OutdoorAmbient = rgb(132, 126, 156)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.ShadowSoftness = 0.3
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "S67Atmosphere"
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.1
	atmosphere.Color = rgb(206, 214, 240)
	atmosphere.Decay = rgb(110, 112, 156)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "S67Bloom"
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "S67Grade"
	grade.Saturation = 0.08
	grade.Contrast = 0.06
	grade.Parent = Lighting
end

local function buildLobby(map: Model)
	return EventMap.Build(map, LOBBY, STAGE)
end

local function buildSpawns(map: Model)
	local spawns = Instance.new("Folder")
	spawns.Name = "SpawnPoints"
	spawns.Parent = Workspace
	current = spawns
	-- the lobby spawn is the hub stage's pedestal (its top is 0.65 above the floor)
	block("Lobby", Vector3.new(6, 1, 6), CFrame.new(LOBBY + STAGE + Vector3.new(0, 0.7, 0)), rgb(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false })
	for i, offset in GameConfig.Arena.StartOffsets do
		block("Arena" .. i, Vector3.new(6, 1, 6), CFrame.new(CENTER + offset + Vector3.new(0, 0.5, 0)), rgb(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false })
	end
	return map
end

---------------------------------------------------------------------------
-- colliders & regions for the server simulation
---------------------------------------------------------------------------
local COLLIDER_CELL = 32

function MapBuilder.ExtractColliders(arena: Instance)
	local cells = {}
	local count = 0
	local water = {}
	for _, d in arena:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Water") then
			-- a flat cylinder: its radius is half the size across (arena coordinates)
			local p = d.CFrame.Position - CENTER
			table.insert(water, { X = p.X, Z = p.Z, R = math.max(d.Size.Y, d.Size.Z) / 2 })
		end
		if d:IsA("BasePart") and d:GetAttribute("EnemyBlocker") then
			-- XZ bounding box of the (possibly rotated) part, in arena coordinates
			local cf, size = d.CFrame, d.Size
			local hx = math.abs(cf.RightVector.X) * size.X / 2 + math.abs(cf.UpVector.X) * size.Y / 2 + math.abs(cf.LookVector.X) * size.Z / 2
			local hz = math.abs(cf.RightVector.Z) * size.X / 2 + math.abs(cf.UpVector.Z) * size.Y / 2 + math.abs(cf.LookVector.Z) * size.Z / 2
			local p = cf.Position - CENTER
			local col = { MinX = p.X - hx, MaxX = p.X + hx, MinZ = p.Z - hz, MaxZ = p.Z + hz, Name = d.Name }
			count += 1
			-- register in every cell it (plus an enemy radius margin) overlaps
			local margin = 8
			for cx = math.floor((col.MinX - margin) / COLLIDER_CELL), math.floor((col.MaxX + margin) / COLLIDER_CELL) do
				for cz = math.floor((col.MinZ - margin) / COLLIDER_CELL), math.floor((col.MaxZ + margin) / COLLIDER_CELL) do
					local key = cx * 4096 + cz
					cells[key] = cells[key] or {}
					table.insert(cells[key], col)
				end
			end
		end
	end
	return { Cell = COLLIDER_CELL, Cells = cells, Count = count, Water = water }
end

function MapBuilder.ExtractRegions(map: Instance)
	local regions = {}
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("SecretRegion") then
			table.insert(regions, { Key = d:GetAttribute("SecretRegion"), CFrame = d.CFrame, Size = d.Size + Vector3.new(0, 8, 0) })
		end
	end
	return regions
end

function MapBuilder:Init(services)
	self.Services = services
	local map = Workspace:FindFirstChild("Map")
	if not map then
		map = Instance.new("Model")
		map.Name = "Map"
		buildArena(map)
		buildLobby(map)
		map.Parent = Workspace
	end
	if not Workspace:FindFirstChild("SpawnPoints") then
		buildSpawns(map)
	end
	applyLighting()
	self.Map = map
	local arena = map:FindFirstChild("Arena") or map
	self.Colliders = MapBuilder.ExtractColliders(arena)
	self.Regions = MapBuilder.ExtractRegions(map)
end

function MapBuilder:Start() end

function MapBuilder:SpawnPoint(name: string): CFrame
	local spawns = Workspace:FindFirstChild("SpawnPoints")
	local p = spawns and spawns:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p.CFrame
	end
	if name == "Lobby" then
		return CFrame.new(LOBBY + STAGE + Vector3.new(0, 0.7, 0))
	end
	return CFrame.new(CENTER + Vector3.new(0, 0.5, 0))
end

-- key of the secret region containing a world position (or nil)
function MapBuilder:RegionAt(position: Vector3): string?
	for _, r in self.Regions do
		local lp = r.CFrame:PointToObjectSpace(position)
		local h = r.Size / 2
		if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
			return r.Key
		end
	end
	return nil
end

return MapBuilder
