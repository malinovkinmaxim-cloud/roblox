--!nocheck
--[[
	Soak test: several players play for 20 simulated minutes with random actions
	(tapping, buying, hatching, panels, junk remotes, events, chests, leaving / rejoining).
	Fails on any script error or if client instance counts keep growing (leaks).
	Run from ChileSimulator/:   lune run tests/soak.luau [minutes]
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Engine = require("./engine")

local MINUTES = tonumber(process.args[1]) or 20
local rng = Random and Random.new and nil
math.randomseed(12345)

local server = Engine.StartServer()
local PlayerService = Engine.Module(server, "ServerScriptService.Server.Services.PlayerService")
local WorldService = Engine.Module(server, "ServerScriptService.Server.Services.WorldService")

local names = { "Ana", "Ben", "Cat" }
local clients = {}
for i, name in names do
	clients[name] = Engine.AddPlayer(name, { Touch = i == 3 })
	Engine.SpawnCharacter(name, roblox.Vector3.new(-120 + i * 6, 3, 0))
end
Engine.Step(2)

local PANELS = { "Pets", "Shop", "Rebirth", "Boosts", "Quests", "Daily", "Free", "Leaderboard", "Worlds", "Settings" }

-- panels are built lazily on first open: build them all before the leak baseline
local function buildAllPanels(name)
	local panels = Engine.Module(clients[name], "StarterPlayer.StarterPlayerScripts.Client.Controllers.PanelController")
	for _, panel in PANELS do
		panels:Open(panel)
		Engine.Step(0.1)
	end
	panels:Close()
end
for _, name in names do
	buildAllPanels(name)
end
local JUNK = {
	{ "Tap", 1e9 }, { "Tap", 0 / 0 }, { "Hatch", "Galaxy", 3 }, { "Hatch", "Basic", -1 }, { "Rebirth" },
	{ "TeleportZone", 99 }, { "BuyCosmetic", "Trail", "Glitch" }, { "EquipPet", "nope", true }, { "SetSetting", "Sfx", "yes" },
	{ "ClaimQuest", 5 }, { "ActivateBoost", {} }, { "BuyGemUpgrade", "Luck" }, { "DeletePet", "1" },
}

local function controller(name, module)
	return Engine.Module(clients[name], "StarterPlayer.StarterPlayerScripts.Client.Controllers." .. module)
end

local function instanceCount(world)
	local ws = rawget(world.Game:GetService("Workspace"), "__real")
	local gui = rawget(world.LocalPlayer.PlayerGui, "__real")
	return #ws:GetDescendants() + #gui:GetDescendants()
end

local baseline = {}
local baselineClasses = {}
local baselinePets = {}
local function petCount(name)
	local count = 0
	for _ in PlayerService:Get(server.PlayersByName[name]).Data.Pets do
		count += 1
	end
	return count
end
local function classCounts(world)
	local counts = {}
	local ws = rawget(world.Game:GetService("Workspace"), "__real")
	local gui = rawget(world.LocalPlayer.PlayerGui, "__real")
	for _, root in { ws, gui } do
		for _, d in root:GetDescendants() do
			local key = d.ClassName .. " @ " .. (if d.Parent then d.Parent.Name else "?")
			counts[key] = (counts[key] or 0) + 1
		end
	end
	return counts
end
local totalTicks = MINUTES * 60 * 10
local EggPos = WorldService:EggPosition("Basic")
for tick = 1, totalTicks do
	local t = tick / 10
	for _, name in names do
		local client = clients[name]
		if client then
			local tapper = controller(name, "TapController")
			if math.random() < 0.75 then
				tapper:Tap(nil)
			end
			local roll = math.random()
			local cd = controller(name, "ClientData")
			if roll < 0.004 then
				cd:Fire("BuyUpgrade", if math.random() < 0.6 then "TapPower" else "AutoGrow")
			elseif roll < 0.006 then
				controller(name, "PanelController"):Open(PANELS[math.random(1, #PANELS)])
			elseif roll < 0.008 then
				controller(name, "PanelController"):Close()
			elseif roll < 0.009 then
				local junk = JUNK[math.random(1, #JUNK)]
				cd:Fire(table.unpack(junk))
			elseif roll < 0.0095 then
				Engine.MoveCharacter(name, EggPos + roblox.Vector3.new(0, 3, 6))
				cd:Fire("Hatch", "Basic", math.random(1, 3))
			elseif roll < 0.0097 then
				cd:Fire("Rebirth")
			elseif roll < 0.0099 then
				cd:Fire("ClaimDaily")
				cd:Fire("ClaimPlaytime", math.random(1, 5))
				cd:Fire("ClaimQuest", "Taps")
			elseif roll < 0.01 then
				local x = math.random(-150, 1500)
				Engine.MoveCharacter(name, roblox.Vector3.new(x, 3, math.random(-100, 100)), roblox.Vector3.new(12, 0, 0))
			end
		end
	end
	-- one player leaves and comes back every ~7 minutes
	if tick % 4200 == 0 then
		Engine.RemovePlayer("Ben")
		clients.Ben = nil
		Engine.Step(2)
		clients.Ben = Engine.AddPlayer("Ben", { UserId = 1002 })
		Engine.SpawnCharacter("Ben")
	end
	Engine.Step(0.1, 0.05)
	if tick == 1200 then -- after 2 minutes: remember instance counts
		for name, client in clients do
			baseline[name] = instanceCount(client)
			baselineClasses[name] = classCounts(client)
			baselinePets[name] = petCount(name)
		end
	end
	if tick % 3000 == 0 then
		print(string.format("  %d min: errors %d, Ana height %s, rebirths %d", t // 60, #Engine.Errors, tostring(PlayerService:Get(server.PlayersByName.Ana).Data.Height), PlayerService:Get(server.PlayersByName.Ana).Data.Rebirths))
	end
end

local ok = true
print("\nsoak results after " .. MINUTES .. " simulated minutes:")
print("  script errors: " .. #Engine.Errors)
ok = ok and #Engine.Errors == 0
for _, name in { "Ana", "Cat" } do
	local now = instanceCount(clients[name])
	local growth = now - baseline[name]
	-- every pet in storage can have a card (~20 instances) in the Pets panel (rebuilt when it is
	-- opened); one-button mode hatches a lot, so allow for that. Cosmetics / effects add a
	-- little; a leak would add thousands.
	local pets = petCount(name)
	local allowed = 400 + 25 * pets
	print(string.format("  %s client instances: %d -> %d (allowed +%d, %d pets, %d at baseline)", name, baseline[name], now, allowed, pets, baselinePets[name]))
	if growth > allowed then
		print("  LEAK suspected for " .. name)
		ok = false
	end
	local nowClasses = classCounts(clients[name])
	local diffs = {}
	for key, n in nowClasses do
		local d = n - (baselineClasses[name][key] or 0)
		if d > 15 then
			table.insert(diffs, { key, d })
		end
	end
	table.sort(diffs, function(a, b)
		return a[2] > b[2]
	end)
	for i = 1, math.min(8, #diffs) do
		print(string.format("     +%d  %s", diffs[i][2], diffs[i][1]))
	end
end
local sessions = 0
for _ in PlayerService:GetSessions() do
	sessions += 1
end
print("  sessions on server: " .. sessions)
ok = ok and sessions == 3
if not ok then
	process.exit(1)
end
print("  OK")
