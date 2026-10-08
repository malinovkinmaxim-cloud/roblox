--[[
	Bestiary - the AI of the BESTIARY's horde, elites and boss minions (shared/EnemyData.lua,
	Role Regular / Elite / Minion; their main bosses: Sim/BossPatterns.lua).

	Every behaviour returns the wanted move direction (unit or zero) and a speed multiplier, like
	the classic ones in Sim/EnemyManager.lua, which installs these (Bestiary.Install).
	  Hop       Gloopy: bursts of speed on a beat (it hops)
	  Zigzag    Buzz Bat: weaves sideways, flashes, darts along a line
	  Jumper    King Gloop: jumps onto you (red circle), lands with a shockwave
	  Orbit     Mini Gloop: circles its boss (MEGA SIX takes less damage while one lives)
	  Shy       Boo Sheet: slower when you face it, faster behind your back; floats through walls
	  Bonk      Bonk Skull: stops, opens its jaw (a line), bonks straight ahead, bounces off walls
	  Knight    Pumpkin Knight: a front shield (flank it), a fan of three sparks
	  Stinger   Scorp: keeps its distance, flashes its tail, a slow stinger
	  Golem     Sand Golem: an 8-stud fist slam, cracked ground after it
	  Roam      Sand Spout: a whirlwind on a circle round the arena
	  Lobber    Snowy Pal: snowballs from afar, a roll up close
	  Wisp      Frost Wisp: an ice trail that slows you, an ice ring when it breaks
	  Yeti      Yeti Chonk: crouch, charge, a line of ice spikes ahead
	  Imp       Imp Pop: one fireball at a time; pops when it dies (a circle)
	  Crab      Obsidian Crab: walks sideways; its shell cuts damage until it cracks; a pinch
	  Glitchy   Pixel Bit: jumps 5 studs sideways every 2 s
	  Firewall  Firewall Bot: a front holo shield that breaks, calls Pixel Bits
	  Holo      OVERCLOCK-6's hologram: one hit pops it, it fires rings
	  Voidling  Voidling: pulls at you (walking away from it is slower)
	  Moons     Star Eater: throws its moons; each one flies back 3 s later
	  Eclipse   Eclipse Knight: a dark circle (slower inside), a spear lunge
	  EchoBoss  THE 67's echoes of the earlier bosses: one signature move each
	(Magma Bun walks with the classic Cinder behaviour, Drone Pod with Sniper, Wrappy with Chase.)

	Every attack is telegraphed: a flash (Windup state) plus a circle / line / cone on the ground,
	>= 0.7 s for the horde and >= 0.8 s for elites (NO MERCY shortens it like every wind-up).
	Elites attack Rate times faster below their Phases (Sim/Elites).
	Hooks EnemyManager calls: Init (spawn), Hurt (a hit lands: shields, shells, orbiters may cut
	it) and Died (death effects: bandages, ice rings, pops, a flung split).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local Protocol = require(Shared.Protocol)

local Bestiary = {}

local sqrt, cos, sin, atan2, min, max, abs = math.sqrt, math.cos, math.sin, math.atan2, math.min, math.max, math.abs
local TAU = math.pi * 2
local ES = Protocol.EState
local GFX = Protocol.Fx
local SHAPE = Protocol.Shapes
local PLAYER_R = GameConfig.Player.Radius
local HALF = GameConfig.Arena.HalfSize

-- installed by EnemyManager (it requires this module: no cycle)
local EM: any = nil
local Bosses: any = nil


local function windup(run, seconds: number): number
	return seconds * (run.Windup or 1)
end

local function setState(run, e, s: number)
	if e.VState ~= s then
		e.VState = s
		run:Write("EState", e.Id, s)
	end
end

local function chase(e, dx: number, dz: number, d: number): (number, number, number)
	if d < (e.Radius + PLAYER_R) * 0.85 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 1
end

-- closer than keep -> back off, further -> come closer, else circle round you
local function keepAway(e, dx: number, dz: number, d: number, keep: number): (number, number, number)
	if d > keep + 4 then
		return dx / d, dz / d, 1
	elseif d < keep - 4 then
		return -dx / d, -dz / d, 0.8
	end
	return -dz / d * e.Side, dx / d * e.Side, 0.6
end

-- a shield bearer turns to face you, but only so fast (`rate` rad/s): you can go round it
local function turnFace(e, dx: number, dz: number, rate: number, dt: number)
	local want = atan2(dz, dx)
	local cur = e.FaceA or want
	local diff = ((want - cur + math.pi) % TAU) - math.pi
	cur += math.clamp(diff, -rate * dt, rate * dt)
	e.FaceA = cur
	e.FaceX, e.FaceZ = cos(cur), sin(cur)
end

-- the attack timer of e (elites below a phase count down faster)
local function tick(e, dt: number): number
	e.T -= dt * (e.Rate or 1)
	return e.T
end

local function telegraph(run, e, shape: number, x: number, z: number, angle: number, size: number, width: number, delay: number, damage: number, kind: string?, slow: number?)
	Bosses.Telegraph(run, e, shape, x, z, angle, size, width, delay, damage, kind, slow)
end

-- a fan of n shots towards angle a, `spread` radians between neighbours
local function fan(run, e, a: number, n: number, spread: number, speed: number, damage: number, radius: number, life: number)
	for i = 1, n do
		local ang = a + (i - (n + 1) / 2) * spread
		EM.Shoot(run, e.X, e.Z, cos(ang) * speed, sin(ang) * speed, radius, damage, life)
	end
end

-- a timed step for the horde (the run's queue: Sim/EnemyManager.Step runs it)
local function later(run, delay: number, fn: () -> ())
	table.insert(run.Echoes, { At = run.Time + delay, Fn = fn })
end

-- a dash with a line on the ground: windup -> dash -> rest. Returns the move if busy.
-- p: Windup, DashTime, DashSpeed, Rest (+ the line length)
local function startDash(run, e, dx: number, dz: number, d: number, seconds: number, length: number)
	e.State = 1
	e.T = windup(run, seconds)
	e.DirX, e.DirZ = dx / d, dz / d
	run:Write("Telegraph", SHAPE.DashLine, e.X, e.Z, atan2(e.DirZ, e.DirX), length, e.Radius * 2, e.T)
	setState(run, e, ES.Windup)
end

local function stepDash(run, e, dt: number, dashTime: number, dashSpeed: number, rest: number): (number?, number?, number?)
	if e.State == 1 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 2
			e.T = dashTime
			setState(run, e, ES.Dash)
			EM.EchoLine(run, e, dashSpeed * dashTime)
		end
		return 0, 0, 0
	elseif e.State == 2 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 3
			e.T = rest
			setState(run, e, ES.Normal)
			if e.OnDashEnd then
				e.OnDashEnd(run, e)
			end
		end
		return e.DirX, e.DirZ, dashSpeed / max(0.1, e.Speed)
	elseif e.State == 3 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 0
			e.T = e.Def.Params.Every or 4
		end
		return nil, nil, 0.5 -- (rest: walk on slowly)
	end
	return nil, nil, nil
end

local B = {}

---------------------------------------------------------------------------- I CALM · Meadow
function B.Hop(_run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.HopT = (e.HopT + dt) % p.HopEvery
	local x, z, m = chase(e, dx, dz, d)
	return x, z, m * (if e.HopT < p.HopTime then p.HopBoost else p.Rest)
end

function B.Zigzag(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	local x, z, m = stepDash(run, e, dt, p.DashTime, p.DashSpeed, p.Rest)
	if m then
		if x then
			return x, z, m
		end
	elseif tick(e, dt) <= 0 and d < p.Trigger then
		startDash(run, e, dx, dz, d, p.Windup, p.DashSpeed * p.DashTime)
		return 0, 0, 0
	end
	-- weave: steer to the side and back on a sine
	e.WeaveT += dt
	local w = sin(e.WeaveT * p.WeaveSpeed) * p.Weave
	local c, s = cos(w), sin(w)
	local ux, uz = dx / d, dz / d
	return ux * c - uz * s, ux * s + uz * c, m or 1
end

-- King Gloop (and the echo of MEGA SIX): crouch, jump onto your spot, land with a shockwave
local function jumper(run, e, p, dx: number, dz: number, d: number, dt: number): (number, number, number)
	if e.State == 1 then
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
			setState(run, e, ES.Normal)
			return 0, 0, 0
		end
		return e.DirX, e.DirZ, e.JumpSpeed / max(0.1, e.Speed)
	elseif e.State == 3 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 0
			e.T = p.Every
		end
		return 0, 0, 0
	end
	if tick(e, dt) <= 0 and d < p.Trigger then
		e.State = 1
		e.T = windup(run, p.Windup)
		e.TX, e.TZ = e.X + dx, e.Z + dz
		-- the circle covers the wind-up and the flight; the hit lands with it
		telegraph(run, e, SHAPE.Circle, e.TX, e.TZ, 0, p.JumpRadius, 0, e.T + p.JumpTime, p.JumpDamage * e.DmgScale, "Land")
		setState(run, e, ES.Windup)
		return 0, 0, 0
	end
	return chase(e, dx, dz, d)
end

function B.Jumper(run, e, dx, dz, d, dt)
	return jumper(run, e, e.Def.Params, dx, dz, d, dt)
end

function B.Orbit(run, e, _dx, _dz, _d, dt)
	local o = e.Owner
	if not (o and o.Alive) then
		e.Life = run.Time -- its boss is gone: it pops
		return 0, 0, 0
	end
	e.Angle += e.Spin * dt
	e.X = o.X + cos(e.Angle) * e.OrbitR
	e.Z = o.Z + sin(e.Angle) * e.OrbitR
	return 0, 0, 0
end

---------------------------------------------------------------------------- II HUNT · Graveyard
function B.Shy(run, e, dx, dz, d)
	local p = e.Def.Params
	local x, z, m = chase(e, dx, dz, d)
	-- the angle between where you face and where it is
	local dot = math.clamp(run.FX * (-dx / d) + run.FZ * (-dz / d), -1, 1)
	local angle = math.acos(dot)
	if angle < p.SeenArc then
		m *= p.Seen
	elseif angle > p.BehindArc then
		m *= p.Behind
	end
	return x, z, m
end

-- would a step from (x, z) along (dx, dz) hit a wall or the edge? (which axis)
local function blocked(run, x: number, z: number, r: number): boolean
	return abs(x) > HALF - r or abs(z) > HALF - r or EM.InsideCollider(run, x, z, r)
end

function B.Bonk(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if e.State == 1 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 2
			e.Left = p.DashLength
			e.Bounces = p.Bounces
			setState(run, e, ES.Dash)
			EM.EchoLine(run, e, p.DashLength)
		end
		return 0, 0, 0
	elseif e.State == 2 then
		local step = p.DashSpeed * dt
		e.Left -= step
		-- a wall ahead: bounce (once or twice), else stop
		local ahead = e.Radius + step + 0.3
		local nx, nz = e.X + e.DirX * ahead, e.Z + e.DirZ * ahead
		if blocked(run, nx, nz, e.Radius * 0.5) then
			if e.Bounces > 0 then
				e.Bounces -= 1
				if blocked(run, nx, e.Z, e.Radius * 0.5) then
					e.DirX = -e.DirX
				end
				if blocked(run, e.X, nz, e.Radius * 0.5) then
					e.DirZ = -e.DirZ
				end
				run:Write("Fx", 0, e.X, e.Z, 0, 3, 0, GFX.Block)
			else
				e.Left = 0
			end
		end
		if e.Left <= 0 then
			e.State = 3
			e.T = p.Rest
			setState(run, e, ES.Normal)
			return 0, 0, 0
		end
		return e.DirX, e.DirZ, p.DashSpeed / max(0.1, e.Speed)
	elseif e.State == 3 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 0
			e.T = p.Every
		end
		return 0, 0, 0
	end
	if tick(e, dt) <= 0 and d < p.Trigger then
		startDash(run, e, dx, dz, d, p.Windup, p.DashLength)
		return 0, 0, 0
	end
	return chase(e, dx, dz, d)
end

function B.Knight(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	turnFace(e, dx, dz, p.Turn, dt)
	if e.State == 1 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 0
			e.T = p.Every
			setState(run, e, ES.Normal)
			fan(run, e, atan2(dz, dx), p.FanShots, p.FanSpread, p.ProjSpeed, p.ProjDamage * e.DmgScale, p.ProjRadius, p.ProjLife)
		end
		return 0, 0, 0
	end
	if tick(e, dt) <= 0 and d < 30 then
		e.State = 1
		e.T = windup(run, p.Windup)
		run:Write("Telegraph", SHAPE.DashLine, e.X, e.Z, atan2(dz, dx), p.ProjSpeed * p.ProjLife * 0.6, 3, e.T)
		setState(run, e, ES.Windup)
		return 0, 0, 0
	end
	return chase(e, dx, dz, d)
end

---------------------------------------------------------------------------- III HORDE · Desert
function B.Stinger(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if e.State == 1 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 0
			e.T = p.Every
			setState(run, e, ES.Normal)
			local a = atan2(run.PZ - e.Z, run.PX - e.X)
			EM.Shoot(run, e.X, e.Z, cos(a) * p.ProjSpeed, sin(a) * p.ProjSpeed, p.ProjRadius, p.ProjDamage * e.DmgScale, p.ProjLife)
		end
		return 0, 0, 0
	end
	if tick(e, dt) <= 0 and d < p.Keep + 14 then
		e.State = 1
		e.T = windup(run, p.Windup)
		setState(run, e, ES.Windup)
		return 0, 0, 0
	end
	return keepAway(e, dx, dz, d, p.Keep)
end

function B.Golem(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if e.State == 1 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 0
			e.T = p.Every
			setState(run, e, ES.Normal)
		end
		return 0, 0, 0
	end
	if tick(e, dt) <= 0 and d < p.Trigger then
		e.State = 1
		local delay = windup(run, p.Windup)
		e.T = delay + 0.3
		local x, z = run.PX, run.PZ
		telegraph(run, e, SHAPE.Circle, x, z, 0, p.SlamRadius, 0, delay, p.SlamDamage * e.DmgScale, "Slam")
		local crack = p.Crack
		local scale = e.DmgScale
		later(run, delay, function()
			-- the ground stays cracked for a moment
			for i = 1, crack.Count do
				local a = i * TAU / crack.Count + 0.4
				local r = p.SlamRadius * 0.45
				Bosses.Telegraph(run, nil, SHAPE.Spill, x + cos(a) * r, z + sin(a) * r, 0, crack.Radius, crack.Time, 0.05, crack.Damage * scale)
			end
		end)
		setState(run, e, ES.Windup)
		return 0, 0, 0
	end
	return chase(e, dx, dz, d)
end

-- a whirlwind: round and round a centre (its boss's arena), then it blows out
function B.Roam(_run, e, _dx, _dz, _d, dt)
	e.Angle += e.Spin * dt
	local tx = e.CX + cos(e.Angle) * e.OrbitR - e.X
	local tz = e.CZ + sin(e.Angle) * e.OrbitR - e.Z
	local m = sqrt(tx * tx + tz * tz)
	if m < 0.05 then
		return 0, 0, 0
	end
	return tx / m, tz / m, min(1.6, m / 2)
end

---------------------------------------------------------------------------- IV NIGHTMARE · Frostbite
function B.Lobber(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if e.Rolling then
		local x, z, m = stepDash(run, e, dt, p.RollTime, p.RollSpeed, p.Rest)
		if e.State == 0 then
			e.Rolling = false
			e.T = p.Every
		end
		if m then
			if x then
				return x, z, m
			end
			return 0, 0, 0
		end
	end
	if e.State == 4 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 0
			e.T = p.Every
			setState(run, e, ES.Normal)
			local a = atan2(run.PZ - e.Z, run.PX - e.X)
			EM.Shoot(run, e.X, e.Z, cos(a) * p.ProjSpeed, sin(a) * p.ProjSpeed, p.ProjRadius, p.ProjDamage * e.DmgScale, p.ProjLife)
		end
		return 0, 0, 0
	end
	-- up close: it rolls into you
	local t = tick(e, dt)
	if d < p.RollTrigger + e.Radius and t <= p.Every * 0.5 then
		e.Rolling = true
		startDash(run, e, dx, dz, d, p.Windup, p.RollSpeed * p.RollTime)
		return 0, 0, 0
	end
	if t <= 0 and d < p.Keep + 10 then
		e.State = 4
		e.T = windup(run, p.Windup)
		setState(run, e, ES.Windup)
		return 0, 0, 0
	end
	return keepAway(e, dx, dz, d, p.Keep)
end

function B.Wisp(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	e.T -= dt
	if e.T <= 0 then
		e.T = p.TrailEvery
		-- an icy patch (the run caps how fast new ones come, like the fire trails)
		if run.Time >= (run.IceAt or 0) then
			run.IceAt = run.Time + 0.1
			Bosses.Telegraph(run, nil, SHAPE.Puddle, e.X, e.Z, 0, p.TrailRadius, p.TrailTime, 0.05, 0, nil, p.Slow)
		end
	end
	return chase(e, dx, dz, d)
end

function B.Yeti(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	local x, z, m = stepDash(run, e, dt, p.DashTime, p.DashSpeed, p.Rest)
	if m then
		if x then
			return x, z, m
		end
		return chase(e, dx, dz, d)
	end
	if tick(e, dt) <= 0 and d < p.Trigger then
		startDash(run, e, dx, dz, d, p.Windup, p.DashSpeed * p.DashTime)
		return 0, 0, 0
	end
	return chase(e, dx, dz, d)
end

-- the spikes after a Yeti's charge: a line straight ahead
local function yetiSpikes(run, e)
	local p = e.Def.Params
	telegraph(run, e, SHAPE.Laser, e.X, e.Z, atan2(e.DirZ, e.DirX), p.SpikeLength, p.SpikeWidth, windup(run, p.SpikeDelay), p.SpikeDamage * e.DmgScale, "Sweep")
end

---------------------------------------------------------------------------- V INFERNO · Volcano
function B.Imp(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if e.State == 1 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 0
			e.T = p.Every
			setState(run, e, ES.Normal)
			local a = atan2(run.PZ - e.Z, run.PX - e.X)
			EM.Shoot(run, e.X, e.Z, cos(a) * p.ProjSpeed, sin(a) * p.ProjSpeed, p.ProjRadius, p.ProjDamage * e.DmgScale, p.ProjLife)
		end
		return 0, 0, 0
	end
	if tick(e, dt) <= 0 and d < p.Keep + 16 then
		e.State = 1
		e.T = windup(run, p.Windup)
		setState(run, e, ES.Windup)
		return 0, 0, 0
	end
	return keepAway(e, dx, dz, d, p.Keep)
end

function B.Crab(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	local now = run.Time
	-- the shell grows back
	if e.ShellBackAt and now >= e.ShellBackAt then
		e.ShellBackAt = nil
		e.Shell = p.ShellHits
		if e.State == 0 then
			setState(run, e, ES.Normal)
		end
	end
	if e.State == 1 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 0
			e.T = p.Every
			setState(run, e, if e.ShellBackAt then ES.Broken else ES.Normal)
		end
		return 0, 0, 0
	end
	if tick(e, dt) <= 0 and d < p.Trigger + e.Radius then
		e.State = 1
		e.T = windup(run, p.Windup) + 0.2
		local ux, uz = dx / d, dz / d
		telegraph(run, e, SHAPE.Circle, e.X + ux * e.Radius, e.Z + uz * e.Radius, 0, p.PinchRadius, 0, windup(run, p.Windup), p.PinchDamage * e.DmgScale, "Slam")
		setState(run, e, ES.Windup)
		return 0, 0, 0
	end
	-- sideways: half towards you, half round you
	local ux, uz = dx / d, dz / d
	local sx, sz = -uz * e.Side, ux * e.Side
	local mx, mz = ux * (1 - p.Side * 0.6) + sx * p.Side, uz * (1 - p.Side * 0.6) + sz * p.Side
	local m = sqrt(mx * mx + mz * mz)
	if d < e.Radius + PLAYER_R then
		return 0, 0, 0
	end
	return mx / m, mz / m, 1
end

---------------------------------------------------------------------------- VI OBLIVION · Cyber
function B.Glitchy(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if tick(e, dt) <= 0 then
		e.T = p.Every
		-- a random side step, never away from you
		local base = atan2(dz, dx)
		for _ = 1, 4 do
			local a = base + run.Rng:NextNumber(-1.8, 1.8)
			local x, z = e.X + cos(a) * p.Jump, e.Z + sin(a) * p.Jump
			if not blocked(run, x, z, e.Radius) then
				run:Write("Fx", 0, e.X, e.Z, a, p.Jump, 0, GFX.Phantom)
				e.X, e.Z = x, z
				e.SentX, e.SentZ = x, z
				run:Write("Blink", e.Id, x, z)
				return 0, 0, 0
			end
		end
	end
	return chase(e, dx, dz, d)
end

function B.Firewall(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	turnFace(e, dx, dz, p.Turn, dt)
	if tick(e, dt) <= 0 then
		e.T = p.Every
		run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2, 0, GFX.Rally)
		for i = 1, p.SummonCount do
			local a = i * TAU / p.SummonCount
			local add = EM.Spawn(run, p.SummonKey, e.X + cos(a) * (e.Radius + 2.5), e.Z + sin(a) * (e.Radius + 2.5))
			if add and e.ArenaAdd then
				add.ArenaAdd = true
			end
		end
	end
	local x, z, m = chase(e, dx, dz, d)
	return x, z, m * 0.85
end

function B.Holo(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if tick(e, dt) <= 0 then
		e.T = p.Every
		local off = run.Rng:NextNumber(0, TAU)
		for i = 1, p.Count do
			local a = off + i * TAU / p.Count
			EM.Shoot(run, e.X, e.Z, cos(a) * p.ProjSpeed, sin(a) * p.ProjSpeed, 1.2, p.ProjDamage * e.DmgScale, 3)
		end
	end
	local x, z, m = chase(e, dx, dz, d)
	return x, z, m * 0.5
end

---------------------------------------------------------------------------- VII THE 67 · Void
function B.Voidling(run, e, dx, dz, d, _dt)
	local p = e.Def.Params
	local w = e.Well
	if w and w.Until > run.Time then
		w.X, w.Z, w.Until = e.X, e.Z, run.Time + 0.3
	elseif d < p.PullRadius + 6 then
		e.Well = run:AddWell(e.X, e.Z, p.PullRadius, p.PullSlow, 0.3)
	end
	return chase(e, dx, dz, d)
end

function B.Moons(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	if e.State == 1 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 0
			e.T = p.Every
			setState(run, e, ES.Normal)
			-- a moon flies at you ...
			local a = atan2(run.PZ - e.Z, run.PX - e.X)
			local vx, vz = cos(a) * p.ProjSpeed, sin(a) * p.ProjSpeed
			local damage = p.ProjDamage * e.DmgScale
			EM.Shoot(run, e.X, e.Z, vx, vz, p.ProjRadius, damage, p.ProjLife)
			e.MoonsOut += 1
			local fx, fz = e.X + vx * p.ProjLife, e.Z + vz * p.ProjLife
			-- ... and comes back to it later
			later(run, p.Return, function()
				e.MoonsOut = max(0, e.MoonsOut - 1)
				if e.Alive then
					local bx, bz = e.X - fx, e.Z - fz
					local bd = max(1, sqrt(bx * bx + bz * bz))
					EM.Shoot(run, fx, fz, bx / bd * p.ProjSpeed, bz / bd * p.ProjSpeed, p.ProjRadius, damage, bd / p.ProjSpeed)
				end
			end)
		end
		return 0, 0, 0
	end
	if tick(e, dt) <= 0 and e.MoonsOut < p.Moons and d < p.Keep + 14 then
		e.State = 1
		e.T = windup(run, p.Windup)
		setState(run, e, ES.Windup)
		return 0, 0, 0
	end
	return keepAway(e, dx, dz, d, p.Keep)
end

function B.Eclipse(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	-- the eclipse has its own timer
	e.EclipseT -= dt * (e.Rate or 1)
	if e.EclipseT <= 0 and e.State == 0 then
		e.EclipseT = p.EclipseEvery
		local delay = windup(run, p.EclipseDelay)
		run:Write("Telegraph", SHAPE.Circle, e.X, e.Z, 0, p.EclipseRadius, 0, delay)
		local x, z = e.X, e.Z
		later(run, delay, function()
			Bosses.Telegraph(run, nil, SHAPE.Puddle, x, z, 0, p.EclipseRadius, p.EclipseTime, 0.05, 0, nil, p.EclipseSlow)
			run:Write("Fx", 0, x, z, 0, p.EclipseRadius, 0, GFX.Gravity)
		end)
	end
	local x, z, m = stepDash(run, e, dt, p.DashTime, p.DashSpeed, p.Rest)
	if m then
		if x then
			return x, z, m
		end
		return chase(e, dx, dz, d)
	end
	if tick(e, dt) <= 0 and d < p.Trigger then
		startDash(run, e, dx, dz, d, p.Windup, p.DashSpeed * p.DashTime)
		return 0, 0, 0
	end
	return chase(e, dx, dz, d)
end

-- THE 67's echoes: one signature move of an earlier boss
function B.EchoBoss(run, e, dx, dz, d, dt)
	local p = e.Def.Params
	local kind = p.Echo
	if kind == "Jump" then
		local jp = e.JumpParams
		if not jp then
			jp = { Every = p.Every, Trigger = 40, Windup = p.Windup, JumpTime = 0.6, JumpRadius = p.AttackRadius, JumpDamage = p.AttackDamage, Rest = 0.6 }
			e.JumpParams = jp
		end
		return jumper(run, e, jp, dx, dz, d, dt)
	elseif kind == "Slide" then
		local x, z, m = stepDash(run, e, dt, p.DashTime, p.DashSpeed, 0.6)
		if m then
			if x then
				return x, z, m
			end
			return chase(e, dx, dz, d)
		end
	end
	if e.State == 0 and tick(e, dt) <= 0 then
		e.T = p.Every
		local a = atan2(dz, dx)
		local delay = windup(run, p.Windup or 1)
		local damage = (p.AttackDamage or 0) * e.DmgScale
		if kind == "Bats" then
			for i = 1, p.Count do
				local ang = i * TAU / p.Count
				local bat = EM.Spawn(run, p.Key, e.X + cos(ang) * 4, e.Z + sin(ang) * 4, { Force = true })
				if bat and e.ArenaAdd then
					bat.ArenaAdd = true
				end
			end
			run:Write("Fx", 0, e.X, e.Z, 0, 6, 0, GFX.Teleport)
		elseif kind == "Clap" then
			telegraph(run, e, SHAPE.Circle, run.PX, run.PZ, 0, p.AttackRadius, 0, delay, damage, "Slam")
		elseif kind == "Slide" then
			startDash(run, e, dx, dz, d, p.Windup, p.DashSpeed * p.DashTime)
			e.DashDamage = damage
			return 0, 0, 0
		elseif kind == "Breath" then
			telegraph(run, e, SHAPE.Sector, e.X, e.Z, a, p.AttackRadius, p.Half, delay, damage, "Sector")
		elseif kind == "Laser" then
			telegraph(run, e, SHAPE.Laser, e.X, e.Z, a, p.Length, p.Width, delay, damage, "Sweep")
		end
		if kind ~= "Bats" then
			e.State = 5
			e.T = delay
			setState(run, e, ES.Windup)
			return 0, 0, 0
		end
	elseif e.State == 5 then
		e.T -= dt
		if e.T <= 0 then
			e.State = 0
			e.T = p.Every
			setState(run, e, ES.Normal)
		end
		return 0, 0, 0
	end
	local x, z, m = keepAway(e, dx, dz, d, 9)
	return x, z, m
end

---------------------------------------------------------------------------- hooks
-- a new enemy of the bestiary: its timers and state
function Bestiary.Init(run, e)
	local p = e.Def.Params
	local b = e.Behavior
	local rng = run.Rng
	e.Phase0 = rng:NextNumber(0, TAU)
	if p.Ghost or p.Fly then
		e.Ghost = true -- floats over walls
	end
	if p.OneHit then
		e.HP, e.MaxHP = 1, 1 -- (a hologram: any hit pops it, whatever the difficulty)
	end
	if b == "Hop" then
		e.HopT = rng:NextNumber(0, p.HopEvery)
	elseif b == "Zigzag" then
		e.WeaveT = rng:NextNumber(0, 6)
		e.T = p.Every * rng:NextNumber(0.4, 1)
	elseif b == "Wisp" then
		e.T = p.TrailEvery
	elseif b == "Moons" then
		e.T = p.Every * rng:NextNumber(0.5, 1)
		e.MoonsOut = 0
	elseif b == "Eclipse" then
		e.T = p.Every * rng:NextNumber(0.5, 1)
		e.EclipseT = p.EclipseEvery * rng:NextNumber(0.4, 0.8)
	elseif b == "Crab" then
		e.T = p.Every
		e.Shell = p.ShellHits
	elseif b == "Knight" or b == "Firewall" or b == "Golem" or b == "Jumper" or b == "Bonk" or b == "Stinger" or b == "Lobber" or b == "Imp" or b == "Yeti" or b == "Glitchy" or b == "Holo" or b == "EchoBoss" then
		e.T = (p.Every or 4) * rng:NextNumber(0.4, 1)
	end
	if b == "Yeti" then
		e.OnDashEnd = yetiSpikes
	elseif b == "Roam" or b == "Orbit" then
		-- (its boss sets the circle; on its own it circles where it appeared)
		e.CX, e.CZ = e.X - 8, e.Z
		e.Angle, e.OrbitR, e.Spin = 0, 8, 1
	end
	-- what a hit or a death of it does (EnemyManager calls Hurt / Died)
	if p.BlockCut or p.ShellHits then
		e.Hurt = true
	end
	if p.Unwrap or p.BurstCount or p.PopRadius or p.SplitFling then
		e.Died = true
	end
end

-- a hit lands on e (after the SHIELDED elite's shield): returns the damage and knockback left
function Bestiary.Hurt(run, e, dmg: number, kx: number, kz: number, knock: number): (number, number)
	local p = e.Def.Params
	local now = run.Time
	-- a front shield (Pumpkin Knight): where the hit came from, against its knockback
	if p.BlockCut then
		local hx, hz = -kx, -kz
		if hx * hx + hz * hz < 1e-4 then
			hx, hz = run.PX - e.X, run.PZ - e.Z
		end
		local len = sqrt(hx * hx + hz * hz)
		if len > 1e-3 and ((e.FaceX or 0) * hx + (e.FaceZ or 0) * hz) / len >= cos(p.BlockArc) then
			dmg *= 1 - p.BlockCut
			knock *= 0.2
			if now >= (e.BlockFx or 0) then
				e.BlockFx = now + 0.4
				run:Write("Fx", 0, e.X + (e.FaceX or 0) * e.Radius, e.Z + (e.FaceZ or 0) * e.Radius, 0, e.Radius, 0, GFX.Block)
			end
		end
	end
	-- an obsidian shell: cuts every hit until it cracks open, then grows back
	if p.ShellHits and e.Shell and e.Shell > 0 then
		dmg *= 1 - p.ShellCut
		knock *= 0.3
		e.Shell -= 1
		if e.Shell == 0 then
			e.ShellBackAt = now + p.ShellBroken
			setState(run, e, ES.Broken)
			run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2, 0, GFX.ShieldBreak)
		elseif now >= (e.BlockFx or 0) then
			e.BlockFx = now + 0.3
			run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 1.3, 0, GFX.Block)
		end
	end
	-- a boss behind its orbiting slimes (MEGA SIX)
	local orbit = e.Orbiters
	if orbit then
		for _, o in orbit do
			if o.Alive then
				dmg *= 1 - (e.OrbitCut or 0)
				break
			end
		end
	end
	return dmg, knock
end

-- e just died: its parting gift
function Bestiary.Died(run, e)
	local p = e.Def.Params
	local x, z = e.X, e.Z
	if p.Unwrap then
		-- Wrappy: its bandages lie on the ground for a moment (you walk slower on them)
		local u = p.Unwrap
		local off = run.Rng:NextNumber(0, TAU)
		for i = 1, u.Count do
			local a = off + i * TAU / u.Count
			Bosses.Telegraph(run, nil, SHAPE.Puddle, x + cos(a) * u.Spread, z + sin(a) * u.Spread, 0, u.Radius, u.Time, 0.05, 0, nil, u.Slow)
		end
	end
	if p.BurstCount then
		-- Frost Wisp: an ice ring
		local off = run.Rng:NextNumber(0, TAU)
		for i = 1, p.BurstCount do
			local a = off + i * TAU / p.BurstCount
			EM.Shoot(run, x, z, cos(a) * p.BurstSpeed, sin(a) * p.BurstSpeed, 1.0, p.BurstDamage * e.DmgScale, p.BurstLife)
		end
		run:Write("Fx", 0, x, z, 0, 4, 0, GFX.Freeze)
	end
	if p.PopRadius then
		-- Imp Pop: a little explosion (its circle shows first)
		Bosses.Telegraph(run, nil, SHAPE.Circle, x, z, 0, p.PopRadius, 0, windup(run, p.PopDelay), p.PopDamage * e.DmgScale, "Slam")
	end
end

-- the gloopies a King Gloop pops into fly out in an arc
function Bestiary.Fling(e, child, a: number)
	local p = e.Def.Params
	if p.SplitFling and child then
		child.KX += cos(a) * p.SplitFling
		child.KZ += sin(a) * p.SplitFling
	end
end

function Bestiary.Install(behaviors, em, bosses)
	EM, Bosses = em, bosses
	for name, fn in B do
		assert(behaviors[name] == nil, "behaviour defined twice: " .. name)
		behaviors[name] = fn
	end
end

Bestiary.Behaviors = B

return Bestiary
