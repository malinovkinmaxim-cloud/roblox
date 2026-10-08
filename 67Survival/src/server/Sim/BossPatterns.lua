--[[
	BossPatterns - the attacks of the BESTIARY's main bosses (shared/EnemyData.lua Params,
	shared/BossData.lua phases). They plug into the pattern engine of Sim/Bosses.lua: each one
	is an entry of Bosses.Actions with its own <Pattern>Every timer, so they mix freely (THE 67
	borrows from the others).
	  MEGA SIX            BellyFlop (Sim/Bosses) SlimeFan Orbiters Swell
	  COUNT SEVEN         NightStep BatSwarm Slam (Sim/Bosses) BloodMoon
	  PHARAOH SIXSEVEN    Sandstorm Clap RaiseGolems TileVolley
	  EMPEROR PENGUIN     BellySlide SpikeGrid IceArena
	  DRAKO 67            FireBreath Meteors (Sim/Bosses) Takeoff Summon (Sim/Bosses)
	  OVERCLOCK-6         LaserSweep DigitalRain Hologram Overclock
	  THE 67              SixSmash SevenBeams BlackHoles EchoCall + Meteors, DoomRing
	Every attack shows its telegraph first (>= 1 s; NO MERCY shortens it, never below 0.75 s).
	Bosses.Step calls BossPatterns.Step every frame for the things that last: the BLOOD MOON,
	a belly slide's next leg.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local Protocol = require(Shared.Protocol)

local BossPatterns = {}

local sqrt, cos, sin, atan2, min, max = math.sqrt, math.cos, math.sin, math.atan2, math.min, math.max
local TAU = math.pi * 2
local ES = Protocol.EState
local GFX = Protocol.Fx
local SHAPE = Protocol.Shapes
local MIN_WINDUP = 0.75

local Bosses: any = nil -- installed by Sim/Bosses.lua (no require cycle)

local function windup(run, seconds: number): number
	return max(min(seconds, MIN_WINDUP), seconds * (run.Windup or 1))
end

local function state(run, e, s: number)
	if e.VState ~= s then
		e.VState = s
		run:Write("EState", e.Id, s)
	end
end

local function telegraph(...)
	return Bosses.Telegraph(...)
end

local function cue(run, e, text: string, time: number?)
	Bosses.Cue(run, e, text, time)
end

-- (x, z) pulled inside the boss's arena (margin studs from its edge)
local function inArena(e, x: number, z: number, margin: number?): (number, number)
	local cx, cz, r = Bosses.ArenaOf(e)
	local lim = r - (margin or 3)
	local dx, dz = x - cx, z - cz
	local d = sqrt(dx * dx + dz * dz)
	if d > lim then
		return cx + dx / d * lim, cz + dz / d * lim
	end
	return x, z
end

local function pointNear(run, e, x: number, z: number, rMin: number, rMax: number): (number, number)
	local a = run.Rng:NextNumber(0, TAU)
	local r = run.Rng:NextNumber(rMin, rMax)
	return inArena(e, x + cos(a) * r, z + sin(a) * r)
end

local function towards(run, e): number
	return atan2(run.PZ - e.Z, run.PX - e.X)
end

local A = {}

---------------------------------------------------------------------------- MEGA SIX
-- a fan of slime balls (it crouches and flashes first; the line shows the middle of the fan)
function A.SlimeFan(run, e, p, scale)
	local delay = windup(run, p.FanDelay)
	local a = towards(run, e)
	telegraph(run, e, SHAPE.DashLine, e.X, e.Z, a, 26, 8, delay, 0)
	e.Busy = delay
	state(run, e, ES.Windup)
	Bosses.After(run, e, delay, function(_, _, em)
		for i = 1, p.FanShots do
			local ang = a + (i - (p.FanShots + 1) / 2) * (p.FanSpread / (p.FanShots - 1))
			em.Shoot(run, e.X, e.Z, cos(ang) * p.FanSpeed, sin(ang) * p.FanSpeed, 1.6, p.FanDamage * scale, 3.2)
		end
	end)
end

-- three little slimes circle it: while any lives it takes OrbitCut less damage (Sim/Bestiary.Hurt);
-- OrbitBack seconds after the last one falls, three new ones come
function A.Orbiters(run, e, p, _scale, EM)
	local list = e.Orbiters
	if list then
		for _, o in list do
			if o.Alive then
				return -- still circling
			end
		end
		if not e.OrbitBackAt then
			e.OrbitBackAt = run.Time + p.OrbitBack
			return
		elseif run.Time < e.OrbitBackAt then
			return
		end
	end
	e.OrbitBackAt = nil
	list = {}
	local base = run.Rng:NextNumber(0, TAU)
	for i = 1, p.OrbitCount do
		local a = base + i * TAU / p.OrbitCount
		local o = Bosses.SpawnAdd(run, e, EM, p.OrbitKey, e.X + cos(a) * p.OrbitRadius, e.Z + sin(a) * p.OrbitRadius)
		if o then
			o.Owner = e
			o.Angle = a
			o.OrbitR = p.OrbitRadius
			o.Spin = p.OrbitSpin
			table.insert(list, o)
		end
	end
	e.Orbiters = list
	e.OrbitCut = p.OrbitCut
	e.Hurt = true
	cue(run, e, "KNOCK OUT THE ORBITING SLIMES", 3)
end

-- phase 2: it swells up and calls the Gloopies (once)
function A.Swell(run, e, p, _scale, EM)
	run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2, 0, GFX.Swell)
	for i = 1, p.SwellCount do
		local a = i * TAU / p.SwellCount
		local x, z = inArena(e, e.X + cos(a) * (e.Radius + 5), e.Z + sin(a) * (e.Radius + 5), 3)
		Bosses.SpawnAdd(run, e, EM, p.SwellKey, x, z, { FromSky = true })
	end
	cue(run, e, "SWELL!", 2)
