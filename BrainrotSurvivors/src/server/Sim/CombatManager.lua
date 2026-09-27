--[[
	CombatManager - the player's automatic weapons, their projectiles and allies.

	Every weapon Kind has one function that runs each simulation step (cooldown timer,
	targeting, damage). Damage is only ever computed here, on the server. The client gets
	compact visual records (Proj / Fx / Hit) and draws them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)

local SpatialGrid = require(script.Parent.SpatialGrid)
local EnemyManager = require(script.Parent.EnemyManager)

local CombatManager = {}

local sqrt, cos, sin, atan2, abs, min, max = math.sqrt, math.cos, math.sin, math.atan2, math.abs, math.min, math.max
local TAU = math.pi * 2
local MAX_ENEMY_R = 7.5
local scratch = {}
local hitList = {}

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

-- one hit with the player's crit / 67% modifiers
function CombatManager.Hit(run, e, base: number, kx: number, kz: number, knock: number)
	if not e.Alive then
		return
	end
	local st = run.Stats
	local dmg = base
	local flags = 0
	local rng = run.Rng
	if st.Crit > 0 and rng:NextNumber() < st.Crit then
		dmg *= st.CritMult
		flags += 1
	end
	if run.Rares.Percent67 and rng:NextNumber() < 0.67 then
		dmg *= 1.67
		flags += 2
	end
	EnemyManager.Damage(run, e, dmg, flags, kx, kz, knock)
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

local function area(run, x: number, z: number, r: number, dmg: number, knock: number): number
	local n = gather(run, x, z, r)
	local list = table.move(hitList, 1, n, 1, {})
	for _, e in list do
		CombatManager.Hit(run, e, dmg, e.X - x, e.Z - z, knock)
	end
	return n
end
CombatManager.Area = area

local function targetable(e): boolean
	return e.Alive and e.Key ~= "Crate"
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

local function nextProjId(run): number
	run.NextProjId = (run.NextProjId or 0) % 65535 + 1
	return run.NextProjId
end

local function fire(run, w, mode: string, angle: number, speed: number, life: number, target)
	if #run.Projectiles >= GameConfig.Sim.MaxProjectiles then
		return
	end
	local s = w.S
	local p = {
		Id = nextProjId(run),
		W = w,
		Mode = mode,
		X = run.PX,
		Z = run.PZ,
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
	run:Write("Proj", p.Id, w.Id, p.X, p.Z, angle, speed, if mode == "Boomerang" then p.OutTime else life, if target then target.Id else 0)
end

---------------------------------------------------------------------------
-- weapon kinds
---------------------------------------------------------------------------
local KINDS = {}

local function ready(w, dt: number): boolean
	w.Timer -= dt
	return w.Timer <= 0
end

function KINDS.Projectile(run, w, dt)
	if not ready(w, dt) then
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
	for i = 1, n do
		fire(run, w, "Straight", base + (i - (n + 1) / 2) * 0.13, s.Speed, s.Duration)
	end
end

function KINDS.Orbit(run, w, _dt)
	local s = w.S
	local now = run.Time
	local n = s.Amount
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
	end
end

function KINDS.Aura(run, w, dt)
	if not ready(w, dt) then
		return
	end
	local s = w.S
	w.Timer = s.Cooldown
	local n = gather(run, run.PX, run.PZ, s.Radius)
	local list = table.move(hitList, 1, n, 1, {})
	local mog = run.Character == "Sigma"
	for _, e in list do
		if mog then
			EnemyManager.Slow(e, 0.7, 0.8, run.Time)
		end
		CombatManager.Hit(run, e, s.Damage, e.X - run.PX, e.Z - run.PZ, s.Knockback)
	end
end

function KINDS.Hammer(run, w, dt)
	if not ready(w, dt) then
		return
	end
	local s = w.S
	local candidates = inRange(run, s.Range)
	if #candidates == 0 then
		w.Timer = 0.3
		return
	end
	w.Timer = s.Cooldown
	local used = {}
	for _ = 1, s.Amount do
		-- the densest spot among a few random candidates
		local best, bestN = nil, -1
		for _ = 1, min(10, #candidates) do
			local e = candidates[run.Rng:NextInteger(1, #candidates)]
			if not used[e.Uid] then
				local n = gather(run, e.X, e.Z, s.Radius)
				if n > bestN then
					best, bestN = e, n
				end
			end
		end
		if best then
			used[best.Uid] = true
			table.insert(run.Pending, { At = run.Time + s.Duration, X = best.X, Z = best.Z, R = s.Radius, Damage = s.Damage, Knock = s.Knockback })
			run:Write("Fx", w.Id, best.X, best.Z, 0, s.Radius, s.Duration, 0)
		end
	end
end

function KINDS.Missile(run, w, dt)
	if not ready(w, dt) then
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

local BEAM_OFFSETS = { 0, math.pi, math.pi / 2, -math.pi / 2, math.pi / 4, -math.pi / 4, 3 * math.pi / 4, -3 * math.pi / 4 }

function KINDS.Beam(run, w, dt)
	if not ready(w, dt) then
		return
	end
	local s = w.S
	w.Timer = s.Cooldown
	-- aims at the nearest enemy in reach (kind to phones), else where the player walks
	local target = CombatManager.Nearest(run, run.PX, run.PZ, s.Length + 6)
	local base = if target then atan2(target.Z - run.PZ, target.X - run.PX) else atan2(run.FZ, run.FX)
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

function KINDS.Boomerang(run, w, dt)
	if not ready(w, dt) then
		return
	end
	local s = w.S
	w.Timer = s.Cooldown
	local target = CombatManager.Nearest(run, run.PX, run.PZ, s.Range + 15)
	local base = if target then atan2(target.Z - run.PZ, target.X - run.PX) else atan2(run.FZ, run.FX)
	for i = 1, s.Amount do
		fire(run, w, "Boomerang", base + (i - 1) * TAU / s.Amount, s.Speed, 0)
	end
end

local function chain(run, w, from, jumps: number, dmg: number, hit: { [number]: boolean })
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
		prev = nextE
	end
end

function KINDS.Lightning(run, w, dt)
	if not ready(w, dt) then
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
				chain(run, w, target, s.Chain, s.Damage * 0.7, { [target.Uid] = true })
			end
		end
	end
end

function KINDS.Slam(run, w, dt)
	if not ready(w, dt) then
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

function KINDS.Chaos(run, w, dt)
	if not ready(w, dt) then
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
			local n = gather(run, run.PX, run.PZ, r)
			local list = table.move(hitList, 1, n, 1, {})
			for _, e in list do
				EnemyManager.Slow(e, 0.3, 2.5, run.Time)
				CombatManager.Hit(run, e, s.Damage * 0.5, 0, 0, 0)
			end
		elseif variant == 3 then
			local first = CombatManager.Nearest(run, run.PX, run.PZ, s.Range)
			if first then
				local dx, dz = first.X - run.PX, first.Z - run.PZ
				run:Write("Fx", w.Id, first.X, first.Z, atan2(-dz, -dx), 1.5, sqrt(dx * dx + dz * dz), 3)
				CombatManager.Hit(run, first, s.Damage * 0.8, dx, dz, 1)
				chain(run, w, first, 6, s.Damage * 0.8, { [first.Uid] = true })
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

function KINDS.Blast67(run, w, dt)
	if not ready(w, dt) then
		return
	end
	local s = w.S
	w.Timer = s.Cooldown
	run:Write("Fx", w.Id, run.PX, run.PZ, 0, s.Radius, 0, 0)
	area(run, run.PX, run.PZ, s.Radius, s.Damage, s.Knockback)
end

function KINDS.FinalAura(run, w, dt)
	if not ready(w, dt) then
		return
	end
	local s = w.S
	w.Timer = s.Cooldown
	local n = gather(run, run.PX, run.PZ, s.Radius)
	local list = table.move(hitList, 1, n, 1, {})
	for _, e in list do
		EnemyManager.Slow(e, 1 - s.Slow, 0.7, run.Time)
		local dmg = s.Damage + (if e.IsBoss then 0 else e.HP * s.Percent)
		CombatManager.Hit(run, e, dmg, e.X - run.PX, e.Z - run.PZ, 0)
	end
end

CombatManager.Kinds = KINDS

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
			if not p.Hit[e.Uid] and e.Alive then
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
		elseif p.Mode == "Boomerang" then
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

local function stepPending(run)
	local list = run.Pending
	local i = 1
	while i <= #list do
		local p = list[i]
		if run.Time >= p.At then
			area(run, p.X, p.Z, p.R, p.Damage, p.Knock)
			list[i] = list[#list]
			list[#list] = nil
		else
			i += 1
		end
	end
end

---------------------------------------------------------------------------
-- GOOBER ARMY allies
---------------------------------------------------------------------------
local function stepAllies(run, dt: number)
	local stacks = run.Rares.GooberArmy or 0
	local want = min(GameConfig.Sim.MaxAllies, stacks * 2)
	local allies = run.Allies
	while #allies < want do
		table.insert(allies, { X = run.PX, Z = run.PZ, Bite = 0 })
	end
	if want == 0 then
		return
	end
	local dmg = (8 + run.Level * 1.2) * run.Stats.Might
	for i, a in allies do
		local t = a.Target
		if not (t and t.Alive) or (t.X - run.PX) ^ 2 + (t.Z - run.PZ) ^ 2 > 32 * 32 then
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
	for _, w in run.Weapons do
		local fn = KINDS[w.Def.Kind]
		if fn then
			fn(run, w, dt)
		end
	end
	stepProjectiles(run, dt)
	stepPending(run)
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
