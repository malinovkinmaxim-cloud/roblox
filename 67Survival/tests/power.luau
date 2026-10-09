--!nocheck
--[[
	Power of an ability, measured in the real simulation: the hero stands still (invulnerable)
	with only that ability, and the damage it deals in SECONDS is summed (burns, marks and its
	level mechanics included). Two scenes:
	  Crowd   CROWD enemies that never die walk at you from a ring (area / summon abilities)
	  Single  one enemy that never dies (a boss-like single target)
	The PREMIUM cap (shared/AbilityConfig.lua PowerCap): in both scenes, at level 1 and at max
	level, a premium ability never deals more than PowerCap x the best FREE ability of its
	Category (no evolutions, no premium) at the same level. tests/run.luau [premium] checks it;
	`lune run tools/power.luau` prints the table.
]]

local Harness = require("./harness")

local Run = Harness.Require("ServerScriptService.Server.Sim.Run")
local EnemyManager = Harness.Require("ServerScriptService.Server.Sim.EnemyManager")
local CombatManager = Harness.Require("ServerScriptService.Server.Sim.CombatManager")
local WeaponData = Harness.Require("ReplicatedStorage.Modules.WeaponData")
local Protocol = Harness.Require("ReplicatedStorage.Modules.Protocol")

local Power = {}

local DT = 1 / (tonumber(require("@lune/process").env.POWER_HZ) or 20)
Power.Seconds = 30
Power.Crowd = 40
local ENEMY = "Goober"
local HUGE = 1e8

local function scene(run, kind: string)
	local n = if kind == "Crowd" then Power.Crowd else 1
	local list = {}
	for i = 1, n do
		local a = (i / n) * math.pi * 2
		local d = if kind == "Crowd" then 10 + (i * 37) % 19 else 9
		local e = EnemyManager.Spawn(run, ENEMY, math.cos(a) * d, math.sin(a) * d, { Force = true, NoScale = true })
		e.HP, e.MaxHP = HUGE, HUGE
		table.insert(list, e)
	end
	return list
end

-- damage dealt by `key` at `level` in a scene ("Crowd" / "Single")
function Power.Measure(key: string, level: number, kind: string): number
	local run = Run.new({ Seed = 11, Hero = "Rookie", Unlocked = { [key] = true }, StartWeapon = key, Difficulty = 2 })
	assert(#run.Weapons == 1 and run.Weapons[1].Key == key, "only " .. key)
	run.Weapons[1].Level = level
	run:RefreshStats()
	run.Invulnerable = 1e9
	local list = scene(run, kind)
	local total = 0
	for _ = 1, math.floor(Power.Seconds / DT) do
		run.Time += DT
		run.Invulnerable = 1e9
		EnemyManager.Step(run, DT)
		CombatManager.Step(run, DT)
		for _, e in list do
			total += HUGE - e.HP
			e.HP = HUGE -- never dies
		end
		Protocol.Reset(run.Out) -- (records are not read)
		table.clear(run.Events)
	end
	return total
end

-- the free abilities (no evolution, no premium, no secret) of a category
function Power.FreeOf(category: string): { string }
	local out = {}
	for _, def in WeaponData.List do
		if def.Category == category and not def.Evolution and not def.Premium and def.Rarity ~= "Secret" then
			table.insert(out, def.Key)
		end
	end
	return out
end

-- { Key, Level, Scene, Premium = dmg, Best = best free dmg, BestKey, Ratio } for every premium ability
function Power.Table(): { any }
	local rows = {}
	local cache = {}
	local function measure(key, level, kind)
		local id = key .. ":" .. level .. ":" .. kind
		cache[id] = cache[id] or Power.Measure(key, level, kind)
		return cache[id]
	end
	for _, def in WeaponData.Premium do
		for _, level in { 1, def.MaxLevel } do
			for _, kind in { "Crowd", "Single" } do
				local best, bestKey = 0, nil
				for _, key in Power.FreeOf(def.Category) do
					local free = WeaponData.ByKey[key]
					local d = measure(key, math.min(level, free.MaxLevel), kind)
					if d > best then
						best, bestKey = d, key
					end
				end
				local mine = measure(def.Key, level, kind)
				table.insert(rows, { Key = def.Key, Level = level, Scene = kind, Premium = mine, Best = best, BestKey = bestKey, Ratio = mine / math.max(1, best) })
			end
		end
	end
	return rows
end

return Power
