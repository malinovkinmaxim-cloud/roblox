--[[
	CharacterService - the physical character stays a normal-sized R15 rig (so walking,
	collisions and the camera stay sane), but it is made INVISIBLE. Every client draws the
	funny stretched body on top of it (client/Controllers/BodyController).

	  * all parts / decals / accessories -> Transparency 1; the original value is kept in the
	    "TetOrig" attribute so clients can clone the head + hats with their real look
	  * players don't collide with each other (a 500-stud body walks through a 1-stud one)
	  * no jumping (Space = TAP), no default name / health bar (we draw our own tag)
	  * walk speed grows with the visual body height (long legs = long steps), server-side
]]

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BodyShape = require(Shared.BodyShape)

local GROUP = "ChilePlayers"

local CharacterService = {}

function CharacterService:Init(services)
	self.Services = services
	pcall(function()
		PhysicsService:RegisterCollisionGroup(GROUP)
	end)
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
end

local function hide(instance: Instance)
	if instance:IsA("BasePart") then
		if instance:GetAttribute("TetOrig") == nil then
			instance:SetAttribute("TetOrig", instance.Transparency)
		end
		instance.Transparency = 1
		instance.CollisionGroup = GROUP
		instance.CastShadow = false
	elseif instance:IsA("Decal") then
		if instance:GetAttribute("TetOrig") == nil then
			instance:SetAttribute("TetOrig", instance.Transparency)
		end
		instance.Transparency = 1
	end
end

function CharacterService:Setup(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.WalkSpeed = Config.Character.BaseWalkSpeed

	for _, descendant in character:GetDescendants() do
		hide(descendant)
	end
	character.DescendantAdded:Connect(hide)
	self:UpdateSpeed(player)
end

function CharacterService:UpdateSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local height = player:GetAttribute("Height")
	local shape = BodyShape.FromHeight(if type(height) == "number" then height else Config.START_HEIGHT)
	local cfg = Config.Character
	local speed = math.clamp(cfg.BaseWalkSpeed + shape.Body * cfg.WalkSpeedPerStud, cfg.BaseWalkSpeed, cfg.MaxWalkSpeed)
	if math.abs(humanoid.WalkSpeed - speed) > 0.5 then
		humanoid.WalkSpeed = speed
	end
end

function CharacterService:Start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			self:Setup(player, character)
		end)
		if player.Character then
			task.spawn(self.Setup, self, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	-- walk speed follows height (1 Hz is plenty)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				self:UpdateSpeed(player)
			end
		end
	end)
end

return CharacterService
