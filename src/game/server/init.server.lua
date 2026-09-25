local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Levels = require(ReplicatedStorage.Shared.Levels)
local Modes = require(ReplicatedStorage.Shared.Modes)
local Parties = require(ReplicatedStorage.Shared.Parties)
local ProgressStore = require(ReplicatedStorage.Shared.ProgressStore)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)
local Buddies = require(ReplicatedStorage.Shared.Buddies)
local CharacterFactory = require(ReplicatedStorage.Shared.CharacterFactory)
local Community = require(ReplicatedStorage.Shared.Community)
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
local selectBuddyRemote = remote("SelectBuddy")
local grabRemote = remote("Grab")
local wriggleRemote = remote("Wriggle")
local thrownRemote = remote("Thrown")
local rewardRemote = remote("Reward")
remotes.Parent = ReplicatedStorage

local gameState = Instance.new("Folder")
gameState.Name = "GameState"
gameState:SetAttribute("HubAvailable", Config.HUB_PLACE_ID ~= 0)
gameState:SetAttribute("TimeLeft", -1)
gameState:SetAttribute("Signal", "")
gameState.Parent = ReplicatedStorage

local FAIL_TEXT = {
	time = "Time's up!",
}

-- Per-player gag lines when someone tumbles (used as the hardcore game-over reason too)
local KO_TEXT = {
	death = "Oops, {name}!",
	shot = "Boom! {name} caught a cannonball",
	scroll = "The screen caught {name}",
	stop = "{name}, no moving on red!",
}

local carrying = {} -- carrier -> carried player
local carriedBy = {} -- carried -> carrier

local playerDir = {}
local lastHubRequest = {}
local slots = {}
local mode = nil
local party = Parties.list.duo
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
	return if mode.endless then 0 else #Levels[party.id][mode.pack]
end

local function levelData(index)
	if mode.endless then
		return LevelGenerator.generate(runSeed, index, party.id)
	end
	return Levels[party.id][mode.pack][index]
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
	player:SetAttribute("KnockedOut", false)
	local ok = pcall(function()
		player:LoadCharacter()
	end)
	local character = player.Character
	if not ok or not character or not character.Parent then
		return
	end
	character:PivotTo(CFrame.lookAt(position, position + Vector3.new(1, 0, 0)))
end

