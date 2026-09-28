--[[
	WeaponFx - visuals of the hero's abilities, enemy projectiles and telegraphs.

	The server decides every hit; this module only draws what the Frame records describe:
	  Proj / ProjEnd      bolts, arrows, swords, homing missiles, boomerangs (simulated
	                      locally from one record)
	  Fx                  per ability Kind: meteors, fists, lobs, beams, lightning, slashes,
	                      shockwaves, 67 blast... and generic effects (weapon id 0)
	  Zone / ZoneEnd      poison clouds, black holes
	  Clone               the decoy copy of the hero
	  EProj / EProjEnd    enemy projectiles (straight lines, deterministic)
	  Telegraph           circles / dash lines / void zones / laser lines that fill up
	Always-on abilities (auras, fire rings, ice fields, orbits, drones, barrier) are drawn
	from the Loadout every frame, with the same formulas as the server.

	ABILITY SKINS (cosmetic): one colour for every effect, or a rainbow.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local WeaponData = require(Shared.WeaponData)
local Protocol = require(Shared.Protocol)
local CosmeticData = require(Shared.CosmeticData)
local HeroModels = require(Shared.HeroModels)
local GameConfig = require(Shared.GameConfig)

local WeaponFx = {}

local rgb = Color3.fromRGB
local PARK = CFrame.new(0, -400, 0)
local FLAT = CFrame.Angles(0, 0, math.rad(90))
local TAU = math.pi * 2
local GFX = Protocol.Fx

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.CFrame = PARK
	return p
end

local function addTrail(p: BasePart, color: Color3, width: number, life: number)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, width / 2, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -width / 2, 0)
	a1.Parent = p
	local trail = Instance.new("Trail")
	trail.Name = "Trail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = life
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.LightEmission = 0.7
	trail.Parent = p
end

-- part builders by style (pooled)
local BUILD = {
	Bolt = function()
		local p = newPart("Bolt", Vector3.new(0.7, 0.7, 2.2), rgb(120, 190, 255))
		addTrail(p, rgb(255, 255, 255), 0.6, 0.12)
		return p
	end,
	Arrow = function()
		local p = newPart("Arrow", Vector3.new(0.3, 0.3, 3.4), rgb(120, 230, 140))
		addTrail(p, rgb(255, 255, 255), 0.3, 0.12)
		return p
	end,
	Sword = function()
		return newPart("Sword", Vector3.new(0.35, 0.9, 3.2), rgb(220, 230, 255))
	end,
	Missile = function()
		local p = newPart("Missile", Vector3.new(1.2, 1.2, 1.2), rgb(170, 120, 255), nil, Enum.PartType.Ball)
		addTrail(p, rgb(220, 200, 255), 0.9, 0.3)
		return p
	end,
	Rocket = function()
		local p = newPart("Rocket", Vector3.new(0.9, 0.9, 2.4), rgb(255, 120, 60))
		addTrail(p, rgb(255, 200, 120), 0.8, 0.35)
		return p
	end,
	Boomerang = function()
		return newPart("Boomerang", Vector3.new(0.3, 3.6, 3.6), rgb(255, 170, 60), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end,
	Orb = function()
		local p = newPart("Orb", Vector3.new(3.4, 3.4, 3.4), rgb(170, 90, 255), nil, Enum.PartType.Ball)
		addTrail(p, rgb(200, 140, 255), 1.6, 0.2)
		return p
	end,
	Blade = function()
		return newPart("Blade", Vector3.new(0.3, 0.3, 3), rgb(200, 220, 255))
	end,
	Drone = function()
		return newPart("Drone", Vector3.new(1.2, 0.5, 1.2), rgb(120, 200, 255), Enum.Material.SmoothPlastic)
	end,
	EProj = function()
		return newPart("EnemyShot", Vector3.new(2.6, 2.6, 2.6), rgb(255, 60, 90), nil, Enum.PartType.Ball)
	end,
	Beam = function()
		return newPart("Beam", Vector3.new(1, 1, 1), rgb(120, 255, 170))
	end,
	Seg = function()
		return newPart("Seg", Vector3.new(0.6, 0.6, 1), rgb(160, 230, 255))
	end,
	Disc = function()
		return newPart("Disc", Vector3.new(0.2, 1, 1), rgb(255, 60, 70), nil, Enum.PartType.Cylinder)
	end,
	Ball = function()
		return newPart("Ball", Vector3.new(1, 1, 1), rgb(255, 255, 255), nil, Enum.PartType.Ball)
	end,
	Block = function()
		return newPart("Block", Vector3.new(1, 1, 1), rgb(255, 255, 255), Enum.Material.SmoothPlastic)
	end,
}

-- projectile style by ability Kind (and a few keys)
local PROJ_STYLE = { Projectile = "Bolt", Swords = "Sword", Missile = "Missile", Boomerang = "Boomerang", Drone = "Bolt" }
local PROJ_BY_KEY = { Arrow = "Arrow", Rocket = "Rocket", NukeLauncher = "Rocket" }

function WeaponFx:Init(controllers)
	self.C = controllers
	local folder = Instance.new("Folder")
	folder.Name = "RunFx"
	folder.Parent = Workspace
	self.Folder = folder
	self.Free = {}
	self.Projectiles = {}
	self.EProjectiles = {}
	self.Transients = {}
	self.Telegraphs = {}
	self.Zones = {}
	self.Always = {} -- [weapon key] = { Parts, Spec, Kind }
	self.Loadout = nil
	self.CloneModel = nil
end

-- "Fewer effects": ability areas and auras are more see-through (your hero stays visible);
-- enemy telegraphs are never faded (they warn you)
function WeaponFx:Fade(transparency: number): number
	if transparency < 1 and self.C.ClientData:Setting("FewerEffects") == true then
		return math.min(0.97, transparency + GameConfig.Visuals.FewerEffectsFade)
	end
	return transparency
end

function WeaponFx:Take(style: string): BasePart
	local free = self.Free[style]
	local p = free and table.remove(free)
	if not p then
		p = BUILD[style]()
		p.Parent = self.Folder
	end
	p.Transparency = 0
	return p
end

function WeaponFx:Give(style: string, p: BasePart)
	p.CFrame = PARK
	self.Free[style] = self.Free[style] or {}
	table.insert(self.Free[style], p)
end

local function localRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- arena position of the local character (for effects that start "at the player")
function WeaponFx:PlayerXZ(fallbackX: number, fallbackZ: number): (number, number)
	local root = localRoot()
	local center = self.C.RunClient.Center
	if root then
		local x, z = root.Position.X - center.X, root.Position.Z - center.Z
		if (x - fallbackX) ^ 2 + (z - fallbackZ) ^ 2 < 12 * 12 then
			return x, z
		end
	end
	return fallbackX, fallbackZ
end

-- a transient effect: update(t 0..1) each frame, done() at the end
function WeaponFx:Transient(duration: number, update: (number) -> (), done: (() -> ())?)
	table.insert(self.Transients, { T = 0, Duration = duration, Update = update, Done = done })
end

-- the colour of an ability's effects (ABILITY SKIN cosmetic)
function WeaponFx:ColorOf(def): Color3
	local data = self.C.ClientData.Data
	local style = CosmeticData.Style(data and data.Cosmetics and data.Cosmetics.Equipped, "WeaponSkin")
	if style == "Rainbow" then
		return Color3.fromHSV((os.clock() * 0.35) % 1, 0.75, 1)
	end
	local skin = CosmeticData.ById["WeaponSkin." .. style]
	if skin and skin.Color then
		return skin.Color
	end
	return def.Color
end

---------------------------------------------------------------------------
-- loadout: always-on abilities
---------------------------------------------------------------------------
local ALWAYS_KINDS = { Aura = true, FireRing = true, Field = true, Orbit = true, Drone = true, Allies = false }

function WeaponFx:ReleaseAlways(key: string)
	local a = self.Always[key]
	if a then
		for _, entry in a.Parts do
			self:Give(entry[1], entry[2])
		end
		self.Always[key] = nil
	end
end

function WeaponFx:SetLoadout(loadout)
	self.Loadout = loadout
	local keep = {}
	for _, w in loadout.Weapons or {} do
		local def = WeaponData.ByKey[w.Key]
		if def and ALWAYS_KINDS[def.Kind] then
			keep[w.Key] = true
			local a = self.Always[w.Key]
			local count = if def.Kind == "Orbit" or def.Kind == "Drone" then w.Amount else 2
			if not a or #a.Parts ~= count then
				self:ReleaseAlways(w.Key)
				a = { Parts = {}, Kind = def.Kind, Def = def }
				for i = 1, count do
					local style = if def.Kind == "Orbit" then (if w.Key == "OrbitalBlades" then "Blade" else "Orb")
						elseif def.Kind == "Drone" then "Drone"
						else "Disc"
					table.insert(a.Parts, { style, self:Take(style) })
					if def.Kind ~= "Orbit" and def.Kind ~= "Drone" and i == 1 then
						a.Parts[1][2].Transparency = 0.8
					end
				end
				self.Always[w.Key] = a
			end
			a.Spec = w
			local color = self:ColorOf(def)
			for i, entry in a.Parts do
				local p = entry[2]
				p.Color = color
				if def.Kind == "Orbit" and entry[1] == "Orb" then
					local r = w.Radius
					p.Size = Vector3.new(r * 2, r * 2, r * 2)
				elseif def.Kind == "Aura" or def.Kind == "FireRing" or def.Kind == "Field" then
					p.Transparency = self:Fade(if i == 1 then (if def.Kind == "Field" then 0.75 else 0.82) else 0.45)
				end
			end
		end
	end
	for key in self.Always do
		if not keep[key] then
			self:ReleaseAlways(key)
		end
	end
end

---------------------------------------------------------------------------
-- projectiles
---------------------------------------------------------------------------
function WeaponFx:Projectile(id: number, weaponId: number, x: number, z: number, angle: number, speed: number, life: number, target: number)
	local def = WeaponData.ById[weaponId]
	if not def then
		return
	end
	local old = self.Projectiles[id]
	if old then
		self:Give(old.Style, old.Part)
	end
	local style = PROJ_BY_KEY[def.Key] or PROJ_STYLE[def.Kind] or "Bolt"
	local sx, sz = x, z
	if def.Kind ~= "Drone" then
		sx, sz = self:PlayerXZ(x, z)
	end
	local mode = if def.Kind == "Missile" then "Homing" elseif def.Kind == "Boomerang" then "Boomerang" else "Straight"
	local part = self:Take(style)
	local color = self:ColorOf(def)
	part.Color = color
	local trail = part:FindFirstChild("Trail") :: Trail?
	if trail then
		trail.Color = ColorSequence.new(color)
	end
	local base = part:GetAttribute("BaseSize")
	if not base then
		base = part.Size
		part:SetAttribute("BaseSize", base)
	end
	part.Size = if def.Evolution then base * 1.35 else base -- evolved: bigger
	self.Projectiles[id] = {
		Style = style,
		Part = part,
		Mode = mode,
		X = sx,
		Z = sz,
		DX = math.cos(angle),
		DZ = math.sin(angle),
		Speed = speed,
		Life = if mode == "Boomerang" then life * 2 + 2 else life,
		OutTime = life,
		T = 0,
		Target = target,
	}
	if style == "Bolt" or style == "Arrow" then
		self.C.SoundController:Play("Blast", 1 + math.random() * 0.2, 0.5)
	end
end

function WeaponFx:ProjectileEnd(id: number, x: number, z: number, flags: number)
	local p = self.Projectiles[id]
	if p then
		self.Projectiles[id] = nil
		self:Give(p.Style, p.Part)
	end
	if bit32.band(flags, 1) ~= 0 then
		local run = self.C.RunClient
		local pos = run:World(x, z, 1.5)
		local fx = self.C.EffectsController
		fx:Ring(pos, 5, if p then p.Part.Color else rgb(120, 210, 255), 0.35)
		fx:Emit("Smoke", pos, rgb(200, 200, 210), 5)
		self.C.SoundController:Play("Boom", 1.4, 0.4)
	end
end

function WeaponFx:EnemyProjectile(id: number, x: number, z: number, vx: number, vz: number, radius: number, life: number)
	local old = self.EProjectiles[id]
	if old then
		self:Give("EProj", old.Part)
	end
	local part = self:Take("EProj")
	part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	self.EProjectiles[id] = { Part = part, X = x, Z = z, VX = vx, VZ = vz, T0 = self.C.RunClient.FrameT, Life = life }
end

function WeaponFx:EnemyProjectileEnd(id: number)
	local p = self.EProjectiles[id]
	if p then
		self.EProjectiles[id] = nil
		self:Give("EProj", p.Part)
	end
end

---------------------------------------------------------------------------
-- lingering zones (poison clouds, black holes) and the clone
---------------------------------------------------------------------------
function WeaponFx:Zone(id: number, weaponId: number, x: number, z: number, radius: number, duration: number)
	local def = WeaponData.ById[weaponId]
	if not def then
		return
	end
	self:ZoneEnd(id)
	local run = self.C.RunClient
	local pos = run:World(x, z, 0.4)
	local color = self:ColorOf(def)
	local disc = self:Take("Disc")
	local core = self:Take("Ball")
	disc.Color = color
	core.Color = if def.Kind == "Vortex" then rgb(20, 10, 30) else color
	local vortex = def.Kind == "Vortex"
	local zone = { Disc = disc, Core = core, Pos = pos, R = radius, Until = os.clock() + duration, Vortex = vortex, Spin = 0 }
	self.Zones[id] = zone
	if vortex then
		self.C.SoundController:Play("Boom", 0.6, 0.5)
	end
end

function WeaponFx:ZoneEnd(id: number)
	local zone = self.Zones[id]
	if zone then
		self.Zones[id] = nil
		self:Give("Disc", zone.Disc)
		self:Give("Ball", zone.Core)
	end
end

function WeaponFx:Clone(x: number, z: number, duration: number)
	local run = self.C.RunClient
	if self.CloneModel then
		self.CloneModel:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "HeroClone"
	model.Parent = self.Folder
	local parts = HeroModels.Build(run.Hero or "Rookie", CFrame.new(run:World(x, z, 3)), model, { Ring = true })
	for _, p in parts do
		p.Transparency = math.max(p.Transparency, 0.45)
		p.Material = Enum.Material.ForceField
	end
	self.CloneModel = model
	self.C.EffectsController:Ring(run:World(x, z, 0.3), 5, rgb(140, 200, 255), 0.4)
	task.delay(duration, function()
		if self.CloneModel == model then
			self.CloneModel = nil
		end
		model:Destroy()
	end)
end

---------------------------------------------------------------------------
-- telegraphs (enemy / boss attacks)
---------------------------------------------------------------------------
function WeaponFx:Telegraph(shape: number, x: number, z: number, angle: number, size: number, width: number, delay: number)
	local run = self.C.RunClient
	local edge = self:Take("Disc")
	local fill = self:Take("Disc")
	local red = if shape == 3 then rgb(150, 60, 255) else rgb(255, 40, 60)
	edge.Color = red
	fill.Color = red
	edge.Transparency = 0.55
	fill.Transparency = 0.35
	local tele = { Edge = edge, Fill = fill, Shape = shape, T = 0, Delay = math.max(0.1, delay) }
	if shape == 1 or shape == 3 then
		local pos = run:World(x, z, 0.35)
		edge.Size = Vector3.new(0.15, size * 2, size * 2)
		edge.CFrame = CFrame.new(pos) * FLAT
		tele.Update = function(t)
			local r = size * t
			fill.Size = Vector3.new(0.2, r * 2, r * 2)
			fill.CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * FLAT
		end
		if shape == 3 then
			-- after the warning the void zone stays for `width` seconds
			tele.Linger = width
			tele.Pos = pos
			tele.R = size
		end
	else
		-- line from (x, z) along angle
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local base = run:World(x, z, 0.35)
		local look = CFrame.lookAt(base, base + dir)
		edge.Shape = Enum.PartType.Block
		fill.Shape = Enum.PartType.Block
		local w = if shape == 4 then math.max(0.6, width) else width
		edge.Size = Vector3.new(w, 0.15, size)
		edge.CFrame = look * CFrame.new(0, 0, -size / 2)
		tele.Update = function(t)
			if shape == 4 then
				-- laser: full length, grows thicker
				fill.Size = Vector3.new(math.max(0.1, w * t), 0.2, size)
				fill.CFrame = look * CFrame.new(0, 0.05, -size / 2)
			else
				local l = math.max(0.1, size * t)
				fill.Size = Vector3.new(w, 0.2, l)
				fill.CFrame = look * CFrame.new(0, 0.05, -l / 2)
			end
		end
	end
	tele.Update(0)
	table.insert(self.Telegraphs, tele)
end

---------------------------------------------------------------------------
-- one-shot effects
---------------------------------------------------------------------------
function WeaponFx:Bolt(from: Vector3, to: Vector3, color: Color3, thickness: number, duration: number)
	-- zig-zag of 3 segments
	local points = { from }
	for k = 1, 2 do
		local p = from:Lerp(to, k / 3)
		table.insert(points, p + Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 3))
	end
	table.insert(points, to)
	local parts = {}
	for k = 1, 3 do
		local a, b = points[k], points[k + 1]
		local seg = self:Take("Seg")
		seg.Color = color
		seg.Size = Vector3.new(thickness, thickness, (b - a).Magnitude)
		seg.CFrame = CFrame.lookAt((a + b) / 2, b)
		table.insert(parts, seg)
	end
	self:Transient(duration, function(t)
		for _, seg in parts do
			seg.Transparency = t
		end
	end, function()
		for _, seg in parts do
			self:Give("Seg", seg)
		end
	end)
end

function WeaponFx:Beam(x: number, z: number, angle: number, length: number, halfWidth: number, color: Color3, duration: number?)
	local run = self.C.RunClient
	local px, pz = self:PlayerXZ(x, z)
	local base = run:World(px, pz, 2)
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local beam = self:Take("Beam")
	beam.Color = color
	local look = CFrame.lookAt(base, base + dir)
	self:Transient(duration or 0.28, function(t)
		local w = halfWidth * 2 * (1 - t * 0.7)
		beam.Size = Vector3.new(w, w * 0.6, length)
		beam.CFrame = look * CFrame.new(0, 0, -length / 2)
		beam.Transparency = t * 0.9
	end, function()
		self:Give("Beam", beam)
	end)
end

-- something falls from the sky onto (x, z): meteors, fists
function WeaponFx:Drop(x: number, z: number, radius: number, fall: number, color: Color3, style: string, size: number, onLand: (() -> ())?)
	local run = self.C.RunClient
	local ground = run:World(x, z, 0)
	local p = self:Take(style)
	p.Color = color
	p.Size = Vector3.new(size, size, size)
	local fx = self.C.EffectsController
	-- a shadow grows where it lands
	local shadow = self:Take("Disc")
	shadow.Color = rgb(20, 15, 30)
	self:Transient(math.max(0.15, fall), function(t)
		local y = (1 - t * t) * 45 + size / 2
		p.CFrame = CFrame.new(ground + Vector3.new((1 - t) * 8, y, 0)) * CFrame.Angles(t * 3, 0, t * 2)
		shadow.Size = Vector3.new(0.12, radius * 2 * t, radius * 2 * t)
		shadow.CFrame = CFrame.new(ground + Vector3.new(0, 0.3, 0)) * FLAT
		shadow.Transparency = 1 - t * 0.5
	end, function()
		fx:Ring(ground, radius, color, 0.4)
		fx:Emit("Smoke", ground + Vector3.new(0, 1, 0), rgb(210, 200, 190), 8)
		self.C.CameraController:Shake(0.5)
		self.C.SoundController:Play("Hammer")
		self:Give(style, p)
		self:Give("Disc", shadow)
		if onLand then
			onLand()
		end
	end)
end

-- a slash arc in front of the hero
function WeaponFx:Slash(x: number, z: number, angle: number, reach: number, arc: number, color: Color3, big: boolean)
	local run = self.C.RunClient
	local px, pz = self:PlayerXZ(x, z)
	local center = run:World(px, pz, 1.8)
	local n = if arc > 4 then 10 else 5
	local parts = {}
	for i = 1, n do
		local seg = self:Take("Seg")
		seg.Color = color
		table.insert(parts, seg)
	end
	self:Transient(if big then 0.28 else 0.18, function(t)
		local sweep = angle - arc / 2 + arc * math.min(1, t * 1.6)
		for i, seg in parts do
			local a = sweep - (i - 1) * (arc / n) * 0.5
			local r = reach * (0.55 + 0.45 * (i % 2))
			local pos = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			seg.Size = Vector3.new(if big then 1 else 0.6, 0.3, reach * 0.45)
			seg.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a)))
			seg.Transparency = t
		end
	end, function()
		for _, seg in parts do
			self:Give("Seg", seg)
		end
	end)
	if big then
		self.C.EffectsController:Ring(center - Vector3.new(0, 1.5, 0), reach, color, 0.3)
		self.C.CameraController:Shake(0.6)
	end
	self.C.SoundController:Play("Slash", 1 + math.random() * 0.2, 0.6)