end

---------------------------------------------------------------------------- COUNT SEVEN
-- fades into bats, steps out of the night BEHIND you, swings its cape in an arc
function A.NightStep(run, e, p, scale)
	-- behind = against the way you face
	local bx, bz = run.PX - run.FX * p.StepBehind, run.PZ - run.FZ * p.StepBehind
	local tx, tz = inArena(e, bx, bz, 4)
	local delay = windup(run, p.CapeDelay)
	local a = atan2(run.PZ - tz, run.PX - tx)
	run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 1.5, 0, GFX.Bats)
	e.TeleportAt = run.Time + p.StepFade
	e.TeleportX, e.TeleportZ = tx, tz
	telegraph(run, e, SHAPE.Sector, tx, tz, a, p.CapeRadius, p.CapeArc, delay, p.CapeDamage * scale, "Sector")
	e.Busy = delay
	e.PendingExpose = { Reason = "NightStep", At = run.Time + delay }
	state(run, e, ES.Windup)
end

-- a ring of bats around you
function A.BatSwarm(run, e, p, _scale, EM)
	local base = run.Rng:NextNumber(0, TAU)
	for i = 1, p.BatCount do
		local a = base + i * TAU / p.BatCount
		local x, z = inArena(e, run.PX + cos(a) * 20, run.PZ + sin(a) * 20, 2)
		Bosses.SpawnAdd(run, e, EM, p.BatKey, x, z)
	end
	run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2, 0, GFX.Bats)
	cue(run, e, "BATS!", 2)
end

-- phase 2: the BLOOD MOON rises (once): bats keep coming until you deal MoonShare of its HP
function A.BloodMoon(run, e, p)
	if e.Moon then
		return
	end
	e.Moon = { HP = e.HP - e.MaxHP * p.MoonShare, Next = run.Time + 1 }
	run:Event("Arena", { Tint = "Blood" })
	cue(run, e, "BLOOD MOON: HURT HIM TO MAKE IT SET", 4)
end

