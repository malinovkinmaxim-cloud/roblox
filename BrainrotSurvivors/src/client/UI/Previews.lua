--[[
	Previews - small 3D pictures for the menus (ViewportFrames), instead of emoji:
	  Previews.Character(parent, key, hatKey?, props?)   a blocky survivor wearing its look + hat
	  Previews.Weapon(parent, key, props?)               a tiny model of the weapon / effect
	  Previews.Hat(parent, key, props?)                  a head wearing the hat
	Each returns the ViewportFrame. Parts are anchored and static: cheap to render.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Looks = require(Shared.Looks)
local CharacterData = require(Shared.CharacterData)
local WeaponData = require(Shared.WeaponData)

local Previews = {}

local rgb = Color3.fromRGB
local SKIN = rgb(245, 205, 160)
local UP = CFrame.Angles(0, 0, math.rad(90))

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

local function face(head: BasePart)
	local decal = Instance.new("Decal")
	decal.Texture = "rbxasset://textures/face.png"
	decal.Face = Enum.NormalId.Front
	decal.Parent = head
end

-- the figure faces the camera (camera looks along -Z towards the origin from +Z)
function Previews.Character(parent: Instance, key: string, hatKey: string?, props: { [string]: any }?): ViewportFrame
	local vf, camera = viewport(parent, props)
	local def = CharacterData.ByKey[key]
	local shirt = if def then def.Color else rgb(120, 220, 90)
	local turn = CFrame.Angles(0, math.rad(180 - 18), 0) -- front towards the camera, slightly turned
	local function at(x: number, y: number, z: number): CFrame
		return turn * CFrame.new(x, y, z)
	end
	part(vf, Vector3.new(0.95, 2, 1), rgb(48, 52, 70), at(-0.5, -2, 0))
	part(vf, Vector3.new(0.95, 2, 1), rgb(48, 52, 70), at(0.5, -2, 0))
	part(vf, Vector3.new(2, 2, 1), shirt, at(0, 0, 0))
	part(vf, Vector3.new(0.95, 2, 1), SKIN, at(-1.5, 0, 0))
	part(vf, Vector3.new(0.95, 2, 1), SKIN, at(1.5, 0, 0))
	local head = part(vf, Vector3.new(1.2, 1.2, 1.2), SKIN, at(0, 1.6, 0))
	face(head)
	Looks.Build(Looks.Characters[key] or Looks.Characters.Goober, head, vf, false)
	if hatKey and Looks.Hats[hatKey] then
		Looks.Build(Looks.Hats[hatKey], head, vf, false)
	end
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.9, 9.5), Vector3.new(0, 0.2, 0))
	return vf
end

function Previews.Hat(parent: Instance, key: string, props: { [string]: any }?): ViewportFrame
	local vf, camera = viewport(parent, props)
	local head = part(vf, Vector3.new(1.2, 1.2, 1.2), SKIN, CFrame.Angles(0, math.rad(160), 0))
	face(head)
	Looks.Build(Looks.Hats[key] or {}, head, vf, false)
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, 5.2), Vector3.new(0, 0.55, 0))
	return vf
end

-- weapon models, built around the origin
local WEAPONS = {}

function WEAPONS.BrainBlast(vf, c)
	part(vf, Vector3.new(1.6, 1.6, 1.6), c, CFrame.new(0.6, 0.3, 0), Enum.PartType.Ball, Enum.Material.Neon)
	part(vf, Vector3.new(0.9, 0.9, 0.9), c, CFrame.new(-0.6, -0.2, 0), Enum.PartType.Ball, Enum.Material.Neon)
	part(vf, Vector3.new(0.5, 0.5, 0.5), c, CFrame.new(-1.4, -0.55, 0), Enum.PartType.Ball, Enum.Material.Neon)
end

function WEAPONS.Orb67(vf, c)
	part(vf, Vector3.new(0.8, 0.8, 0.8), rgb(230, 230, 240), CFrame.new(), Enum.PartType.Ball)
	for i = 1, 3 do
		local a = i * math.pi * 2 / 3
		part(vf, Vector3.new(0.9, 0.9, 0.9), c, CFrame.new(math.cos(a) * 1.6, math.sin(a) * 0.5, math.sin(a) * 1.6), Enum.PartType.Ball, Enum.Material.Neon)
	end
end

function WEAPONS.SigmaAura(vf, c)
	part(vf, Vector3.new(0.12, 3.4, 3.4), c, CFrame.Angles(math.rad(70), 0, 0) * UP, Enum.PartType.Cylinder, Enum.Material.Neon).Transparency = 0.1
	part(vf, Vector3.new(0.1, 2.6, 2.6), rgb(30, 28, 40), CFrame.new(0, 0.02, 0) * CFrame.Angles(math.rad(70), 0, 0) * UP, Enum.PartType.Cylinder)
	part(vf, Vector3.new(0.9, 0.9, 0.9), c, CFrame.new(0, 0.2, 0), Enum.PartType.Ball)
end

local function hammer(vf, headColor: Color3, scale: number)
	local tilt = CFrame.Angles(0, 0, math.rad(-35))
	part(vf, Vector3.new(0.35, 3, 0.35) * scale, rgb(150, 100, 60), tilt * CFrame.new(0, -0.6 * scale, 0))
	part(vf, Vector3.new(1.9, 1.1, 1.1) * scale, headColor, tilt * CFrame.new(0, 1.1 * scale, 0))
