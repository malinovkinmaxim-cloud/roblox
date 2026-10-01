--[[
	Bosses - the attack patterns of the classic bosses and the MAIN bosses. Every attack is
	telegraphed (red circle / line / sector / zone on the ground, sent as a Telegraph record)
	so the player has to move:
	  classic   Slam DoubleSlam Leap Teleport Barrage Sweep Hazard Dash Ring Spiral Summon
	            Rain DoomRing
	  main      BellyFlop GooRain Nest (MAMA GOOBER) · Lanes BannerCall Formation FullCharge
	            (THE HORDEMASTER) · Hands EyeSweep Echoes LightsOut (THE DREAD) · Sectors
	            EmberRing Meteors Steam (THE FURNACE) · Swipe Erase Redraw (THE ERASER) ·
	            SixSeven (THE 67 PRIME, which borrows the others)
	A pattern is one entry of Params.Patterns with its own <Pattern>Every timer; patterns mix
	freely (THE 67 PRIME is built from the other main bosses' patterns).
	PHASES come from shared/BossData.lua (Sim/MiniBosses.StepPhase): each one speeds the boss
	up (e.Rate) and adds Params.PhasePatterns[phase] (or EnragePatterns in phase 2), or
	swaps the whole set (Params.PhaseSets[phase]); Params.EdgeErase eats the arena's edge.
	After some attacks the boss is EXPOSED (its weak point, BossData WeakPoint):
	e.PendingExpose. DoomRing: a ring of shots with one gap; a line points at the gap.
	Multi-step attacks queue their next steps (Bosses.After); new patterns shorten their
	wind-ups on NO MERCY like every other enemy (never below 0.75 s).

	Called by EnemyManager (which passes itself in, avoiding a require cycle).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local Protocol = require(Shared.Protocol)
local BossData = require(Shared.BossData)
local EnemyData = require(Shared.EnemyData)

local Pickups = require(script.Parent.Pickups)

local Bosses = {}

local sqrt, cos, sin, atan2, min, max = math.sqrt, math.cos, math.sin, math.atan2, math.min, math.max
local TAU = math.pi * 2
local PLAYER_R = GameConfig.Player.Radius
local GFX = Protocol.Fx
local ES = Protocol.EState
local MAIN = BossData.Main

local EVERY: { [string]: string } = {
	Slam = "SlamEvery",
	DoubleSlam = "SlamEvery",
	Dash = "DashEvery",
	Ring = "RingEvery",
	Spiral = "SpiralEvery",
	Summon = "SummonEvery",
	Rain = "RainEvery",
	Leap = "LeapEvery",
	Teleport = "TeleportEvery",
	Barrage = "BarrageEvery",
	Sweep = "SweepEvery",
	Hazard = "HazardEvery",
	DoomRing = "DoomRingEvery",
}
-- every other pattern: <Pattern>Every
setmetatable(EVERY, {
	__index = function(_, pattern)
		return pattern .. "Every"
	end,
})
Bosses.Every = EVERY

local SHAPE = Protocol.Shapes
local SECTOR_BURN = Protocol.SectorBurn

local function state(run, e, s: number)
	if e.VState ~= s then
		e.VState = s
		run:Write("EState", e.Id, s)
	end
end

function Bosses.Init(run, e)
	local p = e.Def.Params
	e.Patterns = table.clone(p.Patterns)
	e.Timers = {}
	for i, pattern in e.Patterns do
		-- stagger the first attacks so the boss opens with its first pattern
		e.Timers[pattern] = (p[EVERY[pattern]] or 6) * (0.35 + 0.2 * (i - 1))
	end
	e.Busy = 0
	e.Enraged = false
	e.Rate = e.Rate or 1
	e.Phase = e.Phase or 1
	if run.Mods and run.Mods.BossRage then
		-- BOSS RAGE difficulty: the second phase's attacks are there from the start
		Bosses.AddPhase(run, e, 2, true)
	end
	-- the big bar at the top of the screen: the main boss (and a boss without an encounter)
	local enc = e.Encounter
	if not enc or enc.Main then
		run.Boss = e
		run:Event("BossSpawn", { Id = e.Id, Key = e.Key, Title = p.Title, MaxHP = math.ceil(e.MaxHP), Final = p.Final == true })
	end
end

-- the patterns a phase adds (PhaseSets: the phase's own set replaces them); rage = the BOSS
-- RAGE head start (adds the attacks, nothing else)
function Bosses.AddPhase(run, e, phase: number, rage: boolean?)
	local p = e.Def.Params
	local set = p.PhaseSets and p.PhaseSets[phase]
	if set then
		if rage then
			return
		end
		e.Patterns = table.clone(set)
		e.Timers = {}
		for i, pattern in e.Patterns do
			e.Timers[pattern] = 1.5 + (i - 1) * 1.1
		end
	else
		local add = (p.PhasePatterns and p.PhasePatterns[phase]) or (if phase == 2 then p.EnragePatterns else nil) or {}
		for i, pattern in add do
			if not e.Timers[pattern] then
				table.insert(e.Patterns, pattern)
				e.Timers[pattern] = 1.2 + i * 0.8
			end
		end
	end
	if p.EdgeErase and not rage then
		Bosses.EraseEdge(run, e, phase)
	end
end

-- a delayed attack: shape 1 circle, 2 dash line (visual only), 3 lingering zone, 4 laser line,
-- 5 slippery puddle (slows, no damage), 6 spill (a small lingering zone that hurts), 7 sector,
-- 8 safe circle (visual), 9 erased floor (lingering, hurts), 10 safe sector (visual):
-- Protocol.Shapes. extra (server only): Safe = { {X, Z, R} } holes in a circle, Burn = seconds
-- a sector keeps burning, Echo = false (an ECHO elite's copy), Silent = no record
local function telegraph(run, e, shape: number, x: number, z: number, angle: number, size: number, width: number, delay: number, damage: number, kind: string?, slow: number?, extra: any?)
	if shape ~= SHAPE.Safe and shape ~= SHAPE.SafeSector then
		table.insert(run.Telegraphs, {
			At = run.Time + delay,
			Shape = shape,
			X = x,
			Z = z,
			Angle = angle,
			R = size,
			Width = width,
			Damage = damage,
			Boss = e,
			Kind = kind,
			Slow = slow,
			Safe = extra and extra.Safe,
			Burn = extra and extra.Burn,
		})
	end
	if not (extra and extra.Silent) then
		run:Write("Telegraph", shape, x, z, angle, size, width, delay)
	end
	-- an ECHO elite: every attack comes again a moment later
	local echo = e and e.Echo
	if echo and not (extra and extra.Echo == false) and damage > 0 then
		table.insert(run.Echoes, {
			At = run.Time + echo.Delay,
			Fn = function()
				telegraph(run, e, shape, x, z, angle, size, width, delay, damage, kind, slow, { Echo = false })
			end,
		})
	end
end

-- seconds of wind-up (NO MERCY shortens it; boss telegraphs never go below 0.75 s)
local function windup(run, seconds: number): number
	return seconds * (run.Windup or 1)
end
Bosses.Windup = windup

-- multi-step attacks: fn(run, e, EM) runs `delay` seconds from now (dropped if e dies)
function Bosses.After(run, e, delay: number, fn: (any, any, any) -> ())
	e.Queue = e.Queue or {}
	table.insert(e.Queue, { At = run.Time + delay, Fn = fn })
end

function Bosses.RunQueue(run, e, EM)
	local q = e.Queue
	if not q or #q == 0 then
		return
	end
	local now = run.Time
	local i = 1
	while i <= #q do
		local item = q[i]
		if now >= item.At then
			table.remove(q, i)
			if e.Alive then
				item.Fn(run, e, EM)
			end
		else
			i += 1
		end
	end
end

-- the angles of a ring of `count` shots with `gap` shots missing, centred on gapAngle
local function gapAngles(count: number, gap: number, gapAngle: number): { number }
	local out = {}
	local step = TAU / count
	local offset = if gap % 2 == 1 then 0 else 0.5
	for i = 0, count - 1 do
		local k = i + offset -- steps from the gap's centre, going round
		if gap <= 0 or math.min(k, count - k) > (gap - 1) / 2 + 1e-6 then
			table.insert(out, gapAngle + k * step)
		end
	end
	return out
end
Bosses.GapAngles = gapAngles

-- a ring of shots from (x, z) with `gap` shots missing around gapAngle (gap 0: a full ring)
function Bosses.GapRing(run, EM, x: number, z: number, count: number, gap: number, gapAngle: number, speed: number, damage: number, radius: number?, life: number?)
	for _, a in gapAngles(count, gap, gapAngle) do
		EM.Shoot(run, x, z, cos(a) * speed, sin(a) * speed, radius or 1.4, damage, life or 5)
	end
end

-- a ring of shots coming IN from a circle of radius r around (x, z) towards its centre
function Bosses.InwardRing(run, EM, x: number, z: number, r: number, count: number, gap: number, gapAngle: number, speed: number, damage: number)
	for _, a in gapAngles(count, gap, gapAngle) do
		EM.Shoot(run, x + cos(a) * r, z + sin(a) * r, -cos(a) * speed, -sin(a) * speed, 1.4, damage, r / speed)
	end
end

local function ring(run, e, count: number, speed: number, damage: number, offset: number, EM)
	for i = 1, count do
		local a = offset + (i / count) * TAU
		EM.Shoot(run, e.X, e.Z, cos(a) * speed, sin(a) * speed, 1.4, damage, 5)
	end
end

local ACTIONS = {}

function ACTIONS.Slam(run, e, p, scale)
	telegraph(run, e, 1, run.PX, run.PZ, 0, p.SlamRadius, 0, p.SlamDelay, p.SlamDamage * scale, "Slam")
	e.Busy = p.SlamDelay * 0.8
	e.PendingExpose = { Reason = "Slam", At = run.Time + p.SlamDelay }
	state(run, e, ES.Windup)
end

function ACTIONS.DoubleSlam(run, e, p, scale)
	ACTIONS.Slam(run, e, p, scale)
	e.SecondSlamAt = run.Time + 0.67
	e.PendingExpose = { Reason = "DoubleSlam", At = run.Time + 0.67 + p.SlamDelay }
end

-- jumps onto the spot where the player stands
function ACTIONS.Leap(run, e, p, scale)
	local tx, tz = run.PX, run.PZ
	telegraph(run, e, 1, tx, tz, 0, p.LeapRadius, 0, p.LeapDelay, p.LeapDamage * scale, "Land")
	e.LeapFromX, e.LeapFromZ = e.X, e.Z
	e.LeapToX, e.LeapToZ = tx, tz
	e.LeapT, e.LeapDur = 0, p.LeapDelay
	e.Air = true
	e.Busy = p.LeapDelay
	e.PendingExpose = { Reason = "Leap", At = run.Time + p.LeapDelay }
	state(run, e, ES.Dash)
end

-- vanishes and reappears on top of the player
function ACTIONS.Teleport(run, e, p, scale)
	local a = run.Rng:NextNumber(0, TAU)
	local tx, tz = run.PX + cos(a) * 2, run.PZ + sin(a) * 2
	telegraph(run, e, 1, tx, tz, 0, p.TeleportRadius, 0, p.TeleportDelay, p.TeleportDamage * scale, "Slam")
	e.TeleportAt = run.Time + p.TeleportDelay * 0.85
	e.TeleportX, e.TeleportZ = tx, tz
	e.Busy = p.TeleportDelay
	e.PendingExpose = { Reason = "Teleport", At = run.Time + p.TeleportDelay }
	run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 1.5, 0, GFX.Teleport)
	state(run, e, ES.Windup)
end

-- a volley of impacts around the player
function ACTIONS.Barrage(run, e, p, scale)
	local rng = run.Rng
	for i = 1, p.BarrageCount do
		local x, z
		if i == 1 then
			x, z = run.PX, run.PZ
		else
			local a = rng:NextNumber(0, TAU)
			local r = rng:NextNumber(4, p.BarrageSpread)
			x, z = run.PX + cos(a) * r, run.PZ + sin(a) * r
		end
		telegraph(run, e, 1, x, z, 0, p.BarrageRadius, 0, p.BarrageDelay + (i - 1) * 0.12, p.BarrageDamage * scale, "Slam")
	end
	e.Busy = 0.6
	state(run, e, ES.Windup)
end

-- laser lines through the player's position
function ACTIONS.Sweep(run, e, p, scale)
	local base = run.Rng:NextNumber(0, math.pi)
	local n = p.SweepCount
	for i = 1, n do
		local a = base + (i - 1) * (math.pi / n)
		local dx, dz = cos(a), sin(a)
		local half = p.SweepLength / 2
		telegraph(run, e, 4, run.PX - dx * half, run.PZ - dz * half, a, p.SweepLength, p.SweepWidth, p.SweepDelay + (i - 1) * 0.18, p.SweepDamage * scale, "Sweep")
	end
	e.Busy = p.SweepDelay * 0.6
	e.PendingExpose = { Reason = "Sweep", At = run.Time + p.SweepDelay + n * 0.18 }
	state(run, e, ES.Windup)
end

-- void zones that stay on the ground for a few seconds
function ACTIONS.Hazard(run, e, p, scale)
	local rng = run.Rng
	for i = 1, p.HazardCount do
		local x, z = run.PX, run.PZ
		if i > 1 then
			local a = rng:NextNumber(0, TAU)
			local r = rng:NextNumber(8, 16)
			x, z = run.PX + cos(a) * r, run.PZ + sin(a) * r
		end
		telegraph(run, e, 3, x, z, 0, p.HazardRadius, p.HazardTime, p.HazardDelay, p.HazardDamage * scale, "Hazard")
	end
end

function ACTIONS.Dash(run, e, p, scale)
	local dx, dz = run.PX - e.X, run.PZ - e.Z
	local d = max(0.1, sqrt(dx * dx + dz * dz))
	e.DirX, e.DirZ = dx / d, dz / d
	e.DashAt = run.Time + p.DashWindup
	e.DashDamage = p.DashDamage * scale
	e.Busy = p.DashWindup
	telegraph(run, e, 2, e.X, e.Z, atan2(e.DirZ, e.DirX), p.DashLength, e.Radius * 2, p.DashWindup, 0)
	state(run, e, ES.Windup)
end

function ACTIONS.Ring(run, e, p, scale, EM)
	ring(run, e, p.RingCount, p.RingSpeed, p.RingDamage * scale, run.Rng:NextNumber(0, TAU), EM)
end

function ACTIONS.Spiral(run, e, p, scale)
	e.SpiralLeft = p.SpiralCount
	e.SpiralAngle = run.Rng:NextNumber(0, TAU)
	e.SpiralTimer = 0
	e.SpiralDamage = p.SpiralDamage * scale
	e.PendingExpose = { Reason = "Spiral", At = run.Time + p.SpiralCount * 0.07 }
end

-- DOOM RING (THE FINAL ONE): a ring of shots with one gap; a line shows where the gap is
function ACTIONS.DoomRing(run, e, p, scale)
	local gapA = run.Rng:NextNumber(0, TAU)
	local delay = p.DoomDelay or 1.2
	e.DoomAt = run.Time + delay
	e.DoomGap = gapA
	e.DoomDamage = p.DoomDamage * scale
	telegraph(run, e, 2, e.X, e.Z, gapA, 30, 6, delay, 0)
	state(run, e, ES.Windup)
	e.Busy = delay
end

function ACTIONS.Summon(run, e, p, _scale, EM)
	local main = e.Encounter and e.Encounter.Main
	for i = 1, p.SummonCount do
		local a = (i / p.SummonCount) * TAU
		local add = EM.Spawn(run, p.SummonKey, e.X + cos(a) * (e.Radius + 3), e.Z + sin(a) * (e.Radius + 3), { Force = p.SummonKey == "Goblin67" or main, NoScale = p.SummonKey == "Goblin67" })
		if add and main then
			add.ArenaAdd = true -- stays inside the sealed arena
		end
	end
end

function ACTIONS.Rain(run, _e, p, _scale, EM)
	for _ = 1, p.RainCount do
		local a = run.Rng:NextNumber(0, TAU)
		local r = run.Rng:NextNumber(10, 30)
		EM.Spawn(run, "Goober", run.PX + cos(a) * r, run.PZ + sin(a) * r, { FromSky = true })
	end
end

---------------------------------------------------------------------------
-- the MAIN bosses of the harder tiers (their arena: the 67 ARENA, BossData.Main)
---------------------------------------------------------------------------
-- the arena a boss fights in: centre and radius (a boss on its own: around its home)
local function arenaOf(e): (number, number, number)
	local enc = e.Encounter
	if enc and enc.Main then
		return enc.X, enc.Z, MAIN.ArenaR
	end
	return e.HomeX or e.X, e.HomeZ or e.Z, MAIN.ArenaR
end
Bosses.ArenaOf = arenaOf

-- (x, z) pulled inside the arena (margin studs from its edge)
local function inArena(e, x: number, z: number, margin: number?): (number, number)
	local cx, cz, r = arenaOf(e)
	local lim = r - (margin or 3)
	local dx, dz = x - cx, z - cz
	local d = sqrt(dx * dx + dz * dz)
	if d > lim then
		return cx + dx / d * lim, cz + dz / d * lim
	end
	return x, z
end

-- a random point rMin..rMax from (x, z), inside the arena
local function pointNear(run, e, x: number, z: number, rMin: number, rMax: number): (number, number)
	local a = run.Rng:NextNumber(0, TAU)
	local r = run.Rng:NextNumber(rMin, rMax)
	return inArena(e, x + cos(a) * r, z + sin(a) * r)
end

-- an add of a main boss: forced past the enemy cap and kept inside the sealed arena
local function spawnAdd(run, e, EM, key: string, x: number, z: number, opts: { [string]: any }?)
	local o = opts or {}
	o.Force = true
	local add = EM.Spawn(run, key, x, z, o)
	if add and e.Encounter and e.Encounter.Main then
		add.ArenaAdd = true
	end
	return add
end
Bosses.SpawnAdd = spawnAdd

-- a short line on the boss's name plate / a toast for a main boss (what to do now)
local function cue(run, e, text: string, time: number?)
	run:Event("BossCue", { Id = e.Id, Text = text, Time = time or 2.5 })
end
Bosses.Cue = cue

-- the part of the line through (px, pz) along (dx, dz) inside the arena: start x, z and length
local function chord(e, px: number, pz: number, dx: number, dz: number): (number?, number?, number)
	local cx, cz, r = arenaOf(e)
	r -= 1.5
	local ox, oz = px - cx, pz - cz
	local b = ox * dx + oz * dz
	local c = ox * ox + oz * oz - r * r
	local disc = b * b - c
	if disc <= 0 then
		return nil, nil, 0
	end
	local s = sqrt(disc)
	local t0 = -b - s
	return px + dx * t0, pz + dz * t0, 2 * s
end

-- a stampede lane: a red line that hits when the herd runs down it (the runners are its look)
local RUNNER_SPEED = 48
local function lane(run, e, EM, x: number, z: number, a: number, length: number, width: number, delay: number, damage: number, herdKey: string?, herd: number)
	telegraph(run, e, SHAPE.Laser, x, z, a, length, width, delay, damage, "Sweep")
	if herdKey and herd > 0 then
		local dx, dz = cos(a), sin(a)
		Bosses.After(run, e, max(0, delay - 0.35), function(_, _, em)
			for k = 1, herd do
				local back = (k - 1) * 2.6
				local r = spawnAdd(run, e, em, herdKey, x - dx * back, z - dz * back, { Behavior = "March", DirX = dx, DirZ = dz, Life = (length + back) / RUNNER_SPEED + 0.2 })
				if r then
					r.Speed = RUNNER_SPEED
					r.NoContact = true -- the line does the damage
					r.Runner = true
				end
			end
		end)
	end
end

-- MAMA GOOBER: jumps onto you, splashes goo drops out of the landing
function ACTIONS.BellyFlop(run, e, p, scale)
	local delay = windup(run, p.FlopDelay)
	local tx, tz = inArena(e, run.PX, run.PZ, 4)
	telegraph(run, e, SHAPE.Circle, tx, tz, 0, p.FlopRadius, 0, delay, p.FlopDamage * scale, "Land")
	e.LeapFromX, e.LeapFromZ = e.X, e.Z
	e.LeapToX, e.LeapToZ = tx, tz
	e.LeapT, e.LeapDur = 0, delay
	e.Air = true
	e.Busy = delay
	e.PendingExpose = { Reason = "BellyFlop", At = run.Time + delay }
	state(run, e, ES.Dash)
	Bosses.After(run, e, delay, function(_, _, em)
		Bosses.GapRing(run, em, tx, tz, p.FlopDrops, 0, run.Rng:NextNumber(0, TAU), p.FlopDropSpeed, p.FlopDropDamage * scale, 1.2, 3.5)
	end)
end

-- goobers fall out of the sky all over the arena
function ACTIONS.GooRain(run, e, p, _scale, EM)
	for _ = 1, p.RainCount do
		local x, z = pointNear(run, e, run.PX, run.PZ, 8, 22)
		spawnAdd(run, e, EM, "Goober", x, z, { FromSky = true })
	end
end

-- a nest of eggs around her: they hatch into goobers unless you break them
function ACTIONS.Nest(run, e, p, _scale, EM)
	local base = run.Rng:NextNumber(0, TAU)
	for i = 1, p.EggCount do
		local a = base + i * TAU / p.EggCount
		local x, z = inArena(e, e.X + cos(a) * (e.Radius + 7), e.Z + sin(a) * (e.Radius + 7), 5)
		spawnAdd(run, e, EM, p.EggKey, x, z)
	end
	cue(run, e, "BREAK THE EGGS!")
end

-- THE HORDEMASTER: parallel stampede lanes through your spot (one more every phase)
function ACTIONS.Lanes(run, e, p, scale, EM)
	local n = p.LaneCount + max(0, (e.Phase or 1) - 1)
	local a = run.Rng:NextNumber(0, TAU)
	local dx, dz = cos(a), sin(a)
	local nx, nz = -dz, dx
	local delay = windup(run, p.LaneDelay)
	for i = 1, n do
		local off = (i - (n + 1) / 2) * (p.LaneWidth + 6) + run.Rng:NextNumber(-1.5, 1.5)
		local x, z, len = chord(e, run.PX + nx * off, run.PZ + nz * off, dx, dz)
		if x and z and len > 8 then
			lane(run, e, EM, x, z, a, min(len, p.LaneLength), p.LaneWidth, delay + (i - 1) * 0.12, p.LaneDamage * scale, p.LaneKey, p.LaneHerd)
		end
	end
	e.Busy = 0.5
	state(run, e, ES.Windup)
end

-- plants a war banner: the horde (and it) runs faster until you break the pole
function ACTIONS.BannerCall(run, e, p, _scale, EM)
	if e.Banner and e.Banner.Alive then
		return
	end
	local a = run.Rng:NextNumber(0, TAU)
	local x, z = inArena(e, e.X + cos(a) * (e.Radius + 7), e.Z + sin(a) * (e.Radius + 7), 5)
	local b = spawnAdd(run, e, EM, p.BannerKey, x, z)
	if b then
		b.Owner = e
		e.Banner = b
		run:Write("Fx", 0, x, z, 0, b.Def.Params.Aura, 0, GFX.Rally)
		cue(run, e, "BREAK THE BANNER!", 4)
	end
end

-- a ring of shielders around you, one gap, closing in
function ACTIONS.Formation(run, e, p, _scale, EM)
	local cx, cz = run.PX, run.PZ
	local gapA = run.Rng:NextNumber(0, TAU)
	for _, a in gapAngles(p.FormationCount, p.FormationGap, gapA) do
		local x, z = inArena(e, cx + cos(a) * p.FormationRadius, cz + sin(a) * p.FormationRadius, 2)
		local s = spawnAdd(run, e, EM, p.FormationKey, x, z, { Behavior = "Converge", Life = p.FormationLife })
		if s then
			s.CX, s.CZ = cx, cz
			s.Speed = p.FormationSpeed
		end
	end
	-- the way out
	telegraph(run, e, SHAPE.DashLine, cx, cz, gapA, p.FormationRadius + 4, 6, windup(run, 1.2), 0)
	cue(run, e, "FIND THE GAP")
end

-- lanes from all four sides; the cross in the middle of the arena stays safe
function ACTIONS.FullCharge(run, e, p, scale, EM)
	local cx, cz, r = arenaOf(e)
	local safe = p.ChargeSafe
	local delay = windup(run, p.ChargeDelay)
	local n = 0
	for _, side in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		local sx, sz = side[1], side[2] -- the herd runs this way (inwards)
		for _, o in { 13, 24, 35 } do
			for _, sign in { -1, 1 } do
				local along = sqrt(max(0, (r - 1.5) ^ 2 - o * o))
				if along > safe + 3 then
					local ox, oz = -sz * o * sign, sx * o * sign
					n += 1
					lane(run, e, EM, cx + ox - sx * along, cz + oz - sz * along, atan2(sz, sx), along - safe, p.LaneWidth, delay + (n % 4) * 0.06, p.ChargeDamage * scale, if n % 2 == 0 then p.LaneKey else nil, 1)
				end
			end
		end
	end
	e.Busy = delay
	state(run, e, ES.Windup)
	cue(run, e, "FULL CHARGE: GET TO THE CROSS!", 3)
end

-- THE DREAD: shadow hands grab where you stand and around you
function ACTIONS.Hands(run, e, p, scale)
	local delay = windup(run, p.HandDelay)
	for i = 1, p.HandCount do
		local x, z = run.PX, run.PZ
		if i > 1 then
			x, z = pointNear(run, e, run.PX, run.PZ, 4, p.HandSpread)
		end
		telegraph(run, e, SHAPE.Circle, x, z, 0, p.HandRadius, 0, delay + (i - 1) * 0.12, p.HandDamage * scale, "Slam")
	end
	e.Busy = 0.5
	state(run, e, ES.Windup)
end

-- the moon eye sweeps a fan of beams across you, one after the other; then it stays open
function ACTIONS.EyeSweep(run, e, p, scale)
	local n = p.SweepLines
	local toward = atan2(run.PZ - e.Z, run.PX - e.X)
	local dir = if run.Rng:NextNumber() < 0.5 then -1 else 1
	local base = toward - dir * (n - 1) / 2 * p.SweepStep
	local delay = windup(run, p.SweepDelay)
	for i = 0, n - 1 do
		telegraph(run, e, SHAPE.Laser, e.X, e.Z, base + dir * i * p.SweepStep, p.SweepLength, p.SweepWidth, delay + i * p.SweepGap, p.SweepDamage * scale, "Sweep")
	end
	local done = delay + (n - 1) * p.SweepGap
	e.Busy = done
	e.PendingExpose = { Reason = "EyeSweep", At = run.Time + done }
	state(run, e, ES.Windup)
end

-- dread echoes: shadows follow the path you just walked
function ACTIONS.Echoes(run, e, p, scale)
	local pts = run:TrailPoints(3.2, 0.6)
	if #pts == 0 then
		return
	end
	local n = min(p.EchoCount, #pts)
	local delay = windup(run, p.EchoDelay)
	for i = 1, n do
		local pt = pts[max(1, math.floor(i * #pts / n))]
		telegraph(run, e, SHAPE.Circle, pt.X, pt.Z, 0, p.EchoRadius, 0, delay + (i - 1) * 0.15, p.EchoDamage * scale, "Slam")
	end
end

-- lights out: the arena goes dark around you (telegraphs keep glowing)
function ACTIONS.LightsOut(run, e, p)
	if run.Map then
		run.Map.DarkUntil = run.Time + p.DarkTime
	end
	run:Event("Arena", { Dark = true, Time = p.DarkTime })
	cue(run, e, "LIGHTS OUT", 2)
end

-- THE FURNACE: the arena is split in sectors; some heat up, then burn (never all of them)
function ACTIONS.Sectors(run, e, p, scale)
	local cx, cz, r = arenaOf(e)
	local n = p.SectorCount
	local hot = min(n - 2, p.SectorHot + max(0, (e.Phase or 1) - 1))
	local order = {}
	for k = 1, n do
		order[k] = k
	end
	for k = n, 2, -1 do
		local j = run.Rng:NextInteger(1, k)
		order[k], order[j] = order[j], order[k]
	end
	local delay = windup(run, p.SectorDelay)
	for i = 1, hot do
		local k = order[i]
		telegraph(run, e, SHAPE.Sector, cx, cz, (k - 0.5) * TAU / n, r, math.pi / n, delay, p.SectorDamage * scale, "Sector", nil, { Burn = SECTOR_BURN })
	end
	e.Busy = 0.4
end

-- two rings of embers, each with a gap (the line shows it)
function ACTIONS.EmberRing(run, e, p, scale)
	local delay = windup(run, 1.0)
	local gapA = atan2(run.PZ - e.Z, run.PX - e.X) + run.Rng:NextNumber(-1.2, 1.2)
	for k = 0, 1 do
		local a = gapA + k * 0.6
		local at = delay + k * 0.9
		telegraph(run, e, SHAPE.DashLine, e.X, e.Z, a, 26, 6, at, 0)
		Bosses.After(run, e, at, function(_, _, em)
			Bosses.GapRing(run, em, e.X, e.Z, p.EmberCount, p.EmberGap, a, p.EmberSpeed, p.EmberDamage * scale, 1.4, 4)
		end)
	end
	e.Busy = delay
	state(run, e, ES.Windup)
end

-- a meteor shower around you
function ACTIONS.Meteors(run, e, p, scale)
	local delay = windup(run, p.MeteorDelay)
	for i = 1, p.MeteorCount do
		local x, z = run.PX, run.PZ
		if i > 1 then
			x, z = pointNear(run, e, run.PX, run.PZ, 4, p.MeteorSpread)
		end
		telegraph(run, e, SHAPE.Circle, x, z, 0, p.MeteorRadius, 0, delay + (i - 1) * 0.14, p.MeteorDamage * scale, "Slam")
	end
end

-- it vents steam all around itself, then its door hangs open
function ACTIONS.Steam(run, e, p, scale)
	local delay = windup(run, p.SteamDelay)
	telegraph(run, e, SHAPE.Circle, e.X, e.Z, 0, p.SteamRadius, 0, delay, p.SteamDamage * scale, "Slam")
	e.Busy = delay
	e.PendingExpose = { Reason = "Steam", At = run.Time + delay }
	state(run, e, ES.Windup)
end

-- THE ERASER: a wide line, then it slides down it; its tip wears out
function ACTIONS.Swipe(run, e, p, scale)
	local dx, dz = run.PX - e.X, run.PZ - e.Z
	local d = max(0.1, sqrt(dx * dx + dz * dz))
	e.DirX, e.DirZ = dx / d, dz / d
	local a = atan2(e.DirZ, e.DirX)
	local _, _, inside = chord(e, e.X, e.Z, e.DirX, e.DirZ)
	local len = math.clamp(inside, 10, p.SwipeLength)
	local w = windup(run, p.SwipeWindup)
	telegraph(run, e, SHAPE.Laser, e.X, e.Z, a, len, p.SwipeWidth, w, p.SwipeDamage * scale, "Sweep")
	e.DashAt = run.Time + w
	e.DashLen, e.DashSpd = len, p.SwipeSpeed
	e.DashDamage = p.SwipeDamage * scale
	e.Busy = w
	e.PendingExpose = { Reason = "Swipe", At = run.Time + w + len / p.SwipeSpeed }
	state(run, e, ES.Windup)
end

-- erases circles of the floor: white means erased, don't stand in it
function ACTIONS.Erase(run, e, p, scale)
	local delay = windup(run, p.EraseDelay)
	for i = 1, p.EraseCount do
		local x, z = run.PX, run.PZ
		if i > 1 then
			x, z = pointNear(run, e, run.PX, run.PZ, 6, 16)
		end
		telegraph(run, e, SHAPE.Erase, x, z, 0, p.EraseRadius, p.EraseTime, delay + (i - 1) * 0.15, p.EraseDamage * scale, "Erase")
	end
end

-- every new phase erases a ring of the arena's edge (the arena shrinks)
function Bosses.EraseEdge(run, e, phase: number)
	local p = e.Def.Params
	local k = phase - (p.EdgeFrom or 2) + 1
	if k < 1 then
		return
	end
	local cx, cz, r = arenaOf(e)
	local rc = p.EdgeErase
	local ring = r - k * rc + rc * 0.35
	if ring < rc * 2.5 then
		return
	end
	local n = math.ceil(TAU * ring / (rc * 1.3))
	local delay = windup(run, 1.6)
	for i = 1, n do
		local a = i * TAU / n
		telegraph(run, e, SHAPE.Erase, cx + cos(a) * ring, cz + sin(a) * ring, 0, rc, 600, delay, (p.EraseDamage or 10) * e.DmgScale, "Erase")
	end
	cue(run, e, "THE EDGE IS ERASED", 3)
end

-- sketched copies of elite enemies (no loot, they fade after a while)
local SKETCHES = { "Brute", "Charger", "Leaper", "Spitter", "Shielder", "Predator", "Stampeder", "Wailer" }
function ACTIONS.Redraw(run, e, p, _scale, EM)
	local kinds = {}
	for _, key in SKETCHES do
		if EnemyData.OnTier(EnemyData.ByKey[key], run.Difficulty or 2) then
			table.insert(kinds, key)
		end
	end
	for _ = 1, p.RedrawCount do
		local key = kinds[run.Rng:NextInteger(1, #kinds)]
		local x, z = pointNear(run, e, e.X, e.Z, 8, 14)
		spawnAdd(run, e, EM, key, x, z, { Elite = true, Sketch = true, Life = p.RedrawLife })
	end
	cue(run, e, "REDRAW")
end

-- THE 67 PRIME: 6... 7...: six rings, a breath, seven rings, on a beat; the gap walks round
function ACTIONS.SixSeven(run, e, p, scale)
	local beat = p.SeriesBeat
	local lead = windup(run, 2 * beat)
	local gapA = atan2(run.PZ - e.Z, run.PX - e.X)
	for k = 1, 13 do
		local second = k > 6
		local at = lead + (k - 1) * beat + (if second then beat else 0)
		local a = gapA + (if second then 0.35 else -0.35) * ((k - 1) % 6 + (if second and k == 13 then 1 else 0))
		if k == 1 or k == 7 then
			telegraph(run, e, SHAPE.DashLine, e.X, e.Z, a, 26, 6, at, 0)
		end
		Bosses.After(run, e, at, function(_, _, em)
			Bosses.GapRing(run, em, e.X, e.Z, p.SeriesCount, p.SeriesGap, a, p.SeriesSpeed, p.SeriesDamage * scale, 1.3, 2.6)
		end)
	end
	e.Busy = lead + 14 * beat
	e.PendingExpose = { Reason = "Series", At = run.Time + e.Busy }
	state(run, e, ES.Windup)
	cue(run, e, "6... 7...", 3)
end

Bosses.Actions = ACTIONS
Bosses.Telegraph = telegraph -- mini-bosses (Sim/MiniBosses) telegraph the same way

-- movement intent for EnemyManager: dirX, dirZ, speed multiplier
function Bosses.Step(run, e, dx: number, dz: number, d: number, dt: number, EM): (number, number, number)
	local p = e.Def.Params
	local scale = e.DmgScale

	local rate = e.Rate or 1
	if not e.Encounter then
		Bosses.RunQueue(run, e, EM) -- (an encounter's body runs its queue in Sim/MiniBosses)
	end

	-- the doom ring fires (everything but the gap)
	if e.DoomAt and run.Time >= e.DoomAt then
		e.DoomAt = nil
		local n = p.DoomCount or 40
		local gap = p.DoomGap or 5
		local speed = p.DoomSpeed or 15
		for i = 1, n do
			local a = e.DoomGap + (i / n) * TAU
			local off = (i % n)
			if off > math.floor(gap / 2) and off < n - math.floor(gap / 2) then
				EM.Shoot(run, e.X, e.Z, cos(a) * speed, sin(a) * speed, 1.5, e.DoomDamage, 5)
			end
		end
		run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2, 0, GFX.Enrage)
	end

	-- second slam of the 67 King
	if e.SecondSlamAt and run.Time >= e.SecondSlamAt then
		e.SecondSlamAt = nil
		telegraph(run, e, 1, run.PX, run.PZ, 0, p.SlamRadius * 1.15, 0, p.SlamDelay, p.SlamDamage * scale, "Slam")
	end

	-- spiral in progress
	if e.SpiralLeft and e.SpiralLeft > 0 then
		e.SpiralTimer -= dt
		while e.SpiralTimer <= 0 and e.SpiralLeft > 0 do
			e.SpiralTimer += 0.07
			e.SpiralLeft -= 1
			e.SpiralAngle += 0.5
			local a = e.SpiralAngle
			EM.Shoot(run, e.X, e.Z, cos(a) * p.SpiralSpeed, sin(a) * p.SpiralSpeed, 1.3, e.SpiralDamage, 5)
			if e.Key == "King67" or e.Enraged then
				EM.Shoot(run, e.X, e.Z, cos(a + math.pi) * p.SpiralSpeed, sin(a + math.pi) * p.SpiralSpeed, 1.3, e.SpiralDamage, 5)
			end
		end
	end

	-- leap in the air: straight line to the landing spot
	if e.LeapToX then
		e.LeapT += dt
		local f = min(1, e.LeapT / e.LeapDur)
		e.X = e.LeapFromX + (e.LeapToX - e.LeapFromX) * f
		e.Z = e.LeapFromZ + (e.LeapToZ - e.LeapFromZ) * f
		if f >= 1 then
			e.LeapToX = nil
			e.Air = false
			state(run, e, ES.Normal)
		end
		return 0, 0, 0
	end

	-- teleport arrives
	if e.TeleportAt and run.Time >= e.TeleportAt then
		e.TeleportAt = nil
		e.X, e.Z = e.TeleportX, e.TeleportZ
		e.SentX, e.SentZ = e.X, e.Z
		run:Write("Blink", e.Id, e.X, e.Z)
		run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 1.5, 0, GFX.Teleport)
	end

	-- dash (a swipe has its own length and speed)
	if e.DashAt and run.Time >= e.DashAt then
		e.DashAt = nil
		e.Dashing = true
		e.DashLeft = e.DashLen or p.DashLength
		state(run, e, ES.Dash)
	end
	if e.Dashing then
		local speed = e.DashSpd or p.DashSpeed
		e.DashLeft -= speed * dt
		if e.DashLeft <= 0 then
			e.Dashing = false
			e.DashLen, e.DashSpd = nil, nil
			state(run, e, ES.Normal)
		end
		return e.DirX, e.DirZ, speed / e.Speed
	end

	if e.Busy > 0 then
		e.Busy -= dt
		if e.Busy <= 0 then
			state(run, e, ES.Normal)
		end
		return 0, 0, 0
	end

	-- next attack (one per step)
	for _, pattern in e.Patterns do
		e.Timers[pattern] -= dt * rate
		if e.Timers[pattern] <= 0 then
			e.Timers[pattern] = p[EVERY[pattern]] or 6
			local action = ACTIONS[pattern]
			if action then
				action(run, e, p, scale, EM)
			end
			break
		end
	end

	if d < e.Radius + PLAYER_R then
		return 0, 0, 0
	end
	return dx / d, dz / d, 1
end

-- distance from (px, pz) to the segment starting at (x, z) with angle a and length len
local function segmentDistance(px: number, pz: number, x: number, z: number, a: number, len: number): number
	local ux, uz = cos(a), sin(a)
	local rx, rz = px - x, pz - z
	local t = math.clamp(rx * ux + rz * uz, 0, len)
	local cx, cz = x + ux * t, z + uz * t
	return sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

-- is (px, pz) inside the sector around (x, z) towards angle with half-arc `half`, radius r?
local function inSector(px: number, pz: number, x: number, z: number, angle: number, half: number, r: number, pad: number): boolean
	local dx, dz = px - x, pz - z
	local d = sqrt(dx * dx + dz * dz)
	if d > r + pad then
		return false
	end
	if d < pad then
		return true
	end
	local diff = math.abs(((atan2(dz, dx) - angle + math.pi) % TAU) - math.pi)
	return diff <= half + pad / d
end
Bosses.InSector = inSector

-- inside one of the safe holes of a circle telegraph?
local function inSafe(px: number, pz: number, safe): boolean
	for _, hole in safe do
		local dx, dz = px - hole.X, pz - hole.Z
		if dx * dx + dz * dz <= (hole.R - PLAYER_R * 0.5) ^ 2 then
			return true
		end
	end
	return false
end

function Bosses.StepTelegraphs(run, _EM, dt: number?)
	local list = run.Telegraphs
	local now = run.Time
	local i = 1
	while i <= #list do
		local t = list[i]
		if now >= t.At then
			if t.Shape == 1 then
				if t.Damage > 0 then
					local dx, dz = run.PX - t.X, run.PZ - t.Z
					if dx * dx + dz * dz <= (t.R + PLAYER_R * 0.5) ^ 2 and not (t.Safe and inSafe(run.PX, run.PZ, t.Safe)) then
						run:HurtPlayer(t.Damage, true, "Boss")
					end
				end
				run:Write("Fx", 0, t.X, t.Z, 0, t.R, 0, if t.Kind == "Land" then GFX.Land else GFX.Slam)
			elseif t.Shape == 4 then
				if segmentDistance(run.PX, run.PZ, t.X, t.Z, t.Angle, t.R) <= t.Width / 2 + PLAYER_R * 0.5 then
					run:HurtPlayer(t.Damage, true, "Boss")
				end
				run:Write("Fx", 0, t.X, t.Z, t.Angle, t.R, t.Width, GFX.Sweep)
			elseif t.Shape == 7 then
				-- a sector: hits now, then keeps burning for a moment
				if inSector(run.PX, run.PZ, t.X, t.Z, t.Angle, t.Width, t.R, PLAYER_R * 0.5) then
					run:HurtPlayer(t.Damage, true, "Boss")
				end
				if t.Burn then
					table.insert(run.Hazards, { X = t.X, Z = t.Z, R = t.R, Until = now + t.Burn, Tick = 0.5, Damage = t.Damage * 0.35, Sector = t.Angle, Half = t.Width })
				end
			elseif t.Shape == 3 or t.Shape == 6 or t.Shape == 9 then
				table.insert(run.Hazards, { X = t.X, Z = t.Z, R = t.R, Until = now + t.Width, Tick = 0, Damage = t.Damage, Void = t.Shape == 3 })
			elseif t.Shape == 5 then
				-- a puddle: no damage, you wade through it slower (Run:SlowFactor)
				table.insert(run.Hazards, { X = t.X, Z = t.Z, R = t.R, Until = now + t.Width, Tick = 0, Damage = 0, Slow = t.Slow or 0.6 })
			end
			list[i] = list[#list]
			list[#list] = nil
		else
			i += 1
		end
	end

	-- lingering zones (void, spills, fire, erased floor, burning sectors)
	local hazards = run.Hazards
	i = 1
	while i <= #hazards do
		local h = hazards[i]
		if now >= h.Until then
			hazards[i] = hazards[#hazards]
			hazards[#hazards] = nil
		else
			h.Tick -= dt or 0.05
			if h.Tick <= 0 and h.Damage > 0 then
				local inside
				if h.Sector then
					inside = inSector(run.PX, run.PZ, h.X, h.Z, h.Sector, h.Half, h.R, PLAYER_R * 0.3)
				else
					local dx, dz = run.PX - h.X, run.PZ - h.Z
					inside = dx * dx + dz * dz <= (h.R + PLAYER_R * 0.3) ^ 2
				end
				if inside then
					h.Tick = 0.5
					run:HurtPlayer(h.Damage, true, "Hazard")
					if h.Void then
						run:Write("Fx", 0, run.PX, run.PZ, 0, 3, 0, GFX.Hazard)
					end
				end
			end
			i += 1
		end
	end
end

function Bosses.OnKilled(run, e, EM)
	local p = e.Def.Params
	table.insert(run.Result.Bosses, e.Key)
	if run.Boss == e then
		run.Boss = nil
	end
	run:AddCoins(p.Coins or 0)
	Pickups.SpawnItem(run, if e.Key == "King67" then "Chest67" else "Chest", e.X, e.Z)
	for k = 1, GameConfig.Rewards.FragmentsPerBoss + (run.LiveEvent.BossFragments or 0) do
		local a = k * 2.4
		Pickups.SpawnItem(run, "Fragment", e.X + cos(a) * 3, e.Z + sin(a) * 3)
	end
	run:Event("BossDefeated", { Id = e.Id, Key = e.Key, Title = p.Title, Final = p.Final == true })
	if p.Final then
		run.VictoryAt = run.Time + 3.5
		run.Invulnerable = math.max(run.Invulnerable, 10) -- nothing can take this win away
		run:Banner("VICTORY", p.Title .. " has been defeated", "Victory")
	else
		run:Banner(p.Title .. " DEFEATED", "Grab the chest!", "Reward")
	end
	-- a boss kill clears some pressure
	local n = 0
	for _, other in table.clone(run.Enemies) do
		local dx, dz = other.X - e.X, other.Z - e.Z
		if not other.IsBoss and other.Key ~= "Crate" and dx * dx + dz * dz < 30 * 30 and n < 40 then
			n += 1
			EM.Damage(run, other, other.HP + 1, 0, dx, dz, 8)
		end
	end
	return min(n, 40)
end

return Bosses
