local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Modes = require(ReplicatedStorage.Shared.Modes)
local ProgressStore = require(ReplicatedStorage.Shared.ProgressStore)
local Buddies = require(ReplicatedStorage.Shared.Buddies)
local HubWorld = require(script.HubWorld)

local PAD_RADIUS = 7
local PAD_HEIGHT_REACH = 12
local TELEPORT_TIMEOUT = 15
local TICK = 0.25

Lighting.ClockTime = 14
Lighting.GlobalShadows = true

-- The default Studio template's floor and spawn would overlap the hub floor
for _, item in workspace:GetChildren() do
	if item:IsA("SpawnLocation") or (item:IsA("BasePart") and item.Name == "Baseplate") then
		item:Destroy()
	end
end

local remotes = Instance.new("Folder")
remotes.Name = "HubRemotes"
local startNowRemote = Instance.new("RemoteEvent")
startNowRemote.Name = "StartNow"
startNowRemote.Parent = remotes
local setModeRemote = Instance.new("RemoteEvent")
setModeRemote.Name = "SetMode"
setModeRemote.Parent = remotes
local shopRemote = Instance.new("RemoteEvent")
shopRemote.Name = "Shop"
shopRemote.Parent = remotes
local noticeRemote = Instance.new("RemoteEvent")
noticeRemote.Name = "Notice"
noticeRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

local rooms = HubWorld.build(PAD_RADIUS)
for _, room in rooms do
	room.members = {}
	room.mode = Modes.order[1]
	room.state = "open"
	room.deadline = nil
	room.teleportStarted = 0
end

local function notice(player, text)
	noticeRemote:FireClient(player, text)
end

local function roomOf(player)
	for _, room in rooms do
		if table.find(room.members, player) then
			return room
		end
	end
	return nil
end

local function isOnPad(room, root)
	local offset = root.Position - room.center
	local flat = Vector2.new(offset.X, offset.Z)
	return flat.Magnitude < PAD_RADIUS and offset.Y > -1 and offset.Y < PAD_HEIGHT_REACH
end

local function pushOff(room, root)
	local out = (room.entrance - room.center).Unit
	local target = room.center + out * (PAD_RADIUS + 5) + Vector3.new(0, 3, 0)
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.lookAt(target, target + out)
end

local function resetRoom(room)
	room.state = "open"
	room.deadline = nil
end

local function teleportRoom(room)
	local members = table.clone(room.members)
	if #members < Config.ROOM_MIN_PLAYERS then
		resetRoom(room)
		return
	end

	if RunService:IsStudio() or Config.GAME_PLACE_ID == 0 then
		for _, player in members do
			notice(player, "Телепорт работает только в опубликованной игре и с заполненным GAME_PLACE_ID в Config.lua")
		end
		resetRoom(room)
		return
	end

	room.state = "teleporting"
	room.teleportStarted = os.clock()
	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true
	options:SetTeleportData({ roomSize = #members, mode = room.mode })
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Config.GAME_PLACE_ID, members, options)
	end)
	if not ok then
		warn("Room teleport failed:", err)
		for _, player in members do
			if player.Parent then
				notice(player, "Не удалось перейти в игру, попробуйте ещё раз")
			end
		end
		resetRoom(room)
	end
end

Players.PlayerAdded:Connect(ProgressStore.load)
for _, player in Players:GetPlayers() do
	task.spawn(ProgressStore.load, player)
end
Players.PlayerRemoving:Connect(ProgressStore.release)

-- Wardrobe: buddies and skins are bought with stars; Robux only buys skins and star packs
shopRemote.OnServerEvent:Connect(function(player, action, kind, id)
	if type(id) ~= "string" or (kind ~= "class" and kind ~= "skin") then
		return
	end
	if action == "select" then
		ProgressStore.select(player, kind, id)
	elseif action == "buy" then
		local catalog = Buddies.catalog(kind)
		local item = catalog[id]
		if item and not ProgressStore.buy(player, kind, id) and not ProgressStore.owns(player, kind, id) then
			noticeRemote:FireClient(player, `Не хватает звёзд: нужно ⭐ {item.cost}. Проходите уровни!`)
		end
	elseif action == "robux" then
		local productId = if kind == "skin" then Config.SKIN_PRODUCTS[id] else nil
		if id == "starPack" then
			productId = Config.STAR_PACK.productId
		end
		if productId and productId ~= 0 then
			MarketplaceService:PromptProductPurchase(player, productId)
		end
	end
end)

