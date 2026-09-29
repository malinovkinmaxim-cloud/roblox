--[[
	Net - the single list of RemoteEvents (created by the server in ReplicatedStorage.Remotes).

	Client -> server events only carry INTENT ("start a run as THE TANK", "I pick card 2"),
	never amounts of XP / coins / damage. Every handler on the server validates types,
	rate and state (server/Util/Guard.lua).

	Server -> client:
	  Frame        (owner)  binary run frame, 10 Hz (shared/Protocol.lua)
	  RunEvent     (owner)  rare run moments: start, level up offer, banners, boss, death, results
	  Sync         (owner)  profile snapshot for the lobby UI
	  Notify       (owner)  toasts
	  Leaderboard  (owner)  top lists
	  Party        (owner)  a party invite arrived
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.ClientToServer = {
	"Ready", -- ()
	"StartRun", -- (heroKey: string?, startWeapon: string?) nil = the active loadout
	"Choose", -- (index: number)
	"Reroll", -- ()
	"Skip", -- ()
	"Revive", -- () ask for a Robux revive while dead
	"GiveUp", -- () end the run now (decline revive / quit)
	"Pause", -- (paused: boolean) settings menu open during a run
	"Dash", -- (dirX: number, dirZ: number) DASH with the Rocket Skates relic (the run decides)
	"ReturnToLobby", -- ()
	"BuyMeta", -- (key)
	"UnlockHero", -- (key) fragments
	"SelectHero", -- (key)
	"UnlockWeapon", -- (key) fragments
	"SetStartWeapon", -- (key | "")
	"SelectLoadout", -- (index)
	"BuyCosmetic", -- (id)
	"EquipCosmetic", -- (id)
	"SeenCosmetics", -- ()
	"Emote", -- (style)
	"RedeemCode", -- (code: string)
	"ClaimDaily", -- ()
	"ClaimQuest", -- (index)
	"ClaimWeekly", -- (index)
	"AfkClaim", -- ()
	"AfkSetSlot", -- (index, heroKey | "")
	"AfkBuySlot", -- ()
	"PartyInvite", -- (userId)
	"PartyAccept", -- (userId)
	"PartyDecline", -- (userId)
	"PartyLeave", -- ()
	"PartyKick", -- (userId)
	"SetSetting", -- (key, value)
	"SelectDifficulty", -- (tier index)
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
	"Party", -- party invites
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
