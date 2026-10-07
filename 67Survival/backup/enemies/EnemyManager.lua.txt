--[[
	EnemyManager - enemies of a run: spawn, AI behaviours, movement, crowd separation,
	obstacle avoidance, contact damage, burning, damage / death / drops.

	Enemies are plain tables (no Instances). One pass per simulation step handles every
	enemy; neighbour queries go through the run's SpatialGrid. Anything that can kill an
	enemy during that pass (burning, bomber blasts, thorns) is applied after it.

	Behaviours (shared/EnemyData.lua Behavior):
	  Chase Charge Strafe Blink Bomber Dive Summoner Phase Leap Mimic Sniper
	  Flee (67 Goblin)  Sixty (THE 67)  Static (loot box)  March (formations)  Boss
	  Champion (the MINI-BOSSES of 67 TOWN: Sim/MiniBosses.lua)
	  the harder tiers: Sleep (Snoozer) Shield (Shielder) Stampede Banner (Bannerman, an
	  aura: faster) Wail (a ring with a gap) Hex (a curse circle) Cinder (a fire trail)
	  Mortar (Eruptor) Predator (runs where you will be) Ward (Warden, an aura: tougher)
	  Egg Rally (war banner) Converge (a shrinking formation)
	SIXLET / SEVENLET come as a pair (EnemyManager.Pair): kill one and the other rages 3 s
	later, unless it falls too. Sketches (THE ERASER's Redraw) drop nothing.

	67 TOWN (Sim/ArenaDirector.lua): the horde never spawns in the sealed rift or behind a wall
	from you, the zone scales XP / coins, kills fill the zone's threat meter; enemies stuck on
	a wall for a while are moved ahead of you like stragglers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local ArenaData = require(Shared.ArenaData)
local EnemyData = require(Shared.EnemyData)
local WaveData = require(Shared.WaveData)
local Protocol = require(Shared.Protocol)

local SpatialGrid = require(script.Parent.SpatialGrid)
local Bosses = require(script.Parent.Bosses)
local Pickups = require(script.Parent.Pickups)
local MiniBosses = require(script.Parent.MiniBosses)
local ArenaDirector = require(script.Parent.ArenaDirector)
local Perks = require(script.Parent.Perks)
local Elites = require(script.Parent.Elites)

local EnemyManager = {}

local sqrt, exp, min, max, abs, floor = math.sqrt, math.exp, math.min, math.max, math.abs, math.floor
local cos, sin, atan2 = math.cos, math.sin, math.atan2
local TAU = math.pi * 2
local FLAGS = Protocol.Flags
local ES = Protocol.EState
local GFX = Protocol.Fx
local SHAPE = Protocol.Shapes
local PLAYER_R = GameConfig.Player.Radius
local HALF = GameConfig.Arena.HalfSize
local scratch = {}
local auraScratch = {}
local NO_DIFF = { EnemyHP = 1, EnemyDamage = 1, EnemySpeed = 1, BossHP = 1, BossDamage = 1 }

-- NO MERCY difficulty: shorter wind-ups (the telegraph is shortened too: always fair)
local function windup(run, seconds: number): number
	return seconds * (run.Windup or 1)
end

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

-- visual state for the client (windup flash, dash, phased...)
local function setState(run, e, state: number)
	if e.VState ~= state then
		e.VState = state
		run:Write("EState", e.Id, state)
	end
end
EnemyManager.SetState = setState

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
	DamageMult: number?, -- the zone's danger
	Encounter: any?, -- a boss of the timeline: its encounter (Sim/MiniBosses)
	BossHP: number?, -- ... and its HP
	BossDamage: number?, -- ... and its damage multiplier (shared/BossData.lua Slots Damage)
	HomeX: number?, -- mini-boss: its lair
	HomeZ: number?,
	Sketch: boolean?, -- THE ERASER's redrawn copy: no loot
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
	local diff = run.Diff or NO_DIFF
	local hpScale = if o.NoScale then 1 else WaveData.HPScale(t)
	local dmgScale = if o.NoScale then 1 else WaveData.DamageScale(t)
	local champion = def.Champion == true
	local isBoss = def.Boss == true or def.MiniBoss == true or champion
	-- difficulty: the horde (and THE 67) gets tougher; loot boxes and the goblin do not
	if not o.NoScale or key == "The67" then
		hpScale *= diff.EnemyHP
		dmgScale *= diff.EnemyDamage
	end
	if champion then
		-- mini-bosses grow with the run (and a little with a strong build)
		hpScale = WaveData.HPScale(t) * (1 + max(0, run.Level - 10) * 0.02) * diff.BossHP
		dmgScale = WaveData.DamageScale(t) * diff.BossDamage
	elseif isBoss then
		-- bosses scale with the player's level so a strong build still has a fight
		hpScale = (1 + max(0, run.Level - 10) * 0.025) * diff.BossHP
		dmgScale = WaveData.DamageScale(t) * diff.BossDamage
	end
	local hp = def.HP * hpScale * (o.HPMult or 1)
	if o.BossHP then
		hp = o.BossHP -- a boss of the timeline: its HP comes from shared/BossData.lua (Sim/MiniBosses)
	end
	if o.BossDamage then
		dmgScale = o.BossDamage * diff.BossDamage
	end
	local radius, speed = def.Radius, def.Speed
	if not isBoss and not o.NoScale then
		speed *= diff.EnemySpeed -- FASTER HORDE
	end
	local tiny = o.Tiny == true or (not isBoss and run:Buff("TinyMode"))
	local giant = not isBoss and not tiny and run:Buff("GiantMode") and def.Behavior ~= "Static"
	if tiny then
		hp *= 0.33
		radius *= 0.6
		speed *= 1.1
	elseif giant then
		hp *= 2
		radius *= 1.5
		speed *= 0.85
	end
	if o.Elite then
		hp *= GameConfig.Elite.HP
		radius *= GameConfig.Elite.Size
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
		Damage = def.Damage * dmgScale * (o.DamageMult or 1) * (if o.Elite then GameConfig.Elite.Damage else 1),
		DmgScale = dmgScale,
		Radius = radius,
		Mass = def.Mass * (if o.Elite then 2 elseif giant then 1.5 else 1),
		KX = 0,
		KZ = 0,
		SlowUntil = 0,
		SlowFactor = 1,
		FrozenUntil = 0,
		Tiny = tiny,
		Giant = giant,
		Golden = o.Golden == true,
		Elite = o.Elite == true,
		Behavior = o.Behavior or def.Behavior,
		DirX = o.DirX or 0,
		DirZ = o.DirZ or 0,
		T = 0,
		State = 0,
		VState = 0,
		Side = if run.Rng:NextNumber() < 0.5 then -1 else 1,
		Life = if o.Life then t + o.Life elseif def.Params.Lifetime then t + def.Params.Lifetime else nil,
		Alive = true,
		IsBoss = isBoss,
		NoContact = def.NoContact == true,
		SpawnedAt = t,
		Index = 0,
		Sketch = o.Sketch == true,
	}
	local p = def.Params
	local b = e.Behavior
	local rng = run.Rng
	if p.GuardHP then
		e.Guard = hp * p.GuardHP -- a Shielder's shield (EnemyManager.Damage)
	end
	if p.ShotRoom then
		run.ShotRoom = p.ShotRoom -- a main boss of the harder tiers: room for its rings
	end
	if b == "Wail" or b == "Hex" or b == "Mortar" then
		e.T = p.Every * rng:NextNumber(0.4, 1)
	elseif b == "Cinder" then
		e.T = p.TrailEvery
	elseif b == "Banner" or b == "Ward" or b == "Rally" then
		e.T = rng:NextNumber(0, 0.5)
	elseif b == "Egg" then
		e.T = p.Hatch
	elseif b == "Sleep" then
		e.Dormant = true
	elseif b == "Blink" or b == "Summoner" or b == "Sniper" then
		e.T = p.Every * rng:NextNumber(0.4, 1)
	elseif b == "Strafe" then
		e.T = p.ShootEvery * rng:NextNumber(0.4, 1)
	elseif b == "Phase" then
		e.T = p.Solid * rng:NextNumber(0.5, 1)
	elseif b == "Dive" then
		e.T = p.Circle * rng:NextNumber(0.6, 1)
		e.Angle = atan2(z - run.PZ, x - run.PX)
	elseif b == "Sixty" then
		e.T = p.Every * 0.5
		e.Angle = atan2(z - run.PZ, x - run.PX)
	elseif b == "Mimic" then
		e.Dormant = true
	end
	table.insert(run.Enemies, e)
	e.Index = #run.Enemies
	run.EnemyById[e.Id] = e
	local flags = 0
	if tiny then
		flags += FLAGS.Tiny
	end
	if e.Golden then
		flags += FLAGS.Golden
	end
	if o.FromSky then
		flags += FLAGS.FromSky
	end
	if isBoss and not champion then
		flags += FLAGS.Boss
	end
	if champion then
		flags += FLAGS.Champion
	end
	if o.Elite then
		flags += FLAGS.Elite
	end
	if giant then
		flags += FLAGS.Giant
	end
	if e.Sketch then
		flags += FLAGS.Sketch
	end
	run:Write("Spawn", e.Id, def.Id, x, z, flags)
	if e.Dormant then
		setState(run, e, ES.Dormant)
	end
	if o.Encounter or champion then
		MiniBosses.Init(run, e, o) -- a boss of the timeline: its lair / the arena (debug: where it stands)
	end
	if isBoss and not champion then
		Bosses.Init(run, e)
	end
	return e
end

-- SIXLET + SEVENLET: kill one and the other rages (unless it falls within RageDelay too)
function EnemyManager.Pair(a, b)
	a.Partner, b.Partner = b, a
end

-- true when a wall stands between (x0, z0) and (x1, z1) (sampled every few studs)
function EnemyManager.WallBetween(run, x0: number, z0: number, x1: number, z1: number): boolean
	if not run.Colliders then
		return false
	end
	local dx, dz = x1 - x0, z1 - z0
	local n = math.ceil(sqrt(dx * dx + dz * dz) / 6)
	for i = 1, n - 1 do
		local f = i / n
		if EnemyManager.InsideCollider(run, x0 + dx * f, z0 + dz * f, 0.3) then
			return true
		end
	end
	return false
end

-- A spawn point on a ring around the player, inside the arena: not in a wall, not in the
-- sealed rift, not behind a wall from the player (the horde has to reach you)
function EnemyManager.RingPoint(run, rMin: number, rMax: number): (number, number)
	local rng = run.Rng
	local fallbackX, fallbackZ = nil, nil
	for _ = 1, 10 do
		local a = rng:NextNumber(0, TAU)
		local r = rng:NextNumber(rMin, rMax)
		local x, z = run.PX + cos(a) * r, run.PZ + sin(a) * r
		if abs(x) <= HALF and abs(z) <= HALF and not EnemyManager.InsideCollider(run, x, z, 1.5) and not (run.Map and ArenaDirector.SpawnBlocked(run, x, z)) then
			if not EnemyManager.WallBetween(run, run.PX, run.PZ, x, z) then
				return x, z
			end
			fallbackX, fallbackZ = fallbackX or x, fallbackZ or z
		end
	end
	if fallbackX and fallbackZ then
		return fallbackX, fallbackZ
	end
	for _ = 1, 8 do
		local a = rng:NextNumber(0, TAU)
		local x, z = math.clamp(run.PX + cos(a) * rMin, -HALF, HALF), math.clamp(run.PZ + sin(a) * rMin, -HALF, HALF)
		if not (run.Map and ArenaDirector.SpawnBlocked(run, x, z)) then
			return x, z
		end
	end
	return math.clamp(run.PX, -HALF, HALF), math.clamp(run.PZ + rMin, -HALF, HALF)
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
	if run.Boss == e then
		run.Boss = nil
	end
end

-- silently removes an enemy (timed out, event over)
function EnemyManager.Despawn(run, e)
	if not e.Alive then
		return
	end
	remove(run, e)
	run:Write("Death", e.Id, 1)
end

local ITEM_TABLE = { { "Snack", 38 }, { "Magnet", 22 }, { "Nuke", 12 }, { "CoinBag", 28 } }

function EnemyManager.RollItem(run): string
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
	return "Snack"
end

-- a Bomber's blast: hurts the player inside the circle and the horde around it
local function bomberBlast(run, e, hurtPlayer: boolean)
	local p = e.Def.Params
	local r = p.BlastRadius * (if e.Giant then 1.4 else 1)
	run:Write("Fx", 0, e.X, e.Z, 0, r, 0, GFX.Bomb)
	if hurtPlayer then
		local dx, dz = run.PX - e.X, run.PZ - e.Z
		if dx * dx + dz * dz <= (r + PLAYER_R * 0.5) ^ 2 then
			run:HurtPlayer(p.BlastDamage * e.DmgScale, true)
		end
	end
	-- chain reactions: the blast hurts other enemies (a reward for killing it lit)
	local n = SpatialGrid.Query(run.Grid, e.X, e.Z, r + 3, scratch)
	local victims = table.move(scratch, 1, n, 1, {})
	local dmg = 30 * WaveData.HPScale(run.Time)
	for _, o in victims do
		if o ~= e and o.Alive and not o.IsBoss then
			local dx, dz = o.X - e.X, o.Z - e.Z
			if dx * dx + dz * dz <= (r + o.Radius) ^ 2 then
				EnemyManager.Damage(run, o, dmg, 0, dx, dz, 6)
			end
		end
	end
end

function EnemyManager.Kill(run, e)
	if not e.Alive then
		return
	end
	remove(run, e)
	run:Write("Death", e.Id, 0)
	local def = e.Def
	local key = e.Key
	local rng = run.Rng
	local luck = run.Stats.Luck
	local result = run.Result

	if key == "Crate" then
		result.Crates += 1
		Pickups.SpawnItem(run, EnemyManager.RollItem(run), e.X, e.Z)
		return
	end
	-- a sketch (THE ERASER) or a lane runner (THE HORDEMASTER) leaves nothing behind
	if e.Sketch or e.Runner then
		return
	end
	-- SIXLET / SEVENLET: the other one notices (it shakes) and goes mad RageDelay s later
	local mate = e.Partner
	if mate and mate.Alive and not mate.GriefUntil then
		mate.GriefUntil = run.Time + mate.Def.Params.RageDelay
		setState(run, mate, ES.Windup)
	end
	-- THE HORDEMASTER's war banner: its megaphone is open
	if e.Owner and e.Behavior == "Rally" then
		local owner = e.Owner
		owner.Banner = nil
		run:Write("Fx", 0, e.X, e.Z, 0, 6, 0, GFX.ShieldBreak)
		if owner.Alive then
			MiniBosses.Expose(run, owner, "Banner")
		end
	end

	run.Kills += 1
	result.EnemyKills[key] = (result.EnemyKills[key] or 0) + 1
	run:OnKill(e)

	-- XP gem (the zone it died in pays more or less; an elite pays a burst: Sim/Elites)
	if def.XP > 0 and not e.Elite then
		local xp = def.XP * (if e.Golden then 5 elseif e.Giant then 1.5 else 1)
		if run.Map then
			xp *= ArenaDirector.XPMult(run, e.X, e.Z)
		end
		Pickups.SpawnGem(run, e.X, e.Z, xp)
	end
	-- coins / items
	local params = def.Params
	local coinChance = def.CoinChance * luck * (if run.Mech == "Hoarder" then 1.5 else 1) * (if run.Map then ArenaDirector.CoinMult(run, e.X, e.Z) else 1)
	if params.Coins then
		run:AddCoins(params.Coins)
	elseif rng:NextNumber() < coinChance then
		Pickups.SpawnItem(run, "Coin", e.X + rng:NextNumber(-1, 1), e.Z + rng:NextNumber(-1, 1))
	end
	if params.Chest then
		Pickups.SpawnItem(run, if key == "The67" then "Chest67" else "Chest", e.X, e.Z)
	end
	if def.ItemChance > 0 and rng:NextNumber() < GameConfig.Drops.BaseItemChance * def.ItemChance * luck then
		Pickups.SpawnItem(run, EnemyManager.RollItem(run), e.X, e.Z)
	end
	if e.Elite then
		Elites.OnKilled(run, e, EnemyManager)
	end
	if params.SplitInto and not e.Tiny then
		for i = 1, params.SplitCount do
			local a = (i / params.SplitCount) * TAU
			EnemyManager.Spawn(run, params.SplitInto, e.X + cos(a) * 1.5, e.Z + sin(a) * 1.5)
		end
	end
	if e.Lit then
		bomberBlast(run, e, false)
	end

	if key == "GoldenGoober" then
		result.Flags.GoldenGoober = true
		run:Event("Secret", { Key = "GoldenGoober", Title = "GOLDEN GOOBER", Sub = "1 in 500. Lucky you." })
	elseif key == "The67" then
		result.Flags.DefeatThe67 = true
		result.Fragments += GameConfig.Rewards.FragmentsThe67
		run:Write("Fx", 0, e.X, e.Z, 0, 30, 0, GFX.Blast67)
		run:Banner("THE 67 DEFEATED", "+" .. GameConfig.Rewards.FragmentsThe67 .. " fragments. Something was unlocked...", "Secret")
	elseif key == "Mimic" then
		run:Write("Fx", 0, e.X, e.Z, 0, 6, 0, GFX.Bomb)
	end
	if e.Encounter then
		MiniBosses.OnKilled(run, e, EnemyManager)
	elseif e.IsBoss then
		Bosses.OnKilled(run, e, EnemyManager)
	end
end

local function wake(run, e)
	if e.Dormant then
		e.Dormant = false
		if e.Behavior == "Sleep" then
			-- a Snoozer blinks awake before it runs
			e.State = 1
			e.T = windup(run, e.Def.Params.Blink)
			setState(run, e, ES.Windup)
		else
			setState(run, e, ES.Normal)
		end
	end
end

-- a hit on a Shielder's shield: from the front (the side it faces), mostly absorbed
local function guard(run, e, dmg: number, kx: number, kz: number): (number, boolean)
	local p = e.Def.Params
	-- where the hit came from: against its knockback, else from you
	local hx, hz = -kx, -kz
	if hx * hx + hz * hz < 1e-4 then
		hx, hz = run.PX - e.X, run.PZ - e.Z
	end
	local len = math.sqrt(hx * hx + hz * hz)
	local fx, fz = e.FaceX or 0, e.FaceZ or 0
	if len < 1e-3 or (fx * hx + fz * hz) / len < math.cos(p.GuardArc) then
		return dmg, false
	end
	local absorbed = dmg * p.GuardCut
	e.Guard -= absorbed
	dmg -= absorbed
	if e.Guard <= 0 then
		-- the shield breaks: the rest of the hit goes through
		dmg -= e.Guard
		e.Guard = nil
		e.GuardBroken = true
		setState(run, e, ES.Broken)
		run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2, 0, GFX.ShieldBreak)
	elseif run.Time >= (e.BlockFx or 0) then
		e.BlockFx = run.Time + 0.4
		run:Write("Fx", 0, e.X + (e.FaceX or 0) * e.Radius, e.Z + (e.FaceZ or 0) * e.Radius, 0, e.Radius, 0, GFX.Block)
	end
	return dmg, true
end

function EnemyManager.Damage(run, e, dmg: number, hitFlags: number, kx: number, kz: number, knock: number)
	if not e.Alive or dmg <= 0 or e.Phased or e.Shielded then
		return
	end
	if e.Dormant then
		wake(run, e)
	end
	local now = run.Time
	-- a SHIELDED elite: its shield eats whole hits (it comes back when left alone)
	if e.HitShield and e.HitShield > 0 then
		e.HitShield -= 1
		e.LastHitAt = now
		if e.HitShield == 0 then
			run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2, 0, GFX.ShieldBreak)
		elseif now >= (e.BlockFx or 0) then
			e.BlockFx = now + 0.3
			run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 1.4, 0, GFX.Block)
		end
		return
	end
	e.LastHitAt = now
	if e.ArmorCut then
		dmg *= 1 - e.ArmorCut -- an ARMORED elite
	end
	if e.WardUntil and e.WardUntil > now then
		dmg *= 1 - e.Ward -- inside a Warden's bubble
	end
	if e.Guard then
		local blocked
		dmg, blocked = guard(run, e, dmg, kx, kz)
		if blocked then
			knock *= 0.2 -- the shield holds its ground
		end
	end
	-- a THORNED elite: hitting it up close hurts you a little
	local thorns = e.Thorns
	if thorns and now >= (e.ThornAt or 0) then
		local dx, dz = run.PX - e.X, run.PZ - e.Z
		if dx * dx + dz * dz <= (thorns.Range + e.Radius) ^ 2 then
			e.ThornAt = now + thorns.Every
			run:HurtPlayer(thorns.Damage * e.DmgScale, true, "Thorns")
			run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 1.5, 0, GFX.Thorns)
		end
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