local function activeRoot(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if
		humanoid
		and root
		and humanoid.Health > 0
		and player:GetAttribute("InDoor") ~= true
		and player:GetAttribute("KnockedOut") ~= true
	then
		return root
	end
	return nil
end

local function setWalkSpeed(player, speed)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

local function releaseCarry(player)
	local carried = carrying[player]
	if carried then
		carrying[player] = nil
		carriedBy[carried] = nil
		carried:SetAttribute("CarriedBy", nil)
		player:SetAttribute("Carrying", nil)
		setWalkSpeed(player, Config.WALK_SPEED)
	end
	local carrier = carriedBy[player]
	if carrier then
		releaseCarry(carrier)
	end
end

local function startCarry(carrier, carried)
	carrying[carrier] = carried
	carriedBy[carried] = carrier
	carrier:SetAttribute("Carrying", carried.UserId)
	carried:SetAttribute("CarriedBy", carrier.UserId)
	setWalkSpeed(carrier, Config.CARRY_WALK_SPEED)
end

local function clearLevel()
	if level then
		level.folder:Destroy()
		level = nil
	end
	gameState:SetAttribute("TimeLeft", -1)
	gameState:SetAttribute("Signal", "")
	gameState:SetAttribute("Celebrating", false)
	for _, player in Players:GetPlayers() do
		releaseCarry(player)
	end
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
	gameState:SetAttribute("LevelChapter", data.chapter or "")

	-- Buddy levels are built around one ability. If nobody brought that buddy, one pal borrows it
	-- for this level, so a team is never stuck without it.
	local loanMessage = nil
	local players = Players:GetPlayers()
	for _, player in players do
		player:SetAttribute("LoanClass", nil)
	end
	if data.needsClass and #players > 0 then
		local hasIt = false
		for _, player in players do
			if player:GetAttribute("Class") == data.needsClass then
				hasIt = true
			end
		end
		if not hasIt then
			local borrower = players[math.random(1, #players)]
			borrower:SetAttribute("LoanClass", data.needsClass)
			loanMessage = `{borrower.DisplayName} borrows the {Buddies.getClass(data.needsClass).name} for this level!`
		end
	end

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
	if loanMessage then
		setMessage(loanMessage, "info")
	end
end

-- Win streaks live for the whole visit to the experience, so they travel with teleports
local function streakData(players)
	local streaks = {}
	for _, player in players do
		streaks[tostring(player.UserId)] = player:GetAttribute("Streak") or 0
	end
	return { streaks = streaks }
end

local function resetStreaks()
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Streak", 0)
	end
end

local function sendToHub(players)
	if Config.HUB_PLACE_ID == 0 or RunService:IsStudio() or #players == 0 then
		return false
	end
	for _, player in players do
		ProgressStore.save(player)
	end
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(streakData(players))
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Config.HUB_PLACE_ID, players, options)
	end)
	if not ok then
		warn("Teleport to hub failed:", err)
	end
	return ok
end

local function chooseMode()
	phase = "choosing"
	gameState:SetAttribute("PartyId", Parties.forCount(#Players:GetPlayers()).id)
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

local function startRun(newMode, newParty)
	mode = newMode
	party = newParty or Parties.forCount(#Players:GetPlayers())
	gameState:SetAttribute("PartyId", party.id)
	gameState:SetAttribute("PartyName", party.name)
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
		setMessage("Heading back to the hub...", "info")
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

	resetStreaks()
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

-- Where a tumbled player comes back: the last checkpoint, or next to the team on scrolling levels
local function respawnPoint()
	local point = level.checkpoint or level.spawn
	if level.scroll and point.X < level.scroll.x + 6 then
		local rearmost = nil
		for _, other in Players:GetPlayers() do
			local root = activeRoot(other)
			if root and (not rearmost or root.Position.X < rearmost.X) then
				rearmost = root.Position
			end
		end
		point = if rearmost then rearmost + Vector3.new(0, 4, 0) else Vector3.new(level.scroll.x + 8, point.Y + 6, 0)
	end
	return Vector3.new(point.X, point.Y, 0)
end

-- Falling is a gag, not a punishment: the player tumbles for a moment and pops back at the
-- last checkpoint while the rest of the level stays as it is. Hardcore still ends the run.
local function knockOut(player, reason)
	if phase ~= "playing" or player:GetAttribute("KnockedOut") == true then
		return
	end
	local text = string.gsub(KO_TEXT[reason] or KO_TEXT.death, "{name}", player.DisplayName)
	if mode.oneLife then
		task.spawn(fail, reason, text)
		return
	end

	level.koCount += 1
	player:SetAttribute("KnockedOut", true)
	releaseCarry(player)
	local head = player.Character and player.Character:FindFirstChild("Head")
	if head then
		local _, dizzy = UiStyle.worldTag(head, Vector3.new(0, 2.2, 0), "✕ ✕", UiStyle.colors.danger, UiStyle.colors.white)
		dizzy.Name = "Dizzy"
	end
	setMessage(text, "ko")

	local koLevel = level
	task.delay(Config.KO_TIME, function()
		if level ~= koLevel or not player.Parent or player:GetAttribute("KnockedOut") ~= true then
			return
		end
		local position = respawnPoint()
		player:SetAttribute("KnockedOut", false)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and character.Parent and humanoid and humanoid.Health > 0 and root then
			local dizzy = character.Head:FindFirstChild("Dizzy")
			if dizzy then
				dizzy:Destroy()
			end
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			character:PivotTo(CFrame.lookAt(position, position + Vector3.new(1, 0, 0)))
		else
			spawnPlayer(player, position)
		end
	end)
end

-- Everyone pops out of the door and hops around while confetti flies (clients do the effects)
local function celebrate()
	local door = level.door
	if not door then
		return
	end
	local list = Players:GetPlayers()
	for i, player in list do
		local character = player.Character
		if character and character.Parent then
			CharacterFactory.show(character)
			player:SetAttribute("InDoor", false)
			local offset = (i - (#list + 1) / 2) * Config.SPAWN_SPACING
			local position = Vector3.new(door.x + offset, door.bottom + 2, 0)
			local facing = if offset > 0 then -1 else 1
			character:PivotTo(CFrame.lookAt(position, position + Vector3.new(facing, 0, 0)))
		end
	end
	gameState:SetAttribute("CelebrateAt", door.center)
	gameState:SetAttribute("Celebrating", true)
	gameState:SetAttribute("CelebrateId", (gameState:GetAttribute("CelebrateId") or 0) + 1)
end

local function completeLevel()
	if phase ~= "playing" then
		return
	end
	phase = "transition"
	celebrate()

	-- Rewards: base Paws/Stars x squad bonus (real number of pals who reached the door together)
	-- x personal win streak (levels cleared in a row this visit, capped)
	local finishers = #Players:GetPlayers()
	local squad = Parties.squadMultiplier(finishers)
	local basePaws = Config.PAWS[mode.id] or 10
	local baseStars = (Config.STARS[mode.id] or 1) + (if level.koCount == 0 then Config.STARS_NO_FALL_BONUS else 0)
	local levelKey = `{party.id}:{mode.pack or "endless"}:{levelIndex}`

	-- Referral: a new player invited by a friend gets a one-time bonus, for both, on their first
	-- level cleared together with that friend
	local referralBonus = {}
	for _, player in Players:GetPlayers() do
		local referrerId = ProgressStore.pendingReferrer(player)
		local referrer = referrerId and Players:GetPlayerByUserId(referrerId)
		if referrer then
			ProgressStore.completeReferral(player)
			referralBonus[player] = referrer.DisplayName
			referralBonus[referrer] = player.DisplayName
		end
	end

	for _, player in Players:GetPlayers() do
		local streak = player:GetAttribute("Streak") or 0
		local streakBonus = 1 + math.min(streak, Config.STREAK_CAP) * Config.STREAK_STEP
		local daily = ProgressStore.claimDaily(player)
		local firstClear = mode.endless or ProgressStore.markLevelCleared(player, levelKey)
		local multiplier = squad * streakBonus
			* (if daily then Config.DAILY_FIRST_CLEAR_MULT else 1)
			* (if firstClear then 1 else Config.REPLAY_MULT)
		local paws = math.round(basePaws * multiplier * Community.pawsMultiplier(player))
		local stars = math.round(baseStars * multiplier)
		if referralBonus[player] then
			paws += Config.REFERRAL_PAWS
		end
		ProgressStore.addReward(player, paws, stars)
		player:SetAttribute("Streak", streak + 1)
		rewardRemote:FireClient(player, {
			paws = paws,
			stars = stars,
			squad = squad,
			finishers = finishers,
			streak = streak + 1,
			streakBonus = streakBonus,
			noFalls = level.koCount == 0,
			daily = daily,
			replay = not firstClear,
			group = player:GetAttribute("InGroup") == true,
			referral = referralBonus[player],
		})

		Community.award(player, "firstClear")
		if finishers >= 4 then
			Community.award(player, "squadOf4")
		end
		if finishers >= 8 then
			Community.award(player, "partyOf8")
		end
		if level.koCount == 0 and mode.pack == "hard" then
			Community.award(player, "noFalls")
		end
		if mode.endless and levelIndex >= 10 then
			Community.award(player, "endless10")
		end
	end

	local isLast = not mode.endless and levelIndex >= levelCount()
	if mode.endless then
		for _, player in Players:GetPlayers() do
			ProgressStore.recordEndless(player, party.id, levelIndex)
		end
	end
	if isLast then
		for _, player in Players:GetPlayers() do
			ProgressStore.markCompleted(player, party.id, mode.id)
			if mode.id == "hardcore" then
				Community.award(player, "hardcoreHero")
			end
		end
		local unlockedNext = nil
		for _, id in Modes.order do
			if Modes.get(id).requires == mode.id then
				unlockedNext = Modes.get(id)
			end
		end
		setMessage(
			if unlockedNext
				then `{party.name} {mode.name} cleared! {unlockedNext.name} unlocked for {party.name}`
				else `{party.name} {mode.name} cleared! You are legends!`,
			"success"
		)
		task.wait(Config.COMPLETE_DELAY + 3)
		endRun()
		return
	end
	setMessage(
		if mode.endless then `Level {levelIndex} cleared! Squad x{squad}` else `Level cleared! Squad x{squad}`,
		"success"
	)
	task.wait(Config.COMPLETE_DELAY + 1)
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
	CharacterFactory.decorate(
		character,
		Config.PLAYER_COLORS[slot],
		player.DisplayName,
		player:GetAttribute("LoanClass") or player:GetAttribute("Class"),
		player:GetAttribute("Skin")
	)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		if player.Character == character then
			knockOut(player, "death")
		end
	end)
end

local function onPlayerAdded(player)
	local joinData = player:GetJoinData().TeleportData
	local streaks = type(joinData) == "table" and type(joinData.streaks) == "table" and joinData.streaks or {}
	player:SetAttribute("Streak", math.clamp(math.floor(tonumber(streaks[tostring(player.UserId)]) or 0), 0, 1000))
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
	releaseCarry(player)
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
		task.spawn(fail, "giveup", `{player.DisplayName} gave up`)
	else
		phase = "transition"
		-- A voluntary restart is not a failure, so win streaks survive it
		setMessage(`{player.DisplayName} restarted the level`, "info")
		task.delay(Config.FAIL_DELAY, loadLevel, levelIndex)
	end
end)

chooseModeRemote.OnServerEvent:Connect(function(player, id)
	if phase == "choosing" and ProgressStore.isUnlocked(player, id, Parties.forCount(#Players:GetPlayers()).id) then
		modeChosen:Fire(id)
	end
end)

selectBuddyRemote.OnServerEvent:Connect(function(player, kind, id)
	if phase == "choosing" and (kind == "class" or kind == "skin") and type(id) == "string" then
		ProgressStore.select(player, kind, id)
	end
end)

-- Press once to pick up the nearest teammate, press again to throw them where you face
grabRemote.OnServerEvent:Connect(function(player, facing)
	if phase ~= "playing" then
		return
	end
	local dir = if facing == -1 then -1 else 1
	local carried = carrying[player]
	if carried then
		releaseCarry(player)
		thrownRemote:FireClient(carried, Vector3.new(dir * Config.THROW_VELOCITY.X, Config.THROW_VELOCITY.Y, 0))
		return
	end
	local myRoot = activeRoot(player)
	if carriedBy[player] or not myRoot then
		return
	end
	local best, bestDistance = nil, math.huge
	for _, other in Players:GetPlayers() do
		local root = other ~= player and not carrying[other] and not carriedBy[other] and activeRoot(other)
		if root then
			local offset = root.Position - myRoot.Position
			if math.abs(offset.X) < Config.CARRY_REACH and math.abs(offset.Y) < 3.5 and math.abs(offset.X) < bestDistance then
				best, bestDistance = other, math.abs(offset.X)
			end
		end
	end
	if best then
		startCarry(player, best)
	end
end)

wriggleRemote.OnServerEvent:Connect(function(player)
	if carriedBy[player] then
		releaseCarry(player)
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
				weight = if (player:GetAttribute("LoanClass") or player:GetAttribute("Class")) == "bear" then 2 else 1,
				inDoor = player:GetAttribute("InDoor") == true,
				knockedOut = player:GetAttribute("KnockedOut") == true,
			})
		end
	end

	for carrier, carried in carrying do
		if not activeRoot(carrier) or not activeRoot(carried) then
			releaseCarry(carrier)
		end
	end

	local reason, knocked = Mechanics.step(level, dt, infos, #all, os.clock())
	gameState:SetAttribute("TimeLeft", level.timeLeft or -1)
	gameState:SetAttribute("Signal", level.signal or "")
	if reason then
		task.spawn(fail, reason)
		return
	end
	for player, why in knocked do
		knockOut(player, why)
	end
	if phase ~= "playing" then
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
	local teleportParty = nil
	if type(data) == "table" then
		if type(data.roomSize) == "number" and data.roomSize == data.roomSize then
			expected = math.clamp(math.floor(data.roomSize), 1, #Config.PLAYER_COLORS)
		end
		teleportMode = Modes.get(data.mode)
		teleportParty = Parties.get(data.party)
	end

	local deadline = os.clock() + Config.TEAM_ARRIVAL_TIMEOUT
	while #Players:GetPlayers() < expected and os.clock() < deadline do
		gameState:SetAttribute("Waiting", `Waiting for the team: {#Players:GetPlayers()}/{expected}`)
		task.wait(0.5)
	end
	gameState:SetAttribute("Waiting", "")
	if teleportMode then
		startRun(teleportMode, teleportParty)
	else
		startRun(chooseMode())
	end
end

ProgressStore.start()
Community.start()
start()
