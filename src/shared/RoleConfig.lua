--[[
	RoleConfig
	Display data for every doppelgänger role (shared by server + client).
	Behaviour lives in ServerScriptService.Server.Roles.<RoleName>.
]]

local RoleConfig = {}

RoleConfig.HiddenName = "???"
RoleConfig.HiddenColor = Color3.fromRGB(110, 205, 255)

RoleConfig.Roles = {
	Follower = {
		DisplayName = "ECHO",
		RevealText = "YOUR ECHO.",
		Description = "Walks in your exact footsteps. Presses what you walk past.",
		Difficulty = 0,
		Color = Color3.fromRGB(120, 215, 255),
		Ability = nil,
		Interact = nil,
	},
	Rival = {
		DisplayName = "RIVAL",
		RevealText = "THE RIVAL.",
		Description = "Races you to the finish. A little faster than you... but not perfect.",
		Difficulty = 2,
		Color = Color3.fromRGB(255, 120, 70),
		Ability = nil,
		Interact = nil,
	},
	Shadow = {
		DisplayName = "SHADOW",
		RevealText = "YOUR SHADOW.",
		Description = "Repeats everything you do - a moment later.",
		Difficulty = 2,
		Color = Color3.fromRGB(170, 120, 255),
		Ability = "FREEZE", -- only on levels with AllowFreeze = true
		Interact = "RELEASE",
	},
	Ally = {
		DisplayName = "ALLY",
		RevealText = "YOUR ALLY.",
		Description = "Helps you - if you tell it what to do.",
		Difficulty = 1,
		Color = Color3.fromRGB(90, 230, 150),
		Ability = "SEND",
		Interact = "RECALL",
	},
	Troll = {
		DisplayName = "TROLL",
		RevealText = "THE TROLL.",
		Description = "Pretends to help. Watch it closely.",
		Difficulty = 3,
		Color = Color3.fromRGB(255, 80, 200),
		Ability = "SEND",
		Interact = "RECALL",
	},
	Partner = {
		DisplayName = "PARTNER",
		RevealText = "YOUR PARTNER.",
		Description = "A real player controls your doppelgänger.",
		Difficulty = 1,
		Color = Color3.fromRGB(255, 210, 90),
		Ability = nil,
		Interact = nil,
	},
}

function RoleConfig.Get(roleName: string?)
	if roleName == nil then
		return nil
	end
	return RoleConfig.Roles[roleName]
end

return RoleConfig
