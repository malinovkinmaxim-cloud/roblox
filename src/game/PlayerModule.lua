-- Replaces Roblox's default PlayerModule in the game place. Movement and camera are fully custom
-- (see Client), and the default ControlModule kept calling Player:Move while no character existed
-- (between levels), spamming "Player:Move called, but player currently has no character".
-- PlayerScriptsLoader still requires this module, so it returns a harmless stub.
local PlayerModule = {}

local noControls = {
	Enable = function() end,
	Disable = function() end,
}

function PlayerModule:GetControls()
	return noControls
end

function PlayerModule:GetCameras()
	return nil
end

return PlayerModule