---------------------------------------------------------------------------- PHARAOH SIXSEVEN
-- three whirlwinds go round the arena for a while
function A.Sandstorm(run, e, p, _scale, EM)
	local cx, cz, r = Bosses.ArenaOf(e)
	local base = run.Rng:NextNumber(0, TAU)
	for i = 1, p.SpoutCount do
		local a = base + i * TAU / p.SpoutCount
		local rad = r * (0.3 + 0.18 * i)
		local s = Bosses.SpawnAdd(run, e, EM, p.SpoutKey, cx + cos(a) * rad, cz + sin(a) * rad)
		if s then
			s.CX, s.CZ = cx, cz
			s.Angle, s.OrbitR = a, rad
			s.Spin = (if i % 2 == 0 then -1 else 1) * 9 / rad
		end
	end
	cue(run, e, "SANDSTORM", 2)
end

-- the hands clap where you stand, then again where you went
function A.Clap(run, e, p, scale)
	local delay = windup(run, p.ClapDelay)
	telegraph(run, e, SHAPE.Circle, run.PX, run.PZ, 0, p.ClapRadius, 0, delay, p.ClapDamage * scale, "Slam")
	Bosses.After(run, e, p.ClapGap, function()
		telegraph(run, e, SHAPE.Circle, run.PX, run.PZ, 0, p.ClapRadius, 0, delay, p.ClapDamage * scale, "Slam")
	end)
	e.Busy = 0.6
	e.PendingExpose = { Reason = "Clap", At = run.Time + p.ClapGap + delay }
	state(run, e, ES.Windup)
end

-- three little Sand Golems rise from the sand (no elite attacks: they just walk)
function A.RaiseGolems(run, e, p, _scale, EM)
	for _ = 1, p.GolemCount do
		local x, z = pointNear(run, e, run.PX, run.PZ, 10, 15)
		run:Write("Fx", 0, x, z, 0, 3, 0, GFX.Hatch)
		Bosses.SpawnAdd(run, e, EM, p.GolemKey, x, z, { Behavior = "Chase" })
	end
end

-- phase 2: the tile ring fires its tiles at you, one after another
function A.TileVolley(run, e, p, scale)
	local lead = windup(run, 1.0)
	for i = 1, p.TileCount do
		local at = lead + (i - 1) * p.TileGap
		local a0 = i * TAU / p.TileCount
		Bosses.After(run, e, at, function(_, _, em)
			local x, z = e.X + cos(a0) * (e.Radius + 2), e.Z + sin(a0) * (e.Radius + 2)
			local a = atan2(run.PZ - z, run.PX - x)
			em.Shoot(run, x, z, cos(a) * p.TileSpeed, sin(a) * p.TileSpeed, 1.4, p.TileDamage * scale, 3)
		end)
	end
	telegraph(run, e, SHAPE.DashLine, e.X, e.Z, towards(run, e), 24, 4, lead, 0)
	cue(run, e, "THE TILES FLY", 2)
end

---------------------------------------------------------------------------- EMPEROR PENGUIN PRIME
-- the legs of a slide from (x, z) along angle a, bouncing off the arena's edge
local function slideLegs(e, x: number, z: number, a: number, bounces: number): { { X: number, Z: number, A: number, Len: number } }
	local cx, cz, r = Bosses.ArenaOf(e)
	r -= 3
	local legs = {}
	for _ = 0, bounces do
		local dx, dz = cos(a), sin(a)
		local ox, oz = x - cx, z - cz
		local b = ox * dx + oz * dz
		local c = ox * ox + oz * oz - r * r
		local t = -b + sqrt(max(0, b * b - c))
		t = max(8, t)
		table.insert(legs, { X = x, Z = z, A = a, Len = t })
		x, z = x + dx * t, z + dz * t
		-- reflect off the edge (the normal points to the centre)
		local nx, nz = (cx - x) / r, (cz - z) / r
		local dot = dx * nx + dz * nz
		a = atan2(dz - 2 * dot * nz, dx - 2 * dot * nx)
	end
	return legs
end