end

-- a banana arc: thrown from the hero to (x, z)
function WeaponFx:Lob(x: number, z: number, radius: number, flight: number, color: Color3)
	local run = self.C.RunClient
	local px, pz = self:PlayerXZ(x, z)
	local from = run:World(px, pz, 2)
	local to = run:World(x, z, 0.8)
	local p = self:Take("Ball")
	p.Color = color
	p.Size = Vector3.new(1.4, 1.4, 2.2)
	self:Transient(math.max(0.15, flight), function(t)
		local pos = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * 12, 0)
		p.CFrame = CFrame.new(pos) * CFrame.Angles(t * 8, 0, t * 5)
	end, function()
		self:Give("Ball", p)
		local fx = self.C.EffectsController
		fx:Ring(to, radius, color, 0.4)
		fx:Emit("Big", to + Vector3.new(0, 1, 0), color, 20)
		self.C.SoundController:Play("Boom", 1.1, 0.5)
	end)
end

function WeaponFx:Fx(weaponId: number, x: number, z: number, angle: number, p1: number, p2: number, variant: number)
	local run = self.C.RunClient
	local fx = self.C.EffectsController
	local sound = self.C.SoundController
	local pos = run:World(x, z, 0)

	if weaponId == 0 then
		self:Generic(variant, x, z, pos, angle, p1, p2)
		return
	end

	local def = WeaponData.ById[weaponId]
	if not def then
		return
	end
	local kind = def.Kind
	local color = self:ColorOf(def)
	if kind == "Lob" then
		if variant == 2 then
			fx:Ring(pos, p1, color, 0.3)
			fx:Emit("Poof", pos + Vector3.new(0, 1, 0), color, 8)
		else
			self:Lob(x, z, p1, p2, color)
		end
	elseif kind == "Meteor" then
		self:Drop(x, z, p1, p2, color, "Ball", 3 + p1 * 0.3, function()
			fx:Emit("Big", pos + Vector3.new(0, 1, 0), rgb(255, 140, 40), 20)
		end)
	elseif kind == "Hammer" then
		self:Drop(x, z, p1, p2, color, "Block", 3.2, nil)
	elseif kind == "Slam" or kind == "Blast67" or kind == "Barrier" or kind == "Glitch" or kind == "Stare" then
		local px, pz = self:PlayerXZ(x, z)
		local here = run:World(px, pz, 0)
		fx:Ring(here, p1, color, 0.45)
		if kind == "Blast67" then
			fx:Ring(here, p1 * 0.6, rgb(255, 150, 40), 0.4)
			fx:WorldText(here + Vector3.new(0, 7, 0), "67", rgb(255, 215, 40), 3, 1)
			sound:Play("Blast67")
			self.C.CameraController:Shake(1)
		elseif kind == "Slam" then
			fx:Emit("Smoke", here + Vector3.new(0, 1, 0), rgb(200, 190, 180), 10)
			sound:Play("Slam", 1.1, 0.7)
			self.C.CameraController:Shake(0.7)
		elseif kind == "Stare" then
			fx:Flash(rgb(40, 40, 50), 0.45)
			sound:Play("Freeze")
		else
			sound:Play("Zap", 0.8, 0.6)
		end
	elseif kind == "Lightning" or kind == "Chain" then
		if variant == 0 then
			self:Bolt(pos + Vector3.new(0, 40, 0), pos, color, 0.8, 0.2)
			fx:Ring(pos, p1, color, 0.25)
			sound:Play("Zap")
		else
			local from = pos + Vector3.new(math.cos(angle) * p2, 2, math.sin(angle) * p2)
			self:Bolt(from, pos + Vector3.new(0, 2, 0), color, if def.Evolution then 0.8 else 0.5, 0.2)
			sound:Play("Zap", 1.2, 0.4)
		end
	elseif kind == "Beam" then
		self:Beam(x, z, angle, p1, p2, color, if def.Evolution then 0.4 else 0.28)
		if variant == 1 then
			sound:Play("Beam")
		end
	elseif kind == "Slash" then
		self:Slash(x, z, angle, p1, p2, color, variant == 1)
	elseif kind == "Orbit" then
		fx:Ring(pos, p1, color, 0.35)
		fx:Emit("Big", pos + Vector3.new(0, 2, 0), color, 14)
		sound:Play("Boom", 1.2, 0.5)
	elseif kind == "Chaos" then
		if variant == 1 then
			fx:Ring(pos, p1, rgb(200, 80, 255), 0.4)
			fx:Emit("Big", pos + Vector3.new(0, 2, 0), rgb(200, 80, 255), 20)
			sound:Play("Boom", 1.1, 0.6)
		elseif variant == 2 then
			fx:Ring(pos, p1, rgb(140, 230, 255), 0.6)
			sound:Play("Freeze")
		elseif variant == 3 then
			local from = pos + Vector3.new(math.cos(angle) * p2, 2, math.sin(angle) * p2)
			self:Bolt(from, pos + Vector3.new(0, 2, 0), rgb(220, 120, 255), 0.6, 0.25)
			sound:Play("Zap", 0.7)
		elseif variant == 4 then
			fx:Ring(pos, p1, rgb(255, 140, 200), 0.4)
			fx:WorldText(pos + Vector3.new(0, 5, 0), "SNACK!", rgb(255, 200, 120), 1.6)
		else
			fx:Ring(pos, p1, rgb(255, 255, 255), 0.5)
			sound:Play("VineBoom")
			self.C.CameraController:ZoomPunch(0.8, 0.35)
			self.C.CameraController:Shake(1.2)
		end
	else
		fx:Ring(pos, math.max(2, p1), color, 0.3)
	end