-- stops a normal enemy for a moment (abilities and items); frozen = the ice look
function EnemyManager.Stun(run, e, time: number, frozen: boolean?)
	if not e.Alive or e.IsBoss or e.Behavior == "Static" or time <= 0 then
		return
	end
	local control = run.UP and run.UP.Duration and run.UP.Duration.Control
	if control then
		time *= control -- Duration IV
	end
	local now = run.Time
	if e.FrozenUntil < now + time then
		e.FrozenUntil = now + time
		e.Thaw = true
		run:Write("EState", e.Id, if frozen then ES.Frozen else ES.Stunned)
	end
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

-- 67 MODE: TINY shrinks the horde that is already there
function EnemyManager.ShrinkAll(run, chance: number)
	for _, e in run.Enemies do
		if not e.IsBoss and not e.Tiny and e.Behavior ~= "Static" and e.Behavior ~= "Sixty" and run.Rng:NextNumber() < chance then
			e.Tiny = true
			e.Giant = false
			e.HP *= 0.33
			e.MaxHP *= 0.33
			e.Radius *= 0.6
			e.Speed *= 1.1
			run:Write("Shrink", e.Id)
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
-- enemy projectiles (straight, deterministic: the client simulates them from one record)
---------------------------------------------------------------------------
function EnemyManager.Shoot(run, x: number, z: number, vx: number, vz: number, radius: number, damage: number, life: number)
	if #run.EnemyProjectiles >= GameConfig.Sim.MaxEnemyProjectiles + (run.ShotRoom or 0) then
		return
	end
	-- an ECHO elite is shooting: the same shot again a moment later
	local src = run.Shooter
	if src and src.Echo then
		local delay = src.Echo.Delay
		table.insert(run.Echoes, {
			At = run.Time + delay,
			Fn = function()
				EnemyManager.Shoot(run, x, z, vx, vz, radius, damage, life)
			end,
		})
	end
	run.NextEProj = (run.NextEProj or 0) % 65535 + 1
	local k = run.ShotSpeed or 1 -- NO MERCY: faster shots (same reach)
	vx, vz, life = vx * k, vz * k, life / k
	local p = { Id = run.NextEProj, X = x, Z = z, VX = vx, VZ = vz, R = radius, Damage = damage, Life = life }
	table.insert(run.EnemyProjectiles, p)
	run:Write("EProj", p.Id, x, z, vx, vz, radius, life)
