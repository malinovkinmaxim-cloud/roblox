local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local TeleportService = game:GetService("TeleportService")

local Buddies = require(ReplicatedStorage.Shared.Buddies)
local CharacterFactory = require(ReplicatedStorage.Shared.CharacterFactory)
local Community = require(ReplicatedStorage.Shared.Community)
local Config = require(ReplicatedStorage.Shared.Config)
local Modes = require(ReplicatedStorage.Shared.Modes)
local Parties = require(ReplicatedStorage.Shared.Parties)
local ProgressStore = require(ReplicatedStorage.Shared.ProgressStore)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)
local HubWorld = require(script.HubWorld)

local PAD_RADIUS = 7
local PAD_HEIGHT_REACH = 12
local TELEPORT_TIMEOUT = 15
local TICK = 0.25

local BONUS_TEXT = {
	solo = "x1 rewards",
	duo = "x1.5 rewards",
	squad = "x2 rewards",
	party = "x2.5 rewards",
}

Lighting.ClockTime = 14
Lighting.GlobalShadows = true

-- The default Studio template's floor and spawn would overlap the hub floor
for _, item in workspace:GetChildren() do
	if item:IsA("SpawnLocation") or (item:IsA("BasePart") and item.Name == "Baseplate") then
		item:Destroy()
	end
end

-- Same pixel buddy as in the game place instead of the default avatar
StarterPlayer.LoadCharacterAppearance = false
local existingStarter = StarterPlayer:FindFirstChild("StarterCharacter")
if existingStarter then
	existingStarter:Destroy()
end
CharacterFactory.buildStarterCharacter().Parent = StarterPlayer

