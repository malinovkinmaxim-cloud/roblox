--[[
	ArenaDirector - 67 TOWN inside one run: the zone you are in and what it does to the horde,
	and the reasons to go somewhere else (the bosses have their own timeline: Sim/BossDirector).

	  ZONES     (shared/ArenaData) every zone scales the horde spawned around you (HP, damage,
	            its own enemies) and the XP / coins it drops. The square pays less after a
	            while ("picked clean"). First visit of a zone: a small XP bonus.
	  THE RIFT  sealed until ArenaData.RiftOpensAt, then the deadliest, best paying zone
	  67 RUSH   every ~2 minutes one zone pays x1.67 XP and double coins for 40 seconds
	  VAULTS    a 67 VAULT in a far corner wakes up: stand on it to crack it open (an ITEM,
	            shared/LootData.lua Vault)
	  SECRETS   the map's secret places also pay inside the run (once per run)
	The Compass item announces rushes and vaults ahead and opens vaults faster.

	Boss fights stay clear: no new rush / vault while a boss is being fought.
	Called by WaveManager.Step (the run's director) and by the systems it scales.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local Protocol = require(Shared.Protocol)
local ArenaData = require(Shared.ArenaData)

local MiniBosses = require(script.Parent.MiniBosses)
local Items = require(script.Parent.Items)
local Pickups = require(script.Parent.Pickups)

local ArenaDirector = {}

local sqrt, max, floor = math.sqrt, math.max, math.floor
local GFX = Protocol.Fx
local VS = Protocol.VaultState
local MAP = GameConfig.Map

function ArenaDirector.Init(run)
	local rng = run.Rng
	local zone = ArenaData.ZoneAt(run.PX, run.PZ)
	run.Map = {
		Zone = zone,
		Visited = { [zone.Key] = true },
		RiftOpen = false,
		Hot = nil,
		HotAt = MAP.HotFirstAt + rng:NextNumber(0, 20),
		Vaults = {},
		VaultAt = MAP.VaultFirstAt + rng:NextNumber(0, 15),
		Encounters = {}, -- bosses out right now (Sim/MiniBosses)
		Secrets = {},
		ArenaSealed = nil, -- { X, Z, R } while THE FINAL ONE's arena is sealed
		MainOut = nil,
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

-- no rush / vault / elite surprise while a boss is being fought
local function quiet(run): boolean
	return not MiniBosses.Fighting(run) and not run.Map.ArenaSealed
end

local function zoneOpen(run, zoneKey: string): boolean
	local zone = ArenaData.ByKey[zoneKey]
	return zone ~= nil and (not zone.Locked or run.Map.RiftOpen)
end

-- the Compass (level III) announces rushes and vaults this many seconds ahead
local function scout(run): number
	local compass = run.IP and run.IP.Compass
	return if compass then compass.Scout or 0 else 0
end

---------------------------------------------------------------------------
-- rush, vaults, the rift
---------------------------------------------------------------------------
local function openZones(run, except: string?): { string }
	local out = {}
	for _, zone in ArenaData.Zones do
		if zone.Stars > 0 and zone.Key ~= except and zoneOpen(run, zone.Key) then
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
	local ahead = scout(run)
	if ahead > 0 and not m.Hot and not m.HotNext and now >= m.HotAt - ahead then
		local list = openZones(run, m.Zone.Key)
		if #list > 0 then
			m.HotNext = list[run.Rng:NextInteger(1, #list)]
			run:Event("Map", { HotSoon = m.HotNext, Time = max(0, m.HotAt - now) })
		end
	end
	if not m.Hot and now >= m.HotAt then
		if not quiet(run) then
			m.HotAt = now + 8
			return
		end
		local list = openZones(run, m.Zone.Key)
		local next = m.HotNext
		m.HotNext = nil
		if next or #list > 0 then
			local key = next or list[run.Rng:NextInteger(1, #list)]
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
	-- the item pops out towards the middle of the map
	local d = sqrt(def.X * def.X + def.Z * def.Z)
	Items.DropFrom(run, "Vault", def.X - def.X / d * 6, def.Z - def.Z / d * 6)
	local _ = zone
	for k = 1, 5 do
		local a = k * 1.26
		Pickups.SpawnItem(run, "Coin", def.X + math.cos(a) * 4, def.Z + math.sin(a) * 4)
	end
	run.Result.Vaults = (run.Result.Vaults or 0) + 1
	run:Write("Fx", 0, def.X, def.Z, 0, 10, 0, GFX.VaultOpen)
	run:Event("Map", { Vault = i, State = "Opened" })
	run:Banner("67 VAULT OPENED", "An item popped out!", "Reward")
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
					local compass = run.IP and run.IP.Compass
					v.Progress += dt * (if compass and compass.VaultSpeed then compass.VaultSpeed else 1)
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
	-- a sleeping vault in an open zone, a walk away from you
	local function pickVault(): number?
		local options = {}
		for i, v in m.Vaults do
			local def = ArenaData.Vaults[i]
			local dx, dz = def.X - run.PX, def.Z - run.PZ
			if v.State == VS.Asleep and zoneOpen(run, def.Zone) and dx * dx + dz * dz > 60 * 60 then
				table.insert(options, i)
			end
		end
		return if #options > 0 then options[run.Rng:NextInteger(1, #options)] else nil
	end
	local ahead = scout(run)
	if ahead > 0 and not m.VaultNext and now >= m.VaultAt - ahead then
		m.VaultNext = pickVault()
		if m.VaultNext then
			run:Event("Map", { VaultSoon = m.VaultNext, Time = max(0, m.VaultAt - now) })
		end
	end
	if now >= m.VaultAt then
		if not quiet(run) then
			m.VaultAt = now + 8
			return
		end
		local i = m.VaultNext or pickVault()
		m.VaultNext = nil
		if i then
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
	if s.Item then
		Items.Drop(run, s.Item, x, z)
	end
	if s.Loot then
		Items.DropFrom(run, s.Loot, x, z)
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
end

function ArenaDirector.Step(run, dt: number)
	local m = run.Map
	local now = run.Time
	if not m.RiftOpen and now >= ArenaData.RiftOpensAt then
		m.RiftOpen = true
		run:Event("Map", { Rift = true })
		run:Banner("THE RIFT IS OPEN", "North of the square · x1.7 XP · deadly", "Rift")
	end
	stepZone(run)
	stepRush(run)
	stepVaults(run, dt)
end

-- the state a client needs when it (re)joins the run view
function ArenaDirector.Snapshot(run)
	local m = run.Map
	return { Rift = m.RiftOpen, Hot = if m.Hot then m.Hot.Zone else nil, Visited = table.clone(m.Visited) }
end

return ArenaDirector
