--[[
	WeaponFx - visuals of the player's weapons, enemy projectiles and boss telegraphs.

	The server decides every hit; this module only draws what the Frame records describe:
	  Proj / ProjEnd      blasts, homing missiles, boomerang pizzas (simulated locally from one record)
	  Fx                  hammers, beams, lightning, slams, chaos, 67 blast, generic effects
	  EProj / EProjEnd    enemy projectiles (straight lines, deterministic)
	  Telegraph           red circles / lines that fill up before a boss attack lands
	Always-on weapons (67 Orb, auras) are drawn from the loadout every frame.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local WeaponData = require(Shared.WeaponData)
local Protocol = require(Shared.Protocol)

local WeaponFx = {}

local rgb = Color3.fromRGB
local PARK = CFrame.new(0, -400, 0)
local FLAT = CFrame.Angles(0, 0, math.rad(90))
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
	Blast = function()
		local p = newPart("Blast", Vector3.new(1.6, 1.6, 1.6), rgb(255, 110, 200), nil, Enum.PartType.Ball)
		addTrail(p, rgb(255, 110, 200), 1.2, 0.18)
		return p
	end,
	Missile = function()
		local p = newPart("Missile", Vector3.new(0.8, 0.8, 2.2), rgb(90, 200, 255))
		addTrail(p, rgb(200, 230, 255), 0.7, 0.3)
		return p
	end,
	Pizza = function()
		local p = newPart("Pizza", Vector3.new(0.4, 4.4, 4.4), rgb(255, 185, 60), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		return p
	end,
	Orb = function()
		local p = newPart("Orb", Vector3.new(3.4, 3.4, 3.4), rgb(170, 90, 255), nil, Enum.PartType.Ball)
		addTrail(p, rgb(200, 140, 255), 1.6, 0.2)
		return p
	end,
	EProj = function()
		return newPart("EnemyShot", Vector3.new(2.6, 2.6, 2.6), rgb(255, 60, 90), nil, Enum.PartType.Ball)
	end,
	Beam = function()
		return newPart("Beam", Vector3.new(1, 1, 1), rgb(120, 255, 170))
	end,
	Bolt = function()
		return newPart("Bolt", Vector3.new(0.6, 0.6, 1), rgb(160, 230, 255))
	end,
	Disc = function()
		return newPart("Disc", Vector3.new(0.2, 1, 1), rgb(255, 60, 70), nil, Enum.PartType.Cylinder)
	end,
	Block = function()
		return newPart("Block", Vector3.new(1, 1, 1), rgb(255, 255, 255), Enum.Material.SmoothPlastic)
	end,
}

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
	self.Orbs = {}
	self.Auras = {}
	self.Loadout = nil
end

function WeaponFx:Take(style: string): BasePart
	local free = self.Free[style]
	local p = free and table.remove(free)
	if not p then
		p = BUILD[style]()
		p.Parent = self.Folder
	end
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

---------------------------------------------------------------------------
-- loadout (always-on weapons)
---------------------------------------------------------------------------
function WeaponFx:SetLoadout(loadout)
	self.Loadout = loadout
	self.OrbSpec = nil
	self.AuraSpecs = {}
	for _, w in loadout.Weapons do
		if w.Key == "Orb67" then
			self.OrbSpec = w
		elseif w.Key == "SigmaAura" then
			table.insert(self.AuraSpecs, { Key = w.Key, Radius = w.Radius, Color = rgb(255, 205, 60), Mog = loadout.Mog })
		elseif w.Key == "FinalAura" then
			table.insert(self.AuraSpecs, { Key = w.Key, Radius = w.Radius, Color = rgb(255, 240, 150) })
		end
	end
	-- orbs
	local want = if self.OrbSpec then self.OrbSpec.Amount else 0
	while #self.Orbs < want do
		table.insert(self.Orbs, self:Take("Orb"))
	end
	while #self.Orbs > want do
		self:Give("Orb", table.remove(self.Orbs) :: BasePart)
	end
	if self.OrbSpec then
		local r = 1.7 * (self.OrbSpec.Radius / 1.7)
		for _, orb in self.Orbs do
			orb.Size = Vector3.new(r * 2, r * 2, r * 2)
			orb.Color = if self.OrbSpec.Awakened then rgb(255, 205, 60) else rgb(170, 90, 255)
		end
	end
	-- auras
	for key, aura in self.Auras do
		local keep = false
		for _, spec in self.AuraSpecs do
			if spec.Key == key then
				keep = true
			end
		end
		if not keep then
			self:Give("Disc", aura.Disc)
			self:Give("Disc", aura.Edge)
			self.Auras[key] = nil
		end
	end
	for _, spec in self.AuraSpecs do
		local aura = self.Auras[spec.Key]
		if not aura then
			aura = { Disc = self:Take("Disc"), Edge = self:Take("Disc") }
			self.Auras[spec.Key] = aura
		end
		aura.Spec = spec
		aura.Disc.Color = spec.Color
		aura.Disc.Transparency = 0.82
		aura.Edge.Color = spec.Color
		aura.Edge.Transparency = 0.45
	end
end

---------------------------------------------------------------------------
-- projectiles
---------------------------------------------------------------------------
local STYLE_BY_WEAPON = { BrainBlast = "Blast", NPCMissile = "Missile", PizzaDisc = "Pizza" }

function WeaponFx:Projectile(id: number, weaponId: number, x: number, z: number, angle: number, speed: number, life: number, target: number)
	local def = WeaponData.ById[weaponId]
	if not def then
		return
	end
	local old = self.Projectiles[id]
	if old then
		self:Give(old.Style, old.Part)
	end
	local style = STYLE_BY_WEAPON[def.Key] or "Blast"
	local sx, sz = self:PlayerXZ(x, z)
	local mode = if def.Kind == "Missile" then "Homing" elseif def.Kind == "Boomerang" then "Boomerang" else "Straight"
	local p = {
		Style = style,
		Part = self:Take(style),
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
	self.Projectiles[id] = p
	if style == "Blast" then
		self.C.SoundController:Play("Blast", 1 + math.random() * 0.2)
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
		fx:Ring(pos, 5, rgb(120, 210, 255), 0.35)
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
-- telegraphs (boss attacks)
---------------------------------------------------------------------------
function WeaponFx:Telegraph(shape: number, x: number, z: number, angle: number, size: number, width: number, delay: number)
	local run = self.C.RunClient
	local edge = self:Take("Disc")
	local fill = self:Take("Disc")
	edge.Color = rgb(255, 40, 60)
	fill.Color = rgb(255, 40, 60)
	edge.Transparency = 0.55
	fill.Transparency = 0.35
	local tele = { Edge = edge, Fill = fill, Shape = shape, T = 0, Delay = math.max(0.1, delay) }
	if shape == 1 then
		local pos = run:World(x, z, 0.35)
		edge.Size = Vector3.new(0.15, size * 2, size * 2)
		edge.CFrame = CFrame.new(pos) * FLAT
		tele.Update = function(t)
			local r = size * t
			fill.Size = Vector3.new(0.2, r * 2, r * 2)
			fill.CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * FLAT
		end
	else
		-- line from (x, z) along angle
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local base = run:World(x, z, 0.35)
		local look = CFrame.lookAt(base, base + dir)
		edge.Shape = Enum.PartType.Block
		fill.Shape = Enum.PartType.Block
		edge.Size = Vector3.new(width, 0.15, size)
		edge.CFrame = look * CFrame.new(0, 0, -size / 2)
		tele.Update = function(t)
			local l = math.max(0.1, size * t)
			fill.Size = Vector3.new(width, 0.2, l)
			fill.CFrame = look * CFrame.new(0, 0.05, -l / 2)
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
		local seg = self:Take("Bolt")
		seg.Color = color
		seg.Transparency = 0
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
			self:Give("Bolt", seg)
		end
	end)
end

function WeaponFx:Beam(x: number, z: number, angle: number, length: number, halfWidth: number, color: Color3)
	local run = self.C.RunClient
	local px, pz = self:PlayerXZ(x, z)
	local base = run:World(px, pz, 2)
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local beam = self:Take("Beam")
	beam.Color = color
	local look = CFrame.lookAt(base, base + dir)
	self:Transient(0.28, function(t)
		local w = halfWidth * 2 * (1 - t * 0.7)
		beam.Size = Vector3.new(w, w * 0.6, length)
		beam.CFrame = look * CFrame.new(0, 0, -length / 2)
		beam.Transparency = t * 0.9
	end, function()
		self:Give("Beam", beam)
	end)
end

function WeaponFx:Hammer(x: number, z: number, radius: number, fall: number, big: boolean)
	local run = self.C.RunClient
	local ground = run:World(x, z, 0)
	local scale = if big then 2.2 else 1.2
	local handle = self:Take("Block")
	local head = self:Take("Block")
	handle.Color = rgb(150, 100, 60)
	head.Color = if big then rgb(230, 40, 50) else rgb(255, 130, 60)
	handle.Size = Vector3.new(0.9, 7, 0.9) * scale
	head.Size = Vector3.new(4, 2.4, 2.4) * scale
	local fx = self.C.EffectsController
	self:Transient(math.max(0.15, fall), function(t)
		local y = (1 - t * t) * 35 + 1.2 * scale
		local tilt = CFrame.Angles(0, 0, (1 - t) * 1.2)
		head.CFrame = CFrame.new(ground + Vector3.new(0, y, 0)) * tilt
		handle.CFrame = head.CFrame * CFrame.new(0, 4.6 * scale, 0)
	end, function()
		fx:Ring(ground, radius, if big then rgb(255, 60, 60) else rgb(255, 160, 60), 0.4)
		fx:Emit("Smoke", ground + Vector3.new(0, 1, 0), rgb(210, 200, 190), if big then 14 else 6)
		self.C.CameraController:Shake(if big then 1.4 else 0.5)
		self.C.SoundController:Play(if big then "Slam" else "Hammer")
		if math.random() < 0.12 then
			fx:WorldText(ground + Vector3.new(0, 4, 0), if big then "BANNED" else "BONK", rgb(255, 230, 90), 1.8, 0.9)
		end
		task.delay(0.25, function()
			self:Give("Block", handle)
			self:Give("Block", head)
		end)
	end)
end

function WeaponFx:Fx(weaponId: number, x: number, z: number, angle: number, p1: number, p2: number, variant: number)
	local run = self.C.RunClient
	local fx = self.C.EffectsController
	local sound = self.C.SoundController
	local pos = run:World(x, z, 0)

	if weaponId == 0 then
		if variant == GFX.Slam then
			fx:Ring(pos, p1, rgb(255, 40, 60), 0.4)
			fx:Emit("Smoke", pos + Vector3.new(0, 1, 0), rgb(120, 90, 90), 16)
			self.C.CameraController:Shake(1.3)
			sound:Play("Slam")
		elseif variant == GFX.Enrage then
			fx:Ring(pos, p1 * 2, rgb(255, 30, 30), 0.8)
			fx:Emit("Big", pos + Vector3.new(0, 3, 0), rgb(255, 60, 60), 40)
		elseif variant == GFX.Revive then
			fx:Ring(pos, p1, rgb(255, 140, 220), 0.6)
		elseif variant == GFX.Nuke then
			fx:Ring(pos, p1, rgb(255, 255, 255), 0.7)
			fx:Emit("Big", pos + Vector3.new(0, 3, 0), rgb(255, 240, 200), 60)
		elseif variant == GFX.Storm then
			self:Bolt(pos + Vector3.new(0, 45, 0), pos, rgb(210, 120, 255), 1.1, 0.25)
			fx:Ring(pos, p1, rgb(210, 120, 255), 0.3)
			sound:Play("Zap", 0.8)
		elseif variant == GFX.Shrink then
			fx:Ring(pos, p1, rgb(200, 120, 255), 1)
		elseif variant == GFX.SigmaStare then
			fx:Ring(pos, p1, rgb(140, 140, 160), 1.2)
			fx:Flash(rgb(40, 40, 50), 0.6)
		end
		return
	end

	local def = WeaponData.ById[weaponId]
	if not def then
		return
	end
	local key = def.Key
	if key == "GoofyHammer" then
		self:Hammer(x, z, p1, p2, false)
	elseif key == "BanHammer" then
		local px, pz = self:PlayerXZ(x, z)
		self:Hammer(px, pz, p1, 0.18, true)
	elseif key == "BrainrotBeam" then
		self:Beam(x, z, angle, p1, p2, def.Color)
		if variant == 1 then
			sound:Play("Beam")
		end
	elseif key == "ZapZap" then
		if variant == 0 then
			self:Bolt(pos + Vector3.new(0, 40, 0), pos, rgb(160, 230, 255), 0.8, 0.2)
			fx:Ring(pos, p1, rgb(160, 230, 255), 0.25)
			sound:Play("Zap")
		else
			local from = pos + Vector3.new(math.cos(angle) * p2, 2, math.sin(angle) * p2)
			self:Bolt(from, pos + Vector3.new(0, 2, 0), rgb(160, 230, 255), 0.5, 0.2)
		end
	elseif key == "ChaosOrb" then
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
			fx:WorldText(pos + Vector3.new(0, 5, 0), "🍕", rgb(255, 255, 255), 1.6)
		else
			fx:Ring(pos, p1, rgb(255, 255, 255), 0.5)
			sound:Play("VineBoom")
			self.C.CameraController:ZoomPunch(0.8, 0.35)
			self.C.CameraController:Shake(1.2)
		end
	elseif key == "Blast67" then
		local px, pz = self:PlayerXZ(x, z)
		local here = run:World(px, pz, 0)
		fx:Ring(here, p1, rgb(255, 215, 40), 0.55)
		fx:Ring(here, p1 * 0.6, rgb(255, 150, 40), 0.45)
		fx:WorldText(here + Vector3.new(0, 7, 0), "67", rgb(255, 215, 40), 3, 1)
		sound:Play("Blast67")
		self.C.CameraController:Shake(1)
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
			if p.Style == "Pizza" then
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

	-- orbs (same formula as the server: angle = time * speed + i * 2pi / n)
	local spec = self.OrbSpec
	if spec and root then
		local n = #self.Orbs
		for i, orb in self.Orbs do
			local a = now * spec.Speed + (i - 1) * 2 * math.pi / n
			orb.CFrame = CFrame.new(center.X + px + math.cos(a) * spec.Orbit, ground + 2.5, center.Z + pz + math.sin(a) * spec.Orbit)
		end
	end

	-- auras
	for _, aura in self.Auras do
		if root then
			local r = aura.Spec.Radius
			local pulse = 1 + math.sin(os.clock() * 5) * 0.03
			local base = CFrame.new(center.X + px, ground + 0.3, center.Z + pz)
			aura.Disc.Size = Vector3.new(0.1, r * 2 * pulse, r * 2 * pulse)
			aura.Disc.CFrame = base * FLAT
			aura.Edge.Size = Vector3.new(0.12, r * 2, r * 2)
			aura.Edge.CFrame = (base + Vector3.new(0, 0.02, 0)) * FLAT
			aura.Edge.Transparency = 0.55 + math.sin(os.clock() * 5) * 0.15
		end
	end

	-- telegraphs
	local i = 1
	local teles = self.Telegraphs
	while i <= #teles do
		local t = teles[i]
		t.T += sdt
		local frac = t.T / t.Delay
		if frac >= 1 then
			self:Give("Disc", t.Edge)
			self:Give("Disc", t.Fill)
			t.Edge.Shape = Enum.PartType.Cylinder
			t.Fill.Shape = Enum.PartType.Cylinder
			teles[i] = teles[#teles]
			teles[#teles] = nil
		else
			t.Update(frac)
			t.Fill.Transparency = 0.55 - frac * 0.3 + (if frac > 0.75 then math.sin(os.clock() * 40) * 0.15 else 0)
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
	self:SetLoadout({ Weapons = {} })
	self.Loadout = nil
end

function WeaponFx:Start()
	RunService.RenderStepped:Connect(function(dt)
		self:Update(dt)
	end)
end

return WeaponFx