local slots = {}
local function claimSlot(player)
	for i = 1, #Config.PLAYER_COLORS do
		if not slots[i] then
			slots[i] = player
			return i
		end
	end
	return (#Players:GetPlayers() - 1) % #Config.PLAYER_COLORS + 1
end

local remotes = Instance.new("Folder")
remotes.Name = "HubRemotes"
local function remote(name)
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remotes
	return event
end
local startNowRemote = remote("StartNow")
local setModeRemote = remote("SetMode")
local shopRemote = remote("Shop")
local noticeRemote = remote("Notice")
local inviteRemote = remote("Invite")
remotes.Parent = ReplicatedStorage

local rooms, extras = HubWorld.build(PAD_RADIUS)
for _, room in rooms do
	room.members = {}
	room.mode = Modes.order[1]
	room.state = "open"
	room.deadline = nil
	room.teleportStarted = 0
end

local lastInvite = {}

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

local function rootOf(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function isOnPad(center, radius, root)
	local offset = root.Position - center
	return Vector2.new(offset.X, offset.Z).Magnitude < radius and offset.Y > -1 and offset.Y < PAD_HEIGHT_REACH
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

-- Badge over the head with the chosen party size and its promised bonus
local function showPartyBadge(player)
	local partyInfo = Parties.get(player:GetAttribute("PartyChoice"))
	local head = player.Character and player.Character:FindFirstChild("Head")
	if not partyInfo or not head then
		return
	end
	local old = head:FindFirstChild("PartyBadge")
	if old then
		old:Destroy()
	end
	local label, gui = UiStyle.worldTag(head, Vector3.new(0, 5, 0), `{partyInfo.name} · {BONUS_TEXT[partyInfo.id]}`, partyInfo.color, UiStyle.colors.white)
	gui.Name = "PartyBadge"
	gui.Size = UDim2.fromOffset(190, 32)
	UiStyle.stroke(label, 1.5, UiStyle.colors.ink, Enum.ApplyStrokeMode.Contextual)
end

local function choosePartyKiosk(player, partyInfo)
	if player:GetAttribute("PartyChoice") ~= partyInfo.id then
		player:SetAttribute("PartyChoice", partyInfo.id)
		showPartyBadge(player)
	end
end

-- Real matchmaking: the room's players are moved together to a fresh reserved server of the game
-- place (TeleportAsync + ShouldReserveServer). Studio playtests cannot teleport between places, so
-- in Studio every room stays on this one server and players just get a notice instead.
local function teleportRoom(room)
	local members = table.clone(room.members)
	if #members < room.minPlayers then
		resetRoom(room)
		return
	end

	if RunService:IsStudio() or Config.GAME_PLACE_ID == 0 then
		for _, player in members do
			notice(player, "Teleports only work in the published game with GAME_PLACE_ID set in Config.lua")
		end
		resetRoom(room)
		return
	end

	room.state = "teleporting"
	room.teleportStarted = os.clock()
	local streaks = {}
	for _, player in members do
		streaks[tostring(player.UserId)] = player:GetAttribute("Streak") or 0
		ProgressStore.save(player)
	end
	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true
	options:SetTeleportData({ roomSize = #members, mode = room.mode, party = room.party.id, streaks = streaks })
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Config.GAME_PLACE_ID, members, options)
	end)
	if not ok then
		warn("Room teleport failed:", err)
		for _, player in members do
			if player.Parent then
				notice(player, "Could not start the game, please try again")
			end
		end
		resetRoom(room)
	end
end

local function onPlayerAdded(player)
	-- Win streaks survive trips between the hub and the game (they end when you leave the experience)
	local data = player:GetJoinData().TeleportData
	local streaks = type(data) == "table" and type(data.streaks) == "table" and data.streaks or {}
	player:SetAttribute("Streak", math.clamp(math.floor(tonumber(streaks[tostring(player.UserId)]) or 0), 0, 1000))
	player:SetAttribute("Slot", claimSlot(player))

	-- Invited by a friend? Remember who, once the save has loaded (only brand-new players count)
	local referrerId = player:GetJoinData().ReferredByPlayerId
	if type(referrerId) == "number" and referrerId > 0 then
		task.spawn(function()
			while player.Parent and player:GetAttribute("SaveStatus") == nil do
				task.wait(0.2)
			end
			if player.Parent then
				ProgressStore.setReferrer(player, referrerId)
			end
		end)
	end
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head")
		CharacterFactory.decorate(
			character,
			Config.PLAYER_COLORS[player:GetAttribute("Slot")],
			player.DisplayName,
			player:GetAttribute("Class"),
			player:GetAttribute("Skin")
		)
		-- The hub is a free 3D lobby: normal camera-relative walking and turning
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.AutoRotate = true
			humanoid.WalkSpeed = 18
		end
		showPartyBadge(player)
	end)

	-- Rebuild the buddy when the wardrobe (or the save loading) changes class or skin
	local pending = false
	local function refreshLook()
		if pending then
			return
		end
		pending = true
		task.delay(0.3, function()
			pending = false
			local root = rootOf(player)
			if player.Parent and root and not roomOf(player) then
				local position = root.CFrame
				player:LoadCharacter()
				if player.Character then
					player.Character:PivotTo(position)
				end
			end
		end)
	end
	player:GetAttributeChangedSignal("Class"):Connect(refreshLook)
	player:GetAttributeChangedSignal("Skin"):Connect(refreshLook)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerRemoving:Connect(function(player)
	lastInvite[player] = nil
	for i, owner in slots do
		if owner == player then
			slots[i] = nil
		end
	end
end)
ProgressStore.start()
Community.start()

-- Wardrobe: buddies and skins are bought with Paws; Robux only buys skins and Paw packs
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
			notice(player, `Not enough Paws: you need 🐾 {item.cost}. Clear some levels!`)
		end
	elseif action == "robux" then
		local productId = if kind == "skin" then Config.SKIN_PRODUCTS[id] else nil
		if id == "pawPack" then
			productId = Config.PAW_PACK.productId
		end
		if productId and productId ~= 0 then
			MarketplaceService:PromptProductPurchase(player, productId)
		end
	end
end)

local function grantFor(productId)
	if productId == Config.PAW_PACK.productId and productId ~= 0 then
		return function(data)
			data.paws += Config.PAW_PACK.paws
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
	notice(player, "Could not start the game, please try again")
	local room = roomOf(player)
	if room then
		resetRoom(room)
	end
end)

-- Only the first player on the pad (the room leader) picks the mode
setModeRemote.OnServerEvent:Connect(function(player, modeId)
	local room = roomOf(player)
	if room and room.state == "open" and room.members[1] == player and ProgressStore.isUnlocked(player, modeId, room.party.id) then
		room.mode = modeId
	end
end)

