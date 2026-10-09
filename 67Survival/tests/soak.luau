--!nocheck
--[[
	Soak test: a FULL run (15 minutes of virtual time + THE FINAL ONE) with the real server +
	client, through the boss timeline to VICTORY, then a second run. Checks the performance
	budgets:
	  * server: enemies / gems / projectiles never exceed their caps, step time
	  * network: average and max frame size
	  * client: pooled models stay bounded, instance count does not grow between runs,
	    effect pools stay within budget, no runtime errors
	lune run tests/soak.luau [minutes=17]
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Engine = require("./engine")
local Bot = require("./bot")

local minutes = tonumber(process.args[1]) or 17

local passed, failed = 0, 0
local function check(name: string, condition: any, detail: any?)
	if condition then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FAIL " .. name .. (if detail ~= nil then " (" .. tostring(detail) .. ")" else ""))
	end
end

local server = Engine.StartServer()
local GM = Engine.Module(server, "ServerScriptService.Server.Services.GameManager")
local PM = Engine.Module(server, "ServerScriptService.Server.Services.PlayerManager")
local client, player = Engine.AddPlayer("Soaker")
Engine.Step(1)
local cd = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ClientData")
local runClient = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.RunClient")
local enemyRenderer = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.EnemyRenderer")
local effects = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.EffectsController")
local levelUp = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.LevelUpController")
local results = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ResultsController")
local pickups = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.PickupRenderer")
local weaponFx = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.WeaponFx")
local clientWS = client.Game:GetService("Workspace")

local function countWorkspace(): number
	return #rawget(clientWS, "__real"):GetDescendants()
end

local function oneRun(label: string, god: boolean)
	print("\n[" .. label .. "]")
	local mark = #Engine.Errors
	cd:Fire("StartRun")
	Engine.Step(0.5)
	local entry = GM.Entries[player]
	check("run started", entry ~= nil)
	local run = entry.Run
	if god then
		cd:Fire("Admin", "god", "")
	end
	local maxEnemies, maxGems, maxProj, maxEProj, maxItems = 0, 0, 0, 0, 0
	local maxFrame, maxNumbers, maxRings, maxPool = 0, 0, 0, 0
	local lastBytes, lastFrames = runClient.Stats.Bytes, runClient.Stats.Frames
	local real0 = os.clock()
	local nextReport = 60
	while not run.Ended and run.Time < minutes * 60 do
		if levelUp:IsOpen() and not levelUp.Busy then
			levelUp:Pick(Bot.Pick(run))
		end
		if not run:IsPaused() then
			local dx, dz = Bot.Direction(run, 1)
			local speed = run.Stats.WalkSpeed * 0.1
			Engine.MoveCharacter("Soaker", roblox.Vector3.new(run.PX + dx * speed, 3, run.PZ + dz * speed))
		end
		local bytesBefore = runClient.Stats.Bytes
		Engine.Step(0.1, 0.05)
		maxFrame = math.max(maxFrame, runClient.Stats.Bytes - bytesBefore)
		maxEnemies = math.max(maxEnemies, #run.Enemies)
		maxGems = math.max(maxGems, #run.Gems)
		maxProj = math.max(maxProj, #run.Projectiles)
		-- (a main boss of the bestiary gets ShotRoom more for its rings: Sim/EnemyManager.Shoot)
		maxEProj = math.max(maxEProj, #run.EnemyProjectiles - (run.ShotRoom or 0))
		maxItems = math.max(maxItems, #run.Drops)
		maxNumbers = math.max(maxNumbers, #effects.Numbers)
		maxRings = math.max(maxRings, #effects.Rings)
		maxPool = math.max(maxPool, enemyRenderer.Pool.Created)
		if run.Time >= nextReport then
			nextReport += 60
			local boss = run.Boss
			print(string.format(
				"  %4.0fs lvl %2d kills %5d enemies %3d pool %3d gems %3d ws %5d you %4.0f,%4.0f boss %s",
				run.Time, run.Level, run.Kills, #run.Enemies, enemyRenderer.Pool.Created, #run.Gems, countWorkspace(), run.PX, run.PZ,
				if boss then string.format("%s %d%% at %.0f,%.0f", boss.Key, math.floor(boss.HP / boss.MaxHP * 100), boss.X, boss.Z) else "-"
			))
		end
	end
	if not run.Ended then
		cd:Fire("GiveUp") -- still alive at the time cap: end it like a player would
	end
	Engine.Step(5)
	local frames = runClient.Stats.Frames - lastFrames
	local avg = (runClient.Stats.Bytes - lastBytes) / math.max(1, frames)
	print(string.format("  real %.1fs | max enemies %d gems %d proj %d eproj %d items %d | frame avg %d max %d bytes | numbers %d rings %d pool %d", os.clock() - real0, maxEnemies, maxGems, maxProj, maxEProj, maxItems, avg, maxFrame, maxNumbers, maxRings, maxPool))
	check("enemy cap respected", maxEnemies <= 440 + 80, maxEnemies) -- 67 INVASION raises the cap; forced spawns may exceed briefly
	check("gem cap respected", maxGems <= 180, maxGems)
	check("projectile cap respected", maxProj <= 120, maxProj)
	check("enemy projectile cap respected", maxEProj <= 70, maxEProj)
	check("pickup cap respected", maxItems <= 24, maxItems)
	check("average frame < 2.5 KB", avg < 2500, avg)
	check("largest frame < 12 KB", maxFrame < 12000, maxFrame)
	check("damage number budget", maxNumbers <= 40, maxNumbers)
	check("ring budget", maxRings <= 24, maxRings)
	-- models = alive + dying + parked; the renderer frees parked models above a small budget
	-- (EnemyRenderer PARKED_BUDGET), so the pool follows the horde instead of growing forever
	check("enemy model pool bounded", maxPool <= maxEnemies + 240, maxPool .. " models for " .. maxEnemies .. " enemies")
	check("no runtime errors", #Engine.Errors == mark, Engine.Errors[mark + 1])
	return run
end

local run1 = oneRun("full run (god mode) -> victory", true)
local slots = {}
for _, slot in run1.Result.BossSlots or {} do
	slots[slot] = (slots[slot] or 0) + 1
end
local twice = false
for _, n in slots do
	twice = twice or n > 1
end
check("bosses of the timeline beaten, each slot at most once", (run1.Result.BossesBeaten or 0) >= 2 and not twice, table.concat(run1.Result.Bosses, ","))
check("THE FINAL ONE defeated in its arena", run1.Result.MainBoss == true)
check("victory", run1.Victory == true, run1.EndReason)
check("results screen says VICTORY", results.Panel.Visible and results.ResultTitle.Text == "VICTORY", results.ResultTitle.Text)
local session = PM:Get(player)
check("win recorded", session.Data.Stats.Wins == 1)
check("Victory achievement unlocked (and the Survivor Crown with it)", session.Data.Achievements.Victory ~= nil and session.Data.Cosmetics.Owned["Hat.Crown"] == true)

-- back to the lobby, then a second run: nothing must pile up
results:Hide()
runClient:Leave()
cd:Fire("ReturnToLobby")
Engine.Step(2)
local wsAfterFirst = countWorkspace()
local poolAfterFirst = enemyRenderer.Pool.Created
check("client world cleaned after the run", enemyRenderer:Count() == 0 and next(pickups.Gems) == nil and next(weaponFx.Projectiles) == nil)

local run2 = oneRun("second run (normal)", false)
results:Hide()
runClient:Leave()
cd:Fire("ReturnToLobby")
Engine.Step(2)
local wsAfterSecond = countWorkspace()
print(string.format("  workspace instances after run 1: %d, after run 2: %d | pool %d -> %d", wsAfterFirst, wsAfterSecond, poolAfterFirst, enemyRenderer.Pool.Created))
check("no instance growth between runs (pools reused + trimmed)", wsAfterSecond <= wsAfterFirst + 300, wsAfterSecond - wsAfterFirst)
local keys = 0
for _ in enemyRenderer.Pool.Free do
	keys += 1
end
check("pool trimmed between runs (<= 24 parked models per enemy kind)", enemyRenderer.Pool.Created <= keys * 24, enemyRenderer.Pool.Created .. " models, " .. keys .. " kinds")
check("second run ended", run2.Ended)

print(string.format("\n%d passed, %d failed", passed, failed))
process.exit(if failed == 0 then 0 else 1)
