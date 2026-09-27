--[[
	EnemyManager - enemies of a run: spawn, AI behaviours, movement, crowd separation,
	obstacle avoidance, contact damage, damage / death / drops.

	Enemies are plain tables (no Instances). One pass per simulation step handles every
	enemy; neighbour queries go through the run's SpatialGrid.

	Behaviours: Chase, Charge, Flee, Strafe, Blink, Orbit, Stand, Static, March, Boss
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local EnemyData = require(Shared.EnemyData)
local WaveData = require(Shared.WaveData)
local Protocol = require(Shared.Protocol)

local SpatialGrid = require(script.Parent.SpatialGrid)
local Bosses = require(script.Parent.Bosses)
local Pickups = require(script.Parent.Pickups)

local EnemyManager = {}

local sqrt, exp, min, max, abs, floor = math.sqrt, math.exp, math.min, math.max, math.abs, math.floor
local cos, sin, atan2 = math.cos, math.sin, math.atan2
local FLAGS = Protocol.Flags
local PLAYER_R = GameConfig.Player.Radius
local HALF = GameConfig.Arena.HalfSize
local scratch = {}

---------------------------------------------------------------------------
-- spawn
---------------------------------------------------------------------------
local function allocId(run): number
	local id = run.NextEnemyId or 0
	for _ = 1, 65535 do
		id = id % 65535 + 1
		if not run.EnemyById[id] then
			run.NextEnemyId = id
			return id
		end
	end
	error("out of enemy ids")
end

export type SpawnOptions = {
	Tiny: boolean?,
	Golden: boolean?,
	FromSky: boolean?,
	Elite: boolean?,
	Behavior: string?,
	DirX: number?,
	DirZ: number?,
	Life: number?,
	NoScale: boolean?,
	Force: boolean?, -- ignore the enemy cap (bosses, event specials)
	HPMult: number?,
}

function EnemyManager.Count(run): number
	return #run.Enemies
end

function EnemyManager.Spawn(run, key: string, x: number, z: number, opts: SpawnOptions?)
	local o = opts or {}
	if not o.Force and #run.Enemies >= run.MaxEnemies then
		return nil
	end
	local def = EnemyData.Get(key)
	local t = run.Time
	local hpScale = if o.NoScale then 1 else WaveData.HPScale(t)
	local dmgScale = if o.NoScale then 1 else WaveData.DamageScale(t)
	if def.Boss or def.MiniBoss then
		-- bosses scale with the player's level so a strong build still has a fight
		hpScale = 1 + max(0, run.Level - 10) * 0.025
		dmgScale = WaveData.DamageScale(t)
	end
	local hp = def.HP * hpScale * (o.HPMult or 1)
	local radius, speed = def.Radius, def.Speed
	if o.Tiny then
		hp *= 0.34
		radius *= 0.6
		speed *= 1.15
	end
	if o.Elite then
		hp *= 3
		radius *= 1.3
	end
	x = math.clamp(x, -HALF, HALF)
	z = math.clamp(z, -HALF, HALF)
	local e = {
		Uid = run:NewUid(),
		Id = allocId(run),
		Def = def,
		Key = key,
		X = x,
		Z = z,
		SentX = x,
		SentZ = z,
		HP = hp,
		MaxHP = hp,
		Speed = speed,
		Damage = def.Damage * dmgScale,
		Radius = radius,
		Mass = def.Mass * (if o.Elite then 2 else 1),
		KX = 0,
		KZ = 0,
		SlowUntil = 0,
		SlowFactor = 1,
		FrozenUntil = 0,
		Tiny = o.Tiny == true,
		Golden = o.Golden == true,
		Behavior = o.Behavior or def.Behavior,
		DirX = o.DirX or 0,
		DirZ = o.DirZ or 0,
		T = 0,
		State = 0,
		Side = if run.Rng:NextNumber() < 0.5 then -1 else 1,
		Life = if o.Life then t + o.Life elseif def.Params.Lifetime then t + def.Params.Lifetime else nil,
		Alive = true,
		IsBoss = def.Boss == true or def.MiniBoss == true,
		NoContact = def.NoContact == true,
		SpawnedAt = t,
		Index = 0,
	}
	if e.Behavior == "Blink" then
		e.T = def.Params.Every * run.Rng:NextNumber(0.5, 1)
	elseif e.Behavior == "Strafe" then
		e.T = def.Params.ShootEvery * run.Rng:NextNumber(0.4, 1)
	elseif e.Behavior == "Orbit" then
		local dx, dz = x - run.PX, z - run.PZ
		e.Angle = atan2(dz, dx)
	end
	table.insert(run.Enemies, e)
	e.Index = #run.Enemies
	run.EnemyById[e.Id] = e
	local flags = 0
	if e.Tiny then
		flags += FLAGS.Tiny
	end
	if e.Golden then
		flags += FLAGS.Golden
	end
	if o.FromSky then
		flags += FLAGS.FromSky
	end
	if e.IsBoss then
		flags += FLAGS.Boss
	end
	if o.Elite then
		flags += FLAGS.Elite
	end
	run:Write("Spawn", e.Id, def.Id, x, z, flags)
	run.Result.Seen = run.Result.Seen or {}
	run.Result.Seen[key] = true
	if e.IsBoss then
		Bosses.Init(run, e)
	end
	return e
end

-- A spawn point on a ring around the player, inside the arena
function EnemyManager.RingPoint(run, rMin: number, rMax: number): (number, number)
	local rng = run.Rng
	for _ = 1, 8 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(rMin, rMax)
		local x, z = run.PX + cos(a) * r, run.PZ + sin(a) * r
		if abs(x) <= HALF and abs(z) <= HALF and not EnemyManager.InsideCollider(run, x, z, 1.5) then
			return x, z
		end
	end
	local a = rng:NextNumber(0, math.pi * 2)
	return math.clamp(run.PX + cos(a) * rMin, -HALF, HALF), math.clamp(run.PZ + sin(a) * rMin, -HALF, HALF)
end

---------------------------------------------------------------------------
-- removal / damage
---------------------------------------------------------------------------
local function remove(run, e)
	if not e.Alive then
		return
	end
	e.Alive = false
	local list = run.Enemies
	local i = e.Index
	local last = list[#list]
	list[i] = last
	last.Index = i
	list[#list] = nil
	run.EnemyById[e.Id] = nil
end

-- silently removes an enemy (timed out, event over)
function EnemyManager.Despawn(run, e)
	if not e.Alive then
		return
	end
	remove(run, e)
	run:Write("Death", e.Id, 1)
	if run.Boss == e then
		run.Boss = nil
	end
end

local ITEM_TABLE = { { "Pizza", 38 }, { "Magnet", 22 }, { "Nuke", 12 }, { "CoinBag", 28 } }

local function rollItem(run): string
	local total = 0
	for _, entry in ITEM_TABLE do
		total += entry[2]
	end
	local r = run.Rng:NextNumber(0, total)
	for _, entry in ITEM_TABLE do
		r -= entry[2]
		if r <= 0 then
			return entry[1]
		end
	end
	return "Pizza"
end

function EnemyManager.Kill(run, e)
	if not e.Alive then
		return
	end
	remove(run, e)
	run:Write("Death", e.Id, 0)
	local def = e.Def
	local key = e.Key
	local luck = run.Stats.Luck
	local result = run.Result

	if key == "Crate" then
		result.Crates += 1
		Pickups.SpawnItem(run, rollItem(run), e.X, e.Z)
		return
	end

	run.Kills += 1
	result.EnemyKills[key] = (result.EnemyKills[key] or 0) + 1

	-- XP gem
	if def.XP > 0 then
		Pickups.SpawnGem(run, e.X, e.Z, def.XP * (if e.Golden then 5 else 1))
	end
	-- special rewards
	local params = def.Params
	if params.Coins then
		run:AddCoins(params.Coins)
	elseif run.Rng:NextNumber() < def.CoinChance * luck then
		Pickups.SpawnItem(run, "Coin", e.X + run.Rng:NextNumber(-1, 1), e.Z + run.Rng:NextNumber(-1, 1))
	end
	if params.Chest then
		Pickups.SpawnItem(run, "Chest", e.X, e.Z)
	end
	if def.ItemChance > 0 and run.Rng:NextNumber() < GameConfig.Drops.BaseItemChance * def.ItemChance * luck then
		Pickups.SpawnItem(run, rollItem(run), e.X, e.Z)
	end
	if params.SplitInto and not e.Tiny then
		for i = 1, params.SplitCount do
			local a = (i / params.SplitCount) * math.pi * 2
			EnemyManager.Spawn(run, params.SplitInto, e.X + cos(a) * 1.5, e.Z + sin(a) * 1.5)
		end
	end
	if key == "GoldenGoober" then
		result.Flags.GoldenGoober = true
	elseif key == "TheNPC" then
		result.Flags.JustStanding = true
		run:Banner("IT WAS JUST STANDING THERE", "You monster.", "Secret")
	end
	if e.IsBoss then
		Bosses.OnKilled(run, e, EnemyManager)
	end
end

function EnemyManager.Damage(run, e, dmg: number, hitFlags: number, kx: number, kz: number, knock: number)
	if not e.Alive or dmg <= 0 then
		return
	end
	e.HP -= dmg
	if run.FrameHits < GameConfig.Sim.MaxHitsPerFrame or dmg >= 100 or e.IsBoss then
		run.FrameHits += 1
		run:Write("Hit", e.Id, dmg, hitFlags)
	end
	if knock > 0 then
		local len = sqrt(kx * kx + kz * kz)
		if len > 1e-3 then
			local v = knock * 4 / e.Mass
			e.KX += kx / len * v
			e.KZ += kz / len * v
		end
	end
	if e.HP <= 0 then
		EnemyManager.Kill(run, e)
	end
end

function EnemyManager.Slow(e, factor: number, duration: number, now: number)
	if e.IsBoss then
		factor = 1 - (1 - factor) * 0.4
	end
	if e.SlowUntil <= now then
		e.SlowFactor = 1
	end
	e.SlowFactor = min(e.SlowFactor, factor)
	e.SlowUntil = max(e.SlowUntil, now + duration)
end

-- pushes every non-boss enemy in a radius away from (x, z)
function EnemyManager.Shockwave(run, x: number, z: number, radius: number, knock: number, damage: number)
	local n = SpatialGrid.Query(run.Grid, x, z, radius + 3, scratch)
	local list = table.move(scratch, 1, n, 1, {})
	for _, e in list do
		if e.Alive and not e.IsBoss then
			local dx, dz = e.X - x, e.Z - z
			if dx * dx + dz * dz <= (radius + e.Radius) ^ 2 then
				if damage > 0 then
					EnemyManager.Damage(run, e, damage, 0, dx, dz, knock)
				else
					local len = max(0.1, sqrt(dx * dx + dz * dz))
					local v = knock * 4 / e.Mass
					e.KX += dx / len * v
					e.KZ += dz / len * v
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- obstacles (static colliders from the map, bucketed in a coarse grid)
---------------------------------------------------------------------------
local function collidersNear(run, x: number, z: number)
	local c = run.Colliders
	if not c then
		return nil
	end
	return c.Cells[floor(x / c.Cell) * 4096 + floor(z / c.Cell)]
end

function EnemyManager.InsideCollider(run, x: number, z: number, r: number): boolean
	local list = collidersNear(run, x, z)
	if not list then
		return false
	end
	for _, col in list do
		if x > col.MinX - r and x < col.MaxX + r and z > col.MinZ - r and z < col.MaxZ + r then
			return true
		end
	end
	return false
end

-- Moves e out of any collider; returns the push normal (0, 0 if none)
local function pushOut(run, e): (number, number)
	local list = collidersNear(run, e.X, e.Z)
	if not list then
		return 0, 0
	end
	local r = e.Radius
	local nx, nz = 0, 0
	for _, col in list do
		local x0, x1, z0, z1 = col.MinX - r, col.MaxX + r, col.MinZ - r, col.MaxZ + r
		local x, z = e.X, e.Z
		if x > x0 and x < x1 and z > z0 and z < z1 then
			local left, right, down, up = x - x0, x1 - x, z - z0, z1 - z
			local m = min(left, right, down, up)
			if m == left then
				e.X = x0
				nx -= 1
			elseif m == right then
				e.X = x1
				nx += 1
			elseif m == down then
				e.Z = z0
				nz -= 1
			else
				e.Z = z1
				nz += 1
			end
		end
	end
	return nx, nz
end

---------------------------------------------------------------------------
-- behaviours: return the desired move direction (unit or zero) and a speed multiplier
---------------------------------------------------------------------------
local Behaviors = {}

function Behaviors.Chase(_run, e, dx, dz, d)
	if d < (e.Radius + PLAYER_R) * 0.85 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 1
end

function Behaviors.Charge(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if e.State == 0 then
		if d < p.Trigger then
			e.State = 1
			e.T = p.Windup
			run:Write("EState", e.Id, 1)
			return 0, 0, 0
		end
		return Behaviors.Chase(run, e, dx, dz, d)
	elseif e.State == 1 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 2
			e.T = p.DashTime
			e.DirX, e.DirZ = dx / d, dz / d
			run:Write("EState", e.Id, 2)
		end
		return 0, 0, 0
	elseif e.State == 2 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 3
			e.T = p.Rest
			run:Write("EState", e.Id, 0)
		end
		return e.DirX, e.DirZ, p.DashSpeed / e.Speed
	end
	e.T -= dt
	if e.T <= 0 then
		e.State = 0
	end
	local x, z = Behaviors.Chase(run, e, dx, dz, d)
	return x, z, 0.5
end

function Behaviors.Flee(_run, e, dx, dz, d)
	local keep = 34
	if d < keep then
		return -dx / d, -dz / d, 1
	end
	-- circle around the player at a distance (so it stays catchable)
	local tx, tz = -dz / d * e.Side, dx / d * e.Side
	return tx, tz, 0.6
end

function Behaviors.Strafe(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.T <= 0 and d < p.Orbit + 18 then
		e.T = p.ShootEvery
		local vx, vz = dx / d * p.ProjSpeed, dz / d * p.ProjSpeed
		EnemyManager.Shoot(run, e.X, e.Z, vx, vz, p.ProjRadius, p.ProjDamage * WaveData.DamageScale(run.Time), p.ProjLife)
	end
	if d > p.Orbit + 4 then
		return dx / d, dz / d, 1
	elseif d < p.Orbit - 4 then
		return -dx / d, -dz / d, 0.8
	end
	return -dz / d * e.Side, dx / d * e.Side, 0.7
end

function Behaviors.Blink(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.T <= 0 then
		e.T = p.Every
		if d > p.MinRange + 2 then
			local jump = min(p.Distance, d - p.MinRange)
			e.X += dx / d * jump
			e.Z += dz / d * jump
			e.SentX, e.SentZ = e.X, e.Z
			run:Write("Blink", e.Id, e.X, e.Z)
			return 0, 0, 0
		end
	end
	return Behaviors.Chase(run, e, dx, dz, d)
end

function Behaviors.Orbit(run, e, _dx, _dz, _d, dt)
	local r = e.Def.Params.Radius
	e.Angle = (e.Angle or 0) + (e.Speed / r) * dt * e.Side
	local tx, tz = run.PX + cos(e.Angle) * r, run.PZ + sin(e.Angle) * r
	local mx, mz = tx - e.X, tz - e.Z
	local m = sqrt(mx * mx + mz * mz)
	if m < 0.01 then
		return 0, 0, 0
	end
	return mx / m, mz / m, min(1.4, m / 3)
end

function Behaviors.Stand(run, e, dx, dz, d)
	if d < 6 then
		return 0, 0, 0
	end
	return Behaviors.Chase(run, e, dx, dz, d)
end

function Behaviors.Static()
	return 0, 0, 0
end

function Behaviors.March(_run, e)
	return e.DirX, e.DirZ, 1
end

function Behaviors.Boss(run, e, dx, dz, d, dt)
	return Bosses.Step(run, e, dx, dz, d, dt, EnemyManager)
end

---------------------------------------------------------------------------
-- enemy projectiles (straight, deterministic: the client simulates them from one record)
---------------------------------------------------------------------------
function EnemyManager.Shoot(run, x: number, z: number, vx: number, vz: number, radius: number, damage: number, life: number)
	if #run.EnemyProjectiles >= GameConfig.Sim.MaxEnemyProjectiles then
		return
	end
	run.NextEProj = (run.NextEProj or 0) % 65535 + 1
	local p = { Id = run.NextEProj, X = x, Z = z, VX = vx, VZ = vz, R = radius, Damage = damage, Life = life }
	table.insert(run.EnemyProjectiles, p)
	run:Write("EProj", p.Id, x, z, vx, vz, radius, life)
end

local function stepEnemyProjectiles(run, dt: number)
	local list = run.EnemyProjectiles
	local px, pz = run.PX, run.PZ
	local i = 1
	while i <= #list do
		local p = list[i]
		p.X += p.VX * dt
		p.Z += p.VZ * dt
		p.Life -= dt
		local dx, dz = p.X - px, p.Z - pz
		local hit = dx * dx + dz * dz <= (p.R + PLAYER_R) ^ 2
		if hit then
			run:HurtPlayer(p.Damage, true)
			run:Write("EProjEnd", p.Id)
		end
		if hit or p.Life <= 0 then
			list[i] = list[#list]
			list[#list] = nil
		else
			i += 1
		end
	end
end

---------------------------------------------------------------------------
-- step
---------------------------------------------------------------------------
function EnemyManager.RebuildGrid(run)
	local grid = run.Grid
	SpatialGrid.Clear(grid)
	for _, e in run.Enemies do
		SpatialGrid.Insert(grid, e, e.X, e.Z)
	end
end

function EnemyManager.Step(run, dt: number)
	local px, pz = run.PX, run.PZ
	local now = run.Time
	local stormMult = if run:Buff("Storm") then 1.2 else 1
	local relocate = GameConfig.Arena.RelocateDistance
	local grid = run.Grid
	local knockDecay = exp(-7 * dt)

	EnemyManager.RebuildGrid(run)

	local touchMax, touchCount = 0, 0
	local expired = nil
	-- index loop over the enemies that existed at the start of the step: bosses summon
	-- during the loop (appended at the end, they move from the next step on)
	local list = run.Enemies
	for index = 1, #list do
		local e = list[index]
		local dx, dz = px - e.X, pz - e.Z
		local d = sqrt(dx * dx + dz * dz)
		if d < 0.01 then
			d = 0.01
		end

		local dirX, dirZ, mult = 0, 0, 0
		if e.FrozenUntil > now then
			mult = 0
		else
			local behavior = Behaviors[e.Behavior] or Behaviors.Chase
			dirX, dirZ, mult = behavior(run, e, dx, dz, d, dt)
		end
		local slow = if e.SlowUntil > now then e.SlowFactor else 1
		if e.SlowUntil <= now then
			e.SlowFactor = 1
		end
		local speed = e.Speed * mult * slow * stormMult

		-- crowd separation (a few neighbours are enough to spread a horde)
		local sepX, sepZ = 0, 0
		if not e.IsBoss and e.Behavior ~= "Static" then
			local n = SpatialGrid.Query(grid, e.X, e.Z, e.Radius * 2, scratch)
			local checked = 0
			for k = 1, n do
				local o = scratch[k]
				if o ~= e then
					local ox, oz = e.X - o.X, e.Z - o.Z
					local rr = e.Radius + o.Radius
					local dd = ox * ox + oz * oz
					if dd < rr * rr then
						local dist = sqrt(dd)
						if dist < 1e-3 then
							ox, oz, dist = e.Side * 0.1, 0.1, 0.14
						end
						local push = (rr - dist) / rr
						local weight = if o.IsBoss then 2.5 else 1
						sepX += ox / dist * push * weight
						sepZ += oz / dist * push * weight
					end
					checked += 1
					if checked >= 10 then
						break
					end
				end
			end
		end

		e.X += (dirX * speed + e.KX + sepX * 9) * dt
		e.Z += (dirZ * speed + e.KZ + sepZ * 9) * dt
		e.KX *= knockDecay
		e.KZ *= knockDecay

		-- obstacles: push out, then slide along the wall around the obstacle
		local nx, nz = pushOut(run, e)
		if nx ~= 0 or nz ~= 0 then
			local tx, tz = -nz * e.Side, nx * e.Side
			e.X += tx * speed * dt * 0.8
			e.Z += tz * speed * dt * 0.8
			pushOut(run, e)
		end
		if e.X < -HALF then
			e.X = -HALF
		elseif e.X > HALF then
			e.X = HALF
		end
		if e.Z < -HALF then
			e.Z = -HALF
		elseif e.Z > HALF then
			e.Z = HALF
		end

		-- left far behind: reappear ahead of the player (the horde never thins out)
		if d > relocate and not e.IsBoss and e.Behavior ~= "March" and e.Behavior ~= "Static" and e.Behavior ~= "Flee" then
			local fx, fz = run.FX, run.FZ
			local a = atan2(fz, fx) + run.Rng:NextNumber(-0.9, 0.9)
			local r = run.Rng:NextNumber(GameConfig.Arena.SpawnRadiusMin, GameConfig.Arena.SpawnRadiusMax)
			e.X = math.clamp(px + cos(a) * r, -HALF, HALF)
			e.Z = math.clamp(pz + sin(a) * r, -HALF, HALF)
			e.SentX, e.SentZ = e.X, e.Z
			run:Write("Blink", e.Id, e.X, e.Z)
		end

		-- contact with the player
		if not e.NoContact then
			local cx, cz = px - e.X, pz - e.Z
			local reach = e.Radius + PLAYER_R + 0.3
			if cx * cx + cz * cz <= reach * reach then
				touchCount += 1
				local dmg = e.Damage
				if e.Dashing then
					dmg = e.DashDamage or dmg
				end
				if dmg > touchMax then
					touchMax = dmg
				end
			end
		end

		if e.Life and now >= e.Life then
			expired = expired or {}
			table.insert(expired, e)
		end
	end

	if touchCount > 0 then
		-- swarmed: the strongest hit + a little per extra attacker
		run:HurtPlayer(touchMax + min(touchCount - 1, 6) * 1.5)
	end

	if expired then
		for _, e in expired do
			if e.Key == "Goblin67" then
				run:Banner("THE 67 GOBLIN ESCAPED", "Next time, bro.", "Info")
			elseif e.Key == "Runner" then
				run:Banner("HE GOT AWAY", "We still don't know why he was running.", "Info")
			end
			EnemyManager.Despawn(run, e)
		end
	end

	stepEnemyProjectiles(run, dt)
	Bosses.StepTelegraphs(run, EnemyManager)
	EnemyManager.RebuildGrid(run)
end

return EnemyManager
