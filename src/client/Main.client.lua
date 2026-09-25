--[[
	THE DOPPELGÄNGER OBBY - client entry point.
	Loads controllers, calls Init() on all of them, then Start().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- make sure remotes exist before anything connects to them
require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")).Setup()

local ORDER = {
	"ClientState",
	"SoundController",
	"InputController",
	"HudController",
	"OverlayController",
	"MenuController",
	"EffectsController",
	"SpectateController",
	"DebugController",
}

local folder = script.Parent:WaitForChild("Controllers")
local controllers = {}

for _, name in ORDER do
	controllers[name] = require(folder:WaitForChild(name))
end

local Kit = require(script.Parent:WaitForChild("UI"):WaitForChild("Kit"))

for _, name in ORDER do
	local controller = controllers[name]
	if controller.Init then
		local ok, err = pcall(controller.Init, controller, controllers)
		if not ok then
			warn("[Client] " .. name .. ":Init failed: " .. tostring(err))
		end
	end
end

local click = controllers.SoundController:Get("Click")
if click then
	Kit.SetClickSound(click)
end

for _, name in ORDER do
	local controller = controllers[name]
	if controller.Start then
		task.spawn(function()
			local ok, err = pcall(controller.Start, controller)
			if not ok then
				warn("[Client] " .. name .. ":Start failed: " .. tostring(err))
			end
		end)
	end
end
