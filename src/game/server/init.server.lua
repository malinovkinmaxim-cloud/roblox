local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Levels = require(ReplicatedStorage.Shared.Levels)
local Modes = require(ReplicatedStorage.Shared.Modes)
local ProgressStore = require(ReplicatedStorage.Shared.ProgressStore)
local CharacterFactory = require(script.CharacterFactory)
local LevelBuilder = require(script.LevelBuilder)
local LevelGenerator = require(script.LevelGenerator)
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

local existingStarter = StarterPlayer:FindFirstChild("StarterCharacter")
if existingStarter then
	existingStarter:Destroy()
end
CharacterFactory.buildStarterCharacter().Parent = StarterPlayer

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(name)
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remotes
	return event
end
local inputRemote = remote("Input")
local restartRemote = remote("Restart")
local toHubRemote = remote("ToHub")
local chooseModeRemote = remote("ChooseMode")
remotes.Parent = ReplicatedStorage

local gameState = Instance.new("Folder")
gameState.Name = "GameState"
gameState:SetAttribute("HubAvailable", Config.HUB_PLACE_ID ~= 0)
gameState:SetAttribute("TimeLeft", -1)
gameState:SetAttribute("Signal", "")
gameState.Parent = ReplicatedStorage

local FAIL_TEXT = {
	death = "Упс! Ещё разок",
	shot = "Попадание из пушки!",
	scroll = "Экран вас обогнал!",
	stop = "Кто-то двигался на красный!",
	time = "Время вышло!",
}

local playerDir = {}
local lastHubRequest = {}
local slots = {}
local mode = nil
local runSeed = 0
local levelIndex = 1
local level = nil
local phase = "waiting"
local messageId = 0
local modeChosen = Instance.new("BindableEvent")

-- kind: "success" | "fail" | "info" (picks the banner colour on the client)
local function setMessage(text, kind)
	messageId += 1
	gameState:SetAttribute("Message", text)
	gameState:SetAttribute("MessageKind", kind or "info")
	gameState:SetAttribute("MessageId", messageId)
end

local function levelCount()
	return if mode.endless then 0 else #Levels[mode.pack]
end

local function levelData(index)
	if mode.endless then
		return LevelGenerator.generate(runSeed, index)
	end
	return Levels[mode.pack][index]
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

local function clearLevel()
	if level then
		level.folder:Destroy()
		level = nil
	end
	gameState:SetAttribute("TimeLeft", -1)
	gameState:SetAttribute("Signal", "")
end

local function loadLevel(index)
	phase = "loading"
	levelIndex = index
	clearLevel()
	local data = levelData(index)
	level = LevelBuilder.build(data, index)
	level.folder.Parent = workspace

	gameState:SetAttribute("LevelIndex", index)
	gameState:SetAttribute("LevelName", data.name)
	gameState:SetAttribute("LevelHint", data.hint or "")
	gameState:SetAttribute("LevelSerial", (gameState:GetAttribute("LevelSerial") or 0) + 1)

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

local function sendToHub(players)
	if Config.HUB_PLACE_ID == 0 or RunService:IsStudio() or #players == 0 then
		return false
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Config.HUB_PLACE_ID, players)
	end)
	if not ok then
		warn("Teleport to hub failed:", err)
	end
	return ok
end

local function chooseMode()
	phase = "choosing"
	clearLevel()
	for _, player in Players:GetPlayers() do
		if player.Character then
			player.Character:Destroy()
		end
	end
	gameState:SetAttribute("ChoosingMode", true)
	local chosen = Modes.get(modeChosen.Event:Wait())
	gameState:SetAttribute("ChoosingMode", false)
	return chosen
end

local function startRun(newMode)
	mode = newMode
	runSeed = math.random(1, 1000000)
	gameState:SetAttribute("ModeId", mode.id)
	gameState:SetAttribute("ModeName", mode.name)
	gameState:SetAttribute("LevelCount", levelCount())
	gameState:SetAttribute("GameOver", false)
	loadLevel(1)
end

-- After the last level or a hardcore game over: back to the hub, or (in Studio) pick a mode again
local function endRun()
	if sendToHub(Players:GetPlayers()) then
		setMessage("Возвращаемся в хаб…", "info")
		task.wait(15)
		if #Players:GetPlayers() == 0 then
			return
		end
	end
	gameState:SetAttribute("GameOver", false)
	startRun(chooseMode())