function A.BellySlide(run, e, p, scale)
	local w = windup(run, p.SlideWindup)
	local legs = slideLegs(e, e.X, e.Z, towards(run, e), p.SlideBounces)
	local t = w
	for _, leg in legs do
		telegraph(run, e, SHAPE.Laser, leg.X, leg.Z, leg.A, leg.Len, p.SlideWidth, t, p.SlideDamage * scale, "Sweep")
		t += leg.Len / p.SlideSpeed
	end
	-- the first leg starts the dash (Sim/Bosses.Step), the others follow (Legs)
	local first = table.remove(legs, 1)
	e.DirX, e.DirZ = cos(first.A), sin(first.A)
	e.DashAt = run.Time + w
	e.DashLen, e.DashSpd = first.Len, p.SlideSpeed
	e.DashDamage = p.SlideDamage * scale
	e.Legs = legs
	e.Busy = w
	e.PendingExpose = { Reason = "BellySlide", At = run.Time + t }
	state(run, e, ES.Windup)
	cue(run, e, "SLIDE!", 1.5)
end

-- ice spikes in a grid around you (always a way out)
function A.SpikeGrid(run, e, p, scale)
	local n, step = p.GridSize, p.GridStep
	local delay = windup(run, p.GridDelay)
	local half = (n - 1) / 2
	local rng = run.Rng
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local mid = i == half and j == half
			-- the cell you stand in always gets a spike; a checkerboard of gaps elsewhere
			if mid or ((i + j) % 2 == 0 and rng:NextNumber() < p.GridFill * 1.6) then
				local x, z = inArena(e, run.PX + (i - half) * step, run.PZ + (j - half) * step, 2)
				telegraph(run, e, SHAPE.Circle, x, z, 0, p.GridRadius, 0, delay + i * 0.08, p.GridDamage * scale, "Slam")
			end
		end
	end
	e.Busy = 0.6
	state(run, e, ES.Windup)
end

-- phase 2: the arena freezes in patches (you walk slower on them), Snowy Pals at the edge
function A.IceArena(run, e, p, _scale, EM)
	local cx, cz, r = Bosses.ArenaOf(e)
	for i = 1, p.IcePatches do
		local x, z
		if i == 1 then
			x, z = run.PX, run.PZ
		else
			x, z = pointNear(run, e, cx, cz, 4, r - 6)
		end
		telegraph(run, e, SHAPE.Puddle, x, z, 0, p.IceRadius, p.IceTime, windup(run, 1.0), 0, nil, p.IceSlow)
	end
	local base = run.Rng:NextNumber(0, TAU)
	for i = 1, p.IcePals do
		local a = base + i * TAU / p.IcePals
		Bosses.SpawnAdd(run, e, EM, p.IcePalKey, cx + cos(a) * (r - 4), cz + sin(a) * (r - 4))
	end
	run:Write("Fx", 0, cx, cz, 0, r, 0, GFX.Freeze)
	cue(run, e, "THE ARENA FREEZES", 3)
end

---------------------------------------------------------------------------- DRAKO 67
-- fire breath in a 90° cone towards you (the cone fills first, then burns a moment)
function A.FireBreath(run, e, p, scale)
	local delay = windup(run, p.BreathDelay)
	local a = towards(run, e)
	telegraph(run, e, SHAPE.Sector, e.X, e.Z, a, p.BreathRadius, p.BreathHalf, delay, p.BreathDamage * scale, "Sector", nil, { Burn = Protocol.SectorBurn })
	Bosses.After(run, e, delay, function()
		run:Write("Fx", 0, e.X, e.Z, a, p.BreathRadius, p.BreathHalf, GFX.Breath)
	end)
	e.Busy = delay
	state(run, e, ES.Windup)
end

-- takes off and lands on you: a circle, then a ring of embers with a gap
function A.Takeoff(run, e, p, scale)
	local time = windup(run, p.TakeoffTime)
	local tx, tz = inArena(e, run.PX, run.PZ, 5)
	telegraph(run, e, SHAPE.Circle, tx, tz, 0, p.LandRadius, 0, time, p.LandDamage * scale, "Land")
	e.LeapFromX, e.LeapFromZ = e.X, e.Z
	e.LeapToX, e.LeapToZ = tx, tz
	e.LeapT, e.LeapDur = 0, time
	e.Air = true
	e.Busy = time
	e.PendingExpose = { Reason = "Takeoff", At = run.Time + time }
	state(run, e, ES.Dash)
	Bosses.After(run, e, time, function(_, _, em)
		Bosses.GapRing(run, em, tx, tz, p.LandRing, 3, run.Rng:NextNumber(0, TAU), p.LandRingSpeed, p.LandRingDamage * scale, 1.3, 3)
	end)
	cue(run, e, "IT TAKES OFF!", 1.5)
