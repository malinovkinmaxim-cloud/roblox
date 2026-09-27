--[[
	Bosses - boss attack patterns. Every attack is telegraphed (red circle / line on the
	ground, sent as a Telegraph record) so the player has to move: slam circles, dashes,
	projectile rings and spirals, summons, goober rain. Enrage below a HP fraction.

	Called by EnemyManager (which passes itself in, avoiding a require cycle).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local WaveData = require(Shared.WaveData)

local Pickups = require(script.Parent.Pickups)

local Bosses = {}

local sqrt, cos, sin, atan2, min = math.sqrt, math.cos, math.sin, math.atan2, math.min
local TAU = math.pi * 2
local PLAYER_R = GameConfig.Player.Radius

Bosses.FX_SLAM = 20 -- generic Fx variants (weapon id 0)
Bosses.FX_ENRAGE = 21

local EVERY = {
	Slam = "SlamEvery",
	DoubleSlam = "SlamEvery",
	Dash = "DashEvery",
	Ring = "RingEvery",
	Spiral = "SpiralEvery",
	Summon = "SummonEvery",
	Rain = "RainEvery",
}

function Bosses.Init(run, e)
	local p = e.Def.Params
	e.Timers = {}
	for i, pattern in p.Patterns do
		-- stagger the first attacks so the boss opens with its first pattern
		e.Timers[pattern] = (p[EVERY[pattern]] or 6) * (0.35 + 0.2 * (i - 1))
	end
	e.Busy = 0
	e.Enraged = false
	run.Boss = e
	run:Event("BossSpawn", { Id = e.Id, Key = e.Key, Title = p.Title, MaxHP = math.ceil(e.MaxHP), Final = p.Final == true })
end

local function telegraph(run, e, shape: number, x: number, z: number, angle: number, size: number, width: number, delay: number, damage: number)
	table.insert(run.Telegraphs, {
		At = run.Time + delay,
		Shape = shape,
		X = x,
		Z = z,
		R = size,
		Damage = damage,
		Boss = e,
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
	telegraph(run, e, 1, run.PX, run.PZ, 0, p.SlamRadius, 0, p.SlamDelay, p.SlamDamage * scale)
	e.Busy = p.SlamDelay * 0.8
	run:Write("EState", e.Id, 1)
end

function ACTIONS.DoubleSlam(run, e, p, scale)
	ACTIONS.Slam(run, e, p, scale)
	e.SecondSlamAt = run.Time + 0.67
end

function ACTIONS.Dash(run, e, p, scale)
	local dx, dz = run.PX - e.X, run.PZ - e.Z
	local d = math.max(0.1, sqrt(dx * dx + dz * dz))
	e.DirX, e.DirZ = dx / d, dz / d
	e.DashAt = run.Time + p.DashWindup
	e.DashDamage = p.DashDamage * scale
	e.Busy = p.DashWindup
	telegraph(run, e, 2, e.X, e.Z, atan2(e.DirZ, e.DirX), p.DashLength, e.Radius * 2, p.DashWindup, 0)
	run:Write("EState", e.Id, 1)
end

function ACTIONS.Ring(run, e, p, scale, EM)
	ring(run, e, p.RingCount, p.RingSpeed, p.RingDamage * scale, run.Rng:NextNumber(0, TAU), EM)
end

function ACTIONS.Spiral(run, e, p, scale)
	e.SpiralLeft = p.SpiralCount
	e.SpiralAngle = run.Rng:NextNumber(0, TAU)
	e.SpiralTimer = 0
	e.SpiralDamage = p.SpiralDamage * scale
end

function ACTIONS.Summon(run, e, p, _scale, EM)
	for i = 1, p.SummonCount do
		local a = (i / p.SummonCount) * TAU
		EM.Spawn(run, p.SummonKey, e.X + cos(a) * (e.Radius + 3), e.Z + sin(a) * (e.Radius + 3))
	end
end

function ACTIONS.Rain(run, _e, p, _scale, EM)
	for _ = 1, p.RainCount do
		local a = run.Rng:NextNumber(0, TAU)
		local r = run.Rng:NextNumber(10, 30)
		EM.Spawn(run, "Goober", run.PX + cos(a) * r, run.PZ + sin(a) * r, { FromSky = true })
	end
end

-- movement intent for EnemyManager: dirX, dirZ, speed multiplier
function Bosses.Step(run, e, dx: number, dz: number, d: number, dt: number, EM): (number, number, number)
	local p = e.Def.Params
	local scale = WaveData.DamageScale(run.Time)

	if p.EnrageAt and not e.Enraged and e.HP < e.MaxHP * p.EnrageAt then
		e.Enraged = true
		e.Speed *= 1.3
		run:Banner(p.Title .. " IS ENRAGED", "It's getting serious", "Boss")
		run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2, 0, Bosses.FX_ENRAGE)
	end
	local rate = if e.Enraged then 1.45 else 1

	-- second slam of the 67 King
	if e.SecondSlamAt and run.Time >= e.SecondSlamAt then
		e.SecondSlamAt = nil
		telegraph(run, e, 1, run.PX, run.PZ, 0, p.SlamRadius * 1.15, 0, p.SlamDelay, p.SlamDamage * scale)
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

	-- dash
	if e.DashAt and run.Time >= e.DashAt then
		e.DashAt = nil
		e.Dashing = true
		e.DashLeft = p.DashLength
		run:Write("EState", e.Id, 2)
	end
	if e.Dashing then
		local step = p.DashSpeed * dt
		e.DashLeft -= step
		if e.DashLeft <= 0 then
			e.Dashing = false
			run:Write("EState", e.Id, 0)
		end
		return e.DirX, e.DirZ, p.DashSpeed / e.Speed
	end

	if e.Busy > 0 then
		e.Busy -= dt
		if e.Busy <= 0 then
			run:Write("EState", e.Id, 0)
		end
		return 0, 0, 0
	end

	-- next attack (one per step)
	for _, pattern in p.Patterns do
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

function Bosses.StepTelegraphs(run, _EM)
	local list = run.Telegraphs
	local i = 1
	while i <= #list do
		local t = list[i]
		if run.Time >= t.At then
			if t.Shape == 1 and t.Damage > 0 then
				local dx, dz = run.PX - t.X, run.PZ - t.Z
				if dx * dx + dz * dz <= (t.R + PLAYER_R * 0.5) ^ 2 then
					run:HurtPlayer(t.Damage, true)
				end
				run:Write("Fx", 0, t.X, t.Z, 0, t.R, 0, Bosses.FX_SLAM)
			end
			list[i] = list[#list]
			list[#list] = nil
		else
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
	-- pending attacks of this boss are cancelled
	local list = run.Telegraphs
	for i = #list, 1, -1 do
		if list[i].Boss == e then
			table.remove(list, i)
		end
	end
	run:AddCoins(p.Coins or 0)
	Pickups.SpawnItem(run, "Chest", e.X, e.Z)
	run:Event("BossDefeated", { Id = e.Id, Key = e.Key, Title = p.Title, Final = p.Final == true })
	if p.Final then
		run.VictoryAt = run.Time + 3.5
		run:Banner("VICTORY", "THE FINAL GOOBER has been defeated", "Victory")
	else
		run:Banner(p.Title .. " DEFEATED", "Grab the chest!", "Reward")
	end
	-- a boss kill clears some pressure
	local n = 0
	for _, other in table.clone(run.Enemies) do
		local dx, dz = other.X - e.X, other.Z - e.Z
		if not other.IsBoss and dx * dx + dz * dz < 30 * 30 and n < 40 then
			n += 1
			EM.Damage(run, other, other.HP + 1, 0, dx, dz, 8)
		end
	end
	return min(n, 40)
end

return Bosses
