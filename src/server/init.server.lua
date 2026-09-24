local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage.Shared.Config)
local Levels = require(ReplicatedStorage.Shared.Levels)
local CharacterFactory = require(script.CharacterFactory)
local LevelBuilder = require(script.LevelBuilder)
local Mechanics = require(script.Mechanics)

Players.CharacterAutoLoads = false
workspace.Gravity = Config.GRAVITY
StarterPlayer.LoadCharacterAppearance = false
StarterPlayer.CharacterUseJumpPower = false
StarterPlayer.CharacterJumpHeight = Config.JUMP_HEIGHT
StarterPlayer.CharacterWalkSpeed = Config.WALK_SPEED
StarterPlayer.EnableMouseLockOption = false

Lighting.GlobalShadows = false
Lighting.Brightness = 2
Lighting.ClockTime = 13
Lighting.Ambient = Color3.fromRGB(170, 170, 170)
Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
Lighting.EnvironmentDiffuseScale = 0
Lighting.EnvironmentSpecularScale = 0

-- A default Studio template's floor would catch players falling into pits
for _, item in workspace:GetChildren() do
	if item:IsA("SpawnLocation") or (item:IsA("BasePart") and item.Name == "Baseplate") then
		item:Destroy()
	end
end

local existingStarter =StarterPlayer:FindFirstChild("StarterCharacter")
if existingStarter then
	existingStarter:Destroy()
end
CharacterFactory.buildStarterCharacter().Parent = StarterPlayer

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local inputRemote = Instance.new("RemoteEvent")
inputRemote.Name = "Input"
inputRemote.Parent = remotes
local restartRemote = Instance.new("RemoteEvent")
restartRemote.Name = "Restart"
restartRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

local gameState = Instance.new("Folder")
gameState.Name = "GameState"
gameState:SetAttribute("LevelCount", #Levels)
gameState.Parent = ReplicatedStorage

local playerDir = {}
local slots = {}
local levelIndex = 1
local level = nil
local phase = "loading"
local messageId = 0

local function setMessage(text)
	messageId += 1
	gameState:SetAttribute("Message", text)
	gameState:SetAttribute("MessageId", messageId)
end

local function activePositions(except)
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if player ~= except and root and player:GetAttribute("InDoor") ~= true then
			table.insert(list, root.Position)
		end
	end
	return list
end

local function spawnPlayer(player, position)
	player:SetAttribute("InDoor", false)
	local ok = pcall(function()
		player:LoadCharacter()
	end)
	local character = player.Character
	if not ok or not character or not character.Parent then
		return
	end
	character:PivotTo(CFrame.lookAt(position, position + Vector3.new(1, 0, 0)))
end

local function loadLevel(index)
	phase = "loading"
	levelIndex = index
	if level then
		level.folder:Destroy()
	end
	local data = Levels[index]
	level = LevelBuilder.build(data, index)
	level.folder.Parent = workspace

	gameState:SetAttribute("LevelIndex", index)
	gameState:SetAttribute("LevelName", data.name)
	gameState:SetAttribute("LevelHint", data.hint or "")

	for order, player in Players:GetPlayers() do
		spawnPlayer(player, level.spawn + Vector3.new((order - 1) * Config.SPAWN_SPACING, 0, 0))
	end
	-- Players who joined while characters were loading
	for _, player in Players:GetPlayers() do
		if not player.Character then
			spawnPlayer(player, level.spawn)
		end
	end
	phase = "playing"
end

local function restartLevel(text)
	if phase ~= "playing" then
		return
	end
	phase = "transition"
	setMessage(text)
	task.wait(Config.FAIL_DELAY)
	loadLevel(levelIndex)
end

local function completeLevel()
	if phase ~= "playing" then
		return
	end
	phase = "transition"
	local isLast = levelIndex >= #Levels
	setMessage(if isLast then "Все уровни пройдены! 🎉" else "Уровень пройден!")
	task.wait(Config.COMPLETE_DELAY)
	loadLevel(if isLast then 1 else levelIndex + 1)
end

local function claimSlot(player)
	for i = 1, #Config.PLAYER_COLORS do
		if not slots[i] then
			slots[i] = player
			return i
		end
	end
	return (#Players:GetPlayers() - 1) % #Config.PLAYER_COLORS + 1
end

local function onCharacterAdded(player, character)
	local slot = player:GetAttribute("Slot") or 1
	CharacterFactory.decorate(character, Config.PLAYER_COLORS[slot], player.DisplayName)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		if player.Character == character then
			task.spawn(restartLevel, "Упс! Попробуем ещё раз")
		end
	end)
end

local function onPlayerAdded(player)
	player:SetAttribute("Slot", claimSlot(player))
	player:SetAttribute("InDoor", false)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	if level and phase ~= "loading" then
		local others = activePositions(player)
		local position = level.spawn
		if #others > 0 then
			local sum = Vector3.zero
			for _, p in others do
				sum += p
			end
			position = sum / #others + Vector3.new(0, 4, 0)
		end
		spawnPlayer(player, Vector3.new(position.X, position.Y, 0))
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	playerDir[player] = nil
	for i, owner in slots do
		if owner == player then
			slots[i] = nil
		end
	end
end)

inputRemote.OnServerEvent:Connect(function(player, dir)
	if typeof(dir) ~= "number" or dir ~= dir then
		return
	end
	playerDir[player] = math.clamp(math.round(dir), -1, 1)
end)

restartRemote.OnServerEvent:Connect(function(player)
	task.spawn(restartLevel, `{player.DisplayName} перезапускает уровень`)
end)

RunService.Heartbeat:Connect(function(dt)
	if phase ~= "playing" or not level then
		return
	end

	local all = Players:GetPlayers()
	local infos = {}
	for _, player in all do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			table.insert(infos, {
				player = player,
				character = character,
				root = root,
				pos = root.Position,
				dir = playerDir[player] or 0,
				inDoor = player:GetAttribute("InDoor") == true,
			})
		end
	end

	if Mechanics.step(level, dt, infos, #all, os.clock()) == "fail" then
		task.spawn(restartLevel, "Упс! Попробуем ещё раз")
		return
	end

	if #all == 0 then
		return
	end
	for _, player in all do
		if player:GetAttribute("InDoor") ~= true then
			return
		end
	end
	task.spawn(completeLevel)
end)

loadLevel(1)
