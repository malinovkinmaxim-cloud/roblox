--[[
	PetBuilder - cute pets built from a handful of primitive parts (no assets needed).

	PetBuilder.Build(petId, parent) -> pet
	  pet.Parts   { { Part, Size (unit), Offset (unit CFrame), Flap = -1|1|nil } }
	  pet:SetScale(s)          resize (only when the scale really changes)
	  pet:Pose(cf, t, push)    place every part relative to cf (push(part, cframe) collects moves)
	  pet:Destroy()
	Shape comes from PetConfig Look: body colours, ears, extras (horn, wings, halo...),
	Tall (stretched body - the Secret pets are tall, of course), Neon, Rainbow, Sparkle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PetConfig = require(ReplicatedStorage:WaitForChild("Shared").PetConfig)

local PetBuilder = {}
PetBuilder.__index = PetBuilder

local BLACK = Color3.fromRGB(25, 20, 30)
local WHITE = Color3.new(1, 1, 1)

local function makePart(parent: Instance, color: Color3, shape: string?, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color
	if shape == "Sphere" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Parent = parent
	return p
end

function PetBuilder.Build(petId: string, parent: Instance)
	local def = PetConfig.Pets[petId] or PetConfig.Pets.Doggy
	local look = def.Look
	local self = setmetatable({
		Id = petId,
		Def = def,
		Parts = {},
		Scale = 0,
		Rainbow = look.Rainbow == true,
	}, PetBuilder)
	local accentMaterial = if look.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic

	local function add(color: Color3, size: Vector3, offset: CFrame, shape: string?, material: Enum.Material?, flap: number?): BasePart
		local part = makePart(parent, color, shape, material)
		table.insert(self.Parts, { Part = part, Size = size, Offset = offset, Flap = flap })
		return part
	end

	local tall = look.Tall == true
	local bodyH = if tall then 1.7 else 1
	local body = add(look.Body, Vector3.new(if tall then 0.8 else 1, bodyH, if tall then 0.8 else 1), CFrame.new(), "Sphere")
	self.Body = body
	local top = bodyH / 2
	local faceY = if tall then top - 0.35 else 0.12
	local front = if tall then -0.36 else -0.45

	-- eyes (+ shine)
	for _, side in { -1, 1 } do
		add(BLACK, Vector3.one * 0.17, CFrame.new(side * 0.19, faceY, front), "Sphere")
		add(WHITE, Vector3.one * 0.06, CFrame.new(side * 0.16, faceY + 0.05, front - 0.07), "Sphere", Enum.Material.Neon)
	end
	-- feet
	for _, side in { -1, 1 } do
		add(look.Body:Lerp(BLACK, 0.25), Vector3.new(0.26, 0.18, 0.3), CFrame.new(side * 0.22, -bodyH / 2 + 0.05, -0.1), "Sphere")
	end
	if look.Snout then
		add(look.Accent, Vector3.new(0.3, 0.22, 0.2), CFrame.new(0, faceY - 0.15, front - 0.04), "Sphere")
	end

	local ears = look.Ears or "None"
	for _, side in { -1, 1 } do
		if ears == "Pointy" then
			add(look.Accent, Vector3.new(0.3, 0.3, 0.1), CFrame.new(side * 0.27, top - 0.02, 0) * CFrame.Angles(0, 0, math.rad(45)), nil, accentMaterial)
		elseif ears == "Floppy" then
			add(look.Accent, Vector3.new(0.14, 0.42, 0.3), CFrame.new(side * 0.5, faceY, 0) * CFrame.Angles(0, 0, side * 0.35))
		elseif ears == "Long" then
			add(look.Body, Vector3.new(0.15, 0.72, 0.14), CFrame.new(side * 0.18, top + 0.3, 0) * CFrame.Angles(0, 0, side * -0.12))
			add(look.Accent, Vector3.new(0.07, 0.5, 0.15), CFrame.new(side * 0.18, top + 0.3, -0.01) * CFrame.Angles(0, 0, side * -0.12))
		elseif ears == "Round" then
			add(look.Accent, Vector3.one * 0.3, CFrame.new(side * 0.32, top - 0.08, 0), "Sphere")
		end
	end

	local extra = look.Extra
	if extra == "Beak" then
		add(look.Accent, Vector3.new(0.24, 0.12, 0.24), CFrame.new(0, faceY - 0.12, front - 0.06))
	elseif extra == "Horn" then
		add(look.Accent, Vector3.new(0.09, 0.45, 0.09), CFrame.new(0, top + 0.15, -0.22) * CFrame.Angles(-0.4, 0, 0), nil, Enum.Material.Neon)
	elseif extra == "Wings" then
		for _, side in { -1, 1 } do
			add(look.Accent, Vector3.new(0.06, 0.48, 0.62), CFrame.new(side * 0.56, 0.12, 0.12), nil, accentMaterial, side)
		end
	elseif extra == "Halo" then
		local halo = add(look.Accent, Vector3.new(0.05, 0.62, 0.62), CFrame.new(0, top + 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)), "Cylinder", Enum.Material.Neon)
		halo.Transparency = 0.25
	elseif extra == "Antenna" then
		add(BLACK, Vector3.new(0.05, 0.36, 0.05), CFrame.new(0, top + 0.16, 0))
		add(look.Accent, Vector3.one * 0.15, CFrame.new(0, top + 0.36, 0), "Sphere", Enum.Material.Neon)
	elseif extra == "Ring" then
		local ring = add(look.Accent, Vector3.new(0.04, 1.9, 1.9), CFrame.Angles(0.4, 0, math.rad(90)), "Cylinder", Enum.Material.Neon)
		ring.Transparency = 0.35
	end

	if look.Sparkle then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(look.Accent)
		sparkle.LightEmission = 1
		sparkle.Rate = 5
		sparkle.Lifetime = NumberRange.new(0.6, 1)
		sparkle.Speed = NumberRange.new(0.5, 1.5)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Parent = body
		self.Sparkle = sparkle
	end
	local rarity = PetConfig.Rarities[def.Rarity]
	if rarity and rarity.Order >= PetConfig.Rarities.Legendary.Order then
		local light = Instance.new("PointLight")
		light.Color = if def.Rarity == "Secret" then look.Accent else rarity.Color
		light.Brightness = 1.5
		light.Range = 6
		light.Shadows = false
		light.Parent = body
		self.Light = light
	end
	return self
end

function PetBuilder:SetScale(s: number)
	if math.abs(s - self.Scale) <= self.Scale * 0.05 then
		return
	end
	self.Scale = s
	for _, entry in self.Parts do
		entry.Part.Size = entry.Size * s
	end
	if self.Sparkle then
		self.Sparkle.Size = NumberSequence.new(0.25 * s, 0)
	end
	if self.Light then
		self.Light.Range = math.clamp(6 * s, 4, 40)
	end
end

-- Places the pet at cf (pet centre). t = time for wing flaps / rainbow.
function PetBuilder:Pose(cf: CFrame, t: number, push: (BasePart, CFrame) -> ())
	local s = self.Scale
	for _, entry in self.Parts do
		local offset = entry.Offset
		if entry.Flap then
			offset = offset * CFrame.Angles(0, 0, entry.Flap * math.sin(t * 12) * 0.5)
		end
		push(entry.Part, cf * CFrame.new(offset.Position * s) * offset.Rotation)
	end
	if self.Rainbow then
		self.Body.Color = Color3.fromHSV((t * 0.25) % 1, 0.55, 1)
	end
end

function PetBuilder:Destroy()
	for _, entry in self.Parts do
		entry.Part:Destroy()
	end
	table.clear(self.Parts)
end

return PetBuilder
