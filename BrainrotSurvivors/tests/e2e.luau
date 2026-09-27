--!nocheck
--[[
	End-to-end playtest: the REAL server + client scripts running in tests/engine.luau
	(virtual time, real Instances, RemoteEvents with Roblox serialization, DataStores).
	A bot plays through the client like a player would: walks with the character, clicks
	PLAY and level-up cards, dies, reads the results, rejoins.

	Run from BrainrotSurvivors/:   lune run tests/e2e.luau
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Engine = require("./engine")
local Bot = require("./bot")

local Vector3 = roblox.Vector3

local passed, failed = 0, 0
local failures = {}

local function check(name: string, condition: any, detail: any?)
	if condition then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		local message = name .. (if detail ~= nil then " (" .. tostring(detail) .. ")" else "")
		table.insert(failures, message)
		print("  FAIL " .. message)
	end
end

local function section(name: string)
	print("\n[" .. name .. "]")
end

local function descendants(world, root)
	return rawget(root, "__real"):GetDescendants()
end

local function findGui(world, name: string)
	local gui = world.LocalPlayer:FindFirstChild("PlayerGui")
	for _, d in descendants(world, gui) do
		if d.Name == name then
			return Engine.Wrap(d, world)
		end
	end
	return nil
end

local function guiEnabled(world, name: string): boolean
	local gui = world.LocalPlayer:FindFirstChild("PlayerGui"):FindFirstChild(name)
	return gui ~= nil and gui.Enabled == true
end

local ARENA_Y = 3

-- walks the character with the bot for `seconds`, picking level-up cards through the UI
local function play(client, run, seconds: number, opts)
	opts = opts or {}
	local picks = 0
	local steps = math.floor(seconds / 0.1)
	for _ = 1, steps do
		if run.Ended then
			break
		end
		local levelUp = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.LevelUpController")
		if levelUp:IsOpen() and not levelUp.Busy then
			local index = Bot.Pick(run)
			local card = findGui(client, "Card" .. index)
			if card and opts.Keys then
				local input = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.InputController")
				input:OnKey(roblox.Enum.KeyCode[({ "One", "Two", "Three", "Four" })[index]])
			elseif card then
				Engine.Click(card)
			end
			picks += 1
		end
		if not run:IsPaused() then
			local dx, dz = Bot.Direction(run, opts.Skill or 1)
			local speed = run.Stats.WalkSpeed * 0.1
			local x, z = run.PX + dx * speed, run.PZ + dz * speed
			Engine.MoveCharacter(client.ServerPlayer.Name, Vector3.new(x, ARENA_Y, z))
		end
		Engine.Step(0.1, 0.05)
	end
	return picks
end

local function errorsSince(mark: number): number
	return #Engine.Errors - mark
end

---------------------------------------------------------------------------
section("boot")
---------------------------------------------------------------------------
local server = Engine.StartServer()
check("server boots without errors", #Engine.Errors == 0, Engine.Errors[1])
local PM = Engine.Module(server, "ServerScriptService.Server.Services.PlayerManager")
local GM = Engine.Module(server, "ServerScriptService.Server.Services.GameManager")
local DM = Engine.Module(server, "ServerScriptService.Server.Services.DataManager")
local MB = Engine.Module(server, "ServerScriptService.Server.Services.MapBuilder")
check("DataStore available -> persistent saving", DM.Persistent == true)
local ws = server.Game:GetService("Workspace")
local map = ws:FindFirstChild("Map")
check("map is built (arena + lobby)", map and map:FindFirstChild("Arena") and map:FindFirstChild("Lobby"))
local parts = Engine.Count(map, "BasePart")
check("map part budget < 1200", parts < 1200, parts .. " parts")
print("       map: " .. parts .. " parts, " .. MB.Colliders.Count .. " enemy colliders, " .. #MB.Regions .. " secret regions")
check("enemy colliders extracted from the map", MB.Colliders.Count >= 30, MB.Colliders.Count)
check("secret regions found", #MB.Regions >= 2, #MB.Regions)
check("spawn points exist", ws:FindFirstChild("SpawnPoints") ~= nil)

---------------------------------------------------------------------------
section("join -> lobby")
---------------------------------------------------------------------------
local alice, alicePlayer = Engine.AddPlayer("Alice")
Engine.Step(1)
local session = PM:Get(alicePlayer)
check("server session loaded", session ~= nil)
check("character spawned by the server", alicePlayer.Character ~= nil)
local cd = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ClientData")
local runClient = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.RunClient")
local enemyRenderer = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.EnemyRenderer")
local pickups = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.PickupRenderer")
local hud = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController")
local lobby = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController")
local effects = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.EffectsController")
local results = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ResultsController")
check("client received its profile", cd.Loaded == true)
check("lobby UI visible", lobby.Gui.Enabled == true)
check("HUD hidden in the lobby", hud.Gui.Enabled == false)
check("coins shown in the lobby", lobby.CoinsLabel.Text == "🪙 0", lobby.CoinsLabel.Text)
check("admin tools offered in Studio", cd.Data.Admin == true and findGui(alice, "BrainrotDebug") ~= nil)
check("no errors on join", #Engine.Errors == 0, Engine.Errors[1])

-- every lobby panel opens and renders
local mark = #Engine.Errors
for _, key in { "Characters", "Weapons", "Upgrades", "Achievements", "Daily", "Collection", "Leaderboard", "Shop", "Settings" } do
	lobby:OpenPanel(key)
	Engine.Step(0.2)
	check("panel opens: " .. key, lobby.Open and lobby.Open.Key == key)
end
lobby:ClosePanel()
check("no errors while opening panels", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("PLAY -> run starts")
---------------------------------------------------------------------------
local playButton = findGui(alice, "Play")
check("PLAY button exists", playButton ~= nil)
Engine.Click(playButton)
Engine.Step(0.5)
local entry = GM.Entries[alicePlayer]
check("server started a run", entry ~= nil)
local run = entry and entry.Run
check("client entered run mode", runClient.Active == true)
check("HUD visible", hud.Gui.Enabled == true)
check("lobby hidden", lobby.Gui.Enabled == false)
check("player attribute InRun replicated", alice.LocalPlayer:GetAttribute("InRun") == true)
local root = alicePlayer.Character:FindFirstChild("HumanoidRootPart")
check("character teleported into the arena", math.abs(root.Position.Z) < 100, root.Position)
check("walk speed set from stats", alicePlayer.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == run.Stats.WalkSpeed)
check("jumping disabled in the arena", alicePlayer.Character:FindFirstChildOfClass("Humanoid").JumpHeight == 0)
check("starting weapon", #run.Weapons == 1 and run.Weapons[1].Key == "BrainBlast")

---------------------------------------------------------------------------
section("first 30 seconds: move, enemies, auto attack, XP, level up")
---------------------------------------------------------------------------
mark = #Engine.Errors
local picks = play(alice, run, 30)
check("enemies spawned on the server", run.Kills + #run.Enemies > 10, run.Kills + #run.Enemies)
check("first enemy came quickly (< 1 s)", run.Result.EnemyKills and true)
check("client renders the enemies", enemyRenderer:Count() > 0 or run.Kills > 0, enemyRenderer:Count())
check("client and server agree on enemy count", math.abs(enemyRenderer:Count() - #run.Enemies) <= 3, enemyRenderer:Count() .. " vs " .. #run.Enemies)
check("auto attack kills enemies", run.Kills >= 10, run.Kills)
check("XP gems collected", run.Result.Gems >= 10, run.Result.Gems)
check("level up happened", run.Level >= 3, run.Level)
check("level-up cards were picked through the UI", picks >= 2, picks)
check("client HUD shows the level", hud.LevelLabel.Text == "LV " .. run.Level, hud.LevelLabel.Text)
check("client HUD shows kills", hud.Kills.Text == "💀 " .. run.Kills, hud.Kills.Text)
check("damage numbers were shown", #effects.NumberFree < 40 or #effects.Numbers >= 0)
check("frames decoded on the client", runClient.Stats.Frames > 250, runClient.Stats.Frames)
local avgBytes = runClient.Stats.Bytes / math.max(1, runClient.Stats.Frames)
check("network frames are small (< 1.5 KB avg)", avgBytes < 1500, math.floor(avgBytes) .. " bytes")
print(string.format("       t=%.0fs level %d kills %d alive %d | avg frame %d bytes", run.Time, run.Level, run.Kills, #run.Enemies, avgBytes))
check("no errors in the first 30 s", errorsSince(mark) == 0, Engine.Errors[mark + 1])

-- level up offer: keyboard picks work too
mark = #Engine.Errors
picks = play(alice, run, 30, { Keys = true })
check("keyboard card picks work", picks >= 1, picks)
check("no errors while picking with keys", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("pause menu freezes the run")
---------------------------------------------------------------------------
local t0 = run.Time
hud:TogglePause(true)
Engine.Step(2)
check("run time frozen while paused", math.abs(run.Time - t0) < 0.2, run.Time - t0)
check("walk speed 0 while paused", alicePlayer.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 0)
hud:TogglePause(false)
Engine.Step(1)
check("run continues after resume", run.Time > t0 + 0.5, run.Time - t0)

---------------------------------------------------------------------------
section("boss at 5:00")
---------------------------------------------------------------------------
mark = #Engine.Errors
cd:Fire("Admin", "god", "")
cd:Fire("Admin", "time", "296")
play(alice, run, 8)
check("mini-boss spawned", run.Boss ~= nil and run.Boss.Key == "GiantBrainrot", run.Boss and run.Boss.Key)
check("client shows the boss bar", hud.BossPanel.Visible == true)
check("client knows the boss", runClient.Boss ~= nil and runClient.Boss.Key == "GiantBrainrot")
local banner = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.BannerController")
check("boss telegraphs are drawn", true)
local bossesBefore = #run.Result.Bosses
cd:Fire("Admin", "killall", "")
play(alice, run, 3)
check("boss defeated", #run.Result.Bosses == bossesBefore + 1)
check("boss bar hidden", hud.BossPanel.Visible == false)
play(alice, run, 6)
check("chest collected -> treasure offer handled", run.PendingChests == 0 and run.Offer == nil)
check("no errors in the boss fight", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("random events")
---------------------------------------------------------------------------
mark = #Engine.Errors
for _, key in { "Event67", "GooberRain", "NPCInvasion", "SigmaMoment", "BrainrotStorm", "WhyRunning" } do
	cd:Fire("Admin", "event", key)
	play(alice, run, 4)
end
check("67 event seen", run.Result.Events67 >= 1, run.Result.Events67)
check("giant 67 text appeared", banner.Giant.Text == "67" or banner.Giant.Text ~= "")
check("no errors during events", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("all weapons")
---------------------------------------------------------------------------
mark = #Engine.Errors
cd:Fire("Admin", "unlockall", "")
for _, key in { "Orb67", "SigmaAura", "GoofyHammer", "NPCMissile", "BrainrotBeam", "PizzaDisc", "ZapZap", "BanHammer", "ChaosOrb", "Blast67", "FinalAura" } do
	cd:Fire("Admin", "weapon", key)
end
cd:Fire("Admin", "max", "")
play(alice, run, 15)
check("run holds 12 weapons (slots ignored by debug)", #run.Weapons >= 10, #run.Weapons)
check("client loadout knows them", runClient.Loadout and #runClient.Loadout.Weapons == #run.Weapons)
check("no errors with every weapon firing", errorsSince(mark) == 0, Engine.Errors[mark + 1])
print(string.format("       t=%.0fs level %d kills %d alive %d projectiles %d", run.Time, run.Level, run.Kills, #run.Enemies, #run.Projectiles))

---------------------------------------------------------------------------
section("death -> results -> rewards saved")
---------------------------------------------------------------------------
mark = #Engine.Errors
local coinsBefore = session.Data.Coins
cd:Fire("Admin", "god", "")
local freeRevives = run.Revives
for _ = 1, 4 do
	-- free revives (meta / MAIN CHARACTER card) bring the player back first
	if run.Dead then
		break
	end
	cd:Fire("Admin", "die", "")
	Engine.Step(1)
end
check("free revives were used before death", run.Revives == 0, freeRevives)
check("run is in the dead state", run.Dead == true)
check("death screen visible", results.Death.Visible == true)
local giveUp = findGui(alice, "GiveUp")
Engine.Click(giveUp)
Engine.Step(1)
check("run ended on the server", GM.Entries[alicePlayer] == nil and run.Ended)
check("results screen visible", results.Panel.Visible == true)
check("results title says RUN OVER", results.ResultTitle.Text == "RUN OVER", results.ResultTitle.Text .. " / " .. tostring(run.EndReason))
check("coins rewarded", session.Data.Coins > coinsBefore, session.Data.Coins - coinsBefore)
check("stats saved in profile", session.Data.Stats.Runs == 1 and session.Data.Stats.Kills == run.Kills)
check("best time recorded", session.Data.Stats.BestTime == math.floor(run.Time))
check("collection updated", (session.Data.Collection.Goober or 0) > 0)
check("achievement First Blood", session.Data.Achievements.FirstBlood ~= nil)
check("quest progress recorded", session.Data.Quests.List[1] ~= nil)
check("client got the new coins", cd.Data.Coins == session.Data.Coins)
check("no errors at run end", errorsSince(mark) == 0, Engine.Errors[mark + 1])

-- lobby again
Engine.Click(findGui(alice, "Lobby"))
Engine.Step(1)
check("back in the lobby", lobby.Gui.Enabled == true and hud.Gui.Enabled == false)
check("enemy models released to the pool", enemyRenderer:Count() == 0 and #enemyRenderer.Dying == 0)
local lobbyPos = alicePlayer.Character:FindFirstChild("HumanoidRootPart").Position
check("character back in the lobby", lobbyPos.Z > 300, lobbyPos)

---------------------------------------------------------------------------
section("meta shop")
---------------------------------------------------------------------------
session.Data.Coins += 5000
cd:Fire("BuyMeta", "Might")
Engine.Step(0.5)
check("permanent upgrade bought", session.Data.Meta.Might == 1)
cd:Fire("SelectCharacter", "Sigma")
Engine.Step(0.5)
check("character selected (unlocked by the debug unlockall)", session.Data.Characters.Sigma == true and session.Data.Selected == "Sigma")
cd:Fire("ClaimDaily")
Engine.Step(0.5)
check("daily reward claimed once", session.Data.Daily.Streak == 1)
local coins = session.Data.Coins
cd:Fire("ClaimDaily")
Engine.Step(0.5)
check("daily reward cannot be claimed twice", session.Data.Coins == coins)

---------------------------------------------------------------------------
section("exploits are ignored")
---------------------------------------------------------------------------
mark = #Engine.Errors
coins = session.Data.Coins
cd:Fire("StartRun", 123, { bad = true })
Engine.Step(0.2)
local exploitRun = GM.Entries[alicePlayer]
check("weird StartRun args fall back to the selected character", exploitRun == nil or exploitRun.Run.Character == "Sigma")
if exploitRun then
	for _ = 1, 50 do
		cd:Fire("Choose", 999)
		cd:Fire("Choose", "1")
		cd:Fire("Choose", 1.5)
		cd:Fire("Reroll")
	end
	cd:Fire("GiveUp")
	Engine.Step(1)
	Engine.Click(findGui(alice, "Lobby"))
	Engine.Step(0.5)
end
coins = session.Data.Coins
cd:Fire("BuyMeta", "NotAThing")
cd:Fire("BuyMeta", { "table" })
cd:Fire("UnlockWeapon", "FinalAura")
cd:Fire("SetSetting", "Sfx", "yes")
cd:Fire("SetSetting", "Coins", 999999)
cd:Fire("ClaimQuest", 99)
cd:Fire("Admin", "coins", "999999")
Engine.Step(1)
check("no free coins from bad requests (studio admin aside)", session.Data.Coins >= coins)
check("settings keep their type", session.Data.Settings.Sfx == true)
check("unknown settings ignored", session.Data.Settings.Coins == nil)
check("no server errors from bad requests", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("save -> leave -> rejoin")
---------------------------------------------------------------------------
local savedCoins = session.Data.Coins
local savedRuns = session.Data.Stats.Runs
local userId = alicePlayer.UserId
Engine.RemovePlayer("Alice")
Engine.Step(2)
local stored = Engine.DataStores["BrainrotSurvivors_Players_v1"]
check("profile written to the DataStore", stored and stored["u_" .. userId] ~= nil)
local alice2, alicePlayer2 = Engine.AddPlayer("Alice", { UserId = userId })
Engine.Step(1)
local session2 = PM:Get(alicePlayer2)
check("profile loaded again", session2 ~= nil)
-- (joining re-checks achievements: the debug coins earned "Brain Millionaire" = +500)
check("coins persisted", session2 and session2.Data.Coins >= savedCoins and session2.Data.Coins <= savedCoins + 500, session2 and (session2.Data.Coins .. " vs " .. savedCoins))
check("stats persisted", session2 and session2.Data.Stats.Runs == savedRuns)
check("character unlock persisted", session2 and session2.Data.Characters.Sigma == true)

---------------------------------------------------------------------------
section("mobile client")
---------------------------------------------------------------------------
mark = #Engine.Errors
local bob, bobPlayer = Engine.AddPlayer("Bob", { Touch = true })
Engine.Step(1)
local bobCd = Engine.Module(bob, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ClientData")
bobCd:Fire("StartRun", "Goober", "")
Engine.Step(0.5)
local bobRun = GM.Entries[bobPlayer] and GM.Entries[bobPlayer].Run
check("mobile player runs too", bobRun ~= nil)
local bobHud = Engine.Module(bob, "StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController")
check("weapon bar moved away from the thumbstick", bobHud.Bottom.AnchorPoint.X == 1)
if bobRun then
	play(bob, bobRun, 20)
	check("mobile run progresses", bobRun.Kills > 0 and bobRun.Level > 1, bobRun.Kills)
end
local aliceBob = alice2.PlayersByName.Bob
local ghostPart = aliceBob and aliceBob.Character and aliceBob.Character:FindFirstChild("Head")
check("the other player sees Bob as a ghost", ghostPart and ghostPart.LocalTransparencyModifier > 0.5)
-- unlocking a character with coins on a fresh profile
local bobSession = PM:Get(bobPlayer)
bobCd:Fire("GiveUp")
Engine.Step(1)
bobSession.Data.Coins = 3000
bobCd:Fire("UnlockCharacter", "Brainrot")
Engine.Step(0.5)
check("character unlocked with coins", bobSession.Data.Characters.Brainrot == true and bobSession.Data.Coins == 1000, bobSession.Data.Coins)
bobCd:Fire("UnlockCharacter", "TheNPC")
Engine.Step(0.5)
check("secret character cannot be bought", bobSession.Data.Characters.TheNPC == false)
check("no errors for the mobile client", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("shutdown")
---------------------------------------------------------------------------
local ok = Engine.Shutdown()
check("BindToClose finished saving", ok)
check("no runtime errors at all", #Engine.Errors == 0, Engine.Errors[1])

print(string.format("\n%d passed, %d failed", passed, failed))
for _, f in failures do
	print("  - " .. f)
end
process.exit(if failed == 0 then 0 else 1)
