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
local Workspace = game:GetService("Workspace")

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
