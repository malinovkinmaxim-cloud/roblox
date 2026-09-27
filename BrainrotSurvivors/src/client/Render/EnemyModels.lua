--[[
	EnemyModels - builds the client-side enemy models from parts (no assets needed).

	Every model is one ANCHORED root part plus unanchored, massless parts welded to it, so the
	renderer moves a whole enemy with a single CFrame (workspace:BulkMoveTo over the roots).
	Nothing collides, casts shadows or can be queried: they are pure visuals.

	Faces are deliberately goofy: googly eyes with pupils looking in random directions, the
	classic blank NPC face, open screaming mouths.

	EnemyModels.Build(def, tiny, golden) -> model, root, info { Height, BodyColor, Parts }
]]

local EnemyModels = {}

local rgb = Color3.fromRGB
local WHITE = rgb(255, 255, 255)
local BLACK = rgb(20, 20, 25)
local SKIN = rgb(234, 190, 150)
local FACE = "rbxasset://textures/face.png"

local rng = Random.new()

type Builder = {
	Model: Model,
	Root: BasePart?,
	Scale: number,
	Parts: { BasePart },
}

local function newPart(b: Builder, name: string, size: Vector3, color: Color3, offset: CFrame, shape: Enum.PartType?, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size * b.Scale
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	local root = b.Root
	if root then
		p.Anchored = false
		p.Massless = true
		p.CFrame = root.CFrame * CFrame.new(offset.Position * b.Scale) * offset.Rotation
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
	else
		p.Anchored = true
		p.CFrame = CFrame.new(0, -400, 0)
		b.Root = p
	end
	p.Parent = b.Model
	table.insert(b.Parts, p)
	return p
end

local BALL = Enum.PartType.Ball

local function googlyEyes(b: Builder, size: number, spread: number, y: number, z: number)
	for _, side in { -1, 1 } do
		newPart(b, "Eye", Vector3.new(size, size, size), WHITE, CFrame.new(side * spread, y, z), BALL)
		-- pupils look in random directions: maximum brainrot
		local px = rng:NextNumber(-0.22, 0.22) * size
		local py = rng:NextNumber(-0.22, 0.22) * size
		newPart(b, "Pupil", Vector3.new(size * 0.48, size * 0.48, size * 0.48), BLACK, CFrame.new(side * spread + px, y + py, z - size * 0.36), BALL)
	end
end

local function face(part: BasePart)
	local decal = Instance.new("Decal")
	decal.Texture = FACE
	decal.Face = Enum.NormalId.Front
	decal.Parent = part
end

local function billboard(part: BasePart, text: string, color: Color3, size: number, offset: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(size, size * 0.6)
	gui.StudsOffset = Vector3.new(0, offset, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.LuckiestGuy
	label.TextColor3 = color
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
end

local STYLES = {}

function STYLES.Blob(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Body", Vector3.new(2.6, 2.3, 2.6), c, CFrame.new(), BALL)
	googlyEyes(b, 0.95, 0.55, 0.45, -0.95)
	newPart(b, "Mouth", Vector3.new(0.8, 0.16, 0.12), a:Lerp(BLACK, 0.6), CFrame.new(0, -0.35, -1.24))
	return 1.15
end

local function blocky(b: Builder, body: Color3, skin: Color3, legs: Color3): BasePart
	newPart(b, "Torso", Vector3.new(1.8, 1.6, 0.9), body, CFrame.new())
	newPart(b, "Legs", Vector3.new(1.8, 1.6, 0.9), legs, CFrame.new(0, -1.6, 0))
	newPart(b, "ArmL", Vector3.new(0.8, 1.6, 0.9), skin, CFrame.new(-1.3, 0, 0))
	newPart(b, "ArmR", Vector3.new(0.8, 1.6, 0.9), skin, CFrame.new(1.3, 0, 0))
	return newPart(b, "Head", Vector3.new(1.15, 1.15, 1.15), skin, CFrame.new(0, 1.4, 0))
end

function STYLES.Npc(b: Builder, c: Color3, a: Color3): number
	local head = blocky(b, a, c, rgb(40, 127, 71))
	face(head)
	return 2.4
end

function STYLES.Skinny(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Body", Vector3.new(1.1, 2.4, 0.9), c, CFrame.new())
	newPart(b, "Legs", Vector3.new(1.0, 1.4, 0.8), c:Lerp(BLACK, 0.4), CFrame.new(0, -1.9, 0))
	newPart(b, "Head", Vector3.new(1.3, 1.3, 1.3), SKIN, CFrame.new(0, 1.8, 0), BALL)
	newPart(b, "Headband", Vector3.new(1.4, 0.3, 1.4), a, CFrame.new(0, 2.1, 0), Enum.PartType.Cylinder)
	googlyEyes(b, 0.45, 0.28, 1.9, -0.5)
	return 2.6
end

function STYLES.Brute(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Body", Vector3.new(3.6, 3.2, 2.4), c, CFrame.new())
	newPart(b, "Legs", Vector3.new(2.8, 1.6, 1.8), a, CFrame.new(0, -2.4, 0))
	newPart(b, "PadL", Vector3.new(1.4, 1, 2.6), a, CFrame.new(-2.3, 1.3, 0))
	newPart(b, "PadR", Vector3.new(1.4, 1, 2.6), a, CFrame.new(2.3, 1.3, 0))
	local head = newPart(b, "Head", Vector3.new(1.4, 1.4, 1.4), SKIN, CFrame.new(0, 2.3, 0))
	face(head)
	return 3.2
end

function STYLES.Screamer(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Head", Vector3.new(2.6, 3.0, 2.4), c, CFrame.new(), BALL)
	newPart(b, "Mouth", Vector3.new(1.3, 1.6, 0.6), rgb(60, 10, 15), CFrame.new(0, -0.35, -1.0), BALL)
	googlyEyes(b, 0.6, 0.55, 0.8, -0.95)
	newPart(b, "Body", Vector3.new(1.2, 1.2, 1), a, CFrame.new(0, -2, 0))
	return 2.6
end

function STYLES.Goblin(b: Builder, c: Color3, a: Color3): number
	local body = newPart(b, "Body", Vector3.new(1.8, 1.8, 1.8), c, CFrame.new(), BALL, Enum.Material.Foil)
	newPart(b, "EarL", Vector3.new(0.3, 0.9, 0.6), c, CFrame.new(-1.0, 0.5, 0) * CFrame.Angles(0, 0, 0.5))
	newPart(b, "EarR", Vector3.new(0.3, 0.9, 0.6), c, CFrame.new(1.0, 0.5, 0) * CFrame.Angles(0, 0, -0.5))
	newPart(b, "Sack", Vector3.new(1.3, 1.3, 1.3), a, CFrame.new(0.9, 0.3, 0.8), BALL)
	googlyEyes(b, 0.55, 0.35, 0.3, -0.7)
	billboard(body, "67", rgb(255, 215, 50), 3, 2.2)
	return 1.0
end

function STYLES.Suit(b: Builder, c: Color3, a: Color3): number
	blocky(b, c, SKIN, rgb(25, 25, 30))
	newPart(b, "Shades", Vector3.new(1.2, 0.32, 0.2), BLACK, CFrame.new(0, 1.5, -0.6))
	newPart(b, "Chain", Vector3.new(1.2, 0.3, 0.2), a, CFrame.new(0, 0.5, -0.5), nil, Enum.Material.Neon)
	newPart(b, "Jaw", Vector3.new(1.05, 0.35, 0.25), SKIN:Lerp(BLACK, 0.1), CFrame.new(0, 0.95, -0.55))
	return 2.4
end

function STYLES.Glitch(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Torso", Vector3.new(1.8, 1.6, 0.9), c, CFrame.new(), nil, Enum.Material.Neon)
	newPart(b, "Legs", Vector3.new(1.8, 1.6, 0.9), a, CFrame.new(0, -1.6, 0))
	for i, off in { Vector2.new(-0.3, 0.3), Vector2.new(0.3, 0.3), Vector2.new(-0.3, -0.3), Vector2.new(0.3, -0.3) } do
		local color = if i == 1 or i == 4 then c else a
		newPart(b, "Pixel", Vector3.new(0.6, 0.6, 1.1), color, CFrame.new(off.X, 1.4 + off.Y, 0), nil, if color == c then Enum.Material.Neon else nil)
	end
	return 2.4
end

function STYLES.Brain(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Brain", Vector3.new(9, 7, 10), c, CFrame.new(), BALL)
	newPart(b, "LobeL", Vector3.new(5, 4, 7), a, CFrame.new(-2.4, 2.2, 0.5), BALL)
	newPart(b, "LobeR", Vector3.new(5, 4, 7), a, CFrame.new(2.4, 2.2, 0.5), BALL)
	newPart(b, "LegL", Vector3.new(1.4, 3.5, 1.4), SKIN, CFrame.new(-2.2, -4.6, 0))
	newPart(b, "LegR", Vector3.new(1.4, 3.5, 1.4), SKIN, CFrame.new(2.2, -4.6, 0))
	googlyEyes(b, 2.2, 1.9, 0.6, -4.3)
	return 6.3
end

function STYLES.Overlord(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Torso", Vector3.new(4.4, 4, 2.2), c, CFrame.new())
	newPart(b, "Legs", Vector3.new(4.2, 3.6, 2), rgb(15, 15, 20), CFrame.new(0, -3.8, 0))
	newPart(b, "ArmL", Vector3.new(1.8, 4, 2), c, CFrame.new(-3.1, 0, 0))
	newPart(b, "ArmR", Vector3.new(1.8, 4, 2), c, CFrame.new(3.1, 0, 0))
	newPart(b, "Head", Vector3.new(2.8, 2.8, 2.8), SKIN, CFrame.new(0, 3.4, 0))
	newPart(b, "Shades", Vector3.new(2.9, 0.7, 0.3), BLACK, CFrame.new(0, 3.7, -1.4))
	newPart(b, "Jaw", Vector3.new(2.7, 0.9, 0.4), SKIN:Lerp(BLACK, 0.12), CFrame.new(0, 2.5, -1.3))
	newPart(b, "Chain", Vector3.new(2.6, 0.5, 0.3), a, CFrame.new(0, 1.2, -1.2), nil, Enum.Material.Neon)
	return 5.6
end

function STYLES.King(b: Builder, c: Color3, a: Color3): number
	local body = newPart(b, "Body", Vector3.new(4.5, 4.5, 3), c, CFrame.new(), nil, Enum.Material.Foil)
	newPart(b, "Legs", Vector3.new(4, 3, 2.6), a, CFrame.new(0, -3.7, 0))
	newPart(b, "Head", Vector3.new(3, 3, 3), c:Lerp(WHITE, 0.3), CFrame.new(0, 3.8, 0))
	newPart(b, "Cape", Vector3.new(4.6, 6, 0.3), a, CFrame.new(0, 0.5, 1.7))
	newPart(b, "CrownBand", Vector3.new(3.2, 0.6, 3.2), c, CFrame.new(0, 5.5, 0), nil, Enum.Material.Neon)
	for i = -1, 1 do
		newPart(b, "Spike", Vector3.new(0.7, 1.3, 0.7), c, CFrame.new(i * 1.1, 6.3, 0), nil, Enum.Material.Neon)
	end
	googlyEyes(b, 0.9, 0.7, 4, -1.55)
	billboard(body, "67", rgb(255, 230, 90), 5, 0)
	return 4.8
end

function STYLES.Crate(b: Builder, c: Color3, a: Color3): number
	local box = newPart(b, "Box", Vector3.new(2.8, 2.8, 2.8), c, CFrame.new(), nil, Enum.Material.WoodPlanks)
	newPart(b, "Band", Vector3.new(2.95, 0.5, 2.95), a, CFrame.new(0, 0, 0), nil, Enum.Material.Neon)
	for _, f in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Top } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = f
		gui.LightInfluence = 0
		gui.CanvasSize = Vector2.new(100, 100)
		gui.Parent = box
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "?"
		label.TextScaled = true
		label.Font = Enum.Font.LuckiestGuy
		label.TextColor3 = a
		label.Parent = gui
	end
	return 1.4
end

-- models that stand on the ground (height = root centre above the ground, unscaled)
function EnemyModels.Build(def, tiny: boolean, golden: boolean): (Model, BasePart, any)
	local model = Instance.new("Model")
	model.Name = def.Key
	local scale = def.Scale * (if tiny then 0.55 else 1)
	local b: Builder = { Model = model, Root = nil, Scale = scale, Parts = {} }
	local color, accent = def.Color, def.Accent
	if golden then
		color, accent = rgb(255, 205, 50), rgb(255, 245, 170)
	end
	local style = STYLES[def.Model] or STYLES.Blob
	local height = style(b, color, accent)
	local root = b.Root :: BasePart
	model.PrimaryPart = root
	return model, root, { Height = height * scale, BodyColor = root.Color, Scale = scale, Parts = b.Parts }
end

return EnemyModels
