--[[
	Skins
	Cosmetic recipes for the doppelgänger (see Shared.CosmeticsConfig).
	Only simple recolours, materials and a few welded Parts - no custom models, no gameplay effect.
]]

local Skins = {}

local BODY = {
	Head = "Head",
	UpperTorso = "Torso",
	LowerTorso = "Torso",
	Torso = "Torso",
	LeftUpperArm = "Arms",
	LeftLowerArm = "Arms",
	LeftHand = "Arms",
	RightUpperArm = "Arms",
	RightLowerArm = "Arms",
	RightHand = "Arms",
	["Left Arm"] = "Arms",
	["Right Arm"] = "Arms",
	LeftUpperLeg = "Legs",
	LeftLowerLeg = "Legs",
	LeftFoot = "Legs",
	RightUpperLeg = "Legs",
	RightLowerLeg = "Legs",
	RightFoot = "Legs",
	["Left Leg"] = "Legs",
	["Right Leg"] = "Legs",
}

local function removeClothes(model: Model)
	for _, child in model:GetChildren() do
		if child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
			child:Destroy()
		end
	end
end

local function removeAccessories(model: Model)
	for _, child in model:GetChildren() do
		if child:IsA("Accessory") then
			child:Destroy()
		end
	end
end

local function removeFace(model: Model)
	local head = model:FindFirstChild("Head")
	if head then
		for _, child in head:GetChildren() do
			if child:IsA("Decal") then
				child:Destroy()
			end
		end
	end
end

local function clearTexture(part: BasePart)
	if part:IsA("MeshPart") then
		pcall(function()
			(part :: MeshPart).TextureID = ""
		end)
	end
end

local function paintBody(model: Model, colors: { [string]: Color3 }, material: Enum.Material?)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and BODY[part.Name] then
			local color = colors[BODY[part.Name]] or colors.All
			if color then
				clearTexture(part)
				part.Color = color
			end
			if material then
				part.Material = material
			end
		end
	end
end

local function paintAccessories(model: Model, color: Color3, material: Enum.Material?)
	for _, accessory in model:GetChildren() do
		if accessory:IsA("Accessory") then
			for _, part in accessory:GetDescendants() do
				if part:IsA("BasePart") then
					clearTexture(part)
					part.Color = color
					if material then
						part.Material = material
					end
				end
			end
		end
	end
end

-- Attach a simple part to the head in head-local space.
local function addHeadPart(model: Model, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, wedge: boolean?)
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return nil
	end
	local part: BasePart
	if wedge then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if shape then
			p.Shape = shape
		end
		part = p
	end
	part.Name = "SkinPart"
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = head.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
	return part
end

local function headSize(model: Model): Vector3
	local head = model:FindFirstChild("Head") :: BasePart?
	return if head then head.Size else Vector3.new(1.2, 1.2, 1.2)
end

