--[[
	Net
	Single place that declares every RemoteEvent / RemoteFunction.
	The server creates ReplicatedStorage.Remotes on startup, the client waits for it.

	Client -> Server events are ALWAYS validated on the server (types, rate limit, state).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	-- client -> server
	"RequestPlay", -- (levelId: number)
	"RequestLeave", -- ()
	"RequestRestart", -- (kind: "Checkpoint" | "Level")
	"UseAbility", -- ()
	"UseInteract", -- ()
	"ShopAction", -- (action: "Buy" | "Equip", itemId: string)
	"ClaimQuest", -- (questId: string)
	"UpdateSettings", -- (key: string, value: boolean)
	"DebugCommand", -- (command: string, arg: string?)
	"DuoAction", -- (action: string, payload: any)

	-- server -> client
	"ProfileUpdated", -- (profileSnapshot)
	"RunStarted", -- (runInfo)
	"RunEnded", -- (results)
	"CheckpointReached", -- (index, total)
	"PlayerDied", -- (info)
	"PlayerRespawned", -- ()
	"RoleState", -- (roleInfo)
	"RoleRevealed", -- (roleName)
	"DoppelStatus", -- (statusKey, text)
	"AbilityState", -- (state)
	"Toast", -- (text, kind)
	"Launch", -- (velocity: Vector3)
	"DuoState", -- (state)
	"CatalogUpdated", -- (catalog)
}

Net.Functions = {
	"GetBootstrap", -- () -> { Profile, Catalog, IsDebug, ... }
}

local remotesFolder: Folder? = nil

local function getFolder(): Folder
	local cached = remotesFolder
	if cached then
		return cached
	end
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
		end
		for _, name in Net.Events do
			if not folder:FindFirstChild(name) then
				local remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = folder
			end
		end
		for _, name in Net.Functions do
			if not folder:FindFirstChild(name) then
				local remote = Instance.new("RemoteFunction")
				remote.Name = name
				remote.Parent = folder
			end
		end
		folder.Parent = ReplicatedStorage
		remotesFolder = folder
	else
		remotesFolder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return (remotesFolder :: any) :: Folder
end

function Net.Setup()
	getFolder()
end

function Net.Event(name: string): RemoteEvent
	assert(table.find(Net.Events, name), "Unknown remote event: " .. name)
	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if not remote and RunService:IsClient() then
		remote = folder:WaitForChild(name, 15)
	end
	assert(remote and remote:IsA("RemoteEvent"), "Remote event missing: " .. name)
	return remote
end

function Net.Function(name: string): RemoteFunction
	assert(table.find(Net.Functions, name), "Unknown remote function: " .. name)
	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if not remote and RunService:IsClient() then
		remote = folder:WaitForChild(name, 15)
	end
	assert(remote and remote:IsA("RemoteFunction"), "Remote function missing: " .. name)
	return remote
end

return Net
