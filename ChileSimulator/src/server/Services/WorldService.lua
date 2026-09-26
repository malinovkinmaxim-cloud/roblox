--[[
	WorldService - builds the whole map from code at server start (no manual Studio work
	needed) and owns everything about positions:

	  * 7 zone islands along +X, each with its own look (Tiny Land ... Galaxy)
	  * gates between zones (collide until you unlock the zone; the client opens its own gate)
	  * a giant HEIGHT RULER in every zone: marks are placed exactly where a body of that height
	    ends (BodyShape), so "am I taller than 1K m?" can be read against the world
	  * the cloud layer and the Moon sit at the height a body reaches at that milestone, so
	    "YOUR HEAD REACHED THE CLOUDS" is literally true
	  * egg stands, 4 leaderboards, VIP lounge, spawn
	  * server-side zone verification: position + unlock -> zone multiplier; players found in a
	    locked zone or in the VIP lounge without VIP are moved out

	~700 anchored parts in total, most with CanCollide/CanQuery/CanTouch off and no shadows.
	If Workspace already contains a model named "ChileMap", it is used instead (so the map
	can be hand-decorated in Studio later) - only the logical markers are then required.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneConfig = require(Shared.ZoneConfig)
local PetConfig = require(Shared.PetConfig)
local BodyShape = require(Shared.BodyShape)
local Format = require(Shared.Util.Format)
local Num = require(Shared.Util.Num)

local Logic = script.Parent.Parent.Logic
local Session = require(Logic.Session)
local Guard = require(script.Parent.Parent.Util.Guard)

local WorldService = {}

local L = ZoneConfig.Length
local W = ZoneConfig.Width
local VIP_CENTER = Vector3.new(-40, 0, 105)
local VIP_SIZE = Vector3.new(48, 0, 40)
local SPAWN_POS = Vector3.new(-120, 0, 0)

---------------------------------------------------------------------------
-- tiny builder helpers
---------------------------------------------------------------------------
local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	local collide = props.CanCollide
	if collide == nil then
		collide = false
	end
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
	p.CastShadow = props.CastShadow == true
	for key, value in props do
		if key ~= "CanCollide" and key ~= "CastShadow" and key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = parent
	return p
end

local function ball(parent: Instance, position: Vector3, size: Vector3, color: Color3, props: { [string]: any }?): Part
	local p = part(parent, {
		Size = size,
		CFrame = CFrame.new(position),
		Color = color,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	if props then
		for key, value in props do
			(p :: any)[key] = value
		end
	end
	return p
end

local function cylinder(parent: Instance, from: Vector3, to: Vector3, diameter: number, color: Color3, props: { [string]: any }?): Part
	local delta = to - from
	local length = delta.Magnitude
	-- cylinders extend along their local X axis
	local cf
	if math.abs(delta.Unit.Y) > 0.999 then
		cf = CFrame.new((from + to) / 2) * CFrame.Angles(0, 0, math.rad(90)) -- vertical (lookAt is degenerate)
	else
		cf = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0)
	end
	local p = part(parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = cf,
		Color = color,
	})
	if props then
		for key, value in props do
			(p :: any)[key] = value
		end
	end
	return p
end

local function billboard(adornee: BasePart, text: string, size: UDim2, offset: Vector3, color: Color3?, maxDistance: number?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 400
	gui.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Parent = adornee
	return gui
end

local function rngFor(seed: number)
	return Random.new(seed)
end

---------------------------------------------------------------------------
-- Height ruler (the "shkala rosta")
---------------------------------------------------------------------------
local RULER_MARKS = { 1, 10, 100, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e12, 1e15, 1e18, 1e24, 1e30 }

function WorldService:BuildRuler(parent: Instance, base: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "HeightRuler"
	folder.Parent = parent
	local top = BodyShape.TotalAtMeters(RULER_MARKS[#RULER_MARKS]) + 10
	part(folder, {
		Name = "Pole",
		Size = Vector3.new(1.4, top, 1.4),
		CFrame = CFrame.new(base + Vector3.new(0, top / 2, 0)),
		Color = Color3.fromRGB(255, 255, 255),
		Material = Enum.Material.SmoothPlastic,
	})
	for i, meters in RULER_MARKS do
		local y = BodyShape.TotalAtMeters(meters)
		local size = math.clamp(y * 0.06, 1.2, 30)
		local color = Color3.fromHSV((i / #RULER_MARKS) * 0.8, 0.75, 1)
		local tick = part(folder, {
			Name = "Mark",
			Size = Vector3.new(size * 1.6, math.max(0.3, size * 0.12), size * 1.6),
			CFrame = CFrame.new(base + Vector3.new(0, y, 0)),
			Color = color,
			Material = Enum.Material.Neon,
		})
		billboard(tick, Format.Length(meters * 100), UDim2.new(size * 3.2, 0, size * 1.1, 0), Vector3.new(size * 2.2, 0, 0), color, 5000)
	end
end

---------------------------------------------------------------------------
-- Zone content
---------------------------------------------------------------------------
local function tree(parent: Instance, pos: Vector3, height: number, rng)
	cylinder(parent, pos, pos + Vector3.new(0, height * 0.55, 0), height * 0.12, Color3.fromRGB(120, 80, 50))
	ball(parent, pos + Vector3.new(0, height * 0.7, 0), Vector3.one * height * 0.6, Color3.fromHSV(0.3 + rng:NextNumber(-0.04, 0.04), 0.6, 0.65 + rng:NextNumber(0, 0.15)))
end

local function house(parent: Instance, pos: Vector3, size: Vector3, wall: Color3, roof: Color3)
	part(parent, { Size = size, CFrame = CFrame.new(pos + Vector3.new(0, size.Y / 2, 0)), Color = wall, CanCollide = false })
	local r = Instance.new("WedgePart")
	r.Anchored = true
	r.CanCollide = false
	r.CanQuery = false
	r.CanTouch = false
	r.CastShadow = false
	r.Size = Vector3.new(size.X + 1, size.Y * 0.45, size.Z / 2 + 0.5)
	r.CFrame = CFrame.new(pos + Vector3.new(0, size.Y + r.Size.Y / 2, size.Z / 4))
	r.Color = roof
	r.Parent = parent
	local r2 = r:Clone()
	r2.CFrame = CFrame.new(pos + Vector3.new(0, size.Y + r.Size.Y / 2, -size.Z / 4)) * CFrame.Angles(0, math.pi, 0)
	r2.Parent = parent
	-- door + windows
	part(parent, { Size = Vector3.new(0.3, size.Y * 0.45, size.Z * 0.2), CFrame = CFrame.new(pos + Vector3.new(size.X / 2, size.Y * 0.225, 0)), Color = Color3.fromRGB(110, 70, 40) })
	for _, dz in { -0.3, 0.3 } do
		part(parent, { Size = Vector3.new(0.3, size.Y * 0.22, size.Z * 0.18), CFrame = CFrame.new(pos + Vector3.new(size.X / 2, size.Y * 0.62, size.Z * dz)), Color = Color3.fromRGB(170, 220, 255), Material = Enum.Material.Glass, Transparency = 0.2 })
	end
end

local function skyscraper(parent: Instance, pos: Vector3, size: Vector3, color: Color3, rng)
	part(parent, { Size = size, CFrame = CFrame.new(pos + Vector3.new(0, size.Y / 2, 0)), Color = color, CastShadow = false })
	local stripes = math.floor(size.Y / 12)
	local glow = Color3.fromHSV(rng:NextNumber(0.1, 0.16), 0.5, 1)
	for s = 1, stripes do
		part(parent, {
			Size = Vector3.new(size.X + 0.3, 1.2, size.Z + 0.3),
			CFrame = CFrame.new(pos + Vector3.new(0, s * (size.Y / (stripes + 1)), 0)),
			Color = glow,
			Material = Enum.Material.Neon,
			Transparency = 0.25,
		})
	end
	part(parent, { Size = Vector3.new(size.X * 0.4, 6, size.Z * 0.4), CFrame = CFrame.new(pos + Vector3.new(0, size.Y + 3, 0)), Color = color:Lerp(Color3.new(1, 1, 1), 0.3) })
end

local function cloudPuff(parent: Instance, center: Vector3, scale: number, rng, transparency: number?)
	for _ = 1, 4 do
		local offset = Vector3.new(rng:NextNumber(-1, 1) * scale, rng:NextNumber(-0.2, 0.3) * scale, rng:NextNumber(-1, 1) * scale * 0.6)
		local s = scale * rng:NextNumber(0.9, 1.5)
		ball(parent, center + offset, Vector3.new(s * 1.6, s * 0.7, s * 1.2), Color3.fromRGB(255, 255, 255), {
			Transparency = transparency or 0.08,
		})
	end
end

function WorldService:BuildZoneContent(index: number, folder: Folder, cx: number)
	local zone = ZoneConfig.Zones[index]
	local rng = rngFor(index * 1337)
	local function randomSpot(margin: number): Vector3
		local x = cx + rng:NextNumber(-L / 2 + margin, L / 2 - margin)
		local z = rng:NextNumber(-W / 2 + margin, W / 2 - margin)
		-- keep the central walkway free
		if math.abs(z) < 22 then
			z = if z < 0 then z - 26 else z + 26
		end
		return Vector3.new(x, 0, z)
	end

	if index == 1 then
		-- Tiny Land: giant grass blades, flowers and mushrooms. Everything is bigger than you.
		for _ = 1, 70 do
			local p = randomSpot(8)
			local h = rng:NextNumber(4, 14)
			local blade = Instance.new("WedgePart")
			blade.Anchored = true
			blade.CanCollide = false
			blade.CanQuery = false
			blade.CanTouch = false
			blade.CastShadow = false
			blade.Size = Vector3.new(0.6, h, rng:NextNumber(1.2, 2.2))
			blade.CFrame = CFrame.new(p + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.15, 0.15))
			blade.Color = Color3.fromHSV(0.27 + rng:NextNumber(-0.03, 0.05), 0.7, rng:NextNumber(0.6, 0.85))
			blade.Parent = folder
		end
		local petalColors = { Color3.fromRGB(255, 120, 190), Color3.fromRGB(255, 210, 60), Color3.fromRGB(150, 120, 255), Color3.fromRGB(255, 100, 90) }
		for i = 1, 16 do
			local p = randomSpot(15)
			local h = rng:NextNumber(10, 26)
			cylinder(folder, p, p + Vector3.new(0, h, 0), 0.8, Color3.fromRGB(80, 170, 70))
			local color = petalColors[(i % #petalColors) + 1]
			for a = 0, 4 do
				local angle = a / 5 * math.pi * 2
				ball(folder, p + Vector3.new(math.cos(angle) * 2.6, h, math.sin(angle) * 2.6), Vector3.new(3.6, 1, 3.6), color)
			end
			ball(folder, p + Vector3.new(0, h + 0.3, 0), Vector3.new(2.6, 1.4, 2.6), Color3.fromRGB(255, 230, 90))
		end
		for _ = 1, 6 do
			local p = randomSpot(20)
			local h = rng:NextNumber(5, 9)
			cylinder(folder, p, p + Vector3.new(0, h, 0), 2, Color3.fromRGB(250, 240, 220))
			ball(folder, p + Vector3.new(0, h, 0), Vector3.new(h * 1.3, h * 0.6, h * 1.3), Color3.fromRGB(230, 60, 60))
		end
		for _ = 1, 10 do
			local p = randomSpot(10)
			local s = rng:NextNumber(2, 5)
			ball(folder, p + Vector3.new(0, s * 0.3, 0), Vector3.new(s * 1.4, s, s * 1.2), Color3.fromRGB(150, 150, 160), { CanCollide = false })
		end
	elseif index == 2 then
		-- Normal World: road, houses, trees
		part(folder, { Size = Vector3.new(L, 0.2, 26), CFrame = CFrame.new(cx, 0.1, 0), Color = Color3.fromRGB(60, 60, 66) })
		for x = -L / 2 + 10, L / 2 - 10, 14 do
			part(folder, { Size = Vector3.new(6, 0.25, 0.8), CFrame = CFrame.new(cx + x, 0.12, 0), Color = Color3.fromRGB(250, 240, 200) })
		end
		local walls = { Color3.fromRGB(245, 235, 210), Color3.fromRGB(200, 225, 250), Color3.fromRGB(250, 205, 190), Color3.fromRGB(215, 245, 200) }
		local roofs = { Color3.fromRGB(190, 70, 60), Color3.fromRGB(90, 90, 110), Color3.fromRGB(60, 120, 180) }
		for i = 1, 14 do
			local side = if i % 2 == 0 then 1 else -1
			local x = cx - L / 2 + 25 + (i // 2) * 44
			local size = Vector3.new(rng:NextNumber(12, 16), rng:NextNumber(9, 12), rng:NextNumber(12, 16))
			house(folder, Vector3.new(x, 0, side * rng:NextNumber(40, 110)), size, walls[(i % #walls) + 1], roofs[(i % #roofs) + 1])
		end
		for _ = 1, 26 do
			tree(folder, randomSpot(10), rng:NextNumber(10, 16), rng)
		end
		for x = -L / 2 + 20, L / 2 - 20, 40 do
			for _, z in { -15, 15 } do
				local p = Vector3.new(cx + x, 0, z)
				cylinder(folder, p, p + Vector3.new(0, 9, 0), 0.4, Color3.fromRGB(70, 70, 80))
				ball(folder, p + Vector3.new(0, 9.3, 0), Vector3.one * 1.2, Color3.fromRGB(255, 240, 180), { Material = Enum.Material.Neon })
			end
		end
	elseif index == 3 then
		-- Giant City: skyscrapers up to ~70 studs (a 1M m body is taller than all of them)
		part(folder, { Size = Vector3.new(L, 0.2, 30), CFrame = CFrame.new(cx, 0.1, 0), Color = Color3.fromRGB(45, 45, 52) })
		local colors = { Color3.fromRGB(70, 90, 120), Color3.fromRGB(120, 130, 150), Color3.fromRGB(60, 70, 85), Color3.fromRGB(150, 110, 90), Color3.fromRGB(90, 120, 110) }
		for gx = 0, 5 do
			for _, side in { -1, 1 } do
				for gz = 0, 1 do
					local size = Vector3.new(rng:NextNumber(20, 30), rng:NextNumber(26, 70), rng:NextNumber(20, 30))
					local x = cx - L / 2 + 35 + gx * 58 + rng:NextNumber(-4, 4)
					local z = side * (45 + gz * 55 + rng:NextNumber(-4, 4))
					skyscraper(folder, Vector3.new(x, 0, z), size, colors[rng:NextInteger(1, #colors)], rng)
				end
			end
		end
	elseif index == 4 then
		-- Cloud World: walk through clouds, rainbow
		for _ = 1, 28 do
			local p = randomSpot(15)
			cloudPuff(folder, p + Vector3.new(0, rng:NextNumber(4, 36), 0), rng:NextNumber(5, 11), rng, 0.05)
		end
		local rainbow = { Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 160, 50), Color3.fromRGB(255, 235, 70), Color3.fromRGB(80, 220, 100), Color3.fromRGB(70, 150, 255), Color3.fromRGB(160, 90, 255) }
		for band, color in rainbow do
			local radius = 60 - band * 3
			for s = 0, 17 do
				local a1, a2 = s / 18 * math.pi, (s + 1) / 18 * math.pi
				local p1 = Vector3.new(cx + math.cos(a1) * radius, math.sin(a1) * radius, 120)
				local p2 = Vector3.new(cx + math.cos(a2) * radius, math.sin(a2) * radius, 120)
				cylinder(folder, p1, p2, 3, color, { Material = Enum.Material.Neon, Transparency = 0.15 })
			end
		end
	elseif index == 5 then
		-- Sky World: floating islands
		for _ = 1, 14 do
			local p = randomSpot(25) + Vector3.new(0, rng:NextNumber(18, 90), 0)
			local s = rng:NextNumber(12, 24)
			ball(folder, p - Vector3.new(0, s * 0.35, 0), Vector3.new(s, s * 0.9, s), Color3.fromRGB(140, 110, 90))
			part(folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, s, s), CFrame = CFrame.new(p + Vector3.new(0, s * 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(110, 200, 90) })
			tree(folder, p + Vector3.new(0, s * 0.08, 0), s * 0.5, rng)
		end
		for _ = 1, 10 do
			local p = randomSpot(15)
			cloudPuff(folder, p + Vector3.new(0, rng:NextNumber(2, 10), 0), rng:NextNumber(6, 10), rng, 0.1)
		end
	elseif index == 6 then
		-- Space: craters, rocks, planets, the Moon
		for _ = 1, 18 do
			local p = randomSpot(15)
			local s = rng:NextNumber(8, 22)
			part(folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, s, s), CFrame = CFrame.new(p + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(45, 45, 60) })
			part(folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, s + 2, s + 2), CFrame = CFrame.new(p + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(95, 95, 115) })
		end
		for _ = 1, 16 do
			local p = randomSpot(10)
			local s = rng:NextNumber(2, 7)
			ball(folder, p + Vector3.new(0, s * 0.3, 0), Vector3.new(s * 1.3, s, s * 1.1), Color3.fromRGB(110, 110, 130))
		end
		local moonY = BodyShape.TotalAtMeters(1e9) + 20
		local moon = ball(folder, Vector3.new(cx, moonY, 60), Vector3.one * 44, Color3.fromRGB(225, 225, 235), { Material = Enum.Material.Slate, Name = "Moon" })
		billboard(moon, "🌕 THE MOON (1B m)", UDim2.new(40, 0, 8, 0), Vector3.new(0, 30, 0), Color3.fromRGB(255, 255, 220), 5000)
		ball(folder, Vector3.new(cx - 120, 140, -110), Vector3.one * 60, Color3.fromRGB(70, 130, 230), { Name = "Planet" })
		ball(folder, Vector3.new(cx + 110, 110, -120), Vector3.one * 34, Color3.fromRGB(230, 170, 90), { Name = "Saturn" })
		part(folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 62, 62), CFrame = CFrame.new(cx + 110, 110, -120) * CFrame.Angles(0.3, 0, math.rad(90)), Color = Color3.fromRGB(240, 210, 160), Transparency = 0.3 })
		-- a little rocket
		local rp = Vector3.new(cx + 60, 0, -60)
		cylinder(folder, rp, rp + Vector3.new(0, 26, 0), 7, Color3.fromRGB(240, 240, 245))
		ball(folder, rp + Vector3.new(0, 27, 0), Vector3.new(7, 10, 7), Color3.fromRGB(230, 60, 60))
	elseif index == 7 then
		-- Galaxy: neon grid, crystals, a black hole
		for x = -L / 2 + 20, L / 2 - 20, 30 do
			part(folder, { Size = Vector3.new(0.5, 0.15, W - 10), CFrame = CFrame.new(cx + x, 0.08, 0), Color = zone.Accent, Material = Enum.Material.Neon, Transparency = 0.3 })
		end
		for z = -W / 2 + 20, W / 2 - 20, 30 do
			part(folder, { Size = Vector3.new(L - 10, 0.15, 0.5), CFrame = CFrame.new(cx, 0.08, z), Color = zone.Accent, Material = Enum.Material.Neon, Transparency = 0.3 })
		end
		for _ = 1, 16 do
			local p = randomSpot(15)
			local h = rng:NextNumber(8, 24)
			part(folder, {
				Size = Vector3.new(h * 0.3, h, h * 0.3),
				CFrame = CFrame.new(p + Vector3.new(0, h / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)),
				Color = Color3.fromHSV(rng:NextNumber(0.7, 0.95), 0.6, 1),
				Material = Enum.Material.Neon,
				Transparency = 0.2,
			})
		end
		local hole = ball(folder, Vector3.new(cx, 180, -40), Vector3.one * 50, Color3.new(0, 0, 0), { Name = "BlackHole" })
		for r = 1, 3 do
			part(folder, {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.6, 70 + r * 22, 70 + r * 22),
				CFrame = hole.CFrame * CFrame.Angles(0.35, 0, math.rad(90)),
				Color = Color3.fromHSV(0.8 + r * 0.04, 0.8, 1),
				Material = Enum.Material.Neon,
				Transparency = 0.5 + r * 0.12,
			})
		end
		local sign = part(folder, { Size = Vector3.new(2, 30, 90), CFrame = CFrame.new(cx + L / 2 - 6, 15, 0), Color = Color3.fromRGB(30, 10, 60), CanCollide = true })
		billboard(sign, "TO BE CONTINUED... 👀", UDim2.new(70, 0, 12, 0), Vector3.new(-3, 8, 0), zone.Accent, 2000)
	end
end

---------------------------------------------------------------------------
-- Eggs
---------------------------------------------------------------------------
function WorldService:BuildEgg(parent: Instance, egg, position: Vector3)
	local model = Instance.new("Model")
	model.Name = "Egg_" .. egg.Id
	local base = part(model, {
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 14, 14),
		CFrame = CFrame.new(position + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 60, 75),
		CanCollide = true,
	})
	part(model, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 15, 15),
		CFrame = CFrame.new(position + Vector3.new(0, 2.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = egg.Spots,
		Material = Enum.Material.Neon,
	})
	local shell = ball(model, position + Vector3.new(0, 7, 0), Vector3.new(7, 9, 7), egg.Color, { Name = "Shell" })
	local rng = rngFor(#egg.Id * 97)
	for _ = 1, 7 do
		local theta = rng:NextNumber(0, math.pi * 2)
		local phi = rng:NextNumber(-0.9, 0.9)
		local dir = Vector3.new(math.cos(theta) * math.cos(phi), math.sin(phi) * 1.2, math.sin(theta) * math.cos(phi))
		ball(model, shell.Position + dir * 3.4, Vector3.one * rng:NextNumber(1, 1.8), egg.Spots)
	end
	billboard(shell, egg.Name, UDim2.new(14, 0, 3, 0), Vector3.new(0, 8.5, 0), Color3.new(1, 1, 1), 250)
	billboard(shell, "🪙 " .. Format.Number(egg.Cost), UDim2.new(10, 0, 2.2, 0), Vector3.new(0, 6.2, 0), Color3.fromRGB(255, 220, 80), 250)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HatchPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = egg.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 22
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("EggId", egg.Id)
	prompt.Parent = base
	model:SetAttribute("EggId", egg.Id)
	model.Parent = parent
	self.EggPositions[egg.Id] = position
end

---------------------------------------------------------------------------
-- Leaderboards
---------------------------------------------------------------------------
function WorldService:BuildBoard(parent: Instance, key: string, position: Vector3, facing: Vector3)
	local board = part(parent, {
		Name = "Board_" .. key,
		Size = Vector3.new(40, 30, 1.5),
		CFrame = CFrame.lookAt(position, position + facing),
		Color = Color3.fromRGB(25, 25, 40),
		CanCollide = true,
	})
	for _, dx in { -21, 21 } do
		part(parent, {
			Size = Vector3.new(2, position.Y + 15, 2),
			CFrame = board.CFrame * CFrame.new(dx, -(position.Y + 15) / 2 + 15, 0),
			Color = Color3.fromRGB(255, 200, 60),
			Material = Enum.Material.Neon,
		})
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(800, 600)
	gui.LightInfluence = 0
	gui.MaxDistance = 600
	gui.Parent = board

	local function label(text: string, pos: UDim2, size: UDim2, color: Color3, align: Enum.TextXAlignment?): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = pos
		t.Size = size
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = color
		t.TextXAlignment = align or Enum.TextXAlignment.Center
		t.Text = text
		return t
	end

	local title = label("...", UDim2.fromOffset(20, 12), UDim2.new(1, -40, 0, 70), Color3.fromRGB(255, 215, 70))
	title.Parent = gui
	local rows = {}
	local rankColors = { Color3.fromRGB(255, 215, 60), Color3.fromRGB(210, 220, 235), Color3.fromRGB(230, 150, 90) }
	for i = 1, 10 do
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(40, 40, 60) else Color3.fromRGB(33, 33, 50)
		frame.BorderSizePixel = 0
		frame.Position = UDim2.fromOffset(20, 90 + (i - 1) * 46)
		frame.Size = UDim2.new(1, -40, 0, 42)
		frame.Visible = false
		frame.Parent = gui
		local rank = label("#" .. i, UDim2.fromOffset(8, 4), UDim2.new(0, 70, 1, -8), rankColors[i] or Color3.fromRGB(180, 185, 200))
		rank.Parent = frame
		local name = label("", UDim2.fromOffset(90, 4), UDim2.new(0.55, -90, 1, -8), Color3.new(1, 1, 1), Enum.TextXAlignment.Left)
		name.Parent = frame
		local value = label("", UDim2.new(0.55, 0, 0, 4), UDim2.new(0.45, -12, 1, -8), Color3.fromRGB(120, 255, 150), Enum.TextXAlignment.Right)
		value.Parent = frame
		rows[i] = { Frame = frame, Name = name, Value = value }
	end
	local footer = label("", UDim2.new(0, 20, 1, -44), UDim2.new(1, -40, 0, 34), Color3.fromRGB(150, 155, 180))
	footer.Parent = gui
	self.Boards[key] = { Title = title, Rows = rows, Footer = footer }
end

---------------------------------------------------------------------------
-- Build everything
---------------------------------------------------------------------------
function WorldService:Build()
	local map = Instance.new("Model")
	map.Name = "ChileMap"

	for index, zone in ZoneConfig.Zones do
		local cx = ZoneConfig.CenterX(index)
		local folder = Instance.new("Folder")
		folder.Name = string.format("Zone%d_%s", index, (string.gsub(zone.Name, " ", "")))
		folder.Parent = map

		local ground = part(folder, {
			Name = "Ground",
			Size = Vector3.new(L, 4, W),
			CFrame = CFrame.new(cx, -2, 0),
			Color = zone.Ground,
			Material = if index <= 2 then Enum.Material.Grass elseif index == 3 then Enum.Material.Concrete elseif index == 6 then Enum.Material.Slate else Enum.Material.SmoothPlastic,
			CanCollide = true,
		})
		ground:SetAttribute("Zone", index)
		-- walkway down the middle
		part(folder, {
			Size = Vector3.new(L, 0.1, 16),
			CFrame = CFrame.new(cx, 0.05, 0),
			Color = zone.Ground:Lerp(Color3.new(1, 1, 1), 0.25),
		})
		-- side walls (invisible) so nobody falls off
		for _, side in { -1, 1 } do
			part(folder, { Name = "Edge", Size = Vector3.new(L, 60, 2), CFrame = CFrame.new(cx, 30, side * (W / 2 + 1)), Transparency = 1, CanCollide = true })
		end

		-- zone title arch at the entrance
		local entryX = cx - L / 2 + 6
		for _, side in { -1, 1 } do
			part(folder, { Size = Vector3.new(3, 26, 3), CFrame = CFrame.new(entryX, 13, side * 22), Color = zone.Accent, Material = Enum.Material.Neon })
		end
		local arch = part(folder, { Size = Vector3.new(3, 5, 47), CFrame = CFrame.new(entryX, 27, 0), Color = zone.Accent:Lerp(Color3.new(0, 0, 0), 0.3) })
		billboard(arch, string.format("%d. %s  (x%s)", index, string.upper(zone.Name), Format.Number(zone.Multiplier, 2)), UDim2.new(46, 0, 7, 0), Vector3.new(0, 7, 0), Color3.new(1, 1, 1), 1500)

		-- gate into this zone (not for the first one)
		if index > 1 then
			local gate = part(folder, {
				Name = "Gate",
				Size = Vector3.new(2, 60, W),
				CFrame = CFrame.new(cx - L / 2, 30, 0),
				Color = zone.Accent,
				Material = Enum.Material.ForceField,
				Transparency = 0.35,
				CanCollide = true,
			})
			gate:SetAttribute("Zone", index)
			billboard(gate, "🔒 REACH " .. Format.Length(zone.Unlock * 100), UDim2.new(40, 0, 7, 0), Vector3.new(-2, -12, 0), Color3.new(1, 1, 1), 800).Name = "LockLabel"
			table.insert(self.Gates, gate)
		end

		self:BuildRuler(folder, Vector3.new(entryX + 18, 0, -40))
		self:BuildZoneContent(index, folder, cx)
		self.ZoneSpawns[index] = CFrame.new(entryX + 14, 3, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	end

	-- end wall
	part(map, { Name = "EndWall", Size = Vector3.new(2, 80, W), CFrame = CFrame.new(ZoneConfig.CenterX(#ZoneConfig.Zones) + L / 2 + 1, 40, 0), Transparency = 1, CanCollide = true })
	part(map, { Name = "StartWall", Size = Vector3.new(2, 80, W), CFrame = CFrame.new(-L / 2 - 1, 40, 0), Transparency = 1, CanCollide = true })

	-- global cloud layer: a body of 100M m pokes its head through it
	local clouds = Instance.new("Folder")
	clouds.Name = "CloudLayer"
	clouds.Parent = map
	local cloudY = BodyShape.TotalAtMeters(1e8)
	local rng = rngFor(4242)
	for _ = 1, 26 do
		local x = rng:NextNumber(-L / 2, ZoneConfig.CenterX(5) + L / 2)
		local z = rng:NextNumber(-W / 2, W / 2)
		cloudPuff(clouds, Vector3.new(x, cloudY + rng:NextNumber(-6, 6), z), rng:NextNumber(12, 22), rng, 0.15)
	end

	-- spawn
	local spawnFolder = Instance.new("Folder")
	spawnFolder.Name = "Spawn"
	spawnFolder.Parent = map
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(SPAWN_POS + Vector3.new(0, 0.5, 0))
	spawn.Color = Color3.fromRGB(90, 230, 120)
	spawn.Material = Enum.Material.Neon
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = spawnFolder
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	part(spawnFolder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 30, 30), CFrame = CFrame.new(SPAWN_POS + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 255, 255) })
	self.ZoneSpawns[1] = CFrame.new(SPAWN_POS + Vector3.new(0, 3, 0)) * CFrame.Angles(0, -math.pi / 2, 0)

	-- leaderboards behind the spawn, facing it
	local boards = Instance.new("Folder")
	boards.Name = "Leaderboards"
	boards.Parent = map
	local boardX = -L / 2 + 16
	for i, key in { "Tallest", "Live", "Rebirths", "Taps" } do
		local z = -105 + (i - 1) * 70
		self:BuildBoard(boards, key, Vector3.new(boardX, 17, z), Vector3.new(1, 0, 0))
	end

	-- eggs
	local eggs = Instance.new("Folder")
	eggs.Name = "Eggs"
	eggs.Parent = map
	for _, egg in PetConfig.Eggs do
		local cx = ZoneConfig.CenterX(egg.Zone)
		self:BuildEgg(eggs, egg, Vector3.new(cx - 60, 0, -62))
	end

	-- VIP lounge
	local vip = Instance.new("Folder")
	vip.Name = "VIPLounge"
	vip.Parent = map
	part(vip, { Size = Vector3.new(VIP_SIZE.X, 0.4, VIP_SIZE.Z), CFrame = CFrame.new(VIP_CENTER + Vector3.new(0, 0.2, 0)), Color = Color3.fromRGB(255, 200, 50), Material = Enum.Material.Neon, Transparency = 0.2 })
	for _, wall in {
		{ Vector3.new(0, 6, VIP_SIZE.Z / 2), Vector3.new(VIP_SIZE.X, 12, 1) },
		{ Vector3.new(-VIP_SIZE.X / 2, 6, 0), Vector3.new(1, 12, VIP_SIZE.Z) },
		{ Vector3.new(VIP_SIZE.X / 2, 6, 0), Vector3.new(1, 12, VIP_SIZE.Z) },
	} do
		part(vip, { Size = wall[2], CFrame = CFrame.new(VIP_CENTER + wall[1]), Color = Color3.fromRGB(255, 215, 90), Material = Enum.Material.Glass, Transparency = 0.5, CanCollide = true })
	end
	local door = part(vip, {
		Name = "VIPDoor",
		Size = Vector3.new(VIP_SIZE.X, 12, 1),
		CFrame = CFrame.new(VIP_CENTER + Vector3.new(0, 6, -VIP_SIZE.Z / 2)),
		Color = Color3.fromRGB(255, 200, 40),
		Material = Enum.Material.ForceField,
		Transparency = 0.3,
		CanCollide = true,
	})
	billboard(door, "👑 VIP LOUNGE  (+20% growth)", UDim2.new(34, 0, 5, 0), Vector3.new(0, 10, 0), Color3.fromRGB(255, 220, 80), 400)
	self.VIPDoor = door

	map.Parent = Workspace
	return map
end

---------------------------------------------------------------------------
-- Chest
---------------------------------------------------------------------------
function WorldService:BuildChest(position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "TreasureChest"
	local body = part(model, { Size = Vector3.new(6, 4, 4), CFrame = CFrame.new(position + Vector3.new(0, 2, 0)), Color = Color3.fromRGB(140, 85, 40), Material = Enum.Material.Wood })
	part(model, { Size = Vector3.new(6.2, 1.6, 4.2), CFrame = CFrame.new(position + Vector3.new(0, 4.6, 0)), Color = Color3.fromRGB(120, 70, 30), Material = Enum.Material.Wood })
	part(model, { Size = Vector3.new(6.4, 0.6, 4.4), CFrame = CFrame.new(position + Vector3.new(0, 3.9, 0)), Color = Color3.fromRGB(255, 205, 60), Material = Enum.Material.Neon })
	part(model, { Size = Vector3.new(1, 1.2, 0.4), CFrame = CFrame.new(position + Vector3.new(0, 3.6, -2.2)), Color = Color3.fromRGB(255, 225, 90), Material = Enum.Material.Neon })
	cylinder(model, position, position + Vector3.new(0, 400, 0), 3, Color3.fromRGB(255, 220, 80), { Material = Enum.Material.Neon, Transparency = 0.55 })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 90)
	light.Range = 20
	light.Brightness = 3
	light.Parent = body
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
	sparkles.Rate = 12
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Speed = NumberRange.new(3, 6)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new(0.6, 0)
	sparkles.LightEmission = 1
	sparkles.Parent = body
	billboard(body, "🎁 CHEST!", UDim2.new(12, 0, 4, 0), Vector3.new(0, 7, 0), Color3.fromRGB(255, 230, 90), 2000)
	model.Parent = Workspace
	return model
end

---------------------------------------------------------------------------
-- Positions / zones
---------------------------------------------------------------------------
function WorldService:RootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

function WorldService:EggPosition(eggId: string): Vector3?
	return self.EggPositions[eggId]
end

function WorldService:GetBoard(key: string)
	return self.Boards[key]
end

function WorldService:InVIPArea(position: Vector3): boolean
	local d = position - VIP_CENTER
	return math.abs(d.X) <= VIP_SIZE.X / 2 and math.abs(d.Z) <= VIP_SIZE.Z / 2
end

function WorldService:Teleport(player: Player, zone: number)
	local character = player.Character
	local cf = self.ZoneSpawns[zone]
	if character and cf then
		character:PivotTo(cf)
	end
end

-- Server truth for "which zone multiplier applies": position-based, but never above what the
-- player unlocked. Players inside a locked zone (exploit / glitch) are moved back.
function WorldService:ZoneFor(player: Player, session): number
	local pos = self:RootPosition(player)
	local unlocked = ZoneConfig.HighestUnlocked(session.Data.BestHeight)
	if not pos then
		session.InVIPArea = false
		return math.min(session.ZoneIndex, unlocked)
	end
	local zone = ZoneConfig.IndexFromX(pos.X)
	if zone > unlocked then
		self:Teleport(player, unlocked)
		Session.Notify(session, "Error", "🔒 Reach " .. Format.Length(ZoneConfig.Zones[zone].Unlock * 100) .. " to enter " .. ZoneConfig.Zones[zone].Name)
		zone = unlocked
	end
	local inVip = self:InVIPArea(pos)
	if inVip and not session.Passes.VIP then
		self:Teleport(player, 1)
		inVip = false
	end
	if inVip ~= (session.InVIPArea == true) then
		session.InVIPArea = inVip
		Session.MarkDirty(session, "Rates")
	end
	return zone
end

function WorldService:Init(services)
	self.Services = services
	self.EggPositions = {}
	self.Boards = {}
	self.Gates = {}
	self.ZoneSpawns = {}
	self:Build()
end

function WorldService:Start()
	Guard.On("TeleportZone", 1, function(session, player, zone)
		local index = Num.ValidInt(zone, 1, #ZoneConfig.Zones)
		if not index then
			return
		end
		if index > ZoneConfig.HighestUnlocked(session.Data.BestHeight) then
			Session.Notify(session, "Error", "🔒 Reach " .. Format.Length(ZoneConfig.Zones[index].Unlock * 100) .. " first!")
			return
		end
		self:Teleport(player, index)
		session.ZoneIndex = index
		session.AttrDirty = true
		Session.MarkDirty(session, "Rates")
		Session.Effect(session, "Teleported", { Zone = index })
	end)
end

return WorldService
