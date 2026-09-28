--!nocheck
--[[
	Headless playtest: the REAL run simulation (src/server/Sim) played by tests/bot.luau.
	Prints a per-minute timeline (level, kills, enemies alive, HP, build) and the outcome.

	lune run tests/sim.luau [seeds=3] [hero=Rookie] [skill=1] [maxMinutes=16] [meta=0]
]]

local process = require("@lune/process")
local Harness = require("./harness")
local Bot = require("./bot")

local seeds = tonumber(process.args[1]) or 3
local hero = process.args[2] or "Rookie"
local skill = tonumber(process.args[3]) or 1
local maxMinutes = tonumber(process.args[4]) or 16
local metaLevel = tonumber(process.args[5]) or 0

local Run = Harness.Require("ServerScriptService.Server.Sim.Run")
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
for seed = 1, seeds do
	local run = Run.new({ Seed = seed * 7919, Hero = hero, Unlocked = unlocked, Meta = meta })
	local nextReport = 60
	local maxEnemies, maxGems, maxProj = 0, 0, 0
	local stepTime, steps = 0, 0
	local levelAt = {}
	local bossAt, bossLog, eventLog = {}, {}, {}
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
print(string.format("\n%d/%d victories, average survival %.0f s", wins, #outcomes, total / #outcomes))
