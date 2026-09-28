--[[
	Previews - small 3D pictures for the menus (ViewportFrames), no emoji art:
	  Previews.Hero(parent, key, opts?)      the real hero model (shared/HeroModels.lua) with
	                                         an optional skin / hat
	  Previews.Weapon(parent, key, props?)   a tiny model of the ability (by its Kind)
	  Previews.Hat(parent, key, props?)      a head wearing the hat
	  Previews.Enemy(parent, key, props?)    the enemy model (Render/EnemyModels.lua)
	Each returns the ViewportFrame. Parts are anchored and static: cheap to render.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local HeroModels = require(Shared.HeroModels)
local WeaponData = require(Shared.WeaponData)
local EnemyData = require(Shared.EnemyData)
local EnemyModels = require(script.Parent.Parent.Render.EnemyModels)

local Previews = {}

local rgb = Color3.fromRGB
local SKIN = rgb(245, 205, 160)
local UP = CFrame.Angles(0, 0, math.rad(90))
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local NEON = Enum.Material.Neon

local function viewport(parent: Instance, props: { [string]: any }?)
	local vf = Instance.new("ViewportFrame")
	vf.Name = "Preview"
	vf.BackgroundTransparency = 1
	vf.Size = UDim2.fromScale(1, 1)
	vf.Ambient = rgb(170, 168, 190)
	vf.LightColor = rgb(255, 255, 255)
	vf.LightDirection = Vector3.new(-0.6, -1, -0.8)
	if props then
		for k, v in props do
			(vf :: any)[k] = v
		end
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 38
	camera.Parent = vf
	vf.CurrentCamera = camera
	vf.Parent = parent
	return vf, camera
end

local function part(vf: Instance, size: Vector3, color: Color3, cf: CFrame, shape: Enum.PartType?, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.Color = color
	p.CFrame = cf
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = vf
	return p
end

export type HeroOptions = { Skin: string?, Hat: string?, Props: { [string]: any }?, Turn: number? }

-- the hero faces the camera (camera on +Z looking at the origin); feet at y = -3
function Previews.Hero(parent: Instance, key: string, opts: HeroOptions?): ViewportFrame
	local o = opts or {}
	local vf, camera = viewport(parent, o.Props)
	local turn = CFrame.Angles(0, math.rad(180 + (o.Turn or -18)), 0)
	HeroModels.Build(key, turn, vf, { Skin = o.Skin, Hat = o.Hat, Ring = false })
	local top = HeroModels.Top(key) + (if o.Hat and o.Hat ~= "None" then 1.2 else 0)
	local midY = (top - 3) / 2
	local height = top + 3
	camera.CFrame = CFrame.lookAt(Vector3.new(0, midY + 0.6, height * 1.55 + 1.5), Vector3.new(0, midY, 0))
	return vf
end

-- a smooth ellipsoid (a part + a Sphere mesh)
local function ellipsoid(vf: Instance, size: Vector3, color: Color3, cf: CFrame, material: Enum.Material?): Part
	local p = part(vf, size, color, cf, nil, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

function Previews.Hat(parent: Instance, key: string, props: { [string]: any }?): ViewportFrame
	local vf, camera = viewport(parent, props)
	local turn = CFrame.Angles(0, math.rad(168), 0) -- almost facing the camera: glasses and plates read
	local head = HeroModels.PreviewHead
	ellipsoid(vf, head.Size, SKIN, turn * CFrame.new(0, -head.Top, 0))
	-- two small eyes so the head reads as a face (and shades sit where they should)
	for _, side in { -1, 1 } do
		ellipsoid(vf, Vector3.new(0.2, 0.34, 0.1), rgb(24, 22, 30), turn * CFrame.new(side * 0.3, -head.Top + 0.03, -0.77))
	end
	HeroModels.BuildHat(key, turn, vf)
	local tall = 0
	for _, piece in HeroModels.Hats[key] or {} do
		tall = math.max(tall, piece.At.Position.Y + piece.Size.Y / 2)
	end
	local mid = (tall - head.Top * 2) / 2
	camera.CFrame = CFrame.lookAt(Vector3.new(0, mid + 1.1, 5.6 + tall * 0.6), Vector3.new(0, mid, 0))
	return vf
end

function Previews.Enemy(parent: Instance, key: string, props: { [string]: any }?): ViewportFrame
	local vf, camera = viewport(parent, props)
	local def = EnemyData.ByKey[key]
	if not def then
		return vf
	end
	local model = EnemyModels.Build(def, "")
	model:PivotTo(CFrame.Angles(0, math.rad(200), 0))
	model.Parent = vf
	local size = model:GetExtentsSize()
	local r = math.max(size.X, size.Y, size.Z)
	camera.CFrame = CFrame.lookAt(Vector3.new(0, r * 0.35, r * 2 + 1), Vector3.new(0, 0, 0))
	return vf
end

---------------------------------------------------------------------------
-- ability models by Kind (the ability's colour), built around the origin
---------------------------------------------------------------------------
local KINDS = {}

local function bolt(vf, c: Color3)
	local points = { Vector3.new(0.3, 2, 0), Vector3.new(-0.5, 0.6, 0), Vector3.new(0.5, -0.4, 0), Vector3.new(-0.3, -2, 0) }
	for i = 1, 3 do
		local a, b = points[i], points[i + 1]
		part(vf, Vector3.new(0.35, 0.35, (b - a).Magnitude), c, CFrame.lookAt((a + b) / 2, b), nil, NEON)
	end
end

function KINDS.Projectile(vf, c, def)
	if def.Key == "Arrow" then
		local tilt = CFrame.Angles(0, math.rad(90), math.rad(30))
		part(vf, Vector3.new(3.6, 0.2, 0.2), rgb(160, 110, 70), tilt)
		part(vf, Vector3.new(0.7, 0.7, 0.7), c, tilt * CFrame.new(1.9, 0, 0), BALL, NEON)
		part(vf, Vector3.new(0.6, 0.6, 0.1), rgb(240, 240, 240), tilt * CFrame.new(-1.6, 0, 0))
		return
	end
	for i = 0, 2 do
		part(vf, Vector3.new(0.5, 0.5, 1.6), c, CFrame.new(i * 0.9 - 0.9, i * 0.4 - 0.4, 0) * CFrame.Angles(0, math.rad(60), 0), nil, NEON)
	end
end

function KINDS.Missile(vf, c, def)
	if def.Key == "Rocket" or def.Key == "NukeLauncher" then
		local tilt = CFrame.Angles(0, math.rad(90), math.rad(35))
		part(vf, Vector3.new(2.4, 0.8, 0.8), c, tilt, CYL)
		part(vf, Vector3.new(0.8, 0.8, 0.8), rgb(240, 240, 250), tilt * CFrame.new(1.2, 0, 0), BALL)
		part(vf, Vector3.new(0.3, 1.4, 0.15), rgb(255, 80, 90), tilt * CFrame.new(-1, 0, 0))
		return
	end
	part(vf, Vector3.new(1.4, 1.4, 1.4), c, CFrame.new(0.5, 0.3, 0), BALL, NEON)
	part(vf, Vector3.new(0.8, 0.8, 0.8), c, CFrame.new(-0.6, -0.3, 0), BALL, NEON)
	part(vf, Vector3.new(0.4, 0.4, 0.4), c, CFrame.new(-1.3, -0.6, 0), BALL, NEON)
end

function KINDS.Boomerang(vf, c)
	local tilt = CFrame.Angles(math.rad(60), 0, 0)
	part(vf, Vector3.new(2.6, 0.3, 0.7), c, tilt * CFrame.Angles(0, math.rad(30), 0) * CFrame.new(0.9, 0, 0))
	part(vf, Vector3.new(2.6, 0.3, 0.7), c, tilt * CFrame.Angles(0, math.rad(-30), 0) * CFrame.new(-0.9, 0, 0))
end

function KINDS.Lob(vf, c)
	for i = 0, 3 do
		part(vf, Vector3.new(0.8, 0.8, 0.8), c, CFrame.new(math.cos(i * 0.5) * 1.2 - 0.6, math.sin(i * 0.5) * 1.2 - 0.4, 0), BALL)
	end
	part(vf, Vector3.new(0.25, 0.4, 0.25), rgb(90, 70, 40), CFrame.new(1.1, 0.6, 0))
end

local function ring(vf, c: Color3, r: number, y: number?)
	local p = part(vf, Vector3.new(0.12, r, r), c, CFrame.new(0, y or 0, 0) * CFrame.Angles(math.rad(70), 0, 0) * UP, CYL, NEON)
	p.Transparency = 0.15
	return p
end

function KINDS.Aura(vf, c)
	ring(vf, c, 3.4)
	part(vf, Vector3.new(0.9, 0.9, 0.9), c, CFrame.new(0, 0.2, 0), BALL)
end

function KINDS.FireRing(vf, c)
	ring(vf, c, 3.4)
	for i = 1, 6 do
		local a = i * math.pi / 3
		part(vf, Vector3.new(0.5, 0.9, 0.5), rgb(255, 200, 80), CFrame.Angles(math.rad(70), 0, 0) * CFrame.new(math.cos(a) * 1.6, 0.3, math.sin(a) * 1.6), BALL, NEON)
	end
end

function KINDS.Field(vf, c)
	ring(vf, c, 3.6).Transparency = 0.5
	for i = -1, 1 do
		part(vf, Vector3.new(0.5, 1.4 - math.abs(i) * 0.4, 0.5), c, CFrame.new(i * 0.6, 0.2, 0) * CFrame.Angles(0, 0, i * 0.3), nil, NEON)
	end
end

function KINDS.Cloud(vf, c)
	for _, off in { Vector3.new(-0.8, 0, 0), Vector3.new(0.7, 0.2, 0.2), Vector3.new(0, 0.6, -0.3), Vector3.new(0.1, -0.3, 0.4) } do
		part(vf, Vector3.new(1.6, 1.4, 1.6), c, CFrame.new(off), BALL).Transparency = 0.25
	end
end

function KINDS.Meteor(vf, c)
	part(vf, Vector3.new(1.8, 1.8, 1.8), rgb(110, 80, 70), CFrame.new(-0.4, -0.3, 0), BALL, Enum.Material.Slate)
	for i = 1, 3 do
		part(vf, Vector3.new(1.4 - i * 0.3, 1.4 - i * 0.3, 1.4 - i * 0.3), c, CFrame.new(0.3 + i * 0.5, 0.3 + i * 0.5, 0), BALL, NEON)
	end
end

function KINDS.Slam(vf, c)
	ring(vf, c, 3.6)
	ring(vf, c, 2.2)
	part(vf, Vector3.new(1.1, 1.1, 1.1), rgb(160, 150, 150), CFrame.new(0, 0.5, 0), nil)
end

function KINDS.Lightning(vf, c)
	bolt(vf, c)
end
KINDS.Chain = KINDS.Lightning

function KINDS.Beam(vf, c)
	part(vf, Vector3.new(0.5, 0.5, 4), c, CFrame.Angles(math.rad(-10), math.rad(55), 0), nil, NEON)
	part(vf, Vector3.new(0.9, 0.9, 0.9), rgb(255, 255, 255), CFrame.Angles(0, math.rad(55), 0) * CFrame.new(0, 0, 2), BALL, NEON)
end

function KINDS.Vortex(vf, c)
	part(vf, Vector3.new(1.3, 1.3, 1.3), rgb(15, 10, 25), CFrame.new(), BALL)
	ring(vf, c, 3.2)
	ring(vf, c, 2.2).Transparency = 0.5
end

function KINDS.Blast67(vf, c)
	ring(vf, c, 3.4)
	ring(vf, rgb(255, 150, 40), 2.4)
	part(vf, Vector3.new(0.8, 0.8, 0.8), c, CFrame.new(0, 0.2, 0), BALL, NEON)
end

function KINDS.Slash(vf, c)
	local tilt = CFrame.Angles(0, 0, math.rad(-40))
	part(vf, Vector3.new(0.25, 3.6, 0.5), c, tilt * CFrame.new(0, 0.8, 0), nil, NEON)
	part(vf, Vector3.new(0.9, 0.2, 0.9), rgb(255, 205, 60), tilt * CFrame.new(0, -1.1, 0))
	part(vf, Vector3.new(0.3, 1, 0.3), rgb(60, 40, 40), tilt * CFrame.new(0, -1.7, 0))
end

function KINDS.Hammer(vf, c)
	part(vf, Vector3.new(2, 2, 2), c, CFrame.new(0, 0.3, 0), BALL)
	for i = -1, 1 do
		part(vf, Vector3.new(0.5, 0.5, 0.7), c:Lerp(rgb(255, 255, 255), 0.2), CFrame.new(i * 0.55, 1.1, -0.6), BALL)
	end
end

function KINDS.Swords(vf, c)
	for i = -1, 1 do
		local tilt = CFrame.Angles(0, 0, math.rad(i * 30))
		part(vf, Vector3.new(0.2, 2.8, 0.45), c, tilt * CFrame.new(0, 1, 0), nil, NEON)
		part(vf, Vector3.new(0.7, 0.15, 0.3), rgb(255, 205, 60), tilt * CFrame.new(0, -0.45, 0))
	end
end

function KINDS.Orbit(vf, c, def)
	part(vf, Vector3.new(0.8, 0.8, 0.8), rgb(230, 230, 240), CFrame.new(), BALL)
	for i = 1, 3 do
		local a = i * math.pi * 2 / 3
		local at = CFrame.new(math.cos(a) * 1.6, math.sin(a) * 0.5, math.sin(a) * 1.6)
		if def.Key == "OrbitalBlades" then
			part(vf, Vector3.new(0.25, 0.25, 1.4), c, at * CFrame.Angles(0, a, 0), nil, NEON)
		else
			part(vf, Vector3.new(0.9, 0.9, 0.9), c, at, BALL, NEON)
		end
	end
end

function KINDS.Drone(vf, c)
	part(vf, Vector3.new(1.6, 0.6, 1.6), c, CFrame.Angles(math.rad(20), math.rad(30), 0))
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			part(vf, Vector3.new(0.1, 0.9, 0.9), rgb(200, 200, 210), CFrame.Angles(math.rad(20), math.rad(30), 0) * CFrame.new(x * 0.9, 0.4, z * 0.9) * UP, CYL)
		end
	end
	part(vf, Vector3.new(0.4, 0.4, 0.4), rgb(255, 80, 80), CFrame.Angles(math.rad(20), math.rad(30), 0) * CFrame.new(0, 0, -0.8), BALL, NEON)
end

function KINDS.Clone(vf, c)
	part(vf, Vector3.new(1.4, 2.4, 1), c, CFrame.new(0.5, -0.2, 0), nil, Enum.Material.ForceField)
	part(vf, Vector3.new(1, 1, 1), c, CFrame.new(0.5, 1.5, 0), BALL, Enum.Material.ForceField)
	part(vf, Vector3.new(1.4, 2.4, 1), c:Lerp(rgb(255, 255, 255), 0.3), CFrame.new(-0.7, -0.2, 0.3))
	part(vf, Vector3.new(1, 1, 1), c:Lerp(rgb(255, 255, 255), 0.3), CFrame.new(-0.7, 1.5, 0.3), BALL)
end

function KINDS.Allies(vf, c)
	for i = -1, 1 do
		part(vf, Vector3.new(1.1, 1, 1.1), c, CFrame.new(i * 1.1, -0.3 + math.abs(i) * -0.2, math.abs(i) * 0.3), BALL)
		part(vf, Vector3.new(0.35, 0.35, 0.2), rgb(255, 255, 255), CFrame.new(i * 1.1 - 0.2, 0, -0.55), BALL)
		part(vf, Vector3.new(0.35, 0.35, 0.2), rgb(255, 255, 255), CFrame.new(i * 1.1 + 0.2, 0, -0.55), BALL)
	end
end

function KINDS.Barrier(vf, c)
	part(vf, Vector3.new(3, 3, 3), c, CFrame.new(), BALL, Enum.Material.ForceField)
	part(vf, Vector3.new(1, 1, 1), c, CFrame.new(), BALL, NEON)
end

function KINDS.Glitch(vf, c)
	for i, off in { Vector3.new(-0.6, 0.6, 0), Vector3.new(0.6, 0.6, 0), Vector3.new(-0.6, -0.6, 0), Vector3.new(0.6, -0.6, 0), Vector3.new(1.4, 0.2, 0) } do
		part(vf, Vector3.new(1, 1, 1), if i % 2 == 0 then c else rgb(255, 0, 200), CFrame.new(off), nil, NEON)
	end
end

function KINDS.Chaos(vf, c)
	part(vf, Vector3.new(1.8, 1.8, 1.8), c, CFrame.new(), BALL, NEON)
	part(vf, Vector3.new(0.1, 3.2, 3.2), rgb(255, 255, 255), CFrame.Angles(math.rad(60), math.rad(20), 0) * UP, CYL).Transparency = 0.4
end

function KINDS.Stare(vf, c)
	part(vf, Vector3.new(2.2, 1.4, 1), rgb(245, 245, 250), CFrame.new(), BALL)
	part(vf, Vector3.new(0.8, 0.8, 0.5), c, CFrame.new(0, 0, 0.35), BALL, NEON)
	part(vf, Vector3.new(0.4, 0.4, 0.3), rgb(10, 10, 15), CFrame.new(0, 0, 0.55), BALL)
end

function Previews.Weapon(parent: Instance, key: string, props: { [string]: any }?): ViewportFrame
	local vf, camera = viewport(parent, props)
	local def = WeaponData.ByKey[key]
	local color = if def then def.Color else rgb(255, 255, 255)
	local build = def and KINDS[def.Kind]
	if build then
		build(vf, color, def)
	else
		part(vf, Vector3.new(1.6, 1.6, 1.6), color, CFrame.new(), BALL, NEON)
	end
	if def and def.Evolution then
		-- evolved forms sit on a glowing Mythic ring
		local p = part(vf, Vector3.new(0.1, 4.4, 4.4), rgb(0, 225, 210), CFrame.new(0, -1.9, 0) * CFrame.Angles(math.rad(80), 0, 0) * UP, CYL, NEON)
		p.Transparency = 0.2
	end
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, 7), Vector3.new(0, 0, 0))
	return vf
end

return Previews