end

---------------------------------------------------------------------------- OVERCLOCK-6
-- a laser that turns round the arena, one line after the other
function A.LaserSweep(run, e, p, scale)
	local delay = windup(run, p.LaserDelay)
	local dir = if run.Rng:NextNumber() < 0.5 then -1 else 1
	local base = towards(run, e) - dir * p.LaserStep
	for i = 0, p.LaserLines - 1 do
		telegraph(run, e, SHAPE.Laser, e.X, e.Z, base + dir * i * p.LaserStep, p.LaserLength, p.LaserWidth, delay + i * p.LaserGap, p.LaserDamage * scale, "Sweep")
	end
	local done = delay + (p.LaserLines - 1) * p.LaserGap
	e.Busy = done
	e.PendingExpose = { Reason = "LaserSweep", At = run.Time + done }
	state(run, e, ES.Windup)
end

-- digital rain: columns light up in a grid, then the pixels fall (column by column)
function A.DigitalRain(run, e, p, scale)
	local delay = windup(run, p.RainDelay)
	local rng = run.Rng
	local hx, hz = (p.RainCols - 1) / 2, (p.RainRows - 1) / 2
	local skip = rng:NextInteger(0, p.RainRows - 1) -- one row stays dry: the way through
	for i = 0, p.RainCols - 1 do
		for j = 0, p.RainRows - 1 do
			if j ~= skip then
				local x, z = inArena(e, run.PX + (i - hx) * p.RainStep, run.PZ + (j - hz) * p.RainStep, 2)
				telegraph(run, e, SHAPE.Circle, x, z, 0, p.RainRadius, 0, delay + i * 0.25, p.RainDamage * scale, "Slam")
			end
		end
	end
end

-- it splits: two holograms with red cores, the real one (green core) somewhere else
function A.Hologram(run, e, p, _scale, EM)
	local cx, cz, r = Bosses.ArenaOf(e)
	local base = run.Rng:NextNumber(0, TAU)
	local spots = {}
	for i = 1, p.HoloCount + 1 do
		local a = base + i * TAU / (p.HoloCount + 1)
		table.insert(spots, { cx + cos(a) * r * 0.55, cz + sin(a) * r * 0.55 })
	end
	local real = run.Rng:NextInteger(1, #spots)
	run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2, 0, GFX.Holo)
	for i, spot in spots do
		if i == real then
			e.TeleportAt = run.Time + 0.3
			e.TeleportX, e.TeleportZ = spot[1], spot[2]
		else
			Bosses.SpawnAdd(run, e, EM, p.HoloKey, spot[1], spot[2])
			run:Write("Fx", 0, spot[1], spot[2], 0, 6, 0, GFX.Holo)
		end
	end
	e.Busy = 0.8
	cue(run, e, "FIND THE GREEN CORE", 3)
end

-- phase 2: OVERCLOCK (once): it attacks OverclockRate times faster, the screen goes red
function A.Overclock(run, e, p)
	if e.Overclocked then
		return
	end
	e.Overclocked = true
	e.Rate = (e.Rate or 1) * p.OverclockRate
	run:Event("Arena", { Tint = "Overclock" })
	run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2, 0, GFX.Rage)
	cue(run, e, "OVERCLOCK: +40% ATTACK SPEED", 3)
end

---------------------------------------------------------------------------- THE 67
-- the 6 smashes down where you stand: a circle, then a ring of drops with a gap
function A.SixSmash(run, e, p, scale)
	local delay = windup(run, p.SmashDelay)
	local tx, tz = inArena(e, run.PX, run.PZ, 4)
	telegraph(run, e, SHAPE.Circle, tx, tz, 0, p.SmashRadius, 0, delay, p.SmashDamage * scale, "Slam")
	Bosses.After(run, e, delay, function(_, _, em)
		Bosses.GapRing(run, em, tx, tz, p.SmashDrops, 3, run.Rng:NextNumber(0, TAU), p.SmashDropSpeed, p.SmashDropDamage * scale, 1.3, 3)
	end)
	e.Busy = delay * 0.7
	e.PendingExpose = { Reason = "SixSmash", At = run.Time + delay }
	state(run, e, ES.Windup)
