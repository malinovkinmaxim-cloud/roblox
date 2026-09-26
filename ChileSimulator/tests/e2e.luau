--!nocheck
--[[
	End-to-end test: the REAL server + client scripts running in tests/engine.luau.
	Run from ChileSimulator/:   lune run tests/e2e.luau

	Covers the final checklist: RemoteEvents, DataStore (save / load / session lock / outage /
	BindToClose), Rebirth, Tap, visual stretching, mobile layout, UI panels, exploits,
	network / instance budget.
]]

local process = require("@lune/process")
local Engine = require("./engine")

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

local function textOf(button)
	local label = button:FindFirstChild("Label")
	return label and label.Text or ""
end

-- first TextButton under root whose "Label" text contains `pattern` (plain)
local function findButton(root, pattern: string)
	for _, d in rawget(root, "__real"):GetDescendants() do
		if d:IsA("TextButton") then
			local label = d:FindFirstChild("Label")
			if label and string.find(label.Text, pattern, 1, true) then
				return Engine.Wrap(d, rawget(root, "__world"))
			end
		end
	end
	return nil
end

local function errorsSince(mark: number): number
	return #Engine.Errors - mark
end

---------------------------------------------------------------------------
section("boot")
---------------------------------------------------------------------------
local server = Engine.StartServer()
check("server boots without errors", #Engine.Errors == 0)
local PlayerService = Engine.Module(server, "ServerScriptService.Server.Services.PlayerService")
local DataService = Engine.Module(server, "ServerScriptService.Server.Services.DataService")
local WorldService = Engine.Module(server, "ServerScriptService.Server.Services.WorldService")
check("DataStore available -> persistent saving", DataService.Persistent == true)
local map = server.Game:GetService("Workspace"):FindFirstChild("ChileMap")
check("map is built", map ~= nil)
local serverParts = Engine.Count(map, "BasePart")
check("map part budget < 1500", serverParts < 1500, serverParts .. " parts")
print("       map: " .. serverParts .. " parts")

local alice, alicePlayer = Engine.AddPlayer("Alice")
-- this scenario tests the classic (manual) UI; one-button mode has its own test (e2e_onebutton)
Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ClientData"):Fire("SetSetting", "OneButton", false)
Engine.SpawnCharacter("Alice")
Engine.Step(1)
local session = PlayerService:Get(alicePlayer)
check("server session created", session ~= nil)
check("one-button mode is the default, classic mode can be chosen", session.Data.Settings.OneButton == false)
local cd = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ClientData")
local hud = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController")
local bodies = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.BodyController")
local tapper = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.TapController")
local panels = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.PanelController")
local hatch = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.HatchController")
check("client received its data (Sync)", cd.Loaded == true)
check("HUD visible after load", hud.Gui and hud.Gui.Enabled == true)
check("HUD shows the start height 0.01 m", hud.HeightLabel.Text == "0.01 m", hud.HeightLabel.Text)
local localPlayer = alice.LocalPlayer
local body = bodies:GetBody(localPlayer)
check("stretched body built for the local player", body ~= nil)
check("start body is a flat cutlet (wider than tall)", body and body.Shape.Width > body.Shape.Body, body and body.Shape.Body)
check("real rig is invisible on the server", alicePlayer.Character.Head.Transparency == 1)

---------------------------------------------------------------------------
section("tap -> grow")
---------------------------------------------------------------------------
local mark = #Engine.Errors
local startBody = body.Shape.Body
for _ = 1, 30 do
	tapper:Tap(nil)
	Engine.Step(0.1)
end
Engine.Step(0.5)
check("30 taps -> +30 cm on the server", session.Data.Height == 31, session.Data.Height)
check("taps counted", session.Data.Taps == 30, session.Data.Taps)
check("coins earned", session.Data.Coins > 0, session.Data.Coins)
check("HUD height follows", hud.HeightLabel.Text == "0.31 m", hud.HeightLabel.Text)
check("body got taller", body.Shape.Body > startBody * 2, body.Shape.Body)
check("player attribute replicated", localPlayer:GetAttribute("Height") == 31)
check("no errors while tapping", errorsSince(mark) == 0)

-- keyboard (Space) and world clicks also tap
local cas = alice.Stubs.ContextActionService
local action = cas.Actions.TallerTap or cas.Actions.ChileTap
check("Space / Enter bound", action ~= nil)
if action then
	action.Fn("ChileTap", Engine.Unwrap and require("@lune/roblox").Enum.UserInputState.Begin, {})
end
alice.Stubs.UserInputService.InputBegan:Fire({ UserInputType = require("@lune/roblox").Enum.UserInputType.MouseButton1, Position = require("@lune/roblox").Vector3.new(10, 10, 0) }, false)
Engine.Step(0.5)
check("Space + mouse click taps reach the server", session.Data.Taps == 32, session.Data.Taps)

-- upgrade from the HUD button
session.Data.Coins = 1000
session.Dirty.Stats = true
Engine.Step(0.3)
Engine.Click(hud.TapUpgrade)
Engine.Step(0.3)
check("TAP POWER bought from the HUD", session.Data.TapLevel == 2, session.Data.TapLevel)
tapper:Tap(nil)
Engine.Step(0.3)
check("tap power x2 applies (33 + 2)", session.Data.Height == 35, session.Data.Height)

---------------------------------------------------------------------------
section("exploits (client sends garbage)")
---------------------------------------------------------------------------
mark = #Engine.Errors
local before = session.Data.Taps
cd:Fire("Tap", 1e9)
cd:Fire("Tap", 0 / 0)
cd:Fire("Tap", -5)
cd:Fire("Tap", "100")
cd:Fire("Tap", { 1 })
Engine.Step(0.1)
check("+1,000,000,000 taps in one remote -> at most MaxBatch", session.Data.Taps - before <= 12, session.Data.Taps - before)
before = session.Data.Taps
for _ = 1, 500 do
	cd:Fire("Tap", 12)
end
Engine.Step(1)
check("500 remotes in a frame are flood-limited", session.Data.Taps - before <= 40, session.Data.Taps - before)
local coinsBefore = session.Data.Coins
cd:Fire("Hatch", "Basic", 0 / 0)
cd:Fire("Hatch", "Galaxy", 1)
cd:Fire("Hatch", { "Basic" }, 1)
Engine.Step(0.5)
check("hatch with NaN / locked egg / junk changes nothing", session.Data.Coins == coinsBefore and session.Data.Coins == session.Data.Coins)
cd:Fire("Rebirth")
Engine.Step(1.2)
check("rebirth without enough height is refused", session.Data.Rebirths == 0)
cd:Fire("TeleportZone", 7)
cd:Fire("ClaimPlaytime", 1)
cd:Fire("ClaimQuest", "Taps")
cd:Fire("ActivateBoost", "SuperGrowth")
cd:Fire("BuyCosmetic", "Aura", "Cosmic")
cd:Fire("EquipCosmetic", "Trail", "VIPGold")
cd:Fire("BuyGemUpgrade", "Luck")
cd:Fire("EquipPet", "999", true)
Engine.Step(1.5)
check("locked teleport / early gifts / unowned items refused", session.ZoneIndex == 1 and next(session.PlaytimeClaimed) == nil and session.Data.Auras.Equipped == "" and session.Data.Trails.Equipped == "")
Engine.Studio = false
cd:Fire("Admin", "coins")
cd:Fire("StudioPurchase", "Pass", "VIP")
Engine.Step(0.5)
Engine.Studio = true
check("admin + fake purchases refused outside Studio", session.Data.Coins < 1e6 and session.Passes.VIP ~= true, session.Data.Coins)
check("server stayed healthy (no errors from junk input)", errorsSince(mark) == 0, errorsSince(mark))

---------------------------------------------------------------------------
section("rebirth through the UI")
---------------------------------------------------------------------------
mark = #Engine.Errors
session.Data.Height = 10000
session.Data.BestHeight = 10000
session.Dirty.Stats = true
session.AttrDirty = true
Engine.Step(1)
check("HUD says rebirth ready", hud.RebirthReady == true)
panels:Open("Rebirth")
Engine.Step(0.2)
local rebirthButton = findButton(panels.Built.Rebirth.Frame, "REBIRTH!")
check("REBIRTH button found", rebirthButton ~= nil)
local bigBefore = body.Shape.Body
Engine.Click(rebirthButton)
Engine.Step(0.2)
check("rebirth done on the server", session.Data.Rebirths == 1, session.Data.Rebirths)
check("height reset to 0.01 m", session.Data.Height == 1)
check("rebirth gems paid", session.Data.Gems >= 4, session.Data.Gems)
check("panel closed to show the animation", panels.Current == nil)
Engine.Step(1.5)
check("body shrank back to a cutlet", body.Shape.Body < bigBefore / 4, body.Shape.Body)
local overlay = localPlayer.PlayerGui:FindFirstChild("ChileFxOverlay")
check("REBIRTH! text shown", overlay ~= nil)
check("no errors during rebirth", errorsSince(mark) == 0)
tapper:Tap(nil)
Engine.Step(0.3)
check("after rebirth taps give x4 (tap power 2 * rebirth 2)", session.Data.Height == 5, session.Data.Height)

---------------------------------------------------------------------------
section("every panel opens and refreshes")
---------------------------------------------------------------------------
mark = #Engine.Errors
for _, name in { "Pets", "Shop", "Rebirth", "Boosts", "Quests", "Daily", "Free", "Leaderboard", "Worlds", "Settings" } do
	panels:Open(name)
	Engine.Step(1.2)
	check("panel " .. name, panels.Current == name and errorsSince(mark) == 0)
	mark = #Engine.Errors
end
panels:Close()

---------------------------------------------------------------------------
section("daily, boosts, cosmetics")
---------------------------------------------------------------------------
mark = #Engine.Errors
panels:Open("Daily")
Engine.Step(0.3)
Engine.Click(findButton(panels.Built.Daily.Frame, "CLAIM DAY 1"))
Engine.Step(0.5)
check("daily reward claimed via UI", session.Data.Daily.Streak == 1)
Engine.Step(0.5)
check("daily button now says come back tomorrow", findButton(panels.Built.Daily.Frame, "COME BACK TOMORROW") ~= nil)
cd:Fire("Admin", "boosts")
Engine.Step(0.5)
panels:Open("Boosts")
Engine.Step(0.5)
Engine.Click(findButton(panels.Built.Boosts.Frame, "USE"))
Engine.Step(0.5)
local activeCount = 0
for _ in session.Data.Boosts.Active do
	activeCount += 1
end
check("boost activated from the panel", activeCount == 1)
check("HUD shows the boost timer", next(hud.BoostPills) ~= nil)
session.Data.Coins = 1e7
session.Dirty.Stats = true
Engine.Step(0.3)
panels:Open("Shop")
Engine.Step(0.3)
local shop = panels.Built.Shop.Frame
Engine.Click(findButton(shop, "🪙 5K"))
Engine.Step(0.5)
check("Cloud trail bought + equipped", session.Data.Trails.Equipped == "Cloud")
check("trail attribute replicated + rendered", localPlayer:GetAttribute("Trail") == "Cloud" and body.Fx and body.Fx.Trail ~= nil)
panels:Close()
check("no errors in daily / boosts / shop", errorsSince(mark) == 0)

---------------------------------------------------------------------------
section("eggs + pets")
---------------------------------------------------------------------------
mark = #Engine.Errors
local eggPos = WorldService:EggPosition("Basic")
Engine.MoveCharacter("Alice", eggPos + require("@lune/roblox").Vector3.new(0, 3, 8))
Engine.Step(0.5)
local prompt
for _, d in rawget(alice.Game:GetService("Workspace"), "__real"):GetDescendants() do
	if d:IsA("ProximityPrompt") and d:GetAttribute("EggId") == "Basic" then
		prompt = Engine.Wrap(d, alice)
	end
end
check("egg prompt replicated to the client", prompt ~= nil)
alice.Stubs.ProximityPromptService.PromptTriggered:Fire(prompt)
Engine.Step(0.3)
check("egg popup opened", hatch.EggPanel ~= nil)
local hatch3 = hatch.EggPanel and findButton(hatch.EggPanel, "HATCH 3")
Engine.Click(hatch3)
Engine.Step(0.5)
local petCount = 0
for _ in session.Data.Pets do
	petCount += 1
end
check("hatched 3 pets on the server", petCount == 3, petCount)
check("hatch animation playing", hatch.Playing == true)
Engine.Step(6)
check("hatch animation finished", hatch.Playing == false)
check("pets auto-equipped + replicated", localPlayer:GetAttribute("Pets") ~= "")
local petController = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.PetController")
check("pets follow the player", petController.Owners[localPlayer] ~= nil and #petController.Owners[localPlayer].Pets == 3)
panels:Open("Pets")
Engine.Step(0.3)
Engine.Click(findButton(panels.Built.Pets.Frame, "EQUIP BEST"))
Engine.Step(0.5)
panels:Close()
check("no errors with eggs / pets", errorsSince(mark) == 0)

---------------------------------------------------------------------------
section("zones, events, chest")
---------------------------------------------------------------------------
mark = #Engine.Errors
session.Data.BestHeight = 2e5 -- unlocks Normal World + Giant City + Cloud World
session.Dirty.Stats = true
Engine.Step(0.5)
cd:Fire("TeleportZone", 3)
Engine.Step(1.5)
check("teleport to an unlocked zone", session.ZoneIndex == 3, session.ZoneIndex)
local zoneController = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ZoneController")
Engine.MoveCharacter("Alice", require("@lune/roblox").Vector3.new(720, 3, 0))
Engine.Step(1.5)
check("client lighting switched to Giant City", zoneController.CurrentZone == 3)
-- sneaking into a locked zone moves you back
Engine.MoveCharacter("Alice", require("@lune/roblox").Vector3.new(2160, 3, 0))
Engine.Step(1.5)
check("locked zone gives no multiplier (server truth)", session.ZoneIndex <= 4, session.ZoneIndex)
local EventService = Engine.Module(server, "ServerScriptService.Server.Services.EventService")
EventService:StartEvent("MegaGrowth")
Engine.Step(1)
check("event replicated to the client", alice.Game:GetService("Workspace"):GetAttribute("EventId") == "MegaGrowth")
check("event banner visible", hud.EventFrame.Visible == true)
local h0 = session.Data.Height
tapper:Tap(nil)
Engine.Step(0.3)
local megaGrowth = Engine.Module(server, "ReplicatedStorage.Shared.EventConfig").Events.MegaGrowth.Height
check("MEGA GROWTH x" .. megaGrowth .. " on taps", session.Data.Height - h0 >= megaGrowth * 2 * 2, session.Data.Height - h0)
Engine.Step(61)
check("event ended + participation gems", alice.Game:GetService("Workspace"):GetAttribute("EventId") == "" and session.Data.Stats.Events == 1)
local RewardService = Engine.Module(server, "ServerScriptService.Server.Services.RewardService")
RewardService:SpawnChest()
Engine.Step(0.2)
check("chest spawned", RewardService.Chest ~= nil)
if RewardService.Chest then
	Engine.MoveCharacter("Alice", RewardService.Chest.Position + require("@lune/roblox").Vector3.new(0, 3, 0))
end
Engine.Step(1)
check("chest grabbed", session.Data.Stats.Chests == 1)
check("no errors in zones / events / chest", errorsSince(mark) == 0)

---------------------------------------------------------------------------
section("quests, gifts, tutorial, achievements")
---------------------------------------------------------------------------
mark = #Engine.Errors
local Roblox = require("@lune/roblox")
check("tutorial advanced by real actions (tap, upgrade, rebirth)", session.Data.Tutorial >= 3, session.Data.Tutorial)
check("achievements unlocked on the way", session.Data.Achievements.T100 == nil and session.Data.Achievements.R1 == true and session.Data.Achievements.P1 == true)
-- 1000 taps for the daily quest (use the server logic directly: 1000 taps at 10/s)
for _ = 1, 100 do
	cd:Fire("Tap", 10)
	Engine.Step(1)
end
check("quest progress tracked", session.Data.Quests.Progress.Taps >= 1000, session.Data.Quests.Progress.Taps)
panels:Open("Quests")
Engine.Step(0.5)
local claimQuest = findButton(panels.Built.Quests.Frame, "CLAIM Coins")
check("quest CLAIM button enabled", claimQuest ~= nil)
local coinsBeforeQuest = session.Data.Coins
Engine.Click(claimQuest)
Engine.Step(0.5)
check("quest reward paid", session.Data.Quests.Claimed.Taps == true and session.Data.Coins > coinsBeforeQuest)
check("taps achievement (100 / 1000) unlocked", session.Data.Achievements.T100 == true and session.Data.Achievements.T1K == true)
panels:Open("Free")
Engine.Step(0.5)
check("5-minute gift is not claimable before 5 minutes", Engine.Now - session.JoinClock >= 300 or findButton(panels.Built.Free.Frame, "CLAIM!") == nil)
Engine.Step(math.max(0, 301 - (Engine.Now - session.JoinClock)))
local gift = findButton(panels.Built.Free.Frame, "CLAIM!")
check("5-minute gift ready after 5+ minutes of play", gift ~= nil)
if gift then
	Engine.Click(gift)
	Engine.Step(0.5)
end
check("playtime gift claimed (and shown as claimed)", session.PlaytimeClaimed[1] == true and findButton(panels.Built.Free.Frame, "CLAIMED") ~= nil)
panels:Close()
check("no errors in quests / gifts", errorsSince(mark) == 0)

---------------------------------------------------------------------------
section("game passes, products, VIP, auto systems")
---------------------------------------------------------------------------
mark = #Engine.Errors
local shopPanel = require("@lune/roblox") and panels
shopPanel:Open("Shop")
Engine.Step(0.3)
Engine.Click(findButton(panels.Built.Shop.Frame, "R$ 199")) -- VIP (Id 0 -> Studio test purchase)
Engine.Step(0.5)
check("VIP granted (Studio test purchase)", session.Passes.VIP == true)
check("VIP gets the Royal aura", session.Data.Auras.Equipped == "Royal" and body.Fx and body.Fx.AuraBox ~= nil)
check("VIP tag replicated", localPlayer:GetAttribute("VIP") == true)
panels:Close()
Engine.MoveCharacter("Alice", Roblox.Vector3.new(-40, 3, 105))
Engine.Step(1.5)
check("VIP lounge bonus active", session.InVIPArea == true)
Engine.MoveCharacter("Alice", Roblox.Vector3.new(-120, 3, 0))
Engine.Step(1.5)
local MonetizationService = Engine.Module(server, "ServerScriptService.Server.Services.MonetizationService")
MonetizationService.ProductById[4242] = "GemsSmall"
local gemsBefore = session.Data.Gems
local receipt = { PlayerId = alicePlayer.UserId, ProductId = 4242, PurchaseId = "receipt-1" }
local decision1 = MonetizationService:ProcessReceipt(receipt)
local decision2 = MonetizationService:ProcessReceipt(receipt)
check("ProcessReceipt grants once (idempotent)", session.Data.Gems == gemsBefore + 100, session.Data.Gems - gemsBefore)
check("ProcessReceipt reports PurchaseGranted", decision1 == Roblox.Enum.ProductPurchaseDecision.PurchaseGranted and decision2 == Roblox.Enum.ProductPurchaseDecision.PurchaseGranted)
-- auto tap pass: taps without touching the screen
cd:Fire("StudioPurchase", "Pass", "AutoTap")
Engine.Step(0.5)
local tapsBeforeAuto = session.Data.Taps
Engine.Step(5)
check("Auto Tap pass taps by itself (~6/s)", session.Data.Taps - tapsBeforeAuto >= 20, session.Data.Taps - tapsBeforeAuto)
check("HUD shows the auto tap switch", hud.AutoTapButton.Visible == true)
Engine.Click(hud.AutoTapButton)
Engine.Step(0.5)
tapsBeforeAuto = session.Data.Taps
Engine.Step(3)
check("auto tap can be switched off", session.Data.Taps == tapsBeforeAuto)
-- auto grow upgrade
session.Data.Coins = 1e9
session.Dirty.Stats = true
Engine.Step(0.3)
Engine.Click(hud.AutoUpgrade)
Engine.Step(0.3)
local h1 = session.Data.Height
Engine.Step(3)
check("AUTO GROW grows passively", session.Data.AutoLevel == 1 and session.Data.Height > h1)
check("no errors with passes / products", errorsSince(mark) == 0)

---------------------------------------------------------------------------
section("viral moments + server events visuals")
---------------------------------------------------------------------------
mark = #Engine.Errors
local notify = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.NotifyController")
local shownBanner = false
local originalShow = notify.ShowBanner
notify.ShowBanner = function(self, item)
	if string.find(item.Text, "SKYSCRAPER", 1, true) then
		shownBanner = true
	end
	return originalShow(self, item)
end
session.Data.Height = 2e7
cd:Fire("Tap", 1)
-- several milestones are crossed at once: their banners play one after another
for _ = 1, 40 do
	Engine.Step(0.5)
	if shownBanner then
		break
	end
end
check("milestone banner: TALLER THAN A SKYSCRAPER", shownBanner)
EventService:StartEvent("GiantMode")
Engine.Step(3)
check("GIANT MODE makes every body huge on the client", bodies.VisualScale > 2.5, bodies.VisualScale)
EventService:StartEvent("TinyMode")
Engine.Step(3)
check("TINY MODE makes every body tiny", bodies.VisualScale < 0.4, bodies.VisualScale)
Engine.Step(25)
check("visual scale returns to normal after the event", math.abs(bodies.VisualScale - 1) < 0.05, bodies.VisualScale)
local LeaderboardService = Engine.Module(server, "ServerScriptService.Server.Services.LeaderboardService")
Engine.Step(80)
local tallest = LeaderboardService.Services.WorldService:GetBoard("Tallest")
check("in-world TALLEST PLAYERS board filled", tallest.Rows[1].Frame.Visible == true and tallest.Rows[1].Name.Text == "Alice", tallest.Rows[1].Name.Text)
local live = LeaderboardService.Services.WorldService:GetBoard("Live")
check("live server board filled", live.Rows[1].Frame.Visible == true)
LeaderboardService.Histogram = { Counts = { ["0"] = 60, ["20"] = 30, ["40"] = 9 }, Total = 100 }
check("percentile math (taller than X% of players)", math.abs((LeaderboardService:Percentile(1e11) or 0) - 0.99) < 1e-9)
check("no errors in viral moments", errorsSince(mark) == 0)

---------------------------------------------------------------------------
section("social: two players")
---------------------------------------------------------------------------
mark = #Engine.Errors
local bob, bobPlayer = Engine.AddPlayer("Bob")
Engine.SpawnCharacter("Bob", require("@lune/roblox").Vector3.new(-110, 3, 0))
Engine.MoveCharacter("Alice", require("@lune/roblox").Vector3.new(-120, 3, 0))
session.Data.Height = 1e5
session.AttrDirty = true
Engine.Step(1.5)
local aliceBodies = bodies
check("Alice sees Bob's stretched body", aliceBodies:GetBody(alice.PlayersByName.Bob) ~= nil)
local social = Engine.Module(alice, "StarterPlayer.StarterPlayerScripts.Client.Controllers.SocialController")
local bobTag = social.Tags[alice.PlayersByName.Bob]
check("Bob has a height tag", bobTag ~= nil)
check("comparison shown: YOU ARE ...x TALLER", bobTag and bobTag.Compare.Visible and string.find(bobTag.Compare.Text, "YOU ARE", 1, true) ~= nil, bobTag and bobTag.Compare.Text)
local bobSocial = Engine.Module(bob, "StarterPlayer.StarterPlayerScripts.Client.Controllers.SocialController")
local aliceTagForBob = bobSocial.Tags[bob.PlayersByName.Alice]
check("Bob sees: ...x TALLER THAN YOU", aliceTagForBob and string.find(aliceTagForBob.Compare.Text, "TALLER THAN YOU", 1, true) ~= nil, aliceTagForBob and aliceTagForBob.Compare.Text)
local bobNotify = Engine.Module(bob, "StarterPlayer.StarterPlayerScripts.Client.Controllers.NotifyController")
local passedShown = false
local bobShow = bobNotify.ShowBanner
bobNotify.ShowBanner = function(self, item)
	if string.find(item.Text, "YOU PASSED ALICE", 1, true) then
		passedShown = true
	end
	return bobShow(self, item)
end
local bobSession = PlayerService:Get(bobPlayer)
Engine.Step(5) -- Bob's client has seen that Alice is taller
bobSession.Data.Height = 1e9
bobSession.AttrDirty = true
Engine.Step(3)
check("🚨 YOU PASSED ALICE! shown to Bob", passedShown)
check("no errors with two players", errorsSince(mark) == 0)

---------------------------------------------------------------------------
section("saving")
---------------------------------------------------------------------------
mark = #Engine.Errors
local aliceId = alicePlayer.UserId
local savedRebirths = session.Data.Rebirths
local savedPets = petCount
Engine.RemovePlayer("Alice")
Engine.Step(1)
local stored = Engine.DataStores["ChileSimulator_Players_v1"]["u_" .. aliceId]
check("saved on leave", stored ~= nil)
local decoded = require("@lune/serde").decode("json", stored)
check("save contains progress", decoded.Data.Rebirths == savedRebirths and decoded.Data.Trails.Equipped == "Cloud")
check("session lock released on leave", decoded.Lock == nil)
local alice2, alicePlayer2 = Engine.AddPlayer("Alice", { UserId = aliceId })
Engine.SpawnCharacter("Alice")
Engine.Step(1)
local session2 = PlayerService:Get(alicePlayer2)
local pets2 = 0
for _ in session2.Data.Pets do
	pets2 += 1
end
check("rejoin loads rebirths, pets, trail", session2.Data.Rebirths == savedRebirths and pets2 == savedPets and session2.Data.Trails.Equipped == "Cloud")

-- session lock: another (dead) server still holds Carol's profile
Engine.DataStores["ChileSimulator_Players_v1"]["u_777"] = require("@lune/serde").encode("json", {
	Data = { Rebirths = 5 },
	Lock = { Server = "other-server", Time = Engine.BaseTime + math.floor(Engine.Now) },
})
local carol, carolPlayer = Engine.AddPlayer("Carol", { UserId = 777 })
Engine.Step(2)
check("locked profile is NOT loaded immediately", PlayerService:Get(carolPlayer) == nil)
Engine.Step(30)
local carolSession = PlayerService:Get(carolPlayer)
check("lock taken over after retries, data intact", carolSession ~= nil and carolSession.Data.Rebirths == 5)

-- DataStore outage on join: kicked instead of getting empty data
Engine.DataStoreDown = true
local kicksBefore = #Engine.Kicks
local dave = Engine.AddPlayer("Dave", { UserId = 888 })
Engine.Step(90)
Engine.DataStoreDown = false
check("outage on join -> kicked, never overwritten", #Engine.Kicks > kicksBefore and Engine.DataStores["ChileSimulator_Players_v1"]["u_888"] == nil)
local _ = dave
check("no script errors in the saving tests", errorsSince(mark) == 0)

---------------------------------------------------------------------------
section("mobile")
---------------------------------------------------------------------------
mark = #Engine.Errors
local phone = Engine.AddPlayer("Phone", { Touch = true })
Engine.SpawnCharacter("Phone")
Engine.Step(2)
local phoneHud = Engine.Module(phone, "StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController")
check("touch layout built", phoneHud.Touch == true and phoneHud.TapButton ~= nil)
check("big TAP button on the right (away from the thumbstick)", phoneHud.TapButton.AnchorPoint.X == 1 and phoneHud.TapButton.Size.Y.Offset >= 140)
local phoneSession = PlayerService:Get(phone.ServerPlayer)
Engine.Click(phoneHud.TapButton)
Engine.Step(0.5)
check("touch tap on the button grows you", phoneSession.Data.Taps == 1, phoneSession.Data.Taps)
check("no errors on mobile", errorsSince(mark) == 0)

---------------------------------------------------------------------------
section("performance")
---------------------------------------------------------------------------
local syncBefore = alice2.NetLog.Sync or 0
local cd2 = Engine.Module(alice2, "StarterPlayer.StarterPlayerScripts.Client.Controllers.ClientData")
local tapper2 = Engine.Module(alice2, "StarterPlayer.StarterPlayerScripts.Client.Controllers.TapController")
for _ = 1, 100 do -- 10 s of 10 taps/s
	tapper2:Tap(nil)
	Engine.Step(0.1)
end
local syncs = (alice2.NetLog.Sync or 0) - syncBefore
check("Sync messages <= 8 per second while tapping 10/s", syncs <= 85, syncs)
local _ = cd2
local clientBodies = Engine.Count(alice2.Game:GetService("Workspace"):FindFirstChild("ChileBodies"), "BasePart")
check("client body parts for 4 players < 120", clientBodies < 120, clientBodies)
print(string.format("       %d Sync msgs / 10 s, %d body parts for %d players", syncs, clientBodies, 4))

---------------------------------------------------------------------------
section("shutdown")
---------------------------------------------------------------------------
local ok = Engine.Shutdown()
check("BindToClose finishes", ok)
local final = require("@lune/serde").decode("json", Engine.DataStores["ChileSimulator_Players_v1"]["u_" .. aliceId])
check("BindToClose saved + released everyone", final.Lock == nil and final.Data.Taps >= 100)

---------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed, %d script errors, %d warnings", passed, failed, #Engine.Errors, #Engine.Warnings))
for _, f in failures do
	print("  - " .. f)
end
for _, w in Engine.Warnings do
	print("  warn: " .. w)
end
if failed > 0 or #Engine.Errors > 0 then
	process.exit(1)
end