end

function WEAPONS.GoofyHammer(vf, c)
	hammer(vf, c, 1)
end

function WEAPONS.BanHammer(vf, c)
	hammer(vf, c, 1.1)
	part(vf, Vector3.new(0.12, 1.2, 1.2), rgb(255, 255, 255), CFrame.Angles(0, 0, math.rad(-35)) * CFrame.new(0, 1.1 * 1.1, -0.62) * CFrame.Angles(0, math.rad(90), 0) * UP, Enum.PartType.Cylinder)
end

function WEAPONS.NPCMissile(vf, c)
	local tilt = CFrame.Angles(0, math.rad(90), math.rad(35))
	part(vf, Vector3.new(2.4, 0.8, 0.8), c, tilt, Enum.PartType.Cylinder)
	part(vf, Vector3.new(0.8, 0.8, 0.8), rgb(240, 240, 250), tilt * CFrame.new(1.2, 0, 0), Enum.PartType.Ball)
	part(vf, Vector3.new(0.3, 1.4, 0.15), rgb(255, 80, 90), tilt * CFrame.new(-1, 0, 0))
	part(vf, Vector3.new(0.3, 0.15, 1.4), rgb(255, 80, 90), tilt * CFrame.new(-1, 0, 0))
end

function WEAPONS.BrainrotBeam(vf, c)
	part(vf, Vector3.new(0.5, 0.5, 4), c, CFrame.Angles(math.rad(-10), math.rad(55), 0), nil, Enum.Material.Neon)
	part(vf, Vector3.new(0.9, 0.9, 0.9), rgb(255, 255, 255), CFrame.Angles(0, math.rad(55), 0) * CFrame.new(0, 0, 2), Enum.PartType.Ball, Enum.Material.Neon)
end

function WEAPONS.PizzaDisc(vf, c)
	local tilt = CFrame.Angles(math.rad(60), 0, 0) * UP
	part(vf, Vector3.new(0.3, 3, 3), c, tilt, Enum.PartType.Cylinder)
	for i = 1, 4 do
		local a = i * 1.6
		part(vf, Vector3.new(0.35, 0.6, 0.6), rgb(200, 40, 40), tilt * CFrame.new(0.05, math.cos(a) * 0.8, math.sin(a) * 0.8), Enum.PartType.Cylinder)
	end
end

local function bolt(vf, c: Color3)
	local points = { Vector3.new(0.3, 2, 0), Vector3.new(-0.5, 0.6, 0), Vector3.new(0.5, -0.4, 0), Vector3.new(-0.3, -2, 0) }
	for i = 1, 3 do
		local a, b = points[i], points[i + 1]
		part(vf, Vector3.new(0.35, 0.35, (b - a).Magnitude), c, CFrame.lookAt((a + b) / 2, b), nil, Enum.Material.Neon)
	end
end

function WEAPONS.ZapZap(vf, c)
	bolt(vf, c)
end

function WEAPONS.ChaosOrb(vf, c)
	part(vf, Vector3.new(1.8, 1.8, 1.8), c, CFrame.new(), Enum.PartType.Ball, Enum.Material.Neon)
	part(vf, Vector3.new(0.1, 3.2, 3.2), rgb(255, 255, 255), CFrame.Angles(math.rad(60), math.rad(20), 0) * UP, Enum.PartType.Cylinder).Transparency = 0.4
end

function WEAPONS.Blast67(vf, c)
	for i, r in { 3.4, 2.4 } do
		part(vf, Vector3.new(0.12, r, r), if i == 1 then c else rgb(255, 150, 40), CFrame.Angles(math.rad(70), 0, 0) * UP, Enum.PartType.Cylinder, Enum.Material.Neon)
	end
	part(vf, Vector3.new(0.8, 0.8, 0.8), c, CFrame.new(0, 0.2, 0), Enum.PartType.Ball, Enum.Material.Neon)
end

function WEAPONS.FinalAura(vf, c)
	for i = 1, 10 do
		local a = i * math.pi * 2 / 10
		part(vf, Vector3.new(0.45, 0.45, 0.45), c, CFrame.Angles(math.rad(70), 0, 0) * CFrame.new(math.cos(a) * 1.6, 0, math.sin(a) * 1.6), Enum.PartType.Ball, Enum.Material.Neon)
	end
	for i = -1, 1 do
		part(vf, Vector3.new(0.3, 0.7, 0.3), c, CFrame.new(i * 0.45, 0.4 + (if i == 0 then 0.15 else 0), 0), nil, Enum.Material.Neon)
	end
	part(vf, Vector3.new(1.4, 0.3, 0.5), c, CFrame.new(0, 0, 0), nil, Enum.Material.Neon)
end

function Previews.Weapon(parent: Instance, key: string, props: { [string]: any }?): ViewportFrame
	local vf, camera = viewport(parent, props)
	local def = WeaponData.ByKey[key]
	local color = if def then def.Color else rgb(255, 255, 255)
	local build = WEAPONS[key]
	if build then
		build(vf, color)
	else
		part(vf, Vector3.new(1.6, 1.6, 1.6), color, CFrame.new(), Enum.PartType.Ball, Enum.Material.Neon)
	end
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, 7), Vector3.new(0, 0, 0))
	return vf
end

return Previews
