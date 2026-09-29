--[[
	ArenaDirector - 67 TOWN inside one run: the zone you are in and what it does to the horde,
	and the reasons to go somewhere else.

	  ZONES     (shared/ArenaData) every zone scales the horde spawned around you (HP, damage,
	            elites, its own enemies) and the XP / coins it drops. The square pays less
	            after a while ("picked clean"). First visit of a zone: a small XP bonus.
	  THREAT    kills inside a zone fill its threat meter: full = its mini-boss wakes up
	  MINI-BOSS the lure: every ~1:40 a mini-boss appears in a zone you are NOT in; reaching
	            level 10 / 20 calls one; TICK TOCK roams to a 67 SPOT (Sim/MiniBosses fights)
	  THE RIFT  sealed until ArenaData.RiftOpensAt, then the deadliest, best paying zone
	  67 RUSH   every ~2 minutes one zone pays x1.67 XP and double coins for 40 seconds
	  VAULTS    a 67 VAULT in a far corner wakes up: stand on it to crack it open (a relic)
	  SECRETS   the map's secret places also pay inside the run (once per run)

	Big boss moments stay clear: no new mini-boss / rush / vault around a boss warning.
	Called by WaveManager.Step (the run's director) and by the systems it scales.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local Protocol = require(Shared.Protocol)
local ArenaData = require(Shared.ArenaData)
local MiniBossData = require(Shared.MiniBossData)

local MiniBosses = require(script.Parent.MiniBosses)
local Relics = require(script.Parent.Relics)
local Pickups = require(script.Parent.Pickups)

local ArenaDirector = {}

local sqrt, max, floor = math.sqrt, math.max, math.floor
local GFX = Protocol.Fx
local VS = Protocol.VaultState
local DIRECTOR = MiniBossData.Director
local MAP = GameConfig.Map

-- lazy: EnemyManager requires this module
local enemies: any = nil
local function EM(): any
	if not enemies then
		enemies = require(script.Parent.EnemyManager) :: any
	end
	return enemies
end

function ArenaDirector.Init(run)
	local rng = run.Rng
	local zone = ArenaData.ZoneAt(run.PX, run.PZ)
	run.Map = {
		Zone = zone,
		Visited = { [zone.Key] = true },
		Threat = {}, -- zone key -> kills
		ThreatSent = -1,
		RiftOpen = false,
		Hot = nil,
		HotAt = MAP.HotFirstAt + rng:NextNumber(0, 20),
		Vaults = {},
		VaultAt = MAP.VaultFirstAt + rng:NextNumber(0, 15),
		LureAt = rng:NextNumber(DIRECTOR.FirstLure[1], DIRECTOR.FirstLure[2]),
		LevelLured = {},
		Encounters = {},
		Rest = {}, -- mini-boss key -> run time it can come back
		Secrets = {},
		QuietUntil = 0,
	}
	for i in ArenaData.Vaults do
		run.Map.Vaults[i] = { State = VS.Asleep, Until = 0, Progress = 0, Sent = 0 }
	end
end

---------------------------------------------------------------------------
-- zone effects
---------------------------------------------------------------------------
function ArenaDirector.Zone(run)
	return run.Map.Zone
end

function ArenaDirector.RiftOpen(run): boolean
	return run.Map.RiftOpen
end

-- XP of a gem dropped at (x, z)
function ArenaDirector.XPMult(run, x: number, z: number): number
	local zone = ArenaData.ZoneAt(x, z)
	local m = zone.XP
	if zone.Decay and run.Time >= zone.Decay.After then
		m = zone.Decay.XP
	end
	local hot = run.Map.Hot
	if hot and hot.Zone == zone.Key then
		m *= MAP.HotXP
	end
	return m
end

-- coin drop chance multiplier at (x, z)
function ArenaDirector.CoinMult(run, x: number, z: number): number
	local zone = ArenaData.ZoneAt(x, z)
	local hot = run.Map.Hot
	return zone.Coins * (if hot and hot.Zone == zone.Key then MAP.HotCoins else 1)
end

-- the horde may not appear here (the sealed rift)
function ArenaDirector.SpawnBlocked(run, x: number, z: number): boolean
	return not run.Map.RiftOpen and ArenaData.ZoneAt(x, z).Locked == true
end

-- a kill fills the threat meter of the zone it happened in
function ArenaDirector.OnKill(run, e)
	if e.IsBoss or e.Key == "Crate" then
		return
	end
	local zone = ArenaData.ZoneAt(e.X, e.Z)
	if zone.Threat then
		local threat = run.Map.Threat
		threat[zone.Key] = (threat[zone.Key] or 0) + 1
	end
end

---------------------------------------------------------------------------
-- mini-bosses: who, where
---------------------------------------------------------------------------
local function quiet(run): boolean
	return run.Boss == nil and run.Wave.PendingBoss == nil and run.Time >= run.Map.QuietUntil
end

local function zoneOpen(run, zoneKey: string): boolean
	local zone = ArenaData.ByKey[zoneKey]
	return zone ~= nil and (not zone.Locked or run.Map.RiftOpen)
end

-- can this mini-boss come out now? (forced: only "not already out" counts - debug)
local function ready(run, def, force: boolean?): boolean
	if MiniBosses.IsOut(run, def.Key) then
		return false
	end
	if force then
		return true
	end
	if run.Time < def.MinTime or run.Time < (run.Map.Rest[def.Key] or 0) then
		return false
	end
	return def.Zone == nil or zoneOpen(run, def.Zone)
end

-- a 67 SPOT for a roaming mini-boss: open zone, not too close, not too far
local function pickSpot(run): (number?, number?)
	local best, bestScore = nil, -math.huge
	for _, s in ArenaData.Spots do
		local x, z = s[1], s[2]
		if not ArenaDirector.SpawnBlocked(run, x, z) then
			local dx, dz = x - run.PX, z - run.PZ
			local d = sqrt(dx * dx + dz * dz)
			local score = -math.abs(d - 100) + run.Rng:NextNumber(0, 40)
			if d > 45 and score > bestScore then
				best, bestScore = s, score
			end
		end
	end
	if best then
		return best[1], best[2]
	end
	return nil, nil
end

-- summons a mini-boss (with where it goes); `away` = not in the zone you are in
local function summon(run, reason: string, away: boolean, only: string?, force: boolean?): boolean
	if #run.Map.Encounters >= DIRECTOR.MaxAlive and not force then
		return false
	end
	local here = run.Map.Zone.Key
	local last = run.Map.LastMini
	local candidates = {}
	-- variety (not the same one twice in a row) and a walk, not a trek
	local function weight(def, x: number, z: number): number
		local dx, dz = x - run.PX, z - run.PZ
		local d = sqrt(dx * dx + dz * dz)
		return def.Weight * (if def.Key == last then 0.3 else 1) / (1 + max(0, d - 170) / 80)
	end
	for _, def in MiniBossData.List do
		if (only == nil or def.Key == only) and ready(run, def, force) then
			if def.Zone then
				if not (away and def.Zone == here) then
					local lair = ArenaData.LairOfZone[def.Zone]
					table.insert(candidates, { Def = def, Lair = lair, X = lair.X, Z = lair.Z, Weight = weight(def, lair.X, lair.Z) })
				end
			elseif only or reason ~= "Threat" then
				local x, z = pickSpot(run)
				if x and z then
					table.insert(candidates, { Def = def, X = x, Z = z, Weight = weight(def, x, z) })
				end
			end
		end
	end
	if #candidates == 0 then
		return false
	end
	local total = 0
	for _, c in candidates do
		total += c.Weight
	end
	local r = run.Rng:NextNumber(0, total)
	local pick = candidates[#candidates]
	for _, c in candidates do
		r -= c.Weight
		if r <= 0 then
			pick = c
			break
		end
	end
	MiniBosses.Summon(run, pick.Def, pick.X, pick.Z, pick.Lair, reason)
	run.Map.LastMini = pick.Def.Key
	return true
end
ArenaDirector.Summon = summon

local function stepMiniBosses(run)
	local m = run.Map
	local now = run.Time
	-- the lure: one comes out somewhere else every now and then
	if now >= m.LureAt then
		if quiet(run) and summon(run, "Lure", true) then
			m.LureAt = now + run.Rng:NextNumber(DIRECTOR.LureGap[1], DIRECTOR.LureGap[2])
		else
			m.LureAt = now + 8
		end
	end
	-- levels 10 / 20 call one right away
	for _, level in DIRECTOR.LevelLures do
		if run.Level >= level and not m.LevelLured[level] and quiet(run) then
			if summon(run, "Level", true) then
				m.LevelLured[level] = true
				m.LureAt = max(m.LureAt, now + DIRECTOR.LureGap[1] * 0.6)
			end
		end
	end
	-- a full threat meter wakes the zone's own mini-boss
	for key, kills in m.Threat do
		local zone = ArenaData.ByKey[key]
		if zone.Threat and kills >= zone.Threat then
			local def = MiniBossData.ByZone[key]
			if def and ready(run, def) and quiet(run) and summon(run, "Threat", false, def.Key) then
				m.Threat[key] = 0
			else
				m.Threat[key] = zone.Threat -- full, waiting
			end
		end
	end
end

---------------------------------------------------------------------------
-- rush, vaults, the rift
---------------------------------------------------------------------------
local function openZones(run, except: string?): { string }
	local out = {}
	for _, zone in ArenaData.Zones do
		if zone.Threat and zone.Key ~= except and zoneOpen(run, zone.Key) then
			table.insert(out, zone.Key)
		end
	end
	return out
end

local function stepRush(run)
	local m = run.Map
	local now = run.Time
	if m.Hot and now >= m.Hot.Until then
		m.Hot = nil
		run:Event("Map", { Hot = false })
	end
	if not m.Hot and now >= m.HotAt then
		if not quiet(run) then
			m.HotAt = now + 8
			return
		end
		local list = openZones(run, m.Zone.Key)
		if #list > 0 then
			local key = list[run.Rng:NextInteger(1, #list)]
			local zone = ArenaData.ByKey[key]
			m.Hot = { Zone = key, Until = now + MAP.HotTime }
			run:Event("Map", { Hot = key, Time = MAP.HotTime })
			run:Banner("67 RUSH: " .. zone.Name, string.format("x%s XP and double coins for %ds", tostring(MAP.HotXP), MAP.HotTime), "Rush")
		end
		m.HotAt = now + run.Rng:NextNumber(MAP.HotEvery[1], MAP.HotEvery[2])
	end
end

local function sendVault(run, i: number, v)
	local pct = floor(math.clamp(v.Progress / ArenaData.VaultTime, 0, 1) * 100)
	run:Write("Vault", i, v.State, pct)
	v.Sent = pct
end

local function openVault(run, i: number, v)
	local def = ArenaData.Vaults[i]
	local zone = ArenaData.ByKey[def.Zone]
	v.State = VS.Opened
	sendVault(run, i, v)
	v.State = VS.Asleep
	v.Progress = 0
	-- the relic pops out towards the middle of the map
	local d = sqrt(def.X * def.X + def.Z * def.Z)
	local key = Relics.Roll(run, zone.LootTier)
	if key then
		Relics.Drop(run, key, def.X - def.X / d * 6, def.Z - def.Z / d * 6)
	end
	for k = 1, 5 do
		local a = k * 1.26
		Pickups.SpawnItem(run, "Coin", def.X + math.cos(a) * 4, def.Z + math.sin(a) * 4)
	end
	run.Result.Vaults = (run.Result.Vaults or 0) + 1
	run:Write("Fx", 0, def.X, def.Z, 0, 10, 0, GFX.VaultOpen)
	run:Event("Map", { Vault = i, State = "Opened" })
	run:Banner("67 VAULT OPENED", "A relic popped out!", "Reward")
end

local function stepVaults(run, dt: number)
	local m = run.Map
	local now = run.Time
	local pad2 = ArenaData.VaultPad * ArenaData.VaultPad
	for i, v in m.Vaults do
		if v.State == VS.Awake then
			local def = ArenaData.Vaults[i]
			if now >= v.Until then
				v.State = VS.Asleep
				v.Progress = 0
				sendVault(run, i, v)
				run:Event("Map", { Vault = i, State = "Closed" })
			else
				local dx, dz = run.PX - def.X, run.PZ - def.Z
				if dx * dx + dz * dz <= pad2 then
					v.Progress += dt
				else
					v.Progress = max(0, v.Progress - dt * 0.5)
				end
				if v.Progress >= ArenaData.VaultTime then
					openVault(run, i, v)
				else
					local pct = floor(v.Progress / ArenaData.VaultTime * 100)
					if math.abs(pct - v.Sent) >= 5 or (pct == 0 and v.Sent ~= 0) then
						sendVault(run, i, v)
					end
				end
			end
		end
	end
	if now >= m.VaultAt then
		if not quiet(run) then
			m.VaultAt = now + 8
			return
		end
		-- a sleeping vault in an open zone, a walk away from you
		local options = {}
		for i, v in m.Vaults do
			local def = ArenaData.Vaults[i]
			local dx, dz = def.X - run.PX, def.Z - run.PZ
			if v.State == VS.Asleep and zoneOpen(run, def.Zone) and dx * dx + dz * dz > 60 * 60 then
				table.insert(options, i)
			end
		end
		if #options > 0 then
			local i = options[run.Rng:NextInteger(1, #options)]
			local v = m.Vaults[i]
			local def = ArenaData.Vaults[i]
			v.State = VS.Awake
			v.Until = now + MAP.VaultAwake
			v.Progress = 0
			sendVault(run, i, v)
			run:Event("Map", { Vault = i, State = "Awake", Time = MAP.VaultAwake })
			run:Banner("A 67 VAULT WOKE UP", ArenaData.ByKey[def.Zone].Name .. ": stand on it to crack it open", "Vault")
		end
		m.VaultAt = now + run.Rng:NextNumber(MAP.VaultEvery[1], MAP.VaultEvery[2])
	end
end

---------------------------------------------------------------------------
-- secrets
---------------------------------------------------------------------------
-- a secret place of the map (the server saw the player there): pays once per run
function ArenaDirector.RunSecret(run, key: string): boolean
	local s = ArenaData.RunSecrets[key]
	local m = run.Map
	if not s or m.Secrets[key] or run.Ended then
		return false
	end
	m.Secrets[key] = true
	run.Result.Flags[key] = true
	local x, z = run.PX + run.FX * 3, run.PZ + run.FZ * 3
	if s.Relic then
		Relics.Drop(run, s.Relic, x, z)
	end
	if s.RelicTier then
		local relic = Relics.Roll(run, s.RelicTier)
		if relic then
			Relics.Drop(run, relic, x, z)
		end
	end
	if s.Coins then
		run:AddCoins(s.Coins)
	end
	run:Event("Secret", { Key = key, Title = s.Title, Sub = s.Sub })
	return true
end

---------------------------------------------------------------------------
-- step
---------------------------------------------------------------------------
local function stepZone(run)
	local m = run.Map
	local zone = ArenaData.ZoneAt(run.PX, run.PZ)
	if zone ~= m.Zone then
		m.Zone = zone
		m.ThreatSent = -1
		if not m.Visited[zone.Key] then
			m.Visited[zone.Key] = true
			-- a new place: a little XP for exploring
			local value = 3 + run.Level
			for k = 1, 3 do
				local a = k * 2.1
				Pickups.SpawnGem(run, run.PX + math.cos(a) * 3, run.PZ + math.sin(a) * 3, value)
			end
		end
		run:Event("Zone", { Key = zone.Key })
	end
	-- the threat meter of the zone you are in (for the zone chip)
	if zone.Threat then
		local kills = m.Threat[zone.Key] or 0
		local pct = floor(math.clamp(kills / zone.Threat, 0, 1) * 100)
		if pct ~= m.ThreatSent then
			m.ThreatSent = pct
			run:Write("Threat", zone.Index, pct)
		end
	end
end

function ArenaDirector.Step(run, dt: number)
	local m = run.Map
	local now = run.Time
	-- big boss moments stay clear
	if run.Wave.PendingBoss or run.Boss then
		m.QuietUntil = max(m.QuietUntil, now + DIRECTOR.QuietAfterBoss)
	end
	if not m.RiftOpen and now >= ArenaData.RiftOpensAt then
		m.RiftOpen = true
		run:Event("Map", { Rift = true })
		run:Banner("THE RIFT IS OPEN", "North of the square · x1.7 XP · deadly", "Rift")
	end
	stepZone(run)
	stepMiniBosses(run)
	MiniBosses.StepEncounters(run, EM())
	stepRush(run)
	stepVaults(run, dt)
end

-- the state a client needs when it (re)joins the run view
function ArenaDirector.Snapshot(run)
	local m = run.Map
	return { Rift = m.RiftOpen, Hot = if m.Hot then m.Hot.Zone else nil, Visited = table.clone(m.Visited) }
end

return ArenaDirector