local function grantFor(productId)
	if productId == Config.STAR_PACK.productId and productId ~= 0 then
		return function(data)
			data.stars += Config.STAR_PACK.stars
		end
	end
	for skinId, skinProduct in Config.SKIN_PRODUCTS do
		if skinProduct ~= 0 and skinProduct == productId then
			return function(data)
				data.skins[skinId] = true
				data.skin = skinId
			end
		end
	end
	return nil
end

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local grant = grantFor(receipt.ProductId)
	if not player or not grant then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if ProgressStore.grantReceipt(player, receipt.PurchaseId, grant) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

TeleportService.TeleportInitFailed:Connect(function(player, _result, message)
	warn("TeleportInitFailed:", player.Name, message)
	notice(player, "Не удалось перейти в игру, попробуйте ещё раз")
	local room = roomOf(player)
	if room then
		resetRoom(room)
	end
end)

-- Only the first player on the pad (the room leader) picks the mode
setModeRemote.OnServerEvent:Connect(function(player, modeId)
	local room = roomOf(player)
	if room and room.state == "open" and room.members[1] == player and ProgressStore.isUnlocked(player, modeId) then
		room.mode = modeId
	end
end)

startNowRemote.OnServerEvent:Connect(function(player)
	local room = roomOf(player)
	if room and room.state == "open" and #room.members >= Config.ROOM_MIN_PLAYERS then
		local soon = os.clock() + Config.ROOM_START_NOW_WAIT
		room.deadline = if room.deadline then math.min(room.deadline, soon) else soon
	end
end)

local function updateMembership(room)
	local stillHere = {}
	for _, player in room.members do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if player.Parent and root and (room.state == "teleporting" or isOnPad(room, root)) then
			table.insert(stillHere, player)
		end
	end
	room.members = stillHere
	-- A new leader may not have unlocked the mode the previous leader picked
	if #stillHere == 0 or not ProgressStore.isUnlocked(stillHere[1], room.mode) then
		room.mode = Modes.order[1]
	end

	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and not table.find(room.members, player) and isOnPad(room, root) then
			local current = roomOf(player)
			if current and current ~= room then
				continue
			end
			if room.state == "open" and #room.members < room.capacity then
				table.insert(room.members, player)
			else
				pushOff(room, root)
				notice(player, if room.state == "open" then "Комната заполнена" else "Эта команда уже уходит в игру")
			end
		end
	end
end

local function updateCountdown(room, now)
	if room.state == "teleporting" then
		if #room.members == 0 or now - room.teleportStarted > TELEPORT_TIMEOUT then
			resetRoom(room)
		end
		return
	end

	local count = #room.members
	if count < Config.ROOM_MIN_PLAYERS then
		room.deadline = nil
		return
	end
	local wait = if count >= room.capacity then Config.ROOM_FULL_WAIT else Config.ROOM_WAIT
	room.deadline = if room.deadline then math.min(room.deadline, now + wait) else now + wait
	if now >= room.deadline then
		task.spawn(teleportRoom, room)
	end
end

local function publish(room, now)
	local count = #room.members
	local secondsLeft = if room.deadline then math.max(0, math.ceil(room.deadline - now)) else -1

	local modeInfo = Modes.get(room.mode)
	local status
	if room.state == "teleporting" then
		status = "Переход в игру…"
	elseif secondsLeft >= 0 then
		status = `{modeInfo.name} · {count}/{room.capacity} · старт {secondsLeft}`
	elseif count > 0 then
		status = `{modeInfo.name} · {count}/{room.capacity} · ждём игроков`
	else
		status = `0/{room.capacity} · свободно`
	end
	room.statusLabel.Text = status
	room.pad.Material = if count > 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic

	for _, player in room.members do
		player:SetAttribute("RoomCapacity", room.capacity)
		player:SetAttribute("RoomCount", count)
		player:SetAttribute("RoomSecondsLeft", secondsLeft)
		player:SetAttribute("RoomState", room.state)
		player:SetAttribute("RoomMode", room.mode)
		player:SetAttribute("RoomLeader", room.members[1] == player)
		player:SetAttribute("RoomUnlocked", room.members[1]:GetAttribute("UnlockedModes") or "")
	end
end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < TICK then
		return
	end
	elapsed = 0

	local now = os.clock()
	for _, room in rooms do
		updateMembership(room)
		updateCountdown(room, now)
		publish(room, now)
	end
	for _, player in Players:GetPlayers() do
		if not roomOf(player) and player:GetAttribute("RoomCapacity") ~= 0 then
			player:SetAttribute("RoomCapacity", 0)
		end
	end
end)
