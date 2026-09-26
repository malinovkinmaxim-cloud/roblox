--!nocheck
--[[
	Studio without "Enable Studio Access to API Services": DataStores throw.
	The game must still be fully playable (memory mode) and say that saving is off.
	Run from ChileSimulator/:   lune run tests/e2e_offline.luau
]]

local process = require("@lune/process")
local Engine = require("./engine")

Engine.StudioNoApi = true
local server = Engine.StartServer()
local DataService = Engine.Module(server, "ServerScriptService.Server.Services.DataService")
local PlayerService = Engine.Module(server, "ServerScriptService.Server.Services.PlayerService")
local client, player = Engine.AddPlayer("Offline")
Engine.SpawnCharacter("Offline")
Engine.Step(1)
local tapper = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.TapController")
for _ = 1, 20 do
	tapper:Tap(nil)
	Engine.Step(0.1)
end
Engine.Step(1)
local panels = Engine.Module(client, "StarterPlayer.StarterPlayerScripts.Client.Controllers.PanelController")
panels:Open("Settings")
Engine.Step(0.5)
local statusText = ""
for _, d in rawget(panels.Built.Settings.Frame, "__real"):GetDescendants() do
	if d:IsA("TextLabel") and string.find(d.Text, "Saving is OFF", 1, true) then
		statusText = d.Text
	end
end
Engine.RemovePlayer("Offline")
Engine.Step(1)
local ok = DataService.Persistent == false
	and PlayerService:Get(player) == nil
	and statusText ~= ""
	and #Engine.Errors == 0
	and #Engine.Kicks == 0
print("memory mode: persistent =", DataService.Persistent, "| settings says:", statusText, "| errors:", #Engine.Errors, "| kicks:", #Engine.Kicks)
if not ok then
	process.exit(1)
end
print("OK")