startNowRemote.OnServerEvent:Connect(function(player)
	local room = roomOf(player)
	if room and room.state == "open" and #room.members >= room.minPlayers then
		local soon = os.clock() + Config.ROOM_START_NOW_WAIT
		room.deadline = if room.deadline then math.min(room.deadline, soon) else soon
	end
end)

local function updateMembership(room)
	local stillHere = {}
	for _, player in room.members do
		local root = rootOf(player)
		if player.Parent and root and (room.state == "teleporting" or isOnPad(room.center, PAD_RADIUS, root)) then
			table.insert(stillHere, player)
		end
	end
	room.members = stillHere
	-- A new leader may not have unlocked the mode the previous leader picked
	if #stillHere == 0 or not ProgressStore.isUnlocked(stillHere[1], room.mode, room.party.id) then
		room.mode = Modes.order[1]
	end

	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and not table.find(room.members, player) and isOnPad(room.center, PAD_RADIUS, root) then
			local current = roomOf(player)
			if current and current ~= room then
				continue
			end
			if room.state == "open" and #room.members < room.capacity then
				table.insert(room.members, player)
				choosePartyKiosk(player, room.party)
			else
				pushOff(room, root)
				notice(player, if room.state == "open" then "This kiosk is full" else "This team is already heading out")
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
	if count < room.minPlayers then
		room.deadline = nil
		return
	end
	local wait = if room.capacity == 1
		then Config.ROOM_SOLO_WAIT
		elseif count >= room.capacity then Config.ROOM_FULL_WAIT
		else Config.ROOM_WAIT
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
		status = "Heading out..."
	elseif secondsLeft >= 0 then
		status = `{modeInfo.name} · {count}/{room.capacity} · go in {secondsLeft}`
	elseif count > 0 then
		status = `{modeInfo.name} · {count}/{room.capacity} · need {room.minPlayers}`
	else
		status = `0/{room.capacity} · open`
	end
	room.statusLabel.Text = status
	room.pad.Material = if count > 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic

	for _, player in room.members do
		player:SetAttribute("RoomParty", room.party.id)
		player:SetAttribute("RoomCapacity", room.capacity)
		player:SetAttribute("RoomMin", room.minPlayers)
		player:SetAttribute("RoomCount", count)
		player:SetAttribute("RoomSecondsLeft", secondsLeft)
		player:SetAttribute("RoomState", room.state)
		player:SetAttribute("RoomMode", room.mode)
		player:SetAttribute("RoomLeader", room.members[1] == player)
		player:SetAttribute("RoomUnlocked", room.members[1]:GetAttribute(`Unlocked_{room.party.id}`) or "")
	end
end

-- Invite kiosk: the server asks the client to open Roblox's invite prompt
local function updateInviteKiosk()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and isOnPad(extras.invite.center, extras.invite.radius, root) then
			if not lastInvite[player] or now - lastInvite[player] > Config.INVITE_COOLDOWN then
				lastInvite[player] = now
				inviteRemote:FireClient(player)
			end
		end
	end
end

-- Top 5 players on this server by Stars
local function refreshLeaderboard()
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		return (a:GetAttribute("Stars") or 0) > (b:GetAttribute("Stars") or 0)
	end)
	local lines = { "TOP STARS" }
	for i = 1, math.min(5, #list) do
		table.insert(lines, `{i}. {list[i].DisplayName}  ⭐ {list[i]:GetAttribute("Stars") or 0}`)
	end
	if #list == 0 then
		table.insert(lines, "Nobody here yet")
	end
	extras.leaderboardLabel.Text = table.concat(lines, "\n")
end

task.spawn(function()
	while true do
		refreshLeaderboard()
		task.wait(Config.LEADERBOARD_REFRESH)
	end
end)

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
	updateInviteKiosk()
	for _, player in Players:GetPlayers() do
		if not roomOf(player) and player:GetAttribute("RoomCapacity") ~= 0 then
			player:SetAttribute("RoomCapacity", 0)
		end
	end
end)