end

-- generic effects (weapon id 0): events, bosses, hero mechanics
function WeaponFx:Generic(variant: number, x: number, z: number, pos: Vector3, angle: number, p1: number, p2: number)
	local fx = self.C.EffectsController
	local sound = self.C.SoundController
	local cam = self.C.CameraController
	if variant == GFX.Slam or variant == GFX.Land then
		fx:Ring(pos, p1, if variant == GFX.Land then rgb(255, 150, 60) else rgb(255, 40, 60), 0.4)
		fx:Emit("Smoke", pos + Vector3.new(0, 1, 0), rgb(120, 90, 90), if p1 > 8 then 16 else 8)
		cam:Shake(if p1 > 8 then 1.3 else 0.5)
		sound:Play("Slam", 1, if p1 > 8 then 1 else 0.6)
	elseif variant == GFX.Bomb then
		fx:Ring(pos, p1, rgb(255, 120, 40), 0.35)
		fx:Emit("Big", pos + Vector3.new(0, 1.5, 0), rgb(255, 140, 50), 25)
		fx:Emit("Smoke", pos + Vector3.new(0, 1, 0), rgb(70, 60, 60), 10)
		sound:Play("Boom", 1, 0.8)
		cam:Shake(0.6)
	elseif variant == GFX.Sweep then
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local base = pos + Vector3.new(0, 1.5, 0)
		local beam = self:Take("Beam")
		beam.Color = rgb(255, 50, 80)
		local look = CFrame.lookAt(base, base + dir)
		self:Transient(0.3, function(t)
			beam.Size = Vector3.new(p2 * (1 - t * 0.6), 1.2, p1)
			beam.CFrame = look * CFrame.new(0, 0, -p1 / 2)
			beam.Transparency = t
		end, function()
			self:Give("Beam", beam)
		end)
		sound:Play("Beam", 0.8, 0.8)
	elseif variant == GFX.Teleport or variant == GFX.GlitchStep then
		fx:Ring(pos, math.max(3, p1), rgb(0, 255, 220), 0.3)
		fx:Poof(x, z, rgb(255, 0, 200), 12)
		sound:Play("Zap", 1.4, 0.6)
	elseif variant == GFX.Hazard then
		fx:Poof(x, z, rgb(150, 60, 255), 4)
	elseif variant == GFX.Thorns then
		fx:Ring(pos, p1, rgb(200, 220, 255), 0.25)
	elseif variant == GFX.Enrage then
		fx:Ring(pos, p1 * 2, rgb(255, 30, 30), 0.8)
		fx:Emit("Big", pos + Vector3.new(0, 3, 0), rgb(255, 60, 60), 40)
	elseif variant == GFX.Revive then
		fx:Ring(pos, p1, rgb(255, 140, 220), 0.6)
	elseif variant == GFX.Nuke then
		fx:Ring(pos, p1, rgb(255, 255, 255), 0.7)
		fx:Emit("Big", pos + Vector3.new(0, 3, 0), rgb(255, 240, 200), 60)
	elseif variant == GFX.Chaos67 then
		self:Bolt(pos + Vector3.new(0, 45, 0), pos, rgb(255, 205, 50), 1.1, 0.25)
		fx:Ring(pos, p1, rgb(170, 90, 255), 0.35)
		sound:Play("Zap", 0.8)
	elseif variant == GFX.Freeze then
		fx:Ring(pos, p1, rgb(140, 220, 255), 0.8)
	elseif variant == GFX.Shrink then
		fx:Ring(pos, p1, rgb(200, 120, 255), 1)
	elseif variant == GFX.SigmaStare then
		fx:Ring(pos, p1, rgb(140, 140, 160), 1.2)
		fx:Flash(rgb(40, 40, 50), 0.6)
	elseif variant == GFX.Blast67 then
		fx:Ring(pos, p1, rgb(255, 215, 40), 0.55)
		fx:WorldText(pos + Vector3.new(0, 7, 0), "67", rgb(255, 215, 40), 3, 1)
		sound:Play("Blast67")
		cam:Shake(1)
	elseif variant == GFX.Evolve then
		fx:Ring(pos, p1, rgb(0, 225, 210), 0.7)
		fx:Ring(pos, p1 * 0.6, rgb(255, 255, 255), 0.5)
		fx:Emit("Big", pos + Vector3.new(0, 3, 0), rgb(0, 225, 210), 50)
		fx:Flash(rgb(0, 225, 210), 0.35)
		cam:ZoomPunch(0.7, 0.8)
		sound:Play("Rare")
	elseif variant == GFX.Event67 then
		-- the event banner and screen effects come with the reliable Event67 event
		fx:Ring(pos, p1, rgb(255, 205, 50), 0.8)
	end
