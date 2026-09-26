--!nocheck
--[[
	ONE-BUTTON test: a player who NEVER touches anything except the big TAP button.
	No menus, no walking, no shop. Runs the real server + client code (tests/engine.luau).
	Run from ChileSimulator/:   lune run tests/e2e_onebutton.luau [minutes]
]]

local process = require("@lune/process")
local Engine = require("./engine")

local MINUTES = tonumber(process.args[1]) or 15
local PRESSES_PER_SECOND = 6

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
local PlayerService = Engine.Module(server, "ServerScriptService.Server.Services.PlayerService")
local client, serverPlayer = Engine.AddPlayer("OneButton")
Engine.SpawnCharacter("OneButton")
Engine.Step(1)
local session = PlayerService:Get(serverPlayer)
local hud = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController")
local hatch = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.HatchController")
local panels = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.PanelController")

print("\n[layout]")
check("one-button mode is on by default", session.Data.Settings.OneButton == true)
check("upgrade buttons folded away", hud.TapUpgrade.Visible == false and hud.AutoUpgrade.Visible == false)
check("menus folded into one MENU button", hud.LeftColumn.Visible == false and hud.RightColumn.Visible == false and hud.MenuButton.Visible == true)
check("the TAP button is big", hud.TapButton.Size.X.Offset >= 380)

print("\n[" .. MINUTES .. " minutes of pressing ONE button]")
local timeline = {}
local function note(text)
	table.insert(timeline, string.format("%6s  %s", string.format("%d:%02d", Engine.Now // 60, Engine.Now % 60), text))
end
local lastTap, lastAuto, lastRebirths, lastZone, lastPets = 1, 0, 0, 1, 0
local rebirthPresses = 0
local blocked = false
local presses = MINUTES * 60 * PRESSES_PER_SECOND
for i = 1, presses do
	if hud:IsRebirthArmed() then
		rebirthPresses += 1
	end
	Engine.Click(hud.TapButton) -- the only input, ever
	Engine.Step(1 / PRESSES_PER_SECOND, 1 / 30)
	if hatch.Playing or panels.Current then
		blocked = true
	end
	local d = session.Data
	if d.TapLevel ~= lastTap then
		lastTap = d.TapLevel
		if lastTap <= 4 or lastTap % 3 == 0 then
			note("auto upgrade: TAP POWER level " .. lastTap)
		end
	end
	if d.AutoLevel ~= lastAuto then
		lastAuto = d.AutoLevel
		if lastAuto == 1 then
			note("auto upgrade: AUTO GROW")
		end
	end
	if d.Rebirths ~= lastRebirths then
		lastRebirths = d.Rebirths
		note("REBIRTH " .. lastRebirths .. " (pressed the purple button)")
	end
	if session.ZoneIndex ~= lastZone then
		lastZone = session.ZoneIndex
		note("moved to world " .. lastZone)
	end
	local pets = 0
	for _ in d.Pets do
		pets += 1
	end
	if pets > lastPets then
		lastPets = pets
		if pets <= 3 or pets % 10 == 0 then
			note("auto hatched pet #" .. pets)
		end
	end
	if i % (60 * PRESSES_PER_SECOND * 5) == 0 then
		note(string.format("height %s, best %s", tostring(math.floor(d.Height / 100)) .. " m", tostring(math.floor(d.BestHeight / 100)) .. " m"))
	end
end
for _, line in timeline do
	print("   " .. line)
end

local d = session.Data
local pets = 0
for _ in d.Pets do
	pets += 1
end
local equipped = 0
for _, pet in d.Pets do
	if pet.E then
		equipped += 1
	end
end

print("\n[results]")
check("upgrades bought automatically", d.TapLevel >= 6 and d.AutoLevel >= 2, d.TapLevel .. "/" .. d.AutoLevel)
check("rebirths done with the same button", d.Rebirths >= 2 and rebirthPresses >= d.Rebirths, d.Rebirths)
check("gems spent on permanent upgrades", d.Gem.TapBonus + d.Gem.CoinBonus + d.Gem.AutoBonus >= 1)
check("daily reward claimed automatically", d.Daily.Streak == 1)
check("playtime gifts claimed automatically", session.PlaytimeClaimed[1] == true and session.PlaytimeClaimed[2] == true)
check("taps quest claimed automatically", d.Quests.Claimed.Taps == true)
check("pets hatched and equipped automatically", pets >= 1 and equipped >= 1, pets)
local ZoneConfig = Engine.Module(server, "ReplicatedStorage.Shared.ZoneConfig")
check("moved to the best unlocked world", session.ZoneIndex == ZoneConfig.HighestUnlocked(d.BestHeight) and session.ZoneIndex >= 4, session.ZoneIndex)
check("never blocked by a full-screen popup", not blocked)
check("tutorial finished", d.Tutorial >= 4, d.Tutorial)
check("reached 10K m with one button", d.BestHeight >= 1e6, d.BestHeight / 100)
check("no script errors", #Engine.Errors == 0, #Engine.Errors)

print(string.format("\n%d passed, %d failed  |  best height %s m, %d rebirths, %d pets, world %d", passed, failed, tostring(math.floor(d.BestHeight / 100)), d.Rebirths, pets, session.ZoneIndex))
if failed > 0 or #Engine.Errors > 0 then
	process.exit(1)
end
