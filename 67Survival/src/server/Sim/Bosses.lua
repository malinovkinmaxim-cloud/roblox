--[[
	Bosses - the attack patterns of the classic bosses and THE FINAL ONE. Every attack is
	telegraphed (red circle / line / zone on the ground, sent as a Telegraph record) so the
	player has to move:
	  Slam DoubleSlam Leap Teleport Barrage Sweep Hazard Dash Ring Spiral Summon Rain DoomRing
	PHASES come from shared/BossData.lua (Sim/MiniBosses.StepPhase): each one speeds the boss
	up (e.Rate) and adds Params.PhasePatterns[phase] (or EnragePatterns in phase 2). After some
	attacks the boss is EXPOSED (its weak point, BossData WeakPoint): e.PendingExpose.
	DoomRing (THE FINAL ONE): a ring of shots with one gap; a line points at the gap.

	Called by EnemyManager (which passes itself in, avoiding a require cycle).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local Protocol = require(Shared.Protocol)

local Pickups = require(script.Parent.Pickups)

local Bosses = {}

local sqrt, cos, sin, atan2, min, max = math.sqrt, math.cos, math.sin, math.atan2, math.min, math.max
local TAU = math.pi * 2
local PLAYER_R = GameConfig.Player.Radius
local GFX = Protocol.Fx
local ES = Protocol.EState

local EVERY = {
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
	if run.Mods and run.Mods.BossRage then
		-- BOSS RAGE difficulty: the second phase's attacks are there from the start
		Bosses.AddPhase(run, e, 2)
	end
	-- the big bar at the top of the screen: THE FINAL ONE (and a boss without an encounter)
	local enc = e.Encounter
	if not enc or enc.Main then
		run.Boss = e
		run:Event("BossSpawn", { Id = e.Id, Key = e.Key, Title = p.Title, MaxHP = math.ceil(e.MaxHP), Final = p.Final == true })
	end
end

-- the patterns a phase adds
function Bosses.AddPhase(run, e, phase: number)
	local p = e.Def.Params
	local add = (p.PhasePatterns and p.PhasePatterns[phase]) or (if phase == 2 then p.EnragePatterns else nil) or {}
	for i, pattern in add do
		if not e.Timers[pattern] then
			table.insert(e.Patterns, pattern)
			e.Timers[pattern] = 1.2 + i * 0.8
		end
	end
	local _ = run
end

-- a delayed attack: shape 1 circle, 2 dash line (visual only), 3 lingering zone, 4 laser line,
-- 5 slippery puddle (slows, no damage), 6 spill (a small lingering zone that hurts): Protocol.Shapes
local function telegraph(run, e, shape: number, x: number, z: number, angle: number, size: number, width: number, delay: number, damage: number, kind: string?, slow: number?)
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
	})
	run:Write("Telegraph", shape, x, z, angle, size, width, delay)
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

Bosses.Actions = ACTIONS
Bosses.Telegraph = telegraph -- mini-bosses (Sim/MiniBosses) telegraph the same way

-- movement intent for EnemyManager: dirX, dirZ, speed multiplier
function Bosses.Step(run, e, dx: number, dz: number, d: number, dt: number, EM): (number, number, number)
	local p = e.Def.Params
	local scale = e.DmgScale

	local rate = e.Rate or 1

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

	-- dash
	if e.DashAt and run.Time >= e.DashAt then
		e.DashAt = nil
		e.Dashing = true
		e.DashLeft = p.DashLength
		state(run, e, ES.Dash)
	end
	if e.Dashing then
		local step = p.DashSpeed * dt
		e.DashLeft -= step
		if e.DashLeft <= 0 then
			e.Dashing = false
			state(run, e, ES.Normal)
		end
		return e.DirX, e.DirZ, p.DashSpeed / e.Speed
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
					if dx * dx + dz * dz <= (t.R + PLAYER_R * 0.5) ^ 2 then
						run:HurtPlayer(t.Damage, true, "Boss")
					end
				end
				run:Write("Fx", 0, t.X, t.Z, 0, t.R, 0, if t.Kind == "Land" then GFX.Land else GFX.Slam)
			elseif t.Shape == 4 then
				if segmentDistance(run.PX, run.PZ, t.X, t.Z, t.Angle, t.R) <= t.Width / 2 + PLAYER_R * 0.5 then
					run:HurtPlayer(t.Damage, true, "Boss")
				end
				run:Write("Fx", 0, t.X, t.Z, t.Angle, t.R, t.Width, GFX.Sweep)
			elseif t.Shape == 3 or t.Shape == 6 then
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

	-- lingering void zones
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
				local dx, dz = run.PX - h.X, run.PZ - h.Z
				if dx * dx + dz * dz <= (h.R + PLAYER_R * 0.3) ^ 2 then
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