end

---------------------------------------------------------------------------
-- frame update
---------------------------------------------------------------------------
function WeaponFx:Update(dt: number)
	local run = self.C.RunClient
	if not run.Active and next(self.Projectiles) == nil and #self.Transients == 0 then
		return
	end
	local paused = run.Paused
	local center = run.Center
	local ground = run.GroundY
	local root = localRoot()
	local px, pz = 0, 0
	if root then
		px, pz = root.Position.X - center.X, root.Position.Z - center.Z
	end
	local now = run:Now()
	local sdt = if paused then 0 else dt
	local clock = os.clock()

	-- player projectiles
	for id, p in self.Projectiles do
		p.T += sdt
		if p.Mode == "Homing" then
			local target = run.Enemies[p.Target]
			if target then
				local tx, tz = target.RX or target.X1, target.RZ or target.Z1
				local dx, dz = tx - p.X, tz - p.Z
				local d = math.max(0.01, math.sqrt(dx * dx + dz * dz))
				local k = math.min(1, 7 * sdt)
				local nx, nz = p.DX + (dx / d - p.DX) * k, p.DZ + (dz / d - p.DZ) * k
				local len = math.max(0.01, math.sqrt(nx * nx + nz * nz))
				p.DX, p.DZ = nx / len, nz / len
			end
		elseif p.Mode == "Boomerang" and p.T >= p.OutTime then
			local dx, dz = px - p.X, pz - p.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > 0.5 then
				p.DX, p.DZ = dx / d, dz / d
			end
		end
		p.X += p.DX * p.Speed * sdt
		p.Z += p.DZ * p.Speed * sdt
		if p.T > p.Life + 0.3 then
			self.Projectiles[id] = nil
			self:Give(p.Style, p.Part)
		else
			local pos = Vector3.new(center.X + p.X, ground + 2, center.Z + p.Z)
			if p.Style == "Boomerang" then
				p.Part.CFrame = CFrame.new(pos) * CFrame.Angles(0, p.T * 14, math.rad(90))
			else
				p.Part.CFrame = CFrame.lookAt(pos, pos + Vector3.new(p.DX, 0, p.DZ))
			end
		end
	end

	-- enemy projectiles
	for id, p in self.EProjectiles do
		local t = now - p.T0
		if t > p.Life then
			self.EProjectiles[id] = nil
			self:Give("EProj", p.Part)
		else
			t = math.max(0, t)
			p.Part.CFrame = CFrame.new(center.X + p.X + p.VX * t, ground + 2, center.Z + p.Z + p.VZ * t)
		end
	end

	-- always-on abilities (same formulas as the server)
	for key, a in self.Always do
		local spec = a.Spec
		if root and spec then
			local color = if a.Def then self:ColorOf(a.Def) else nil
			if a.Kind == "Orbit" then
				local n = #a.Parts
				for i, entry in a.Parts do
					local ang = now * spec.Speed + (i - 1) * TAU / n
					local op = Vector3.new(center.X + px + math.cos(ang) * spec.Orbit, ground + 2.5, center.Z + pz + math.sin(ang) * spec.Orbit)
					if entry[1] == "Blade" then
						entry[2].CFrame = CFrame.lookAt(op, op + Vector3.new(-math.sin(ang), 0, math.cos(ang)))
					else
						entry[2].CFrame = CFrame.new(op)
					end
					if color and key ~= "Orb67" then
						entry[2].Color = color
					end
				end
			elseif a.Kind == "Drone" then
				local n = #a.Parts
				for i, entry in a.Parts do
					local ang = now * 1.3 + (i - 1) * TAU / n
					entry[2].CFrame = CFrame.new(center.X + px + math.cos(ang) * 3.6, ground + 5 + math.sin(clock * 4 + i) * 0.3, center.Z + pz + math.sin(ang) * 3.6) * CFrame.Angles(0, clock * 6, 0)
				end
			else
				local r = spec.Radius
				local pulse = 1 + math.sin(clock * 5) * 0.03
				local base = CFrame.new(center.X + px, ground + 0.3, center.Z + pz)
				local disc, edge = a.Parts[1][2], a.Parts[2][2]
				disc.Size = Vector3.new(0.1, r * 2 * pulse, r * 2 * pulse)
				disc.CFrame = base * FLAT
				edge.Size = Vector3.new(0.12, r * 2, r * 2)
				edge.CFrame = (base + Vector3.new(0, 0.02, 0)) * FLAT
				edge.Transparency = self:Fade(0.55 + math.sin(clock * (if a.Kind == "FireRing" then 14 else 5)) * 0.15)
				if color then
					disc.Color = color
					edge.Color = color
				end
			end
		end
	end

	-- zones
	for id, zone in self.Zones do
		local left = zone.Until - clock
		if left <= -0.5 then
			self:ZoneEnd(id)
		else
			zone.Spin += dt * (if zone.Vortex then 4 else 0.6)
			local r = zone.R * (1 + math.sin(clock * 3) * 0.04)
			zone.Disc.Size = Vector3.new(0.15, r * 2, r * 2)
			zone.Disc.CFrame = CFrame.new(zone.Pos) * CFrame.Angles(0, zone.Spin, 0) * FLAT
			zone.Disc.Transparency = if left < 0 then 1 else self:Fade(if zone.Vortex then 0.35 else 0.55)
			local cr = if zone.Vortex then r * 0.35 else r * 0.9
			zone.Core.Size = Vector3.new(cr * 2, if zone.Vortex then cr * 2 else cr * 0.8, cr * 2)
			zone.Core.CFrame = CFrame.new(zone.Pos + Vector3.new(0, if zone.Vortex then 2 else 1, 0))
			zone.Core.Transparency = if left < 0 then 1 else self:Fade(if zone.Vortex then 0.1 else 0.7)
		end
	end

	-- barrier bubble (a charge is ready)
	if run.Shield and root then
		if not self.Bubble then
			self.Bubble = self:Take("Ball")
			self.Bubble.Material = Enum.Material.ForceField
			self.Bubble.Color = rgb(120, 220, 255)
		end
		self.Bubble.Size = Vector3.new(7, 7, 7)
		self.Bubble.CFrame = root.CFrame
	elseif self.Bubble then
		self.Bubble.Material = Enum.Material.Neon
		self:Give("Ball", self.Bubble)
		self.Bubble = nil
	end

	-- telegraphs
	local i = 1
	local teles = self.Telegraphs
	while i <= #teles do
		local t = teles[i]
		t.T += sdt
		local frac = t.T / t.Delay
		if frac >= 1 and t.Linger and t.Linger > 0 then
			-- a void zone stays on the ground for a while
			if not t.Lingering then
				t.Lingering = t.T
				t.Fill.Size = Vector3.new(0.25, t.R * 2, t.R * 2)
				t.Fill.CFrame = CFrame.new(t.Pos + Vector3.new(0, 0.05, 0)) * FLAT
				t.Fill.Color = rgb(60, 20, 110)
			end
			local lt = (t.T - t.Lingering) / t.Linger
			t.Fill.Transparency = 0.25 + math.sin(clock * 6) * 0.1 + math.max(0, lt - 0.85) * 4
			if lt >= 1 then
				t.Linger = 0
			end
			i += 1
		elseif frac >= 1 then
			self:Give("Disc", t.Edge)
			self:Give("Disc", t.Fill)
			t.Edge.Shape = Enum.PartType.Cylinder
			t.Fill.Shape = Enum.PartType.Cylinder
			teles[i] = teles[#teles]
			teles[#teles] = nil
		else
			t.Update(frac)
			t.Fill.Transparency = 0.55 - frac * 0.3 + (if frac > 0.75 then math.sin(clock * 40) * 0.15 else 0)
			i += 1
		end
	end

	-- transients
	local tr = self.Transients
	i = 1
	while i <= #tr do
		local t = tr[i]
		t.T += dt
		local frac = math.min(1, t.T / t.Duration)
		t.Update(frac)
		if frac >= 1 then
			tr[i] = tr[#tr]
			tr[#tr] = nil
			if t.Done then
				t.Done()
			end
		else
			i += 1
		end
	end
end

function WeaponFx:Clear()
	for id, p in self.Projectiles do
		self:Give(p.Style, p.Part)
		self.Projectiles[id] = nil
	end
	for id, p in self.EProjectiles do
		self:Give("EProj", p.Part)
		self.EProjectiles[id] = nil
	end
	for id in self.Zones do
		self:ZoneEnd(id)
	end
	for _, t in self.Telegraphs do
		t.Edge.Shape = Enum.PartType.Cylinder
		t.Fill.Shape = Enum.PartType.Cylinder
		self:Give("Disc", t.Edge)
		self:Give("Disc", t.Fill)
	end
	table.clear(self.Telegraphs)
	for _, t in self.Transients do
		if t.Done then
			t.Done()
		end
	end
	table.clear(self.Transients)
	if self.CloneModel then
		self.CloneModel:Destroy()
		self.CloneModel = nil
	end
	if self.Bubble then
		self.Bubble.Material = Enum.Material.Neon
		self:Give("Ball", self.Bubble)
		self.Bubble = nil
	end
	self:SetLoadout({ Weapons = {} })
	self.Loadout = nil
	-- a busy run can park hundreds of parts: keep a few per style for the next run
	for _, free in self.Free do
		for i = #free, 25, -1 do
			free[i]:Destroy()
			free[i] = nil
		end
	end
end

function WeaponFx:Start()
	RunService.RenderStepped:Connect(function(dt)
		self:Update(dt)
	end)
end

return WeaponFx
