--[[
	Net - the single list of RemoteEvents (created by the server in ReplicatedStorage.Remotes).

	Client -> server events only carry INTENT ("start a run as Sigma", "I pick card 2"),
	never amounts of XP / coins / damage. Every handler on the server validates types,
	rate and state (server/Util/Guard.lua).

	Server -> client:
	  Frame        (owner)  binary run frame, 10 Hz (shared/Protocol.lua)
	  RunEvent     (owner)  rare run moments: start, level up offer, banners, boss, death, results
	  Sync         (owner)  profile snapshot for the lobby UI
	  Notify       (owner)  toasts
	  Leaderboard  (owner)  top lists
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.ClientToServer = {
	"Ready", -- ()
	"StartRun", -- (characterKey: string, startWeapon: string)
	"Choose", -- (index: number)
	"Reroll", -- ()
	"Skip", -- ()
	"Revive", -- () ask for a Robux revive while dead
	"GiveUp", -- () end the run now (decline revive / quit)
	"Pause", -- (paused: boolean) settings menu open during a run (solo runs only)
	"ReturnToLobby", -- ()
	"BuyMeta", -- (key)
	"UnlockCharacter", -- (key)
	"SelectCharacter", -- (key)
	"UnlockWeapon", -- (key)
	"SetStartWeapon", -- (key | "")
	"BuySkin", -- (key)
	"EquipSkin", -- (key)
	"ClaimDaily", -- ()
	"ClaimQuest", -- (index)
	"SetSetting", -- (key, value)
	"RequestLeaderboard", -- ()
	"Buy", -- (kind: "Pass" | "Product", key) opens the Roblox purchase prompt
	"StudioPurchase", -- (kind, key) Studio-only fake purchase for testing unconfigured ids
	"Admin", -- (command, arg) Studio / admins only
}

Net.ServerToClient = {
	"Frame",
	"RunEvent",
	"Sync",
	"Notify",
	"Leaderboard",
}

Net.FolderName = "Remotes"

-- Server: create all remotes (idempotent)
function Net.Setup(): Folder
	assert(RunService:IsServer(), "Net.Setup is server only")
	local folder = ReplicatedStorage:FindFirstChild(Net.FolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Net.FolderName
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
	return folder :: Folder
end

function Net.Event(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild(Net.FolderName)
	local remote = folder:WaitForChild(name, 30)
	assert(remote and remote:IsA("RemoteEvent"), "missing remote " .. name)
	return remote
end

return Net
