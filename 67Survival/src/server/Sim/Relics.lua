--[[
	Relics - the RELICS of a run (shared/RelicData.lua): the loot lying on the ground, picking
	it up, and what every relic does.

	Hooks (called by the modules that own the moment):
	  Relics.Sources(run)        stat bonuses (Run:Sources)
	  Relics.ApplyWeapon(run, w) ability-type buffs (Run:RefreshStats)
	  Relics.DamageMult(run, e)  Champion Belt, Momentum Shoes (Run:DamageMult)
	  Relics.OnHit(run, e, dmg)  Pocket Sand, Static Sock (CombatManager.Hit)
	  Relics.CritMult(run, mult) Loaded 67 Dice (CombatManager.Hit, on a crit)
	  Relics.OnKill(run, e)      Boom Juice, Crown of 67 (Run:OnKill)
	  Relics.Thorns(run, list)   Cactus Hug (EnemyManager contact)
	  Relics.Step(run, dt)       dash charges, fire trail, Pocket Watch, loot pickup
	  Relics.Dash(run, dx, dz)   the DASH of the Rocket Skates (the client asks, this decides)

	Loot: Relics.Roll picks a relic for a loot tier (better tiers in dangerous zones, luck
	helps), Relics.Drop puts it on the ground (LootSpawn), walking over it takes it (Gain).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local RelicData = require(Shared.RelicData)
local ArenaData = require(Shared.ArenaData)
local Rarity = require(Shared.Rarity)
local Protocol = require(Shared.Protocol)
local WaveData = require(Shared.WaveData)

local SpatialGrid = require(script.Parent.SpatialGrid)

local Relics = {}

local sqrt, min, max, abs, cos, sin, atan2 = math.sqrt, math.min, math.max, math.abs, math.cos, math.sin, math.atan2
local GFX = Protocol.Fx
local BY_KEY = RelicData.ByKey
local PICKUP_R = 4 -- walk this close to a relic to take it (relics are not magnetized: go get them)
local MAX_ENEMY_R = 7.5
local scratch = {}

-- lazy: CombatManager and EnemyManager require this module
local combat: any, enemies: any = nil, nil
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

local function params(key: string): { [string]: any }
	return BY_KEY[key].Params or {}
end

-- damage that keeps up with the horde (enemy HP grows with run time)
local function scaled(run, base: number): number
	return base * run.Stats.Might * (1 + (WaveData.HPScale(run.Time) - 1) * 0.6)
end

function Relics.Init(run)
	run.Relics = {} -- key -> stacks
	run.RelicOrder = {}
	run.Loot = {} -- relics on the ground
	run.DashState = nil
	run.HitCount = 0
	run.MoveTime = 0
	run.TrailAt = 0
	run.TrailTick = 0
	run.Trail = {}
	run.WatchAt = nil
	run.CrownKills = 0
	run.BoomBudget = 6
end

function Relics.Stacks(run, key: string): number
	return run.Relics[key] or 0
end

---------------------------------------------------------------------------
-- stats
---------------------------------------------------------------------------
function Relics.Sources(run): { [string]: number }
	local out = {}
	for key, stacks in run.Relics do
		local def = BY_KEY[key]
		if def and def.Stats then
			for stat, value in def.Stats do
				out[stat] = (out[stat] or 0) + value * stacks
			end
		end
	end
	return out
end

local AREA_FIELDS = { "Radius", "Orbit", "Length", "Blast", "Explode" }

-- ability-type buffs (Slingshot Scope, Dog Treats, Brass Knuckles, Bucket Hat)
function Relics.ApplyWeapon(run, w)
	for key, stacks in run.Relics do
		local def = BY_KEY[key]
		if def and def.Effect == "Category" and def.Params and w.Def.Category == def.Params.Category then
			local p, s = def.Params, w.S
			if p.Damage then
				s.Damage = (s.Damage or 0) * (1 + p.Damage * stacks)
				if s.Burn then
					s.Burn *= 1 + p.Damage * stacks
				end
			end
			if p.Area then
				local k = 1 + p.Area * stacks
				for _, field in AREA_FIELDS do
					if s[field] then
						s[field] *= k
					end
				end
			end
			if p.Speed and s.Speed then
				s.Speed *= 1 + p.Speed * stacks
			end
			if p.Amount and not w.Def.NoAmount then
				s.Amount = (s.Amount or 1) + p.Amount * stacks
			end
		end
	end
end

function Relics.DamageMult(run, e): number
	local m = 1
	local belt = run.Relics.ChampionBelt
	if belt and e then
		local p = params("ChampionBelt")
		if e.IsBoss then
			m *= 1 + p.Boss * belt
		elseif e.Elite then
			m *= 1 + p.Elite * belt
		end
	end
	if run.Relics.MomentumShoes then
		local p = params("MomentumShoes")
		m *= 1 + p.Max * min(1, run.MoveTime / p.Build)
	end
	return m
end

-- Loaded 67 Dice: a crit can become a 6.7x hit. Returns the crit multiplier to use.
function Relics.CritMult(run, mult: number): number
	if run.Relics.Dice67 then
		local p = params("Dice67")
		if run.Rng:NextNumber() < p.Chance then
			return max(mult, p.Mult)
		end
	end
	return mult
end

---------------------------------------------------------------------------
-- hits and kills
---------------------------------------------------------------------------
-- up to `count` enemies closest to (x, z) inside `range`, never `skip`
local function closest(run, x: number, z: number, range: number, count: number, skip): { any }
	local n = SpatialGrid.Query(run.Grid, x, z, range + MAX_ENEMY_R, scratch)
	local picked = {}
	for _ = 1, count do
		local best, bestD = nil, range * range
		for i = 1, n do
			local o = scratch[i]
			if o ~= skip and o.Alive and not o.Phased and not o.Dormant and o.Key ~= "Crate" and not table.find(picked, o) then
				local dx, dz = o.X - x, o.Z - z
				local d = dx * dx + dz * dz
				if d < bestD then
					best, bestD = o, d
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

function Relics.OnHit(run, e, dmg: number)
	local relics = run.Relics
	local sand = relics.PocketSand
	if sand and e.Alive and not e.IsBoss then
		local p = params("PocketSand")
		if run.Rng:NextNumber() < p.Chance * sand then
			EM().Slow(e, p.Factor, p.Time, run.Time)
		end
	end
	local sock = relics.StaticSock
	if sock and not run.Zapping then
		local p = params("StaticSock")
		run.HitCount += 1
		if run.HitCount >= max(4, p.Every + p.EveryPerStack * (sock - 1)) then
			run.HitCount = 0
			local targets = closest(run, e.X, e.Z, p.Range, p.Targets, e)
			run.Zapping = true -- zaps don't count as hits for the next zap
			for _, t in targets do
				local dx, dz = t.X - e.X, t.Z - e.Z
				run:Write("Fx", 0, e.X, e.Z, atan2(dz, dx), sqrt(dx * dx + dz * dz), 0, GFX.Zap)
				CM().Hit(run, t, dmg * p.Share, dx, dz, 2)
			end
			run.Zapping = false
		end
	end
end

function Relics.OnKill(run, e)
	local relics = run.Relics
	local juice = relics.BoomJuice
	if juice and not run.Booming and run.BoomBudget > 0 then
		local p = params("BoomJuice")
		if run.Rng:NextNumber() < p.Chance + p.ChancePerStack * (juice - 1) then
			run.BoomBudget -= 1
			run.Booming = true -- one blast does not set off another (readable, not a screen wipe)
			run:Write("Fx", 0, e.X, e.Z, 0, p.Radius, 0, GFX.Bomb)
			CM().Area(run, e.X, e.Z, p.Radius, scaled(run, p.Damage), 6)
			run.Booming = false
		end
	end
	if relics.Crown67 then
		run.CrownKills += 1
		if run.CrownKills >= params("Crown67").Every then
			run.CrownKills = 0
			CM().Free67Blast(run)
		end
	end
end

-- Cactus Hug: whatever touches you gets hurt (twice a second at most)
function Relics.Thorns(run, touching: { any }?)
	local cactus = run.Relics.CactusHug
	if not cactus or not touching or run.Time < (run.CactusAt or 0) then
		return
	end
	run.CactusAt = run.Time + 0.5
	local p = params("CactusHug")
	local dmg = (p.Damage + run.Level * p.PerLevel) * cactus * run.Stats.Might
	run:Write("Fx", 0, run.PX, run.PZ, 0, 4, 0, GFX.Thorns)
	for _, e in touching do
		EM().Damage(run, e, dmg, 0, e.X - run.PX, e.Z - run.PZ, 5)
	end
end

---------------------------------------------------------------------------
-- dash
---------------------------------------------------------------------------
local function sendDash(run)
	local dash = run.DashState
	if dash then
		run:Write("Dash", dash.Charges, dash.Max, if dash.Charges < dash.Max then max(0, dash.Timer) else 0)
	end
end
Relics.SendDash = sendDash

-- true when the simulation must not put the player at (x, z): a wall, the arena edge, the
-- sealed rift
function Relics.Blocked(run, x: number, z: number): boolean
	local h = GameConfig.Arena.HalfSize - 3
	if abs(x) > h or abs(z) > h then
		return true
	end
	if run.Map and not run.Map.RiftOpen and ArenaData.ZoneAt(x, z).Locked then
		return true
	end
	return EM().InsideCollider(run, x, z, 1.2)
end

function Relics.Dash(run, dx: number, dz: number): boolean
	local dash = run.DashState
	if not dash or dash.Charges < 1 or run:IsPaused() or run.Dead or run.Ended then
		return false
	end
	if dx ~= dx or dz ~= dz then
		dx, dz = 0, 0
	end
	local len = sqrt(dx * dx + dz * dz)
	if len < 0.1 then
		dx, dz = run.FX, run.FZ -- no direction held: dash where you face
	else
		dx, dz = dx / len, dz / len
	end
	-- step along the line: stop in front of walls
	local x, z = run.PX, run.PZ
	local moved = 0
	for i = 1, math.floor(dash.Distance) do
		local nx, nz = run.PX + dx * i, run.PZ + dz * i
		if Relics.Blocked(run, nx, nz) then
			break
		end
		x, z, moved = nx, nz, i
	end
	if moved < 2 then
		return false
	end
	run:Write("Fx", 0, run.PX, run.PZ, atan2(dz, dx), moved, 0, GFX.Dash)
	run.PX, run.PZ = x, z
	run.FX, run.FZ = dx, dz
	run.TeleportTo = { X = x, Z = z }
	run.Invulnerable = max(run.Invulnerable, dash.Invulnerable)
	if dash.Charges >= dash.Max then
		dash.Timer = dash.Recharge
	end
	dash.Charges -= 1
	run.Result.Dashes = (run.Result.Dashes or 0) + 1
	sendDash(run)
	return true
end

---------------------------------------------------------------------------
-- loot
---------------------------------------------------------------------------
local function available(run, def): boolean
	if def.Secret or (run.Relics[def.Key] or 0) >= def.MaxStacks then
		return false
	end
	if def.Requires and (run.Relics[def.Requires] or 0) <= 0 then
		return false
	end
	-- one of it is already lying on the ground and that would max it out
	local lying = 0
	for _, l in run.Loot do
		if l.Key == def.Key then
			lying += 1
		end
	end
	return (run.Relics[def.Key] or 0) + lying < def.MaxStacks
end

-- a random relic for a loot tier (0..4), or nil when everything is maxed
function Relics.Roll(run, tier: number): string?
	local weights = RelicData.TierWeights[math.clamp(math.floor(tier), 0, 4)]
	local luck = run.Stats.Luck
	local pools = {}
	for _, def in RelicData.List do
		if weights[def.Rarity] and available(run, def) then
			pools[def.Rarity] = pools[def.Rarity] or {}
			table.insert(pools[def.Rarity], def.Key)
		end
	end
	local total = 0
	local function weightOf(rarity: string): number
		if not pools[rarity] then
			return 0
		end
		return weights[rarity] * max(0.2, 1 + (luck - 1) * (Rarity.LuckScale[rarity] or 0))
	end
	for _, rarity in RelicData.Tiers do
		total += weightOf(rarity)
	end
	if total <= 0 then
		-- the tier's rarities are all taken: anything still available
		for _, rarity in RelicData.Tiers do
			if pools[rarity] then
				local list = pools[rarity]
				return list[run.Rng:NextInteger(1, #list)]
			end
		end
		return nil
	end
	local r = run.Rng:NextNumber(0, total)
	for _, rarity in RelicData.Tiers do
		local w = weightOf(rarity)
		if w > 0 then
			r -= w
			if r <= 0 then
				local list = pools[rarity]
				return list[run.Rng:NextInteger(1, #list)]
			end
		end
	end
	return nil
end

-- puts a relic on the ground (out of walls)
function Relics.Drop(run, key: string, x: number, z: number)
	local def = BY_KEY[key]
	if not def then
		return
	end
	local h = GameConfig.Arena.HalfSize - 4
	x, z = math.clamp(x, -h, h), math.clamp(z, -h, h)
	for i = 0, 7 do
		if not EM().InsideCollider(run, x, z, 1) then
			break
		end
		local a = i * (math.pi / 4)
		x, z = math.clamp(x + cos(a) * 4, -h, h), math.clamp(z + sin(a) * 4, -h, h)
	end
	local loot = run.Loot
	if #loot >= GameConfig.Map.MaxLoot then
		local old = table.remove(loot, 1)
		run:Write("LootGone", old.Id)
	end
	run.NextLootId = (run.NextLootId or 0) % 65535 + 1
	local l = { Id = run.NextLootId, Key = key, X = x, Z = z, At = run.Time }
	table.insert(loot, l)
	run:Write("LootSpawn", l.Id, def.Id, x, z)
	return l
end

-- the relic is yours
function Relics.Gain(run, key: string)
	local def = BY_KEY[key]
	if not def then
		return
	end
	local stacks = run.Relics[key] or 0
	if stacks >= def.MaxStacks then
		run:AddCoins(25)
		run:Event("Relic", { Key = key, Stacks = stacks, Maxed = true })
		return
	end
	stacks += 1
	run.Relics[key] = stacks
	if stacks == 1 then
		table.insert(run.RelicOrder, key)
	end
	if def.Effect == "Dash" then
		local p = def.Params or {}
		local dash = run.DashState or { Charges = 0, Max = 0, Timer = 0, Recharge = p.Recharge, Distance = p.Distance, Invulnerable = p.Invulnerable }
		dash.Max += p.Charges
		dash.Charges += p.Charges
		run.DashState = dash
	elseif def.Effect == "DashCharge" and run.DashState then
		run.DashState.Max += 1
		run.DashState.Charges += 1
	end
	if def.Stats and def.Stats.Revives then
		run.Revives += def.Stats.Revives
	end
	run.Result.Relics = (run.Result.Relics or 0) + 1
	run:RefreshStats()
	run:SendLoadout()
	run:Write("Fx", 0, run.PX, run.PZ, 0, 6, def.Id, GFX.RelicTake)
	run:Event("Relic", { Key = key, Stacks = stacks })
	sendDash(run)
end

local function stepLoot(run)
	local loot = run.Loot
	local i = 1
	while i <= #loot do
		local l = loot[i]
		local dx, dz = l.X - run.PX, l.Z - run.PZ
		if dx * dx + dz * dz <= PICKUP_R * PICKUP_R then
			table.remove(loot, i)
			run:Write("LootTake", l.Id)
			Relics.Gain(run, l.Key)
		else
			i += 1
		end
	end
end

---------------------------------------------------------------------------
-- step
---------------------------------------------------------------------------
local function stepTrail(run, dt: number)
	local p = params("HotSauceSocks")
	local now = run.Time
	if run.Moved > 0.05 and now >= run.TrailAt then
		run.TrailAt = now + p.Every
		table.insert(run.Trail, { X = run.PX, Z = run.PZ, Until = now + p.Life })
		if #run.Trail > 12 then
			table.remove(run.Trail, 1)
		end
		run:Write("Fx", 0, run.PX, run.PZ, 0, p.Radius, p.Life, GFX.Trail)
	end
	run.TrailTick -= dt
	if run.TrailTick > 0 then
		return
	end
	run.TrailTick = 0.25
	local dps = scaled(run, p.Burn) * run.Stats.Burn
	local trail = run.Trail
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
					local dx, dz = e.X - patch.X, e.Z - patch.Z
					local rr = p.Radius + e.Radius
					if dx * dx + dz * dz <= rr * rr then
						CM().Burn(run, e, dps, p.BurnTime)
					end
				end
			end
			i += 1
		end
	end
end

local function stepWatch(run)
	local p = params("PocketWatch")
	local now = run.Time
	run.WatchAt = run.WatchAt or (now + 6)
	if now < run.WatchAt then
		return
	end
	run.WatchAt = now + p.Every
	local r2 = p.Radius * p.Radius
	local frozen = Protocol.EState.Frozen
	for _, e in run.Enemies do
		local dx, dz = e.X - run.PX, e.Z - run.PZ
		if dx * dx + dz * dz <= r2 and e.Behavior ~= "Static" then
			if e.IsBoss then
				EM().Slow(e, 0.4, p.Time, now)
			elseif not e.Air then
				e.FrozenUntil = now + p.Time
				e.Thaw = true
				run:Write("EState", e.Id, frozen)
			end
		end
	end
	run:Write("Fx", 0, run.PX, run.PZ, 0, p.Radius, 0, GFX.TimeStop)
end

function Relics.Step(run, dt: number)
	run.BoomBudget = 6
	if run.Moved > 0.05 then
		run.MoveTime += dt
	else
		run.MoveTime = 0
	end
	local dash = run.DashState
	if dash and dash.Charges < dash.Max then
		dash.Timer -= dt
		if dash.Timer <= 0 then
			dash.Charges += 1
			dash.Timer = if dash.Charges < dash.Max then dash.Recharge else 0
			sendDash(run)
		end
	end
	local relics = run.Relics
	if relics.HotSauceSocks then
		stepTrail(run, dt)
	end
	if relics.PocketWatch then
		stepWatch(run)
	end
	stepLoot(run)
end

return Relics