Skins.Recipes = {
	Default = function(_model: Model) end,

	Noob = function(model: Model)
		removeClothes(model)
		removeAccessories(model)
		local yellow = Color3.fromRGB(245, 205, 48)
		paintBody(model, {
			Head = yellow,
			Arms = yellow,
			Torso = Color3.fromRGB(13, 105, 172),
			Legs = Color3.fromRGB(75, 151, 75),
		})
	end,

	SadCat = function(model: Model)
		removeClothes(model)
		removeAccessories(model)
		local grey = Color3.fromRGB(160, 165, 175)
		paintBody(model, { All = grey })
		local size = headSize(model)
		for _, side in { -1, 1 } do
			addHeadPart(model, Vector3.new(0.25, 0.55, 0.4), CFrame.new(side * size.X * 0.3, size.Y * 0.62, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(130, 135, 145), nil, nil, true)
		end
	end,

	Dog = function(model: Model)
		removeClothes(model)
		removeAccessories(model)
		local brown = Color3.fromRGB(170, 115, 70)
		paintBody(model, { All = brown })
		local size = headSize(model)
		for _, side in { -1, 1 } do
			addHeadPart(model, Vector3.new(0.2, 0.8, 0.5), CFrame.new(side * (size.X / 2 + 0.1), 0.05, 0), Color3.fromRGB(100, 65, 40))
		end
		addHeadPart(model, Vector3.new(0.6, 0.4, 0.35), CFrame.new(0, -size.Y * 0.18, -size.Z / 2 - 0.12), Color3.fromRGB(215, 175, 130))
		addHeadPart(model, Vector3.new(0.22, 0.18, 0.1), CFrame.new(0, -size.Y * 0.08, -size.Z / 2 - 0.3), Color3.fromRGB(30, 25, 25))
	end,

	Robot = function(model: Model)
		removeClothes(model)
		removeAccessories(model)
		removeFace(model)
		paintBody(model, { All = Color3.fromRGB(150, 160, 175) }, Enum.Material.DiamondPlate)
		local size = headSize(model)
		addHeadPart(model, Vector3.new(0.12, 0.8, 0.12), CFrame.new(0, size.Y / 2 + 0.4, 0), Color3.fromRGB(80, 85, 95), Enum.Material.Metal)
		addHeadPart(model, Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, size.Y / 2 + 0.85, 0), Color3.fromRGB(255, 70, 70), Enum.Material.Neon, Enum.PartType.Ball)
		for _, side in { -1, 1 } do
			addHeadPart(model, Vector3.new(0.3, 0.15, 0.05), CFrame.new(side * size.X * 0.2, size.Y * 0.08, -size.Z / 2 - 0.02), Color3.fromRGB(80, 230, 255), Enum.Material.Neon)
		end
	end,

	Glitch = function(model: Model)
		removeClothes(model)
		local pink = Color3.fromRGB(255, 60, 200)
		local cyan = Color3.fromRGB(60, 230, 255)
		local toggle = false
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and BODY[part.Name] then
				toggle = not toggle
				clearTexture(part)
				part.Color = if toggle then pink else cyan
				part.Material = Enum.Material.ForceField
			end
		end
		paintAccessories(model, pink, Enum.Material.ForceField)
	end,

	Shadow = function(model: Model)
		removeClothes(model)
		removeAccessories(model)
		removeFace(model)
		paintBody(model, { All = Color3.fromRGB(28, 28, 36) })
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and BODY[part.Name] then
				part.Transparency = 0.12
			end
		end
		local size = headSize(model)
		for _, side in { -1, 1 } do
			addHeadPart(model, Vector3.new(0.22, 0.12, 0.05), CFrame.new(side * size.X * 0.2, size.Y * 0.08, -size.Z / 2 - 0.02), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
		end
	end,

	Alien = function(model: Model)
		removeClothes(model)
		removeAccessories(model)
		removeFace(model)
		paintBody(model, { All = Color3.fromRGB(110, 210, 90) })
		local size = headSize(model)
		for _, side in { -1, 1 } do
			addHeadPart(model, Vector3.new(0.45, 0.3, 0.12), CFrame.new(side * size.X * 0.22, size.Y * 0.05, -size.Z / 2 - 0.02) * CFrame.Angles(0, 0, math.rad(side * -20)), Color3.fromRGB(15, 15, 20), Enum.Material.Glass, Enum.PartType.Ball)
		end
	end,

	Golden = function(model: Model)
		removeClothes(model)
		local gold = Color3.fromRGB(255, 200, 60)
		paintBody(model, { All = gold }, Enum.Material.Foil)
		paintAccessories(model, gold, Enum.Material.Foil)
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and BODY[part.Name] then
				part.Reflectance = 0.25
			end
		end
	end,
}

function Skins.Apply(model: Model, skinId: string?)
	local recipe = Skins.Recipes[skinId or "Default"]
	if not recipe then
		return
	end
	local ok, err = pcall(recipe, model)
	if not ok then
		warn("[Skins] failed to apply " .. tostring(skinId) .. ": " .. tostring(err))
	end
end

return Skins
