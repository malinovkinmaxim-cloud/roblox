--!nocheck
--[[
	Headless playtest: the REAL run simulation (src/server/Sim) played by tests/bot.luau.
	Prints a per-minute timeline (level, kills, enemies alive, HP, build) and the outcome.

	lune run tests/sim.luau [seeds=3] [hero=Rookie] [skill=1] [maxMinutes=17] [meta=0] [difficulty=2]
	(difficulty: tier 1..7, shared/DifficultyData.lua; 2 = HUNT, the classic balance)
	SIM_FROM=n starts at seed n (parallel runs), SIM_LOCKED=1 plays with no premium items.
]]

local process = require("@lune/process")
local Harness = require("./harness")
local Bot = require("./bot")

local seeds = tonumber(process.args[1]) or 3
local hero = process.args[2] or "Rookie"
local skill = tonumber(process.args[3]) or 1
local maxMinutes = tonumber(process.args[4]) or 17
local metaLevel = tonumber(process.args[5]) or 0
local difficulty = tonumber(process.args[6]) or 2

local Run = Harness.Require("ServerScriptService.Server.Sim.Run")
local LootData = Harness.Require("ReplicatedStorage.Modules.LootData")
local ItemData = Harness.Require("ReplicatedStorage.Modules.ItemData")
local WeaponData = Harness.Require("ReplicatedStorage.Modules.WeaponData")
local MetaData = Harness.Require("ReplicatedStorage.Modules.MetaData")

local unlocked = {}
for _, def in WeaponData.List do
	unlocked[def.Key] = true
end
local meta = {}
for _, def in MetaData.Upgrades do
	meta[def.Key] = math.min(def.MaxLevel, metaLevel)
end

local DT = 1 / 20
local outcomes = {}
-- premium items and boss relics: unlocked (a veteran account) unless SIM_LOCKED is set
local unlocks = {}
if not process.env.SIM_LOCKED then
	for _, def in ItemData.List do
		unlocks[def.Key] = true
	end
