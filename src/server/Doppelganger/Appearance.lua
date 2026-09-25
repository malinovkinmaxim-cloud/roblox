--[[
	Appearance
	Builds the doppelgänger rig so that it reads as "that's ME":
	  1. HumanoidDescription of the player's current character (GetAppliedDescription)
	  2. HumanoidDescription from the user id (GetHumanoidDescriptionFromUserId)
	  3. default avatar
	  4. hand-built block figure (last resort, never fails)
	Rigs are cached per player (template) and cloned for every run.

	Also adds the subtle "this is the double" visuals: outline highlight, faint aura, name tag.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Appearance = {}

local templates: { [number]: Model } = {}
local building: { [number]: boolean } = {}

local cacheFolder = Instance.new("Folder")
cacheFolder.Name = "DoppelTemplates"
cacheFolder.Parent = ServerStorage

local function stripScripts(model: Instance)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("ForceField") then
			descendant:Destroy()
		end
	end
end

function Appearance.GetDescription(player: Player): HumanoidDescription?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local ok, description = pcall(function()
			return humanoid:GetAppliedDescription()
		end)
		if ok and description then
			return description
		end
	end
	if player.UserId > 0 then
		local ok, description = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(player.UserId)
		end)
		if ok and description then
			return description
		end
	end
	return nil
end

-- Minimal rig used when Roblox avatar services are unavailable.
function Appearance.BuildBlockRig(): Model
	local model = Instance.new("Model")
	model.Name = "Doppelganger"
	local function block(name: string, size: Vector3, offset: Vector3, color: Color3)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CFrame = CFrame.new(offset)
		part.Parent = model
		return part
	end
	local root = block("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), Color3.new(1, 1, 1))
	root.Transparency = 1
	local torso = block("UpperTorso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), Color3.fromRGB(60, 120, 220))
	local head = block("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0), Color3.fromRGB(245, 205, 150))
	local leftArm = block("LeftUpperArm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0), Color3.fromRGB(245, 205, 150))
	local rightArm = block("RightUpperArm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0), Color3.fromRGB(245, 205, 150))
	local leftLeg = block("LeftUpperLeg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0), Color3.fromRGB(40, 50, 70))
	local rightLeg = block("RightUpperLeg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0), Color3.fromRGB(40, 50, 70))
	for _, part in { torso, head, leftArm, rightArm, leftLeg, rightLeg } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 2
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

function Appearance.BuildTemplate(player: Player): Model
	local model: Model? = nil
	local description = Appearance.GetDescription(player)
	if description then
		local ok, result = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
		if ok and result then
			model = result
		else
			warn("[Appearance] CreateHumanoidModelFromDescription failed for " .. player.Name .. ": " .. tostring(result))
		end
	end
	if not model then
		local ok, result = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
		if ok and result then
			model = result
		end
	end
	if not model then
		model = Appearance.BuildBlockRig()
	end
	local rig = model :: Model
	stripScripts(rig)
	rig.Name = "Doppelganger"
	rig.Archivable = true
	return rig
end

-- Returns a fresh clone of the player's doppelgänger rig. May yield the first time.
function Appearance.GetModel(player: Player): Model
	local userId = player.UserId
	local waited = 0
	while building[userId] and waited < 8 do
		waited += task.wait(0.1)
	end
	local template = templates[userId]
	if not template then
		building[userId] = true
		local ok, result = pcall(Appearance.BuildTemplate, player)
		building[userId] = nil
		if ok then
			template = result
		else
			warn("[Appearance] template failed: " .. tostring(result))
			template = Appearance.BuildBlockRig()
		end
		(template :: Model).Parent = cacheFolder
		templates[userId] = template
	end
	return (template :: Model):Clone()
end

function Appearance.Prewarm(player: Player)
	if templates[player.UserId] or building[player.UserId] then
		return
	end
	task.spawn(function()
		local model = Appearance.GetModel(player)
		model:Destroy()
	end)
end

function Appearance.Forget(player: Player)
	local template = templates[player.UserId]
	if template then
		template:Destroy()
		templates[player.UserId] = nil
	end
end

--[[
	Subtle double visuals. Returns { Highlight, Billboard, NameLabel, RoleLabel, Aura }
]]
function Appearance.AddVisuals(model: Model, color: Color3)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local head = (model:FindFirstChild("Head") or root) :: BasePart

	local highlight = Instance.new("Highlight")
	highlight.Name = "DoppelHighlight"
	highlight.Adornee = model
	highlight.FillColor = color
	highlight.FillTransparency = 0.82
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0.25
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DoppelTag"
	billboard.Adornee = head
	billboard.Size = UDim2.new(7, 0, 1.6, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	billboard.MaxDistance = 110
	billboard.LightInfluence = 0
	billboard.Parent = model

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.fromScale(1, 0.58)
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text = "DOPPELGÄNGER"
	nameLabel.Parent = billboard

	local roleLabel = Instance.new("TextLabel")
	roleLabel.Name = "Role"
	roleLabel.BackgroundTransparency = 1
	roleLabel.Position = UDim2.fromScale(0, 0.58)
	roleLabel.Size = UDim2.fromScale(1, 0.42)
	roleLabel.Font = Enum.Font.GothamBold
	roleLabel.TextScaled = true
	roleLabel.TextColor3 = color
	roleLabel.TextStrokeTransparency = 0.4
	roleLabel.Text = "???"
	roleLabel.Parent = billboard

	local aura: ParticleEmitter? = nil
	if Config.DOPPEL_AURA then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Aura"
		emitter.Color = ColorSequence.new(color)
		emitter.LightEmission = 0.7
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		emitter.Lifetime = NumberRange.new(0.8, 1.2)
		emitter.Speed = NumberRange.new(0.5, 1.4)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rate = 6
		emitter.LockedToPart = false
		emitter.Parent = root
		aura = emitter
	end

	return {
		Highlight = highlight,
		Billboard = billboard,
		NameLabel = nameLabel,
		RoleLabel = roleLabel,
		Aura = aura,
	}
end

return Appearance
