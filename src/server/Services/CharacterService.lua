--[[
	CharacterService
	Owns character spawning (Players.CharacterAutoLoads is false):
	  - loads the character once the profile is ready
	  - puts characters in the "Players" collision group
	  - decides where a (re)spawned character goes (lobby or current checkpoint)
	  - reports deaths to RoundService
]]

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CosmeticsConfig = require(ReplicatedStorage.Shared.CosmeticsConfig)
local TitleConfig = require(ReplicatedStorage.Shared.TitleConfig)

local CharacterService = {}

local LOBBY_RESPAWN_DELAY = 1.5

function CharacterService:Init(services)
	self.Services = services
	Players.CharacterAutoLoads = false

	-- Collision groups:
	--   Players  : characters
	--   Movers   : moving platforms (ignore static geometry so they never get stuck)
	--   Doppel   : doppelgänger rigs (never physically collide with anything)
	for _, group in { "Players", "Movers", "Doppel" } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(group)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable("Movers", "Default", false)
	PhysicsService:CollisionGroupSetCollidable("Movers", "Movers", false)
	PhysicsService:CollisionGroupSetCollidable("Movers", "Players", true)
	PhysicsService:CollisionGroupSetCollidable("Doppel", "Default", false)
	PhysicsService:CollisionGroupSetCollidable("Doppel", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("Doppel", "Movers", false)
	PhysicsService:CollisionGroupSetCollidable("Doppel", "Doppel", false)
	PhysicsService:CollisionGroupSetCollidable("Players", "Players", true)
end

function CharacterService:Start()
	local DataService = self.Services.DataService

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			self:_onCharacterAdded(player, character)
		end)
		task.spawn(function()
			DataService:WaitForData(player, 40)
			if player.Parent and not player.Character then
				self:Respawn(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

local function setCollisionGroup(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end)
end

function CharacterService:_onCharacterAdded(player: Player, character: Model)
	setCollisionGroup(character)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end

	humanoid.Died:Connect(function()
		self.Services.RoundService:OnCharacterDied(player, character)
	end)
	self:ApplyCosmetics(player)

	-- where should this character be?
	local spawnCFrame = self.Services.RoundService:OnCharacterSpawned(player, character)
	local inLobby = spawnCFrame == nil
	local target = spawnCFrame or self:GetLobbySpawn()
	task.defer(function()
		if character.Parent then
			character:PivotTo(target)
			if inLobby then
				self.Services.DoppelgangerService:OnLobbySpawn(player)
			end
		end
	end)
end

function CharacterService:GetLobbySpawn(): CFrame
	local lobby = Workspace:FindFirstChild("Lobby")
	local spawnPart = lobby and lobby:FindFirstChild("LobbySpawn", true)
	if spawnPart and spawnPart:IsA("BasePart") then
		local offset = Vector3.new(math.random(-6, 6), 3.5, math.random(-6, 6))
		return CFrame.new(spawnPart.Position + offset) * CFrame.Angles(0, math.rad(180), 0)
	end
	return CFrame.new(0, 10, 0)
end

-- (Re)load a character. Safe to call any time.
function CharacterService:Respawn(player: Player)
	if not player.Parent then
		return
	end
	task.spawn(function()
		-- LoadCharacterAsync is the current API; fall back to LoadCharacter on older engines
		local ok, err = pcall(function()
			(player :: any):LoadCharacterAsync()
		end)
		if not ok and string.find(tostring(err), "valid member", 1, true) then
			ok, err = pcall(function()
				(player :: any):LoadCharacter()
			end)
		end
		if not ok then
			warn("[CharacterService] LoadCharacter failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)
end

function CharacterService:RespawnInLobbyLater(player: Player)
	task.delay(LOBBY_RESPAWN_DELAY, function()
		if player.Parent and not self.Services.RoundService:GetRun(player) then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				self:Respawn(player)
			end
		end
	end)
end

-- Instantly move a living character (or respawn it if it has none).
function CharacterService:Teleport(player: Player, cf: CFrame)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if character and humanoid and humanoid.Health > 0 and root then
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(cf)
		return true
	end
	self:Respawn(player)
	return false
end

---------------------------------------------------------------------------
-- Cosmetics on the player's own character: trail + title tag
---------------------------------------------------------------------------

local function removeNamed(parent: Instance?, name: string)
	if not parent then
		return
	end
	for _, child in parent:GetChildren() do
		if child.Name == name then
			child:Destroy()
		end
	end
end

function CharacterService:ApplyCosmetics(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local data = self.Services.DataService:GetData(player)
	if not character or not root or not data then
		return
	end

	-- trail
	removeNamed(root, "CosmeticTrail")
	removeNamed(root, "CosmeticTrailTop")
	removeNamed(root, "CosmeticTrailBottom")
	local trailItem = CosmeticsConfig.Get(data.EquippedTrail or "")
	if trailItem and trailItem.Category == "Trail" and trailItem.Colors and data.OwnedCosmetics[data.EquippedTrail] then
		local top = Instance.new("Attachment")
		top.Name = "CosmeticTrailTop"
		top.Position = Vector3.new(0, 0.9, 0)
		top.Parent = root
		local bottom = Instance.new("Attachment")
		bottom.Name = "CosmeticTrailBottom"
		bottom.Position = Vector3.new(0, -0.9, 0)
		bottom.Parent = root
		local keypoints = {}
		local colors = trailItem.Colors
		for index, color in colors do
			local t = if #colors == 1 then 0 else (index - 1) / (#colors - 1)
			table.insert(keypoints, ColorSequenceKeypoint.new(t, color))
		end
		if #keypoints == 1 then
			table.insert(keypoints, ColorSequenceKeypoint.new(1, colors[1]))
		end
		local trail = Instance.new("Trail")
		trail.Name = "CosmeticTrail"
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Color = ColorSequence.new(keypoints)
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		trail.Lifetime = 0.45
		trail.MinLength = 0.1
		trail.LightEmission = 0.5
		trail.FaceCamera = true
		trail.Parent = root
	end

	-- title tag above the head
	removeNamed(character, "TitleTag")
	local titleId = data.EquippedTitle
	if not TitleConfig.IsUnlocked(data, titleId) then
		titleId = TitleConfig.Default
	end
	local title = TitleConfig.Titles[titleId]
	if head and title then
		local tag = Instance.new("BillboardGui")
		tag.Name = "TitleTag"
		tag.Adornee = head
		tag.Size = UDim2.new(6, 0, 0.8, 0)
		tag.StudsOffsetWorldSpace = Vector3.new(0, 3.3, 0)
		tag.MaxDistance = 60
		tag.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = title.Color
		label.TextStrokeTransparency = 0.35
		label.Text = title.Text
		label.Parent = tag
		tag.Parent = character
	end
end

-- Returns root, humanoid, rootOffset (studs between feet and root center) of a living character.
function CharacterService:GetLiving(player: Player): (BasePart?, Humanoid?, number)
	local character = player.Character
	if not character then
		return nil, nil, 3
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil, 3
	end
	local offset
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		offset = 3
	else
		offset = humanoid.HipHeight + root.Size.Y / 2
	end
	return root, humanoid, offset
end

return CharacterService
