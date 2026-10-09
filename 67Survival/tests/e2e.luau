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
-- 67 TOWN (five zones, lairs, vaults) + 67 LAND: static, anchored, no shadows; kept well under
-- what a phone draws comfortably next to a full horde
check("map part budget < 1500", parts < 1500, parts .. " parts")
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
	local ArenaData = Engine.Module(server, "ReplicatedStorage.Modules.ArenaData")
	-- the big duck pond of Goober Gardens (open from the start; visited, so no first-visit bonus)
	local pond = ponds[1]
	for _, w in ponds do
		if w.R > pond.R then
			pond = w
		end
	end
	run.Map.Visited[ArenaData.ZoneAt(pond.X, pond.Z).Key] = true
	check("the arena ponds are water in the simulation", #ponds >= 2 and run:InWater(pond.X, pond.Z) and not run:InWater(pond.X + pond.R + 1, pond.Z))
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
do
	-- game feel (GameConfig.Feel): pops, white flashes, the FOV pulse, the drop arcs
	local cached = 0
	for _, e in enemyRenderer.List do
		if e.Item and e.Item.Info.Colors then
			cached += 1
		end
	end
	check("feel: every enemy model knows its colours (white hit flash)", cached == enemyRenderer:Count(), cached .. " / " .. enemyRenderer:Count())
	check("feel: regular enemies pop when they die", #effects.Pops + #effects.PopFree > 0)
	local camera = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.CameraController")
	effects:PlayerHurt(30)
	check("feel: getting hurt breathes the camera out (FOV pulse)", camera.Fov ~= nil and camera.Fov.Amount > 0)
	local pickups = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.PickupRenderer")
	check("feel: gems hop out in an arc (bounded)", pickups.Dropping ~= nil and #pickups.Dropping <= 80)
end

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
section("boss 1 at 3:00 in its lair (the gardens)")
---------------------------------------------------------------------------
mark = #Engine.Errors
-- puts Alice somewhere in the arena (the server's speed check is told first)
local function teleport(x: number, z: number)
	local e = GM.Entries[alicePlayer]
	if e then
		e.LastX, e.LastZ = x, z
	end
	Engine.MoveCharacter("Alice", roblox.Vector3.new(x, ARENA_Y, z))
	Engine.Step(0.2)
end
-- an open level-up offer pauses the run: answer it (kill timing decides when one opens)
local function answerOffers(r)
	for _ = 1, 10 do
		if not r.Offer then
			return
		end
		cd:Fire("Choose", 1)
		Engine.Step(0.3)
	end
end
-- lets the run go on for `seconds` of RUN time while Alice stands at (x, z) (level-up cards
-- are picked: they pause the run)
local function hold(seconds: number, x: number?, z: number?)
	local levelUp = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.LevelUpController")
	local target = run.Time + seconds
	local guard = 0
	while run.Time < target and not run.Ended and guard < seconds * 40 + 40 do
		guard += 1
		if levelUp:IsOpen() and not levelUp.Busy then
			local card = findGui(alice, "Card1")
			if card then
				Engine.Click(card)
			end
		end
		if x and z then
			local e = GM.Entries[alicePlayer]
			if e then
				e.LastX, e.LastZ = x, z
			end
			Engine.MoveCharacter("Alice", roblox.Vector3.new(x, ARENA_Y, z))
		end
		Engine.Step(0.1, 0.05)
	end
end
cd:Fire("Admin", "god", "")
cd:Fire("Admin", "time", "165")
play(alice, run, 7)
local enc1 = run.Map.Encounters[1]
check("boss 1 announced 10 s early at its lair in the gardens", enc1 ~= nil and enc1.Slot == 1 and enc1.Zone == "Gardens" and enc1.Stage == "Warn", enc1 and enc1.Def.Key)
local key1 = enc1 and enc1.Def.Key or "?"
local banner = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.BannerController")
check("client: the BOSS 1 warning", runClient.Encounters[key1] ~= nil and runClient.Encounters[key1].Slot == 1)
check("HUD: the boss timeline says where it is", string.find(hud.BossLine.Text, "BOSS 1", 1, true) ~= nil and string.find(hud.BossLine.Text, "GARDENS", 1, true) ~= nil, hud.BossLine.Text)
hold(math.max(0.5, 181 - run.Time))
check("boss 1 spawned at 3:00 exactly", enc1 ~= nil and enc1.Stage == "Fight" and math.abs(enc1.SpawnedAt - 180) < 0.2, enc1 and enc1.SpawnedAt)
check("bosses 1-4 have a plate over their head, not the top bar", hud.BossPanel.Visible == false)
local body1 = enc1 and enc1.Bodies[1]
if body1 then
	teleport(body1.X + 12, body1.Z)
	hold(2, body1.X + 12, body1.Z)
end
local drawn1 = body1 and runClient.Enemies[body1.Id]
check("client: its name plate says BOSS 1", drawn1 ~= nil and drawn1.Plate ~= nil and string.find(drawn1.Plate.Status.Text, "BOSS 1", 1, true) ~= nil, drawn1 and drawn1.Plate and drawn1.Plate.Status.Text)
check("it fights you when you are close", body1 ~= nil and body1.Engaged == true)
local bossesBefore = #run.Result.Bosses
cd:Fire("Admin", "killall", "")
Engine.Step(0.5)
check("boss defeated", #run.Result.Bosses == bossesBefore + 1 and run.Result.BossSlots[1] == 1)
check("it dropped an item on the map", #run.Loot >= 1, #run.Loot)
if enc1 then
	teleport(enc1.LastX, enc1.LastZ)
	hold(1.5, enc1.LastX, enc1.LastZ)
end
check("walked over its loot: ITEM ACQUIRED", #run.ItemOrder >= 1 and hud.ItemCard.Visible == true, #run.ItemOrder)
check("HUD: your items row (with levels)", #hud.ItemRow:GetChildren() >= 2)
check("boss dropped a fragment that was picked up", run.Result.Fragments >= 1, run.Result.Fragments)
play(alice, run, 4)
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
section("67 TOWN: zones, minimap, bosses, elites, items, THE FINAL ONE")
---------------------------------------------------------------------------
mark = #Engine.Errors
do
	local ArenaData = Engine.Module(server, "ReplicatedStorage.Modules.ArenaData")
	local ItemData = Engine.Module(server, "ReplicatedStorage.Modules.ItemData")
	local BossData = Engine.Module(server, "ReplicatedStorage.Modules.BossData")
	local Items = Engine.Module(server, "ServerScriptService.Server.Sim.Items")
	local MiniBosses = Engine.Module(server, "ServerScriptService.Server.Sim.MiniBosses")
	local EnemyManager = Engine.Module(server, "ServerScriptService.Server.Sim.EnemyManager")
	local minimap = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.MinimapController")
	local arenaC = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ArenaController")
	local loot = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.LootRenderer")
	check("the battle map is 67 TOWN", map.Arena:GetAttribute("MapName") == "67 TOWN")
	check("the minimap shows in a run", minimap.Gui.Enabled == true)
	check("the zone chip names the zone you are in", string.find(hud.ZoneName.Text, ArenaData.ZoneAt(run.PX, run.PZ).Name, 1, true) ~= nil, hud.ZoneName.Text)
	check("the rift gates are sealed for you until the rift opens", #arenaC.Seals == 3 and (run.Map.RiftOpen or arenaC.Seals[1].Part.CanCollide == true), #arenaC.Seals)
	check("THE 67 ARENA in the centre: pylons and its seal ring", #arenaC.Pylons >= 8 and #arenaC.ArenaSeals >= 30 and arenaC.ArenaSeals[1].CanCollide == false, #arenaC.ArenaSeals)

	-- a boss (debug: THE BIG QUACK now): the warning, its lair lights up, it arrives
	teleport(-100, 40)
	cd:Fire("Admin", "boss", "BigQuack")
	Engine.Step(0.3)
	local enc = nil
	for _, e in run.Map.Encounters do
		if e.Def.Key == "BigQuack" then
			enc = e
		end
	end
	check("server: THE BIG QUACK is coming (to its lair)", enc ~= nil and enc.Lair ~= nil and enc.Lair.Key == "DuckPond")
	check("client: the BOSS warning", runClient.Encounters.BigQuack ~= nil and string.find(banner.Giant.Text, "BOSS", 1, true) ~= nil, banner.Giant.Text)
	check("its lair lights up", arenaC.Lit.DuckPond == true)
	hold(3.5, -100, 40)
	local quack = enc and enc.Bodies[1]
	check("it arrived at its lair", quack ~= nil and quack.Alive and quack.Key == "BigQuack")
	local drawn = quack and runClient.Enemies[quack.Id]
	check("client: its name plate and HP bar", drawn ~= nil and drawn.Plate ~= nil and drawn.Plate.Fill ~= nil)
	local arrow = false
	for _, t in pointer:Targets() do
		if string.find(t.Tag or "", "BOSS", 1, true) then
			arrow = true
		end
	end
	check("an arrow points to it: BOSS + distance", arrow)
	local marked = false
	for _, t in minimap:Targets(os.clock()) do
		if t.Glyph == tostring(enc and enc.Slot) and (t.Size or 0) >= 15 then
			marked = true
		end
	end
	check("the minimap marks it (big, with its number)", marked)
	-- walk up to it: it fights (telegraphed flops)
	teleport(-150, 140)
	hold(1.6, -150, 140)
	check("it fights you when you are close", quack ~= nil and quack.Engaged == true)
	local telegraphed = false
	for _ = 1, 16 do
		if #run.Telegraphs + #run.Hazards > 0 then
			telegraphed = true
			break
		end
		hold(0.5, -150, 140)
	end
	check("its attacks are telegraphed on the ground", telegraphed)
	local mini = quack and runClient.Minis[quack.Id]
	check("the name plate follows its HP", drawn ~= nil and drawn.Plate ~= nil and mini ~= nil and mini.HP ~= nil and mini.HP < 1, mini and mini.HP)
	-- its weak point: exposed, the plate says so
	if quack then
		MiniBosses.Expose(run, quack, "Flop")
		Engine.Step(0.3)
	end
	check("WEAK POINT: the plate says it", drawn ~= nil and drawn.Plate ~= nil and string.find(drawn.Plate.Status.Text, "WEAK POINT", 1, true) ~= nil, drawn and drawn.Plate and drawn.Plate.Status.Text)
	-- defeat it (from a distance, so its loot stays on the ground): an item on the map
	teleport(-100, 40)
	local lootBefore = #run.Loot
	cd:Fire("Admin", "killall", "")
	Engine.Step(0.5)
	check("defeated: the encounter is over", runClient.Encounters.BigQuack == nil and run.Result.BossesBeaten >= 2, run.Result.BossesBeaten)
	check("it dropped an item on the ground", #run.Loot > lootBefore, #run.Loot)
	check("client draws the item (beam + name)", next(loot.Items) ~= nil)
	local itemsBefore = run.Result.ItemsPicked
	local l = run.Loot[#run.Loot]
	if l then
		teleport(l.X, l.Z)
		Engine.Step(0.3)
	end
	check("walked over it: the item is yours (or a level up)", run.Result.ItemsPicked > itemsBefore, run.Result.ItemsPicked)
	local key = run.ItemOrder[1]
	check("your items are real items", key ~= nil and ItemData.ByKey[key] ~= nil)
	-- the same item again: level II, the card says I -> II
	if key then
		answerOffers(run)
		local level = run.Items[key]
		Items.Drop(run, key, run.PX + 1, run.PZ)
		Engine.Step(0.4)
		check("found again: level up", run.Items[key] == math.min(level + 1, ItemData.ByKey[key].MaxLevel), run.Items[key])
		check("ITEM LEVEL UP card: old -> new", hud.ItemCard.Visible == true and (run.Items[key] == level or string.find(hud.ItemCardTag.Text, "→", 1, true) ~= nil), hud.ItemCardTag.Text)
	end

	-- the DASH of the Rocket Skates
	Items.Gain(run, "RocketSkates")
	Engine.Step(0.3)
	answerOffers(run)
	check("dash button appears with the Rocket Skates", hud.DashButton.Visible == true)
	local bx, bz = run.PX, run.PZ
	runClient:RequestDash()
	Engine.Step(0.4)
	check("dash: the server moved you and spent the charge", (run.PX - bx) ^ 2 + (run.PZ - bz) ^ 2 > 9 and run.DashState.Charges < run.DashState.Max, string.format("%.1f,%.1f", run.PX - bx, run.PZ - bz))

	-- an ELITE: a name plate with its affixes, a marker, an arrow
	cd:Fire("Admin", "elite", "Husk")
	Engine.Step(0.8)
	local eliteId = next(runClient.Elites)
	local eliteDrawn = eliteId and runClient.Enemies[eliteId]
	check("an ELITE appeared (server + client)", eliteId ~= nil and #run.Elites >= 1)
	check("its plate: ELITE + affixes", eliteDrawn ~= nil and eliteDrawn.Plate ~= nil and string.find(eliteDrawn.Plate.Name.Text, "ELITE", 1, true) ~= nil, eliteDrawn and eliteDrawn.Plate and eliteDrawn.Plate.Name.Text)
	local eliteMarker = false
	for _, t in minimap:Targets(os.clock()) do
		eliteMarker = eliteMarker or t.Glyph == "E"
	end
	check("the minimap marks the elite", eliteMarker)
	local elitesBefore = run.Result.Elites or 0
	cd:Fire("Admin", "killall", "")
	Engine.Step(0.5)
	check("elite killed: counted, gone from the client", (run.Result.Elites or 0) > elitesBefore and next(runClient.Elites) == nil)

	-- a 67 VAULT and the 67 RUSH
	answerOffers(run)
	cd:Fire("Admin", "vault", "")
	cd:Fire("Admin", "rush", "")
	Engine.Step(0.5)
	local awake = nil
	for i, v in run.Map.Vaults do
		if v.State == 1 then
			awake = i
		end
	end
	check("a 67 VAULT woke up and glows for you", awake ~= nil and arenaC.Lit["vault:" .. awake] == true)
	check("a 67 RUSH zone is on (the client knows which)", run.Map.Hot ~= nil and runClient.Map.Hot == run.Map.Hot.Zone, runClient.Map.Hot)
	if awake then
		local v = ArenaData.Vaults[awake]
		local before = #run.Loot
		teleport(v.X, v.Z)
		Engine.Step(4.8)
		check("stand on the vault: it cracks open (an item pops out)", run.Result.Vaults >= 1 and (#run.Loot > before or run.Result.ItemsPicked > 0), run.Result.Vaults)
	end

	-- the rift opens
	answerOffers(run)
	if not run.Map.RiftOpen then
		cd:Fire("Admin", "time", tostring(ArenaData.RiftOpensAt - 1))
		Engine.Step(1.5)
	end
	check("THE RIFT opens: the gates let you through", run.Map.RiftOpen == true and runClient.Map.Rift == true and arenaC.Seals[1].Part.CanCollide == false)

	-- THE FINAL ONE: 15:00, exactly in the centre, the arena seals when you walk in
	teleport(70, 0)
	cd:Fire("Admin", "killall", "")
	cd:Fire("Admin", "time", tostring(BossData.Main.At - 12))
	Engine.Step(0.2)
	hold(4, 70, 0)
	local main = nil
	for _, e in run.Map.Encounters do
		if e.Main then
			main = e
		end
	end
	check("the bosses 2-4 the jump went past never came", main ~= nil and #run.Map.Encounters == 1 and run.BossNext == 5, #run.Map.Encounters)
	-- (this run is on CALM: its main boss is MAMA GOOBER; every tier has its own)
	local mainDef = BossData.MainFor(run.Difficulty)
	check("the tier's main boss announced (client + HUD)", runClient.Encounters[mainDef.Key] ~= nil and runClient.Encounters[mainDef.Key].Main == true and string.find(hud.BossLine.Text, mainDef.Title, 1, true) ~= nil, hud.BossLine.Text)
	hold(9, 70, 0)
	local boss = main and main.Bodies[1]
	check(
		"it spawned exactly in the centre at 15:00 (and waits there)",
		boss ~= nil and boss.HomeX == BossData.Main.X and boss.HomeZ == BossData.Main.Z and (boss.X - BossData.Main.X) ^ 2 + (boss.Z - BossData.Main.Z) ^ 2 < 1 and math.abs(main.SpawnedAt - BossData.Main.At) < 0.2,
		boss and string.format("%.2f,%.2f", boss.X, boss.Z)
	)
	check("the top boss bar is the main boss's", hud.BossPanel.Visible == true and runClient.Boss ~= nil and runClient.Boss.Key == mainDef.Bodies[1], runClient.Boss and runClient.Boss.Key)
	local big = false
	for _, t in minimap:Targets(os.clock()) do
		big = big or (t.Glyph == "67" and t.Size >= 20)
	end
	check("the minimap marks it: a huge 67", big)
	check("its pylons burn", arenaC.Lit.arena == true)
	teleport(10, 0)
	hold(0.6, 10, 0)
	check("you walked in: the arena is sealed (server + client ring)", run.Map.ArenaSealed ~= nil and runClient.Arena ~= nil and arenaC.ArenaSeals[1].CanCollide == true)
	check("nobody walks out of the ring", Items.Blocked(run, BossData.Main.ArenaR + 6, 0) == true)
	-- LIGHTS OUT (THE DREAD's arena mechanic) on the client: dark around you, then light again
	local Lighting = alice.Game:GetService("Lighting")
	local bright = Lighting.Brightness
	run:Event("Arena", { Dark = true, Time = 1.5 })
	Engine.Step(1)
	check("lights out: the scene darkens, a lamp follows you", arenaC.Lights ~= nil and arenaC.Lamp ~= nil)
	Engine.Step(3)
	check("the lights come back", arenaC.Lights == nil and arenaC.Lamp == nil and math.abs(Lighting.Brightness - bright) < 0.05, Lighting.Brightness)
	-- (the test run goes on: the main boss leaves without a fight)
	if main then
		MiniBosses.Finish(run, main, "Left", EnemyManager)
	end
	Engine.Step(0.5)
	check("the seal is gone with it", run.Map.ArenaSealed == nil and runClient.Arena == nil and arenaC.ArenaSeals[1].CanCollide == false)
	teleport(0, 20)
	cd:Fire("Admin", "killall", "")
	Engine.Step(0.5)

	-- the harder tiers' enemies on the client: a shield that breaks, an elite in its affixes,
	-- a sector telegraph, a sketch
	local Bosses = Engine.Module(server, "ServerScriptService.Server.Sim.Bosses")
	local weaponFx = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.WeaponFx")
	local shielder = EnemyManager.Spawn(run, "Shielder", run.PX + 14, run.PZ, { Force = true })
	shielder.HP, shielder.MaxHP = 1e6, 1e6 -- (your weapons keep firing: it must outlive the check)
	hold(0.4)
	local view = runClient.Enemies[shielder.Id]
	local shieldPart = nil
	for _, p in (view and view.Item and view.Item.Info.Parts) or {} do
		if p.Name == "Shield" then
			shieldPart = p
		end
	end
	check("a Shielder carries its shield", shieldPart ~= nil and shieldPart.Transparency < 1)
	EnemyManager.Damage(run, shielder, shielder.Guard / shielder.Def.Params.GuardCut * 1.01, 0, shielder.X - run.PX, shielder.Z - run.PZ, 0)
	hold(0.4)
	check("its shield breaks off (client)", shielder.Guard == nil and shieldPart ~= nil and shieldPart.Transparency == 1)
	local Elites = Engine.Module(server, "ServerScriptService.Server.Sim.Elites")
	Elites.Spawn(run, "Husk", run.PX + 16, run.PZ + 6, { "Gilded67" })
	hold(0.6)
	local gilded = nil
	for _, e in run.Elites do
		if e.Alive and e.CoinMult then
			gilded = e
		end
	end
	local gv = gilded and runClient.Enemies[gilded.Id]
	check("a GILDED 67 elite: gold, two more affixes, a 67 over its head", gilded ~= nil and #gilded.Affixes == 3 and gv ~= nil and gv.Item ~= nil and gv.Item.Gui ~= nil and gv.Item.Recolored ~= nil)
	local gItem = gv and gv.Item
	if gilded then
		EnemyManager.Damage(run, gilded, gilded.MaxHP * 20, 0, 0, 0, 0)
	end
	hold(0.8)
	check("its gold comes off when it goes back to the pool", gItem == nil or (gItem.Gui == nil and gItem.Recolored == nil))
	Bosses.Telegraph(run, nil, 7, run.PX, run.PZ, 0.5, 20, 0.4, 1.2, 1, "Sector", nil, { Burn = 1.2 })
	Bosses.Telegraph(run, nil, 10, run.PX, run.PZ, 0.5 + math.pi, 20, 0.4, 1.2, 0)
	hold(0.3)
	check("sectors are drawn (a burning one and a safe one)", weaponFx.SectorTeles ~= nil and #weaponFx.SectorTeles == 2, weaponFx.SectorTeles and #weaponFx.SectorTeles)
	hold(3)
	check("they clear after their burn", #weaponFx.SectorTeles == 0)
	local sketch = EnemyManager.Spawn(run, "Brute", run.PX - 14, run.PZ, { Force = true, Elite = true, Sketch = true, Life = 3 })
	hold(0.4)
	local sv = runClient.Enemies[sketch.Id]
	check("a sketch looks like pencil on paper", sv ~= nil and sv.Item ~= nil and string.find(sv.Item.Key, "s", 1, true) ~= nil and sv.Item.Root.Transparency >= 0.25, sv and sv.Item and sv.Item.Key)
	cd:Fire("Admin", "killall", "")
	Engine.Step(0.5)
end
check("no errors in 67 TOWN", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("every ability kind + evolution")
---------------------------------------------------------------------------
mark = #Engine.Errors
cd:Fire("Admin", "unlockall", "")
for i, key in { "Katana", "Orb67", "FireRing", "IceField", "PoisonCloud", "Meteor", "Shockwave", "ChainLightning", "Laser", "BlackHole", "GiantFist", "SwordStorm", "Drone", "Clone", "GooberFriends", "Barrier", "Glitch", "Chaos", "Blast67", "SigmaStare", "BananaBomb", "Boomerang", "Rocket", "MagicMissile", "Arrow", "Lightning", "SigmaAura", "OrbitalBlades", "PulseBlast", "SolarBeam67", "BlackHolePet", "GoldenMeteors", "TimeBubble", "PhoenixFamiliar", "ChainStorm", "AuraCrown" } do
	cd:Fire("Admin", "weapon", key)
	if i % 4 == 0 then
		Engine.Step(1) -- admin commands are rate limited too
	end
end
play(alice, run, 12)
check("run holds many abilities (slots ignored by debug)", #run.Weapons >= 32, #run.Weapons)
do
	local wfx = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.WeaponFx")
	local always = wfx.Premium and wfx.Premium.Always or {}
	check("premium pets and the crown are drawn (black hole, phoenix, crown)", always.BlackHolePet ~= nil and always.PhoenixFamiliar ~= nil and always.AuraCrown ~= nil)
	local pet = always.BlackHolePet
	check("the black hole pet follows the server's positions", pet ~= nil and wfx.Premium.PetAt.BlackHolePet ~= nil)
	local fireballs = 0
	for _, p in wfx.Projectiles do
		if p.Style == "Fireball" then
			fireballs += 1
		end
	end
	local phoenix = run:GetWeapon("PhoenixFamiliar")
	check("the phoenix shoots (server)", phoenix ~= nil and phoenix.Timer < phoenix.S.Cooldown + 0.5)
end
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
section("the bestiary: models, animation, every new enemy in a run")
---------------------------------------------------------------------------
mark = #Engine.Errors
do
	local EnemyModels = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Render.EnemyModels")
	local EnemyAnimator = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Render.EnemyAnimator")
	local EnemyData = Engine.Module(server, "ReplicatedStorage.Modules.EnemyData")
	-- every model of the bestiary builds within its part budget (an elite with its elite ring)
	local BUDGET = { Regular = 10, Minion = 10, Elite = 18, Boss = 45 }
	local bossModels = {}
	for _, def in EnemyData.List do
		if def.Role == "Boss" then
			bossModels[def.Model] = true
		end
	end
	local over, built, moving = {}, 0, 0
	for _, def in EnemyData.List do
		if def.Role then
			local variant = if def.Role == "Elite" then "e" else ""
			local model, root, info = EnemyModels.Build(def, variant)
			local n = #info.Parts
			-- (a minion that is a shrunken boss - an echo, a hologram - has a boss's budget)
			if n > (if bossModels[def.Model] or def.Model == "OverclockHolo" then BUDGET.Boss else BUDGET[def.Role]) then
				table.insert(over, def.Key .. " " .. n)
			end
			built += 1
			-- the animator moves its parts (a few frames of every kind)
			local item = { Root = root, Info = info }
			local e = { Phase = 1.3, RX = 0, RZ = 0 }
			for f = 1, 3 do
				EnemyAnimator.Pose(e, item, f * 0.1, 0.1, 0.5, false)
				EnemyAnimator.Parts(item, f * 0.1)
			end
			if info.Anims then
				for _, a in info.Anims do
					if a.Kind ~= "Pulse" and a.Motor.C0 ~= a.Base then
						moving += 1
						break
					end
				end
			end
			EnemyModels.Reset(item)
			model:Destroy()
		end
	end
	check("every bestiary model builds within its part budget", #over == 0 and built >= 37, table.concat(over, ", "))
	check("their parts move (wings, capes, jaws, moons...)", moving >= 20, moving)
	-- the Studio Models (models/Enemies -> ReplicatedStorage/Enemies): switched on with UseInGame,
	-- the game builds an enemy from its Model instead of the code: same parts, same moving parts
	local file = require("@lune/fs").readFile("models/Enemies/1 CALM - Meadow/MegaSix.rbxm")
	local loaded = roblox.deserializeModel(file)[1]
	local folder = roblox.Instance.new("Folder")
	folder.Name = "Enemies"
	folder:SetAttribute("UseInGame", true)
	loaded.Parent = folder
	folder.Parent = rawget(alice.Game:GetService("ReplicatedStorage"), "__real")
	local def = EnemyData.ByKey.MegaSix
	local _, studioRoot, studio = EnemyModels.Build(def, "e")
	folder:SetAttribute("UseInGame", false)
	local _, _, coded = EnemyModels.Build(def, "e")
	folder:Destroy()
	check("a Studio Model replaces the code model when UseInGame is on",
		#studio.Parts == #coded.Parts and #studio.Anims == #coded.Anims and math.abs(studio.Height - coded.Height) < 1e-3 and studioRoot.Anchored,
		#studio.Parts .. "/" .. #coded.Parts)
end
-- every new enemy, elite and minion in a live run (server AI + client renderer), god mode on
local invulnerable = run.Invulnerable
run.Invulnerable = 1e9
local spawned = 0
for _, def in Engine.Module(server, "ReplicatedStorage.Modules.EnemyData").List do
	if def.Role and def.Role ~= "Boss" then
		cd:Fire("Admin", "spawn", def.Key)
		spawned += 1
		if spawned % 4 == 0 then
			Engine.Step(1)
		end
	end
end
play(alice, run, 8)
check("no errors with every bestiary enemy in the run", errorsSince(mark) == 0, Engine.Errors[mark + 1])
cd:Fire("Admin", "killall", "")
Engine.Step(1)
run.Invulnerable = invulnerable

---------------------------------------------------------------------------
section("death -> results -> rewards saved")
---------------------------------------------------------------------------
mark = #Engine.Errors
local coinsBefore = session.Data.Coins
local fragmentsBefore = session.Data.Fragments
local chipsBefore = session.Data.Chips
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
check("results show fragments and CHIPS", results.StatLabels.Fragments.Text ~= "+0" and results.StatLabels.Chips.Text ~= "+0", results.StatLabels.Chips.Text)
check("CHIPS rewarded for this run (bosses, elites, time)", session.Data.Chips > chipsBefore, session.Data.Chips - chipsBefore)
check("items found are in the collection", next(session.Data.Seen.Items) ~= nil)
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
section("ITEMS: unlock premium items with CHIPS")
---------------------------------------------------------------------------
mark = #Engine.Errors
session.Data.Chips = 1000
table.clear(session.Data.ItemUnlocks) -- (the debug "unlockall" above unlocked everything)
lobby:OpenPanel("Items")
Engine.Step(0.5)
local itemsPanel = lobby.Panels.Items
check("the ITEMS menu opens (lobby nav)", itemsPanel ~= nil and itemsPanel.Frame.Visible == true and lobby.NavButtons.Items ~= nil)
cd:Fire("UnlockItem", "RicochetCore")
Engine.Step(0.5)
check("premium item unlocked: CHIPS spent", session.Data.ItemUnlocks.RicochetCore == true and session.Data.Chips == 1000 - 400, session.Data.Chips)
check("the menu shows the new balance", itemsPanel.State.Balance.Text == "600", itemsPanel.State.Balance.Text)
cd:Fire("UnlockItem", "RicochetCore")
cd:Fire("UnlockItem", "Fragment67")
cd:Fire("UnlockItem", "MagneticBolt")
Engine.Step(0.5)
check("no double buy, no unlock without the CHIPS, base items are free", session.Data.Chips == 600 and session.Data.ItemUnlocks.Fragment67 == nil and session.Data.ItemUnlocks.MagneticBolt == nil)
lobby:ClosePanel()
Engine.Step(0.3)
check("no errors in the ITEMS menu", errorsSince(mark) == 0, Engine.Errors[mark + 1])

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
section("shop: PREMIUM abilities, the free trial, skins, the trail pack")
---------------------------------------------------------------------------
mark = #Engine.Errors
lobby:OpenPanel("Shop", false, "Premium")
Engine.Step(0.5)
local premiumCards = shopState.PremiumCards
local n = 0
for _ in premiumCards do
	n += 1
end
check("PREMIUM page: 7 Mythic ability cards + the trial", shopState.Pages.Premium.Visible == true and n == 7 and shopState.Trial ~= nil)
check("Mythic cards have the animated border", premiumCards.SolarBeam67.Card:FindFirstChildOfClass("UIStroke"):FindFirstChild("MythicShine") ~= nil)
check("Studio, no id yet: TEST BUY", premiumCards.SolarBeam67.ButtonLabel.Text == "TEST BUY", premiumCards.SolarBeam67.ButtonLabel.Text)
cd:Fire("Buy", "Pass", "Ability.SolarBeam67")
Engine.Step(0.5)
check("test purchase: SOLAR BEAM 67 owned", cd.Data.Premium.Owned.SolarBeam67 == true and premiumCards.SolarBeam67.ButtonLabel.Text == "OWNED")
local trialKey = cd.Data.Premium.Trial
check("today's trial is one you don't own", trialKey ~= nil and trialKey ~= "SolarBeam67", trialKey)
cd:Fire("PremiumTrial")
Engine.Step(0.5)
check("TRY IT FREE: armed for the next run", cd.Data.Premium.TrialArmed == true and shopState.Trial.ButtonLabel.Text == "NEXT RUN", shopState.Trial.ButtonLabel.Text)
Engine.Step(2) -- (purchases are rate limited)
cd:Fire("Buy", "Product", "Skin.Void")
Engine.Step(1.2)
cd:Fire("Buy", "Pass", "TrailPack")
Engine.Step(1.2)
check("ability skin bought (saved)", session.Data.Cosmetics.Owned["WeaponSkin.Void"] == true)
check("trail pack: Comet, Sakura, Pixel", session.Data.Cosmetics.Owned["Trail.Comet"] == true and session.Data.Cosmetics.Owned["Trail.Sakura"] == true and session.Data.Cosmetics.Owned["Trail.Pixel"] == true)
cd:Fire("EquipCosmetic", "Trail.Pixel")
Engine.Step(0.5)
local root = alicePlayer.Character and alicePlayer.Character:FindFirstChild("HumanoidRootPart")
local trails = 0
for _, child in root and root:GetChildren() or {} do
	if child:IsA("Trail") then
		trails += 1
	end
end
check("one trail on the hero (Pixel)", trails == 1 and session.Data.Cosmetics.Equipped.Trail == "Trail.Pixel", trails)
cd:Fire("EquipCosmetic", "Trail.None")
-- the published game without ids: COMING SOON, nothing can be bought
cd.Data.Studio = false
lobby:ClosePanel()
lobby:OpenPanel("Shop", false, "Premium")
Engine.Step(0.1)
check("published game, no id yet: COMING SOON", premiumCards.AuraCrown.ButtonLabel.Text == "COMING SOON", premiumCards.AuraCrown.ButtonLabel.Text)
cd.Data.Studio = true
lobby:ClosePanel()
Engine.Step(0.3)
check("no errors in the premium shop", errorsSince(mark) == 0, Engine.Errors[mark + 1])

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
check("the free trial joined the run (once)", aliceRun ~= nil and aliceRun.Trial == trialKey and aliceRun:GetWeapon(trialKey) ~= nil and session.Data.Premium.TrialUses == 1 and session.Data.Premium.TrialKey == "")
check("an owned premium ability can show up in level ups", aliceRun ~= nil and aliceRun.Unlocked.SolarBeam67 == true and session.Data.Weapons.SolarBeam67 == nil)
check("Bob (owns nothing) has no premium ability", bobRun ~= nil and bobRun.Unlocked.SolarBeam67 == nil and bobRun.Trial == nil)
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
	-- loot is personal: an item dropped in Alice's run is never Bob's (and the other way round)
	local ItemsP = Engine.Module(server, "ServerScriptService.Server.Sim.Items")
	local bobLoot = #bobRun.Loot
	ItemsP.Drop(aliceRun, "Fang", aliceRun.PX + 1, aliceRun.PZ)
	Engine.Step(0.5)
	check("party: items are dropped for each player on their own", #bobRun.Loot == bobLoot and (bobRun.Items.Fang or 0) == 0)
	check("party: separate builds (items, synergies)", aliceRun.Items ~= bobRun.Items and aliceRun.Synergies ~= bobRun.Synergies)
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
local chipsNow = session.Data.Chips
cd:Fire("UnlockItem", { "table" })
cd:Fire("UnlockItem", "NotAnItem")
cd:Fire("UnlockItem", "Fragment67")
Engine.Step(1)
check("no free coins or fragments from bad requests", session.Data.Coins >= coins and session.Data.Fragments == fragments)
check("evolutions cannot be unlocked", session.Data.Weapons.OverdriveBlaster == nil)
check("items cannot be unlocked without CHIPS", session.Data.Chips == chipsNow and session.Data.ItemUnlocks.Fragment67 == nil)
check("settings keep their type", session.Data.Settings.Sfx == true)
check("unknown settings ignored", session.Data.Settings.Coins == nil)
check("no server errors from bad requests", errorsSince(mark) == 0, Engine.Errors[mark + 1])

---------------------------------------------------------------------------
section("save -> leave -> rejoin")
---------------------------------------------------------------------------
local savedCoins = session.Data.Coins
local savedRuns = session.Data.Stats.Runs
local savedChips = session.Data.Chips
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
check("CHIPS and item unlocks persisted", session2 and session2.Data.ItemUnlocks.RicochetCore == true and session2.Data.Chips == savedChips, session2 and session2.Data.Chips)
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
