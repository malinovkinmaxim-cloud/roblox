--[[
	CHILE SIMULATOR - client entry point.
	Init() every controller in order, then Start() every controller.
]]

local Controllers = script.Parent:WaitForChild("Controllers")
local Kit = require(script.Parent:WaitForChild("UI"):WaitForChild("Kit"))

local ORDER = {
	"ClientData",
	"SoundController",
	"BodyController",
	"CameraController",
	"EffectsController",
	"NotifyController",
	"TapController",
	"PanelController",
	"HudController",
	"SocialController",
	"ZoneController",
	"PetController",
	"HatchController",
	"TutorialController",
}

local controllers = {}
for _, name in ORDER do
	controllers[name] = require(Controllers:WaitForChild(name))
end

for _, name in ORDER do
	controllers[name]:Init(controllers)
end

Kit.ClickSound = function()
	controllers.SoundController:Play("Click")
end

for _, name in ORDER do
	local ok, err = pcall(function()
		controllers[name]:Start()
	end)
	if not ok then
		warn(string.format("[Main] %s:Start failed: %s", name, tostring(err)))
	end
end
