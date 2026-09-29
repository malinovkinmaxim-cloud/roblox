--[[
	MiniBosses - the MINI-BOSSES of 67 TOWN: their encounters (warn -> fight -> defeated / left),
	their lair behaviour and their fights. Who and when: shared/MiniBossData.lua and the run
	director (Sim/ArenaDirector.lua).

	An ENCOUNTER is one mini-boss event (the twins are one encounter with two bodies):
	  Warn   the lair lights up, "MINI-BOSS APPEARED" (WarnTime seconds)
	  Fight  the bodies are in the world; they guard their lair
	  done   Defeated (relics, XP, coins) / Left (never fought) / Escaped (TICK TOCK's alarm)

	Lair behaviour: a mini-boss comes for you when you are close (Aggro), never strays further
	than Leash from its lair, walks home and heals when you run away (Reset).

	Every attack is telegraphed on the ground (Bosses.Telegraph) so it can be dodged.
	Called by EnemyManager (Behavior "Champion") and ArenaDirector, which pass EnemyManager in.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local Protocol = require(Shared.Protocol)
local ArenaData = require(Shared.ArenaData)
local MiniBossData = require(Shared.MiniBossData)

local Bosses = require(script.Parent.Bosses)
local Pickups = require(script.Parent.Pickups)
local Relics = require(script.Parent.Relics)

local MiniBosses = {}

local sqrt, cos, sin, atan2, min, max, floor = math.sqrt, math.cos, math.sin, math.atan2, math.min, math.max, math.floor
local TAU = math.pi * 2
local GFX = Protocol.Fx
local ES = Protocol.EState
local SHAPE = Protocol.Shapes
local MF = Protocol.MiniFlags
local LAIR = MiniBossData.Lair
local DIRECTOR = MiniBossData.Director
local PLAYER_R = GameConfig.Player.Radius
local telegraph = Bosses.Telegraph

local function state(run, e, s: number)
	if e.VState ~= s then
		e.VState = s
		run:Write("EState", e.Id, s)
	end
end

local function windup(run, seconds: number): number
	return seconds * (run.Windup or 1)
end

---------------------------------------------------------------------------
-- encounters
---------------------------------------------------------------------------
export type Encounter = {
	Def: any,
	X: number,
	Z: number,
	Zone: string,
	Lair: any?,
	Stage: string,
	At: number,
	Bodies: { any },
	Reason: string,
	SpawnedAt: number,
	LastEngaged: number,
	AlarmAt: number?,
	Revive: any?,
	LastX: number,
	LastZ: number,
	Done: boolean?,
}

function MiniBosses.Active(run): { Encounter }
	return run.Map.Encounters
end

-- is this mini-boss (by MiniBossData key) out right now?
function MiniBosses.IsOut(run, key: string): boolean
	for _, enc in run.Map.Encounters do
		if enc.Def.Key == key then
			return true
		end
	end
	return false
end

-- "MINI-BOSS APPEARED": the encounter starts with a warning at its lair / spot
function MiniBosses.Summon(run, def, x: number, z: number, lair, reason: string): Encounter
	local zone = ArenaData.ZoneAt(x, z)
	local enc: Encounter = {
		Def = def,
		X = x,
		Z = z,
		Zone = zone.Key,
		Lair = lair,
		Stage = "Warn",
		At = run.Time + DIRECTOR.WarnTime,
		Bodies = {},
		Reason = reason,
		SpawnedAt = run.Time,
		LastEngaged = run.Time,
		LastX = x,
		LastZ = z,
	}
	table.insert(run.Map.Encounters, enc)
	run:Write("Fx", 0, x, z, 0, if lair then lair.R else 12, 0, GFX.MiniSpawn)
	run:Event("MiniBoss", {
		Phase = "Warn",
		Key = def.Key,
		Title = def.Title,
		Zone = zone.Key,
		ZoneName = zone.Name,
		X = x,
		Z = z,
		Delay = DIRECTOR.WarnTime,
		Hint = def.Hint,
		Reason = reason,
	})
	return enc
end

local function bodyIds(enc: Encounter): { number }
	local ids = {}
	for _, e in enc.Bodies do
		if e.Alive then
			table.insert(ids, e.Id)
		end
	end
	return ids
end

local function spawnBodies(run, enc: Encounter, EM)
	for i, key in enc.Def.Bodies do
		local x, z = enc.X, enc.Z
		local pads = enc.Lair and enc.Lair.Pads
		if pads and pads[i] then
			x, z = pads[i][1], pads[i][2]
		end
		local e = EM.Spawn(run, key, x, z, { Force = true, Encounter = enc, HomeX = x, HomeZ = z })
		if e then
			table.insert(enc.Bodies, e)
			run:Write("Fx", 0, x, z, 0, e.Radius * 3, 0, GFX.MiniSpawn)
		end
	end
	enc.Stage = "Fight"
	enc.SpawnedAt = run.Time
	enc.LastEngaged = run.Time
	local timer = nil
	if enc.Def.Key == "TickTock" and enc.Bodies[1] then
		timer = enc.Bodies[1].Def.Params.Timer
		enc.AlarmAt = run.Time + timer
	end
	run:Event("MiniBoss", {
		Phase = "Spawn",
		Key = enc.Def.Key,
		Title = enc.Def.Title,
		Zone = enc.Zone,
		Ids = bodyIds(enc),
		X = enc.X,
		Z = enc.Z,
		Timer = timer,
		Hint = enc.Def.Hint,
	})
end

local function anyAlive(enc: Encounter): boolean
	for _, e in enc.Bodies do
		if e.Alive then
			return true
		end
	end
	return false
end

local function remove(run, enc: Encounter)
	local list = run.Map.Encounters
	local i = table.find(list, enc)
	if i then
		table.remove(list, i)
	end
end

local function despawnAll(run, enc: Encounter, EM)
	for _, e in enc.Bodies do
		if e.Pylons then
			for _, py in e.Pylons do
				EM.Despawn(run, py)
			end
		end
		EM.Despawn(run, e)
	end
end

-- the rarity tier of an encounter's loot: its own, or the zone's when that is better
local function lootTier(enc: Encounter): number
	return max(enc.Def.Tier, ArenaData.ByKey[enc.Zone].LootTier)
end

local function reward(run, enc: Encounter)
	local def = enc.Def
	local x, z = enc.LastX, enc.LastZ
	local rng = run.Rng
	-- relics: the reason to hunt them
	for i = 1, def.Relics do
		local key = Relics.Roll(run, lootTier(enc))
		if key then
			local a = (i - 1) * 2.4 + 0.6
			local r = if def.Relics > 1 then 3.5 else 0
			Relics.Drop(run, key, x + cos(a) * r, z + sin(a) * r)
		end
	end
	-- a burst of XP (grows with the run: XP needs grow too)
	local xp = def.XP * (1 + run.Time / 120)
	for k = 1, 6 do
		local a = k * (TAU / 6) + rng:NextNumber(-0.3, 0.3)
		local r = rng:NextNumber(4, 7)
		Pickups.SpawnGem(run, x + cos(a) * r, z + sin(a) * r, xp / 6)
	end
	run:AddCoins(def.Coins)
	if rng:NextNumber() < 0.6 then
		Pickups.SpawnItem(run, "Snack", x + rng:NextNumber(-3, 3), z + rng:NextNumber(-3, 3))
	end
end

-- the encounter is over: Defeated / Left / Escaped
local function finish(run, enc: Encounter, outcome: string, EM)
	if enc.Done then
		return
	end
	enc.Done = true
	remove(run, enc)
	local def = enc.Def
	run.Map.Rest[def.Key] = run.Time + def.Cooldown
	if outcome == "Defeated" then
		reward(run, enc)
		run.Result.MiniBosses = (run.Result.MiniBosses or 0) + 1
		local sub = "Loot dropped. Grab the relic!"
		if def.Key == "TickTock" then
			local bonus = enc.Bodies[1] and enc.Bodies[1].Def.Params.OnTimeCoins or 0
			run:AddCoins(bonus)
			run.Result.Flags.OnTime = true
			sub = "Right on time! +" .. bonus .. " coins. Grab the relic!"
		end
		run:Event("MiniBoss", { Phase = "Defeated", Key = def.Key, Title = def.Title, X = enc.LastX, Z = enc.LastZ })
		run:Banner(def.Title .. " DEFEATED", sub, "Reward")
	else
		despawnAll(run, enc, EM)
		run:Event("MiniBoss", { Phase = outcome, Key = def.Key, Title = def.Title })
		if outcome == "Escaped" then
			run:Banner("THE ALARM RANG", def.Title .. " escaped with its loot.", "Info")
		else
			run:Banner(def.Title .. " LEFT", "It got bored of waiting.", "Info")
		end
	end
end

-- warn -> spawn, twins reviving, TICK TOCK's alarm, left alone too long
function MiniBosses.StepEncounters(run, EM)
	local now = run.Time
	for _, enc in table.clone(run.Map.Encounters) do
		if enc.Stage == "Warn" then
			if now >= enc.At then
				spawnBodies(run, enc, EM)
			end
		elseif not enc.Done then
			local revive = enc.Revive
			if revive and now >= revive.At then
				enc.Revive = nil
				if anyAlive(enc) then
					local e = EM.Spawn(run, revive.Key, revive.X, revive.Z, { Force = true, Encounter = enc, HomeX = revive.HomeX, HomeZ = revive.HomeZ })
					if e then
						-- back at half health (the bar shows the half that is missing)
						e.HP = e.MaxHP * 0.5
						for i, old in enc.Bodies do
							if old.Key == revive.Key and not old.Alive then
								enc.Bodies[i] = e
							end
						end
						run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 3, 0, GFX.TwinRevive)
						run:Event("MiniBoss", { Phase = "Revived", Key = enc.Def.Key, Id = e.Id, Body = revive.Key, Ids = bodyIds(enc) })
					end
				end
			end
			if enc.AlarmAt and now >= enc.AlarmAt then
				-- TICK TOCK: the alarm rings: a last ring of shots, and it is gone
				for _, e in enc.Bodies do
					if e.Alive then
						local p = e.Def.Params
						for i = 1, p.AlarmCount do
							local a = (i / p.AlarmCount) * TAU
							EM.Shoot(run, e.X, e.Z, cos(a) * p.AlarmSpeed, sin(a) * p.AlarmSpeed, 1.3, p.AlarmDamage * e.DmgScale, 4)
						end
						run:Write("Fx", 0, e.X, e.Z, 0, 14, 0, GFX.Alarm)
					end
				end
				finish(run, enc, "Escaped", EM)
			elseif now - enc.LastEngaged > LAIR.LeaveAfter then
				finish(run, enc, "Left", EM)
			end
		end
	end
end

-- a body died (EnemyManager.Kill)
function MiniBosses.OnKilled(run, e, EM)
	if e.Pylons then
		for _, py in e.Pylons do
			EM.Despawn(run, py)
		end
	end
	local enc = e.Encounter
	if not enc or enc.Done then
		return
	end
	enc.LastX, enc.LastZ = e.X, e.Z
	-- SIX & SEVEN: the other one brings this one back unless both go down together
	local twin = e.Def.Params.Twin
	if twin then
		for _, other in enc.Bodies do
			if other.Alive and other.Key == twin then
				local delay = e.Def.Params.ReviveTime
				enc.Revive = { Key = e.Key, X = e.X, Z = e.Z, HomeX = e.HomeX, HomeZ = e.HomeZ, At = run.Time + delay }
				run:Event("MiniBoss", { Phase = "Bond", Key = enc.Def.Key, Id = other.Id, Body = e.Key, Delay = delay })
				return
			end
		end
	end
	if not anyAlive(enc) then
		finish(run, enc, "Defeated", EM)
	end
end

-- HP bars over the mini-bosses (only what changed)
function MiniBosses.Flush(run)
	local now = run.Time
	for _, enc in run.Map.Encounters do
		for _, e in enc.Bodies do
			if e.Alive then
				local frac = floor(math.clamp(e.HP / e.MaxHP, 0, 1) * 65535)
				local flags = 0
				if e.Shielded then
					flags += MF.Shielded
				end
				if e.StunnedUntil and e.StunnedUntil > now then
					flags += MF.Stunned
				end
				if e.Enraged then
					flags += MF.Enraged
				end
				if e.GoingHome then
					flags += MF.Home
				end
				if frac ~= e.SentHP or flags ~= e.SentFlags then
					e.SentHP, e.SentFlags = frac, flags
					run:Write("MiniHP", e.Id, frac, flags)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- the fights
---------------------------------------------------------------------------
function MiniBosses.Init(run, e, opts)
	e.Encounter = opts.Encounter
	e.HomeX = opts.HomeX or e.X
	e.HomeZ = opts.HomeZ or e.Z
	e.Timers = {}
	e.Busy = 0
	e.SentHP = -1
	e.SentFlags = -1
	e.HandT = 0
	e.HandA = run.Rng:NextNumber(0, TAU)
	e.HourA = e.HandA + math.pi
	e.Ticks = 0
end

-- a point towards (x, z), but not further than `reach` from the lair
local function nearHome(e, x: number, z: number, reach: number): (number, number)
	local dx, dz = x - e.HomeX, z - e.HomeZ
	local d = sqrt(dx * dx + dz * dz)
	if d > reach then
		return e.HomeX + dx / d * reach, e.HomeZ + dz / d * reach
	end
	return x, z
end

local function timer(e, name: string, first: number): number
	local t = e.Timers[name]
	if t == nil then
		t = first
		e.Timers[name] = t
	end
	return t
end

local function barrage(run, e, count: number, radius: number, spread: number, delay: number, damage: number)
	local rng = run.Rng
	for i = 1, count do
		local x, z = run.PX, run.PZ
		if i > 1 then
			local a = rng:NextNumber(0, TAU)
			local r = rng:NextNumber(4, spread)
			x, z = run.PX + cos(a) * r, run.PZ + sin(a) * r
		end
		telegraph(run, e, SHAPE.Circle, x, z, 0, radius, 0, windup(run, delay) + (i - 1) * 0.1, damage, "Slam")
	end
end

local function ring(run, e, count: number, speed: number, damage: number, offset: number, EM)
	for i = 1, count do
		local a = offset + (i / count) * TAU
		EM.Shoot(run, e.X, e.Z, cos(a) * speed, sin(a) * speed, 1.3, damage, 4.5)
	end
end

local AI = {}

-- THE BIG QUACK: flops onto you (ring of drops + a slippery puddle), calls ducklings
function AI.BigQuack(run, e, dx, dz, d, dt, EM)
	local p = e.Def.Params
	if e.FlopT then
		e.FlopT += dt
		local f = min(1, e.FlopT / e.FlopDur)
		e.X = e.FromX + (e.ToX - e.FromX) * f
		e.Z = e.FromZ + (e.ToZ - e.FromZ) * f
		if f >= 1 then
			e.FlopT = nil
			e.Air = false
			state(run, e, ES.Normal)
			ring(run, e, p.DropCount, p.DropSpeed, p.DropDamage * e.DmgScale, run.Rng:NextNumber(0, TAU), EM)
			telegraph(run, e, SHAPE.Puddle, e.X, e.Z, 0, p.PuddleRadius, p.PuddleTime, 0.05, 0, nil, p.PuddleSlow)
			if e.Enraged then
				local a = run.Rng:NextNumber(0, TAU)
				telegraph(run, e, SHAPE.Puddle, e.X + cos(a) * 11, e.Z + sin(a) * 11, 0, p.PuddleRadius * 0.8, p.PuddleTime, 0.05, 0, nil, p.PuddleSlow)
			end
		end
		return 0, 0, 0
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	local rate = if e.Enraged then 1.45 else 1
	e.Timers.Flop = timer(e, "Flop", p.FlopEvery * 0.35) - dt * rate
	e.Timers.Duck = timer(e, "Duck", p.DucklingEvery * 0.6) - dt
	if e.Timers.Flop <= 0 then
		e.Timers.Flop = p.FlopEvery
		local tx, tz = nearHome(e, run.PX, run.PZ, LAIR.Leash + 8)
		local delay = windup(run, p.FlopDelay)
		telegraph(run, e, SHAPE.Circle, tx, tz, 0, p.FlopRadius, 0, delay, p.FlopDamage * e.DmgScale, "Land")
		e.FromX, e.FromZ, e.ToX, e.ToZ = e.X, e.Z, tx, tz
		e.FlopT, e.FlopDur = 0, delay
		e.Air = true
		state(run, e, ES.Dash)
		return 0, 0, 0
	elseif e.Timers.Duck <= 0 then
		e.Timers.Duck = p.DucklingEvery
		local bx, bz = -dx / d, -dz / d
		for i = 1, p.DucklingCount do
			EM.Spawn(run, "Duckling", e.X + bx * (e.Radius + i * 2.2), e.Z + bz * (e.Radius + i * 2.2), { Force = true })
		end
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 1
end

-- CARTZILLA: a chain of charges along red lines, spills behind, prices from the sky
local function aimCharge(run, e, p)
	local dx, dz = run.PX - e.X, run.PZ - e.Z
	local d = max(0.1, sqrt(dx * dx + dz * dz))
	e.DirX, e.DirZ = dx / d, dz / d
	local w = windup(run, p.DashWindup)
	e.DashAt = run.Time + w
	e.DashDamage = p.DashDamage * e.DmgScale
	telegraph(run, e, SHAPE.DashLine, e.X, e.Z, atan2(e.DirZ, e.DirX), p.DashLength, e.Radius * 2, w, 0)
	state(run, e, ES.Windup)
end

function AI.Cartzilla(run, e, dx, dz, d, dt, _EM)
	local p = e.Def.Params
	local now = run.Time
	if e.Dashing then
		local step = p.DashSpeed * dt
		e.DashLeft -= step
		e.SpillAcc += step
		if e.SpillAcc >= p.SpillEvery then
			e.SpillAcc = 0
			telegraph(run, e, SHAPE.Spill, e.X, e.Z, 0, p.SpillRadius, p.SpillTime, 0.05, p.SpillDamage * e.DmgScale)
		end
		if e.DashLeft <= 0 then
			e.Dashing = false
			state(run, e, ES.Normal)
			e.DashesLeft -= 1
			if e.DashesLeft > 0 then
				e.NextDashAt = now + 0.35
			end
		end
		return e.DirX, e.DirZ, p.DashSpeed / e.Speed
	end
	if e.DashAt then
		if now >= e.DashAt then
			e.DashAt = nil
			e.Dashing = true
			e.DashLeft = p.DashLength
			e.SpillAcc = 0
			state(run, e, ES.Dash)
			return e.DirX, e.DirZ, p.DashSpeed / e.Speed
		end
		return 0, 0, 0
	end
	if e.NextDashAt then
		if now >= e.NextDashAt then
			e.NextDashAt = nil
			aimCharge(run, e, p)
		end
		return 0, 0, 0
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	e.Timers.Charge = timer(e, "Charge", p.ChargeEvery * 0.3) - dt
	e.Timers.Price = timer(e, "Price", p.PriceEvery * 0.7) - dt
	if e.Timers.Charge <= 0 then
		e.Timers.Charge = p.ChargeEvery
		e.DashesLeft = p.Dashes + (if e.Enraged then 1 else 0)
		aimCharge(run, e, p)
		return 0, 0, 0
	elseif e.Timers.Price <= 0 then
		e.Timers.Price = p.PriceEvery
		barrage(run, e, p.PriceCount, p.PriceRadius, p.PriceSpread, p.PriceDelay, p.PriceDamage * e.DmgScale)
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 0.8
end

-- JACKPOT JIMMY: the reels decide; half-way down it tilts behind a shield of coin stacks
local REEL_ORDER = { "Ring", "Cross", "Bombs", "Jackpot" }

local function spinResult(run, p, shielded: boolean): string
	local total = 0
	for _, key in REEL_ORDER do
		if not (shielded and key == "Jackpot") then
			total += p.Reels[key] or 0
		end
	end
	local r = run.Rng:NextNumber(0, total)
	for _, key in REEL_ORDER do
		if not (shielded and key == "Jackpot") then
			r -= p.Reels[key] or 0
			if r <= 0 then
				return key
			end
		end
	end
	return "Ring"
end

local function resolveSpin(run, e, p, result: string, EM)
	local scale = e.DmgScale
	if result == "Ring" then
		ring(run, e, p.RingCount, p.RingSpeed, p.RingDamage * scale, run.Rng:NextNumber(0, TAU), EM)
		e.SecondRingAt = run.Time + 0.55
	elseif result == "Cross" then
		local base = run.Rng:NextNumber(0, math.pi)
		for i = 1, p.CrossCount do
			local a = base + (i - 1) * (math.pi / p.CrossCount)
			local half = p.CrossLength / 2
			telegraph(run, e, SHAPE.Laser, run.PX - cos(a) * half, run.PZ - sin(a) * half, a, p.CrossLength, p.CrossWidth, windup(run, p.CrossDelay) + (i - 1) * 0.15, p.CrossDamage * scale, "Sweep")
		end
	elseif result == "Bombs" then
		barrage(run, e, p.BombCount, p.BombRadius, p.BombSpread, p.BombDelay, p.BombDamage * scale)
	else
		-- 7-7-7: coins everywhere, and it is stunned (hit it now)
		for i = 1, p.JackpotCoins do
			local a = (i / p.JackpotCoins) * TAU
			Pickups.SpawnItem(run, "Coin", e.X + cos(a) * (e.Radius + 3), e.Z + sin(a) * (e.Radius + 3))
		end
		e.StunnedUntil = run.Time + p.StunTime
		run:Write("Fx", 0, e.X, e.Z, 0, 10, 0, GFX.Jackpot)
		run:Event("MiniBoss", { Phase = "Jackpot", Key = "JackpotJimmy", Id = e.Id, Time = p.StunTime })
	end
end

local function tilt(run, e, p, EM)
	e.Tilted = true
	e.Shielded = true
	e.Pylons = {}
	local base = run.Rng:NextNumber(0, TAU)
	for i = 1, p.PylonCount do
		local a = base + (i / p.PylonCount) * TAU
		local x, z = e.HomeX + cos(a) * p.PylonDistance, e.HomeZ + sin(a) * p.PylonDistance
		if EM.InsideCollider(run, x, z, 2) then
			x, z = e.HomeX + cos(a) * p.PylonDistance * 0.6, e.HomeZ + sin(a) * p.PylonDistance * 0.6
		end
		local py = EM.Spawn(run, "CoinStack", x, z, { Force = true })
		if py then
			py.Owner = e
			table.insert(e.Pylons, py)
		end
	end
	run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2, 0, GFX.Enrage)
	run:Event("MiniBoss", { Phase = "Shield", Key = "JackpotJimmy", Id = e.Id, Pylons = #e.Pylons })
	run:Banner("TILT!", "Break the " .. #e.Pylons .. " coin stacks to drop its shield", "MiniBoss")
end

function AI.JackpotJimmy(run, e, dx, dz, d, dt, EM)
	local p = e.Def.Params
	local now = run.Time
	if not e.Tilted and e.HP < e.MaxHP * p.ShieldAt then
		tilt(run, e, p, EM)
	end
	if e.Shielded then
		local standing = 0
		for _, py in e.Pylons do
			if py.Alive then
				standing += 1
			end
		end
		if standing == 0 then
			e.Shielded = false
			run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 3, 0, GFX.Jackpot)
			run:Event("MiniBoss", { Phase = "ShieldDown", Key = "JackpotJimmy", Id = e.Id })
		end
	end
	if e.SecondRingAt and now >= e.SecondRingAt then
		e.SecondRingAt = nil
		ring(run, e, p.RingCount, p.RingSpeed, p.RingDamage * e.DmgScale, run.Rng:NextNumber(0, TAU), EM)
	end
	if e.SpinAt and now >= e.SpinAt then
		e.SpinAt = nil
		state(run, e, ES.Normal)
		resolveSpin(run, e, p, e.SpinResult, EM)
	end
	if e.StunnedUntil and now < e.StunnedUntil then
		return 0, 0, 0
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	e.Timers.Spin = timer(e, "Spin", p.SpinEvery * 0.35) - dt * (if e.Shielded then 1.3 else 1)
	if e.Timers.Spin <= 0 and not e.SpinAt then
		e.Timers.Spin = p.SpinEvery
		e.SpinResult = spinResult(run, p, e.Shielded == true)
		e.SpinAt = now + p.SpinTime
		run:Event("Reels", { Id = e.Id, Result = e.SpinResult, Time = p.SpinTime })
		state(run, e, ES.Windup)
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 0.7
end

-- SIX: keeps its distance, fans out six shots
function AI.Six(run, e, dx, dz, d, dt, EM)
	local p = e.Def.Params
	if not e.Engaged then
		return 0, 0, 0
	end
	e.Timers.Fan = timer(e, "Fan", p.FanEvery * 0.5) - dt
	if e.Timers.Fan <= 0 then
		e.Timers.Fan = p.FanEvery
		local base = atan2(dz, dx)
		local n = p.FanShots
		for i = 1, n do
			local a = base + (i - (n + 1) / 2) * (p.FanSpread / (n - 1))
			EM.Shoot(run, e.X, e.Z, cos(a) * p.FanSpeed, sin(a) * p.FanSpeed, 1.2, p.FanDamage * e.DmgScale, 3.5)
		end
	end
	if d < p.Keep - 2 then
		return -dx / d, -dz / d, 1
	elseif d > p.Keep + 4 then
		return dx / d, dz / d, 1
	end
	return -dz / d * e.Side, dx / d * e.Side, 0.7
end

-- SEVEN: walks up to you and lays seven mines where you are heading
function AI.Seven(run, e, dx, dz, d, dt, _EM)
	local p = e.Def.Params
	if e.Busy > 0 then
		e.Busy -= dt
		if e.Busy <= 0 then
			state(run, e, ES.Normal)
		end
		return 0, 0, 0
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	e.Timers.Mine = timer(e, "Mine", p.MineEvery * 0.4) - dt
	if e.Timers.Mine <= 0 then
		e.Timers.Mine = p.MineEvery
		local fx, fz = run.FX, run.FZ
		local rng = run.Rng
		for i = 0, p.MineCount - 1 do
			local x = run.PX + fx * (2 + i * 4.5) + rng:NextNumber(-1, 1)
			local z = run.PZ + fz * (2 + i * 4.5) + rng:NextNumber(-1, 1)
			telegraph(run, e, SHAPE.Circle, x, z, 0, p.MineRadius, 0, windup(run, p.MineDelay) + i * 0.08, p.MineDamage * e.DmgScale, "Slam")
		end
		e.Busy = 0.45
		state(run, e, ES.Windup)
		return 0, 0, 0
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 1
end

-- TICK TOCK: two laser hands sweep around it while you are close; TOCK slams where you stand
function AI.TickTock(run, e, dx, dz, d, dt, _EM)
	local p = e.Def.Params
	if d < p.HandLength + 16 then
		e.HandT -= dt
		if e.HandT <= 0 then
			e.HandT = p.HandEvery
			e.Ticks += 1
			e.HandA += p.HandSpeed * p.HandEvery
			local delay = windup(run, p.HandDelay)
			telegraph(run, e, SHAPE.Laser, e.X, e.Z, e.HandA, p.HandLength, p.HandWidth, delay, p.HandDamage * e.DmgScale, "Sweep")
			if e.Ticks % 2 == 0 then
				-- the hour hand: shorter, slower, the other way round
				e.HourA -= p.HandSpeed * 0.5 * p.HandEvery * 2
				telegraph(run, e, SHAPE.Laser, e.X, e.Z, e.HourA, p.HandLength * 0.55, p.HandWidth, delay, p.HandDamage * e.DmgScale, "Sweep")
			end
		end
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	e.Timers.Tock = timer(e, "Tock", p.TockEvery * 0.5) - dt
	if e.Timers.Tock <= 0 then
		e.Timers.Tock = p.TockEvery
		telegraph(run, e, SHAPE.Circle, run.PX, run.PZ, 0, p.TockRadius, 0, windup(run, p.TockDelay), p.TockDamage * e.DmgScale, "Slam")
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 0.6
end

MiniBosses.AI = AI

-- movement intent for EnemyManager (Behavior "Champion"): dirX, dirZ, speed multiplier
function MiniBosses.Step(run, e, dx: number, dz: number, d: number, dt: number, EM): (number, number, number)
	local p = e.Def.Params
	-- rage (the attacks come faster)
	if p.EnrageAt and not e.Enraged and e.HP < e.MaxHP * p.EnrageAt then
		e.Enraged = true
		e.Speed *= 1.2
		run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2, 0, GFX.Enrage)
		run:Banner(p.Title .. " IS ANGRY", "It's getting serious", "MiniBoss")
	end
	-- you ran away: walk home and heal (nothing mid-leap / mid-charge)
	local hx, hz = e.HomeX, e.HomeZ
	local pdx, pdz = run.PX - hx, run.PZ - hz
	local busy = e.Air or e.Dashing or e.DashAt or e.NextDashAt or e.FlopT
	-- a big boss is coming / here: mini-bosses step back to their lair and wait (no pile-ups)
	local stage = run.Boss ~= nil or run.Wave.PendingBoss ~= nil
	if stage and not busy then
		e.Engaged = false
		if e.Encounter then
			e.Encounter.LastEngaged = run.Time -- waiting is not being ignored
		end
		local ox, oz = hx - e.X, hz - e.Z
		local home = sqrt(ox * ox + oz * oz)
		if home > 2 then
			return ox / home, oz / home, 1
		end
		return 0, 0, 0
	end
	if not busy and pdx * pdx + pdz * pdz > LAIR.Reset * LAIR.Reset then
		e.Engaged = false
		local ox, oz = hx - e.X, hz - e.Z
		local home = sqrt(ox * ox + oz * oz)
		e.GoingHome = true
		if home > 2 then
			return ox / home, oz / home, 1.2
		end
		e.HP = min(e.MaxHP, e.HP + e.MaxHP * LAIR.Regen * dt)
		return 0, 0, 0
	end
	e.GoingHome = false
	e.Engaged = d <= LAIR.Aggro
	local enc = e.Encounter
	if e.Engaged and enc then
		enc.LastEngaged = run.Time
	end
	local ai = AI[e.Key]
	local mx, mz, mult = 0, 0, 0
	if ai then
		mx, mz, mult = ai(run, e, dx, dz, d, dt, EM)
	end
	-- the leash: never too far from the lair (charges and leaps may overshoot, then come back)
	if not busy and not e.Air and not e.Dashing then
		local ox, oz = hx - e.X, hz - e.Z
		local home = sqrt(ox * ox + oz * oz)
		if home > LAIR.Leash then
			local k = math.clamp((home - LAIR.Leash) / 6, 0, 1)
			mx = mx * (1 - k) + ox / home * k
			mz = mz * (1 - k) + oz / home * k
			local len = sqrt(mx * mx + mz * mz)
			if len > 1e-3 then
				mx, mz = mx / len, mz / len
			end
			mult = max(mult, 0.8)
		end
	end
	return mx, mz, mult
end

return MiniBosses