end

-- the 7 fires beams at you, one after the other, fanning out
function A.SevenBeams(run, e, p, scale)
	local delay = windup(run, p.BeamDelay)
	local a = towards(run, e)
	for i = 1, p.BeamCount do
		local off = (i - (p.BeamCount + 1) / 2) * 0.35
		telegraph(run, e, SHAPE.Laser, e.X, e.Z, a + off, p.BeamLength, p.BeamWidth, delay + (i - 1) * p.BeamGap, p.BeamDamage * scale, "Sweep")
	end
end

-- black holes at the edge: walking away from them is slower; their middle hurts
function A.BlackHoles(run, e, p, scale)
	local cx, cz, r = Bosses.ArenaOf(e)
	local base = run.Rng:NextNumber(0, TAU)
	for i = 1, p.HoleCount do
		local a = base + i * TAU / p.HoleCount
		local x, z = cx + cos(a) * (r - 6), cz + sin(a) * (r - 6)
		run:AddWell(x, z, p.HoleRadius, p.HoleSlow, p.HoleTime)
		telegraph(run, e, SHAPE.Void, x, z, 0, 4, p.HoleTime, windup(run, 1.0), 8 * scale, "Hazard")
		run:Write("Fx", 0, x, z, 0, p.HoleRadius, p.HoleTime, GFX.BlackHole)
	end
	cue(run, e, "BLACK HOLES: DON'T GET PULLED IN", 3)
end

-- phase 2: the echoes of the earlier bosses, one at a time
function A.EchoCall(run, e, p, _scale, EM)
	local keys = p.EchoKeys
	e.EchoNext = (e.EchoNext or 0) % #keys + 1
	local x, z = pointNear(run, e, e.X, e.Z, 10, 16)
	local echo = Bosses.SpawnAdd(run, e, EM, keys[e.EchoNext], x, z)
	run:Write("Fx", 0, x, z, 0, 6, 0, GFX.EchoIn)
	if echo then
		cue(run, e, string.upper(echo.Def.Name), 2.5)
	end
end

---------------------------------------------------------------------------- every frame
-- the parts of the fights that last (called by Sim/Bosses.Step for every boss)
function BossPatterns.Step(run, e, _dt: number, EM)
	local p = e.Def.Params
	-- COUNT SEVEN's BLOOD MOON: bats until enough damage, then it sets
	local moon = e.Moon
	if moon and not moon.Done then
		if e.HP <= moon.HP then
			moon.Done = true
			run:Event("Arena", { Tint = false })
			cue(run, e, "THE MOON SETS", 2.5)
			e.PendingExpose = { Reason = "NightStep", At = run.Time } -- (its weak point opens)
		elseif run.Time >= moon.Next then
			moon.Next = run.Time + p.MoonBatEvery / (e.Rate or 1)
			for i = 1, p.MoonBats do
				local a = i * TAU / p.MoonBats + run.Rng:NextNumber(0, 1)
				local x, z = inArena(e, run.PX + cos(a) * 18, run.PZ + sin(a) * 18, 2)
				Bosses.SpawnAdd(run, e, EM, p.BatKey, x, z)
			end
		end
	end
end

-- a slide's next leg (Sim/Bosses.Step, when a dash ends): true if it goes on
function BossPatterns.NextLeg(e): boolean
	local legs = e.Legs
	if not legs or #legs == 0 then
		e.Legs = nil
		return false
	end
	local leg = table.remove(legs, 1)
	e.X, e.Z = leg.X, leg.Z
	e.DirX, e.DirZ = cos(leg.A), sin(leg.A)
	e.DashLeft = leg.Len
	return true
end

function BossPatterns.Install(bosses)
	Bosses = bosses
	for name, fn in A do
		assert(bosses.Actions[name] == nil, "boss pattern defined twice: " .. name)
		bosses.Actions[name] = fn
	end
end

BossPatterns.Actions = A

return BossPatterns
