--[[
	CombatManager - the player's automatic abilities, their projectiles, lingering zones,
	summons (drones, allies, the clone) and burning.

	Every ability Kind has one function that runs each simulation step (cooldown timer,
	targeting, damage). Damage is only ever computed here, on the server. The client gets
	compact visual records (Proj / Fx / Zone / Clone / Hit / Burn) and draws them.

	Kinds: Projectile Missile Boomerang Lob Aura FireRing Field Cloud Meteor Slam Lightning
	       Chain Beam Vortex Blast67 Slash Hammer Swords Orbit Drone Clone Allies Barrier
	       Glitch Chaos Stare
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local Protocol = require(Shared.Protocol)
local WeaponData = require(Shared.WeaponData)

local SpatialGrid = require(script.Parent.SpatialGrid)
local EnemyManager = require(script.Parent.EnemyManager)

local CombatManager = {}

local sqrt, cos, sin, atan2, abs, min, max = math.sqrt, math.cos, math.sin, math.atan2, math.abs, math.min, math.max
local TAU = math.pi * 2
local MAX_ENEMY_R = 7.5
local HF = Protocol.HitFlags
local GFX = Protocol.Fx
local scratch = {}
local hitList = {}

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

-- one hit with every modifier: hero / streak bonus, crit, the 67% passive, marks, execution
function CombatManager.Hit(run, e, base: number, kx: number, kz: number, knock: number, extraFlags: number?)
	if not e.Alive or e.Phased then
		return
	end
	local st = run.Stats
	local rng = run.Rng
	local dmg = base * run:DamageMult(e)
	local flags = extraFlags or 0
	if st.Crit > 0 and rng:NextNumber() < st.Crit then
		dmg *= st.CritMult
		flags = bit32.bor(flags, HF.Crit)
	end
	if run.Passives.Percent67 and rng:NextNumber() < 0.67 then
		dmg *= 1.67
		flags = bit32.bor(flags, HF.Six)
	end
	if e.MarkUntil and e.MarkUntil > run.Time then
		dmg *= 1 + (e.Mark or 0)
	end
	if st.Execute > 0 and not e.IsBoss and e.HP <= e.MaxHP * 0.2 and rng:NextNumber() < st.Execute then
		dmg = math.max(dmg, e.HP + 1)
		flags = bit32.bor(flags, HF.Execute)
	end
	EnemyManager.Damage(run, e, dmg, flags, kx, kz, knock)
end

-- sets an enemy on fire (damage per second for `duration`)
function CombatManager.Burn(run, e, dps: number, duration: number)
	if not e.Alive or dps <= 0 then
		return
	end
	local now = run.Time
	local burning = e.BurnUntil and e.BurnUntil > now
	e.BurnDps = if burning then max(e.BurnDps or 0, dps) else dps
	e.BurnUntil = max(e.BurnUntil or 0, now + duration)
	e.BurnTick = e.BurnTick or 0
	if not burning then
		run:Write("Burn", e.Id, duration)
	end
end

-- enemies (alive, inside radius) around a point -> hitList[1..n]
local function gather(run, x: number, z: number, r: number): number
	local n = SpatialGrid.Query(run.Grid, x, z, r + MAX_ENEMY_R, scratch)
	local count = 0
	for i = 1, n do
		local e = scratch[i]
		if e.Alive then
			local dx, dz = e.X - x, e.Z - z
			local rr = r + e.Radius
			if dx * dx + dz * dz <= rr * rr then
				count += 1
				hitList[count] = e
			end
		end
	end
	return count
end

local function gatherList(run, x: number, z: number, r: number): { any }
	local n = gather(run, x, z, r)
	return table.move(hitList, 1, n, 1, {})
end

local function area(run, x: number, z: number, r: number, dmg: number, knock: number): number
	local list = gatherList(run, x, z, r)
	for _, e in list do
		CombatManager.Hit(run, e, dmg, e.X - x, e.Z - z, knock)
	end
	return #list
end
CombatManager.Area = area

local function targetable(e): boolean
	return e.Alive and e.Key ~= "Crate" and not e.Phased and not e.Dormant
end

function CombatManager.Nearest(run, x: number, z: number, range: number, skip: { [number]: boolean }?)
	local best, bestD = nil, range * range
	for _, e in run.Enemies do
		if targetable(e) and not (skip and skip[e.Uid]) then
			local dx, dz = e.X - x, e.Z - z
			local d = dx * dx + dz * dz
			if d < bestD then
				best, bestD = e, d
			end
		end
	end
	return best
end

local function inRange(run, range: number): { any }
	local out = {}
	local r2 = range * range
	for _, e in run.Enemies do
		if targetable(e) then
			local dx, dz = e.X - run.PX, e.Z - run.PZ
			if dx * dx + dz * dz <= r2 then
				table.insert(out, e)
			end
		end
	end
	return out
end

-- the densest spots among a few random candidates in range (hammers, meteors, clouds)
local function densest(run, range: number, radius: number, count: number): { any }
	local candidates = inRange(run, range)
	local out = {}
	if #candidates == 0 then
		return out
	end
	local used = {}
	for _ = 1, count do
		local best, bestN = nil, -1
		for _ = 1, min(10, #candidates) do
			local e = candidates[run.Rng:NextInteger(1, #candidates)]
			if not used[e.Uid] then
				local n = gather(run, e.X, e.Z, radius)
				if n > bestN then
					best, bestN = e, n
				end
			end
		end
		if best then
			used[best.Uid] = true
			table.insert(out, best)
		end
	end
	return out
end

local function nextProjId(run): number
	run.NextProjId = (run.NextProjId or 0) % 65535 + 1
	return run.NextProjId
end

local function fire(run, w, mode: string, angle: number, speed: number, life: number, target, fromX: number?, fromZ: number?)
	if #run.Projectiles >= GameConfig.Sim.MaxProjectiles then
		return
	end
	local s = w.S
	local x, z = fromX or run.PX, fromZ or run.PZ
	local p = {
		Id = nextProjId(run),
		W = w,
		Mode = mode,
		X = x,
		Z = z,
		DX = cos(angle),
		DZ = sin(angle),
		Speed = speed,
		Life = life,
		Pierce = s.Pierce or 0,
		R = if mode == "Homing" then 1.2 else (s.Radius or 1),
		Hit = {},
		Target = target,
		T = 0,
		OutTime = 0,
		Out = true,
	}
	if mode == "Boomerang" then
		p.OutTime = (s.Range or 20) / speed
		p.Life = p.OutTime * 2 + 2
	end
	table.insert(run.Projectiles, p)
	run:Write("Proj", p.Id, w.Id, x, z, angle, speed, if mode == "Boomerang" then p.OutTime else life, if target then target.Id else 0)
end

local function nextZoneId(run): number
	run.NextZoneId = (run.NextZoneId or 0) % 65535 + 1
	return run.NextZoneId
end

local function addZone(run, w, kind: string, x: number, z: number, r: number, duration: number)
	if #run.Zones >= GameConfig.Sim.MaxZones then
		return
	end
	local zone = { Id = nextZoneId(run), W = w, Kind = kind, X = x, Z = z, R = r, Until = run.Time + duration, Tick = 0 }
	table.insert(run.Zones, zone)
	run:Write("Zone", zone.Id, w.Id, x, z, r, duration)
end

---------------------------------------------------------------------------
-- ability kinds
---------------------------------------------------------------------------
local KINDS = {}

-- cooldown with the dynamic fire rate (Berserk, THE OVERDRIVE)
local function ready(run, w, dt: number): boolean
	w.Timer -= dt * run.FireRateNow
	return w.Timer <= 0
end

local function aimAngle(run, range: number): number
	local target = CombatManager.Nearest(run, run.PX, run.PZ, range)
	if target then
		return atan2(target.Z - run.PZ, target.X - run.PX), target
	end
	return atan2(run.FZ, run.FX), nil
end

function KINDS.Projectile(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local target = CombatManager.Nearest(run, run.PX, run.PZ, s.Range)
	if not target then
		w.Timer = 0.15
		return
	end
	w.Timer = s.Cooldown
	local base = atan2(target.Z - run.PZ, target.X - run.PX)
	local n = s.Amount
	local spread = s.Spread or 0.1
	for i = 1, n do
		fire(run, w, "Straight", base + (i - (n + 1) / 2) * spread, s.Speed, s.Duration)
	end
end

function KINDS.Missile(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local candidates = inRange(run, s.Range)
	if #candidates == 0 then
		w.Timer = 0.2
		return
	end
	w.Timer = s.Cooldown
	table.sort(candidates, function(a, b)
		return (a.X - run.PX) ^ 2 + (a.Z - run.PZ) ^ 2 < (b.X - run.PX) ^ 2 + (b.Z - run.PZ) ^ 2
	end)
	for i = 1, s.Amount do
		local target = candidates[(i - 1) % #candidates + 1]
		local a = atan2(target.Z - run.PZ, target.X - run.PX) + (i - (s.Amount + 1) / 2) * 0.5
		fire(run, w, "Homing", a, s.Speed, s.Duration, target)
	end
end

function KINDS.Boomerang(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	w.Timer = s.Cooldown
	local base = aimAngle(run, s.Range + 15)
	for i = 1, s.Amount do
		fire(run, w, "Boomerang", base + (i - 1) * TAU / s.Amount, s.Speed, 0)
	end
end

-- Banana Bomb: lobbed at the densest spot, explodes, then its peel explodes around it
function KINDS.Lob(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local spots = densest(run, s.Range, s.Radius, s.Amount)
	if #spots == 0 then
		w.Timer = 0.3
		return
	end
	w.Timer = s.Cooldown
	for _, e in spots do
		table.insert(run.Pending, {
			At = run.Time + s.Duration,
			X = e.X,
			Z = e.Z,
			R = s.Radius,
			Damage = s.Damage,
			Knock = s.Knockback,
			Split = math.floor(s.Split or 0),
			W = w,
		})
		run:Write("Fx", w.Id, e.X, e.Z, atan2(e.Z - run.PZ, e.X - run.PX), s.Radius, s.Duration, 0)
	end
end

function KINDS.Aura(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	w.Timer = s.Cooldown
	for _, e in gatherList(run, run.PX, run.PZ, s.Radius) do
		CombatManager.Hit(run, e, s.Damage, e.X - run.PX, e.Z - run.PZ, s.Knockback)
	end
end

function KINDS.FireRing(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	w.Timer = s.Cooldown
	for _, e in gatherList(run, run.PX, run.PZ, s.Radius) do
		CombatManager.Burn(run, e, s.Burn, s.BurnTime)
		CombatManager.Hit(run, e, s.Damage, e.X - run.PX, e.Z - run.PZ, s.Knockback)
	end
end

function KINDS.Field(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	w.Timer = s.Cooldown
	local now = run.Time
	for _, e in gatherList(run, run.PX, run.PZ, s.Radius) do
		EnemyManager.Slow(e, 1 - math.min(0.85, s.Slow), s.Cooldown + 0.25, now)
		if s.Freeze and not e.IsBoss and run.Rng:NextNumber() < s.Freeze and e.FrozenUntil <= now then
			e.FrozenUntil = now + 1.2
			run:Write("EState", e.Id, 3)
			e.Thaw = true
		end
		CombatManager.Hit(run, e, s.Damage, 0, 0, 0)
	end
end

function KINDS.Cloud(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local spots = densest(run, s.Range, s.Radius, s.Amount)
	if #spots == 0 then
		w.Timer = 0.3
		return
	end
	w.Timer = s.Cooldown
	for _, e in spots do
		addZone(run, w, "Cloud", e.X, e.Z, s.Radius, s.Duration)
	end
end

function KINDS.Meteor(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local spots = densest(run, s.Range, s.Radius, s.Amount)
	if #spots == 0 then
		w.Timer = 0.3
		return
	end
	w.Timer = s.Cooldown
	for _, e in spots do
		table.insert(run.Pending, { At = run.Time + s.Duration, X = e.X, Z = e.Z, R = s.Radius, Damage = s.Damage, Knock = s.Knockback, Burn = s.Burn, BurnTime = s.BurnTime })
		run:Write("Fx", w.Id, e.X, e.Z, 0, s.Radius, s.Duration, 0)
	end
end

function KINDS.Hammer(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local spots = densest(run, s.Range, s.Radius, s.Amount)
	if #spots == 0 then
		w.Timer = 0.3
		return
	end
	w.Timer = s.Cooldown
	for _, e in spots do
		table.insert(run.Pending, { At = run.Time + s.Duration, X = e.X, Z = e.Z, R = s.Radius, Damage = s.Damage, Knock = s.Knockback })
		run:Write("Fx", w.Id, e.X, e.Z, 0, s.Radius, s.Duration, 0)
	end
end

function KINDS.Slam(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	if not CombatManager.Nearest(run, run.PX, run.PZ, s.Radius + 4) then
		w.Timer = 0.25
		return
	end
	w.Timer = s.Cooldown
	run:Write("Fx", w.Id, run.PX, run.PZ, 0, s.Radius, 0, 0)
	area(run, run.PX, run.PZ, s.Radius, s.Damage, s.Knockback)
end

local function chain(run, w, from, jumps: number, dmg: number, hit: { [number]: boolean }, falloff: number)
	local prev = from
	for _ = 1, jumps do
		local nextE = CombatManager.Nearest(run, prev.X, prev.Z, 14, hit)
		if not nextE then
			return
		end
		hit[nextE.Uid] = true
		local dx, dz = nextE.X - prev.X, nextE.Z - prev.Z
		run:Write("Fx", w.Id, nextE.X, nextE.Z, atan2(-dz, -dx), 1.5, sqrt(dx * dx + dz * dz), 1)
		CombatManager.Hit(run, nextE, dmg, dx, dz, 1)
		dmg *= falloff
		prev = nextE
	end
end

function KINDS.Lightning(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local candidates = inRange(run, s.Range)
	if #candidates == 0 then
		w.Timer = 0.3
		return
	end
	w.Timer = s.Cooldown
	for _ = 1, s.Amount do
		if #candidates == 0 then
			break
		end
		local idx = run.Rng:NextInteger(1, #candidates)
		local target = candidates[idx]
		candidates[idx] = candidates[#candidates]
		candidates[#candidates] = nil
		if target.Alive then
			local x, z = target.X, target.Z
			run:Write("Fx", w.Id, x, z, 0, s.Radius, 0, 0)
			area(run, x, z, s.Radius, s.Damage, s.Knockback)
			if (s.Chain or 0) > 0 and target.Alive then
				chain(run, w, target, s.Chain, s.Damage * 0.7, { [target.Uid] = true }, 1)
			end
		end
	end
end

-- Chain Lightning: from the hero to the nearest enemy, then jumping
function KINDS.Chain(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local hit = {}
	local fired = 0
	for _ = 1, s.Amount do
		local first = CombatManager.Nearest(run, run.PX, run.PZ, s.Range, hit)
		if not first then
			break
		end
		fired += 1
		hit[first.Uid] = true
		local dx, dz = first.X - run.PX, first.Z - run.PZ
		run:Write("Fx", w.Id, first.X, first.Z, atan2(-dz, -dx), 1.5, sqrt(dx * dx + dz * dz), 1)
		CombatManager.Hit(run, first, s.Damage, dx, dz, s.Knockback)
		chain(run, w, first, s.Chain, s.Damage * 0.9, hit, 0.92)
	end
	w.Timer = if fired > 0 then s.Cooldown else 0.2
end

local BEAM_OFFSETS = { 0, math.pi, math.pi / 2, -math.pi / 2, math.pi / 4, -math.pi / 4, 3 * math.pi / 4, -3 * math.pi / 4 }

function KINDS.Beam(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	w.Timer = s.Cooldown
	-- aims at the nearest enemy in reach (kind to phones), else where the player walks
	local base = aimAngle(run, s.Length + 6)
	for i = 1, min(s.Amount, #BEAM_OFFSETS) do
		local a = base + BEAM_OFFSETS[i]
		local dx, dz = cos(a), sin(a)
		local hits = {}
		for _, e in run.Enemies do
			local rx, rz = e.X - run.PX, e.Z - run.PZ
			local along = rx * dx + rz * dz
			if along >= -1 and along <= s.Length + e.Radius then
				if abs(rx * dz - rz * dx) <= s.Radius + e.Radius then
					table.insert(hits, e)
				end
			end
		end
		for _, e in hits do
			CombatManager.Hit(run, e, s.Damage, dx, dz, s.Knockback)
		end
		run:Write("Fx", w.Id, run.PX, run.PZ, a, s.Length, s.Radius, i)
	end
end

function KINDS.Vortex(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local spots = densest(run, s.Range, s.Radius, s.Amount)
	if #spots == 0 then
		w.Timer = 0.4
		return
	end
	w.Timer = s.Cooldown
	for _, e in spots do
		addZone(run, w, "Vortex", e.X, e.Z, s.Radius, s.Duration)
	end
end

function KINDS.Blast67(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	w.Timer = s.Cooldown
	run:Write("Fx", w.Id, run.PX, run.PZ, 0, s.Radius, 0, 0)
	area(run, run.PX, run.PZ, s.Radius, s.Damage, s.Knockback)
end

-- Katana / Blood Moon: a cone in front (towards the nearest enemy)
function KINDS.Slash(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local target = CombatManager.Nearest(run, run.PX, run.PZ, s.Radius + 5)
	if not target then
		w.Timer = 0.12
		return
	end
	w.Timer = s.Cooldown
	w.Count += 1
	local big = run.Mech == "Iaijutsu" and w.Count % 4 == 0
	local dmg = s.Damage * (if big then 3 else 1)
	local reach = s.Radius * (if big then 1.3 else 1)
	local arc = math.min(TAU, s.Arc + (if big then 0.8 else 0))
	local base = atan2(target.Z - run.PZ, target.X - run.PX)
	local healed = 0
	for i = 1, s.Amount do
		local a = base + (i - 1) * math.pi
		for _, e in gatherList(run, run.PX, run.PZ, reach) do
			local da = math.abs((atan2(e.Z - run.PZ, e.X - run.PX) - a + math.pi) % TAU - math.pi)
			if arc >= TAU - 0.01 or da <= arc / 2 then
				CombatManager.Hit(run, e, dmg, e.X - run.PX, e.Z - run.PZ, s.Knockback)
				if s.Lifesteal and healed < 8 then
					healed += s.Lifesteal
				end
			end
		end
		run:Write("Fx", w.Id, run.PX, run.PZ, a, reach, arc, if big then 1 else 0)
	end
	if healed > 0 then
		run:Heal(healed)
	end
end

-- Sword Storm: swords burst out in every direction
function KINDS.Swords(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	if not CombatManager.Nearest(run, run.PX, run.PZ, s.Speed * s.Duration + 4) then
		w.Timer = 0.2
		return
	end
	w.Timer = s.Cooldown
	local offset = run.Rng:NextNumber(0, TAU)
	for i = 1, s.Amount do
		fire(run, w, "Straight", offset + (i - 1) * TAU / s.Amount, s.Speed, s.Duration)
	end
end

-- orbit positions are deterministic (angle = time * speed + i * 2pi / n): the client draws the same
function KINDS.Orbit(run, w, dt)
	local s = w.S
	local now = run.Time
	local n = s.Amount
	local explode = s.Explode and s.Explode > 0
	if explode then
		w.ExplodeTimer = (w.ExplodeTimer or s.ExplodeEvery) - dt
	end
	for i = 1, n do
		local a = now * s.Speed + (i - 1) * TAU / n
		local ox, oz = run.PX + cos(a) * s.Orbit, run.PZ + sin(a) * s.Orbit
		local count = gather(run, ox, oz, s.Radius)
		for k = 1, count do
			local e = hitList[k]
			if (w.HitAt[e.Uid] or 0) <= now then
				w.HitAt[e.Uid] = now + s.HitCooldown
				CombatManager.Hit(run, e, s.Damage, e.X - run.PX, e.Z - run.PZ, s.Knockback)
			end
		end
		if explode and w.ExplodeTimer <= 0 then
			run:Write("Fx", w.Id, ox, oz, 0, s.Explode, 0, 1)
			area(run, ox, oz, s.Explode, s.Damage * 0.6, s.Knockback)
		end
	end
	if explode and w.ExplodeTimer <= 0 then
		w.ExplodeTimer = s.ExplodeEvery
	end
end

-- drones fly around the hero (deterministic ring) and shoot from where they are
function CombatManager.DronePos(run, i: number, n: number): (number, number)
	local a = run.Time * 1.3 + (i - 1) * TAU / n
	return run.PX + cos(a) * 3.6, run.PZ + sin(a) * 3.6
end

function KINDS.Drone(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	w.Timer = s.Cooldown
	local n = s.Amount
	for i = 1, n do
		local x, z = CombatManager.DronePos(run, i, n)
		local target = CombatManager.Nearest(run, x, z, s.Range)
		if target then
			fire(run, w, "Straight", atan2(target.Z - z, target.X - x), s.Speed, s.Duration, nil, x, z)
		end
	end
end

-- Clone: a decoy that the horde goes for; it pulses damage while it lasts
function KINDS.Clone(run, w, dt)
	local s = w.S
	local decoy = run.Decoy
	if decoy then
		if run.Time >= decoy.Until then
			run.Decoy = nil
		else
			decoy.Tick -= dt
			if decoy.Tick <= 0 then
				decoy.Tick = s.HitCooldown
				area(run, decoy.X, decoy.Z, s.Blast, s.Damage, 3)
			end
		end
		return
	end
	if not ready(run, w, dt) then
		return
	end
	if not CombatManager.Nearest(run, run.PX, run.PZ, 30) then
		w.Timer = 0.5
		return
	end
	w.Timer = s.Cooldown
	run.Decoy = { X = run.PX, Z = run.PZ, Until = run.Time + s.Duration, R = s.Radius, Tick = 0 }
	run:Write("Clone", run.PX, run.PZ, s.Duration)
end

-- Allies are stepped for everyone (Goober Friends ability + THE GOOBER hero)
function KINDS.Allies() end

function KINDS.Barrier(run, w, dt)
	local s = w.S
	if run.Shield >= s.Amount then
		w.Timer = s.Cooldown
		return
	end
	if ready(run, w, dt) then
		w.Timer = s.Cooldown
		run.Shield += 1
		run:SendLoadout()
	end
end

-- called when a Barrier charge absorbs a hit
function CombatManager.BarrierBurst(run)
	local damage, radius, knock = 25, 9, 16
	for _, w in run.Weapons do
		if w.Def.Kind == "Barrier" then
			damage, radius, knock = w.S.Damage, w.S.Radius, w.S.Knockback
		end
	end
	run.Invulnerable = math.max(run.Invulnerable, 0.6)
	local id = WeaponData.ByKey.Barrier.Id
	run:Write("Fx", id, run.PX, run.PZ, 0, radius, 0, 0)
	area(run, run.PX, run.PZ, radius, damage, knock)
end

-- Glitch: enemies too close get teleported far away (and hurt)
function KINDS.Glitch(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local list = gatherList(run, run.PX, run.PZ, s.Radius)
	if #list == 0 then
		w.Timer = 0.3
		return
	end
	w.Timer = s.Cooldown
	run:Write("Fx", w.Id, run.PX, run.PZ, 0, s.Radius, 0, 0)
	local half = GameConfig.Arena.HalfSize
	local moved = 0
	for _, e in list do
		if moved >= s.Count then
			break
		end
		if not e.IsBoss and e.Alive then
			moved += 1
			CombatManager.Hit(run, e, s.Damage, 0, 0, 0)
			if e.Alive then
				local a = run.Rng:NextNumber(0, TAU)
				e.X = math.clamp(run.PX + cos(a) * s.Distance, -half, half)
				e.Z = math.clamp(run.PZ + sin(a) * s.Distance, -half, half)
				e.SentX, e.SentZ = e.X, e.Z
				run:Write("Blink", e.Id, e.X, e.Z)
			end
		end
	end
end

function KINDS.Chaos(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	w.Timer = s.Cooldown
	for _ = 1, s.Amount do
		local variant = run.Rng:NextInteger(1, 5)
		if variant == 1 then
			local target = CombatManager.Nearest(run, run.PX, run.PZ, s.Range)
			if target then
				local x, z = target.X, target.Z
				run:Write("Fx", w.Id, x, z, 0, s.Radius * 1.2, 0, 1)
				area(run, x, z, s.Radius * 1.2, s.Damage * 1.5, s.Knockback)
			end
		elseif variant == 2 then
			local r = s.Radius * 1.8
			run:Write("Fx", w.Id, run.PX, run.PZ, 0, r, 0, 2)
			for _, e in gatherList(run, run.PX, run.PZ, r) do
				EnemyManager.Slow(e, 0.3, 2.5, run.Time)
				CombatManager.Hit(run, e, s.Damage * 0.5, 0, 0, 0)
			end
		elseif variant == 3 then
			local first = CombatManager.Nearest(run, run.PX, run.PZ, s.Range)
			if first then
				local dx, dz = first.X - run.PX, first.Z - run.PZ
				run:Write("Fx", w.Id, first.X, first.Z, atan2(-dz, -dx), 1.5, sqrt(dx * dx + dz * dz), 3)
				CombatManager.Hit(run, first, s.Damage * 0.8, dx, dz, 1)
				chain(run, w, first, 6, s.Damage * 0.8, { [first.Uid] = true }, 1)
			end
		elseif variant == 4 then
			run:Heal(6)
			run:Write("Fx", w.Id, run.PX, run.PZ, 0, s.Radius, 0, 4)
			area(run, run.PX, run.PZ, s.Radius, s.Damage * 0.6, s.Knockback)
		else
			local r = s.Radius * 2
			run:Write("Fx", w.Id, run.PX, run.PZ, 0, r, 0, 5)
			area(run, run.PX, run.PZ, r, s.Damage * 0.7, s.Knockback * 2)
		end
	end
end

-- Sigma Stare (secret): freezes and marks everything around
function KINDS.Stare(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local list = gatherList(run, run.PX, run.PZ, s.Radius)
	if #list < 3 then
		w.Timer = 0.5
		return
	end
	w.Timer = s.Cooldown
	local now = run.Time
	run:Write("Fx", w.Id, run.PX, run.PZ, 0, s.Radius, 0, 0)
	for _, e in list do
		if not e.IsBoss then
			e.FrozenUntil = now + s.Duration
			e.Thaw = true
			run:Write("EState", e.Id, 3)
		end
		e.MarkUntil = now + s.Duration + 1.5
		e.Mark = s.Mark
		CombatManager.Hit(run, e, s.Damage, 0, 0, 0)
	end
end

CombatManager.Kinds = KINDS

-- THE 67 hero: every 67th kill
function CombatManager.Free67Blast(run)
	local r = 21 * run.Stats.Area
	run:Write("Fx", 0, run.PX, run.PZ, 0, r, 0, GFX.Blast67)
	area(run, run.PX, run.PZ, r, 67 * (1 + run.Level * 0.1) * run.Stats.Might, 10)
end

---------------------------------------------------------------------------
-- projectiles
---------------------------------------------------------------------------
local function endProjectile(run, p, explode: boolean)
	run:Write("ProjEnd", p.Id, p.X, p.Z, if explode then 1 else 0)
end

local function explode(run, p)
	local s = p.W.S
	area(run, p.X, p.Z, s.Radius, s.Damage, s.Knockback)
	endProjectile(run, p, true)
end

local function stepProjectile(run, p, dt: number): boolean -- true = keep
	local s = p.W.S
	local now = run.Time
	p.T += dt
	p.Life -= dt

	if p.Mode == "Homing" then
		local t = p.Target
		if not (t and t.Alive) then
			t = CombatManager.Nearest(run, p.X, p.Z, 35)
			p.Target = t
		end
		if t then
			local dx, dz = t.X - p.X, t.Z - p.Z
			local d = max(0.01, sqrt(dx * dx + dz * dz))
			local turn = min(1, 7 * dt)
			local nx, nz = p.DX + (dx / d - p.DX) * turn, p.DZ + (dz / d - p.DZ) * turn
			local len = max(0.01, sqrt(nx * nx + nz * nz))
			p.DX, p.DZ = nx / len, nz / len
		end
	elseif p.Mode == "Boomerang" then
		if p.Out and p.T >= p.OutTime then
			p.Out = false
		end
		if not p.Out then
			local dx, dz = run.PX - p.X, run.PZ - p.Z
			local d = sqrt(dx * dx + dz * dz)
			if d < 2.5 then
				endProjectile(run, p, false)
				return false
			end
			p.DX, p.DZ = dx / d, dz / d
		end
	end

	p.X += p.DX * p.Speed * dt
	p.Z += p.DZ * p.Speed * dt

	local n = gather(run, p.X, p.Z, p.R)
	for k = 1, n do
		local e = hitList[k]
		if p.Mode == "Straight" then
			if not p.Hit[e.Uid] and targetable(e) then
				p.Hit[e.Uid] = true
				CombatManager.Hit(run, e, s.Damage, p.DX, p.DZ, s.Knockback)
				p.Pierce -= 1
				if p.Pierce < 0 then
					endProjectile(run, p, false)
					return false
				end
			end
		elseif p.Mode == "Homing" then
			if targetable(e) then
				explode(run, p)
				return false
			end
		elseif (p.Hit[e.Uid] or 0) <= now then
			p.Hit[e.Uid] = now + (s.HitCooldown or 0.4)
			CombatManager.Hit(run, e, s.Damage, p.DX, p.DZ, s.Knockback)
		end
	end

	if p.Life <= 0 then
		if p.Mode == "Homing" then
			explode(run, p)
		else
			endProjectile(run, p, false)
		end
		return false
	end
	return true
end

local function stepProjectiles(run, dt: number)
	local list = run.Projectiles
	local i = 1
	while i <= #list do
		if stepProjectile(run, list[i], dt) then
			i += 1
		else
			list[i] = list[#list]
			list[#list] = nil
		end
	end
end

-- delayed impacts: hammers, fists, meteors, banana bombs (and their peels)
local function stepPending(run)
	local list = run.Pending
	local i = 1
	while i <= #list do
		local p = list[i]
		if run.Time >= p.At then
			list[i] = list[#list]
			list[#list] = nil
			local burn = p.Burn
			for _, e in gatherList(run, p.X, p.Z, p.R) do
				CombatManager.Hit(run, e, p.Damage, e.X - p.X, e.Z - p.Z, p.Knock)
				if burn then
					CombatManager.Burn(run, e, burn, p.BurnTime or 2)
				end
			end
			if p.Split and p.Split > 0 and p.W then
				for k = 1, p.Split do
					local a = (k / p.Split) * TAU + run.Rng:NextNumber(-0.3, 0.3)
					local d = run.Rng:NextNumber(3.5, 6.5)
					local x, z = p.X + cos(a) * d, p.Z + sin(a) * d
					table.insert(list, { At = run.Time + 0.3 + k * 0.05, X = x, Z = z, R = p.R * 0.55, Damage = p.Damage * 0.45, Knock = p.Knock * 0.5, Peel = true, W = p.W })
				end
			end
			if p.Peel and p.W then
				run:Write("Fx", p.W.Id, p.X, p.Z, 0, p.R, 0, 2)
			end
		else
			i += 1
		end
	end
end

-- lingering zones: poison clouds and black holes
local function stepZones(run, dt: number)
	local list = run.Zones
	local now = run.Time
	local i = 1
	while i <= #list do
		local z = list[i]
		if now >= z.Until then
			run:Write("ZoneEnd", z.Id)
			list[i] = list[#list]
			list[#list] = nil
		else
			local s = z.W.S
			if z.Kind == "Vortex" then
				-- pull everything (but bosses) towards the centre
				local pull = s.Pull or 16
				for _, e in gatherList(run, z.X, z.Z, z.R) do
					if not e.IsBoss then
						local dx, dz = z.X - e.X, z.Z - e.Z
						local d = sqrt(dx * dx + dz * dz)
						if d > 0.6 then
							local step = min(d - 0.5, pull * dt)
							e.X += dx / d * step
							e.Z += dz / d * step
						end
					end
				end
				if s.Vacuum then
					run.MagnetAll = true
				end
			end
			z.Tick -= dt
			if z.Tick <= 0 then
				z.Tick = s.HitCooldown or 0.5
				for _, e in gatherList(run, z.X, z.Z, z.R) do
					CombatManager.Hit(run, e, s.Damage, 0, 0, 0)
				end
			end
			i += 1
		end
	end
end

---------------------------------------------------------------------------
-- allies: Goober Friends ability + THE GOOBER hero
---------------------------------------------------------------------------
local function allyCount(run): (number, number)
	local count, damage = 0, 0
	for _, w in run.Weapons do
		if w.Def.Kind == "Allies" then
			count += w.S.Amount
			damage = w.S.Damage
		end
	end
	if run.Mech == "GooberFriends" then
		count += math.min(6, 2 + math.floor(run.Level / 10))
		damage = max(damage, (8 + run.Level * 1.2) * run.Stats.Might)
	end
	return min(GameConfig.Sim.MaxAllies, count), damage
end

local function stepAllies(run, dt: number)
	local want, dmg = allyCount(run)
	local allies = run.Allies
	while #allies < want do
		table.insert(allies, { X = run.PX, Z = run.PZ, Bite = 0 })
	end
	while #allies > want do
		table.remove(allies)
	end
	if want == 0 then
		return
	end
	for i, a in allies do
		local t = a.Target
		if not (t and targetable(t)) or (t.X - run.PX) ^ 2 + (t.Z - run.PZ) ^ 2 > 32 * 32 then
			t = CombatManager.Nearest(run, a.X, a.Z, 26)
			a.Target = t
		end
		a.Bite -= dt
		local tx, tz
		if t then
			tx, tz = t.X, t.Z
		else
			local ang = run.Time * 1.5 + i * TAU / #allies
			tx, tz = run.PX + cos(ang) * 4, run.PZ + sin(ang) * 4
		end
		local dx, dz = tx - a.X, tz - a.Z
		local d = sqrt(dx * dx + dz * dz)
		local reach = if t then t.Radius + 1 else 0.5
		if d > reach then
			local step = min(d - reach, 24 * dt)
			a.X += dx / d * step
			a.Z += dz / d * step
		elseif t and a.Bite <= 0 then
			a.Bite = 0.45
			CombatManager.Hit(run, t, dmg, dx, dz, 1.5)
			run:Write("Slash", 1, t.X, t.Z)
		end
	end
end

---------------------------------------------------------------------------
-- step
---------------------------------------------------------------------------
function CombatManager.Step(run, dt: number)
	run.FireRateNow = run:FireRate()
	for _, w in run.Weapons do
		local fn = KINDS[w.Def.Kind]
		if fn then
			fn(run, w, dt)
		end
	end
	stepProjectiles(run, dt)
	stepPending(run)
	stepZones(run, dt)
	stepAllies(run, dt)

	-- forget old per-enemy hit cooldowns
	run.HitCleanAt = run.HitCleanAt or 5
	if run.Time >= run.HitCleanAt then
		run.HitCleanAt = run.Time + 5
		for _, w in run.Weapons do
			for uid, t in w.HitAt do
				if t < run.Time then
					w.HitAt[uid] = nil
				end
			end
		end
	end
end

return CombatManager
