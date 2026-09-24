local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

local CharacterFactory = {}

local function newPart(name, size, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	return part
end

local function attach(base, part, offset)
	part.CFrame = base.CFrame * offset
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = part
	weld.Parent = part
	part.Parent = base.Parent
	return part
end

-- A single-block bunny. The character faces along -Z locally and is turned to face ±X by the client,
-- so the eyes sit on both side faces (the side facing the camera shows).
function CharacterFactory.buildStarterCharacter()
	local size = Config.CHAR_SIZE
	local hip = Config.CHAR_HIP
	local white = Color3.new(1, 1, 1)
	local black = Color3.fromRGB(30, 30, 40)

	local model = Instance.new("Model")
	model.Name = "StarterCharacter"

	local root = newPart("HumanoidRootPart", size, white)
	root.Transparency = 1
	root.CFrame = CFrame.new(0, hip + size.Y / 2, 0)
	root.Parent = model

	local head = attach(root, newPart("Head", size, white), CFrame.new())

	for _, side in { -1, 1 } do
		attach(head, newPart("Eye", Vector3.new(0.1, 0.55, 0.3), black), CFrame.new(side * (size.X / 2 + 0.03), 0.25, -0.45))
		attach(head, newPart("Blush", Vector3.new(0.08, 0.2, 0.35), Color3.fromRGB(255, 150, 170)), CFrame.new(side * (size.X / 2 + 0.02), -0.3, -0.75))
		attach(head, newPart("Ear", Vector3.new(0.45, 1.4, 0.55), white), CFrame.new(side * 0.5, size.Y / 2 + 0.65, 0.35))
	end

	for _, z in { -0.6, 0.6 } do
		attach(root, newPart("Foot", Vector3.new(1.3, hip, 0.75), white), CFrame.new(0, -size.Y / 2 - hip / 2, z))
	end

	local tail = attach(head, newPart("Tail", Vector3.new(0.9, 0.9, 0.9), white), CFrame.new(0, -0.3, size.Z / 2 + 0.2))
	tail.Shape = Enum.PartType.Ball

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hip
	humanoid.AutoRotate = false
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = Config.JUMP_HEIGHT
	humanoid.WalkSpeed = Config.WALK_SPEED
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.AutomaticScalingEnabled = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	model.PrimaryPart = root
	return model
end

function CharacterFactory.decorate(character, color, displayName)
	local feetColor = color:Lerp(Color3.new(0, 0, 0), 0.3)
	for _, part in character:GetChildren() do
		if part.Name == "Head" or part.Name == "Ear" then
			part.Color = color
		elseif part.Name == "Foot" then
			part.Color = feetColor
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.JumpHeight = Config.JUMP_HEIGHT
		humanoid.WalkSpeed = Config.WALK_SPEED
		humanoid.AutoRotate = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	end

	local head = character:FindFirstChild("Head")
	if head then
		local _, tag = UiStyle.worldTag(head, Vector3.new(0, 3.2, 0), displayName, color)
		tag.Name = "NameTag"
		tag.Size = UDim2.fromOffset(130, 30)
		tag.AlwaysOnTop = false
	end
end

return CharacterFactory
