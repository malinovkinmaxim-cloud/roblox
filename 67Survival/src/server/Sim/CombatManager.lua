--[[
	CombatManager - the player's automatic abilities, their projectiles, lingering zones,
	summons (drones, allies, the clone) and burning.

	Every ability Kind has one function that runs each simulation step (cooldown timer,
	targeting, damage). Damage is only ever computed here, on the server. The client gets
	compact visual records (Proj / Fx / Zone / Clone / Hit / Burn) and draws them.

	Kinds: Projectile Missile Boomerang Lob Aura FireRing Field Cloud Meteor Slam Lightning
	       Chain Beam Vortex Blast67 Slash Hammer Swords Orbit Drone Clone Allies Barrier
	       Glitch Chaos Stare
	       + the PREMIUM ones (Solar HolePet GoldMeteor Bubble Phoenix Storm Crown) from
	       Sim/PremiumAbilities.lua, installed at the end of this module

	Ability levels, level-up upgrades and items change behaviour through mechanic keys in the
	ability's stats (shared/WeaponData.lua header): ricochet, split, homing, explosions, return,
	chains, stuns, slows, burns, echo casts, aftershocks, death blasts. Every hit knows the
	ability it comes from (SRC) so the right mechanics apply; the build's own procs live in
	Sim/Perks.lua and never trigger each other (run.Proc).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local Protocol = require(Shared.Protocol)
local WeaponData = require(Shared.WeaponData)

local SpatialGrid = require(script.Parent.SpatialGrid)
local EnemyManager = require(script.Parent.EnemyManager)
local Perks = require(script.Parent.Perks)

local CombatManager = {}

local sqrt, cos, sin, atan2, abs, min, max = math.sqrt, math.cos, math.sin, math.atan2, math.abs, math.min, math.max
local TAU = math.pi * 2
local MAX_ENEMY_R = 7.5
local HF = Protocol.HitFlags
local GFX = Protocol.Fx
local scratch = {}
local hitList = {}
local SRC = nil -- the ability whose hits are being resolved right now

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

-- one hit with every modifier: hero / streak bonus, the build (Sim/Perks), crit, the 67%
-- passive, marks, execution; then the ability's on-hit mechanics and the build's procs.
-- src = the ability (defaults to the one being resolved)
function CombatManager.Hit(run, e, base: number, kx: number, kz: number, knock: number, extraFlags: number?, src: any?)
	if not e.Alive or e.Phased then
		return
	end
	src = src or SRC
	local st = run.Stats
	local rng = run.Rng
	local dmg, pflags = Perks.PreHit(run, e, base * run:DamageMult(e), src)
	local flags = bit32.bor(extraFlags or 0, pflags)
	local crit, dice = false, false
	if st.Crit > 0 and rng:NextNumber() < st.Crit then
		local mult
		mult, dice = Perks.CritMult(run, st.CritMult)
		dmg *= mult
		crit = true
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
	e.LastSrc = if run.Proc then nil else src
	EnemyManager.Damage(run, e, dmg, flags, kx, kz, knock)
	-- the ability's own on-hit mechanics (not from procs)
	local s = src and src.S
	if s and not run.Proc then
		local now = run.Time
		if e.Alive and not e.IsBoss then
			if s.Stun and s.Stun > 0 then
				EnemyManager.Stun(run, e, s.Stun)
			end
			if s.SlowHit and s.SlowHit > 0 then
				EnemyManager.Slow(e, 1 - math.min(0.85, s.SlowHit), 1.5, now)
			end
		end
		if e.Alive and s.BurnHit and s.BurnHit > 0 then
			CombatManager.Burn(run, e, s.BurnHit * st.Might * st.Burn, 2)
		end
		if e.Alive and s.Weaken and s.Weaken > 0 then
			e.Mark = math.max(if e.MarkUntil and e.MarkUntil > now then e.Mark or 0 else 0, s.Weaken)
			e.MarkUntil = now + 3
		end
		if s.ChainHit and s.ChainHit > 0 then
			Perks.Zap(run, e, s.ChainHit, 12, dmg * 0.5)
		elseif s.ChainChance and rng:NextNumber() < s.ChainChance then
			Perks.Zap(run, e, s.ChainJumps or 1, 12, dmg * (s.ChainShare or 0.5))
		end
	end
	Perks.OnHit(run, e, dmg, crit, dice, src)
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
CombatManager.Gather = gatherList

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

-- the enemy to aim at: the closest one. Bosses and elites are measured from their edge
-- and count a little closer (they are what you want to hit when they are in range).
function CombatManager.Nearest(run, x: number, z: number, range: number, skip: { [number]: boolean }?)
	local best, bestD = nil, range * range
	for _, e in run.Enemies do
		if targetable(e) and not (skip and skip[e.Uid]) then
			local dx, dz = e.X - x, e.Z - z
			local d = dx * dx + dz * dz
			if e.IsBoss or e.Elite then
				local edge = math.max(0, math.sqrt(d) - e.Radius - 6)
				d = edge * edge
			end
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

local function fire(run, w, mode: string, angle: number, speed: number, life: number, target, fromX: number?, fromZ: number?, extra: { [string]: any }?)
	if #run.Projectiles >= GameConfig.Sim.MaxProjectiles then
		return nil
	end
	local s = w.S
	local x, z = fromX or run.PX, fromZ or run.PZ
	-- TIME BUBBLE: your shots fly faster (same reach)
	local haste = run.Haste
	if haste and haste > 1 then
		speed *= haste
		life /= haste
	end
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
		Pierce = (s.Pierce or 0) + (if mode == "Straight" then Perks.ExtraPierce(run) else 0),
		R = if mode == "Homing" then 1.2 else (s.Radius or 1),
		Hit = {},
		Target = target,
		T = 0,
		OutTime = 0,
		Out = true,
		Mult = 1, -- damage multiplier (shards, shadow copies, returning shots)
		Ricochet = s.Ricochet or 0,
		Bounces = 0,
		Pierced = 0,
		Travel = 0,
	}
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	if mode == "Boomerang" then
		p.OutTime = (s.Range or 20) / speed
		p.Life = p.OutTime * 2 + 2
	end
	table.insert(run.Projectiles, p)
	run:Write("Proj", p.Id, w.Id, x, z, angle, speed, if mode == "Boomerang" then p.OutTime else life, if target then target.Id else 0)
	return p
end
CombatManager.Fire = fire

local function nextZoneId(run): number
	run.NextZoneId = (run.NextZoneId or 0) % 65535 + 1
	return run.NextZoneId
end

CombatManager.NextZoneId = nextZoneId

local function addZone(run, w, kind: string, x: number, z: number, r: number, duration: number)
	if #run.Zones >= GameConfig.Sim.MaxZones then
		return
	end
	local zone = { Id = nextZoneId(run), W = w, Kind = kind, X = x, Z = z, R = r, Until = run.Time + duration, Tick = 0 }
	table.insert(run.Zones, zone)
	run:Write("Zone", zone.Id, w.Id, x, z, r, duration)
end
CombatManager.AddZone = addZone

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
	if (s.Aftershock or 0) > 0 then
		table.insert(run.Pending, { At = run.Time + 0.45, X = run.PX, Z = run.PZ, R = s.Radius * 1.25, Damage = s.Damage * 0.5, Knock = s.Knockback, After = true, W = w })
	end
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
	return prev
end

-- LastBlast: the last enemy of a chain explodes
local function lastBlast(run, w, at, dmg: number)
	local r = w.S.LastBlast
	if r and r > 0 and at then
		run:Write("Fx", 0, at.X, at.Z, 0, r, 0, GFX.Bomb)
		local was = run.Proc
		run.Proc = true
		area(run, at.X, at.Z, r, dmg, 4)
		run.Proc = was
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
			local last = target
			if (s.Chain or 0) > 0 and target.Alive then
				last = chain(run, w, target, s.Chain, s.Damage * 0.7, { [target.Uid] = true }, 1)
			end
			lastBlast(run, w, last, s.Damage)
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
		local last = chain(run, w, first, s.Chain, s.Damage * 0.9, hit, 0.92)
		lastBlast(run, w, last, s.Damage)
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
			if (s.CloneBlast or 0) > 0 and not decoy.Goo then
				run:Write("Fx", 0, decoy.X, decoy.Z, 0, s.CloneBlast, 0, GFX.Bomb)
				area(run, decoy.X, decoy.Z, s.CloneBlast, s.Damage * 3, 12)
			end
		elseif decoy.Goo then
			return -- a goo decoy of the Goo Heart: the clone waits for it
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
	local barrier = nil
	for _, w in run.Weapons do
		if w.Def.Kind == "Barrier" then
			damage, radius, knock = w.S.Damage, w.S.Radius, w.S.Knockback
			barrier = w
		end
	end
	run.Invulnerable = math.max(run.Invulnerable, 0.6)
	local id = WeaponData.ByKey.Barrier.Id
	run:Write("Fx", id, run.PX, run.PZ, 0, radius, 0, 0)
	local was = SRC
	SRC = barrier
	area(run, run.PX, run.PZ, radius, damage, knock)
	SRC = was
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
require(script.Parent.PremiumAbilities).Install(CombatManager) -- the premium Kinds

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
	area(run, p.X, p.Z, s.Radius, s.Damage * p.Mult, s.Knockback)
	endProjectile(run, p, true)
end

-- shards: n small copies flying out of (x, z) (ability SplitEnd, Split upgrade, missiles)
local function shards(run, p, n: number, spread: boolean)
	local w = p.W
	local s = w.S
	local base = atan2(p.DZ, p.DX)
	for k = 1, n do
		local a = if spread then base + (k - (n + 1) / 2) * 0.55 else base + (k - 1) * TAU / n + 0.3
		if p.Mode == "Homing" then
			local target = CombatManager.Nearest(run, p.X + cos(a) * 6, p.Z + sin(a) * 6, 25, p.Hit)
			fire(run, w, "Homing", a, s.Speed * 1.2, 1.2, target, p.X, p.Z, { Mult = p.Mult * 0.5, Shard = true, Hit = table.clone(p.Hit) })
		else
			local inherit = s.SplitInherit
			fire(run, w, "Straight", a, s.Speed, math.min(s.Duration or 0.6, 0.45), nil, p.X, p.Z, {
				Mult = p.Mult * 0.4,
				Shard = true,
				R = (s.Radius or 1) * 0.7,
				Hit = table.clone(p.Hit),
				Pierce = if inherit then s.Pierce or 0 else 0,
				Ricochet = if inherit then s.Ricochet or 0 else 0,
			})
		end
	end
end

-- a straight shot is done with its last enemy: ricochet, else split / explode at the end
local function lastHit(run, p, e): boolean -- true = the projectile lives on (ricocheted)
	local s = p.W.S
	if p.Ricochet > 0 then
		local range = s.RicochetRange or 16
		local seek = s.RicochetSeek
		local nextE = nil
		local bestD = range * range
		for _, o in run.Enemies do
			if targetable(o) and not p.Hit[o.Uid] then
				local dx, dz = o.X - p.X, o.Z - p.Z
				local d = dx * dx + dz * dz
				if seek and (o.IsBoss or o.Elite) then
					d *= 0.1
				end
				if d < bestD then
					nextE, bestD = o, d
				end
			end
		end
		if nextE then
			endProjectile(run, p, false)
			local a = atan2(nextE.Z - p.Z, nextE.X - p.X)
			local grow = 1 + (s.RicochetGrow or 0)
			fire(run, p.W, "Straight", a, p.Speed, math.max(0.3, sqrt(bestD) / p.Speed + 0.25), nil, p.X, p.Z, {
				Mult = p.Mult * grow,
				Hit = p.Hit,
				Pierce = 0,
				Ricochet = p.Ricochet - 1,
				Bounces = p.Bounces + 1,
				Shard = p.Shard,
				Returned = true, -- a bounced shot does not come back
			})
			return false
		end
	end
	if not p.Shard then
		if (s.SplitEnd or 0) > 0 then
			shards(run, p, math.floor(s.SplitEnd), false)
		end
		if (s.ExplodeEnd or 0) > 0 then
			run:Write("Fx", 0, p.X, p.Z, 0, s.ExplodeEnd, 0, GFX.Bomb)
			local was = run.Proc
			run.Proc = true
			area(run, p.X, p.Z, s.ExplodeEnd, s.Damage * p.Mult * 0.6, s.Knockback)
			run.Proc = was
		end
	end
	return false
end

-- the shot flew its whole range: straight shots may come back (Return Policy, Sword Storm)
local function returnShot(run, p)
	local s = p.W.S
	if p.Returned or p.Shard or not s.Return or s.Return <= 0 then
		return
	end
	local dx, dz = run.PX - p.X, run.PZ - p.Z
	local d = sqrt(dx * dx + dz * dz)
	if d < 4 then
		return
	end
	fire(run, p.W, "Straight", atan2(dz, dx), p.Speed, d / p.Speed + 0.1, nil, p.X, p.Z, {
		Mult = p.Mult * s.Return,
		Returned = true,
		Pierce = if s.ReturnPierce then 99 else s.Pierce or 0,
		Ricochet = 0,
	})
end

local explodeBudget = 0

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
	elseif s.Turn and s.Turn > 0 and p.T > 0.08 then
		-- HOMING upgrade: straight shots curve towards the nearest enemy they have not hit
		local t = p.Seek
		if not (t and t.Alive and not p.Hit[t.Uid]) then
			t = CombatManager.Nearest(run, p.X, p.Z, 26, p.Hit)
			p.Seek = t
		end
		if t then
			local dx, dz = t.X - p.X, t.Z - p.Z
			local d = max(0.01, sqrt(dx * dx + dz * dz))
			local turn = min(1, s.Turn * dt)
			local nx, nz = p.DX + (dx / d - p.DX) * turn, p.DZ + (dz / d - p.DZ) * turn
			local len = max(0.01, sqrt(nx * nx + nz * nz))
			p.DX, p.DZ = nx / len, nz / len
		end
	end

	local step = p.Speed * dt
	p.Travel += step
	run.HitDistance = p.Travel

	-- swept hits: a fast shot checks a few points along its move (and where it starts on its
	-- first step), so it never flies through an enemy pressed against the hero (20 steps / s)
	local x0, z0 = p.X, p.Z
	local samples = max(1, min(4, math.ceil(step / (p.R * 2 + 1.5))))
	for i = if p.T <= dt + 1e-6 then 0 else 1, samples do
		p.X, p.Z = x0 + p.DX * step * i / samples, z0 + p.DZ * step * i / samples
		local n = gather(run, p.X, p.Z, p.R)
		for k = 1, n do
			local e = hitList[k]
			if p.Mode == "Straight" then
				if not p.Hit[e.Uid] and targetable(e) then
					p.Hit[e.Uid] = true
					local dmg = s.Damage * p.Mult * (1 + (s.PierceGrow or 0) * p.Pierced)
					CombatManager.Hit(run, e, dmg, p.DX, p.DZ, s.Knockback)
					p.Pierced += 1
					-- explosive rounds
					if s.ExplodeChance and explodeBudget > 0 and run.Rng:NextNumber() < s.ExplodeChance then
						explodeBudget -= 1
						run:Write("Fx", 0, p.X, p.Z, 0, s.ExplodeR, 0, GFX.Bomb)
						local was = run.Proc
						run.Proc = true
						area(run, p.X, p.Z, s.ExplodeR, dmg * (s.ExplodeShare or 0.4), 3)
						if s.ExplodeBurn then
							for _, o in gatherList(run, p.X, p.Z, s.ExplodeR) do
								CombatManager.Burn(run, o, dmg * 0.2, 2)
							end
						end
						run.Proc = was
					end
					-- split on the first hit
					if not p.Shard and p.Pierced == 1 and s.SplitChance and run.Rng:NextNumber() < s.SplitChance then
						shards(run, p, s.SplitCount or 2, true)
					end
					if s.Retarget then
						p.Seek = nil
					end
					p.Pierce -= 1
					if p.Pierce < 0 then
						lastHit(run, p, e)
						endProjectile(run, p, false)
						return false
					end
				end
			elseif p.Mode == "Homing" then
				if targetable(e) then
					explode(run, p)
					if not p.Shard and (s.SplitEnd or 0) > 0 then
						shards(run, p, math.floor(s.SplitEnd), false)
					end
					return false
				end
			elseif (p.Hit[e.Uid] or 0) <= now then
				p.Hit[e.Uid] = now + (s.HitCooldown or 0.4)
				CombatManager.Hit(run, e, s.Damage * p.Mult, p.DX, p.DZ, s.Knockback)
			end
		end
	end

	if p.Life <= 0 then
		if p.Mode == "Homing" then
			explode(run, p)
			if not p.Shard and (s.SplitEnd or 0) > 0 then
				shards(run, p, math.floor(s.SplitEnd), false)
			end
		else
			endProjectile(run, p, false)
			if p.Mode == "Straight" then
				returnShot(run, p)
			end
		end
		return false
	end
	return true
end

local function stepProjectiles(run, dt: number)
	explodeBudget = 8 -- explosive rounds per step: readable, not a screen wipe
	local list = run.Projectiles
	local i = 1
	while i <= #list do
		local p = list[i]
		SRC = p.W
		if stepProjectile(run, p, dt) then
			i += 1
		else
			-- new shots (ricochets, shards) were appended at the end: p is still at i
			list[i] = list[#list]
			list[#list] = nil
		end
	end
	SRC = nil
	run.HitDistance = nil
end

-- SECOND SHADOW: a copy of a projectile ability fired from the shadow
function CombatManager.ShadowFire(run, w, x: number, z: number, mult: number)
	local s = w.S
	local target = CombatManager.Nearest(run, x, z, s.Range or 40)
	if not target then
		return
	end
	local a = atan2(target.Z - z, target.X - x)
	local kind = w.Def.Kind
	local n = math.max(1, math.floor((s.Amount or 1) * 0.5 + 0.5))
	for i = 1, n do
		local ai = a + (i - (n + 1) / 2) * (s.Spread or 0.12)
		if kind == "Missile" then
			fire(run, w, "Homing", ai, s.Speed, s.Duration, target, x, z, { Mult = mult })
		elseif kind == "Boomerang" then
			fire(run, w, "Boomerang", ai, s.Speed, 0, nil, x, z, { Mult = mult })
		else
			fire(run, w, "Straight", ai, s.Speed, s.Duration, nil, x, z, { Mult = mult })
		end
	end
end

-- delayed impacts: hammers, fists, meteors, banana bombs (and their peels), aftershocks
local function stepPending(run)
	local list = run.Pending
	local i = 1
	while i <= #list do
		local p = list[i]
		if run.Time >= p.At then
			list[i] = list[#list]
			list[#list] = nil
			SRC = p.W
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
			if p.After then
				run:Write("Fx", 0, p.X, p.Z, 0, p.R, 0, GFX.Nova)
			elseif p.W and not p.Peel and (p.W.S.Aftershock or 0) > 0 then
				table.insert(list, { At = run.Time + 0.4, X = p.X, Z = p.Z, R = p.R * 1.25, Damage = p.Damage * 0.5, Knock = p.Knock, After = true, W = p.W })
			end
			SRC = nil
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
		SRC = z.W
		if now >= z.Until then
			run:Write("ZoneEnd", z.Id)
			local s = z.W.S
			if z.Kind == "Vortex" and (s.Collapse or 0) > 0 then
				run:Write("Fx", 0, z.X, z.Z, 0, s.Collapse, 0, GFX.Bomb)
				area(run, z.X, z.Z, s.Collapse, s.Damage * 6, 12)
			end
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
	SRC = nil
end

---------------------------------------------------------------------------
-- allies: Goober Friends ability + THE GOOBER hero
---------------------------------------------------------------------------
local function allyCount(run): (number, number, any)
	local count, damage, src = 0, 0, nil
	for _, w in run.Weapons do
		if w.Def.Kind == "Allies" then
			count += w.S.Amount
			damage = w.S.Damage
			src = w
		end
	end
	if run.Mech == "GooberFriends" then
		count += math.min(6, 2 + math.floor(run.Level / 10))
		damage = max(damage, (8 + run.Level * 1.2) * run.Stats.Might)
	end
	-- the Overlord's Banner: troops for a while
	local troops = Perks.Troops(run)
	if troops > 0 then
		count += troops
		damage = max(damage, Perks.Scaled(run, 10))
	end
	return min(GameConfig.Sim.MaxAllies, count), damage, src
end

local function stepAllies(run, dt: number)
	local want, dmg, src = allyCount(run)
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
			CombatManager.Hit(run, t, dmg, dx, dz, 1.5, nil, src)
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
			SRC = w
			local before = w.Timer
			fn(run, w, dt)
			-- ECHO: every n-th cast fires again right away
			local echo = w.S.Echo
			if echo and echo > 0 and w.Timer > before and w.Timer >= (w.S.Cooldown or 1) * 0.9 then
				if w.Echoing then
					w.Echoing = false
				else
					w.Casts = (w.Casts or 0) + 1
					if w.Casts % math.floor(echo) == 0 then
						w.Timer = 0.12
						w.Echoing = true
					end
				end
			end
		end
	end
	SRC = nil
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
