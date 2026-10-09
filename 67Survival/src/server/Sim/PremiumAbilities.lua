--[[
	PremiumAbilities - what the 7 PREMIUM (Mythic, Robux) abilities DO (shared/WeaponData.lua
	Premium = true; their looks: client Render/PremiumFx.lua; sale and trial:
	shared/AbilityConfig.lua). Sim/CombatManager installs these Kinds next to its own
	(PremiumAbilities.Install), so they share the cooldown, the hit pipeline (crits, burns,
	stuns, the build's procs) and the Fx records.

	  Solar       SOLAR BEAM 67: a pillar on the nearest enemy, 6 pulses that follow it, the 7th
	              is an area blast. Max level: two pillars (two targets) at once.
	  HolePet     BLACK HOLE PET: follows behind you, pulls the horde (not bosses) in and
	              crushes it (double damage in its core from level 5). Max level: it implodes
	              every few seconds. Its position is sent every PET_SYNC s (Fx variant 1).
	  GoldMeteor  GOLDEN METEOR SHOWER: meteors on enemies around you; a kill by one drops
	              +CoinBonus coins (Sim/EnemyManager Kill reads the killer's CoinBonus).
	  Bubble      TIME BUBBLE: a dome on you for Duration s: enemies inside are slowed by Slow
	              (bosses less: EnemyManager.Slow), your shots fly Haste x faster (run.Haste,
	              read by CombatManager fire()). Pure control, no damage. Max level: it ends
	              in a freeze.
	  Phoenix     PHOENIX FAMILIAR: flies round you (a fixed formula the client repeats) and
	              shoots fireballs; once per run it brings you back at ReviveHeal HP
	              (PremiumAbilities.TryRevive, called by Run:OnZeroHP before the normal revives).
	  Storm       CHAIN STORM: one bolt jumps through 12 enemies, each link Falloff x weaker.
	              Max level: every link bursts.
	  Crown       AURA CROWN: digits 6 and 7 on a turning ring hit what they touch (a fixed
	              formula the client repeats, like Orbit). Max level: three rings.
]]

local EnemyManager = require(script.Parent.EnemyManager)

local PremiumAbilities = {}

local sqrt, cos, sin, atan2, min, max, exp = math.sqrt, math.cos, math.sin, math.atan2, math.min, math.max, math.exp
local TAU = math.pi * 2

local PET_SYNC = 0.15 -- seconds between two position reports of the black hole pet
local PHOENIX_R, PHOENIX_SPIN = 3.2, 1.7 -- the phoenix's circle round you (client: Render/PremiumFx)
local CROWN_GAP = 3 -- studs between two rings of the crown

local CM: any = nil -- Sim/CombatManager (installed: no require cycle)

-- the cooldown with the dynamic fire rate (CombatManager's ready())
local function ready(run, w, dt: number): boolean
	w.Timer -= dt * run.FireRateNow
	return w.Timer <= 0
end

-- the phoenix's position at time t (the client draws it with the same formula)
function PremiumAbilities.PhoenixPos(run, t: number): (number, number)
	local a = t * PHOENIX_SPIN
	return run.PX + cos(a) * PHOENIX_R, run.PZ + sin(a) * PHOENIX_R
end

-- the crown's digit i of n on ring k at time t (the client draws it with the same formula)
function PremiumAbilities.CrownPos(run, s, k: number, i: number, n: number, t: number): (number, number)
	local dir = if k % 2 == 0 then -1 else 1
	local a = t * s.Speed * dir + (i - 1) * TAU / n + (k - 1) * 0.5
	local r = s.Orbit + (k - 1) * CROWN_GAP
	return run.PX + cos(a) * r, run.PZ + sin(a) * r
end

local KINDS = {}

---------------------------------------------------------------------------
-- SOLAR BEAM 67
---------------------------------------------------------------------------
local function solarStrike(run, w, seq)
	local s = w.S
	local n = seq.N
	for i, spot in seq.Spots do
		local t = spot.Target
		if not (t and t.Alive) then
			-- the pillar walks on to the nearest enemy close by
			t = CM.Nearest(run, spot.X, spot.Z, 10)
			spot.Target = t
		end
		if t then
			spot.X, spot.Z = t.X, t.Z
		end
		if n < 7 then
			run:Write("Fx", w.Id, spot.X, spot.Z, 0, s.Width, n, i)
			for _, e in CM.Gather(run, spot.X, spot.Z, s.Width) do
				CM.Hit(run, e, s.Damage, e.X - spot.X, e.Z - spot.Z, s.Knockback)
			end
		else
			run:Write("Fx", w.Id, spot.X, spot.Z, 0, s.Radius, 7, i)
			CM.Area(run, spot.X, spot.Z, s.Radius, s.Damage * s.BlastMult, s.Knockback * 4)
		end
	end
end

function KINDS.Solar(run, w, dt)
	local s = w.S
	local seq = w.Seq
	if seq then
		seq.T -= dt
		while seq and seq.T <= 0 do
			seq.N += 1
			solarStrike(run, w, seq)
			if seq.N >= 7 then
				w.Seq = nil
				seq = nil
			else
				seq.T += s.Pulse
			end
		end
		return
	end
	if not ready(run, w, dt) then
		return
	end
	local spots, skip = {}, {}
	for _ = 1, s.Pillars do
		local e = CM.Nearest(run, run.PX, run.PZ, s.Range, skip)
		if not e then
			break
		end
		skip[e.Uid] = true
		table.insert(spots, { Target = e, X = e.X, Z = e.Z })
	end
	if #spots == 0 then
		w.Timer = 0.25
		return
	end
	w.Timer = s.Cooldown
	w.Seq = { N = 0, T = 0, Spots = spots }
end

---------------------------------------------------------------------------
-- BLACK HOLE PET
---------------------------------------------------------------------------
function KINDS.HolePet(run, w, dt)
	local s = w.S
	-- it trails behind you (behind where you face), a little late
	local tx, tz = run.PX - run.FX * s.Follow, run.PZ - run.FZ * s.Follow
	if not w.PX then
		w.PX, w.PZ, w.Sync, w.Tick = tx, tz, 0, 0
	end
	local k = 1 - exp(-3 * dt)
	w.PX += (tx - w.PX) * k
	w.PZ += (tz - w.PZ) * k
	local x, z = w.PX, w.PZ
	w.Sync -= dt
	if w.Sync <= 0 then
		w.Sync = PET_SYNC
		run:Write("Fx", w.Id, x, z, 0, s.Radius, s.Core, 1)
	end
	-- the pull (bosses do not move)
	local list = CM.Gather(run, x, z, s.Radius)
	for _, e in list do
		if not e.IsBoss then
			local dx, dz = x - e.X, z - e.Z
			local d = sqrt(dx * dx + dz * dz)
			if d > 0.6 then
				local step = min(d - 0.5, s.Pull * dt)
				e.X += dx / d * step
				e.Z += dz / d * step
			end
		end
	end
	-- the crush
	w.Tick -= dt
	if w.Tick <= 0 then
		w.Tick = s.HitCooldown
		local core = s.Core * s.Core
		for _, e in list do
			local crushed = s.Crush and ((e.X - x) ^ 2 + (e.Z - z) ^ 2) <= core
			CM.Hit(run, e, s.Damage * (if crushed then 2 else 1), 0, 0, 0)
		end
	end
	-- max level: it implodes now and then
	if s.Collapse then
		w.CollapseT = (w.CollapseT or s.CollapseEvery) - dt
		if w.CollapseT <= 0 then
			w.CollapseT = s.CollapseEvery
			run:Write("Fx", w.Id, x, z, 0, s.Collapse, 0, 2)
			CM.Area(run, x, z, s.Collapse, s.Damage * 6, 6)
		end
	end
end

---------------------------------------------------------------------------
-- GOLDEN METEOR SHOWER
---------------------------------------------------------------------------
function KINDS.GoldMeteor(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local rng = run.Rng
	local near = CM.Gather(run, run.PX, run.PZ, s.Range)
	if #near == 0 then
		w.Timer = 0.3
		return
	end
	w.Timer = s.Cooldown
	for _ = 1, s.Amount do
		local x, z
		if #near > 0 then
			local i = rng:NextInteger(1, #near)
			local e = near[i]
			near[i] = near[#near]
			near[#near] = nil
			x, z = e.X, e.Z
		else
			-- more meteors than enemies: they rain around you anyway
			local a, d = rng:NextNumber(0, TAU), rng:NextNumber(4, s.Range)
			x, z = run.PX + cos(a) * d, run.PZ + sin(a) * d
		end
		table.insert(run.Pending, { At = run.Time + s.Duration, X = x, Z = z, R = s.Radius, Damage = s.Damage, Knock = s.Knockback, W = w, Split = s.Split })
		run:Write("Fx", w.Id, x, z, 0, s.Radius, s.Duration, 0)
	end
end

---------------------------------------------------------------------------
-- TIME BUBBLE
---------------------------------------------------------------------------
function KINDS.Bubble(run, w, dt)
	local s = w.S
	local now = run.Time
	if w.Until and now < w.Until then
		run.Haste = s.Haste -- read by CombatManager fire()
		w.SlowT = (w.SlowT or 0) - dt
		local list = CM.Gather(run, run.PX, run.PZ, s.Radius)
		local slow = w.SlowT <= 0
		if slow then
			w.SlowT = 0.2
		end
		local inside = {}
		for _, e in list do
			inside[e.Uid] = true
			if slow then
				EnemyManager.Slow(e, 1 - s.Slow, 0.35, now)
			end
			if s.Stop and not w.Inside[e.Uid] then
				EnemyManager.Stun(run, e, s.Stop)
			end
		end
		w.Inside = inside
		return
	end
	if w.Until then
		-- it just ended
		w.Until = nil
		run.Haste = nil
		if s.TimeStop then
			run:Write("Fx", w.Id, run.PX, run.PZ, 0, s.Radius, s.TimeStop, 2)
			for _, e in CM.Gather(run, run.PX, run.PZ, s.Radius) do
				EnemyManager.Stun(run, e, s.TimeStop, true)
			end
		end
	end
	if not ready(run, w, dt) then
		return
	end
	if not CM.Nearest(run, run.PX, run.PZ, s.Radius + 6) then
		w.Timer = 0.3
		return
	end
	-- it is always down for a while (a longer Duration never makes it permanent)
	w.Timer = max(s.Cooldown, s.Duration + 2.5)
	w.Until = now + s.Duration
	w.Inside = {}
	run:Write("Fx", w.Id, run.PX, run.PZ, 0, s.Radius, s.Duration, 0)
end

---------------------------------------------------------------------------
-- PHOENIX FAMILIAR
---------------------------------------------------------------------------
function KINDS.Phoenix(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local x, z = PremiumAbilities.PhoenixPos(run, run.Time)
	local target = CM.Nearest(run, x, z, s.Range)
	if not target then
		w.Timer = 0.2
		return
	end
	w.Timer = s.Cooldown
	local a = atan2(target.Z - z, target.X - x)
	local n = s.Amount
	for i = 1, n do
		CM.Fire(run, w, "Straight", a + (i - (n + 1) / 2) * 0.16, s.Speed, s.Duration, nil, x, z)
	end
end

-- Run:OnZeroHP: the phoenix brings you back once per run. Returns true when it did.
function PremiumAbilities.TryRevive(run): boolean
	for _, w in run.Weapons do
		if w.Def.Kind == "Phoenix" and not w.Spent then
			w.Spent = true
			run.PhoenixHeal = w.S.ReviveHeal or 0.4
			run:Write("Fx", w.Id, run.PX, run.PZ, 0, 12, 0, 2)
			run:Banner("PHOENIX REBIRTH", "Back at " .. math.floor(run.PhoenixHeal * 100 + 0.5) .. "% HP", "Evolution")
			run:Revive("Phoenix")
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- CHAIN STORM
---------------------------------------------------------------------------
function KINDS.Storm(run, w, dt)
	if not ready(run, w, dt) then
		return
	end
	local s = w.S
	local hit = {}
	local fired = 0
	for _ = 1, s.Amount do
		local prevX, prevZ = run.PX, run.PZ
		local dmg = s.Damage
		local reach = s.Range
		for link = 1, 1 + s.Chain do
			local e = CM.Nearest(run, prevX, prevZ, reach, hit)
			if not e then
				break
			end
			if link == 1 then
				fired += 1
			end
			hit[e.Uid] = true
			local dx, dz = e.X - prevX, e.Z - prevZ
			run:Write("Fx", w.Id, e.X, e.Z, atan2(-dz, -dx), link, sqrt(dx * dx + dz * dz), 1)
			CM.Hit(run, e, dmg, dx, dz, s.Knockback)
			if s.LinkBlast then
				local was = run.Proc
				run.Proc = true
				CM.Area(run, e.X, e.Z, s.LinkBlast, dmg * 0.4, 2)
				run.Proc = was
			end
			prevX, prevZ = e.X, e.Z
			dmg *= s.Falloff
			reach = s.Jump
		end
	end
	w.Timer = if fired > 0 then s.Cooldown else 0.2
end

---------------------------------------------------------------------------
-- AURA CROWN
---------------------------------------------------------------------------
function KINDS.Crown(run, w, dt)
	local s = w.S
	local now = run.Time
	local n = s.Amount
	for k = 1, s.Rings do
		for i = 1, n do
			local x, z = PremiumAbilities.CrownPos(run, s, k, i, n, now)
			for _, e in CM.Gather(run, x, z, s.Radius) do
				if (w.HitAt[e.Uid] or 0) <= now then
					w.HitAt[e.Uid] = now + s.HitCooldown
					CM.Hit(run, e, s.Damage, e.X - run.PX, e.Z - run.PZ, s.Knockback)
				end
			end
		end
	end
end

-- CombatManager calls this once with itself; the Kinds join its KINDS
function PremiumAbilities.Install(combat)
	CM = combat
	for kind, fn in KINDS do
		combat.Kinds[kind] = fn
	end
end

PremiumAbilities.Kinds = KINDS

return PremiumAbilities
