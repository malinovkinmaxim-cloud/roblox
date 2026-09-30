--[[
	Elites - ELITES: rare, dangerous, worth hunting. An elite is NOT a boss: it is an enemy of
	the current wave made much tougher (GameConfig.Elite), with a ring, a name plate with its
	HP and 1-2 AFFIXES (shared/EnemyData.lua EliteAffixes) that change how it fights:
	  SWIFT     much faster          ARMORED   takes 35% less damage
	  VOLATILE  explodes when it dies (a telegraphed circle: step away)
	  SUMMONER  calls skitters       VAMPIRIC  heals when it hurts you, regenerates
	  FROST     its hits slow you

	The director (GameConfig.Elite): the first one after FirstAt, then a try every Every
	seconds (random), each try spawns one with Chance, never more than Max at once. Never in
	67 SQUARE or in a boss lair, never during THE FINAL ONE. A dangerous zone makes it tougher.
	The difficulty's Elite number makes tries come sooner; ELITE INVASION even more.

	Killing one pays: a burst of XP, coins, a chance of an ITEM (shared/LootData.lua Elite), a
	chance of a hero fragment, a SOUL (Soul Collector), Bounty Hunter's bonus.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local EnemyData = require(Shared.EnemyData)
local ArenaData = require(Shared.ArenaData)
local WaveData = require(Shared.WaveData)
local Protocol = require(Shared.Protocol)

local Pickups = require(script.Parent.Pickups)

local Elites = {}

local cos, sin, min, max, floor = math.cos, math.sin, math.min, math.max, math.floor
local TAU = math.pi * 2
local GFX = Protocol.Fx
local MF = Protocol.MiniFlags
local CFG = GameConfig.Elite

-- lazy: these modules require this one (through EnemyManager)
local function EM(): any
	return require(script.Parent.EnemyManager) :: any
end
local function Items(): any
	return require(script.Parent.Items) :: any
end

local function rate(run): number
	local r = if run.Diff then run.Diff.Elite else 1
	if run.Mods and run.Mods.EliteInvasion then
		r *= 1.4
	end
	return max(0.2, r)
end

function Elites.Init(run)
	run.Elites = {}
	local first = run.Rng:NextNumber(CFG.FirstAt[1], CFG.FirstAt[2])
	if run.Mods and run.Mods.EliteInvasion then
		first = 90
	end
	run.EliteAt = first
end

function Elites.MaxAlive(run): number
	local n = if run.Time >= CFG.LateAt then CFG.MaxLate else CFG.Max
	if run.Mods and run.Mods.EliteInvasion then
		n += 1
	end
	return n
end

-- an elite may not appear here: the square (the arena), a boss lair, a wall, the sealed rift
function Elites.Allowed(run, x: number, z: number): boolean
	local zone = ArenaData.ZoneAt(x, z)
	if zone.Key == "Square" then
		return false
	end
	if zone.Locked and not (run.Map and run.Map.RiftOpen) then
		return false
	end
	for _, lair in ArenaData.Lairs do
		if (lair.X - x) ^ 2 + (lair.Z - z) ^ 2 < (lair.R + 8) ^ 2 then
			return false
		end
	end
	return not EM().InsideCollider(run, x, z, 2)
end

local function spawnPoint(run): (number?, number?)
	local rng = run.Rng
	for _ = 1, 14 do
		local a = rng:NextNumber(0, TAU)
		local r = rng:NextNumber(CFG.Distance[1], CFG.Distance[2])
		local x, z = run.PX + cos(a) * r, run.PZ + sin(a) * r
		local h = GameConfig.Arena.HalfSize - 6
		if math.abs(x) <= h and math.abs(z) <= h and Elites.Allowed(run, x, z) then
			return x, z
		end
	end
	return nil, nil
end

-- a kind from the wave that is running now (the elite pool only)
local function pickKind(run): string
	local _, entry = WaveData.EntryAt(run.Time)
	local total, list = 0, {}
	for _, key in EnemyData.ElitePool do
		local w = entry.Mix[key]
		if w and w > 0 then
			total += w
			table.insert(list, { key, w })
		end
	end
	if total <= 0 then
		return "Husk"
	end
	local r = run.Rng:NextNumber(0, total)
	for _, item in list do
		r -= item[2]
		if r <= 0 then
			return item[1]
		end
	end
	return list[#list][1]
end

-- makes an elite now (the director, the debug menu). Returns it (nil when there is no room)
function Elites.Spawn(run, key: string?, atX: number?, atZ: number?, affixKeys: { string }?)
	if not atX or not atZ then
		atX, atZ = spawnPoint(run)
	end
	if not atX or not atZ then
		return nil
	end
	local x: number, z: number = atX, atZ
	key = key or pickKind(run)
	local zone = ArenaData.ZoneAt(x, z)
	local e = EM().Spawn(run, key, x, z, { Force = true, Elite = true, HPMult = zone.HP, DamageMult = zone.Damage })
	if not e then
		return nil
	end
	-- affixes
	local count = if run.Time >= CFG.LateAt then CFG.AffixesLate else CFG.Affixes
	local pool = table.clone(EnemyData.EliteAffixes)
	local chosen = {}
	if affixKeys then
		for _, k in affixKeys do
			local a = EnemyData.AffixByKey[k]
			if a then
				table.insert(chosen, a)
			end
		end
	else
		for _ = 1, count do
			if #pool == 0 then
				break
			end
			table.insert(chosen, table.remove(pool, run.Rng:NextInteger(1, #pool)))
		end
	end
	local names, keys = {}, {}
	for _, a in chosen do
		table.insert(names, a.Name)
		table.insert(keys, a.Key)
		if a.Speed then
			e.Speed *= a.Speed
		end
		if a.Armor then
			e.ArmorCut = a.Armor
		end
		if a.Leech then
			e.Leech, e.EliteRegen = a.Leech, a.Regen
		end
		if a.Chill then
			e.Chill = a.Chill
		end
		if a.Summon then
			e.Summon = a.Summon
			e.SummonAt = run.Time + a.Summon.Every * 0.5
		end
		if a.Blast then
			e.Volatile = a.Blast
		end
	end
	e.Affixes = keys
	e.SentHP, e.SentFlags = -1, -1
	table.insert(run.Elites, e)
	run.Result.ElitesSeen = (run.Result.ElitesSeen or 0) + 1
	run:Write("Fx", 0, x, z, 0, e.Radius * 2.5, 0, GFX.EliteSpawn)
	run:Event("Elite", {
		Phase = "Spawn",
		Id = e.Id,
		Key = key,
		Name = "ELITE " .. string.upper(e.Def.Name),
		Affixes = names,
		X = x,
		Z = z,
		Zone = zone.Key,
	})
	return e
end

local function alive(run): number
	local n = 0
	for _, e in run.Elites do
		if e.Alive then
			n += 1
		end
	end
	return n
end

-- the main boss fight: no elites (the arena is sealed)
local function quiet(run): boolean
	return not (run.Map and (run.Map.ArenaSealed or run.Map.MainOut))
end

function Elites.Step(run, dt: number)
	local now = run.Time
	-- the director
	if now >= run.EliteAt then
		run.EliteAt = now + run.Rng:NextNumber(CFG.Every[1], CFG.Every[2]) / rate(run)
		if quiet(run) and alive(run) < Elites.MaxAlive(run) and run.Rng:NextNumber() < CFG.Chance then
			if not Elites.Spawn(run) then
				run.EliteAt = now + 5 -- no free spot around you: soon again
			end
		end
	end
	-- affixes that act on their own
	local list = run.Elites
	local i = 1
	while i <= #list do
		local e = list[i]
		if not e.Alive then
			table.remove(list, i)
		else
			if e.Summon and now >= e.SummonAt then
				e.SummonAt = now + e.Summon.Every
				for k = 1, e.Summon.Count do
					local a = k * TAU / e.Summon.Count
					EM().Spawn(run, e.Summon.Key, e.X + cos(a) * (e.Radius + 2), e.Z + sin(a) * (e.Radius + 2), { Force = true })
				end
			end
			if e.EliteRegen and e.HP < e.MaxHP then
				e.HP = min(e.MaxHP, e.HP + e.MaxHP * e.EliteRegen * dt)
			end
			i += 1
		end
	end
end

-- it touched you and hurt you: vampiric heals, frost slows you
function Elites.OnTouch(run, touching: { any }, taken: number)
	for _, e in touching do
		if e.Elite and e.Alive then
			if e.Leech then
				e.HP = min(e.MaxHP, e.HP + e.MaxHP * e.Leech)
			end
			if e.Chill then
				run.ChillUntil = run.Time + e.Chill.Time
				run.ChillFactor = e.Chill.Factor
			end
		end
	end
	local _ = taken
end

function Elites.OnKilled(run, e, EM_)
	local rng = run.Rng
	local zone = ArenaData.ZoneAt(e.X, e.Z)
	run.Result.Elites = (run.Result.Elites or 0) + 1
	-- a burst of XP (Bounty Hunter: more)
	local bounty = run.UP and run.UP.BountyHunter
	local xp = e.Def.XP * CFG.XP * (if run.Map then zone.XP else 1) * (1 + (if bounty then bounty.XP else 0))
	for k = 1, 6 do
		local a = k * (TAU / 6) + rng:NextNumber(-0.3, 0.3)
		local r = rng:NextNumber(2.5, 5)
		Pickups.SpawnGem(run, e.X + cos(a) * r, e.Z + sin(a) * r, xp / 6)
	end
	run:AddCoins(CFG.Coins + (if bounty then bounty.Coins else 0))
	if bounty and bounty.Snack then
		Pickups.SpawnItem(run, "Snack", e.X + 2, e.Z)
		run.MagnetAll = true
	end
	if rng:NextNumber() < CFG.FragmentChance * min(3, run.Stats.Luck) then
		Pickups.SpawnItem(run, "Fragment", e.X - 2, e.Z)
	end
	-- an item, sometimes
	Items().DropFrom(run, "Elite", e.X, e.Z)
	-- VOLATILE: the corpse blows up (telegraphed)
	if e.Volatile then
		local Bosses = require(script.Parent.Bosses) :: any
		local b = e.Volatile
		Bosses.Telegraph(run, e, Protocol.Shapes.Circle, e.X, e.Z, 0, b.Radius, 0, b.Delay, b.Damage * e.DmgScale, "Slam")
		run:Write("Fx", 0, e.X, e.Z, 0, b.Radius, b.Delay, GFX.EliteBlast)
	end
	run:Event("Elite", { Phase = "Defeated", Id = e.Id, Key = e.Key })
	local _ = EM_
end

-- name plates: HP of the elites (only what changed)
function Elites.Flush(run)
	for _, e in run.Elites do
		if e.Alive then
			local frac = floor(math.clamp(e.HP / e.MaxHP, 0, 1) * 65535)
			local flags = if e.DeathMark then MF.Marked else 0
			if frac ~= e.SentHP or flags ~= e.SentFlags then
				e.SentHP, e.SentFlags = frac, flags
				run:Write("MiniHP", e.Id, frac, flags)
			end
		end
	end
end

return Elites
