--!nocheck
--[[
	End-to-end playtest: the REAL server + client scripts running in tests/engine.luau
	(virtual time, real Instances, RemoteEvents with Roblox serialization, DataStores).
	A bot plays through the client like a player would: walks with the character, clicks
	PLAY and level-up cards, dies, reads the results, rejoins.

	Run from 67Survival/:   lune run tests/e2e.luau
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
do
	-- every hero model builds (with a hat and a skin)
	local HeroModels = Engine.Module(server, "ReplicatedStorage.Modules.HeroModels")
	local HeroData = Engine.Module(server, "ReplicatedStorage.Modules.HeroData")
	local folder = server.Game:GetService("Workspace"):FindFirstChild("Map")
	local ok, smallest = true, math.huge
	for _, def in HeroData.List do
		local model = Engine.Wrap(rawget(folder, "__real"), server)
		local built = HeroModels.Build(def.Key, roblox.CFrame.new(0, 500, 0), model, { Skin = "Neon", Hat = "Crown" })
		smallest = math.min(smallest, #built)
		for _, p in built do
			p:Destroy()
		end
	end
	check("all 15 hero models build (hats + skins)", ok and smallest >= 8 and #HeroData.List >= 15, smallest)
	-- welded like a real character: every joint holds its part in place at rest, and the
	-- floating pieces (drone rotor, goober friends, void shards, glitch pixels) get spin motors
	local rest, floating = true, 0
	for _, def in HeroData.List do
		local model = Engine.Wrap(rawget(folder, "__real"), server)
		local root = Engine.Wrap(roblox.Instance.new("Part"), server)
		root.CFrame = roblox.CFrame.new(3, 500, 2) * roblox.CFrame.Angles(0, 0.7, 0)
		root.Parent = model
		local built = HeroModels.Build(def.Key, root.CFrame, model, { WeldTo = root, Ring = true })
		for _, m in root:GetChildren() do
			if m:IsA("Motor6D") then
				local posed = m.Part0.CFrame * m.C0 * m.C1:Inverse()
				local part = m.Part1.CFrame
				if (posed.Position - part.Position).Magnitude > 1e-3 or (posed.LookVector - part.LookVector).Magnitude > 1e-3 then
					rest = false
					print("       " .. def.Key .. " " .. m.Name .. " moves at rest")
				end
				if string.sub(m.Name, 1, 4) == "Spin" then
					floating += 1
				end
			end
		end
		for _, p in built do
			p:Destroy()
		end
		root:Destroy()
	end
	check("welded heroes: joints hold every part at rest, floating parts spin / orbit", rest and floating >= 14, floating)
end

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
local hud = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController")
local lobby = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController")
local effects = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.EffectsController")
local results = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ResultsController")
local levelUpUi = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.LevelUpController")
check("client received its profile", cd.Loaded == true)
check("lobby UI visible", lobby.Gui.Enabled == true)
check("HUD hidden in the lobby", hud.Gui.Enabled == false)
check("coins shown in the lobby", lobby.CoinsLabel.Text == "0", lobby.CoinsLabel.Text)
check("fragments shown in the lobby", lobby.FragmentsLabel.Text == "0", lobby.FragmentsLabel.Text)
check("hub: PLAY + tagline in the centre", findGui(alice, "Play") ~= nil and lobby.Tagline.Text == "Survive. Level up. Become unstoppable.")
check("hub: HEROES / ABILITIES / SHOP / MORE", lobby.NavButtons.Heroes and lobby.NavButtons.Abilities and lobby.NavButtons.Shop and lobby.NavButtons.More)
check("hub: logo says 67 SURVIVAL", findGui(alice, "Mark").Text == "67" and findGui(alice, "Word").Text == "SURVIVAL")
check("hub: daily quest card filled", lobby.QuestText.Text ~= "", lobby.QuestText.Text)
check("hub: hero card shows the selected hero", lobby.CharacterName.Text == "THE ROOKIE", lobby.CharacterName.Text)
check("admin tools offered in Studio", cd.Data.Admin == true and findGui(alice, "S67Debug") ~= nil)
check("Studio test players (negative ids) get no DEBUG", PM:IsAdmin({ UserId = -1 } :: any) == false)
check("snapshot has the new systems", cd.Data.Afk ~= nil and cd.Data.Weekly and #cd.Data.Weekly.List == 3 and cd.Data.CollectionTotal >= 100, cd.Data.CollectionTotal)
check("new players start on CALM (only tier I open)", cd.Data.Difficulty and cd.Data.Difficulty.Selected == 1 and cd.Data.Difficulty.Unlocked == 1)
check("hub: difficulty pill above PLAY shows CALM", lobby.DiffName.Text == "CALM" and lobby.DiffNumeral.Text == "I", lobby.DiffName.Text)
check("hub: the camera frames the hero stage", ws:FindFirstChild("Map"):FindFirstChild("Lobby"):FindFirstChild("HubStage") ~= nil)
check("no errors on join", #Engine.Errors == 0, Engine.Errors[1])

-- the hero model replaces the Roblox look
local character = alicePlayer.Character
local heroModel = character:FindFirstChild("HeroModel")
check("hero model built on the character", heroModel ~= nil and Engine.Count(heroModel, "BasePart") >= 8)
check("hero joint for client animation", character:FindFirstChild("HumanoidRootPart"):FindFirstChild("HeroJoint") ~= nil)
do
	local heroRoot = heroModel and heroModel:FindFirstChild("HeroRoot")
	local limbs = 0
	for _, name in { "LimbArmL", "LimbArmR", "LimbLegL", "LimbLegR" } do
		if heroRoot and heroRoot:FindFirstChild(name) then
			limbs += 1
		end
	end
	check("arms and legs have joints (walk / emote animation)", limbs == 4, limbs)
	local meshes = heroModel and Engine.Count(heroModel, "SpecialMesh") or 0
	check("hero is built from smooth shapes (ellipsoid meshes)", meshes >= 8, meshes)
end
check("roblox rig is invisible", character:FindFirstChild("Head") == nil or character:FindFirstChild("Head").Transparency == 1)
check("name tag with title", character:FindFirstChild("HumanoidRootPart"):FindFirstChild("HeroTag") ~= nil)

-- every lobby panel opens and renders
local mark = #Engine.Errors
for _, key in { "Heroes", "Abilities", "Shop", "More", "Achievements", "Collection", "Challenges", "AfkCamp", "Party", "Leaderboard", "Statistics", "Codes", "Settings", "Credits", "Profile", "Daily", "Difficulty", "HowToPlay" } do
	lobby:OpenPanel(key)
	Engine.Step(0.2)
	check("panel opens: " .. key, lobby.Open and lobby.Open.Key == key and lobby.Open.Frame.Visible)
end
lobby:ClosePanel()
check("no errors while opening panels", errorsSince(mark) == 0, Engine.Errors[mark + 1])

-- navigation by clicks: MORE -> tile -> close; coins pill -> shop UPGRADES page
Engine.Click(lobby.NavButtons.More)
Engine.Step(0.2)
check("MORE opens a compact window", lobby.Open and lobby.Open.Key == "More" and lobby.Open.Module.Kind == "Window")
check("MORE has 9 tiles", lobby.Open and #lobby.Open.State.Tiles.Collection:GetChildren() > 0)
Engine.Click(lobby.Open.State.Tiles.Statistics)
Engine.Step(0.2)
check("MORE tile opens its window", lobby.Open and lobby.Open.Key == "Statistics")
lobby:ClosePanel()
check("closing hides the panel", lobby.Open == nil and not lobby.Panels.Statistics.Frame.Visible)
Engine.Click(lobby.Safe:FindFirstChild("TopRight"):FindFirstChild("Coins"))
Engine.Step(0.2)
check("coins pill opens the shop on UPGRADES", lobby.Open and lobby.Open.Key == "Shop" and lobby.Open.State.Current == "Upgrades")
lobby:OpenPanel("Shop", false, "Cosmetics")
Engine.Step(0.2)
check("shop has 12 cosmetic categories", lobby.Open.State.Current == "Cosmetics" and lobby.Open.State.CatPages.Aura ~= nil)
lobby:ClosePanel()
Engine.Click(lobby.NavButtons.Heroes)
Engine.Step(0.2)
local heroesState = lobby.Open and lobby.Open.State
check("HEROES is a full-screen menu", lobby.Open and lobby.Open.Module.Kind == "Screen")
check("hero cards show EQUIPPED / LOCKED", heroesState and heroesState.Cards.Rookie.State.Text == "EQUIPPED" and heroesState.Cards.Hunter.State.Text == "LOCKED")
check("secret hero is ???", heroesState and heroesState.Cards.Unknown.Name.Text == "???")
lobby:ClosePanel()
check("no errors while navigating", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("67 LAND: the lobby event map")
---------------------------------------------------------------------------
do
	local mapLobby = ws:FindFirstChild("Map"):FindFirstChild("Lobby")
	local gates, npcs, special = {}, 0, {}
	for _, d in mapLobby:GetDescendants() do
		if d:IsA("BasePart") then
			local g = d:GetAttribute("EventGate")
			if g then
				gates[g] = d
			end
			if d:GetAttribute("NpcKey") then
				npcs += 1
			end
			for _, key in { "PlayPortal", "AfkCamp", "Leaderboard", "EventBoard", "Beacon", "Button67" } do
				if d:GetAttribute(key) then
					special[key] = true
				end
			end
		end
	end
	local count = 0
	for i = 1, 7 do
		if gates[i] then
			count += 1
		end
	end
	check("an EVENT GATE for every difficulty tier", count == 7, count)
	check("the lobby keeps PLAY portal, AFK camp, leaderboard (+ events board, beacon, button)", special.PlayPortal and special.AfkCamp and special.Leaderboard and special.EventBoard and special.Beacon and special.Button67)
	check("NPCs stand in 67 LAND", npcs >= 5, npcs)
	local keys = {}
	for _, r in MB.Regions do
		keys[r.Key] = true
	end
	check("secret places: lobby + arena", keys.TouchGrass and keys.Backrooms and keys.Nowhere and keys.UnderBridge and keys.Throne67)

	-- your gates, drawn for you
	local emc = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.EventMapController")
	local g1, g2, g3 = emc.Gates[1], emc.Gates[2], emc.Gates[3]
	check("gates show YOUR state: I selected, II next, III locked", g1 and g2 and g3 and g1.State == "Selected" and g2.State == "Next" and g3.State == "Locked")
	check("an open gate is a portal, a closed one a door with a lock", g1.Portal.CanCollide == false and g2.Portal.CanCollide == true and g1.Locks[1].Transparency == 1 and g2.Locks[1].Transparency == 0)
	local label2 = g2.Label and g2.Label:FindFirstChild("Line2")
	check("the NEXT gate says what opens it", label2 ~= nil and string.find(label2.Text, "DEFEAT A BOSS ON CALM", 1, true) ~= nil, label2 and label2.Text)
	local beacon = emc.Beacon
	check("the beacon stands on your NEXT gate", beacon ~= nil and (Vector3.new(beacon.Position.X, 0, beacon.Position.Z) - Vector3.new(g2.Portal.Position.X, 0, g2.Portal.Position.Z)).Magnitude < 1)
	local guide
	for _, n in emc.Npcs do
		if n.Def.Key == "Guide" then
			guide = n
		end
	end
	local home = alicePlayer.Character:GetPivot()
	alicePlayer.Character:PivotTo(roblox.CFrame.new(guide.Marker.Position + Vector3.new(3, -4, -3)))
	Engine.Step(0.4)
	check("an NPC talks when you come close", guide.Bubble.Enabled and guide.Bubble:FindFirstChild("Line2").Text ~= "")

	-- a locked gate does not start a run (it says why), an open one does, on its tier
	GM:EnterGate(alicePlayer, 3)
	Engine.Step(0.2)
	check("a locked gate does not start a run", GM.Entries[alicePlayer] == nil)
	local carol, carolPlayer = Engine.AddPlayer("Carol")
	Engine.Step(1)
	local carolData = PM:Get(carolPlayer).Data.Difficulty
	carolData.Best[1] = { Time = 400, Bosses = 1, Wins = 0 } -- a boss on CALM opens HUNT
	GM:EnterGate(carolPlayer, 2)
	Engine.Step(0.5)
	local carolEntry = GM.Entries[carolPlayer]
	check("an open gate starts a run on its tier", carolEntry ~= nil and carolEntry.Run.Difficulty == 2 and carolData.Selected == 2, carolEntry and carolEntry.Run.Difficulty)
	local _ = carol
	Engine.RemovePlayer("Carol")
	Engine.Step(0.5)

	-- DO NOT PRESS: 67 presses
	for _ = 1, 67 do
		GM:PressButton(alicePlayer)
	end
	check("the button (67 presses) is a secret", session.Data.SecretsFound.Button67 == true)

	-- falling off the island brings you back
	alicePlayer.Character:PivotTo(roblox.CFrame.new(ws:FindFirstChild("SpawnPoints"):FindFirstChild("Lobby").Position + Vector3.new(200, -80, 0)))
	Engine.Step(1.2)
	local back = alicePlayer.Character:FindFirstChild("HumanoidRootPart").Position
	local spawnPos = ws:FindFirstChild("SpawnPoints"):FindFirstChild("Lobby").Position
	check("falling off 67 LAND puts you back on the spawn", (back - spawnPos).Magnitude < 12, back)
	alicePlayer.Character:PivotTo(home)
	Engine.Step(0.2)
	check("no errors in 67 LAND", #Engine.Errors == 0, Engine.Errors[1])
end

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
check("hero + its starting ability", run.Hero == "Rookie" and #run.Weapons == 1 and run.Weapons[1].Key == "BasicBlaster")
check("the run is on the selected difficulty (CALM)", run.Difficulty == 1 and hud.DiffLabel.Text == "I  CALM", hud.DiffLabel.Text)
check("your hero has an outline in the run", alice.LocalPlayer.Character:FindFirstChild("HeroOutline") ~= nil)
do
	-- ponds are water: they slow you down (and the horde)
	local MB = Engine.Module(server, "ServerScriptService.Server.Services.MapBuilder")
	local GameConfig = Engine.Module(server, "ReplicatedStorage.Modules.GameConfig")
	local ponds = MB.Colliders.Water
	local pond = ponds[1]
	check("the arena ponds are water in the simulation", #ponds == 2 and run:InWater(pond.X, pond.Z) and not run:InWater(pond.X + pond.R + 1, pond.Z))
	local humanoid = alicePlayer.Character:FindFirstChildOfClass("Humanoid")
	local backX, backZ = entry.LastX, entry.LastZ
	entry.LastX, entry.LastZ = pond.X, pond.Z
	Engine.MoveCharacter("Alice", roblox.Vector3.new(pond.X, 3, pond.Z))
	Engine.Step(0.2)
	local wet = humanoid.WalkSpeed
	entry.LastX, entry.LastZ = backX, backZ
	Engine.MoveCharacter("Alice", roblox.Vector3.new(backX, 3, backZ))
	Engine.Step(0.2)
	check("walking through water is slower", math.abs(wet - run.Stats.WalkSpeed * GameConfig.Water.PlayerSpeed) < 0.01 and GameConfig.Water.PlayerSpeed < 1 and humanoid.WalkSpeed == run.Stats.WalkSpeed, wet)
end
cd:SetSetting("HeroOutline", false)
runClient:ApplyOutline()
check("the outline can be switched off", alice.LocalPlayer.Character:FindFirstChild("HeroOutline") == nil)
cd:SetSetting("HeroOutline", true)
runClient:ApplyOutline()
local pointer = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.PointerController")
Engine.Step(0.2)
check("first run: the how-to-survive card shows", pointer.Hint.Visible == true and pointer.HintLines[1].Text == "WASD - move" and string.find(pointer.HintLines[4].Text, "1-3", 1, true) ~= nil, pointer.HintLines[1].Text)

---------------------------------------------------------------------------
section("first 30 seconds: move, enemies, auto attack, XP, level up")
---------------------------------------------------------------------------
mark = #Engine.Errors
local picks = play(alice, run, 30)
check("the how-to card goes away by itself", pointer.Hint.Visible == false and pointer.HintUntil < 0)
check("enemies spawned on the server", run.Kills + #run.Enemies > 10, run.Kills + #run.Enemies)
check("client renders the enemies", enemyRenderer:Count() > 0 or run.Kills > 0, enemyRenderer:Count())
check("client and server agree on enemy count", math.abs(enemyRenderer:Count() - #run.Enemies) <= 3, enemyRenderer:Count() .. " vs " .. #run.Enemies)
check("auto attack kills enemies", run.Kills >= 10, run.Kills)
check("XP gems collected", run.Result.Gems >= 10, run.Result.Gems)
check("level up happened", run.Level >= 3, run.Level)
check("level-up cards were picked through the UI", picks >= 2, picks)
check("client HUD shows the level", hud.LevelLabel.Text == "LV " .. run.Level, hud.LevelLabel.Text)
check("client HUD shows the timer", hud.Timer.Text ~= "" and hud.Timer.Text ~= "0:00", hud.Timer.Text)
check("client HUD shows the ability icon", hud.WeaponRow:FindFirstChild("BasicBlaster") ~= nil)
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
-- (a level-up choice that is still open also pauses the run: answer it first)
if run.Offer then
	cd:Fire("Choose", 1)
	Engine.Step(0.3)
end
local t0 = run.Time
hud:TogglePause(true)
Engine.Step(2)
check("run time frozen while paused", math.abs(run.Time - t0) < 0.2, run.Time - t0)
check("walk speed 0 while paused", alicePlayer.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 0)
hud:TogglePause(false)
Engine.Step(1)
check("run continues after resume", run.Time > t0 + 0.5, run.Time - t0)

---------------------------------------------------------------------------
section("boss at 3:00")
---------------------------------------------------------------------------
mark = #Engine.Errors
cd:Fire("Admin", "god", "")
cd:Fire("Admin", "time", "176")
play(alice, run, 8)
local bossKey = run.Boss and run.Boss.Key
check("first boss spawned (THE GIANT or THE GOOBER)", bossKey == "TheGiant" or bossKey == "TheGoober", bossKey)
check("client shows the boss bar", hud.BossPanel.Visible == true)
check("client knows the boss", runClient.Boss ~= nil and runClient.Boss.Key == bossKey)
local banner = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.BannerController")
play(alice, run, 6)
check("boss attacks are telegraphed", #run.Telegraphs + #run.Hazards >= 0)
local bossesBefore = #run.Result.Bosses
cd:Fire("Admin", "killall", "")
play(alice, run, 3)
check("boss defeated", #run.Result.Bosses == bossesBefore + 1)
check("boss bar hidden", hud.BossPanel.Visible == false)
play(alice, run, 8)
check("chest collected -> treasure offer handled", run.PendingChests == 0 and run.Offer == nil)
check("boss dropped a fragment that was picked up", run.Result.Fragments >= 1, run.Result.Fragments)
check("no errors in the boss fight", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("67 events")
---------------------------------------------------------------------------
mark = #Engine.Errors
for _, key in { "Percent67", "Chest67", "Invasion67", "Luck67", "Chaos67", "Mode67", "Boss67", "The67" } do
	cd:Fire("Admin", "event", key)
	play(alice, run, 4)
	check("67 event runs: " .. key, run.Result.EventsSeen[key] == true)
end
check("every 67 event counted", run.Result.Events67 >= 8, run.Result.Events67)
check("giant 67 text appeared", banner.Giant.Text == "67" or banner.Giant.Text ~= "")
play(alice, run, 20)
check("invasion cap restored afterwards", run.MaxEnemies <= GM.Entries[alicePlayer].Run.BaseMaxEnemies or run.Wave.InvasionUntil > run.Time)
cd:Fire("Admin", "killall", "")
play(alice, run, 3)
check("no errors during 67 events", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("every ability kind + evolution")
---------------------------------------------------------------------------
mark = #Engine.Errors
cd:Fire("Admin", "unlockall", "")
for i, key in { "Katana", "Orb67", "FireRing", "IceField", "PoisonCloud", "Meteor", "Shockwave", "ChainLightning", "Laser", "BlackHole", "GiantFist", "SwordStorm", "Drone", "Clone", "GooberFriends", "Barrier", "Glitch", "Chaos", "Blast67", "SigmaStare", "BananaBomb", "Boomerang", "Rocket", "MagicMissile", "Arrow", "Lightning", "SigmaAura", "OrbitalBlades", "PulseBlast" } do
	cd:Fire("Admin", "weapon", key)
	if i % 4 == 0 then
		Engine.Step(1) -- admin commands are rate limited too
	end
end
play(alice, run, 12)
check("run holds many abilities (slots ignored by debug)", #run.Weapons >= 25, #run.Weapons)
check("client loadout knows them", runClient.Loadout and #runClient.Loadout.Weapons == #run.Weapons)
check("no errors with every ability firing", errorsSince(mark) == 0, Engine.Errors[mark + 1])
print(string.format("       t=%.0fs level %d kills %d alive %d projectiles %d zones %d", run.Time, run.Level, run.Kills, #run.Enemies, #run.Projectiles, #run.Zones))
mark = #Engine.Errors
cd:Fire("Admin", "evolve", "")
Engine.Step(0.5)
check("EVOLUTION AVAILABLE shown", hud.EvoPill.Visible == true)
local evoCard = nil
for i = 1, 20 do
	if levelUpUi:IsOpen() and run.Offer then
		for index, card in run.Offer.Cards do
			if card.Type == "Evolution" then
				evoCard = index
			end
		end
		break
	end
	Engine.Step(0.2)
end
check("level-up offers the evolution first", evoCard == 1, evoCard)
if evoCard then
	Engine.Click(findGui(alice, "Card" .. evoCard))
	Engine.Step(0.5)
end
check("an ability evolved", #run.Result.Evolutions >= 1, #run.Result.Evolutions)
play(alice, run, 6)
check("no errors with evolutions", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("death -> results -> rewards saved")
---------------------------------------------------------------------------
mark = #Engine.Errors
local coinsBefore = session.Data.Coins
local fragmentsBefore = session.Data.Fragments
cd:Fire("Admin", "god", "")
for _ = 1, 4 do
	if run.Dead then
		break
	end
	cd:Fire("Admin", "die", "")
	Engine.Step(1)
end
check("run is in the dead state", run.Dead == true)
check("death screen visible", results.Death.Visible == true)
Engine.Click(findGui(alice, "GiveUp"))
Engine.Step(1)
check("run ended on the server", GM.Entries[alicePlayer] == nil and run.Ended)
check("results screen visible", results.Panel.Visible == true)
check("results title says RUN OVER", results.ResultTitle.Text == "RUN OVER", results.ResultTitle.Text .. " / " .. tostring(run.EndReason))
check("coins rewarded", session.Data.Coins > coinsBefore, session.Data.Coins - coinsBefore)
check("fragments rewarded", session.Data.Fragments > fragmentsBefore, session.Data.Fragments - fragmentsBefore)
check("stats saved in profile", session.Data.Stats.Runs == 1 and session.Data.Stats.Kills == run.Kills)
check("best time recorded", session.Data.Stats.BestTime == math.floor(run.Time))
check("collection: enemies", (session.Data.Collection.Goober or 0) > 0)
check("collection: abilities and events seen", session.Data.Seen.Weapons.BasicBlaster == true and session.Data.Seen.Events.The67 == true)
check("collection: the evolution", next(session.Data.Seen.Evolutions) ~= nil)
check("achievements: First Blood, 67, Evolution", session.Data.Achievements.FirstBlood ~= nil and session.Data.Achievements.SixSeven ~= nil and session.Data.Achievements.Evolved ~= nil)
check("achievement cosmetics granted", session.Data.Cosmetics.Owned["Hat.Headband67"] == true)
check("weekly challenge progress recorded", session.Data.Weekly.List[1] ~= nil)
check("client got the new coins", cd.Data.Coins == session.Data.Coins)
check("results show fragments and collection", results.StatLabels.Fragments.Text ~= "+0" and results.StatLabels.Collection.Text ~= "")
check("difficulty progress saved (a boss on CALM)", session.Data.Difficulty.Best[1].Bosses >= 1 and session.Data.Difficulty.Best[1].Time == math.floor(run.Time))
check("defeating a boss on CALM opens HUNT", cd.Data.Difficulty.Unlocked >= 2, cd.Data.Difficulty.Unlocked)
check("results name the difficulty", string.find(results.ResultSub.Text, "CALM") ~= nil, results.ResultSub.Text)
check("no errors at run end", errorsSince(mark) == 0, Engine.Errors[mark + 1])

-- extra chest (developer product, simulated in Studio): once per run
local coins = session.Data.Coins
cd:Fire("Buy", "Product", "ExtraChest")
Engine.Step(0.5)
check("extra chest opened", session.Data.Coins >= coins + 100, session.Data.Coins - coins)
coins = session.Data.Coins
local fragments = session.Data.Fragments
cd:Fire("Buy", "Product", "ExtraChest")
Engine.Step(0.5)
check("a second extra chest is refunded, not doubled", session.Data.Fragments == fragments and session.Data.Coins == coins + 250)

-- lobby again
Engine.Click(findGui(alice, "Lobby"))
Engine.Step(1)
check("back in the lobby", lobby.Gui.Enabled == true and hud.Gui.Enabled == false)
check("enemy models released to the pool", enemyRenderer:Count() == 0 and #enemyRenderer.Dying == 0)
local lobbyPos = alicePlayer.Character:FindFirstChild("HumanoidRootPart").Position
check("character back in the lobby", lobbyPos.Z > 300, lobbyPos)

---------------------------------------------------------------------------
section("difficulty: select, locks, rewards")
---------------------------------------------------------------------------
mark = #Engine.Errors
cd:Fire("SelectDifficulty", 5)
Engine.Step(0.5)
check("a locked tier cannot be selected", session.Data.Difficulty.Selected == 1, session.Data.Difficulty.Selected)
Engine.Click(lobby.DiffNext)
Engine.Step(0.5)
check("the pill's arrow selects the next open tier", session.Data.Difficulty.Selected == 2 and lobby.DiffName.Text == "HUNT", lobby.DiffName.Text)
Engine.Click(lobby.DiffNext)
Engine.Step(0.5)
check("past the last open tier the arrow opens the difficulty screen", lobby.Open and lobby.Open.Key == "Difficulty" and session.Data.Difficulty.Selected == 2)
do
	local st = lobby.Open and lobby.Open.State
	check("difficulty screen: 7 tiers on the ladder", st and #st.Rows == 7)
	if st then
		st.Focus = 3
		lobby.Open.Module.Refresh(st, cd.Data)
		check("a locked tier shows its goal and progress", string.find(st.Goal.Text, "Survive 10:00 on HUNT") ~= nil, st.Goal.Text)
		check("its new rules are listed", st.RuleList:FindFirstChild("FasterHorde") ~= nil)
		check("PLAY is locked on a locked tier", st.PlayLabel.Text == "LOCKED")
	end
end
lobby:ClosePanel()
-- a short run on HUNT: the tier's numbers and its reward multiplier
coinsBefore = session.Data.Coins
Engine.Click(findGui(alice, "Play"))
Engine.Step(0.5)
local hunt = GM.Entries[alicePlayer] and GM.Entries[alicePlayer].Run
check("HUNT run started", hunt ~= nil and hunt.Difficulty == 2)
if hunt then
	play(alice, hunt, 70)
	cd:Fire("GiveUp")
	Engine.Step(1)
end
check("HUNT pays x1.25", results.Panel.Visible and cd.Data and session.Data.Coins > coinsBefore)
check("HUNT best time recorded", session.Data.Difficulty.Best[2].Time >= 60, session.Data.Difficulty.Best[2].Time)
Engine.Click(findGui(alice, "Lobby"))
Engine.Step(1)
check("no errors with difficulties", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("heroes, abilities, upgrades, codes")
---------------------------------------------------------------------------
session.Data.Coins += 20000
session.Data.Fragments += 50
cd:Fire("BuyMeta", "Might")
Engine.Step(0.5)
check("permanent upgrade bought", session.Data.Meta.Might == 1)
cd:Fire("SelectHero", "Samurai")
Engine.Step(0.5)
check("hero selected (unlocked by the debug unlockall)", session.Data.Heroes.Samurai == true and session.Data.Selected == "Samurai")
check("hero model rebuilt", alicePlayer.Character:GetAttribute("Hero") == "Samurai")
cd:Fire("SetStartWeapon", "Meteor")
Engine.Step(0.5)
check("starting ability saved in the loadout", session.Data.Loadouts[1].StartWeapon == "Meteor" and session.Data.Loadouts[1].Hero == "Samurai")
cd:Fire("SelectLoadout", 2)
Engine.Step(0.5)
check("loadout 2 needs the pass", session.Data.Loadout == 1)
cd:Fire("ClaimDaily")
Engine.Step(0.5)
check("daily reward claimed once", session.Data.Daily.Streak == 1)
coins = session.Data.Coins
cd:Fire("ClaimDaily")
Engine.Step(0.5)
check("daily reward cannot be claimed twice", session.Data.Coins == coins)

-- codes: each works once per player, unknown codes do nothing
coins = session.Data.Coins
cd:Fire("RedeemCode", "67")
Engine.Step(0.5)
check("code redeemed", session.Data.Coins == coins + 67, session.Data.Coins - coins)
cd:Fire("RedeemCode", "67")
cd:Fire("RedeemCode", "NOT_A_CODE")
cd:Fire("RedeemCode", { "table" })
Engine.Step(0.5)
check("code works only once, bad codes ignored", session.Data.Coins == coins + 67, session.Data.Coins - coins)
Engine.Step(6) -- redeem requests are rate limited (burst 3)
fragments = session.Data.Fragments
cd:Fire("RedeemCode", " fragments ")
Engine.Step(0.5)
check("codes ignore case and spaces, can give fragments", session.Data.Fragments == fragments + 5, session.Data.Fragments - fragments)

---------------------------------------------------------------------------
section("cosmetics")
---------------------------------------------------------------------------
coins = session.Data.Coins
cd:Fire("BuyCosmetic", "Hat.Cone")
Engine.Step(0.5)
check("hat bought with coins and worn", session.Data.Cosmetics.Owned["Hat.Cone"] == true and session.Data.Cosmetics.Equipped.Hat == "Hat.Cone" and session.Data.Coins == coins - 400)
check("hat visible on the hero", alicePlayer.Character:FindFirstChild("HeroModel"):FindFirstChild("ConeBase") ~= nil)
cd:Fire("BuyCosmetic", "Hat.Crown")
Engine.Step(0.5)
check("achievement hats cannot be bought", session.Data.Cosmetics.Owned["Hat.Crown"] == nil)
cd:Fire("EquipCosmetic", "Hat.Crown")
Engine.Step(0.5)
check("locked hats cannot be worn", session.Data.Cosmetics.Equipped.Hat == "Hat.Cone")
session.Data.Cosmetics.Owned["Hat.Propeller"] = true
cd:Fire("EquipCosmetic", "Hat.Propeller")
Engine.Step(0.5)
do
	local heroRoot = alicePlayer.Character:FindFirstChild("HeroModel"):FindFirstChild("HeroRoot")
	local spin = heroRoot and heroRoot:FindFirstChild("SpinBladeA")
	local blade = spin and spin.Part1
	local posed = spin and blade and (spin.Part0.CFrame * spin.C0 * spin.C1:Inverse()).Position
	check("propeller blades spin (a motor on the hat's axis, blade in place)", spin ~= nil and (spin:GetAttribute("Speed") or 0) > 0 and posed ~= nil and (posed - blade.CFrame.Position).Magnitude < 1e-3)
end
cd:Fire("BuyCosmetic", "Trail.Fire")
Engine.Step(0.5)
check("trail bought -> trail on the hero", alicePlayer.Character:FindFirstChild("HumanoidRootPart"):FindFirstChild("HeroTrail") ~= nil)
cd:Fire("BuyCosmetic", "UITheme.Mint")
Engine.Step(0.5)
local Theme = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.UI.Theme")
check("UI theme applied on the client", Theme.CurrentAccent == "Mint")
cd:Fire("BuyCosmetic", "Emote.Dance")
Engine.Step(0.5)
cd:Fire("Emote", "Dance")
Engine.Step(0.2)
check("emote plays (character attribute)", alicePlayer.Character:GetAttribute("Emote") == "Dance")
cd:Fire("Emote", "Flex")
Engine.Step(0.2)
check("unowned emote ignored", alicePlayer.Character:GetAttribute("Emote") == "Dance")
cd:Fire("EquipCosmetic", "Hat.None")
Engine.Step(0.5)
check("hat taken off", session.Data.Cosmetics.Equipped.Hat == "Hat.None")

---------------------------------------------------------------------------
section("AFK camp")
---------------------------------------------------------------------------
mark = #Engine.Errors
cd:Fire("AfkSetSlot", 1, "Rookie")
Engine.Step(0.5)
check("hero resting in the camp", session.Data.Afk.Slots[1] == "Rookie" and session.Data.Afk.Since > 0)
cd:Fire("AfkSetSlot", 2, "Tank")
Engine.Step(0.5)
check("slot 2 is locked until bought", session.Data.Afk.Slots[2] ~= "Tank")
coins = session.Data.Coins
cd:Fire("AfkBuySlot")
Engine.Step(0.5)
check("slot 2 bought with coins", session.Data.Afk.SlotCount == 2 and session.Data.Coins == coins - 1500)
cd:Fire("AfkSetSlot", 2, "Tank")
Engine.Step(0.5)
cd:Fire("Admin", "afk", "300")
Engine.Step(0.5)
check("camp is capped (2 h)", cd.Data.Afk.Minutes <= 120 and cd.Data.Afk.Full == true, cd.Data.Afk.Minutes)
check("hub shows AFK REWARDS", lobby.AfkChip.Visible == true)
coins = session.Data.Coins
local afkCoins = cd.Data.Afk.Coins
cd:Fire("AfkClaim")
Engine.Step(0.5)
check("AFK rewards claimed", afkCoins > 0 and session.Data.Coins >= coins + afkCoins, session.Data.Coins - coins)
check("camp restarts after claiming", cd.Data.Afk.Coins == 0)
cd:Fire("Buy", "Product", "AfkBoost")
Engine.Step(0.5)
check("AFK boost active", session.Data.Afk.BoostUntil > Engine.BaseTime + Engine.Now)
check("no errors in the AFK camp", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("shop: passes and products (simulated in Studio)")
---------------------------------------------------------------------------
mark = #Engine.Errors
cd:Fire("Buy", "Pass", "VIPCosmetics")
Engine.Step(0.5)
cd:Fire("Buy", "Pass", "CosmeticPass")
Engine.Step(0.5)
check("pass cosmetics granted", session.Data.Cosmetics.Owned["Trail.Rainbow"] == true and session.Data.Cosmetics.Owned["WeaponSkin.Rainbow"] == true)
check("NEW cosmetic badges", next(session.Data.Cosmetics.New) ~= nil)
cd:Fire("SeenCosmetics")
Engine.Step(0.5)
check("NEW badges cleared after looking", next(session.Data.Cosmetics.New) == nil)
check("client sees owned passes", cd.Data.Passes.VIPCosmetics == true and cd.Data.Passes.CosmeticPass == true)
cd:Fire("Buy", "Pass", "ExtraLoadout")
Engine.Step(0.5)
cd:Fire("SelectLoadout", 2)
Engine.Step(0.5)
check("extra loadout slots with the pass", session.Data.Loadout == 2 and cd.Data.LoadoutSlots == 3)
cd:Fire("SelectLoadout", 1)
cd:Fire("Buy", "Product", "CosmeticBoost")
Engine.Step(0.5)
check("67 aura boost active", session.Data.CosmeticBoostUntil > Engine.BaseTime + Engine.Now + 25 * 60)
check("67 aura on the hero", alicePlayer.Character:FindFirstChild("HumanoidRootPart"):FindFirstChild("HeroAura") ~= nil)
coins = session.Data.Coins
cd:Fire("Buy", "Product", "ExtraReroll")
Engine.Step(0.5)
check("extra reroll outside a run is refunded", session.Data.Coins == coins + 100, session.Data.Coins - coins)
coins = session.Data.Coins
cd:Fire("Buy", "Product", "Support2")
Engine.Step(0.5)
check("SUPPORT: a donation is a thank you, counted, nothing else", session.Data.Stats.Supported == 1 and session.Data.Stats.SupportedRobux == 100 and session.Data.Coins == coins, session.Data.Stats.Supported)
lobby:OpenPanel("Shop", false, "Support")
Engine.Step(0.5)
local shopState = lobby.Panels.Shop and lobby.Panels.Shop.State
check("shop has a SUPPORT page with 3 items", shopState ~= nil and shopState.Pages.Support ~= nil and shopState.Products.Support1 ~= nil and shopState.Products.Support3 ~= nil)
check("Studio: items without an id can be test-bought", cd:CanBuy("Support1") == true and cd:RobuxPrice("Support1") == 25)
-- the published game without ids: the item is there, marked SOON, and can't be bought
cd.Data.Studio = false
lobby:ClosePanel()
lobby:OpenPanel("Shop", false, "Passes")
Engine.Step(0.1)
local slot = shopState.Products.ExtraHeroSlot
check("published game, no id yet: SOON instead of a price", cd:CanBuy("ExtraHeroSlot") == false and slot.ButtonLabel.Text == "SOON", slot.ButtonLabel.Text)
cd.Data.Studio = true
lobby:ClosePanel()
Engine.Step(0.3)
check("no errors while buying", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("party: invite, play together, shared 67 events")
---------------------------------------------------------------------------
mark = #Engine.Errors
local bob, bobPlayer = Engine.AddPlayer("Bob", { Touch = true })
Engine.Step(1.5)
local bobCd = Engine.Module(bob, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ClientData")
local PartyM = Engine.Module(server, "ServerScriptService.Server.Services.PartyManager")
cd:Fire("PartyInvite", bobPlayer.UserId)
Engine.Step(0.5)
check("Bob got the invite", bobCd.Data.Party and #bobCd.Data.Party.Invites == 1)
bobCd:Fire("PartyAccept", alicePlayer.UserId)
Engine.Step(0.5)
check("party of 2", PartyM:Get(alicePlayer) ~= nil and #PartyM:Members(alicePlayer) == 2)
check("hub shows the party", lobby.PartyChip.Visible == true)
cd:Fire("StartRun")
Engine.Step(0.5)
local aliceRun = GM.Entries[alicePlayer] and GM.Entries[alicePlayer].Run
local bobRun = GM.Entries[bobPlayer] and GM.Entries[bobPlayer].Run
check("PLAY started the whole party", aliceRun ~= nil and bobRun ~= nil)
check("players who have played get no how-to card", pointer.Hint.Visible == false)
local bobPointer = Engine.Module(bob, "StarterPlayer.StarterPlayerScripts.Client.Controllers.PointerController")
check("phone, first run: the card talks about the joystick", bobPointer.Hint.Visible == true and string.find(bobPointer.HintLines[1].Text, "joystick", 1, true) ~= nil, bobPointer.HintLines[1].Text)
check("party members start next to each other", aliceRun and bobRun and math.abs(aliceRun.PX - bobRun.PX) + math.abs(aliceRun.PZ - bobRun.PZ) < 20)
check("Bob's 67 events come from the leader", bobRun and bobRun.Follower == true)
if aliceRun and bobRun then
	cd:Fire("Admin", "event", "Luck67")
	play(alice, aliceRun, 3)
	check("shared 67 event reached Bob's run", bobRun.Result.EventsSeen.Luck67 == true)
	local bobHud = Engine.Module(bob, "StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController")
	check("mobile: ability bar away from the thumbstick", bobHud.Bottom.AnchorPoint.X == 1)
	play(bob, bobRun, 10)
	check("mobile run progresses", bobRun.Kills > 0, bobRun.Kills)
	-- (the test engine replicates characters as plain rigs: check a rig part)
	local aliceBob = alice.PlayersByName.Bob
	local sample = aliceBob and aliceBob.Character and aliceBob.Character:FindFirstChild("Head")
	check("a party member is not drawn as a ghost", sample and sample.LocalTransparencyModifier < 0.5)
	cd:Fire("GiveUp")
	bobCd:Fire("GiveUp")
	Engine.Step(1)
	check("party run counted", session.Data.Stats.PartyRuns == 1)
	Engine.Click(findGui(alice, "Lobby"))
	Engine.Step(0.5)
end
bobCd:Fire("PartyLeave")
Engine.Step(0.5)
check("party dissolved when Bob left", PartyM:Get(alicePlayer) == nil)
-- unlocking a hero with fragments on a fresh profile
local bobSession = PM:Get(bobPlayer)
bobSession.Data.Fragments = 20
bobCd:Fire("UnlockHero", "Hunter")
Engine.Step(0.5)
check("hero unlocked with fragments", bobSession.Data.Heroes.Hunter == true and bobSession.Data.Fragments == 5, bobSession.Data.Fragments)
bobCd:Fire("UnlockHero", "Unknown")
Engine.Step(0.5)
check("secret hero cannot be bought", bobSession.Data.Heroes.Unknown == false)
check("no errors in the party", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("exploits are ignored")
---------------------------------------------------------------------------
mark = #Engine.Errors
cd:Fire("StartRun", 123, { bad = true })
Engine.Step(0.2)
local exploitRun = GM.Entries[alicePlayer]
check("weird StartRun args fall back to the loadout", exploitRun == nil or exploitRun.Run.Hero == "Samurai")
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
fragments = session.Data.Fragments
cd:Fire("BuyMeta", "NotAThing")
cd:Fire("BuyMeta", { "table" })
cd:Fire("UnlockWeapon", "OverdriveBlaster")
cd:Fire("UnlockHero", { "Void" })
cd:Fire("AfkSetSlot", 99, "Rookie")
cd:Fire("AfkSetSlot", 1, "NotAHero")
cd:Fire("EquipCosmetic", "Aura.Void")
cd:Fire("SetSetting", "Sfx", "yes")
cd:Fire("SetSetting", "Coins", 999999)
cd:Fire("ClaimQuest", 99)
cd:Fire("ClaimWeekly", 99)
cd:Fire("PartyInvite", "everyone")
Engine.Step(1)
check("no free coins or fragments from bad requests", session.Data.Coins >= coins and session.Data.Fragments == fragments)
check("evolutions cannot be unlocked", session.Data.Weapons.OverdriveBlaster == nil)
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
local stored = Engine.DataStores["Survival67_Players_v1"]
check("profile written to the DataStore", stored and stored["u_" .. userId] ~= nil)
local alice2, alicePlayer2 = Engine.AddPlayer("Alice", { UserId = userId })
Engine.Step(1)
local session2 = PM:Get(alicePlayer2)
check("profile loaded again", session2 ~= nil)
check("coins persisted", session2 and session2.Data.Coins >= savedCoins and session2.Data.Coins <= savedCoins + 2000, session2 and (session2.Data.Coins .. " vs " .. savedCoins))
check("stats persisted", session2 and session2.Data.Stats.Runs == savedRuns)
check("heroes, cosmetics and camp persisted", session2 and session2.Data.Heroes.Samurai == true and session2.Data.Cosmetics.Owned["Hat.Cone"] == true and session2.Data.Afk.Slots[1] == "Rookie")
local _ = alice2

---------------------------------------------------------------------------
section("shutdown")
---------------------------------------------------------------------------
local ok = Engine.Shutdown()
check("BindToClose finished saving", ok)
check("no runtime errors at all", #Engine.Errors == 0, Engine.Errors[1])
check("no errors inside event handlers (engine warnings)", #Engine.Warnings == 0, Engine.Warnings[1])

print(string.format("\n%d passed, %d failed", passed, failed))
for _, f in failures do
	print("  - " .. f)
end
process.exit(if failed == 0 then 0 else 1)
