--[[
	Perks - what the BUILD does: the mechanics of level-up upgrades (shared/UpgradeData.lua),
	items (shared/ItemData.lua) and synergies (shared/SynergyData.lua). The numbers of every
	mechanic come from the data (Levels[n].P); this module is the behaviour, hooked into the
	moments that own it:

	  Perks.Refresh(run)             the build changed: levels, synergies, dash, plating
	  Perks.Sources(run)             stat bonuses                         (Run:Sources)
	  Perks.ApplyWeapon(run, w)      ability changes: category buffs, projectile mechanics
	                                                                      (Run:RefreshStats)
	  Perks.PreHit(run, e, dmg, src) damage multipliers before a hit      (CombatManager.Hit)
	  Perks.OnHit(run, e, dmg, crit, src)  on-hit procs                  (CombatManager.Hit)
	  Perks.OnKill(run, e)           on-kill procs                        (Run:OnKill)
	  Perks.BeforeHurt / AfterHurt   dodge, plating, reductions / reactions (Run:HurtPlayer)
	  Perks.FireRate(run)            attack speed that changes every step (Run:FireRate)
	  Perks.SpeedFactor(run)         walk speed that changes every step   (Run:SpeedFactor)
	  Perks.Step(run, dt)            everything periodic                  (Items.Step)
	  Perks.OnDash / OnRevive / OnLevelUp / OnGem / OnCoin / OnOverheal / OnEnemyShot

	Procs never trigger procs (run.Proc): a zap does not zap, an explosion does not explode.
	Damage of item mechanics keeps up with the horde (scaled by the run's time and Might).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local UpgradeData = require(Shared.UpgradeData)
local ItemData = require(Shared.ItemData)
local SynergyData = require(Shared.SynergyData)
local BossData = require(Shared.BossData)
local Protocol = require(Shared.Protocol)
local WaveData = require(Shared.WaveData)

local SpatialGrid = require(script.Parent.SpatialGrid)

local Perks = {}

local sqrt, min, max, cos, sin, atan2, floor = math.sqrt, math.min, math.max, math.cos, math.sin, math.atan2, math.floor
local TAU = math.pi * 2
local GFX = Protocol.Fx
local HF = Protocol.HitFlags
local MAX_ENEMY_R = 7.5
local scratch = {}
local ZONE = Protocol.ZoneStyle

-- lazy: these modules require this one
local combat: any, enemies: any, pickups: any = nil, nil, nil
local function CM(): any
	if not combat then
		combat = require(script.Parent.CombatManager) :: any
	end
	return combat
end
local function EM(): any
	if not enemies then
		enemies = require(script.Parent.EnemyManager) :: any
	end
	return enemies
end
local function PK(): any
	if not pickups then
		pickups = require(script.Parent.Pickups) :: any
	end
	return pickups
end

-- damage of an item mechanic: keeps up with the horde (enemy HP grows with run time)
local function scaled(run, base: number): number
	return base * run.Stats.Might * (1 + (WaveData.HPScale(run.Time) - 1) * 0.6)
end
Perks.Scaled = scaled

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------
function Perks.Init(run)
	run.UP = {} -- upgrade key -> P of its level (only mechanics)
	run.IP = {} -- item key -> P of its level
	run.Synergies = {}
	run.Perk = {
		Combo = 0,
		ComboAt = -99,
		ComboHits = 0,
		Streak = 0,
		StreakAt = -99,
		StreakWaves = 0,
		MoveTime = 0,
		RunTime = 0, -- Roadrunner / King of Movement (decays instead of resetting)
		Plating = 0,
		PlatingMax = 0,
		PlatingAt = 0,
		PanicAt = -999,
		FractureAt = -999,
		FractureUntil = 0,
		FangKills = 0,
		Guard = false,
		TokenAt = nil,
		TokenPays = 0,
		PulseAt = nil,
		WireNear = 0,
		WireAt = 0,
		WireSparkAt = 0,
		EspressoAt = nil,
		EspressoUntil = 0,
		WatchAt = nil,
		TrailAt = 0,
		TrailTick = 0,
		Trail = {},
		CrownKills = 0,
		CrownFrenzy = 0,
		FlopAt = nil,
		Pools = {}, -- your puddles, void pools, stink clouds, spills
		PoolTick = 0,
		ServoAt = nil,
		HandA = 0,
		HourA = 0,
		HandTick = 0,
		HandHit = {},
		LeverAt = nil,
		JackpotUntil = 0,
		GlitchAt = -99,
		GlitchFrenzy = 0,
		CrownedAt = nil,
		Crowned = false,
		FragmentHits = 0,
		StompHits = 0,
		BannerAt = nil,
		Troops = 0,
		TroopsUntil = 0,
		ShadowAt = nil,
		ShadowUntil = 0,
		ShadowX = 0,
		ShadowZ = 0,
		ShadowTimers = {},
		MarkAt = nil,
		MirrorAt = 0,
		MirrorReady = false,
		GooAt = -99,
		WhoopeeAt = 0,
		WhoopeeCheck = 0,
		GravityKills = 0,
		Predator = 0,
		Souls = 0,
		RedUntil = 0,
		RedSpeed = 0,
		DashFrenzy = 0,
		MarathonT = 0,
		VitalityAt = nil,
		XPStreak = 0,
		XPStreakAt = -99,
		LevelUps = 0,
		HitCount = 0,
		LeechAt = 0,
		Leeched = 0,
		BrawlAt = 0,
		Brawled = 0,
		SixtySevenHits = 0,
		Echo = {},
	}
	run.Proc = false
	run.BoomBudget = 6
end

-- a mechanic number of an owned upgrade / item (nil when not owned or not there)
local function U(run, key: string, name: string): any
	local p = run.UP[key]
	return p and p[name]
end
local function I(run, key: string, name: string): any
	local p = run.IP[key]
	return p and p[name]
end

local function hasDash(run): boolean
	return (run.Items.RocketSkates or 0) > 0 or (run.Items.CartWheel or 0) > 0 or (run.Items.VoidEye or 0) > 0
end
Perks.HasDash = hasDash

-- the build as SynergyData sees it
function Perks.Build(run)
	local abilities = {}
	for _, w in run.Weapons do
		abilities[w.Key] = true
		local from = w.Def.Evolution and w.Def.Evolution.From
		if from then
			abilities[from] = true
		end
	end
	return { Upgrades = run.Passives, Items = run.Items, Abilities = abilities, Dash = hasDash(run) }
end

-- the dash from items (Rocket Skates / Cart Wheel / Void Eye) and Dash Master
local function refreshDash(run)
	local charges, recharge, distance, invulnerable = 0, 3.2, 11, 0.35
	local skates = run.IP.RocketSkates
	if skates then
		charges, recharge, distance, invulnerable = skates.Charges, skates.Recharge, skates.Distance, skates.Invulnerable
	end
	charges = max(charges, I(run, "CartWheel", "Charges") or 0, I(run, "VoidEye", "Charges") or 0)
	if charges <= 0 then
		run.DashState = nil
		return
	end
	local master = run.UP.DashMaster
	if master then
		recharge *= 1 - (master.Recharge or 0)
		distance += master.Distance or 0
	end
	local dash = run.DashState
	if dash then
		local gained = charges - dash.Max
		dash.Max = charges
		dash.Charges = math.clamp(dash.Charges + max(0, gained), 0, charges)
		dash.Recharge, dash.Distance, dash.Invulnerable = recharge, distance, invulnerable
	else
		run.DashState = { Charges = charges, Max = charges, Timer = 0, Recharge = recharge, Distance = distance, Invulnerable = invulnerable }
	end
end

-- the build changed (a level up, an item, an evolution): recompute everything derived
function Perks.Refresh(run)
	table.clear(run.UP)
	for key, level in run.Passives do
		local l = UpgradeData.At(key, level)
		if l and l.P then
			run.UP[key] = l.P
		end
	end
	table.clear(run.IP)
	for key, level in run.Items do
		local l = ItemData.At(key, level)
		run.IP[key] = (l and l.P) or {}
	end
	refreshDash(run)
	-- plating: the new maximum fills up right away
	local plating = U(run, "Plating", "Max") or 0
	local perk = run.Perk
	if plating > perk.PlatingMax then
		perk.Plating += plating - perk.PlatingMax
	end
	perk.PlatingMax = plating
	perk.Plating = min(perk.Plating, plating)
	-- synergies: new ones are announced
	local build = Perks.Build(run)
	for _, syn in SynergyData.List do
		local have, total = SynergyData.Progress(syn, build)
		local on = have >= total
		if on and not run.Synergies[syn.Key] then
			run.Synergies[syn.Key] = true
			run.Result.Synergies = (run.Result.Synergies or 0) + 1
			run.Result.Flags["Syn" .. syn.Key] = true
			run:Write("Fx", 0, run.PX, run.PZ, 0, 14, 0, GFX.Synergy)
			run:Event("Synergy", { Key = syn.Key, Name = syn.Name, Desc = syn.Desc })
		elseif not on and run.Synergies[syn.Key] then
			run.Synergies[syn.Key] = nil
		end
	end
	if run.DashState and run.SendDash then
		run:SendDash()
	end
end

---------------------------------------------------------------------------
-- stats and abilities
---------------------------------------------------------------------------
function Perks.Sources(run): { [string]: number }
	local out = {}
	local function add(stats)
		if stats then
			for stat, value in stats do
				out[stat] = (out[stat] or 0) + value
			end
		end
	end
	for key, level in run.Passives do
		local l = UpgradeData.At(key, level)
		add(l and l.Stats)
	end
	for key, level in run.Items do
		local l = ItemData.At(key, level)
		add(l and l.Stats)
	end
	-- Predator at full stacks: crits
	local pred = run.IP.Predator
	if pred and pred.Crit and run.Perk.Predator >= pred.Max then
		out.Crit = (out.Crit or 0) + pred.Crit
	end
	-- souls
	local souls = run.Perk.Souls
	local sc = run.IP.SoulCollector
	if sc and souls > 0 then
		out.Might = (out.Might or 0) + sc.Might * souls
		out.MaxHPMult = (out.MaxHPMult or 0) + sc.HP * souls
	end
	return out
end

local AREA_FIELDS = { "Radius", "Orbit", "Length", "Blast", "Explode" }
local PROJECTILE_KINDS = { Projectile = true, Missile = true, Boomerang = true, Swords = true, Drone = true, Lob = true }

local function minEcho(a: number?, b: number?): number?
	if a and a > 0 and b and b > 0 then
		return min(a, b)
	end
	return if a and a > 0 then a else b
end

function Perks.ApplyWeapon(run, w)
	local s, def = w.S, w.Def
	local cat = def.Category
	-- ability-type items (Brass Knuckles, Bucket Hat, Slingshot Scope, Dog Treats, Third Arm I)
	for key, level in run.Items do
		local item = ItemData.ByKey[key]
		local p = run.IP[key]
		if item and p and (item.Effect == "Category" or item.Effect == "ThirdArm") and p.Category == cat then
			if p.Damage then
				s.Damage = (s.Damage or 0) * (1 + p.Damage)
				if s.Burn then
					s.Burn *= 1 + p.Damage
				end
			end
			if p.Area then
				for _, field in AREA_FIELDS do
					if s[field] then
						s[field] *= 1 + p.Area
					end
				end
			end
			if p.Speed and s.Speed then
				s.Speed *= 1 + p.Speed
			end
			if p.Amount and not def.NoAmount then
				s.Amount = (s.Amount or 1) + p.Amount
			end
			if p.Stun then
				s.Stun = max(s.Stun or 0, p.Stun)
			end
			if p.Slow then
				s.SlowHit = max(s.SlowHit or 0, p.Slow)
			end
			if p.Ricochet then
				s.Ricochet = (s.Ricochet or 0) + p.Ricochet
			end
			if p.BurnOnHit then
				s.BurnHit = max(s.BurnHit or 0, p.BurnOnHit)
			end
		end
		local _ = level
	end
	-- Overclock Chip: maxed abilities (evolutions are maxed)
	local oc = run.IP.OverclockChip
	if oc and w.Level >= def.MaxLevel then
		s.Damage = (s.Damage or 0) * (1 + oc.Damage)
		s.Echo = minEcho(s.Echo, oc.Echo)
	end
	s.Echo = minEcho(s.Echo, U(run, "RapidFire", "Echo"))
	s.Echo = minEcho(s.Echo, I(run, "ThirdArm", "Echo"))
	-- auras and fields slow (Expansion V)
	local auraSlow = U(run, "Expansion", "AuraSlow")
	if auraSlow and (def.Kind == "Aura" or def.Kind == "Field" or def.Kind == "FireRing") then
		s.SlowHit = max(s.SlowHit or 0, auraSlow)
	end
	-- PROJECTILES: the level-up category changes every projectile ability
	if cat == "PROJECTILE" or PROJECTILE_KINDS[def.Kind] then
		local up = run.UP
		s.Pierce = (s.Pierce or 0) + (U(run, "Penetration", "Pierce") or 0) + (U(run, "Velocity", "Pierce") or 0) + (U(run, "DoubleShot", "Pierce") or 0)
		s.PierceGrow = U(run, "Penetration", "Grow")
		local rico = (U(run, "Ricochet", "Ricochet") or 0) + (I(run, "RicochetCore", "Ricochet") or 0)
		if rico > 0 then
			s.Ricochet = (s.Ricochet or 0) + rico
		end
		s.RicochetRange = U(run, "Ricochet", "Range") or 16
		s.RicochetSeek = U(run, "Ricochet", "Seek")
		s.RicochetGrow = I(run, "RicochetCore", "Grow")
		if up.Split then
			s.SplitChance, s.SplitCount = up.Split.Chance, up.Split.Count
		end
		if up.Homing then
			s.Turn, s.Retarget = up.Homing.Turn, up.Homing.Retarget
		end
		if up.Explosive then
			s.ExplodeChance, s.ExplodeR, s.ExplodeShare, s.ExplodeBurn = up.Explosive.Chance, up.Explosive.Radius, up.Explosive.Share, up.Explosive.Burn
		end
		if up.Return then
			s.Return = max(s.Return or 0, up.Return.Return)
			s.ReturnPierce = up.Return.Pierce
		end
		if up.ChainShot then
			s.ChainChance, s.ChainShare, s.ChainJumps = up.ChainShot.Chance, up.ChainShot.Share, up.ChainShot.Jumps
		end
		local size = U(run, "BigShots", "Size")
		if size and s.Radius and def.Kind ~= "Lob" then
			s.Radius *= 1 + size
		end
		local knock = U(run, "BigShots", "Knock")
		if knock and s.Knockback then
			s.Knockback *= 1 + knock
		end
		s.SplitInherit = run.Synergies.BulletHell
		s.Distance = run.Synergies.Sharpshooter
	end
	-- THE SWARM: +1 summon, summon hits can zap
	if run.Synergies.TheSwarm and cat == "SUMMON" then
		if not def.NoAmount then
			s.Amount = (s.Amount or 1) + 1
		end
		s.ChainChance, s.ChainShare, s.ChainJumps = max(s.ChainChance or 0, 0.25), 0.5, 1
	end
	-- BRAWLER: melee knocks twice as hard
	if run.Synergies.Brawler and cat == "MELEE" and s.Knockback then
		s.Knockback *= 2
	end
	-- GRAVITY WELL: vortexes hit harder and pull XP
	if run.Synergies.GravityWell and def.Kind == "Vortex" then
		s.Damage *= 1.5
		s.Vacuum = 1
	end
end

-- extra pierce right now (Momentum V at full momentum)
function Perks.ExtraPierce(run): number
	local p = run.UP.Momentum
	if p and p.Pierce and run.Perk.MoveTime >= p.Build then
		return p.Pierce
	end
	return 0
end

---------------------------------------------------------------------------
-- damage
---------------------------------------------------------------------------
local function inPool(run, e, kind: string): number?
	for _, pool in run.Perk.Pools do
		if pool.Kind == kind and pool.Weaken then
			local dx, dz = e.X - pool.X, e.Z - pool.Z
			if dx * dx + dz * dz <= (pool.R + e.Radius) ^ 2 then
				return pool.Weaken
			end
		end
	end
	return nil
end

-- the part of the damage multiplier that depends on the player only (once per step)
local function playerMult(run): number
	local perk = run.Perk
	local now = run.Time
	local m = 1
	local combo = run.UP.Combo
	if combo then
		m *= 1 + min(combo.Max, floor(perk.Combo / 10) * 0.01)
	end
	local rampage = run.UP.Rampage
	if rampage then
		m *= 1 + min(rampage.Max, perk.Streak * 0.005)
	end
	local mom = run.UP.Momentum
	if mom then
		m *= 1 + mom.Max * min(1, perk.MoveTime / mom.Build)
	end
	local king = run.IP.KingOfMovement
	if king then
		m *= 1 + king.Might * min(1, perk.RunTime / king.Build)
	end
	local last = run.UP.LastStand
	if last and run.HP <= run.Stats.MaxHP * last.At then
		m *= 1 + last.Might
	end
	local pred = run.IP.Predator
	if pred then
		m *= 1 + perk.Predator * pred.Per
	end
	local frac = run.IP.TimeFracture
	if frac and frac.Might and now < perk.FractureUntil then
		m *= 1 + frac.Might
	end
	if now < perk.GlitchFrenzy then
		m *= 1.5
	end
	if now < perk.DashFrenzy then
		m *= 1 + (U(run, "DashMaster", "Frenzy") or 0)
	end
	if now < perk.CrownFrenzy then
		m *= 1.2
	end
	if now < perk.JackpotUntil then
		m *= 2
	end
	return m
end

function Perks.StepMult(run)
	run.PerkMult = playerMult(run)
end

-- the weak point multiplier of an EXPOSED boss (1 when it is not)
function Perks.ExposedMult(run, e): number
	if not (e.ExposedUntil and e.ExposedUntil > run.Time) then
		return 1
	end
	local boss = BossData.ByBody[e.Key]
	local bonus = (if boss then boss.WeakPoint.Mult else 1.5) - 1
	bonus *= 1 + (U(run, "GiantSlayer", "Exposed") or 0)
	if run.Synergies.BossHunter then
		bonus *= 2
	end
	return 1 + bonus
end

--[[
	Multipliers and special strikes before a hit lands. Returns the damage and extra hit flags.
	src = the weapon the hit comes from (nil for items and procs).
]]
function Perks.PreHit(run, e, dmg: number, src): (number, number)
	local now = run.Time
	local perk = run.Perk
	local flags = 0
	dmg *= run.PerkMult or 1
	local hpFrac = e.HP / max(1, e.MaxHP)
	local ex = U(run, "Execution", "Low")
	if ex and hpFrac < 0.35 then
		dmg *= 1 + ex
	end
	local bully = run.UP.Bully
	if bully then
		if hpFrac > 0.8 then
			dmg *= 1 + bully.High
		end
		if bully.First and not e.Touched then
			dmg *= 1 + bully.First
		end
	end
	e.Touched = true
	if e.IsBoss or e.Elite then
		dmg *= 1 + (U(run, "GiantSlayer", "Big") or 0)
		local orbit = U(run, "OrbitalMastery", "Big")
		if orbit and src and src.Def and src.Def.Kind == "Orbit" then
			dmg *= 1 + orbit
		end
		local belt = run.IP.ChampionBelt
		if belt then
			dmg *= 1 + (if e.IsBoss then belt.Boss else belt.Elite)
		end
	end
	-- weakened enemies
	local sand = I(run, "PocketSand", "Weaken")
	if sand and e.SlowUntil > now then
		dmg *= 1 + sand
	end
	local sauce = I(run, "HotSauceSocks", "Weaken")
	if sauce and e.BurnUntil and e.BurnUntil > now then
		dmg *= 1 + sauce
	end
	local watch = I(run, "PocketWatch", "Weaken")
	if watch and e.FrozenUntil > now then
		dmg *= 1 + watch + (if run.Synergies.TimeLord then 0.25 else 0)
	end
	if run.IP.QuackCore and run.IP.QuackCore.Weaken then
		local w = inPool(run, e, "Puddle")
		if w then
			dmg *= 1 + w
		end
	end
	if run.IP.VoidEye and run.IP.VoidEye.Weaken then
		local w = inPool(run, e, "Void")
		if w then
			dmg *= 1 + w
		end
	end
	-- the weak point of a boss
	local exposed = Perks.ExposedMult(run, e)
	if exposed > 1 then
		dmg *= exposed
		flags = bit32.bor(flags, HF.Weak)
	end
	if run.Proc then
		return dmg, flags
	end
	-- special strikes (counted on real hits only)
	local power = U(run, "Power", "Triple")
	if power and run.Rng:NextNumber() < power then
		dmg *= 3
		flags = bit32.bor(flags, HF.Big)
	end
	local crown = run.IP.KingsCrown
	if crown and perk.Crowned then
		perk.Crowned = false
		perk.CrownedAt = now + crown.Every
		dmg *= crown.Mult
		flags = bit32.bor(flags, HF.Big)
		run:Write("Fx", 0, e.X, e.Z, 0, 5, 0, GFX.Crowned)
		if crown.Slam then
			run.Proc = true
			CM().Area(run, e.X, e.Z, crown.Slam, dmg * 0.3, 8)
			run.Proc = false
			run:Write("Fx", 0, e.X, e.Z, 0, crown.Slam, 0, GFX.Stomp)
		end
	end
	local frag = run.IP.Fragment67
	if frag then
		perk.FragmentHits += 1
		if perk.FragmentHits >= frag.Every then
			perk.FragmentHits = 0
			dmg *= if e.IsBoss then frag.BossMult else frag.Mult
			flags = bit32.bor(flags, HF.Big)
			run:Write("Fx", 0, e.X, e.Z, 0, 6.7, 0, GFX.Crowned)
			if frag.Blast then
				CM().Free67Blast(run)
			end
		end
	end
	-- SIXTY-SEVEN: every 67th hit, a free 67 blast
	if run.Synergies.SixtySeven then
		perk.SixtySevenHits += 1
		if perk.SixtySevenHits >= 67 then
			perk.SixtySevenHits = 0
			CM().Free67Blast(run)
		end
	end
	-- SHARPSHOOTER: long shots hit harder (the projectile passes its distance)
	if src and src.Distance and run.HitDistance then
		dmg *= 1 + min(0.3, run.HitDistance / 10 * 0.02)
	end
	return dmg, flags
end

-- Loaded 67 Dice: a crit can become a 6.7x hit. Returns the multiplier and whether it rolled
function Perks.CritMult(run, mult: number): (number, boolean)
	local dice = run.IP.Dice67
	if dice and run.Rng:NextNumber() < dice.Chance then
		return max(mult, dice.Mult), true
	end
	return mult, false
end

-- up to `count` enemies closest to (x, z) inside `range`, never `skip`
local function closest(run, x: number, z: number, range: number, count: number, skip, seek: boolean?): { any }
	local n = SpatialGrid.Query(run.Grid, x, z, range + MAX_ENEMY_R, scratch)
	local picked = {}
	for _ = 1, count do
		local best, bestD = nil, math.huge
		for i = 1, n do
			local o = scratch[i]
			if o ~= skip and o.Alive and not o.Phased and not o.Dormant and o.Key ~= "Crate" and not table.find(picked, o) then
				local dx, dz = o.X - x, o.Z - z
				local d = dx * dx + dz * dz
				if d <= range * range then
					if seek and (o.IsBoss or o.Elite) then
						d -= 1e6
					end
					if d < bestD then
						best, bestD = o, d
					end
				end
			end
		end
		if not best then
			break
		end
		table.insert(picked, best)
	end
	return picked
end
Perks.Closest = closest

-- a zap from e to up to n enemies around it
local function zap(run, e, n: number, range: number, dmg: number, stun: number?)
	local targets = closest(run, e.X, e.Z, range, n, e)
	local was = run.Proc
	run.Proc = true
	for _, t in targets do
		local dx, dz = t.X - e.X, t.Z - e.Z
		run:Write("Fx", 0, e.X, e.Z, atan2(dz, dx), sqrt(dx * dx + dz * dz), 0, GFX.Zap)
		CM().Hit(run, t, dmg, dx, dz, 2)
		if stun and t.Alive then
			EM().Stun(run, t, stun)
		end
		-- STORM FRONT: a zap can call a lightning strike
		if run.Synergies.StormFront and t.Alive and run.Rng:NextNumber() < 0.15 then
			run:Write("Fx", 0, t.X, t.Z, 0, 4, 0, GFX.Strike)
			CM().Area(run, t.X, t.Z, 4, dmg, 2)
		end
	end
	run.Proc = was
	return targets
end
Perks.Zap = zap

-- an area proc (explosions, stomps...)
local function blast(run, x: number, z: number, r: number, dmg: number, knock: number, fx: number, stun: number?)
	local was = run.Proc
	run.Proc = true
	run:Write("Fx", 0, x, z, 0, r, 0, fx)
	CM().Area(run, x, z, r, dmg, knock)
	if stun then
		local n = SpatialGrid.Query(run.Grid, x, z, r + MAX_ENEMY_R, scratch)
		for i = 1, n do
			local o = scratch[i]
			if o.Alive and (o.X - x) ^ 2 + (o.Z - z) ^ 2 <= (r + o.Radius) ^ 2 then
				EM().Stun(run, o, stun)
			end
		end
	end
	run.Proc = was
end
Perks.Blast = blast

local function mark(run, e, amount: number, time: number)
	e.Mark = max(if e.MarkUntil and e.MarkUntil > run.Time then e.Mark or 0 else 0, amount)
	e.MarkUntil = run.Time + time
end

-- after a hit landed (e may have died)
function Perks.OnHit(run, e, dmg: number, crit: boolean, dice: boolean, src)
	if run.Proc then
		return
	end
	local perk = run.Perk
	local now = run.Time
	local ip, up = run.IP, run.UP
	-- combo
	if up.Combo then
		if now - perk.ComboAt > 1.2 then
			perk.Combo = 0
		end
		perk.Combo += 1
		perk.ComboAt = now
		local blastEvery = up.Combo.Blast
		if blastEvery and floor(perk.Combo / 10) * 0.01 >= up.Combo.Max then
			perk.ComboHits += 1
			if perk.ComboHits >= blastEvery then
				perk.ComboHits = 0
				blast(run, e.X, e.Z, 6, scaled(run, 24), 6, GFX.Bomb)
			end
		end
	end
	if crit then
		local chain = U(run, "CritMaster", "CritChain")
		if chain then
			zap(run, e, 1, 12, dmg * chain)
		end
		local crack = up.Brutal and up.Brutal.Crack
		if crack and e.Alive then
			mark(run, e, crack, up.Brutal.CrackTime)
		end
		local goggles = ip.CritGoggles
		if goggles and e.Alive then
			mark(run, e, goggles.Mark, goggles.Time)
		end
		-- EXECUTIONER: a crit on a marked enemy counts 3 hits for the death mark
		if run.Synergies.Executioner and e.DeathMark then
			e.DeathMark.Hits += 2
		end
	end
	if dice then
		local chain = I(run, "Dice67", "Chain")
		if chain then
			zap(run, e, chain, 16, dmg * 0.3)
		end
	end
	-- pocket sand
	local sand = ip.PocketSand
	if sand and e.Alive and not e.IsBoss and run.Rng:NextNumber() < sand.Chance then
		EM().Slow(e, sand.Factor, sand.Time, now)
	end
	-- static sock
	local sock = ip.StaticSock
	if sock then
		perk.HitCount += 1
		if perk.HitCount >= sock.Every then
			perk.HitCount = 0
			zap(run, e, sock.Targets, sock.Range, dmg * sock.Share, sock.Stun)
		end
	end
	-- giant's toe
	local toe = ip.GiantsToe
	if toe then
		perk.StompHits += 1
		if perk.StompHits >= toe.Every then
			perk.StompHits = 0
			blast(run, e.X, e.Z, toe.Radius, dmg * toe.Damage, 7, GFX.Stomp, toe.Stun)
		end
	end
	-- death mark
	local dm = e.DeathMark
	if dm and ip.DeathMark then
		dm.Hits += 1
		if dm.Hits >= ip.DeathMark.Hits and e.Alive then
			Perks.Detonate(run, e)
		end
	end
	-- blood engine: hits heal at low HP
	local blood = ip.BloodEngine
	if blood and blood.Leech and run.HP <= run.Stats.MaxHP * 0.3 then
		if now - perk.LeechAt >= 1 then
			perk.LeechAt, perk.Leeched = now, 0
		end
		if perk.Leeched < blood.LeechCap then
			perk.Leeched += blood.Leech
			run:Heal(blood.Leech)
		end
	end
	-- BRAWLER: melee hits heal
	if run.Synergies.Brawler and src and src.Def and src.Def.Category == "MELEE" then
		if now - perk.BrawlAt >= 1 then
			perk.BrawlAt, perk.Brawled = now, 0
		end
		if perk.Brawled < 5 then
			perk.Brawled += 1
			run:Heal(1)
		end
	end
end

-- a DEATH MARK explodes: part of the enemy's max HP
function Perks.Detonate(run, e)
	local dm = run.IP.DeathMark
	if not dm then
		return
	end
	e.DeathMark = nil
	local share = if e.IsBoss then dm.Boss else dm.Elite
	if e.Encounter and e.Encounter.Main then
		share *= 0.5 -- THE FINAL ONE resists
	end
	-- a share of max HP as it is: no damage bonuses, crits or 67% on top
	local dmg = e.MaxHP * share
	run:Write("Fx", 0, e.X, e.Z, 0, 6, 0, GFX.MarkBlast)
	local was = run.Proc
	run.Proc = true
	EM().Damage(run, e, dmg, HF.Big, 0, 0, 4)
	if dm.Radius then
		CM().Area(run, e.X, e.Z, dm.Radius, dmg * 0.25, 6)
		for _, t in closest(run, e.X, e.Z, 18, dm.Spread or 0, e) do
			if t.IsBoss or t.Elite then
				t.DeathMark = t.DeathMark or { Hits = 0 }
			else
				mark(run, t, 0.2, 3)
			end
		end
	end
	run.Proc = was
	if run.Synergies.Executioner then
		local pred = run.IP.Predator
		if pred then
			run.Perk.Predator = min(pred.Max, run.Perk.Predator + 5)
		end
	end
end

---------------------------------------------------------------------------
-- kills
---------------------------------------------------------------------------
-- the densest spot among a few random enemies near the player
local function densest(run, range: number, radius: number)
	local best, bestN = nil, -1
	local list = run.Enemies
	if #list == 0 then
		return nil
	end
	for _ = 1, min(10, #list) do
		local e = list[run.Rng:NextInteger(1, #list)]
		if e.Alive and not e.IsBoss and (e.X - run.PX) ^ 2 + (e.Z - run.PZ) ^ 2 <= range * range then
			local n = SpatialGrid.Query(run.Grid, e.X, e.Z, radius, scratch)
			if n > bestN then
				best, bestN = e, n
			end
		end
	end
	return best
end
Perks.Densest = densest

local function addPool(run, kind: string, x: number, z: number, r: number, time: number, opts)
	local perk = run.Perk
	if #perk.Pools >= 14 then
		local old = table.remove(perk.Pools, 1)
		run:Write("ZoneEnd", old.Id)
	end
	local pool = { Kind = kind, X = x, Z = z, R = r, Until = run.Time + time, Id = CM().NextZoneId(run) }
	for k, v in opts or {} do
		pool[k] = v
	end
	table.insert(perk.Pools, pool)
	run:Write("Zone", pool.Id, ZONE[kind], x, z, r, time)
	return pool
end
Perks.AddPool = addPool

function Perks.OnKill(run, e)
	local perk = run.Perk
	local ip, up = run.IP, run.UP
	local now = run.Time
	local src = e.LastSrc
	-- fang
	local fang = ip.Fang
	if fang then
		perk.FangKills += 1
		if perk.FangKills >= fang.Every then
			perk.FangKills = 0
			if fang.Guard and run.HP >= run.Stats.MaxHP then
				perk.Guard = true
			end
			run:Heal(fang.Heal)
		end
	end
	-- rampage
	local rampage = up.Rampage
	if rampage then
		if now - perk.StreakAt > 2 then
			perk.Streak = 0
			perk.StreakWaves = 0
		end
		perk.Streak += 1
		perk.StreakAt = now
		if rampage.Wave and perk.Streak >= (perk.StreakWaves + 1) * rampage.Wave then
			perk.StreakWaves += 1
			blast(run, run.PX, run.PZ, 12, scaled(run, 30), 12, GFX.Nova)
		end
	end
	-- predator
	local pred = ip.Predator
	if pred and perk.Predator < pred.Max then
		perk.Predator += 1
		if perk.Predator == pred.Max and pred.Crit then
			run:RefreshStats()
		end
	end
	if run.Proc then
		return -- a kill by an explosion does not start another one
	end
	-- boom juice
	local juice = ip.BoomJuice
	if juice and run.BoomBudget > 0 and run.Rng:NextNumber() < juice.Chance then
		run.BoomBudget -= 1
		blast(run, e.X, e.Z, juice.Radius, scaled(run, juice.Damage), 6, GFX.Bomb)
		if juice.Burn then
			for _, t in closest(run, e.X, e.Z, juice.Radius, 8) do
				CM().Burn(run, t, scaled(run, juice.Burn), 2.5)
			end
		end
	end
	-- crown of 67
	local crown = ip.Crown67
	if crown then
		perk.CrownKills += 1
		if perk.CrownKills >= crown.Every then
			perk.CrownKills = 0
			CM().Free67Blast(run)
			if crown.Frenzy then
				perk.CrownFrenzy = now + crown.Frenzy
			end
		end
	end
	-- gravity seed
	local seed = ip.GravitySeed
	if seed then
		perk.GravityKills += 1
		if perk.GravityKills >= seed.Every then
			perk.GravityKills = 0
			local at = densest(run, 45, seed.Radius) or e
			addPool(run, "Gravity", at.X, at.Z, seed.Radius, seed.Time, {
				Pull = seed.Pull,
				Damage = scaled(run, seed.Damage) * (if run.Synergies.GravityWell then 1.5 else 1),
				Blast = seed.Blast,
			})
		end
	end
	-- twin pact: the kill passes on
	local pact = ip.TwinPact
	if pact then
		local left = pact.Chain or 1
		local from = e
		local share = e.MaxHP * pact.Share
		for _ = 1, left do
			local t = closest(run, from.X, from.Z, 16, 1, from)[1]
			if not t then
				break
			end
			local dx, dz = t.X - from.X, t.Z - from.Z
			run:Write("Fx", 0, from.X, from.Z, atan2(dz, dx), sqrt(dx * dx + dz * dz), 0, GFX.Pact)
			run.Proc = true
			CM().Hit(run, t, min(share, t.MaxHP * (if t.IsBoss then 0.05 else 10)), dx, dz, 2)
			run.Proc = false
			if t.Alive then
				break
			end
			from = t
		end
	end
	-- marked enemies spread their mark (crit goggles III)
	local spread = I(run, "CritGoggles", "Spread")
	if spread and e.MarkUntil and e.MarkUntil > now then
		for _, t in closest(run, e.X, e.Z, 14, spread, e) do
			mark(run, t, ip.CritGoggles.Mark, ip.CritGoggles.Time)
		end
	end
	-- fire: burning enemies spread it / explode
	local burning = e.BurnUntil and e.BurnUntil > now
	if burning then
		if run.Synergies.ScorchedEarth then
			blast(run, e.X, e.Z, 5, scaled(run, 18), 5, GFX.Bomb)
		elseif U(run, "BurnMastery", "Spread") or (src and src.S and src.S.DeathBurn) then
			for _, t in closest(run, e.X, e.Z, 9, 3, e) do
				CM().Burn(run, t, max(e.BurnDps or 0, scaled(run, 5)), 2.5)
			end
		end
	end
	-- DEEP FREEZE: frozen / slowed enemies shatter
	if run.Synergies.DeepFreeze and (e.FrozenUntil > now or e.SlowUntil > now) then
		blast(run, e.X, e.Z, 4.5, scaled(run, 20), 4, GFX.Shatter)
	end
	-- the ability that killed it
	local s = src and src.S
	if s then
		if s.DeathBlast then
			blast(run, e.X, e.Z, s.DeathBlast, s.Damage * 0.8, 5, GFX.Bomb)
		end
		if s.Spread and src.Def.Kind == "Cloud" and (run.Perk.SpreadAt or 0) <= now then
			run.Perk.SpreadAt = now + 0.8
			CM().AddZone(run, src, "Cloud", e.X, e.Z, s.Radius * 0.7, s.Duration * 0.6)
		end
	end
	-- vampire IV: elites heal a lot
	if e.Elite then
		local heal = U(run, "Vampire", "EliteHeal")
		if heal then
			run:Heal(run.Stats.MaxHP * heal)
		end
	end
	-- souls
	if ip.SoulCollector then
		if e.IsBoss or e.Elite then
			local Items = require(script.Parent.Items) :: any
			Items.DropSoul(run, e.X, e.Z)
		elseif run.Synergies.SoulHarvest and run.Rng:NextNumber() < 0.01 then
			local Items = require(script.Parent.Items) :: any
			Items.DropSoul(run, e.X, e.Z)
		end
	end
end

-- a soul picked up
function Perks.GainSoul(run)
	local sc = run.IP.SoulCollector
	if not sc then
		return
	end
	local perk = run.Perk
	perk.Souls = min(sc.Max, perk.Souls + 1)
	run.Result.Souls = (run.Result.Souls or 0) + 1
	if sc.Heal then
		run:Heal(sc.Heal)
		perk.RedUntil = max(perk.RedUntil, run.Time + (sc.Rush or 3))
		perk.RedSpeed = max(perk.RedSpeed, 0.3)
	end
	run:Write("Fx", 0, run.PX, run.PZ, 0, 5, 0, GFX.Soul)
	run:RefreshStats()
	run:Event("Souls", { Count = perk.Souls, Max = sc.Max })
end

---------------------------------------------------------------------------
-- getting hurt
---------------------------------------------------------------------------
-- kind: "Contact" (touched), "Shot" (enemy projectile), "Boss" (a boss attack), "Hazard"
-- returns the damage that still goes through (0 = avoided completely)
function Perks.BeforeHurt(run, amount: number, kind: string?): number
	local perk = run.Perk
	local up, ip = run.UP, run.IP
	local now = run.Time
	-- dodge
	local dodge = up.Dodge
	if dodge and run.Rng:NextNumber() < dodge.Chance then
		run:Write("Fx", 0, run.PX, run.PZ, 0, 4, 0, GFX.Dodge)
		if dodge.Slip then
			blast(run, run.PX, run.PZ, 7, scaled(run, 8), 14, GFX.Nova, 0.6)
		end
		-- SHADOW DANCE: dodging calls your shadow
		if run.Synergies.ShadowDance then
			perk.ShadowUntil = max(perk.ShadowUntil, now + 3)
			perk.ShadowX, perk.ShadowZ = run.PX, run.PZ
		end
		return 0
	end
	-- fang guard
	if perk.Guard then
		perk.Guard = false
		run:Write("Fx", 0, run.PX, run.PZ, 0, 4, 0, GFX.Guard)
		return 0
	end
	-- glitched core: glitch away
	local core = ip.GlitchedCore
	if core and now >= perk.GlitchAt and run.Rng:NextNumber() < core.Chance then
		perk.GlitchAt = now + core.Cooldown
		local fx, fz = run.PX, run.PZ
		run:GlitchStep(core.Distance)
		blast(run, fx, fz, 6, scaled(run, core.Blast), 10, GFX.Bomb)
		if core.Frenzy then
			perk.GlitchFrenzy = now + core.Frenzy
		end
		return 0
	end
	-- goo heart: a decoy splits off
	local goo = ip.GooHeart
	if goo and now >= perk.GooAt then
		perk.GooAt = now + goo.Cooldown
		run.Decoy = { X = run.PX, Z = run.PZ, Until = now + goo.Time, R = 16, Tick = 1e9, Goo = true, Pop = goo.Pop }
		run:Write("Clone", run.PX, run.PZ, goo.Time)
	end
	-- reductions
	local cut = U(run, "ToughSkin", "Cut") or 0
	local last = up.LastStand
	if last and run.HP <= run.Stats.MaxHP * last.At then
		cut += last.Cut
	end
	if kind == "Boss" then
		cut += U(run, "Armor", "BossCut") or 0
	end
	amount *= max(0.2, 1 - cut)
	local cap = U(run, "ToughSkin", "Cap")
	if cap then
		amount = min(amount, run.Stats.MaxHP * cap)
	end
	-- plating soaks it up first
	perk.PlatingAt = now
	if perk.Plating > 0 then
		local soak = min(perk.Plating, amount)
		perk.Plating -= soak
		amount -= soak
		if perk.Plating <= 0 then
			perk.Plating = 0
			if U(run, "Plating", "Break") then
				blast(run, run.PX, run.PZ, 10, scaled(run, 14), 16, GFX.Nova)
			end
			-- IRON FORTRESS: a thorn nova
			if run.Synergies.IronFortress then
				blast(run, run.PX, run.PZ, 9, scaled(run, 30), 10, GFX.Thorns)
			end
		end
		if amount <= 0 then
			return 0
		end
	end
	return amount
end

function Perks.AfterHurt(run, dmg: number)
	local perk = run.Perk
	local up, ip = run.UP, run.IP
	local now = run.Time
	local red = ip.RedButton
	if red then
		perk.RedUntil = now + red.Time
		perk.RedSpeed = red.Speed
		if red.Wave then
			blast(run, run.PX, run.PZ, red.Wave, scaled(run, 6), 14, GFX.Nova)
		end
	end
	local cactus = ip.CactusHug
	if cactus and cactus.Needles and now >= (perk.NeedleAt or 0) then
		perk.NeedleAt = now + 1
		local d = (cactus.Damage + run.Level * cactus.PerLevel) * run.Stats.Might
		blast(run, run.PX, run.PZ, 11, d, 6, GFX.Thorns)
	end
	local pred = ip.Predator
	if pred then
		local had = perk.Predator
		perk.Predator = max(0, perk.Predator - pred.Lose)
		if pred.Crit and had >= pred.Max and perk.Predator < pred.Max then
			run:RefreshStats()
		end
	end
	local frac = run.HP / max(1, run.Stats.MaxHP)
	local panic = up.PanicButton
	if panic and frac <= panic.At and now >= perk.PanicAt then
		perk.PanicAt = now + panic.Cooldown
		blast(run, run.PX, run.PZ, panic.Radius, scaled(run, 20), 22, GFX.Panic)
		run.Invulnerable = max(run.Invulnerable, panic.Invulnerable)
		if panic.Heal then
			run:Heal(run.Stats.MaxHP * panic.Heal)
		end
		run:Event("Perk", { Key = "PanicButton", Text = "PANIC BUTTON!" })
	end
	local tf = ip.TimeFracture
	if tf and frac <= tf.At and now >= perk.FractureAt then
		perk.FractureAt = now + tf.Cooldown
		perk.FractureUntil = now + tf.Time + (if run.Synergies.TimeLord then 1 else 0)
		local r2 = tf.Radius * tf.Radius
		for _, e in run.Enemies do
			if e.Alive and (e.X - run.PX) ^ 2 + (e.Z - run.PZ) ^ 2 <= r2 then
				EM().Slow(e, tf.Slow, tf.Time, now)
			end
		end
		run:Write("Fx", 0, run.PX, run.PZ, 0, tf.Radius, tf.Time, GFX.Fracture)
		run:Event("Perk", { Key = "TimeFracture", Text = "TIME FRACTURE" })
	end
end

---------------------------------------------------------------------------
-- dynamic speed and attack speed
---------------------------------------------------------------------------
function Perks.FireRate(run): number
	local perk = run.Perk
	local up, ip = run.UP, run.IP
	local now = run.Time
	local missing = 1 - math.clamp(run.HP / max(1, run.Stats.MaxHP), 0, 1)
	local rate = 0
	local blood = ip.BloodEngine
	if blood then
		rate += blood.Max * missing
	end
	if run.Synergies.BloodPact then
		rate += run.Stats.Berserk * 0.5 * missing
	end
	local wire = ip.BlackWire
	if wire then
		rate += min(wire.Max, perk.WireNear * wire.Per)
	end
	local tail = up.Tailwind
	if tail and run.Moved > 0.05 then
		rate += tail.Rate
	end
	local king = ip.KingOfMovement
	if king then
		rate += king.Rate * min(1, perk.RunTime / king.Build)
	end
	local esp = ip.Espresso67
	if esp and now < perk.EspressoUntil then
		rate += esp.Rate
	end
	return rate
end

-- walk speed multiplier: slows on the ground (unless immune) and speed boosts
function Perks.SpeedFactor(run, slow: number): number
	local perk = run.Perk
	local up, ip = run.UP, run.IP
	local now = run.Time
	if U(run, "Swiftness", "NoSlow") then
		slow = 1
	elseif run.ChillUntil and run.ChillUntil > now then
		slow = min(slow, run.ChillFactor or 1)
	end
	local boost = 0
	if now < perk.RedUntil then
		boost += perk.RedSpeed
	end
	local king = ip.KingOfMovement
	if king then
		boost += king.Move * min(1, perk.RunTime / king.Build)
	end
	local rr = up.Roadrunner
	if rr then
		boost += rr.Max * min(1, perk.RunTime / rr.Build)
	end
	local esp = ip.Espresso67
	if esp and esp.Move and now < perk.EspressoUntil then
		boost += esp.Move
	end
	local berserk = U(run, "Berserk", "LowSpeed")
	if berserk and run.HP < run.Stats.MaxHP * 0.5 then
		boost += berserk
	end
	local storm = U(run, "XPStorm", "Move")
	if storm and run:Buff("XPStorm") then
		boost += storm
	end
	return slow * (1 + boost)
end

-- how fast dash charges come back (PERPETUAL MOTION at full speed: twice as fast)
function Perks.DashRechargeRate(run): number
	local king = run.IP.KingOfMovement
	if run.Synergies.PerpetualMotion and king and run.Perk.RunTime >= king.Build then
		return 2
	end
	return 1
end

---------------------------------------------------------------------------
-- moments
---------------------------------------------------------------------------
-- a line from (x1, z1) to (x2, z2): hit what is on it
local function line(run, x1: number, z1: number, x2: number, z2: number, width: number, dmg: number, knock: number)
	local dx, dz = x2 - x1, z2 - z1
	local len = sqrt(dx * dx + dz * dz)
	if len < 0.1 then
		return
	end
	local ux, uz = dx / len, dz / len
	local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
	local n = SpatialGrid.Query(run.Grid, cx, cz, len / 2 + width + MAX_ENEMY_R, scratch)
	local list = {}
	for i = 1, n do
		local e = scratch[i]
		if e.Alive and not e.Phased then
			local rx, rz = e.X - x1, e.Z - z1
			local along = rx * ux + rz * uz
			if along >= -e.Radius and along <= len + e.Radius and math.abs(rx * uz - rz * ux) <= width + e.Radius then
				table.insert(list, e)
			end
		end
	end
	local was = run.Proc
	run.Proc = true
	for _, e in list do
		CM().Hit(run, e, dmg, ux, uz, knock)
	end
	run.Proc = was
end
Perks.Line = line

function Perks.OnDash(run, fromX: number, fromZ: number, toX: number, toZ: number, dx: number, dz: number, dist: number)
	local ip, up = run.IP, run.UP
	local now = run.Time
	local trail = I(run, "RocketSkates", "Trail")
	if trail then
		line(run, fromX, fromZ, toX, toZ, 2.5, scaled(run, trail), 4)
	end
	local master = up.DashMaster
	if master and master.Hit then
		line(run, fromX, fromZ, toX, toZ, 2.5, scaled(run, 18), 8)
	end
	if master and master.Frenzy then
		run.Perk.DashFrenzy = now + 2
	end
	local ram = ip.CartWheel
	if ram then
		line(run, fromX, fromZ, toX, toZ, ram.Width, scaled(run, ram.Damage), 14)
		run:Write("Fx", 0, fromX, fromZ, atan2(dz, dx), dist, ram.Width, GFX.Ram)
		if ram.Spill then
			for k = 1, 3 do
				local f = k / 4
				addPool(run, "Spill", fromX + (toX - fromX) * f, fromZ + (toZ - fromZ) * f, 3, ram.Spill, { Burn = scaled(run, 8) })
			end
		end
	end
	local void = ip.VoidEye
	if void then
		local opts = { Damage = scaled(run, void.Damage), Weaken = void.Weaken }
		addPool(run, "Void", fromX, fromZ, void.Radius, void.Time, opts)
		addPool(run, "Void", toX, toZ, void.Radius, void.Time, opts)
	end
	-- PERPETUAL MOTION: at full speed every dash fires a shockwave
	local king = ip.KingOfMovement
	if run.Synergies.PerpetualMotion and king and run.Perk.RunTime >= king.Build then
		blast(run, toX, toZ, 9, scaled(run, 22), 12, GFX.Nova)
	end
end

function Perks.OnRevive(run)
	local snack = I(run, "GoldenSnack", "Nuke")
	if snack then
		run.HP = run.Stats.MaxHP
		blast(run, run.PX, run.PZ, 30, scaled(run, 60), 26, GFX.Nova)
	end
	local sc = run.IP.SoulCollector
	if sc and run.Perk.Souls > 0 then
		run.Perk.Souls = floor(run.Perk.Souls / 2)
		run:RefreshStats()
		run:Event("Souls", { Count = run.Perk.Souls, Max = sc.Max, Lost = true })
	end
end

function Perks.OnLevelUp(run)
	local perk = run.Perk
	perk.LevelUps += 1
	local every = U(run, "Wisdom", "Reroll")
	if every and perk.LevelUps % every == 0 then
		run.Rerolls += 1
	end
end

-- XP multiplier of the collector's streak (called for every gem picked up)
function Perks.OnGem(run): number
	local pull = U(run, "Magnet", "Pull")
	if pull and run.Rng:NextNumber() < pull then
		run.MagnetAll = true -- Magnet IV: every gem on the map comes to you
	end
	local streak = run.UP.XPStreak
	if not streak then
		return 1
	end
	local perk = run.Perk
	local now = run.Time
	if now - perk.XPStreakAt > 1 then
		perk.XPStreak = 0
	end
	perk.XPStreak += 1
	perk.XPStreakAt = now
	local cap = streak.Max * (if run.Synergies.XPEngine then 2 else 1)
	local bonus = min(cap, floor(perk.XPStreak / 5) * 0.01)
	if streak.Heal and bonus >= cap then
		run:Heal(streak.Heal)
	end
	return 1 + bonus
end

-- a coin picked up (Alchemy III, GOLD RUSH): XP
function Perks.OnCoin(run, n: number)
	local jackpot = U(run, "Greed", "Jackpot")
	if jackpot and run.Rng:NextNumber() < jackpot then
		run:AddCoins(math.floor(n * 5.7 + 0.5)) -- Greed IV: this coin pays x6.7
	end
	local xp = 0
	if U(run, "Alchemy", "Coins") then
		xp += n
	end
	if run.Synergies.GoldRush then
		xp += n * 2
	end
	if xp > 0 then
		run:AddXP(xp)
	end
end

-- healing past full HP (Alchemy)
function Perks.OnOverheal(run, amount: number)
	local rate = U(run, "Alchemy", "Rate")
	if rate and amount > 0 then
		run:AddXP(amount * rate)
	end
end

-- an enemy shot is about to hit you: the Void Mirror reflects it. Returns true when it did
function Perks.OnEnemyShot(run, shot): boolean
	local mirror = run.IP.VoidMirror
	if not mirror or not run.Perk.MirrorReady then
		return false
	end
	run.Perk.MirrorReady = false
	run.Perk.MirrorAt = run.Time + mirror.Every
	local target = closest(run, run.PX, run.PZ, 40, 1, nil, true)[1]
	run:Write("Fx", 0, run.PX, run.PZ, 0, 4, 0, GFX.Mirror)
	if target then
		local dx, dz = target.X - run.PX, target.Z - run.PZ
		local dmg = scaled(run, (shot.Damage or 10) * 3) * mirror.Mult
		run:Write("Fx", 0, run.PX, run.PZ, atan2(dz, dx), sqrt(dx * dx + dz * dz), 0, GFX.Zap)
		if mirror.Pierce then
			line(run, run.PX, run.PZ, target.X, target.Z, 1.6, dmg, 4)
		else
			run.Proc = true
			CM().Hit(run, target, dmg, dx, dz, 4)
			run.Proc = false
		end
	end
	return true
end

-- Cactus Hug: whatever touches you gets hurt (twice a second at most)
function Perks.Thorns(run, touching: { any })
	local cactus = run.IP.CactusHug
	if not cactus or run.Time < (run.Perk.CactusAt or 0) then
		return
	end
	run.Perk.CactusAt = run.Time + 0.5
	local dmg = (cactus.Damage + run.Level * cactus.PerLevel) * run.Stats.Might * (if run.Synergies.IronFortress then 2 else 1)
	run:Write("Fx", 0, run.PX, run.PZ, 0, 4, 0, GFX.Thorns)
	for _, e in touching do
		EM().Damage(run, e, dmg, 0, e.X - run.PX, e.Z - run.PZ, 5)
	end
end

-- temporary troops of the Overlord's Banner (CombatManager counts them as allies)
function Perks.Troops(run): number
	return if run.Time < run.Perk.TroopsUntil then run.Perk.Troops else 0
end

---------------------------------------------------------------------------
-- step: everything periodic
---------------------------------------------------------------------------
local function every(perk, field: string, now: number, period: number, first: number?): boolean
	local at = perk[field]
	if at == nil then
		perk[field] = now + (first or period)
		return false
	end
	if now >= at then
		perk[field] = now + period
		return true
	end
	return false
end

local function stepMovement(run, dt: number)
	local perk = run.Perk
	local moving = run.Moved > 0.05
	if moving then
		perk.MoveTime += dt
		perk.RunTime += dt
	else
		perk.MoveTime = 0
		perk.RunTime = max(0, perk.RunTime - dt * 4) -- fades over ~1.5 s
	end
	run.MoveTime = perk.MoveTime
	-- marathon: pulses while you keep running
	local m = run.UP.Marathon
	if m then
		if moving then
			perk.MarathonT += dt
			if perk.MarathonT >= m.Every then
				perk.MarathonT = 0
				blast(run, run.PX, run.PZ, m.Radius, scaled(run, m.Damage), 6, GFX.Nova)
				if m.Heal then
					run:Heal(m.Heal)
					run.MagnetAll = true
				end
			end
		else
			perk.MarathonT = 0
		end
	end
	-- roadrunner V: trample at top speed
	local rr = run.UP.Roadrunner
	if rr and rr.Ram and perk.RunTime >= rr.Build and run.Time >= (perk.RamAt or 0) then
		perk.RamAt = run.Time + 0.3
		local was = run.Proc
		run.Proc = true
		CM().Area(run, run.PX, run.PZ, 3.2, scaled(run, 9), 8)
		run.Proc = was
	end
	-- king of movement III: shockwaves at full speed
	local king = run.IP.KingOfMovement
	if king and king.Wave and perk.RunTime >= king.Build and run.Time >= (perk.KingWaveAt or 0) then
		perk.KingWaveAt = run.Time + king.Wave
		blast(run, run.PX, run.PZ, 8, scaled(run, 14), 8, GFX.Nova)
	end
end

local function stepDefense(run, dt: number)
	local perk = run.Perk
	local now = run.Time
	local up, ip = run.UP, run.IP
	-- plating refills after a few seconds without a hit
	local plating = up.Plating
	if plating and perk.Plating < perk.PlatingMax and now - perk.PlatingAt >= plating.Delay then
		perk.Plating = min(perk.PlatingMax, perk.Plating + plating.Rate * dt)
	end
	-- extra regeneration
	local extra = 0
	local frac = run.HP / max(1, run.Stats.MaxHP)
	local regen = up.Regeneration
	if regen and regen.Low and frac < 0.5 then
		extra += run.Stats.Regen * (regen.Low - 1)
	end
	local last = up.LastStand
	if last and last.Regen and frac <= last.At then
		extra += last.Regen
	end
	local tf = ip.TimeFracture
	if tf and tf.Regen and now < perk.FractureUntil then
		extra += tf.Regen
	end
	if extra > 0 and run.HP < run.Stats.MaxHP and not run.Dead then
		run.HP = min(run.Stats.MaxHP, run.HP + extra * dt)
	end
	-- vitality V: a periodic heal
	local vit = up.Vitality
	if vit and vit.Pulse and every(perk, "VitalityAt", now, vit.Pulse) then
		run:Heal(run.Stats.MaxHP * vit.Heal)
	end
	-- the goo decoy pops / any decoy ends
	local decoy = run.Decoy
	if decoy and now >= decoy.Until then
		if decoy.Goo and decoy.Pop then
			blast(run, decoy.X, decoy.Z, 9, scaled(run, decoy.Pop), 10, GFX.Bomb)
		end
		if decoy.Goo then
			run.Decoy = nil
		end
	end
	-- the void mirror recharges
	local mirror = ip.VoidMirror
	if mirror and not perk.MirrorReady and now >= perk.MirrorAt then
		perk.MirrorReady = true
	end
end

local function stepTrail(run, dt: number, p)
	local perk = run.Perk
	local now = run.Time
	if run.Moved > 0.05 and now >= perk.TrailAt then
		perk.TrailAt = now + p.Every
		table.insert(perk.Trail, { X = run.PX, Z = run.PZ, Until = now + p.Life })
		if #perk.Trail > 14 then
			table.remove(perk.Trail, 1)
		end
		run:Write("Fx", 0, run.PX, run.PZ, 0, p.Radius, p.Life, GFX.Trail)
	end
	perk.TrailTick -= dt
	if perk.TrailTick > 0 then
		return
	end
	perk.TrailTick = 0.25
	local dps = scaled(run, p.Burn) * run.Stats.Burn
	local trail = perk.Trail
	local i = 1
	while i <= #trail do
		local patch = trail[i]
		if now >= patch.Until then
			table.remove(trail, i)
		else
			local n = SpatialGrid.Query(run.Grid, patch.X, patch.Z, p.Radius + MAX_ENEMY_R, scratch)
			for k = 1, n do
				local e = scratch[k]
				if e.Alive and not e.Air and not e.Phased and e.Key ~= "Crate" then
					if (e.X - patch.X) ^ 2 + (e.Z - patch.Z) ^ 2 <= (p.Radius + e.Radius) ^ 2 then
						CM().Burn(run, e, dps, p.BurnTime)
					end
				end
			end
			i += 1
		end
	end
end

local function freezeAround(run, radius: number, time: number)
	local now = run.Time
	local r2 = radius * radius
	for _, e in run.Enemies do
		if (e.X - run.PX) ^ 2 + (e.Z - run.PZ) ^ 2 <= r2 and e.Behavior ~= "Static" then
			if e.IsBoss then
				EM().Slow(e, 0.4, time, now)
			elseif not e.Air then
				EM().Stun(run, e, time, true)
			end
		end
	end
	run:Write("Fx", 0, run.PX, run.PZ, 0, radius, 0, GFX.TimeStop)
end

-- your pools: puddles slow, void pools hurt, stink clouds slow, spills burn, gravity pulls
local function stepPools(run, dt: number)
	local perk = run.Perk
	local now = run.Time
	local pools = perk.Pools
	perk.PoolTick -= dt
	local tick = perk.PoolTick <= 0
	if tick then
		perk.PoolTick = 0.25
	end
	local i = 1
	while i <= #pools do
		local pool = pools[i]
		if now >= pool.Until then
			if pool.Kind == "Gravity" and pool.Blast then
				blast(run, pool.X, pool.Z, pool.R, scaled(run, pool.Blast), 10, GFX.Bomb)
			end
			run:Write("ZoneEnd", pool.Id)
			table.remove(pools, i)
		else
			local n = SpatialGrid.Query(run.Grid, pool.X, pool.Z, pool.R + MAX_ENEMY_R, scratch)
			for k = 1, n do
				local e = scratch[k]
				if e.Alive and not e.Air and not e.Phased and e.Key ~= "Crate" then
					local dx, dz = pool.X - e.X, pool.Z - e.Z
					local d2 = dx * dx + dz * dz
					if d2 <= (pool.R + e.Radius) ^ 2 then
						if pool.Kind == "Gravity" and not e.IsBoss then
							local d = sqrt(d2)
							if d > 0.6 then
								local step = min(d - 0.5, pool.Pull * dt)
								e.X += dx / d * step
								e.Z += dz / d * step
							end
						end
						if tick then
							if pool.Slow then
								EM().Slow(e, pool.Slow, 0.5, now)
							end
							if pool.Damage then
								run.Proc = true
								CM().Hit(run, e, pool.Damage * 0.25, 0, 0, 0)
								run.Proc = false
							end
							if pool.Burn then
								CM().Burn(run, e, pool.Burn, 2)
							end
						end
					end
				end
			end
			if pool.Kind == "Gravity" and run.Synergies.GravityWell then
				run.MagnetAll = true
			end
			i += 1
		end
	end
end

local function stepItems(run, dt: number)
	local perk = run.Perk
	local now = run.Time
	local ip = run.IP
	-- magnetic bolt III: pull every gem
	local bolt = ip.MagneticBolt
	if bolt and bolt.Pulse then
		local period = if run.Synergies.XPEngine then 20 else bolt.Pulse
		if every(perk, "PulseAt", now, period) then
			run.MagnetAll = true
			run:Write("Fx", 0, run.PX, run.PZ, 0, 30, 0, GFX.Pulse)
		end
	end
	-- rusty token: XP payouts
	local token = ip.RustyToken
	if token and every(perk, "TokenAt", now, token.Every) then
		perk.TokenPays += 1
		local amount = GameConfig.XPNeeded(run.Level) * token.XP * (if run.Synergies.GoldRush then 2 else 1)
		for k = 1, 3 do
			local a = k * TAU / 3 + run.Rng:NextNumber(0, 1)
			PK().SpawnGem(run, run.PX + cos(a) * 3, run.PZ + sin(a) * 3, amount / 3)
		end
		if token.Coins and perk.TokenPays % token.Jackpot == 0 then
			run:AddCoins(token.Coins)
			run:Write("Fx", 0, run.PX, run.PZ, 0, 4, 0, GFX.Jackpot)
		end
	end
	-- black wire: count the crowd twice a second, sparks at the maximum
	local wire = ip.BlackWire
	if wire and now >= perk.WireAt then
		perk.WireAt = now + 0.5
		perk.WireNear = SpatialGrid.Query(run.Grid, run.PX, run.PZ, wire.Range, scratch)
		if wire.Spark and perk.WireNear * wire.Per >= wire.Max and now >= perk.WireSparkAt then
			perk.WireSparkAt = now + wire.Spark
			local fake = { X = run.PX, Z = run.PZ }
			zap(run, fake, 3, wire.Range + 4, scaled(run, 12))
		end
	end
	-- espresso rush
	local esp = ip.Espresso67
	if esp and every(perk, "EspressoAt", now, esp.Every, 4) then
		perk.EspressoUntil = now + esp.Time
		run:Event("Perk", { Key = "Espresso67", Text = "ESPRESSO RUSH", Duration = esp.Time })
	end
	-- pocket watch: time stops around you
	local watch = ip.PocketWatch
	if watch and every(perk, "WatchAt", now, watch.Every, 6) then
		freezeAround(run, watch.Radius, watch.Time + (if run.Synergies.TimeLord then 1 else 0))
	end
	-- hot sauce socks
	if ip.HotSauceSocks then
		stepTrail(run, dt, ip.HotSauceSocks)
	end
	-- quack core: a belly-flop + a puddle
	local quack = ip.QuackCore
	if quack and every(perk, "FlopAt", now, quack.Every, 3) then
		blast(run, run.PX, run.PZ, quack.Radius, scaled(run, quack.Damage), 12, GFX.Flop)
		addPool(run, "Puddle", run.PX, run.PZ, quack.Radius * 0.8, quack.Puddle, { Slow = quack.Slow, Weaken = quack.Weaken })
	end
	-- servo laser: through the biggest crowd
	local servo = ip.ServoLaser
	if servo and every(perk, "ServoAt", now, servo.Every, 3) then
		local target = densest(run, servo.Length, 6)
		if target then
			local a = atan2(target.Z - run.PZ, target.X - run.PX)
			local shots = if servo.Cross then { a, a + math.pi / 2 } else { a }
			for _, angle in shots do
				local ex, ez = run.PX + cos(angle) * servo.Length, run.PZ + sin(angle) * servo.Length
				line(run, run.PX, run.PZ, ex, ez, servo.Width, scaled(run, servo.Damage), 3)
				run:Write("Fx", 0, run.PX, run.PZ, angle, servo.Length, servo.Width, GFX.Servo)
			end
		end
	end
	-- clock hand: a laser hand spinning around you
	local hand = ip.ClockHand
	if hand then
		perk.HandA = (perk.HandA + hand.Speed * dt) % TAU
		perk.HourA = (perk.HourA + hand.Speed * 0.35 * dt) % TAU
		perk.HandTick -= dt
		if perk.HandTick <= 0 then
			perk.HandTick = 0.15
			local hands = { { perk.HandA, hand.Length } }
			if hand.Hour then
				table.insert(hands, { perk.HourA, hand.Length * 0.65 })
			end
			for _, h in hands do
				local ex, ez = run.PX + cos(h[1]) * h[2], run.PZ + sin(h[1]) * h[2]
				local n = SpatialGrid.Query(run.Grid, (run.PX + ex) / 2, (run.PZ + ez) / 2, h[2] / 2 + hand.Width + MAX_ENEMY_R, scratch)
				local ux, uz = cos(h[1]), sin(h[1])
				for k = 1, n do
					local e = scratch[k]
					if e.Alive and not e.Phased and (perk.HandHit[e.Uid] or 0) <= now then
						local rx, rz = e.X - run.PX, e.Z - run.PZ
						local along = rx * ux + rz * uz
						if along >= 0 and along <= h[2] + e.Radius and math.abs(rx * uz - rz * ux) <= hand.Width + e.Radius then
							perk.HandHit[e.Uid] = now + 0.45
							run.Proc = true
							CM().Hit(run, e, scaled(run, hand.Damage), ux, uz, 2)
							run.Proc = false
						end
					end
				end
			end
		end
		if now >= (perk.HandClean or 0) then
			perk.HandClean = now + 5
			for uid, t in perk.HandHit do
				if t < now then
					perk.HandHit[uid] = nil
				end
			end
		end
	end
	-- lucky lever: pull it
	local lever = ip.LuckyLever
	if lever and every(perk, "LeverAt", now, lever.Every, 5) then
		local roll = run.Rng:NextNumber()
		local outcome
		if roll < lever.Jackpot * (if run.Synergies.GoldRush then 2 else 1) then
			outcome = "Jackpot"
			perk.JackpotUntil = now + lever.Time
			if lever.XP then
				for k = 1, 6 do
					local a = k * TAU / 6
					PK().SpawnGem(run, run.PX + cos(a) * 4, run.PZ + sin(a) * 4, GameConfig.XPNeeded(run.Level) * 0.04)
				end
			end
		elseif roll < 0.6 then
			outcome = "Coins"
			run:AddCoins(6)
		else
			outcome = "Heal"
			run:Heal(10)
		end
		run:Write("Fx", 0, run.PX, run.PZ, 0, 5, 0, if outcome == "Jackpot" then GFX.Jackpot else GFX.Reel)
		run:Event("Perk", { Key = "LuckyLever", Text = if outcome == "Jackpot" then "7-7-7 JACKPOT! x2 DAMAGE" elseif outcome == "Coins" then "COINS" else "SNACK", Duration = if outcome == "Jackpot" then lever.Time else nil })
	end
	-- king's crown: the next hit is crowned
	local crown = ip.KingsCrown
	if crown and not perk.Crowned then
		perk.CrownedAt = perk.CrownedAt or (now + crown.Every)
		if now >= perk.CrownedAt then
			perk.Crowned = true
		end
	end
	-- overlord's banner: troops march in
	local banner = ip.OverlordBanner
	if banner and every(perk, "BannerAt", now, banner.Every, 6) then
		perk.Troops = banner.Count
		perk.TroopsUntil = now + banner.Time
		perk.TroopBlast = banner.Blast
		run:Write("Fx", 0, run.PX, run.PZ, 0, 8, 0, GFX.Troops)
	end
	if perk.TroopBlast and perk.TroopsUntil > 0 and now >= perk.TroopsUntil then
		perk.TroopsUntil = 0
		for _, a in run.Allies do
			blast(run, a.X, a.Z, 5, scaled(run, perk.TroopBlast), 6, GFX.Bomb)
		end
	end
	-- death mark: marks the toughest elite / boss around
	local dm = ip.DeathMark
	if dm and every(perk, "MarkAt", now, dm.Every, 2) then
		local best, bestHP = nil, 0
		for _, e in run.Enemies do
			if e.Alive and (e.IsBoss or e.Elite) and not e.DeathMark and e.HP > bestHP then
				if (e.X - run.PX) ^ 2 + (e.Z - run.PZ) ^ 2 <= 45 * 45 then
					best, bestHP = e, e.HP
				end
			end
		end
		if best then
			best.DeathMark = { Hits = 0 }
			run:Write("Fx", 0, best.X, best.Z, 0, best.Radius * 1.5, 0, GFX.Marked)
		end
	end
	-- whoopee cushion: surrounded -> PFFFT
	local cushion = ip.WhoopeeCushion
	if cushion and now >= perk.WhoopeeCheck then
		perk.WhoopeeCheck = now + 0.5
		if now >= perk.WhoopeeAt and SpatialGrid.Query(run.Grid, run.PX, run.PZ, cushion.Range, scratch) >= cushion.Crowd then
			perk.WhoopeeAt = now + cushion.Every
			blast(run, run.PX, run.PZ, cushion.Radius, scaled(run, cushion.Damage), cushion.Knock, GFX.Whoopee)
			if cushion.Cloud then
				addPool(run, "Cloud", run.PX, run.PZ, cushion.Radius * 0.8, cushion.Cloud, { Slow = 0.5 })
			end
		end
	end
	-- second shadow
	local shadow = ip.SecondShadow
	if shadow and every(perk, "ShadowAt", now, shadow.Every, 5) then
		perk.ShadowUntil = now + shadow.Time
		perk.ShadowX, perk.ShadowZ = run.PX, run.PZ
		run:Write("Fx", 0, run.PX, run.PZ, 0, 4, 0, GFX.ShadowIn)
	end
end

-- SECOND SHADOW: follows you a few studs behind and fires copies of your projectiles
local function stepShadow(run, dt: number)
	local perk = run.Perk
	local now = run.Time
	if now >= perk.ShadowUntil then
		if perk.ShadowOn then
			perk.ShadowOn = false
			run:Write("Shadow", perk.ShadowX, perk.ShadowZ, 0)
		end
		return
	end
	perk.ShadowOn = true
	local tx, tz = run.PX - run.FX * 5 + run.FZ * 3, run.PZ - run.FZ * 5 - run.FX * 3
	local k = min(1, dt * 4)
	perk.ShadowX += (tx - perk.ShadowX) * k
	perk.ShadowZ += (tz - perk.ShadowZ) * k
	run:Write("Shadow", perk.ShadowX, perk.ShadowZ, 1)
	local shadow = run.IP.SecondShadow
	local mult = if shadow then shadow.Mult else 0.6
	local all = shadow and shadow.All
	local fired = 0
	for _, w in run.Weapons do
		local kind = w.Def.Kind
		if (kind == "Projectile" or kind == "Missile" or kind == "Boomerang") and (all or fired == 0) then
			fired += 1
			local t = (perk.ShadowTimers[w.Key] or 0) - dt * run.FireRateNow
			if t <= 0 then
				t = w.S.Cooldown
				CM().ShadowFire(run, w, perk.ShadowX, perk.ShadowZ, mult)
			end
			perk.ShadowTimers[w.Key] = t
		end
	end
end

function Perks.Step(run, dt: number)
	run.BoomBudget = 6
	stepMovement(run, dt)
	stepDefense(run, dt)
	stepItems(run, dt)
	stepPools(run, dt)
	stepShadow(run, dt)
	-- combo and streaks fade
	local perk = run.Perk
	if perk.Combo > 0 and run.Time - perk.ComboAt > 1.2 then
		perk.Combo = 0
	end
	if perk.Streak > 0 and run.Time - perk.StreakAt > 2 then
		perk.Streak = 0
		perk.StreakWaves = 0
	end
	-- the plating bar
	if perk.PlatingMax > 0 then
		local shown = floor(perk.Plating + 0.5)
		if shown ~= perk.PlatingSent then
			perk.PlatingSent = shown
			run:Write("Plating", shown, perk.PlatingMax)
		end
	end
	Perks.StepMult(run)
end

return Perks