end

local function fail(reason, customText)
	if phase ~= "playing" then
		return
	end
	phase = "transition"
	local text = customText or FAIL_TEXT[reason] or FAIL_TEXT.death

	if mode.oneLife then
		phase = "gameover"
		gameState:SetAttribute("GameOverReason", text)
		gameState:SetAttribute("GameOverLevel", levelIndex)
		gameState:SetAttribute("GameOver", true)
		task.wait(6)
		endRun()
		return
	end

	setMessage(text, "fail")
	task.wait(Config.FAIL_DELAY)
	loadLevel(levelIndex)
end

local function completeLevel()
	if phase ~= "playing" then
		return
	end
	phase = "transition"
	local isLast = not mode.endless and levelIndex >= levelCount()
	if mode.endless then
		for _, player in Players:GetPlayers() do
			ProgressStore.recordEndless(player, levelIndex)
		end
	end
	if isLast then
		for _, player in Players:GetPlayers() do
			ProgressStore.markCompleted(player, mode.id)
		end
		local unlockedNext = nil
		for _, id in Modes.order do
			if Modes.get(id).requires == mode.id then
				unlockedNext = Modes.get(id)
			end
		end
		setMessage(
			if unlockedNext
				then `{mode.name} пройден! Открыт режим «{unlockedNext.name}»`
				else `{mode.name} пройден! Вы легенды!`,
			"success"
		)
		task.wait(Config.COMPLETE_DELAY + 2)
		endRun()
		return
	end
	setMessage(if mode.endless then `Уровень {levelIndex} пройден!` else "Уровень пройден!", "success")
	task.wait(Config.COMPLETE_DELAY)
	loadLevel(levelIndex + 1)
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
			task.spawn(fail, "death")
		end
	end)
end

local function onPlayerAdded(player)
	task.spawn(ProgressStore.load, player)
	player:SetAttribute("Slot", claimSlot(player))
	player:SetAttribute("InDoor", false)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	if level and (phase == "playing" or phase == "transition") then
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
	ProgressStore.release(player)
	playerDir[player] = nil
	lastHubRequest[player] = nil
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
	if phase ~= "playing" then
		return
	end
	if mode.oneLife then
		task.spawn(fail, "giveup", `{player.DisplayName} сдаётся`)
	else
		phase = "transition"
		setMessage(`{player.DisplayName} начинает заново`, "info")
		task.delay(Config.FAIL_DELAY, loadLevel, levelIndex)
	end
end)

chooseModeRemote.OnServerEvent:Connect(function(player, id)
	if phase == "choosing" and ProgressStore.isUnlocked(player, id) then
		modeChosen:Fire(id)
	end
end)

toHubRemote.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if lastHubRequest[player] and now - lastHubRequest[player] < 5 then
		return
	end
	lastHubRequest[player] = now
	sendToHub({ player })
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

	local reason = Mechanics.step(level, dt, infos, #all, os.clock())
	gameState:SetAttribute("TimeLeft", level.timeLeft or -1)
	gameState:SetAttribute("Signal", level.signal or "")
	if reason then
		task.spawn(fail, reason)
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

-- Players from one hub room arrive one by one; give the whole team a moment before level 1.
-- The hub also tells us which mode the room picked; without it (Studio) the players choose here.
local function start()
	local first = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
	local expected = 1
	local data = first:GetJoinData().TeleportData
	local teleportMode = nil
	if type(data) == "table" then
		if type(data.roomSize) == "number" and data.roomSize == data.roomSize then
			expected = math.clamp(math.floor(data.roomSize), 1, #Config.PLAYER_COLORS)
		end
		teleportMode = Modes.get(data.mode)
	end

	local deadline = os.clock() + Config.TEAM_ARRIVAL_TIMEOUT
	while #Players:GetPlayers() < expected and os.clock() < deadline do
		gameState:SetAttribute("Waiting", `Ждём команду: {#Players:GetPlayers()}/{expected}`)
		task.wait(0.5)
	end
	gameState:SetAttribute("Waiting", "")
	startRun(teleportMode or chooseMode())
end

start()
