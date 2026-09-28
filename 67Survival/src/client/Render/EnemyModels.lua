--[[
	EnemyModels - builds the client-side enemy models from parts (no assets needed).

	Every model is one ANCHORED root part plus unanchored, massless parts welded to it, so the
	renderer moves a whole enemy with a single CFrame (workspace:BulkMoveTo over the roots).
	Nothing collides, casts shadows or can be queried: they are pure visuals.

	Silhouette first: every enemy reads as a different SHAPE from the top-down camera (bug,
	bomb, sac, frog, sheet, rifle...), colour second. Faces stay goofy (googly eyes).

	EnemyModels.Build(def, variant) -> model, root, info { Height, BodyColor, Scale, Parts, Float }
	variant: "" | "t" (tiny) | "g" (golden) | "G" (giant, 67 MODE) | "e" (elite)
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
		-- pupils look in random directions
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

-- Skitter: flat, six legs, antennae (low to the ground, reads as "bug" from above)
function STYLES.Bug(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Body", Vector3.new(1.6, 0.8, 2.0), c, CFrame.new(), BALL)
	newPart(b, "Head", Vector3.new(0.9, 0.7, 0.8), a, CFrame.new(0, 0.1, -1.1), BALL)
	for i = -1, 1 do
		for _, side in { -1, 1 } do
			newPart(b, "Leg", Vector3.new(1.1, 0.14, 0.14), a, CFrame.new(side * 0.95, -0.25, i * 0.55) * CFrame.Angles(0, 0, side * -0.5))
		end
	end
	newPart(b, "AntennaL", Vector3.new(0.1, 0.1, 0.9), a, CFrame.new(-0.25, 0.45, -1.6) * CFrame.Angles(0.6, 0.3, 0))
	newPart(b, "AntennaR", Vector3.new(0.1, 0.1, 0.9), a, CFrame.new(0.25, 0.45, -1.6) * CFrame.Angles(0.6, -0.3, 0))
	return 0.55
end

local function blocky(b: Builder, body: Color3, skin: Color3, legs: Color3): BasePart
	newPart(b, "Torso", Vector3.new(1.8, 1.6, 0.9), body, CFrame.new())
	newPart(b, "Legs", Vector3.new(1.8, 1.6, 0.9), legs, CFrame.new(0, -1.6, 0))
	newPart(b, "ArmL", Vector3.new(0.8, 1.6, 0.9), skin, CFrame.new(-1.3, 0, 0))
	newPart(b, "ArmR", Vector3.new(0.8, 1.6, 0.9), skin, CFrame.new(1.3, 0, 0))
	return newPart(b, "Head", Vector3.new(1.15, 1.15, 1.15), skin, CFrame.new(0, 1.4, 0))
end

-- Husk: the blank blocky stranger
function STYLES.Npc(b: Builder, c: Color3, a: Color3): number
	local head = blocky(b, a, c, rgb(60, 62, 70))
	face(head)
	return 2.4
end

-- Charger: low and wide, two horns
function STYLES.Charger(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Body", Vector3.new(2.4, 1.6, 2.6), c, CFrame.new())
	newPart(b, "Head", Vector3.new(1.6, 1.2, 1.1), c:Lerp(WHITE, 0.15), CFrame.new(0, 0.2, -1.6))
	newPart(b, "HornL", Vector3.new(0.35, 1.1, 0.35), WHITE, CFrame.new(-0.7, 1.0, -1.7) * CFrame.Angles(-0.4, 0, 0.5))
	newPart(b, "HornR", Vector3.new(0.35, 1.1, 0.35), WHITE, CFrame.new(0.7, 1.0, -1.7) * CFrame.Angles(-0.4, 0, -0.5))
	for _, x in { -0.8, 0.8 } do
		for _, z in { -0.8, 0.8 } do
			newPart(b, "Leg", Vector3.new(0.5, 0.9, 0.5), a, CFrame.new(x, -1.1, z))
		end
	end
	googlyEyes(b, 0.45, 0.4, 0.45, -2.1)
	return 1.55
end

-- Spitter: a swollen sac with a nozzle
function STYLES.Spitter(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Sac", Vector3.new(2.6, 2.6, 2.6), c, CFrame.new(), BALL)
	newPart(b, "Nozzle", Vector3.new(1.2, 0.8, 0.8), a, CFrame.new(0, -0.1, -1.5) * CFrame.Angles(0, math.pi / 2, 0), Enum.PartType.Cylinder)
	for _, off in { Vector3.new(-0.8, 0.8, 0.6), Vector3.new(0.7, 0.3, 0.9), Vector3.new(0.2, 1.1, -0.4) } do
		newPart(b, "Spot", Vector3.new(0.6, 0.6, 0.6), a, CFrame.new(off), BALL)
	end
	newPart(b, "LegL", Vector3.new(0.4, 0.8, 0.4), a, CFrame.new(-0.6, -1.5, 0))
	newPart(b, "LegR", Vector3.new(0.4, 0.8, 0.4), a, CFrame.new(0.6, -1.5, 0))
	googlyEyes(b, 0.6, 0.45, 0.9, -1.05)
	return 1.85
end

-- Splitter: two blobs glued together
function STYLES.Splitter(b: Builder, c: Color3, a: Color3): number
	newPart(b, "BodyL", Vector3.new(2.3, 2.2, 2.3), c, CFrame.new(-0.7, 0, 0), BALL)
	newPart(b, "BodyR", Vector3.new(2.1, 2.0, 2.1), a, CFrame.new(0.8, -0.1, 0.1), BALL)
	googlyEyes(b, 0.7, 0.45, 0.4, -1.0)
	newPart(b, "Seam", Vector3.new(0.15, 1.8, 1.8), WHITE, CFrame.new(0.1, 0, 0), nil, Enum.Material.Neon)
	return 1.1
end

-- Bomber: a walking bomb with a lit fuse
function STYLES.Bomber(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Bomb", Vector3.new(2.4, 2.4, 2.4), c, CFrame.new(), BALL)
	newPart(b, "Cap", Vector3.new(0.5, 0.9, 0.9), rgb(90, 90, 100), CFrame.new(0, 1.25, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
	newPart(b, "Fuse", Vector3.new(0.15, 0.8, 0.15), rgb(200, 170, 120), CFrame.new(0.15, 1.8, 0) * CFrame.Angles(0, 0, -0.4))
	newPart(b, "Spark", Vector3.new(0.45, 0.45, 0.45), a, CFrame.new(0.35, 2.2, 0), BALL, Enum.Material.Neon)
	newPart(b, "BrowL", Vector3.new(0.6, 0.12, 0.1), WHITE, CFrame.new(-0.4, 0.55, -1.15) * CFrame.Angles(0, 0, -0.35))
	newPart(b, "BrowR", Vector3.new(0.6, 0.12, 0.1), WHITE, CFrame.new(0.4, 0.55, -1.15) * CFrame.Angles(0, 0, 0.35))
	newPart(b, "EyeL", Vector3.new(0.3, 0.3, 0.1), a, CFrame.new(-0.4, 0.3, -1.18), nil, Enum.Material.Neon)
	newPart(b, "EyeR", Vector3.new(0.3, 0.3, 0.1), a, CFrame.new(0.4, 0.3, -1.18), nil, Enum.Material.Neon)
	return 1.25
end

function STYLES.Brute(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Body", Vector3.new(3.6, 3.2, 2.4), c, CFrame.new())
	newPart(b, "Legs", Vector3.new(2.8, 1.6, 1.8), a, CFrame.new(0, -2.4, 0))
	newPart(b, "PadL", Vector3.new(1.4, 1, 2.6), a, CFrame.new(-2.3, 1.3, 0))
	newPart(b, "PadR", Vector3.new(1.4, 1, 2.6), a, CFrame.new(2.3, 1.3, 0))
	newPart(b, "FistL", Vector3.new(1.5, 1.5, 1.5), a:Lerp(WHITE, 0.2), CFrame.new(-2.4, -0.9, -0.3), BALL)
	newPart(b, "FistR", Vector3.new(1.5, 1.5, 1.5), a:Lerp(WHITE, 0.2), CFrame.new(2.4, -0.9, -0.3), BALL)
	local head = newPart(b, "Head", Vector3.new(1.4, 1.4, 1.4), SKIN, CFrame.new(0, 2.3, 0))
	face(head)
	return 3.2
end

-- Diver: wide wings, beak; flies (height above the ground)
function STYLES.Diver(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Body", Vector3.new(1.4, 1.2, 2.0), c, CFrame.new(), BALL)
	newPart(b, "WingL", Vector3.new(2.6, 0.2, 1.4), c:Lerp(BLACK, 0.2), CFrame.new(-1.8, 0.3, 0.1) * CFrame.Angles(0, 0, 0.3))
	newPart(b, "WingR", Vector3.new(2.6, 0.2, 1.4), c:Lerp(BLACK, 0.2), CFrame.new(1.8, 0.3, 0.1) * CFrame.Angles(0, 0, -0.3))
	newPart(b, "Beak", Vector3.new(0.4, 0.4, 0.8), a, CFrame.new(0, -0.05, -1.3))
	newPart(b, "Tail", Vector3.new(0.8, 0.15, 0.8), c:Lerp(BLACK, 0.3), CFrame.new(0, 0.1, 1.2))
	googlyEyes(b, 0.45, 0.3, 0.3, -0.85)
	return 3.2
end

-- Summoner: a tall hooded robe with a glowing orb
function STYLES.Summoner(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Robe", Vector3.new(2.2, 3.2, 2.2), c, CFrame.new(), BALL)
	newPart(b, "Hood", Vector3.new(1.6, 1.8, 1.6), c:Lerp(BLACK, 0.3), CFrame.new(0, 1.9, 0), BALL)
	newPart(b, "EyeL", Vector3.new(0.25, 0.25, 0.1), a, CFrame.new(-0.3, 1.9, -0.8), nil, Enum.Material.Neon)
	newPart(b, "EyeR", Vector3.new(0.25, 0.25, 0.1), a, CFrame.new(0.3, 1.9, -0.8), nil, Enum.Material.Neon)
	newPart(b, "Staff", Vector3.new(0.2, 3.6, 0.2), rgb(90, 70, 50), CFrame.new(1.3, 0.4, -0.3))
	newPart(b, "Orb", Vector3.new(0.9, 0.9, 0.9), a, CFrame.new(1.3, 2.4, -0.3), BALL, Enum.Material.Neon)
	return 1.7
end

-- Ghost: a floating sheet
function STYLES.Ghost(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Sheet", Vector3.new(2.2, 2.6, 2.2), c, CFrame.new(), BALL)
	newPart(b, "Hem", Vector3.new(0.4, 2.3, 2.3), c:Lerp(a, 0.25), CFrame.new(0, -1.05, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
	newPart(b, "EyeL", Vector3.new(0.4, 0.6, 0.1), BLACK, CFrame.new(-0.4, 0.3, -1.05))
	newPart(b, "EyeR", Vector3.new(0.4, 0.6, 0.1), BLACK, CFrame.new(0.4, 0.3, -1.05))
	newPart(b, "Mouth", Vector3.new(0.45, 0.45, 0.1), BLACK, CFrame.new(0, -0.35, -1.05), BALL)
	for _, p in b.Parts do
		p.Transparency = 0.2
	end
	return 2.2
end

-- Leaper: a frog with huge back legs
function STYLES.Leaper(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Body", Vector3.new(2.8, 1.6, 2.6), c, CFrame.new(), BALL)
	newPart(b, "Belly", Vector3.new(2.0, 1.0, 1.6), a, CFrame.new(0, -0.35, -0.6), BALL)
	newPart(b, "LegL", Vector3.new(0.9, 1.0, 2.0), c:Lerp(BLACK, 0.2), CFrame.new(-1.4, -0.4, 0.8))
	newPart(b, "LegR", Vector3.new(0.9, 1.0, 2.0), c:Lerp(BLACK, 0.2), CFrame.new(1.4, -0.4, 0.8))
	googlyEyes(b, 0.9, 0.7, 0.9, -0.6)
	return 1.0
end

-- Mimic: a loot box... with teeth (look closely)
function STYLES.Mimic(b: Builder, c: Color3, a: Color3): number
	local box = newPart(b, "Box", Vector3.new(2.8, 2.8, 2.8), c, CFrame.new(), nil, Enum.Material.WoodPlanks)
	newPart(b, "Band", Vector3.new(2.95, 0.5, 2.95), a, CFrame.new(0, 0, 0), nil, Enum.Material.Neon)
	for i = -2, 2 do
		newPart(b, "Tooth", Vector3.new(0.3, 0.35, 0.2), WHITE, CFrame.new(i * 0.5, -0.4, -1.45) * CFrame.Angles(0, 0, math.pi / 4))
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.Parent = box
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "?"
	label.TextScaled = true
	label.Font = Enum.Font.LuckiestGuy
	label.TextColor3 = a
	label.Parent = gui
	return 1.4
end

-- Sniper: tall and thin, a long rifle and a red eye
function STYLES.Sniper(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Body", Vector3.new(1.1, 3.0, 0.9), c, CFrame.new())
	newPart(b, "Head", Vector3.new(0.9, 0.9, 0.9), c:Lerp(WHITE, 0.15), CFrame.new(0, 1.95, 0))
	newPart(b, "Eye", Vector3.new(0.5, 0.25, 0.1), a, CFrame.new(0, 2.0, -0.48), nil, Enum.Material.Neon)
	newPart(b, "Rifle", Vector3.new(0.25, 0.25, 3.2), rgb(40, 40, 45), CFrame.new(0.65, 0.6, -1.2))
	newPart(b, "Scope", Vector3.new(0.3, 0.3, 0.3), a, CFrame.new(0.65, 0.85, -1.6), BALL, Enum.Material.Neon)
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

function STYLES.Goblin(b: Builder, c: Color3, a: Color3): number
	local body = newPart(b, "Body", Vector3.new(1.8, 1.8, 1.8), c, CFrame.new(), BALL, Enum.Material.Foil)
	newPart(b, "EarL", Vector3.new(0.3, 0.9, 0.6), c, CFrame.new(-1.0, 0.5, 0) * CFrame.Angles(0, 0, 0.5))
	newPart(b, "EarR", Vector3.new(0.3, 0.9, 0.6), c, CFrame.new(1.0, 0.5, 0) * CFrame.Angles(0, 0, -0.5))
	newPart(b, "Sack", Vector3.new(1.3, 1.3, 1.3), a, CFrame.new(0.9, 0.3, 0.8), BALL)
	googlyEyes(b, 0.55, 0.35, 0.3, -0.7)
	billboard(body, "67", rgb(255, 215, 50), 3, 2.2)
	return 1.0
end

-- THE 67: a golden disc with a spinning ring and a huge "67"
function STYLES.The67(b: Builder, c: Color3, a: Color3): number
	local core = newPart(b, "Core", Vector3.new(3.4, 3.4, 3.4), c, CFrame.new(), BALL, Enum.Material.Neon)
	newPart(b, "Ring", Vector3.new(0.3, 6, 6), a, CFrame.new(0, 0, 0) * CFrame.Angles(0.4, 0, math.pi / 2), Enum.PartType.Cylinder, Enum.Material.Neon)
	newPart(b, "Ring2", Vector3.new(0.3, 5, 5), c, CFrame.new(0, 0, 0) * CFrame.Angles(-0.6, 0.5, math.pi / 2), Enum.PartType.Cylinder, Enum.Material.Neon)
	billboard(core, "67", rgb(255, 230, 90), 7, 3.2)
	return 4.2
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

---------------------------------------------------------------------------- bosses
-- THE GIANT: huge, blank-faced, fists like boulders
function STYLES.Giant(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Torso", Vector3.new(6, 5.5, 3.6), c, CFrame.new())
	newPart(b, "Belt", Vector3.new(6.2, 1, 3.8), a, CFrame.new(0, -2.4, 0))
	newPart(b, "Legs", Vector3.new(5, 3.6, 3), a, CFrame.new(0, -4.6, 0))
	newPart(b, "ArmL", Vector3.new(1.8, 5, 2), c, CFrame.new(-4, -0.2, 0))
	newPart(b, "ArmR", Vector3.new(1.8, 5, 2), c, CFrame.new(4, -0.2, 0))
	newPart(b, "FistL", Vector3.new(3, 3, 3), a, CFrame.new(-4.1, -3.2, -0.3), BALL)
	newPart(b, "FistR", Vector3.new(3, 3, 3), a, CFrame.new(4.1, -3.2, -0.3), BALL)
	local head = newPart(b, "Head", Vector3.new(2.6, 2.6, 2.6), c:Lerp(WHITE, 0.15), CFrame.new(0, 4.1, 0))
	face(head)
	return 6.4
end

-- THE GOOBER: the biggest blob
function STYLES.GooberBoss(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Body", Vector3.new(9, 8, 9), c, CFrame.new(), BALL)
	for _, off in { Vector3.new(-2.6, 2.4, -2.4), Vector3.new(3, 1.2, -2.2), Vector3.new(-3.4, -0.6, 1.5), Vector3.new(2.2, 3, 2) } do
		newPart(b, "Spot", Vector3.new(1.6, 1.6, 1.6), a, CFrame.new(off), BALL)
	end
	googlyEyes(b, 2.6, 1.6, 1.6, -3.5)
	newPart(b, "Antenna", Vector3.new(0.3, 2.4, 0.3), a, CFrame.new(0, 4.8, 0))
	newPart(b, "AntennaBall", Vector3.new(1, 1, 1), a, CFrame.new(0, 6.1, 0), BALL, Enum.Material.Neon)
	return 4
end

-- THE GLITCH: a stack of neon blocks with offset copies
function STYLES.GlitchBoss(b: Builder, c: Color3, a: Color3): number
	for i = 0, 4 do
		local w = 4.5 - i * 0.5
		local color = if i % 2 == 0 then c else a
		newPart(b, "Block", Vector3.new(w, 1.6, w), color, CFrame.new((i % 2) * 0.6 - 0.3, i * 1.7 - 2.5, 0), nil, Enum.Material.Neon)
	end
	for _, off in { Vector3.new(-3.2, 1, 0.8), Vector3.new(3, -1, -0.6), Vector3.new(2.4, 3, 1) } do
		newPart(b, "Shard", Vector3.new(1, 1, 1), a, CFrame.new(off), nil, Enum.Material.Neon)
	end
	newPart(b, "Eye", Vector3.new(2, 0.6, 0.2), WHITE, CFrame.new(0, 4.4, -1.1), nil, Enum.Material.Neon)
	return 4.4
end

-- THE MACHINE: a box robot on treads with two cannons
function STYLES.Machine(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Hull", Vector3.new(6, 4, 5), c, CFrame.new(), nil, Enum.Material.DiamondPlate)
	newPart(b, "TreadL", Vector3.new(1.4, 1.8, 6), rgb(40, 40, 45), CFrame.new(-3.3, -2.6, 0))
	newPart(b, "TreadR", Vector3.new(1.4, 1.8, 6), rgb(40, 40, 45), CFrame.new(3.3, -2.6, 0))
	newPart(b, "Visor", Vector3.new(4, 0.8, 0.3), a, CFrame.new(0, 1, -2.6), nil, Enum.Material.Neon)
	newPart(b, "CannonL", Vector3.new(4, 1.2, 1.2), rgb(70, 70, 80), CFrame.new(-3.6, 1.2, -1.2) * CFrame.Angles(0, math.pi / 2, 0), Enum.PartType.Cylinder)
	newPart(b, "CannonR", Vector3.new(4, 1.2, 1.2), rgb(70, 70, 80), CFrame.new(3.6, 1.2, -1.2) * CFrame.Angles(0, math.pi / 2, 0), Enum.PartType.Cylinder)
	newPart(b, "Antenna", Vector3.new(0.3, 2.5, 0.3), rgb(70, 70, 80), CFrame.new(1.6, 3.2, 1.2))
	newPart(b, "Light", Vector3.new(0.7, 0.7, 0.7), a, CFrame.new(1.6, 4.5, 1.2), BALL, Enum.Material.Neon)
	return 3.5
end

-- THE VOID: a dark core, one huge eye, orbiting shards; floats
function STYLES.VoidBoss(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Core", Vector3.new(7, 7, 7), c, CFrame.new(), BALL)
	newPart(b, "Eye", Vector3.new(3.4, 3.4, 1), WHITE, CFrame.new(0, 0.4, -3.1), BALL)
	newPart(b, "Pupil", Vector3.new(1.6, 1.6, 0.6), a, CFrame.new(0, 0.4, -3.55), BALL, Enum.Material.Neon)
	for i = 0, 5 do
		local ang = i * math.pi / 3
		newPart(b, "Shard", Vector3.new(0.8, 2.2, 0.8), a, CFrame.new(math.cos(ang) * 5.2, math.sin(i) * 1.5, math.sin(ang) * 5.2) * CFrame.Angles(0.4, ang, 0.3), nil, Enum.Material.Neon)
	end
	return 6
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
	newPart(b, "Cape", Vector3.new(4.6, 6.5, 0.3), a:Lerp(BLACK, 0.5), CFrame.new(0, -0.6, 1.3))
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

-- THE FINAL ONE: four arms, one eye, a crown of spikes
function STYLES.FinalOne(b: Builder, c: Color3, a: Color3): number
	newPart(b, "Body", Vector3.new(7, 7.5, 4.5), c, CFrame.new())
	newPart(b, "Legs", Vector3.new(6, 4, 3.5), c:Lerp(BLACK, 0.4), CFrame.new(0, -5.6, 0))
	for _, y in { 2, -1.2 } do
		for _, side in { -1, 1 } do
			newPart(b, "Arm", Vector3.new(4.5, 1.5, 1.5), c:Lerp(a, 0.15), CFrame.new(side * 5.4, y, -0.4) * CFrame.Angles(0, 0, side * 0.35))
			newPart(b, "Claw", Vector3.new(1.6, 1.6, 1.6), a, CFrame.new(side * 7.6, y - 0.9, -0.6), BALL, Enum.Material.Neon)
		end
	end
	newPart(b, "Head", Vector3.new(4, 4, 4), c:Lerp(WHITE, 0.08), CFrame.new(0, 5.6, 0), BALL)
	newPart(b, "Eye", Vector3.new(2.4, 2.4, 0.8), WHITE, CFrame.new(0, 5.8, -1.8), BALL)
	newPart(b, "Pupil", Vector3.new(1.1, 1.1, 0.5), a, CFrame.new(0, 5.8, -2.15), BALL, Enum.Material.Neon)
	for i = -2, 2 do
		newPart(b, "Spike", Vector3.new(0.7, 2 - math.abs(i) * 0.3, 0.7), a, CFrame.new(i * 0.9, 8.2 - math.abs(i) * 0.2, 0) * CFrame.Angles(0, 0, -i * 0.2), nil, Enum.Material.Neon)
	end
	newPart(b, "Cape", Vector3.new(7, 9, 0.4), a:Lerp(BLACK, 0.6), CFrame.new(0, -1, 2.4))
	return 7.6
end

-- floating models bob in the air instead of hopping
local FLOAT = { Diver = true, Ghost = true, The67 = true, VoidBoss = true }

-- models stand on the ground (height = root centre above the ground, unscaled)
function EnemyModels.Build(def, variant: string?): (Model, BasePart, any)
	local v = variant or ""
	local model = Instance.new("Model")
	model.Name = def.Key
	local scale = def.Scale
	if string.find(v, "t", 1, true) then
		scale *= 0.55
	elseif string.find(v, "G", 1, true) then
		scale *= 1.5
	end
	if string.find(v, "e", 1, true) then
		scale *= 1.3
	end
	local b: Builder = { Model = model, Root = nil, Scale = scale, Parts = {} }
	local color, accent = def.Color, def.Accent
	if string.find(v, "g", 1, true) then
		color, accent = rgb(255, 205, 50), rgb(255, 245, 170)
	end
	local style = STYLES[def.Model] or STYLES.Blob
	local height = style(b, color, accent)
	if string.find(v, "e", 1, true) then
		-- elites wear a glowing ring: a tougher version, worth a fragment sometimes
		newPart(b, "EliteRing", Vector3.new(0.25, 3.6, 3.6), rgb(255, 205, 60), CFrame.new(0, -height + 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder, Enum.Material.Neon)
	end
	local root = b.Root :: BasePart
	model.PrimaryPart = root
	return model, root, { Height = height * scale, BodyColor = root.Color, Scale = scale, Parts = b.Parts, Float = FLOAT[def.Model] == true }
end

return EnemyModels