end

local function ringShots(run, e, count: number, speed: number, damage: number, offset: number)
	for i = 1, count do
		local a = offset + (i / count) * TAU
		EnemyManager.Shoot(run, e.X, e.Z, cos(a) * speed, sin(a) * speed, 1.3, damage, 5)
	end
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
			-- the Void Mirror sends it back; else it hurts (a volley shares the hurt cooldown)
			if not Perks.OnEnemyShot(run, p) then
				run:HurtPlayer(p.Damage, false, "Shot")
			end
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
-- behaviours: return the desired move direction (unit or zero) and a speed multiplier.
-- (dx, dz, d) point from the enemy to its target (the player, or the Clone decoy).
---------------------------------------------------------------------------
local Behaviors = {}

function Behaviors.Chase(_run, e, dx, dz, d)
	if d < (e.Radius + PLAYER_R) * 0.85 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 1
end

-- keeps a distance: closer -> back off, further -> approach, else circle
local function keepAway(e, dx, dz, d, keep: number)
	if d > keep + 4 then
		return dx / d, dz / d, 1
	elseif d < keep - 4 then
		return -dx / d, -dz / d, 0.8
	end
	return -dz / d * e.Side, dx / d * e.Side, 0.6
end

function Behaviors.Charge(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if e.State == 0 then
		if d < p.Trigger then
			e.State = 1
			e.T = windup(run, p.Windup)
			setState(run, e, ES.Windup)
			return 0, 0, 0
		end
		return Behaviors.Chase(run, e, dx, dz, d)
	elseif e.State == 1 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 2
			e.T = p.DashTime
			e.DirX, e.DirZ = dx / d, dz / d
			setState(run, e, ES.Dash)
			EnemyManager.EchoLine(run, e, p.DashSpeed * p.DashTime)
		end
		return 0, 0, 0
	elseif e.State == 2 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 3
			e.T = p.Rest
			setState(run, e, ES.Normal)
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
	return -dz / d * e.Side, dx / d * e.Side, 0.6
end

function Behaviors.Strafe(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.T <= 0 and d < p.Orbit + 18 then
		e.T = p.ShootEvery
		local vx, vz = dx / d * p.ProjSpeed, dz / d * p.ProjSpeed
		EnemyManager.Shoot(run, e.X, e.Z, vx, vz, p.ProjRadius, p.ProjDamage * e.DmgScale, p.ProjLife)
	end
	return keepAway(e, dx, dz, d, p.Orbit)
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

-- Bomber: runs in, lights the fuse (red circle), explodes
function Behaviors.Bomber(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if not e.Lit then
		if d < p.Trigger then
			e.Lit = true
			e.T = windup(run, p.Fuse)
			local r = p.BlastRadius * (if e.Giant then 1.4 else 1)
			run:Write("Telegraph", 1, e.X, e.Z, 0, r, 0, e.T)
			setState(run, e, ES.Lit)
			return 0, 0, 0
		end
		return dx / d, dz / d, 1
	end
	e.T -= dt
	if e.T <= 0 then
		e.Explode = true -- resolved after the enemy pass
	end
	return 0, 0, 0
end

-- Diver: circles at a distance, then dives straight through you
function Behaviors.Dive(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.State == 0 then
		local r = p.Radius
		e.Angle = (e.Angle or 0) + (e.Speed / r) * dt * e.Side
		-- target point relative to the enemy: (player + ring offset) - enemy
		local tx, tz = dx + cos(e.Angle) * r, dz + sin(e.Angle) * r
		local m = sqrt(tx * tx + tz * tz)
		if e.T <= 0 and d < r + 10 then
			e.State = 1
			e.T = windup(run, p.Windup or 0.45)
			e.DirX, e.DirZ = dx / d, dz / d
			local length = p.DiveSpeed * p.DiveTime
			run:Write("Telegraph", 2, e.X, e.Z, atan2(e.DirZ, e.DirX), length, e.Radius * 2, e.T)
			setState(run, e, ES.Windup)
			return 0, 0, 0
		end
		if m < 0.05 then
			return 0, 0, 0
		end
		return tx / m, tz / m, min(1.4, m / 3)
	elseif e.State == 1 then
		if e.T <= 0 then
			e.State = 2
			e.T = p.DiveTime
			setState(run, e, ES.Dash)
			EnemyManager.EchoLine(run, e, p.DiveSpeed * p.DiveTime)
		end
		return 0, 0, 0
	end
	if e.T <= 0 then
		e.State = 0
		e.T = p.Circle
		e.Angle = atan2(-dz, -dx)
		setState(run, e, ES.Normal)
	end
	return e.DirX, e.DirZ, p.DiveSpeed / e.Speed
end

-- Summoner: stays back and keeps calling skitters
function Behaviors.Summoner(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.T <= 0.6 and e.VState ~= ES.Windup then
		setState(run, e, ES.Windup)
	end
	if e.T <= 0 then
		e.T = p.Every
		setState(run, e, ES.Normal)
		for i = 1, p.Count do
			local a = (i / p.Count) * TAU + run.Rng:NextNumber(0, 1)
			EnemyManager.Spawn(run, p.SummonKey, e.X + cos(a) * (e.Radius + 2), e.Z + sin(a) * (e.Radius + 2))
		end
	end
	return keepAway(e, dx, dz, d, p.Keep)
end

-- Ghost: solid for a while, then phased (no contact, can't be hit)
function Behaviors.Phase(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.T <= 0 then
		e.Phased = not e.Phased
		e.T = if e.Phased then p.Phased else p.Solid
		setState(run, e, if e.Phased then ES.Phased else ES.Normal)
	end
	local x, z, m = Behaviors.Chase(run, e, dx, dz, d)
	return x, z, if e.Phased then m * 1.35 else m
end

-- Leaper: crouches, jumps to where you were, lands with a shockwave
function Behaviors.Leap(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if e.State == 0 then
		if d < p.Trigger then
			e.State = 1
			e.T = windup(run, p.Windup)
			-- aim where the player stands now (a moving player dodges)
			e.TX, e.TZ = e.X + dx, e.Z + dz
			run:Write("Telegraph", 1, e.TX, e.TZ, 0, p.LandRadius, 0, e.T + p.JumpTime)
			setState(run, e, ES.Windup)
			return 0, 0, 0
		end
		return Behaviors.Chase(run, e, dx, dz, d)
	elseif e.State == 1 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 2
			e.T = p.JumpTime
			e.Air = true
			local jx, jz = e.TX - e.X, e.TZ - e.Z
			local jd = max(0.1, sqrt(jx * jx + jz * jz))
			e.DirX, e.DirZ = jx / jd, jz / jd
			e.JumpSpeed = jd / p.JumpTime
			setState(run, e, ES.Dash)
		end
		return 0, 0, 0
	elseif e.State == 2 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 3
			e.T = p.Rest
			e.Air = false
			e.Land = true -- resolved after the enemy pass
			setState(run, e, ES.Normal)
			return 0, 0, 0
		end
		return e.DirX, e.DirZ, e.JumpSpeed / e.Speed
	end
	e.T -= dt
	if e.T <= 0 then
		e.State = 0
	end
	local x, z = Behaviors.Chase(run, e, dx, dz, d)
	return x, z, 0.4
end

-- Mimic: a loot box until you come close (or hit it)
function Behaviors.Mimic(run, e, dx, dz, d)
	if e.Dormant then
		if d < e.Def.Params.Wake then
			wake(run, e)
			run:Write("Fx", 0, e.X, e.Z, 0, 5, 0, GFX.Land)
		end
		return 0, 0, 0
	end
	return Behaviors.Chase(run, e, dx, dz, d)
end

-- Sniper: keeps its distance, aims a red line, fires a fast shot down it
function Behaviors.Sniper(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.State == 1 then
		if e.T <= 0 then
			e.State = 0
			e.T = p.Every
			setState(run, e, ES.Normal)
			local vx, vz = e.DirX * p.ProjSpeed, e.DirZ * p.ProjSpeed
			EnemyManager.Shoot(run, e.X, e.Z, vx, vz, p.ProjRadius, p.ProjDamage * e.DmgScale, 80 / p.ProjSpeed)
		end
		return 0, 0, 0
	end
	if e.T <= 0 and d < p.Keep + 20 then
		e.State = 1
		e.T = windup(run, p.Aim)
		e.DirX, e.DirZ = dx / d, dz / d
		run:Write("Telegraph", 4, e.X, e.Z, atan2(e.DirZ, e.DirX), 80, p.ProjRadius * 2, e.T)
		setState(run, e, ES.Windup)
		return 0, 0, 0
	end
	return keepAway(e, dx, dz, d, p.Keep)
end

-- THE 67: circles you and throws six, then seven projectiles
function Behaviors.Sixty(run, e, dx, dz, _d, dt)
	local p = e.Def.Params
	local r = p.Radius
	e.Angle = (e.Angle or 0) + (e.Speed / r) * dt * e.Side
	local tx, tz = dx + cos(e.Angle) * r, dz + sin(e.Angle) * r
	e.T -= dt
	if e.T <= 0 then
		e.T = p.Every
		ringShots(run, e, 6, p.ProjSpeed, p.ProjDamage * e.DmgScale, run.Rng:NextNumber(0, TAU))
		e.SevenAt = run.Time + 0.67
		setState(run, e, ES.Windup)
	end
	if e.SevenAt and run.Time >= e.SevenAt then
		e.SevenAt = nil
		ringShots(run, e, 7, p.ProjSpeed, p.ProjDamage * e.DmgScale, run.Rng:NextNumber(0, TAU))
		setState(run, e, ES.Normal)
	end
	local m = sqrt(tx * tx + tz * tz)
	if m < 0.05 then
		return 0, 0, 0
	end
	return tx / m, tz / m, min(1.5, m / 3)
end

function Behaviors.Static()
	return 0, 0, 0
end

function Behaviors.March(_run, e)
	return e.DirX, e.DirZ, 1
end

function Behaviors.Boss(run, e, dx, dz, d, dt)
	if e.Encounter then
		return MiniBosses.Step(run, e, dx, dz, d, dt, EnemyManager) -- lair / arena rules, then its attacks
	end
	return Bosses.Step(run, e, dx, dz, d, dt, EnemyManager)
end

function Behaviors.Champion(run, e, dx, dz, d, dt)
	return MiniBosses.Step(run, e, dx, dz, d, dt, EnemyManager)
end

---------------------------------------------------------------------------
-- the horde of the harder tiers
---------------------------------------------------------------------------
-- an ECHO elite's dash / dive comes again as a red line along its path
function EnemyManager.EchoLine(run, e, length: number)
	local echo = e.Echo
	if not echo then
		return
	end
	local x, z, a = e.X, e.Z, atan2(e.DirZ, e.DirX)
	local damage = e.Damage
	table.insert(run.Echoes, {
		At = run.Time + echo.Delay * 0.5,
		Fn = function()
			Bosses.Telegraph(run, e, SHAPE.Laser, x, z, a, length, e.Radius * 2, windup(run, 0.8), damage, "Sweep", nil, { Echo = false })
		end,
	})
end

-- a patch of fire under (x, z) for a few seconds (Cinder, BURNING elites); the run caps how
-- fast new patches come so a crowd of them never floods the ground
function EnemyManager.FireTrail(run, e, radius: number, time: number, damage: number)
	local now = run.Time
	if now < (run.FireAt or 0) then
		return
	end
	run.FireAt = now + 0.06
	Bosses.Telegraph(run, e, SHAPE.Spill, e.X, e.Z, 0, radius, time, 0.05, damage * e.DmgScale, nil, nil, { Echo = false })
end

-- an aura: every enemy in the radius gets `field` = value for a moment (Bannerman / war banner:
-- Haste, Warden: Ward). withBosses: the war banner speeds up its boss too
local function aura(run, e, radius: number, field: string, value: number, withBosses: boolean?)
	local n = SpatialGrid.Query(run.Grid, e.X, e.Z, radius + 2, auraScratch)
	local untilT = run.Time + 0.7
	for k = 1, n do
		local o = auraScratch[k]
		if o ~= e and o.Alive and (withBosses or not o.IsBoss) then
			local dx, dz = o.X - e.X, o.Z - e.Z
			if dx * dx + dz * dz <= radius * radius then
				o[field .. "Until"] = untilT
				o[field] = value
			end
		end
	end
	if withBosses and e.Owner and e.Owner.Alive then
		e.Owner[field .. "Until"] = untilT
		e.Owner[field] = value
	end
end

-- Snoozer: asleep where it landed; close enough (or hit) and it wakes, blinks, and rushes
function Behaviors.Sleep(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if e.Dormant then
		if d < p.Wake then
			wake(run, e)
		end
		return 0, 0, 0
	end
	if e.State == 1 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 2
			setState(run, e, ES.Normal)
		end
		return 0, 0, 0
	end
	local x, z = Behaviors.Chase(run, e, dx, dz, d)
	return x, z, p.Rush
end

-- Shielder: walks at you behind its shield (the shield faces you: EnemyManager.Damage)
function Behaviors.Shield(run, e, dx, dz, d)
	e.FaceX, e.FaceZ = dx / d, dz / d
	return Behaviors.Chase(run, e, dx, dz, d)
end

-- a formation closing in on a point (THE HORDEMASTER's shielders)
function Behaviors.Converge(run, e, dx, dz, d)
	e.FaceX, e.FaceZ = dx / d, dz / d
	local cx, cz = (e.CX or run.PX) - e.X, (e.CZ or run.PZ) - e.Z
	local cd = sqrt(cx * cx + cz * cz)
	if cd < 2.5 then
		return 0, 0, 0
	end
	return cx / cd, cz / cd, 1
end

-- Stampeder: stamps (a red line), then runs a straight lane, faster and faster, turning badly
function Behaviors.Stampede(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if e.State == 0 then
		if d < p.Trigger then
			e.State = 1
			e.T = windup(run, p.Windup)
			e.DirX, e.DirZ = dx / d, dz / d
			run:Write("Telegraph", 2, e.X, e.Z, atan2(e.DirZ, e.DirX), p.TopSpeed * p.RunTime * 0.7, e.Radius * 2, e.T)
			setState(run, e, ES.Windup)
			return 0, 0, 0
		end
		return Behaviors.Chase(run, e, dx, dz, d)
	elseif e.State == 1 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 2
			e.T = p.RunTime
			e.RunT = 0
			setState(run, e, ES.Dash)
		end
		return 0, 0, 0
	elseif e.State == 2 then
		e.T -= dt
		e.RunT += dt
		local cur = atan2(e.DirZ, e.DirX)
		local diff = ((atan2(dz, dx) - cur + math.pi) % TAU) - math.pi
		cur += math.clamp(diff, -p.Turn * dt, p.Turn * dt)
		e.DirX, e.DirZ = cos(cur), sin(cur)
		if e.T <= 0 then
			e.State = 3
			e.T = p.Rest
			setState(run, e, ES.Normal)
		end
		local speed = p.TopSpeed * min(1, 0.35 + 0.65 * e.RunT / p.Accel)
		return e.DirX, e.DirZ, speed / e.Speed
	end
	e.T -= dt
	if e.T <= 0 then
		e.State = 0
	end
	local x, z = Behaviors.Chase(run, e, dx, dz, d)
	return x, z, 0.5
end

-- Bannerman: stays behind the horde; everything inside its ring runs faster
function Behaviors.Banner(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.T <= 0 then
		e.T = 0.5
		aura(run, e, p.Aura, "Haste", p.Haste)
	end
	return keepAway(e, dx, dz, d, p.Keep)
end

-- Wailer: keeps its distance, wails a slow ring wave with one gap
function Behaviors.Wail(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.State == 1 then
		if e.T <= 0 then
			e.State = 0
			e.T = p.Every
			setState(run, e, ES.Normal)
			Bosses.GapRing(run, EnemyManager, e.X, e.Z, p.Count, p.Gap, e.GapA, p.ProjSpeed, p.ProjDamage * e.DmgScale, p.ProjRadius, p.ProjLife)
		end
		return 0, 0, 0
	end
	if e.T <= 0 and d < p.Keep + 16 then
		e.State = 1
		e.T = windup(run, p.Windup)
		-- the gap opens near you, never exactly on you: a step to the side
		local side = if run.Rng:NextNumber() < 0.5 then -1 else 1
		e.GapA = atan2(dz, dx) + side * run.Rng:NextNumber(0.3, 1.2)
		setState(run, e, ES.Windup)
		return 0, 0, 0
	end
	return keepAway(e, dx, dz, d, p.Keep)
end

-- Hexer: a curse circle under you that explodes Delay seconds later
function Behaviors.Hex(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.T <= 0 and d < p.Keep + 14 then
		e.T = p.Every
		Bosses.Telegraph(run, e, SHAPE.Circle, run.PX, run.PZ, 0, p.Radius, 0, windup(run, p.Delay), p.HexDamage * e.DmgScale, "Slam")
		setState(run, e, ES.Windup)
		e.CastUntil = run.Time + 0.5
	elseif e.CastUntil and run.Time >= e.CastUntil then
		e.CastUntil = nil
		setState(run, e, ES.Normal)
	end
	return keepAway(e, dx, dz, d, p.Keep)
end

-- Cinder: chases you and leaves a trail of fire
function Behaviors.Cinder(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.T <= 0 then
		e.T = p.TrailEvery
		EnemyManager.FireTrail(run, e, p.TrailRadius, p.TrailTime, p.TrailDamage)
	end
	return Behaviors.Chase(run, e, dx, dz, d)
end

-- Eruptor: barely moves, lobs lava onto where you stand (the circle shows where)
function Behaviors.Mortar(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.T <= 0 and d < p.Keep + 22 then
		e.T = p.Every
		local delay = windup(run, p.Delay)
		local tx, tz = run.PX, run.PZ
		Bosses.Telegraph(run, e, SHAPE.Circle, tx, tz, 0, p.Radius, 0, delay, p.LavaDamage * e.DmgScale, "Slam")
		local ax, az = tx - e.X, tz - e.Z
		run:Write("Fx", 0, e.X, e.Z, atan2(az, ax), sqrt(ax * ax + az * az), delay, GFX.Lava)
		setState(run, e, ES.Windup)
		e.CastUntil = run.Time + 0.4
	elseif e.CastUntil and run.Time >= e.CastUntil then
		e.CastUntil = nil
		setState(run, e, ES.Normal)
	end
	return keepAway(e, dx, dz, d, p.Keep)
end

-- Predator: runs to where you WILL be, then pounces along a red line
function Behaviors.Predator(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if e.State == 1 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 2
			e.T = p.PounceTime
			setState(run, e, ES.Dash)
			EnemyManager.EchoLine(run, e, p.PounceSpeed * p.PounceTime)
		end
		return 0, 0, 0
	elseif e.State == 2 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 3
			e.T = p.Rest
			setState(run, e, ES.Normal)
		end
		return e.DirX, e.DirZ, p.PounceSpeed / e.Speed
	elseif e.State == 3 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 0
		end
		local x, z = Behaviors.Chase(run, e, dx, dz, d)
		return x, z, 0.6
	end
	-- the point you are heading to (only when it is hunting you, not your decoy)
	local tx, tz = dx, dz
	local onPlayer = abs(e.X + dx - run.PX) < 0.01 and abs(e.Z + dz - run.PZ) < 0.01
	if onPlayer then
		local v = math.clamp(run.Moved / max(dt, 1e-3), 0, 40)
		tx += run.FX * v * p.Lead
		tz += run.FZ * v * p.Lead
	end
	local td = max(0.01, sqrt(tx * tx + tz * tz))
	if d < p.Trigger then
		e.State = 1
		e.T = windup(run, p.Windup)
		e.DirX, e.DirZ = tx / td, tz / td
		run:Write("Telegraph", 2, e.X, e.Z, atan2(e.DirZ, e.DirX), p.PounceSpeed * p.PounceTime, e.Radius * 2, e.T)
		setState(run, e, ES.Windup)
		return 0, 0, 0
	end
	return tx / td, tz / td, 1
end

-- Warden: slow; its bubble protects the horde inside it
function Behaviors.Ward(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.T <= 0 then
		e.T = 0.5
		aura(run, e, p.Aura, "Ward", p.Ward)
	end
	return keepAway(e, dx, dz, d, p.Keep)
end

-- a goo egg: shakes for its last second, then hatches (resolved after the pass)
function Behaviors.Egg(run, e, _dx, _dz, _d, dt)
	e.T -= dt
	if e.T <= 1.2 and e.VState ~= ES.Windup then
		setState(run, e, ES.Windup)
	end
	if e.T <= 0 then
		e.Hatch = true
	end
	return 0, 0, 0
end

-- a war banner: the horde around it (and its boss) runs faster
function Behaviors.Rally(run, e, _dx, _dz, _d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.T <= 0 then
		e.T = 0.5
		aura(run, e, p.Aura, "Haste", p.Haste, true)
	end
	return 0, 0, 0
end

EnemyManager.Behaviors = Behaviors

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

local STILL = { Static = true, Egg = true, Rally = true } -- never pushed around by the crowd
local NO_RELOCATE = { March = true, Static = true, Flee = true, Sixty = true, Mimic = true, Boss = true, Champion = true, Egg = true, Rally = true, Converge = true }
local RIFT = ArenaData.ByKey.Rift.Rect

local function inRift(x: number, z: number): boolean
	return x < RIFT.MaxX and z < RIFT.MaxZ
end

-- the rift's cliffs are long: an enemy on the other side of them heads for the best gate
-- first (aiming a little past it, so big ones don't stop in the doorway)
local GATES = ArenaData.RiftGates
local THROUGH = 16
local function viaGate(x: number, z: number, tx: number, tz: number): (number, number)
	local best, bestGate = math.huge, GATES[1]
	for _, g in GATES do
		local d = sqrt((g.X - x) ^ 2 + (g.Z - z) ^ 2) + sqrt((tx - g.X) ^ 2 + (tz - g.Z) ^ 2)
		if d < best then
			best, bestGate = d, g
		end
	end
	local g = bestGate
	local inside = x < RIFT.MaxX and z < RIFT.MaxZ
	if g.Axis == "X" then
		-- a gate in the south cliffs (z = -80)
		return g.X, g.Z + (if inside then THROUGH else -THROUGH)
	end
	-- a gate in the east cliffs (x = 80)
	return g.X + (if inside then THROUGH else -THROUGH), g.Z
end

-- the sealed rift: push the horde back out over its nearest edge
local function keepOutOfRift(e)
	if e.X < RIFT.MaxX and e.Z < RIFT.MaxZ and e.X > RIFT.MinX and e.Z > RIFT.MinZ then
		local south, east = RIFT.MaxZ - e.Z, RIFT.MaxX - e.X
		if south < east then
			e.Z = RIFT.MaxZ + e.Radius
		else
			e.X = RIFT.MaxX + e.Radius
		end
	end
end

function EnemyManager.Step(run, dt: number)
	local px, pz = run.PX, run.PZ
	local now = run.Time
	local turbo = if run:Buff("TurboMode") then 1.67 else 1
	local relocate = GameConfig.Arena.RelocateDistance
	local stuckLimit = GameConfig.Arena.StuckRelocate
	local riftSealed = run.Map ~= nil and not run.Map.RiftOpen
	local riftOpen = run.Map ~= nil and run.Map.RiftOpen
	local grid = run.Grid
	local knockDecay = exp(-7 * dt)
	local decoy = run.Decoy
	if decoy and now >= decoy.Until then
		decoy = nil
	end

	EnemyManager.RebuildGrid(run)

	local touchMax, touchCount = 0, 0
	local touching = nil
	local later = nil -- enemies with something to resolve after the pass
	local list = run.Enemies
	-- index loop over the enemies that existed at the start of the step: summons are
	-- appended at the end and move from the next step on
	for index = 1, #list do
		local e = list[index]
		-- target: the player, or the Clone decoy when it is closer
		local tx, tz = px, pz
		if decoy and not e.IsBoss then
			local ddx, ddz = decoy.X - e.X, decoy.Z - e.Z
			if ddx * ddx + ddz * ddz < 40 * 40 then
				tx, tz = decoy.X, decoy.Z
			end
		end
		-- the rift's cliffs: go round through a gate (only when open; sealed, nobody is inside)
		if riftOpen and not e.Air and inRift(e.X, e.Z) ~= inRift(tx, tz) then
			tx, tz = viaGate(e.X, e.Z, tx, tz)
		end
		local dx, dz = tx - e.X, tz - e.Z
		local d = sqrt(dx * dx + dz * dz)
		if d < 0.01 then
			d = 0.01
		end

		local dirX, dirZ, mult = 0, 0, 0
		if e.FrozenUntil > now then
			mult = 0
		else
			if e.Thaw then
				e.Thaw = nil
				run:Write("EState", e.Id, e.VState)
			end
			local behavior = Behaviors[e.Behavior] or Behaviors.Chase
			run.Shooter = if e.Echo then e else nil -- an ECHO elite's shots come twice
			dirX, dirZ, mult = behavior(run, e, dx, dz, d, dt)
		end
		local slow = if e.SlowUntil > now then e.SlowFactor else 1
		if e.SlowUntil <= now then
			e.SlowFactor = 1
		end
		-- a Bannerman / war banner nearby: faster
		if e.HasteUntil and e.HasteUntil > now then
			slow *= e.Haste
		end
		-- SIXLET / SEVENLET lost its twin: it shakes, then rages for a while
		if e.GriefUntil and now >= e.GriefUntil then
			local p = e.Def.Params
			e.GriefUntil = nil
			e.RageUntil = now + p.RageTime
			e.Speed *= p.RageSpeed
			e.Damage *= p.RageDamage
			setState(run, e, ES.Enraged)
			run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2.5, 0, GFX.Rage)
		elseif e.RageUntil and now >= e.RageUntil then
			local p = e.Def.Params
			e.RageUntil = nil
			e.Speed /= p.RageSpeed
			e.Damage /= p.RageDamage
			setState(run, e, ES.Normal)
		end
		-- ponds: the horde wades slower (not bosses, not flyers)
		local wade = if not e.IsBoss and not e.Air and run:InWater(e.X, e.Z) then GameConfig.Water.EnemySpeed else 1
		local speed = e.Speed * mult * slow * turbo * wade

		-- crowd separation (a few neighbours are enough to spread a horde)
		local sepX, sepZ = 0, 0
		if not e.IsBoss and not STILL[e.Behavior] and not e.Air then
			local n = SpatialGrid.Query(grid, e.X, e.Z, e.Radius * 2, scratch)
			local checked = 0
			for k = 1, n do
				local o = scratch[k]
				if o ~= e and not o.Air then
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
		if not e.Air then
			local nx, nz = pushOut(run, e)
			if nx ~= 0 or nz ~= 0 then
				local sx, sz = -nz * e.Side, nx * e.Side
				e.X += sx * speed * dt * 0.8
				e.Z += sz * speed * dt * 0.8
				pushOut(run, e)
				e.Stuck = (e.Stuck or 0) + dt
			elseif e.Stuck then
				e.Stuck = max(0, e.Stuck - dt * 0.5)
			end
		end
		if riftSealed and not e.IsBoss then
			keepOutOfRift(e)
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

		-- the sealed 67 ARENA: the horde stays out, the boss and its adds stay in
		local seal = run.Map and run.Map.ArenaSealed
		if seal then
			local ax, az = e.X - seal.X, e.Z - seal.Z
			local ad = sqrt(ax * ax + az * az)
			if ad < 0.01 then
				ax, az, ad = 0.01, 0, 0.01
			end
			if (e.Encounter and e.Encounter.Main) or e.ArenaAdd then
				-- THE FINAL ONE and its adds stay in (other bosses keep to their lairs)
				local lim = seal.R - e.Radius
				if ad > lim then
					e.X, e.Z = seal.X + ax / ad * lim, seal.Z + az / ad * lim
				end
			elseif ad < seal.R + e.Radius then
				local lim = seal.R + e.Radius
				e.X, e.Z = seal.X + ax / ad * lim, seal.Z + az / ad * lim
			end
		end

		-- left far behind: reappear ahead of the player (the horde never thins out)
		local pdx, pdz = px - e.X, pz - e.Z
		local pd2 = pdx * pdx + pdz * pdz
		local stuck = e.Stuck ~= nil and e.Stuck > stuckLimit and pd2 > 30 * 30
		if (pd2 > relocate * relocate or stuck) and not NO_RELOCATE[e.Behavior] and not e.Lit and e.State == 0 then
			e.Stuck = 0
			local a = atan2(run.FZ, run.FX) + run.Rng:NextNumber(-0.9, 0.9)
			local r = run.Rng:NextNumber(GameConfig.Arena.SpawnRadiusMin, GameConfig.Arena.SpawnRadiusMax)
			e.X = math.clamp(px + cos(a) * r, -HALF, HALF)
			e.Z = math.clamp(pz + sin(a) * r, -HALF, HALF)
			e.SentX, e.SentZ = e.X, e.Z
			run:Write("Blink", e.Id, e.X, e.Z)
		end

		-- contact with the player
		if not (e.NoContact or e.Phased or e.Dormant or e.Air) then
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
				if touchCount <= 8 then
					touching = touching or {}
					table.insert(touching, e)
				end
			end
		end

		if e.Explode or e.Land or e.Hatch or (e.BurnUntil and e.BurnUntil > now) or (e.Life and now >= e.Life) then
			later = later or {}
			table.insert(later, e)
		end
	end

	if touchCount > 0 then
		-- swarmed: the strongest hit + a little per extra attacker
		local taken = run:HurtPlayer(touchMax + min(touchCount - 1, 6) * 1.5, false, "Contact")
		if taken > 0 and touching then
			Elites.OnTouch(run, touching, taken)
		end
		-- THE TANK: whatever touches you gets hurt back
		if run.Mech == "Thorns" and taken > 0 and touching then
			local dmg = (10 + run.Level * 1.5) * run.Stats.Might
			run:Write("Fx", 0, px, pz, 0, 5, 0, GFX.Thorns)
			for _, e in touching do
				EnemyManager.Damage(run, e, dmg, 0, e.X - px, e.Z - pz, 6)
			end
		end
		-- the Cactus Hug item does the same for everyone
		if touching then
			Perks.Thorns(run, touching)
		end
	end

	if later then
		local burnFlag = Protocol.HitFlags.Burn
		for _, e in later do
			if e.Alive then
				if e.Explode then
					e.Explode = nil
					e.Lit = false
					bomberBlast(run, e, true)
					EnemyManager.Despawn(run, e)
				elseif e.Land then
					e.Land = nil
					local p = e.Def.Params
					run:Write("Fx", 0, e.X, e.Z, 0, p.LandRadius, 0, GFX.Land)
					local dx, dz = px - e.X, pz - e.Z
					if dx * dx + dz * dz <= (p.LandRadius + PLAYER_R * 0.5) ^ 2 then
						run:HurtPlayer(p.LandDamage * e.DmgScale, true)
					end
					if e.Echo then
						-- ECHO: the landing comes again
						Bosses.Telegraph(run, e, SHAPE.Circle, e.X, e.Z, 0, p.LandRadius, 0, windup(run, 0.9), p.LandDamage * e.DmgScale, "Land", nil, { Echo = false })
					end
				elseif e.Hatch then
					-- a goo egg hatches
					e.Hatch = nil
					local p = e.Def.Params
					run:Write("Fx", 0, e.X, e.Z, 0, 4, 0, GFX.Hatch)
					for k = 1, p.HatchCount do
						local a = k * TAU / p.HatchCount
						local g = EnemyManager.Spawn(run, p.HatchKey, e.X + cos(a) * 2, e.Z + sin(a) * 2, { Force = true })
						if g and e.ArenaAdd then
							g.ArenaAdd = true
						end
					end
					EnemyManager.Despawn(run, e)
				end
			end
			if e.Alive and e.BurnUntil and e.BurnUntil > now then
				e.BurnTick = (e.BurnTick or 0) - dt
				if e.BurnTick <= 0 then
					e.BurnTick = 0.5
					EnemyManager.Damage(run, e, e.BurnDps * 0.5, burnFlag, 0, 0, 0)
				end
			end
			if e.Alive and e.Life and now >= e.Life then
				if e.Key == "Goblin67" then
					run:Banner("THE 67 GOBLIN ESCAPED", "Next time.", "Info")
				elseif e.Key == "The67" then
					run:Banner("THE 67 LEFT", "It will be back...", "Info")
				end
				EnemyManager.Despawn(run, e)
			end
		end
	end

	run.Shooter = nil
	-- ECHO elites: their attacks again
	local echoes = run.Echoes
	if echoes and #echoes > 0 then
		local k = 1
		while k <= #echoes do
			local ev = echoes[k]
			if now >= ev.At then
				table.remove(echoes, k)
				ev.Fn()
			else
				k += 1
			end
		end
	end

	stepEnemyProjectiles(run, dt)
	Bosses.StepTelegraphs(run, EnemyManager, dt)
	EnemyManager.RebuildGrid(run)
end

return EnemyManager