end
local chipsTotal = 0
local first = tonumber(process.env.SIM_FROM) or 1
for seed = first, first + seeds - 1 do
	local run = Run.new({ Seed = seed * 7919, Hero = hero, Unlocked = unlocked, Meta = meta, Difficulty = difficulty, ItemUnlocks = unlocks })
	local fightAt = {}
	local itemLog, synLog = {}, {}
	local nextReport = 60
	local maxEnemies, maxGems, maxProj = 0, 0, 0
	local stepTime, steps = 0, 0
	local levelAt = {}
	local bossAt, bossLog, eventLog, townLog = {}, {}, {}, {}
	local minHP = math.huge
	print(string.format("\n=== seed %d (%s, skill %.1f) ===", seed, hero, skill))
	while not run.Ended and run.Time < maxMinutes * 60 do
		local t0 = os.clock()
		Bot.Step(run, DT, skill)
		stepTime += os.clock() - t0
		steps += 1
		if steps % 2 == 0 then
			run:Flush()
			for _, ev in run:TakeEvents() do
				if ev.Name == "BossSpawn" then
					bossAt[ev.Payload.Key] = run.Time
				elseif ev.Name == "BossDefeated" then
					table.insert(bossLog, string.format("%s %.0fs (%.0fs fight)", ev.Payload.Key, run.Time, run.Time - (bossAt[ev.Payload.Key] or 0)))
				elseif ev.Name == "EvolutionReady" then
					table.insert(eventLog, string.format("EVO-READY %s@%.0f", ev.Payload.Evolution, run.Time))
				elseif ev.Name == "MiniBoss" and (ev.Payload.Phase == "Spawn" or ev.Payload.Phase == "Timer") then
					fightAt[ev.Payload.Key] = run.Time
				elseif ev.Name == "MiniBoss" and (ev.Payload.Phase == "Defeated" or ev.Payload.Phase == "Left" or ev.Payload.Phase == "Escaped") then
					table.insert(bossLog, string.format("%s %s %.0fs (%.0fs out)", ev.Payload.Key, ev.Payload.Phase, run.Time, run.Time - (fightAt[ev.Payload.Key] or run.Time)))
				elseif ev.Name == "MiniBoss" and ev.Payload.Phase ~= "Bond" and ev.Payload.Phase ~= "Exposed" then
					table.insert(townLog, string.format("%s:%s@%.0f", ev.Payload.Key, ev.Payload.Phase, run.Time))
				elseif ev.Name == "Item" then
					table.insert(itemLog, string.format("%s%s@%.0f", ev.Payload.Key, if ev.Payload.Level > 1 then " L" .. ev.Payload.Level else "", run.Time))
				elseif ev.Name == "Synergy" then
					table.insert(synLog, string.format("%s@%.0f", ev.Payload.Name, run.Time))
				elseif ev.Name == "Map" and (ev.Payload.Vault or ev.Payload.Rift or ev.Payload.Hot) then
					local what = if ev.Payload.Vault then "Vault" .. ev.Payload.Vault .. ":" .. tostring(ev.Payload.State) elseif ev.Payload.Rift then "RiftOpen" else "Rush:" .. tostring(ev.Payload.Hot)
					table.insert(townLog, string.format("%s@%.0f", what, run.Time))
				elseif ev.Name == "Event67" then
					table.insert(eventLog, string.format("%s@%.0f", ev.Payload.Key .. (if ev.Payload.Variant then "/" .. ev.Payload.Variant else ""), run.Time))
				end
			end
		end
		if run.HP < minHP then
			minHP = run.HP
		end
		maxEnemies = math.max(maxEnemies, #run.Enemies)
		maxGems = math.max(maxGems, #run.Gems)
		maxProj = math.max(maxProj, #run.Projectiles + #run.EnemyProjectiles)
		if not levelAt[run.Level] then
			levelAt[run.Level] = run.Time
		end
		if run.Time >= nextReport then
			nextReport += 60
			local weapons = {}
			for _, w in run.Weapons do
				table.insert(weapons, w.Key .. w.Level)
			end
			print(string.format(
				"%5.0fs  lvl %2d  kills %5d  alive %3d  hp %3d/%3d  boss %-14s  %s",
				run.Time,
				run.Level,
				run.Kills,
				#run.Enemies,
				math.floor(run.HP),
				run.Stats.MaxHP,
				if run.Boss then run.Boss.Key .. " " .. math.floor(run.Boss.HP / run.Boss.MaxHP * 100) .. "%" else "-",
				table.concat(weapons, " ")
			))
		end
	end
	local s = run:Summary()
	print(string.format(
		"END %s at %d s | level %d | kills %d | bosses %s | coins %d | max enemies %d gems %d proj %d | %.3f ms/step",
		s.Reason,
		s.Time,
		s.Level,
		s.Kills,
		table.concat(s.Bosses, ","),
		s.Coins,
		maxEnemies,
		maxGems,
		maxProj,
		stepTime / math.max(1, steps) * 1000
	))
	print(string.format("first level-up at %.1fs, level 5 at %.1fs, level 10 at %.1fs, level 20 at %.1fs", levelAt[2] or -1, levelAt[5] or -1, levelAt[10] or -1, levelAt[20] or -1))
	print("bosses: " .. table.concat(bossLog, " | "))
	print("events: " .. table.concat(eventLog, " "))
	local visited = {}
	for key in run.Map.Visited do
		table.insert(visited, key)
	end
	table.sort(visited)
	print("67 town: " .. table.concat(townLog, " "))
	local chips = LootData.ChipsFor(s.Time, s.BossSlots or {}, s.MainBoss == true, s.Elites or 0, 1)
	chipsTotal += chips
	print(string.format("bosses beaten %d, items %d, vaults %d, elites %d/%d, chips %d, zones %s", s.BossesBeaten or 0, #(s.Items or {}), s.Vaults or 0, s.Elites or 0, run.Result.ElitesSeen or 0, chips, table.concat(visited, ",")))
	print("items: " .. table.concat(itemLog, " "))
	print("synergies: " .. table.concat(synLog, " "))
	print(string.format("damage taken %d, lowest hp %d, rares %d, evolutions %s, fragments %d", s.DamageTaken, math.floor(minHP), s.Rares, table.concat(s.Evolutions, ","), s.Fragments))
	table.insert(outcomes, s)
end

local wins, total = 0, 0
for _, s in outcomes do
	total += s.Time
	if s.Victory then
		wins += 1
	end
end
print(string.format("\n%d/%d victories, average survival %.0f s, average chips %.0f", wins, #outcomes, total / #outcomes, chipsTotal / #outcomes))
