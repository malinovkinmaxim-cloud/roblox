--[[
	Net - the single list of RemoteEvents.

	Client -> server events only carry INTENT ("I tapped 3 times", "hatch Basic egg"), never
	amounts of Height / Coins / Gems. Every handler on the server validates types, rate and
	state (see server/Util/Guard.lua).

	Server -> client:
	  Sync     (owner only)  full or partial data snapshot for the UI
	  Notify   (owner/all)   toasts and big banners
	  Effect   (owner/all)   one-shot visual events: rebirth boom, hatch result, milestone...
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.ClientToServer = {
	"Tap", -- (count: integer 1..MaxBatch)
	"BuyUpgrade", -- ("TapPower" | "AutoGrow")
	"BuyGemUpgrade", -- (id)
	"Rebirth", -- ()
	"Hatch", -- (eggId, count)
	"EquipPet", -- (uid, equip: boolean)
	"EquipBest", -- ()
	"DeletePet", -- (uid)
	"ActivateBoost", -- (boostId)
	"ClaimDaily", -- ()
	"ClaimPlaytime", -- (index)
	"ClaimQuest", -- (questId)
	"BuyCosmetic", -- (kind, id)
	"EquipCosmetic", -- (kind, id | "")
	"TeleportZone", -- (zoneIndex)
	"SetSetting", -- (key, value)
	"SetAutoTap", -- (enabled)
	"Tutorial", -- (step)
	"StudioPurchase", -- (kind, id) Studio-only fake purchases for testing unconfigured Robux items
	"Admin", -- (command, arg) Studio / admin only
}

Net.ServerToClient = {
	"Sync",
	"Notify",
	"Effect",
}

local FOLDER_NAME = "ChileRemotes"

-- Server: create all remotes (idempotent)
function Net.Setup()
	assert(RunService:IsServer(), "Net.Setup is server only")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, list in { Net.ClientToServer, Net.ServerToClient } do
		for _, name in list do
			if not folder:FindFirstChild(name) then
				local remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = folder
			end
		end
	end
	return folder
end

function Net.Event(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	local remote = folder:WaitForChild(name, 30)
	assert(remote and remote:IsA("RemoteEvent"), "missing remote " .. name)
	return remote
end

return Net
