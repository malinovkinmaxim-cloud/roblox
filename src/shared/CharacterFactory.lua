local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Buddies = require(ReplicatedStorage.Shared.Buddies)
local Config = require(ReplicatedStorage.Shared.Config)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

local CharacterFactory = {}

local BLACK = Color3.fromRGB(30, 30, 40)
local WHITE = Color3.new(1, 1, 1)

local function newPart(name, size, color, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	if shape then
		part.Shape = shape
	end
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

-- A single-block buddy. The character faces along -Z locally and is turned to face ±X by the client,
-- so face details sit on both side faces (the side facing the camera shows).
-- Ears, tails and other class details are added per buddy in decorate().
function CharacterFactory.buildStarterCharacter()
	local size = Config.CHAR_SIZE
	local hip = Config.CHAR_HIP

	local model = Instance.new("Model")
	model.Name = "StarterCharacter"

	local root = newPart("HumanoidRootPart", size, WHITE)
	root.Transparency = 1
	root.CFrame = CFrame.new(0, hip + size.Y / 2, 0)
	root.Parent = model

	local head = attach(root, newPart("Head", size, WHITE), CFrame.new())
	for _, side in { -1, 1 } do
		attach(head, newPart("Eye", Vector3.new(0.1, 0.55, 0.3), BLACK), CFrame.new(side * (size.X / 2 + 0.03), 0.25, -0.45))
		attach(head, newPart("Blush", Vector3.new(0.08, 0.2, 0.35), Color3.fromRGB(255, 150, 170)), CFrame.new(side * (size.X / 2 + 0.02), -0.3, -0.75))
	end
	for _, z in { -0.6, 0.6 } do
		attach(root, newPart("Foot", Vector3.new(1.3, hip, 0.75), WHITE), CFrame.new(0, -size.Y / 2 - hip / 2, z))
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hip
	humanoid.AutoRotate = false
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = Config.JUMP_HEIGHT
	humanoid.WalkSpeed = Config.WALK_SPEED
	humanoid.MaxSlopeAngle = Config.MAX_SLOPE
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.AutomaticScalingEnabled = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	model.PrimaryPart = root
	return model
end

local function addClassParts(head, classId, body)
	local half = Config.CHAR_SIZE.X / 2
	local top = Config.CHAR_SIZE.Y / 2
	local sides = { -1, 1 }

	if classId == "bear" then
		for _, side in sides do
			attach(head, newPart("Ear", Vector3.new(0.85, 0.85, 0.85), body, Enum.PartType.Ball), CFrame.new(side * 0.6, top + 0.05, 0.25))
			attach(head, newPart("Muzzle", Vector3.new(0.08, 0.65, 0.8), body:Lerp(WHITE, 0.55)), CFrame.new(side * (half + 0.02), -0.3, -0.6))
			attach(head, newPart("Nose", Vector3.new(0.12, 0.25, 0.25), BLACK), CFrame.new(side * (half + 0.05), -0.15, -0.9))
		end
		attach(head, newPart("Tail", Vector3.new(0.55, 0.55, 0.55), body, Enum.PartType.Ball), CFrame.new(0, -0.45, top + 0.15))
	elseif classId == "frog" then
		for _, part in head.Parent:GetChildren() do
			if part.Name == "Eye" then
				part.Transparency = 1
				part:SetAttribute("Hidden", true)
			end
		end
		for _, side in sides do
			attach(head, newPart("EyeBump", Vector3.new(0.95, 0.95, 0.95), WHITE, Enum.PartType.Ball), CFrame.new(side * 0.55, top + 0.15, -0.45))
			attach(head, newPart("Pupil", Vector3.new(0.45, 0.45, 0.45), BLACK, Enum.PartType.Ball), CFrame.new(side * 0.62, top + 0.22, -0.78))
			attach(head, newPart("Mouth", Vector3.new(0.06, 0.08, 1.1), BLACK), CFrame.new(side * (half + 0.02), -0.4, -0.35))
		end
	elseif classId == "gecko" then
		local accent = body:Lerp(BLACK, 0.3)
		for i, z in { -0.3, 0.2, 0.7 } do
			attach(head, newPart("Crest", Vector3.new(0.3, 0.45 - i * 0.08, 0.3), accent), CFrame.new(0, top + 0.18, z))
		end
		for _, side in sides do
			attach(head, newPart("Spot", Vector3.new(0.06, 0.32, 0.32), accent), CFrame.new(side * (half + 0.02), 0.45, 0.5))
		end
		attach(head, newPart("Tail", Vector3.new(0.55, 0.45, 1.6), body), CFrame.new(0, -0.55, top + 0.7))
		attach(head, newPart("TailTip", Vector3.new(0.35, 0.3, 0.9), body), CFrame.new(0, -0.6, top + 1.9))
	else
		for _, side in sides do
			attach(head, newPart("Ear", Vector3.new(0.45, 1.4, 0.55), body), CFrame.new(side * 0.5, top + 0.65, 0.35))
		end
		attach(head, newPart("Tail", Vector3.new(0.9, 0.9, 0.9), WHITE, Enum.PartType.Ball), CFrame.new(0, -0.3, top + 0.2))
	end
end

-- teamColor identifies the player (feet and name tag); the skin may recolour the body.
function CharacterFactory.decorate(character, teamColor, displayName, classId, skinId)
	local buddy = Buddies.getClass(classId)
	local skin = Buddies.getSkin(skinId)
	local body = skin.color or teamColor
	local feetColor = teamColor:Lerp(BLACK, 0.3)

	for _, part in character:GetChildren() do
		if part.Name == "Head" then
			part.Color = body
			if skin.id == "gold" then
				part.Material = Enum.Material.Neon
			end
		elseif part.Name == "Foot" then
			part.Color = feetColor
		end
	end

	local head = character:FindFirstChild("Head")
	if head then
		addClassParts(head, buddy.id, body)
		local _, tag = UiStyle.worldTag(head, Vector3.new(0, 3.3, 0), `{buddy.emoji} {displayName}`, teamColor)
		tag.Name = "NameTag"
		tag.Size = UDim2.fromOffset(150, 30)
		tag.AlwaysOnTop = false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.JumpHeight = Config.JUMP_HEIGHT
		humanoid.WalkSpeed = Config.WALK_SPEED
		humanoid.MaxSlopeAngle = Config.MAX_SLOPE
		humanoid.AutoRotate = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	end
end

-- Makes a character visible again after it was hidden inside the door
function CharacterFactory.show(character)
	for _, item in character:GetDescendants() do
		if item:IsA("BasePart") then
			if item.Name == "HumanoidRootPart" then
				item.CanCollide = true
				item.Anchored = false
			elseif not item:GetAttribute("Hidden") then
				item.Transparency = 0
			end
		elseif item:IsA("BillboardGui") and item.Name == "NameTag" then
			item.Enabled = true
		end
	end
end

return CharacterFactory
