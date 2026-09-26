--[[
	BodyController - THE core visual of the game.

	Every client draws a stretched body for EVERY player on top of their invisible physical
	rig (see server CharacterService). Nothing here is replicated: it costs the server and the
	network nothing - clients only read the replicated "Height" attribute.

	  * shape from shared/BodyShape: height stretches the body UP and makes it THINNER,
	    0.01 m = flat cutlet, 10 m = normal, 1B m = absurd pole with a tiny head
	  * the head is a clone of the player's real head (face + hats + hair), so you still
	    recognise your avatar; shirt/pants colours come from the player's UserId
	  * growth is smoothed in log space, so every tap visibly stretches the body
	  * squash & stretch: each tap squashes the body down, then a spring shoots it up with an
	    overshoot and it settles (stronger taps = stronger jiggle)
	  * procedural walk: long legs take long, slow steps; arms swing; idle breathing
	  * trails and auras are rendered here as well (scaled to the body)
	  * one RenderStepped loop, one workspace:BulkMoveTo call for all parts, far bodies update
	    at a lower rate, Size writes only when a size really changes
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BodyShape = require(Shared.BodyShape)
local Config = require(Shared.Config)
local CosmeticConfig = require(Shared.CosmeticConfig)
local EventConfig = require(Shared.EventConfig)
local Signal = require(Shared.Util.Signal)

local LocalPlayer = Players.LocalPlayer

local BodyController = {}
BodyController.Bodies = {} :: { [Player]: any }
BodyController.BodyAdded = Signal.new()
BodyController.BodyRemoving = Signal.new()
BodyController.VisualScale = 1
BodyController.LocalPending = 0 -- predicted growth (cm) not yet confirmed by the server

local SHIRTS = {
	Color3.fromRGB(235, 70, 70),
	Color3.fromRGB(60, 140, 240),
	Color3.fromRGB(70, 200, 90),
	Color3.fromRGB(255, 150, 40),
	Color3.fromRGB(165, 90, 235),
	Color3.fromRGB(255, 95, 175),
	Color3.fromRGB(255, 210, 50),
	Color3.fromRGB(40, 200, 200),
}
local PANTS = {
	Color3.fromRGB(40, 55, 110),
	Color3.fromRGB(55, 55, 65),
	Color3.fromRGB(35, 90, 60),
	Color3.fromRGB(95, 65, 45),
	Color3.fromRGB(30, 30, 35),
	Color3.fromRGB(70, 60, 130),
}
local SHOES = Color3.fromRGB(30, 30, 38)
local DEFAULT_SKIN = Color3.fromRGB(245, 205, 48)

-- spring for squash & stretch
local SPRING_W = 21 -- angular frequency
local SPRING_Z = 0.32 -- damping ratio

local TEXTURES = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
}

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function newPart(name: string, color: Color3, parent: Instance, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = color
	p.Size = Vector3.one
	p.Parent = parent
	return p
end

local function setSize(part: BasePart, size: Vector3)
	local current = part.Size
	if math.abs(current.X - size.X) > current.X * 0.004 + 0.001
		or math.abs(current.Y - size.Y) > current.Y * 0.004 + 0.001
		or math.abs(current.Z - size.Z) > current.Z * 0.004 + 0.001
	then
		part.Size = size
	end
end

local function colorSequence(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(keys)
end

local function stripClone(instance: Instance)
	for _, d in instance:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("LuaSourceContainer") or d:IsA("TouchTransmitter") then
			d:Destroy()
		end
	end
end

local function restoreLook(instance: Instance)
	for _, d in instance:GetDescendants() do
		if d:IsA("Decal") then
			local orig = d:GetAttribute("TetOrig")
			d.Transparency = if type(orig) == "number" then orig else 0
		end
	end
	if instance:IsA("BasePart") then
		local orig = instance:GetAttribute("TetOrig")
		instance.Transparency = if type(orig) == "number" then orig else 0
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanQuery = false
		instance.CanTouch = false
		instance.Massless = true
		instance.CastShadow = true
	end
end

-- all body parts of all players are moved with ONE BulkMoveTo per frame
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function push(part: BasePart, cf: CFrame)
	table.insert(moveParts, part)
	table.insert(moveCFrames, cf)
end

local function flushMoves()
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	table.clear(moveParts)
	table.clear(moveCFrames)
end

---------------------------------------------------------------------------
-- Body
---------------------------------------------------------------------------
local function heightOf(player: Player): number
	local h = player:GetAttribute("Height")
	if type(h) == "number" and h == h and h > 0 then
		return h
	end
	return Config.START_HEIGHT
end

function BodyController:BuildHead(body)
	-- clean previous head
	if body.Head then
		body.Head.Part:Destroy()
		for _, acc in body.Head.Accessories do
			acc.Part:Destroy()
		end
	end
	local character = body.Character
	local realHead = character:FindFirstChild("Head")
	local head
	if realHead and realHead:IsA("BasePart") then
		local ok, clone = pcall(function()
			return realHead:Clone()
		end)
		if ok and clone then
			stripClone(clone)
			restoreLook(clone)
			clone.Name = "Head"
			head = clone
		end
	end
	if not head then
		local fallback = newPart("Head", body.Skin, body.Folder)
		fallback.Size = Vector3.new(1.2, 1.2, 1.2)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Head
		mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
		mesh.Parent = fallback
		local face = Instance.new("Decal")
		face.Name = "face"
		face.Texture = "rbxasset://textures/face.png"
		face.Face = Enum.NormalId.Front
		face.Parent = fallback
		head = fallback
	end
	head.Parent = body.Folder

	local info = {
		Part = head,
		BaseSize = head.Size,
		Mesh = head:FindFirstChildOfClass("SpecialMesh"),
		Accessories = {},
		K = 0,
	}
	info.MeshScale = info.Mesh and info.Mesh.Scale or nil

	-- hats / hair / face accessories that attach to the head
	if realHead and realHead:IsA("BasePart") then
		for _, accessory in character:GetChildren() do
			if not accessory:IsA("Accessory") then
				continue
			end
			local handle = accessory:FindFirstChild("Handle")
			if not handle or not handle:IsA("BasePart") or handle:FindFirstChildOfClass("WrapLayer") then
				continue
			end
			local handleAttachment = handle:FindFirstChildOfClass("Attachment")
			local headAttachment = handleAttachment and realHead:FindFirstChild(handleAttachment.Name)
			if not handleAttachment or not headAttachment or not headAttachment:IsA("Attachment") then
				continue
			end
			local ok, clone = pcall(function()
				return handle:Clone()
			end)
			if ok and clone then
				stripClone(clone)
				restoreLook(clone)
				clone.Parent = body.Folder
				local mesh = clone:FindFirstChildOfClass("SpecialMesh")
				table.insert(info.Accessories, {
					Part = clone,
					BaseSize = clone.Size,
					Offset = headAttachment.CFrame * handleAttachment.CFrame:Inverse(),
					Mesh = mesh,
					MeshScale = mesh and mesh.Scale or nil,
					MeshOffset = mesh and mesh.Offset or nil,
				})
			end
		end
	end
	body.Head = info
end

function BodyController:ApplyColors(body)
	local colors = body.Character:FindFirstChildOfClass("BodyColors")
	body.Skin = if colors then colors.HeadColor3 else DEFAULT_SKIN
	local id = math.abs(body.Player.UserId)
	body.Shirt = SHIRTS[id % #SHIRTS + 1]
	body.Pants = PANTS[(id // 7) % #PANTS + 1]
	local p = body.Parts
	if p then
		p.Torso.Color = body.Shirt
		p.ArmUL.Color = body.Shirt
		p.ArmUR.Color = body.Shirt
		p.ArmLL.Color = body.Skin
		p.ArmLR.Color = body.Skin
		p.LegL.Color = body.Pants
		p.LegR.Color = body.Pants
	end
end

function BodyController:CreateBody(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not root or not humanoid or not root:IsA("BasePart") or not humanoid:IsA("Humanoid") then
		return
	end
	character:WaitForChild("Head", 5)
	if self.Bodies[player] then
		self:RemoveBody(player)
	end

	local folder = Instance.new("Model")
	folder.Name = "Body_" .. player.Name
	folder.Parent = self.Folder

	local body: any = {
		Player = player,
		Character = character,
		Root = root,
		Humanoid = humanoid,
		Folder = folder,
		LogH = math.log10(heightOf(player)),
		LastHeight = heightOf(player),
		SpringX = 0,
		SpringV = 0,
		Phase = 0,
		Time = math.random() * 10,
		Skip = 0,
		IsLocal = player == LocalPlayer,
		Connections = {},
	}
	self:ApplyColors(body)
	body.Parts = {
		Torso = newPart("Torso", body.Shirt, folder),
		LegL = newPart("LegL", body.Pants, folder),
		LegR = newPart("LegR", body.Pants, folder),
		ShoeL = newPart("ShoeL", SHOES, folder),
		ShoeR = newPart("ShoeR", SHOES, folder),
		ArmUL = newPart("ArmUL", body.Shirt, folder),
		ArmUR = newPart("ArmUR", body.Shirt, folder),
		ArmLL = newPart("ArmLL", body.Skin, folder),
		ArmLR = newPart("ArmLR", body.Skin, folder),
	}
	self:BuildHead(body)

	-- appearance loads asynchronously: rebuild the head when accessories / colours arrive
	local rebuildQueued = false
	local function queueRebuild()
		if rebuildQueued then
			return
		end
		rebuildQueued = true
		task.delay(0.4, function()
			rebuildQueued = false
			if self.Bodies[player] == body then
				self:ApplyColors(body)
				self:BuildHead(body)
				self:ApplyCosmetics(body)
				self:UpdateBody(body, 1 / 60, true)
				flushMoves()
				self.BodyAdded:Fire(body) -- tags re-attach to the new head
			end
		end)
	end
	table.insert(body.Connections, character.ChildAdded:Connect(function(child)
		if child:IsA("Accessory") or child:IsA("BodyColors") or child.Name == "Head" then
			queueRebuild()
		end
	end))
	table.insert(body.Connections, player:GetAttributeChangedSignal("Trail"):Connect(function()
		self:ApplyCosmetics(body)
	end))
	table.insert(body.Connections, player:GetAttributeChangedSignal("Aura"):Connect(function()
		self:ApplyCosmetics(body)
	end))
	table.insert(body.Connections, player:GetAttributeChangedSignal("Height"):Connect(function()
		local h = heightOf(player)
		if body.IsLocal then
			self.LocalPending = math.max(0, self.LocalPending - math.max(0, h - body.LastHeight))
		elseif h > body.LastHeight then
			-- other players visibly jiggle when they grow
			self:Kick(player, 0.6)
		end
		body.LastHeight = h
	end))

	self.Bodies[player] = body
	self:ApplyCosmetics(body)
	self:UpdateBody(body, 1 / 60, true)
	flushMoves()
	self.BodyAdded:Fire(body)
end

function BodyController:RemoveBody(player: Player)
	local body = self.Bodies[player]
	if not body then
		return
	end
	self.Bodies[player] = nil
	self.BodyRemoving:Fire(body)
	for _, c in body.Connections do
		c:Disconnect()
	end
	body.Folder:Destroy()
end

function BodyController:GetBody(player: Player)
	return self.Bodies[player]
end

-- Squash & stretch impulse. strength ~0.5 (small tap) .. 2 (huge). Negative = flatten.
function BodyController:Kick(player: Player, strength: number)
	local body = self.Bodies[player]
	if not body then
		return
	end
	if strength >= 0 then
		-- squash down first, then the spring shoots it up with an overshoot
		body.SpringX = math.min(body.SpringX, 0) - 0.1 * strength
		body.SpringV += 2.6 * strength
	else
		body.SpringX = 0.25 * strength
		body.SpringV = 0
	end
	body.SpringX = math.clamp(body.SpringX, -0.6, 0.6)
	body.SpringV = math.clamp(body.SpringV, -8, 9)
end

---------------------------------------------------------------------------
-- Cosmetics (trail + aura), all local
---------------------------------------------------------------------------
function BodyController:ShowFx(body): boolean
	if body.IsLocal then
		return true
	end
	return self.Controllers.ClientData:Setting("OthersFx")
end

function BodyController:ApplyCosmetics(body)
	local fx = body.Fx
	if fx then
		for _, instance in fx.Instances do
			instance:Destroy()
		end
	end
	fx = { Instances = {}, Orbiters = {}, HaloOrbs = {} }
	body.Fx = fx
	if not self:ShowFx(body) then
		return
	end
	local low = self.Controllers.ClientData:Setting("LowGraphics")
	local torso = body.Parts.Torso

	local trailId = body.Player:GetAttribute("Trail")
	local trailDef = type(trailId) == "string" and CosmeticConfig.Trails[trailId] or nil
	if trailDef then
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailTop"
		a0.Parent = torso
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailBottom"
		a1.Parent = torso
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = colorSequence(trailDef.Colors)
		trail.Transparency = NumberSequence.new(trailDef.Transparency[1], trailDef.Transparency[2])
		trail.Lifetime = trailDef.Lifetime
		trail.LightEmission = trailDef.LightEmission
		trail.FaceCamera = true
		trail.MinLength = 0.05
		trail.WidthScale = NumberSequence.new(1, 0.4)
		trail.Parent = torso
		fx.Trail = trail
		fx.TrailDef = trailDef
		fx.TrailTop, fx.TrailBottom = a0, a1
		table.insert(fx.Instances, a0)
		table.insert(fx.Instances, a1)
		table.insert(fx.Instances, trail)
		if trailDef.Sparkle and not low then
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Texture = TEXTURES.Sparkle
			sparkle.Color = ColorSequence.new(trailDef.Sparkle)
			sparkle.LightEmission = 1
			sparkle.Rate = 8
			sparkle.Lifetime = NumberRange.new(0.6, 1.2)
			sparkle.Speed = NumberRange.new(0.5, 2)
			sparkle.SpreadAngle = Vector2.new(180, 180)
			sparkle.Parent = torso
			fx.Sparkle = sparkle
			table.insert(fx.Instances, sparkle)
		end
	end

	local auraId = body.Player:GetAttribute("Aura")
	local auraDef = type(auraId) == "string" and CosmeticConfig.Auras[auraId] or nil
	if auraDef then
		local box = newPart("AuraBox", Color3.new(1, 1, 1), body.Folder)
		box.Transparency = 1
		box.CastShadow = false
		fx.AuraBox = box
		fx.AuraDef = auraDef
		table.insert(fx.Instances, box)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = TEXTURES[auraDef.Texture] or TEXTURES.Sparkle
		emitter.Color = colorSequence(auraDef.Colors)
		emitter.LightEmission = if auraDef.Texture == "Smoke" then 0.2 else 1
		emitter.Rate = auraDef.Rate * (if low then 0.3 else 1)
		emitter.Lifetime = NumberRange.new(0.8, 1.6)
		emitter.Speed = NumberRange.new(auraDef.Speed * 0.5, auraDef.Speed)
		emitter.SpreadAngle = Vector2.new(25, 25)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Parent = box
		fx.Emitter = emitter
		if auraDef.Light then
			local light = Instance.new("PointLight")
			light.Color = auraDef.Light
			light.Brightness = 2
			light.Shadows = false
			light.Parent = box
			fx.Light = light
		end
		if auraDef.Ring then
			local ring = newPart("AuraRing", auraDef.Colors[1], body.Folder, Enum.Material.Neon)
			ring.Shape = Enum.PartType.Cylinder
			ring.Transparency = 0.45
			ring.CastShadow = false
			fx.Ring = ring
			table.insert(fx.Instances, ring)
		end
		if auraDef.Beam then
			local beam = newPart("AuraBeam", auraDef.Colors[#auraDef.Colors], body.Folder, Enum.Material.Neon)
			beam.Shape = Enum.PartType.Cylinder
			beam.Transparency = 0.85
			beam.CastShadow = false
			fx.Beam = beam
			table.insert(fx.Instances, beam)
		end
		if auraDef.Orbiters and not low then
			for i = 1, auraDef.Orbiters do
				local orb = newPart("Orb", auraDef.Colors[(i - 1) % #auraDef.Colors + 1], body.Folder, Enum.Material.Neon)
				orb.Shape = Enum.PartType.Ball
				orb.CastShadow = false
				table.insert(fx.Orbiters, orb)
				table.insert(fx.Instances, orb)
			end
		end
		if auraDef.Halo then
			for _ = 1, 8 do
				local orb = newPart("Halo", auraDef.Colors[1], body.Folder, Enum.Material.Neon)
				orb.Shape = Enum.PartType.Ball
				orb.CastShadow = false
				table.insert(fx.HaloOrbs, orb)
				table.insert(fx.Instances, orb)
			end
		end
	end
	body.FxScale = nil
end

---------------------------------------------------------------------------
-- Per frame
---------------------------------------------------------------------------
function BodyController:UpdateBody(body, dt: number, force: boolean?)
	local root = body.Root
	local humanoid = body.Humanoid
	body.Time += dt

	-- height: smoothed in log space so growth is always visible, rebirth shrinks smoothly
	local height = heightOf(body.Player)
	if body.IsLocal then
		height += self.LocalPending
	end
	local targetLog = math.log10(math.max(height, 0.01))
	local rate = if targetLog < body.LogH - 1 then 5 else 9
	body.LogH += (targetLog - body.LogH) * (1 - math.exp(-dt * rate))
	if math.abs(targetLog - body.LogH) < 1e-4 then
		body.LogH = targetLog -- land exactly, so the HUD number ends on the real value
	end

	-- squash & stretch spring (semi-implicit Euler, substepped for low frame rates)
	local steps = math.clamp(math.ceil(dt / (1 / 120)), 1, 8)
	local h = dt / steps
	for _ = 1, steps do
		local accel = -SPRING_W * SPRING_W * body.SpringX - 2 * SPRING_Z * SPRING_W * body.SpringV
		body.SpringV += accel * h
		body.SpringX += body.SpringV * h
	end
	local stretch = 1 + math.clamp(body.SpringX, -0.45, 0.6)

	-- idle breathing
	stretch *= 1 + math.sin(body.Time * 2.4) * 0.012

	local B, A, H, legShare = BodyShape.Sample(body.LogH - 2)
	local shape = BodyShape.Build(B, A, H, legShare, stretch, self.VisualScale)
	body.Shape = shape

	-- where are the feet? (R15 hip height; R6 has HipHeight 0 and 2-stud legs)
	local rootCF = root.CFrame
	local hip = humanoid.HipHeight + root.Size.Y / 2
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		hip = 3
	end
	local look = rootCF.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local feet = rootCF.Position - Vector3.new(0, hip, 0)

	-- walk cycle: long legs = long slow steps
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local stride = math.max(1.2, shape.Legs * 1.35)
	body.Phase += dt * speed / stride * math.pi
	local walk = math.clamp(speed / 12, 0, 1)
	body.Walk = (body.Walk or 0) + (walk - (body.Walk or 0)) * math.min(1, dt * 8)
	local swing = math.sin(body.Phase) * 0.55 * body.Walk
	local bob = math.abs(math.cos(body.Phase)) * shape.Legs * 0.05 * body.Walk

	local base = CFrame.lookAt(feet, feet + flat) * CFrame.new(0, bob, 0)
	body.FeetCF = base

	local p = body.Parts
	local W, D, LW = shape.Width, shape.Depth, shape.LimbWidth
	local legs, torso = shape.Legs, shape.Torso

	-- legs + shoes
	local shoeH = math.clamp(legs * 0.1, 0.06, 4)
	for _, entry in { { -1, p.LegL, p.ShoeL }, { 1, p.LegR, p.ShoeR } } :: { any } do
		local side, leg, shoe = entry[1], entry[2], entry[3]
		local hipCF = base * CFrame.new(side * W / 4, legs, 0) * CFrame.Angles(swing * -side, 0, 0)
		setSize(leg, Vector3.new(LW * 0.98, legs, D * 0.95))
		setSize(shoe, Vector3.new(LW * 1.08, shoeH, D * 1.15))
		push(leg, hipCF * CFrame.new(0, -legs / 2, 0))
		push(shoe, hipCF * CFrame.new(0, -legs + shoeH / 2, -D * 0.08))
	end

	-- torso
	setSize(p.Torso, Vector3.new(W, torso, D))
	local torsoCF = base * CFrame.new(0, legs + torso / 2, 0) * CFrame.Angles(math.sin(body.Phase * 2) * 0.03 * body.Walk, 0, 0)
	push(p.Torso, torsoCF)

	-- arms: shirt sleeve (upper) + skin (lower); swing opposite to the legs
	local armLen = shape.ArmLength
	local AW = shape.ArmWidth
	local upper, lower = armLen * 0.45, armLen * 0.55
	local sway = math.sin(body.Time * 1.7) * 0.04
	for _, entry in { { -1, p.ArmUL, p.ArmLL }, { 1, p.ArmUR, p.ArmLR } } :: { any } do
		local side, armU, armL = entry[1], entry[2], entry[3]
		local shoulder = base
			* CFrame.new(side * (W / 2 + AW * 0.45), legs + torso - AW * 0.35, 0)
			* CFrame.Angles(swing * side * 0.9, 0, side * (0.05 + sway))
		setSize(armU, Vector3.new(AW * 1.02, upper, AW * 1.02))
		setSize(armL, Vector3.new(AW * 0.9, lower, AW * 0.9))
		push(armU, shoulder * CFrame.new(0, -upper / 2, 0))
		push(armL, shoulder * CFrame.new(0, -upper - lower / 2, 0))
	end

	-- head (+ hats) scaled to shape.Head
	local head = body.Head
	local k = shape.Head / math.max(0.1, head.BaseSize.Y)
	if math.abs(k - head.K) > head.K * 0.01 or force then
		head.K = k
		head.Part.Size = head.BaseSize * k
		-- FileMesh scale is absolute (ignores part size); other mesh types follow the part
		if head.Mesh and head.MeshScale and head.Mesh.MeshType == Enum.MeshType.FileMesh then
			head.Mesh.Scale = head.MeshScale * k
		end
		for _, acc in head.Accessories do
			acc.Part.Size = acc.BaseSize * k
			if acc.Mesh and acc.MeshScale and acc.Mesh.MeshType == Enum.MeshType.FileMesh then
				acc.Mesh.Scale = acc.MeshScale * k
				acc.Mesh.Offset = acc.MeshOffset * k
			end
		end
	end
	local headSize = head.BaseSize.Y * k
	local nod = math.sin(body.Time * 2.1) * 0.03 + math.sin(body.Phase * 2) * 0.04 * body.Walk
	local headCF = base * CFrame.new(0, legs + torso + headSize / 2, 0) * CFrame.Angles(nod, 0, 0)
	push(head.Part, headCF)
	for _, acc in head.Accessories do
		local offset = acc.Offset
		push(acc.Part, headCF * CFrame.new(offset.Position * k) * offset.Rotation)
	end
	body.HeadCF = headCF
	body.TopPosition = headCF.Position + Vector3.new(0, headSize / 2, 0)

	-- cosmetics
	local fx = body.Fx
	if fx then
		local total = shape.Total
		if fx.Trail then
			fx.TrailTop.Position = Vector3.new(0, torso * 0.45, 0)
			fx.TrailBottom.Position = Vector3.new(0, -torso * 0.45, 0)
			if fx.TrailDef.Flicker then
				fx.Trail.Enabled = math.random() > 0.25
			end
		end
		if fx.AuraBox then
			local boxSize = Vector3.new(W * 2.2 + 1, total * 1.02, W * 2.2 + 1)
			setSize(fx.AuraBox, boxSize)
			push(fx.AuraBox, base * CFrame.new(0, total / 2, 0))
			local scale = math.clamp(total / 6, 0.6, 60)
			if not body.FxScale or math.abs(scale - body.FxScale) > body.FxScale * 0.1 then
				body.FxScale = scale
				local s = fx.AuraDef.Size * math.sqrt(scale)
				fx.Emitter.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, s * 0.4),
					NumberSequenceKeypoint.new(0.3, s),
					NumberSequenceKeypoint.new(1, 0),
				})
				fx.Emitter.Speed = NumberRange.new(fx.AuraDef.Speed * 0.5 * math.sqrt(scale), fx.AuraDef.Speed * math.sqrt(scale))
				if fx.Light then
					fx.Light.Range = math.clamp(8 + total * 0.4, 8, 60)
				end
			end
			if fx.AuraDef.Flicker and fx.Light then
				fx.Light.Brightness = 1 + math.random() * 3
			end
			local ringD = math.max(4, W * 3.4)
			if fx.Ring then
				setSize(fx.Ring, Vector3.new(0.2, ringD, ringD))
				push(fx.Ring, base * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, body.Time * 0.8, math.rad(90)))
			end
			if fx.Beam then
				setSize(fx.Beam, Vector3.new(total * 1.1, W * 1.8, W * 1.8))
				push(fx.Beam, base * CFrame.new(0, total * 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)))
			end
			local orbSize = math.clamp(W * 0.35, 0.4, 12)
			for i, orb in fx.Orbiters do
				local t = body.Time * (0.9 + i * 0.07) + i * (math.pi * 2 / #fx.Orbiters)
				local y = total * (0.15 + 0.7 * ((i * 0.37) % 1)) + math.sin(t * 1.3) * total * 0.05
				local r = W * 1.6 + 1
				setSize(orb, Vector3.one * orbSize)
				push(orb, base * CFrame.new(math.cos(t) * r, y, math.sin(t) * r))
			end
			for i, orb in fx.HaloOrbs do
				local t = body.Time * 1.4 + i * (math.pi * 2 / #fx.HaloOrbs)
				local r = headSize * 0.55
				setSize(orb, Vector3.one * math.max(0.2, headSize * 0.16))
				push(orb, headCF * CFrame.new(math.cos(t) * r, headSize * 0.75, math.sin(t) * r))
			end
		end
	end
end

function BodyController:Step(dt: number)
	-- event visual (GIANT / TINY MODE)
	local eventId = Workspace:GetAttribute("EventId")
	local def = type(eventId) == "string" and EventConfig.Events[eventId] or nil
	local targetScale = if def and def.Visual == "Giant" then 3 elseif def and def.Visual == "Tiny" then 0.3 else 1
	self.VisualScale += (targetScale - self.VisualScale) * (1 - math.exp(-dt * 3))

	-- predicted growth fades out if the server never confirms it
	self.LocalPending *= math.exp(-dt * 1.5)

	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero
	for player, body in self.Bodies do
		if not body.Root.Parent or not body.Character.Parent then
			self:RemoveBody(player)
			continue
		end
		-- far bodies update less often
		local distance = (body.Root.Position - camPos).Magnitude
		local every = if body.IsLocal or distance < 350 then 1 elseif distance < 1200 then 2 else 4
		body.Skip += 1
		body.SkipDt = (body.SkipDt or 0) + dt
		if body.Skip >= every then
			body.Skip = 0
			self:UpdateBody(body, body.SkipDt)
			body.SkipDt = 0
		end
	end
	flushMoves()
end

function BodyController:Init(controllers)
	self.Controllers = controllers
	local folder = Workspace:FindFirstChild("ChileBodies")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ChileBodies"
		folder.Parent = Workspace
	end
	self.Folder = folder
end

function BodyController:Start()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			self:CreateBody(player, character)
		end)
		player.CharacterRemoving:Connect(function()
			self:RemoveBody(player)
		end)
		if player.Character then
			task.spawn(self.CreateBody, self, player, player.Character)
		end
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		self:RemoveBody(player)
	end)

	-- settings that change what we render
	self.Controllers.ClientData.Changed:Connect(function(section)
		if section == "Settings" then
			for _, body in self.Bodies do
				self:ApplyCosmetics(body)
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		self:Step(math.min(dt, 0.1))
	end)
end

return BodyController
