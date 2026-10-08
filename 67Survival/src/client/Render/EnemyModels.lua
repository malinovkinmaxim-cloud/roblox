--[[
	EnemyModels - builds the client-side enemy models from parts (no assets needed).

	Every model is one ANCHORED root part plus unanchored, massless parts welded to it, so the
	renderer moves a whole enemy with a single CFrame (workspace:BulkMoveTo over the roots).
	Nothing collides, casts shadows or can be queried: they are pure visuals.

	ONE FAMILY STYLE: few shapes, a strong silhouette first (every enemy reads as a different
	SHAPE from the top-down run camera), colour second (2-3 colours + one accent, each kind
	keeps its colours: green goobers, red skitters, black-and-orange bombers...). Smooth
	plastic everywhere; neon only for eyes, cores and weak points. Googly eyes. Red / orange
	belong to the telegraphs (the INFERNO kinds are dark with yellow-white embers). Nothing big
	on the top of a model (no capes, no big wings) hides the fight from the camera.
	Budget: a horde enemy 5-10 parts, an elite +4 (ring + crest), a lair boss up to ~50, a
	main boss up to ~80 (they also carry a "67" and change their look with every phase).

	EnemyModels.Build(def, variant) -> model, root, info { Height, Top, BodyColor, Scale, Parts, Float }
	variant: "" | "t" (tiny) | "g" (golden) | "G" (giant, 67 MODE) | "e" (elite) | "s" (sketch)

	Parts can be tagged (attributes) to change with the enemy's state:
	  ShowIn / HideIn = EState   only / never in that state (a Snoozer's eyelids, a shield)
	  Phase / PhaseHide = n      shown / hidden from boss phase n on (main bosses)
	Eggs and ellipsoids are blocks with a Sphere mesh (a ball part is always round).
	EnemyModels.Toggle(item, state), SetPhase(item, n), DressAffixes(item, keys) (an elite's
	affixes: spikes, a shield ring, red eyes, gold...) and Reset(item) (back to the pooled look)
	are used by Controllers/EnemyRenderer.
]]

local EnemyModels = {}

local rgb = Color3.fromRGB
local WHITE = rgb(255, 255, 255)
local BLACK = rgb(20, 20, 25)
local SKIN = rgb(234, 190, 150)
local GOLD = rgb(255, 205, 60)
local FACE = "rbxasset://textures/face.png"
local NEON = Enum.Material.Neon
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder lying flat (axis up)
local FRONT = CFrame.Angles(0, math.pi / 2, 0) -- a cylinder facing -Z (axis along Z)
local TAU = math.pi * 2

local rng = Random.new()

type Builder = {
	Model: Model,
	Root: BasePart?,
	Scale: number,
	Parts: { BasePart },
	Anims: { any }, -- parts on a Motor6D that Render/EnemyAnimator moves (anim)
	Regrow: boolean?, -- its "Broken" parts come back (an Obsidian Crab's shell)
}

local function newPart(b: Builder, name: string, size: Vector3, color: Color3, offset: CFrame, shape: Enum.PartType?, material: Enum.Material?, className: string?): BasePart
	local p = Instance.new(className or "Part") :: any
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

-- shorthands: a ball (size: number = round; a Vector3 = an egg / ellipsoid: a ball part is
-- always round, a Sphere mesh fills the part's box), a box, a flat disc on the ground
local function ball(b: Builder, name: string, size: Vector3 | number, color: Color3, pos: Vector3, material: Enum.Material?): BasePart
	if typeof(size) == "number" or (size.X == size.Y and size.Y == size.Z) then
		local d = if typeof(size) == "number" then size else size.X
		return newPart(b, name, Vector3.new(d, d, d), color, CFrame.new(pos), BALL, material)
	end
	local p = newPart(b, name, size, color, CFrame.new(pos), nil, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function box(b: Builder, name: string, size: Vector3, color: Color3, cf: CFrame, material: Enum.Material?): BasePart
	return newPart(b, name, size, color, cf, nil, material)
end

-- a cylinder `length` long along cf's X axis
local function cyl(b: Builder, name: string, length: number, diameter: number, color: Color3, cf: CFrame, material: Enum.Material?): BasePart
	return newPart(b, name, Vector3.new(length, diameter, diameter), color, cf, CYL, material)
end

-- a flat disc lying on (or floating above) the ground, centred at pos
local function disc(b: Builder, name: string, diameter: number, thickness: number, color: Color3, pos: Vector3, material: Enum.Material?): BasePart
	return cyl(b, name, thickness, diameter, color, CFrame.new(pos) * FLAT, material)
end

-- a wedge (WedgePart): the slope runs from the top of its back (+Z) down to the bottom of its
-- front (-Z); horns, fangs, ears, flames, wings
local function wedge(b: Builder, name: string, size: Vector3, color: Color3, cf: CFrame, material: Enum.Material?): BasePart
	return newPart(b, name, size, color, cf, nil, material, "WedgePart")
end

local function tag(p: BasePart, attribute: string, value: number): BasePart
	p:SetAttribute(attribute, value)
	return p
end

-- a part that moves on its own (Render/EnemyAnimator.lua): its weld becomes a Motor6D whose C0
-- the animator offsets every frame. kind: Flap (rolls round its own Z: wings), Sway (pitches
-- round its own X: capes, arms, tails), Jaw (opens downwards), Spin (turns round Y), Orbit
-- (circles the root round Y), Bob (up and down), Pulse (neon brightens), Jitter (shakes)
local function anim(b: Builder, p: BasePart, kind: string, amp: number, freq: number, phase: number?): BasePart
	local root = b.Root :: BasePart
	local weld = p:FindFirstChildOfClass("WeldConstraint")
	if weld then
		weld:Destroy()
	end
	local m = Instance.new("Motor6D")
	m.Name = "Anim"
	m.Part0 = root
	m.Part1 = p
	m.C0 = root.CFrame:ToObjectSpace(p.CFrame)
	m.Parent = p
	table.insert(b.Anims, { Motor = m, Part = p, Base = m.C0, Kind = kind, Amp = amp, Freq = freq, Phase = phase or 0, Color = p.Color })
	return p
end

-- a big "6" or "7" painted on one face of a part (the 67 mark): u, v = the centre of the text on
-- the face (0..1), size = its share of the face
local function mark(part: BasePart, text: string, color: Color3, face: Enum.NormalId, u: number?, v: number?, size: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Mark"
	gui.Face = face
	gui.LightInfluence = 0
	gui.CanvasSize = Vector2.new(100, 100)
	gui.Parent = part
	local k = size or 0.5
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(u or 0.5, v or 0.5)
	label.Size = UDim2.fromScale(k, k)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color
	label.Parent = gui
end

-- big cartoon eyes: a white oval, a black pupil and a small white highlight (the heroes' eyes)
local function cartoonEyes(b: Builder, size: number, spread: number, y: number, z: number, x: number?, highlight: boolean?)
	local cx = x or 0
	for _, side in { -1, 1 } do
		local ex = cx + side * spread
		ball(b, "Eye", Vector3.new(size * 0.82, size, size * 0.45), WHITE, Vector3.new(ex, y, z))
		ball(b, "Pupil", size * 0.46, BLACK, Vector3.new(ex + side * size * 0.06, y - size * 0.06, z - size * 0.16))
		if highlight ~= false then
			ball(b, "Shine", size * 0.17, WHITE, Vector3.new(ex + side * size * 0.06 + size * 0.1, y + size * 0.08, z - size * 0.36))
		end
	end
end

-- two glowing ovals (neon eyes)
local function glowEyes(b: Builder, size: Vector3, spread: number, y: number, z: number, color: Color3, x: number?)
	for _, side in { -1, 1 } do
		ball(b, "Eye", size, color, Vector3.new((x or 0) + side * spread, y, z), NEON)
	end
end

local function googlyEyes(b: Builder, size: number, spread: number, y: number, z: number, x: number?)
	local cx = x or 0
	for _, side in { -1, 1 } do
		ball(b, "Eye", size, WHITE, Vector3.new(cx + side * spread, y, z))
		-- pupils look in random directions
		local px = rng:NextNumber(-0.22, 0.22) * size
		local py = rng:NextNumber(-0.22, 0.22) * size
		ball(b, "Pupil", size * 0.48, BLACK, Vector3.new(cx + side * spread + px, y + py, z - size * 0.36))
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
	gui.Name = "Sign"
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

-- text painted on a face of a part ("?" on a loot box, "67" on a chest plate)
local function paint(part: BasePart, text: string, color: Color3, faces: { Enum.NormalId })
	for _, f in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Face = f
		gui.LightInfluence = 0
		gui.CanvasSize = Vector2.new(100, 100)
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.Font = Enum.Font.LuckiestGuy
		label.TextColor3 = color
		label.Parent = gui
	end
end

local STYLES = {}

---------------------------------------------------------------------------- the horde
-- Goober: a round blob with a sprout on top (the face of the horde)
function STYLES.Blob(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", Vector3.new(2.7, 2.2, 2.6), c, Vector3.zero)
	ball(b, "Belly", Vector3.new(1.8, 1.3, 1.2), c:Lerp(WHITE, 0.35), Vector3.new(0, -0.35, -0.75))
	googlyEyes(b, 0.95, 0.55, 0.45, -0.95)
	box(b, "Mouth", Vector3.new(0.7, 0.14, 0.12), a:Lerp(BLACK, 0.6), CFrame.new(0, -0.3, -1.24))
	ball(b, "Sprout", Vector3.new(0.7, 0.35, 0.5), a, Vector3.new(0.25, 1.15, 0.1))
	return 1.1
end

-- Skitter: flat red bug, a black head, three leg bars (six legs from above)
function STYLES.Bug(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", Vector3.new(1.7, 0.8, 2.0), c, Vector3.zero)
	ball(b, "Head", Vector3.new(1.0, 0.75, 0.85), a, Vector3.new(0, 0.1, -1.1))
	for i = -1, 1 do
		box(b, "Legs", Vector3.new(2.7, 0.14, 0.16), a, CFrame.new(0, -0.25, i * 0.55) * CFrame.Angles(0, i * 0.25, 0))
	end
	box(b, "Antennae", Vector3.new(1.2, 0.1, 0.1), a, CFrame.new(0, 0.45, -1.55) * CFrame.Angles(0, 0, 0))
	googlyEyes(b, 0.42, 0.24, 0.32, -1.42)
	return 0.55
end

-- Husk: the blank blocky stranger, arms out like a sleepwalker
function STYLES.Npc(b: Builder, c: Color3, a: Color3): number
	box(b, "Torso", Vector3.new(1.8, 1.6, 0.9), a, CFrame.new())
	box(b, "Legs", Vector3.new(1.8, 1.6, 0.9), rgb(60, 62, 70), CFrame.new(0, -1.6, 0))
	box(b, "ArmL", Vector3.new(0.8, 0.8, 1.8), c, CFrame.new(-1.3, 0.35, -0.6))
	box(b, "ArmR", Vector3.new(0.8, 0.8, 1.8), c, CFrame.new(1.3, 0.35, -0.6))
	local head = box(b, "Head", Vector3.new(1.15, 1.15, 1.15), c, CFrame.new(0, 1.4, 0))
	face(head)
	return 2.4
end

-- Charger: a low bull, two white horns forward
function STYLES.Charger(b: Builder, c: Color3, a: Color3): number
	box(b, "Body", Vector3.new(2.4, 1.6, 2.6), c, CFrame.new())
	box(b, "Head", Vector3.new(1.7, 1.3, 1.1), c:Lerp(WHITE, 0.12), CFrame.new(0, 0.25, -1.65))
	box(b, "HornL", Vector3.new(0.35, 0.35, 1.3), WHITE, CFrame.new(-0.75, 0.75, -2.15) * CFrame.Angles(0.35, 0.3, 0))
	box(b, "HornR", Vector3.new(0.35, 0.35, 1.3), WHITE, CFrame.new(0.75, 0.75, -2.15) * CFrame.Angles(0.35, -0.3, 0))
	box(b, "LegsF", Vector3.new(2.0, 0.9, 0.5), a, CFrame.new(0, -1.1, -0.8))
	box(b, "LegsB", Vector3.new(2.0, 0.9, 0.5), a, CFrame.new(0, -1.1, 0.8))
	googlyEyes(b, 0.45, 0.42, 0.55, -2.2)
	return 1.55
end

-- Spitter: a swollen sac with a nozzle
function STYLES.Spitter(b: Builder, c: Color3, a: Color3): number
	ball(b, "Sac", 2.6, c, Vector3.zero)
	cyl(b, "Nozzle", 1.2, 0.85, a, CFrame.new(0, -0.1, -1.5) * FRONT)
	ball(b, "Spot", 0.7, a, Vector3.new(-0.75, 0.75, 0.55))
	ball(b, "Spot", 0.55, a, Vector3.new(0.7, 0.35, 0.85))
	box(b, "Legs", Vector3.new(1.6, 0.8, 0.4), a:Lerp(BLACK, 0.3), CFrame.new(0, -1.45, 0))
	googlyEyes(b, 0.6, 0.45, 0.9, -1.0)
	return 1.85
end

-- Splitter: two blobs glued together (a white seam where they split)
function STYLES.Splitter(b: Builder, c: Color3, a: Color3): number
	ball(b, "BodyL", Vector3.new(2.3, 2.2, 2.3), c, Vector3.new(-0.7, 0, 0))
	ball(b, "BodyR", Vector3.new(2.1, 2.0, 2.1), a, Vector3.new(0.8, -0.1, 0.1))
	box(b, "Seam", Vector3.new(0.14, 1.8, 1.8), WHITE, CFrame.new(0.1, 0, 0))
	googlyEyes(b, 0.7, 0.45, 0.4, -1.0, -0.7)
	return 1.1
end

-- Bomber: a walking bomb with a lit fuse
function STYLES.Bomber(b: Builder, c: Color3, a: Color3): number
	ball(b, "Bomb", 2.4, c, Vector3.zero)
	cyl(b, "Cap", 0.5, 0.9, rgb(90, 90, 100), CFrame.new(0, 1.25, 0) * FLAT)
	box(b, "Fuse", Vector3.new(0.15, 0.8, 0.15), rgb(200, 170, 120), CFrame.new(0.15, 1.8, 0) * CFrame.Angles(0, 0, -0.4))
	ball(b, "Spark", 0.45, a, Vector3.new(0.35, 2.2, 0), NEON)
	box(b, "BrowL", Vector3.new(0.6, 0.12, 0.1), WHITE, CFrame.new(-0.4, 0.55, -1.15) * CFrame.Angles(0, 0, -0.35))
	box(b, "BrowR", Vector3.new(0.6, 0.12, 0.1), WHITE, CFrame.new(0.4, 0.55, -1.15) * CFrame.Angles(0, 0, 0.35))
	box(b, "EyeL", Vector3.new(0.3, 0.3, 0.1), a, CFrame.new(-0.4, 0.3, -1.18), NEON)
	box(b, "EyeR", Vector3.new(0.3, 0.3, 0.1), a, CFrame.new(0.4, 0.3, -1.18), NEON)
	return 1.25
end

-- Blinker: a figure made of pixels, never quite in one place
function STYLES.Glitch(b: Builder, c: Color3, a: Color3): number
	box(b, "Torso", Vector3.new(1.8, 1.6, 0.9), c, CFrame.new())
	box(b, "Legs", Vector3.new(1.8, 1.4, 0.9), a, CFrame.new(0, -1.5, 0))
	for i, off in { Vector2.new(-0.3, 0.3), Vector2.new(0.3, 0.3), Vector2.new(-0.3, -0.3), Vector2.new(0.3, -0.3) } do
		box(b, "Pixel", Vector3.new(0.62, 0.62, 1.1), if i == 1 or i == 4 then c else a, CFrame.new(off.X, 1.45 + off.Y, 0))
	end
	box(b, "Echo", Vector3.new(1.0, 0.6, 0.6), a, CFrame.new(1.25, 0.6, 0.3))
	box(b, "Eye", Vector3.new(0.5, 0.22, 0.1), WHITE, CFrame.new(0.15, 1.6, -0.58), NEON)
	return 2.3
end

-- Brute: a wall of muscle with pads and fists
function STYLES.Brute(b: Builder, c: Color3, a: Color3): number
	box(b, "Body", Vector3.new(3.6, 3.2, 2.4), c, CFrame.new())
	box(b, "Legs", Vector3.new(2.8, 1.6, 1.8), a, CFrame.new(0, -2.4, 0))
	box(b, "PadL", Vector3.new(1.4, 1, 2.6), a, CFrame.new(-2.3, 1.3, 0))
	box(b, "PadR", Vector3.new(1.4, 1, 2.6), a, CFrame.new(2.3, 1.3, 0))
	ball(b, "FistL", 1.6, a:Lerp(WHITE, 0.2), Vector3.new(-2.4, -0.9, -0.4))
	ball(b, "FistR", 1.6, a:Lerp(WHITE, 0.2), Vector3.new(2.4, -0.9, -0.4))
	local head = box(b, "Head", Vector3.new(1.4, 1.4, 1.4), SKIN, CFrame.new(0, 2.3, -0.2))
	face(head)
	return 3.2
end

-- Diver: a round bird with flat wings and a yellow beak; flies
function STYLES.Diver(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", Vector3.new(1.5, 1.3, 2.0), c, Vector3.zero)
	box(b, "WingL", Vector3.new(2.2, 0.18, 1.2), c:Lerp(BLACK, 0.2), CFrame.new(-1.6, 0.3, 0.15) * CFrame.Angles(0, 0, 0.25))
	box(b, "WingR", Vector3.new(2.2, 0.18, 1.2), c:Lerp(BLACK, 0.2), CFrame.new(1.6, 0.3, 0.15) * CFrame.Angles(0, 0, -0.25))
	box(b, "Beak", Vector3.new(0.45, 0.4, 0.9), a, CFrame.new(0, -0.05, -1.35))
	googlyEyes(b, 0.48, 0.32, 0.32, -0.85)
	return 3.2
end

-- Summoner: a tall hooded robe with a glowing orb on a staff
function STYLES.Summoner(b: Builder, c: Color3, a: Color3): number
	ball(b, "Robe", Vector3.new(2.2, 3.2, 2.2), c, Vector3.zero)
	ball(b, "Hood", 1.7, c:Lerp(BLACK, 0.3), Vector3.new(0, 1.9, 0))
	box(b, "EyeL", Vector3.new(0.25, 0.25, 0.1), a, CFrame.new(-0.3, 1.9, -0.82), NEON)
	box(b, "EyeR", Vector3.new(0.25, 0.25, 0.1), a, CFrame.new(0.3, 1.9, -0.82), NEON)
	box(b, "Staff", Vector3.new(0.2, 3.6, 0.2), rgb(90, 70, 50), CFrame.new(1.3, 0.4, -0.3))
	ball(b, "Orb", 0.9, a, Vector3.new(1.3, 2.4, -0.3), NEON)
	return 1.7
end

-- Ghost: a floating sheet
function STYLES.Ghost(b: Builder, c: Color3, a: Color3): number
	ball(b, "Sheet", Vector3.new(2.2, 2.6, 2.2), c, Vector3.zero)
	cyl(b, "Hem", 0.4, 2.3, c:Lerp(a, 0.25), CFrame.new(0, -1.05, 0) * FLAT)
	box(b, "EyeL", Vector3.new(0.4, 0.6, 0.1), BLACK, CFrame.new(-0.4, 0.3, -1.05))
	box(b, "EyeR", Vector3.new(0.4, 0.6, 0.1), BLACK, CFrame.new(0.4, 0.3, -1.05))
	ball(b, "Mouth", Vector3.new(0.45, 0.45, 0.1), BLACK, Vector3.new(0, -0.35, -1.05))
	for _, p in b.Parts do
		p.Transparency = 0.2
	end
	return 2.2
end

-- Leaper: a frog with huge back legs
function STYLES.Leaper(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", Vector3.new(2.8, 1.6, 2.6), c, Vector3.zero)
	ball(b, "Belly", Vector3.new(2.0, 1.0, 1.6), a, Vector3.new(0, -0.35, -0.6))
	box(b, "LegL", Vector3.new(0.9, 1.0, 2.0), c:Lerp(BLACK, 0.2), CFrame.new(-1.45, -0.4, 0.8))
	box(b, "LegR", Vector3.new(0.9, 1.0, 2.0), c:Lerp(BLACK, 0.2), CFrame.new(1.45, -0.4, 0.8))
	googlyEyes(b, 0.9, 0.7, 0.9, -0.6)
	return 1.0
end

-- Mimic: a loot box... with teeth (look closely)
function STYLES.Mimic(b: Builder, c: Color3, a: Color3): number
	local chest = box(b, "Box", Vector3.new(2.8, 2.8, 2.8), c, CFrame.new())
	box(b, "Band", Vector3.new(2.95, 0.45, 2.95), a, CFrame.new(0, 0.1, 0))
	for i = -1, 1 do
		box(b, "Tooth", Vector3.new(0.35, 0.4, 0.2), WHITE, CFrame.new(i * 0.7, -0.25, -1.45) * CFrame.Angles(0, 0, math.pi / 4))
	end
	paint(chest, "?", a, { Enum.NormalId.Top })
	return 1.4
end

-- Sniper: tall and thin, a long rifle and a red eye
function STYLES.Sniper(b: Builder, c: Color3, a: Color3): number
	box(b, "Body", Vector3.new(1.1, 3.0, 0.9), c, CFrame.new())
	box(b, "Head", Vector3.new(0.9, 0.9, 0.9), c:Lerp(WHITE, 0.15), CFrame.new(0, 1.95, 0))
	box(b, "Cap", Vector3.new(1.1, 0.2, 1.3), c:Lerp(BLACK, 0.3), CFrame.new(0, 2.45, -0.15))
	box(b, "Eye", Vector3.new(0.5, 0.25, 0.1), a, CFrame.new(0, 2.0, -0.48), NEON)
	box(b, "Rifle", Vector3.new(0.25, 0.25, 3.2), rgb(40, 40, 45), CFrame.new(0.65, 0.6, -1.2))
	ball(b, "Scope", 0.3, a, Vector3.new(0.65, 0.85, -1.6), NEON)
	return 2.4
end

-- 67 Goblin: a gold-and-green imp with a sack of coins
function STYLES.Goblin(b: Builder, c: Color3, a: Color3): number
	local body = ball(b, "Body", 1.8, c, Vector3.zero)
	box(b, "EarL", Vector3.new(0.3, 0.9, 0.6), c, CFrame.new(-1.0, 0.5, 0) * CFrame.Angles(0, 0, 0.6))
	box(b, "EarR", Vector3.new(0.3, 0.9, 0.6), c, CFrame.new(1.0, 0.5, 0) * CFrame.Angles(0, 0, -0.6))
	ball(b, "Sack", 1.3, a, Vector3.new(0.9, 0.3, 0.8))
	googlyEyes(b, 0.55, 0.35, 0.3, -0.7)
	billboard(body, "67", GOLD, 3, 2.2)
	return 1.0
end

-- THE 67: a golden core with two tilted rings and a huge "67"
function STYLES.The67(b: Builder, c: Color3, a: Color3): number
	local core = ball(b, "Core", 3.4, c, Vector3.zero, NEON)
	cyl(b, "Ring", 0.3, 6, a, CFrame.new() * CFrame.Angles(0.4, 0, math.pi / 2))
	cyl(b, "Ring2", 0.3, 5, c:Lerp(WHITE, 0.3), CFrame.new() * CFrame.Angles(-0.6, 0.5, math.pi / 2))
	billboard(core, "67", rgb(255, 230, 90), 7, 3.2)
	return 4.2
end

function STYLES.Crate(b: Builder, c: Color3, a: Color3): number
	local crate = box(b, "Box", Vector3.new(2.8, 2.8, 2.8), c, CFrame.new())
	box(b, "Band", Vector3.new(2.95, 0.5, 2.95), a, CFrame.new())
	paint(crate, "?", a, { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Top })
	return 1.4
end

---------------------------------------------------------------------------- the horde of the harder tiers
-- Snoozer: a sleepy blob in a nightcap; eyelids while it sleeps, googly eyes when it wakes
function STYLES.Snoozer(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", Vector3.new(2.6, 2.0, 2.5), c, Vector3.zero)
	ball(b, "Belly", Vector3.new(1.7, 1.1, 1.1), c:Lerp(WHITE, 0.35), Vector3.new(0, -0.35, -0.75))
	box(b, "Cap", Vector3.new(0.9, 1.2, 0.9), a, CFrame.new(0.3, 1.15, 0.1) * CFrame.Angles(0, 0, -0.6))
	ball(b, "Pompom", 0.5, WHITE, Vector3.new(0.85, 1.55, 0.1))
	local ES_DORMANT = 5
	for _, side in { -1, 1 } do
		tag(box(b, "Lid", Vector3.new(0.7, 0.14, 0.12), a, CFrame.new(side * 0.5, 0.4, -1.13)), "ShowIn", ES_DORMANT)
	end
	googlyEyes(b, 0.85, 0.5, 0.4, -0.9)
	for i = #b.Parts - 3, #b.Parts do
		tag(b.Parts[i], "HideIn", ES_DORMANT)
	end
	return 1.0
end

-- Shielder: a compact soldier behind a tall white tower shield (the shield breaks off)
function STYLES.Shielder(b: Builder, c: Color3, a: Color3): number
	box(b, "Body", Vector3.new(2.0, 2.2, 1.6), c, CFrame.new())
	box(b, "Helmet", Vector3.new(1.5, 1.0, 1.4), c:Lerp(BLACK, 0.25), CFrame.new(0, 1.55, 0.1))
	box(b, "Feet", Vector3.new(1.8, 0.6, 1.2), c:Lerp(BLACK, 0.4), CFrame.new(0, -1.35, 0))
	local ES_BROKEN = 8
	tag(box(b, "Shield", Vector3.new(2.9, 3.1, 0.4), a, CFrame.new(0, 0.1, -1.25)), "HideIn", ES_BROKEN)
	tag(box(b, "Emblem", Vector3.new(0.5, 2.2, 0.1), c, CFrame.new(0, 0.1, -1.5)), "HideIn", ES_BROKEN)
	googlyEyes(b, 0.5, 0.32, 1.55, -0.65)
	return 1.65
end

-- Stampeder: a hunched bison with cream horns, built to run straight
function STYLES.Stampeder(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", Vector3.new(2.3, 1.9, 3.0), c, Vector3.zero)
	box(b, "Head", Vector3.new(1.4, 1.2, 1.1), c:Lerp(BLACK, 0.35), CFrame.new(0, -0.05, -1.65))
	box(b, "HornL", Vector3.new(1.0, 0.3, 0.3), a, CFrame.new(-0.95, 0.45, -1.7) * CFrame.Angles(0, 0, 0.6))
	box(b, "HornR", Vector3.new(1.0, 0.3, 0.3), a, CFrame.new(0.95, 0.45, -1.7) * CFrame.Angles(0, 0, -0.6))
	box(b, "LegsF", Vector3.new(1.7, 0.8, 0.5), c:Lerp(BLACK, 0.45), CFrame.new(0, -1.05, -0.8))
	box(b, "LegsB", Vector3.new(1.7, 0.8, 0.5), c:Lerp(BLACK, 0.45), CFrame.new(0, -1.05, 0.9))
	googlyEyes(b, 0.4, 0.38, 0.2, -2.15)
	return 1.4
end

-- Bannerman: a robed horn-blower with a banner held high, its rally ring on the ground
function STYLES.Bannerman(b: Builder, c: Color3, a: Color3): number
	ball(b, "Robe", Vector3.new(2.0, 2.6, 2.0), c, Vector3.zero)
	ball(b, "Head", 1.3, SKIN, Vector3.new(0, 1.65, 0))
	box(b, "Pole", Vector3.new(0.2, 5.2, 0.2), rgb(110, 80, 50), CFrame.new(1.15, 1.6, 0.3))
	box(b, "Flag", Vector3.new(0.12, 1.6, 2.0), c:Lerp(WHITE, 0.15), CFrame.new(1.15, 3.35, 1.25))
	box(b, "Stripe", Vector3.new(0.14, 0.35, 2.0), a, CFrame.new(1.15, 3.35, 1.25))
	local ring = disc(b, "RallyRing", 24, 0.08, a, Vector3.new(0, -1.25, 0))
	ring.Transparency = 0.86
	googlyEyes(b, 0.5, 0.3, 1.75, -0.55)
	return 1.3
end

-- Wailer: a pale banshee, mouth wide open
function STYLES.Wailer(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", Vector3.new(2.0, 2.8, 1.9), c, Vector3.zero)
	cyl(b, "Hem", 0.35, 2.0, c:Lerp(a, 0.2), CFrame.new(0, -1.25, 0) * FLAT)
	ball(b, "Mouth", Vector3.new(0.85, 1.1, 0.35), a:Lerp(BLACK, 0.6), Vector3.new(0, -0.15, -0.88))
	box(b, "ArmL", Vector3.new(1.3, 0.3, 0.3), c, CFrame.new(-1.15, 0.35, -0.2) * CFrame.Angles(0, 0, 0.7))
	box(b, "ArmR", Vector3.new(1.3, 0.3, 0.3), c, CFrame.new(1.15, 0.35, -0.2) * CFrame.Angles(0, 0, -0.7))
	googlyEyes(b, 0.55, 0.34, 0.75, -0.8)
	for _, p in b.Parts do
		if p.Name ~= "Eye" and p.Name ~= "Pupil" then
			p.Transparency = 0.15
		end
	end
	return 2.0
end

-- Hexer: a little hooded caster with a pointed hood and a hex gem on its staff
function STYLES.Hexer(b: Builder, c: Color3, a: Color3): number
	ball(b, "Robe", Vector3.new(2.0, 2.4, 2.0), c, Vector3.zero)
	ball(b, "Hood", 1.5, c:Lerp(BLACK, 0.3), Vector3.new(0, 1.45, 0))
	box(b, "HoodTip", Vector3.new(0.6, 1.2, 0.6), c:Lerp(BLACK, 0.3), CFrame.new(0, 2.35, 0.25) * CFrame.Angles(0.5, 0, 0))
	box(b, "EyeL", Vector3.new(0.25, 0.2, 0.1), a, CFrame.new(-0.25, 1.45, -0.74), NEON)
	box(b, "EyeR", Vector3.new(0.25, 0.2, 0.1), a, CFrame.new(0.25, 1.45, -0.74), NEON)
	box(b, "Staff", Vector3.new(0.18, 3.0, 0.18), rgb(70, 60, 50), CFrame.new(1.15, 0.5, -0.3))
	box(b, "Gem", Vector3.new(0.6, 0.6, 0.6), a, CFrame.new(1.15, 2.1, -0.3) * CFrame.Angles(0, math.pi / 4, math.pi / 4), NEON)
	return 1.2
end

-- Cinder: a walking ember: charcoal, glowing cracks, a little flame on top
function STYLES.Cinder(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", Vector3.new(2.2, 2.0, 2.1), c, Vector3.zero)
	box(b, "Crack", Vector3.new(0.14, 1.2, 0.14), a, CFrame.new(-0.6, -0.1, -0.85) * CFrame.Angles(0, 0, 0.5), NEON)
	box(b, "Crack", Vector3.new(0.14, 0.9, 0.14), a, CFrame.new(0.7, 0.3, -0.75) * CFrame.Angles(0, 0, -0.6), NEON)
	ball(b, "Flame", Vector3.new(0.8, 1.1, 0.8), a, Vector3.new(0, 1.2, 0.1), NEON)
	googlyEyes(b, 0.6, 0.38, 0.35, -0.85)
	return 1.0
end

-- Eruptor: a squat little volcano with lava in its crater
function STYLES.Eruptor(b: Builder, c: Color3, a: Color3): number
	ball(b, "Mound", Vector3.new(3.6, 2.6, 3.6), c, Vector3.zero)
	cyl(b, "Base", 1.0, 3.8, c:Lerp(BLACK, 0.2), CFrame.new(0, -0.8, 0) * FLAT)
	cyl(b, "Crater", 0.5, 2.0, c:Lerp(BLACK, 0.4), CFrame.new(0, 1.2, 0) * FLAT)
	disc(b, "Lava", 1.8, 0.2, a, Vector3.new(0, 1.42, 0), NEON)
	box(b, "Feet", Vector3.new(2.6, 0.5, 1.2), c:Lerp(BLACK, 0.3), CFrame.new(0, -1.15, -0.2))
	googlyEyes(b, 0.65, 0.48, 0.2, -1.55)
	return 1.35
end

-- Predator: a lean graphite stalker, low to the ground, two cold cyan eyes
function STYLES.Predator(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", Vector3.new(1.6, 1.2, 3.0), c, Vector3.zero)
	box(b, "Head", Vector3.new(1.1, 0.8, 1.1), c:Lerp(BLACK, 0.2), CFrame.new(0, 0.2, -1.75))
	box(b, "Snout", Vector3.new(0.7, 0.45, 0.6), c:Lerp(BLACK, 0.35), CFrame.new(0, 0.05, -2.45))
	box(b, "LegsF", Vector3.new(1.6, 0.9, 0.4), c:Lerp(BLACK, 0.4), CFrame.new(0, -0.75, -0.85))
	box(b, "LegsB", Vector3.new(1.6, 0.9, 0.4), c:Lerp(BLACK, 0.4), CFrame.new(0, -0.75, 0.9))
	box(b, "Stripe", Vector3.new(1.3, 0.12, 0.3), WHITE, CFrame.new(0, 0.6, -0.2))
	box(b, "Stripe", Vector3.new(1.2, 0.12, 0.3), WHITE, CFrame.new(0, 0.55, 0.5))
	box(b, "EyeL", Vector3.new(0.28, 0.16, 0.1), a, CFrame.new(-0.3, 0.38, -2.31), NEON)
	box(b, "EyeR", Vector3.new(0.28, 0.16, 0.1), a, CFrame.new(0.3, 0.38, -2.31), NEON)
	return 1.25
end

-- Warden: a white guardian with a blue heart; its bubble is the ring on the ground
function STYLES.Warden(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", Vector3.new(2.6, 3.0, 2.3), c, Vector3.zero)
	ball(b, "Dome", 1.5, c:Lerp(a, 0.15), Vector3.new(0, 1.8, 0))
	ball(b, "PadL", 1.1, a:Lerp(c, 0.4), Vector3.new(-1.35, 0.8, 0))
	ball(b, "PadR", 1.1, a:Lerp(c, 0.4), Vector3.new(1.35, 0.8, 0))
	box(b, "Heart", Vector3.new(0.6, 0.6, 0.2), a, CFrame.new(0, 0.2, -1.1) * CFrame.Angles(0, 0, math.pi / 4), NEON)
	local bubble = disc(b, "Bubble", 18, 0.08, a, Vector3.new(0, -1.45, 0))
	bubble.Transparency = 0.8
	googlyEyes(b, 0.5, 0.3, 1.85, -0.6)
	return 1.5
end

-- SIXLET / SEVENLET: little seven-segment digits with googly eyes
local function smallDigit(b: Builder, ch: string, c: Color3, a: Color3): number
	local s, t, depth = 1.5, 0.6, 0.9
	local spots = {
		g = { 0, 0, true },
		a = { 0, s, true },
		d = { 0, -s, true },
		b = { -s / 2, s / 2, false },
		c = { -s / 2, -s / 2, false },
		e = { s / 2, -s / 2, false },
		f = { s / 2, s / 2, false },
	}
	local order = if ch == "6" then { "g", "a", "f", "e", "d", "c" } else { "a", "b", "c" }
	local shift = -spots[order[1]][2]
	for _, seg in order do
		local spot = spots[seg]
		local size = if spot[3] then Vector3.new(s + t, t, depth) else Vector3.new(t, s, depth)
		box(b, "Seg" .. seg, size, c, CFrame.new(spot[1], spot[2] + shift, 0))
	end
	googlyEyes(b, 0.55, 0.36, s + shift + 0.05, -0.5)
	if ch == "7" then
		box(b, "Foot", Vector3.new(1.2, 0.35, 0.9), a, CFrame.new(-s / 2, -s - t / 2 - 0.15 + shift, 0))
	end
	return s + t / 2 + (if ch == "7" then 0.35 else 0) - shift
end

function STYLES.Sixlet(b: Builder, c: Color3, a: Color3): number
	return smallDigit(b, "6", c, a)
end

function STYLES.Sevenlet(b: Builder, c: Color3, a: Color3): number
	return smallDigit(b, "7", c, a)
end

---------------------------------------------------------------------------- boss minions
-- Crow: a round black bird with a yellow beak (THE SCARECROW's)
function STYLES.Crow(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", Vector3.new(1.2, 1.1, 1.6), c, Vector3.zero)
	box(b, "WingL", Vector3.new(1.5, 0.14, 0.9), c:Lerp(WHITE, 0.08), CFrame.new(-1.05, 0.2, 0.1) * CFrame.Angles(0, 0, 0.3))
	box(b, "WingR", Vector3.new(1.5, 0.14, 0.9), c:Lerp(WHITE, 0.08), CFrame.new(1.05, 0.2, 0.1) * CFrame.Angles(0, 0, -0.3))
	box(b, "Beak", Vector3.new(0.35, 0.3, 0.7), a, CFrame.new(0, -0.05, -1.0))
	googlyEyes(b, 0.4, 0.25, 0.25, -0.65)
	return 3
end

-- a goo egg with pink spots (MAMA GOOBER's nest)
function STYLES.GooEgg(b: Builder, c: Color3, a: Color3): number
	ball(b, "Egg", Vector3.new(2.2, 2.9, 2.2), c, Vector3.zero)
	ball(b, "Spot", 0.7, a, Vector3.new(-0.6, 0.6, -0.75))
	ball(b, "Spot", 0.55, a, Vector3.new(0.7, -0.1, -0.8))
	ball(b, "Spot", 0.6, a, Vector3.new(0.1, 0.9, 0.85))
	disc(b, "Nest", 3.0, 0.5, rgb(140, 100, 60), Vector3.new(0, -1.25, 0))
	return 1.45
end

-- THE HORDEMASTER's war banner on a pole, its rally ring on the ground
function STYLES.WarBanner(b: Builder, c: Color3, a: Color3): number
	box(b, "Base", Vector3.new(2.4, 0.8, 2.4), rgb(70, 60, 55), CFrame.new())
	box(b, "Pole", Vector3.new(0.35, 7.5, 0.35), rgb(110, 80, 50), CFrame.new(0, 4.1, 0))
	box(b, "Flag", Vector3.new(0.15, 2.6, 3.0), c, CFrame.new(0, 6.3, 1.55))
	box(b, "Stripe", Vector3.new(0.17, 0.5, 3.0), a, CFrame.new(0, 6.3, 1.55))
	ball(b, "Finial", 0.8, a, Vector3.new(0, 8.0, 0), NEON)
	local ring = disc(b, "RallyRing", 44, 0.08, a, Vector3.new(0, -0.35, 0))
	ring.Transparency = 0.85
	return 0.4
end

---------------------------------------------------------------------------- classic bosses
-- THE GIANT: a stone giant, huge fists, moss on the shoulders, a glowing crack in each fist
function STYLES.Giant(b: Builder, c: Color3, a: Color3): number
	box(b, "Torso", Vector3.new(6, 5.5, 3.6), c, CFrame.new())
	box(b, "Belt", Vector3.new(6.2, 1, 3.8), a, CFrame.new(0, -2.4, 0))
	box(b, "LegL", Vector3.new(2.3, 3.6, 2.8), a, CFrame.new(-1.35, -4.6, 0))
	box(b, "LegR", Vector3.new(2.3, 3.6, 2.8), a, CFrame.new(1.35, -4.6, 0))
	box(b, "ArmL", Vector3.new(1.9, 5, 2.1), c, CFrame.new(-4.05, -0.2, 0))
	box(b, "ArmR", Vector3.new(1.9, 5, 2.1), c, CFrame.new(4.05, -0.2, 0))
	ball(b, "FistL", 3.2, a:Lerp(c, 0.3), Vector3.new(-4.1, -3.3, -0.3))
	ball(b, "FistR", 3.2, a:Lerp(c, 0.3), Vector3.new(4.1, -3.3, -0.3))
	box(b, "CrackL", Vector3.new(0.3, 1.6, 0.3), GOLD, CFrame.new(-4.1, -3.3, -1.75) * CFrame.Angles(0, 0, 0.5), NEON)
	box(b, "CrackR", Vector3.new(0.3, 1.6, 0.3), GOLD, CFrame.new(4.1, -3.3, -1.75) * CFrame.Angles(0, 0, -0.5), NEON)
	ball(b, "MossL", Vector3.new(2.2, 0.8, 2.6), rgb(110, 160, 80), Vector3.new(-2.8, 2.75, 0.3))
	ball(b, "MossR", Vector3.new(1.8, 0.7, 2.2), rgb(110, 160, 80), Vector3.new(2.9, 2.75, 0.5))
	local head = box(b, "Head", Vector3.new(2.6, 2.6, 2.6), c:Lerp(WHITE, 0.15), CFrame.new(0, 4.1, 0))
	box(b, "Brow", Vector3.new(2.7, 0.5, 0.4), a, CFrame.new(0, 4.75, -1.3))
	face(head)
	return 6.4
end

-- THE GOOBER: the biggest blob, spotted, an antenna with a glowing ball
function STYLES.GooberBoss(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", Vector3.new(9, 8, 9), c, Vector3.zero)
	ball(b, "Belly", Vector3.new(6, 4.6, 3), c:Lerp(WHITE, 0.3), Vector3.new(0, -1.4, -3.3))
	for _, off in { Vector3.new(-2.6, 2.4, -2.4), Vector3.new(3, 1.2, -2.2), Vector3.new(-3.4, -0.6, 1.5), Vector3.new(2.2, 3, 2) } do
		ball(b, "Spot", 1.6, a, off)
	end
	googlyEyes(b, 2.6, 1.6, 1.6, -3.5)
	box(b, "Mouth", Vector3.new(2.4, 0.4, 0.4), a:Lerp(BLACK, 0.5), CFrame.new(0, -0.6, -4.3))
	box(b, "Antenna", Vector3.new(0.3, 2.4, 0.3), a, CFrame.new(0, 4.8, 0))
	ball(b, "AntennaBall", 1.1, a, Vector3.new(0, 6.1, 0), NEON)
	return 4
end

-- THE GLITCH: a stack of offset pixel blocks, shards around, one white eye
function STYLES.GlitchBoss(b: Builder, c: Color3, a: Color3): number
	for i = 0, 4 do
		local w = 4.5 - i * 0.5
		box(b, "Block", Vector3.new(w, 1.6, w), if i % 2 == 0 then c else a, CFrame.new((i % 2) * 0.6 - 0.3, i * 1.7 - 2.5, 0))
	end
	for _, off in { Vector3.new(-3.2, 1, 0.8), Vector3.new(3, -1, -0.6), Vector3.new(2.4, 3, 1), Vector3.new(-2.6, -2.2, -1) } do
		box(b, "Shard", Vector3.new(1, 1, 1), a, CFrame.new(off) * CFrame.Angles(0.3, 0.5, 0.2))
	end
	box(b, "Eye", Vector3.new(2, 0.6, 0.2), WHITE, CFrame.new(0, 4.4, -1.1), NEON)
	box(b, "Pupil", Vector3.new(0.6, 0.6, 0.2), BLACK, CFrame.new(0.4, 4.4, -1.25))
	return 4.4
end

-- THE MACHINE: a box robot on treads, two cannons, a missile rack, a laser visor
function STYLES.Machine(b: Builder, c: Color3, a: Color3): number
	box(b, "Hull", Vector3.new(6, 4, 5), c, CFrame.new())
	box(b, "TreadL", Vector3.new(1.4, 1.8, 6), rgb(40, 40, 45), CFrame.new(-3.3, -2.6, 0))
	box(b, "TreadR", Vector3.new(1.4, 1.8, 6), rgb(40, 40, 45), CFrame.new(3.3, -2.6, 0))
	box(b, "Visor", Vector3.new(4, 0.8, 0.3), a, CFrame.new(0, 1, -2.6), NEON)
	cyl(b, "CannonL", 4, 1.2, rgb(70, 70, 80), CFrame.new(-3.6, 1.2, -1.2) * FRONT)
	cyl(b, "CannonR", 4, 1.2, rgb(70, 70, 80), CFrame.new(3.6, 1.2, -1.2) * FRONT)
	box(b, "Rack", Vector3.new(3.2, 1.4, 2.2), c:Lerp(BLACK, 0.3), CFrame.new(0, 2.7, 1.2))
	for i = -1, 1 do
		ball(b, "Missile", 0.6, a, Vector3.new(i * 0.95, 3.45, 1.2))
	end
	box(b, "Antenna", Vector3.new(0.3, 2.5, 0.3), rgb(70, 70, 80), CFrame.new(2.4, 3.2, 1.6))
	ball(b, "Light", 0.7, a, Vector3.new(2.4, 4.5, 1.6), NEON)
	return 3.5
end

-- THE VOID: a dark core, one huge eye, a ring of floating shards; floats
function STYLES.VoidBoss(b: Builder, c: Color3, a: Color3): number
	ball(b, "Core", 7, c, Vector3.zero)
	ball(b, "Eye", Vector3.new(3.4, 3.4, 1), WHITE, Vector3.new(0, 0.4, -3.1))
	ball(b, "Pupil", Vector3.new(1.6, 1.6, 0.6), a, Vector3.new(0, 0.4, -3.55), NEON)
	disc(b, "Halo", 10, 0.25, c:Lerp(a, 0.35), Vector3.new(0, -0.6, 0))
	for i = 0, 5 do
		local ang = i * math.pi / 3
		box(b, "Shard", Vector3.new(0.8, 2.2, 0.8), a:Lerp(c, 0.3), CFrame.new(math.cos(ang) * 5.4, math.sin(i) * 1.2, math.sin(ang) * 5.4) * CFrame.Angles(0.4, ang, 0.3))
	end
	return 6
end

-- THE OVERLORD: an armoured warlord with a tall crested helmet and a banner pole
function STYLES.Overlord(b: Builder, c: Color3, a: Color3): number
	box(b, "Torso", Vector3.new(4.4, 4, 2.2), c, CFrame.new())
	box(b, "Legs", Vector3.new(4.2, 3.6, 2), rgb(15, 15, 20), CFrame.new(0, -3.8, 0))
	box(b, "ArmL", Vector3.new(1.8, 4, 2), c, CFrame.new(-3.1, 0, 0))
	box(b, "ArmR", Vector3.new(1.8, 4, 2), c, CFrame.new(3.1, 0, 0))
	box(b, "PadL", Vector3.new(2.2, 0.9, 2.4), a, CFrame.new(-3.1, 2.2, 0))
	box(b, "PadR", Vector3.new(2.2, 0.9, 2.4), a, CFrame.new(3.1, 2.2, 0))
	box(b, "Head", Vector3.new(2.8, 2.8, 2.8), SKIN, CFrame.new(0, 3.4, 0))
	box(b, "Helmet", Vector3.new(3.0, 1.4, 3.0), c:Lerp(BLACK, 0.2), CFrame.new(0, 4.6, 0))
	box(b, "Crest", Vector3.new(0.5, 1.6, 2.6), a, CFrame.new(0, 5.8, 0.2))
	box(b, "Shades", Vector3.new(2.9, 0.7, 0.3), BLACK, CFrame.new(0, 3.7, -1.4))
	box(b, "Chain", Vector3.new(2.6, 0.5, 0.3), a, CFrame.new(0, 1.2, -1.2), NEON)
	box(b, "Pole", Vector3.new(0.4, 8, 0.4), rgb(70, 60, 50), CFrame.new(2.2, 2, 1.6))
	box(b, "Banner", Vector3.new(0.2, 2.2, 2.6), a:Lerp(BLACK, 0.3), CFrame.new(2.2, 4.8, 2.9))
	return 5.6
end

-- THE 67 KING: a golden robot king with a 67 crown and a scepter
function STYLES.King(b: Builder, c: Color3, a: Color3): number
	local body = box(b, "Body", Vector3.new(4.5, 4.5, 3), c, CFrame.new())
	box(b, "Legs", Vector3.new(4, 3, 2.6), a, CFrame.new(0, -3.7, 0))
	box(b, "Sash", Vector3.new(0.7, 4.6, 3.1), a, CFrame.new(0.6, 0, 0) * CFrame.Angles(0, 0, 0.5))
	box(b, "Head", Vector3.new(3, 3, 3), c:Lerp(WHITE, 0.3), CFrame.new(0, 3.8, 0))
	box(b, "CrownBand", Vector3.new(3.2, 0.6, 3.2), c, CFrame.new(0, 5.5, 0))
	for i = -1, 1 do
		box(b, "Spike", Vector3.new(0.7, 1.3, 0.7), c, CFrame.new(i * 1.1, 6.3, 0))
	end
	ball(b, "Jewel", 0.7, a, Vector3.new(0, 5.5, -1.6), NEON)
	box(b, "Scepter", Vector3.new(0.3, 5, 0.3), a, CFrame.new(3, 0.5, -0.6))
	ball(b, "ScepterTop", 1, c, Vector3.new(3, 3.2, -0.6))
	googlyEyes(b, 0.9, 0.7, 4, -1.55)
	billboard(body, "67", rgb(255, 230, 90), 5, 0)
	return 4.8
end

-- THE FINAL ONE: a dark tower with a pink core and a halo of floating 6s and 7s
-- (phase 2: cracks open, phase 3: its crown and claws burn pink)
function STYLES.FinalOne(b: Builder, c: Color3, a: Color3): number
	local body = box(b, "Body", Vector3.new(6, 6.4, 4.4), c, CFrame.new())
	box(b, "Waist", Vector3.new(4.6, 2.2, 3.6), c:Lerp(BLACK, 0.3), CFrame.new(0, -4.0, 0))
	box(b, "LegL", Vector3.new(2.0, 3.6, 2.4), c:Lerp(BLACK, 0.45), CFrame.new(-1.4, -6.6, 0))
	box(b, "LegR", Vector3.new(2.0, 3.6, 2.4), c:Lerp(BLACK, 0.45), CFrame.new(1.4, -6.6, 0))
	box(b, "Chest", Vector3.new(4.6, 2.6, 3.8), c:Lerp(WHITE, 0.08), CFrame.new(0, 3.9, 0))
	box(b, "ShoulderL", Vector3.new(2.4, 1.6, 3.0), c:Lerp(a, 0.15), CFrame.new(-3.6, 4.2, 0))
	box(b, "ShoulderR", Vector3.new(2.4, 1.6, 3.0), c:Lerp(a, 0.15), CFrame.new(3.6, 4.2, 0))
	for _, y in { 3.0, -0.4 } do
		for _, side in { -1, 1 } do
			box(b, "Arm", Vector3.new(4.2, 1.4, 1.4), c:Lerp(a, 0.1), CFrame.new(side * 5.3, y, -0.4) * CFrame.Angles(0, 0, side * 0.35))
			ball(b, "Claw", 1.6, c:Lerp(a, 0.35), Vector3.new(side * 7.4, y - 0.9, -0.6))
			tag(ball(b, "ClawFire", 1.7, a, Vector3.new(side * 7.4, y - 0.9, -0.6), NEON), "Phase", 3)
		end
	end
	-- the pink core (its weak point)
	cyl(b, "CoreRim", 0.5, 3.4, BLACK, CFrame.new(0, 0.6, -2.25) * FRONT)
	ball(b, "Core", 2.6, a, Vector3.new(0, 0.6, -2.3), NEON)
	-- head: one eye
	box(b, "Head", Vector3.new(3.4, 3.0, 3.2), c:Lerp(WHITE, 0.05), CFrame.new(0, 6.6, 0))
	ball(b, "Eye", Vector3.new(2.2, 2.2, 0.8), WHITE, Vector3.new(0, 6.7, -1.55))
	ball(b, "Pupil", Vector3.new(1.0, 1.0, 0.5), a, Vector3.new(0, 6.7, -1.9), NEON)
	for i = -2, 2 do
		box(b, "Spike", Vector3.new(0.7, 2 - math.abs(i) * 0.3, 0.7), c:Lerp(a, 0.25), CFrame.new(i * 0.75, 8.8 - math.abs(i) * 0.2, 0) * CFrame.Angles(0, 0, -i * 0.2))
		tag(box(b, "SpikeFire", Vector3.new(0.75, 2.05 - math.abs(i) * 0.3, 0.75), a, CFrame.new(i * 0.75, 8.8 - math.abs(i) * 0.2, 0) * CFrame.Angles(0, 0, -i * 0.2), NEON), "Phase", 3)
	end
	-- cracks show from phase 2
	for i, off in { Vector3.new(-1.6, 1.8, -2.25), Vector3.new(1.8, -1.2, -2.25), Vector3.new(-0.6, -2.4, -2.25) } do
		tag(box(b, "Crack", Vector3.new(0.25, 1.8, 0.1), a, CFrame.new(off) * CFrame.Angles(0, 0, 0.6 * (if i % 2 == 0 then 1 else -1)), NEON), "Phase", 2)
	end
	-- the halo of 6s and 7s (floating plates: nothing solid over its head)
	for i = 0, 5 do
		local ang = i * TAU / 6
		local plate = box(b, "Digit", Vector3.new(1.2, 1.4, 0.3), c, CFrame.new(math.cos(ang) * 4.5, 9.9, 0.8 + math.sin(ang) * 4.5) * CFrame.Angles(0, -ang + math.pi / 2, 0))
		paint(plate, if i % 2 == 0 then "6" else "7", a, { Enum.NormalId.Front, Enum.NormalId.Back })
	end
	billboard(body, "67", a, 4, 12)
	return 8.4
end

---------------------------------------------------------------------------- lair bosses of 67 TOWN
-- THE BIG QUACK: a rubber duck the size of a car, in a tiny captain's hat
function STYLES.Quack(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", 8.4, c, Vector3.zero)
	ball(b, "Tail", 3.6, c, Vector3.new(0, 1.8, 3.8))
	for _, side in { -1, 1 } do
		ball(b, "Wing", 3.2, c:Lerp(a, 0.18), Vector3.new(side * 3.9, 0.4, 0.6))
	end
	ball(b, "Belly", Vector3.new(5.6, 4, 2.4), c:Lerp(WHITE, 0.4), Vector3.new(0, -1.6, -3.2))
	ball(b, "Head", 5.4, c, Vector3.new(0, 4.4, -2.4))
	box(b, "Beak", Vector3.new(3.2, 1.1, 2.4), a, CFrame.new(0, 3.9, -5.4))
	box(b, "BeakLow", Vector3.new(2.6, 0.6, 1.8), a:Lerp(BLACK, 0.15), CFrame.new(0, 3.2, -5.1))
	googlyEyes(b, 1.5, 1.25, 5.3, -4.6)
	box(b, "Hat", Vector3.new(3.4, 1.1, 3.4), WHITE, CFrame.new(0, 7.4, -2.2))
	box(b, "HatBand", Vector3.new(3.5, 0.4, 3.5), rgb(40, 60, 140), CFrame.new(0, 7, -2.2))
	box(b, "HatBrim", Vector3.new(2.6, 0.25, 1.4), rgb(40, 60, 140), CFrame.new(0, 6.9, -4.1))
	return 4.2
end

function STYLES.Duckling(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", 1.7, c, Vector3.zero)
	ball(b, "Head", 1.15, c, Vector3.new(0, 0.95, -0.5))
	box(b, "Beak", Vector3.new(0.6, 0.25, 0.5), a, CFrame.new(0, 0.85, -1.15))
	ball(b, "EyeL", 0.25, BLACK, Vector3.new(-0.3, 1.15, -1))
	ball(b, "EyeR", 0.25, BLACK, Vector3.new(0.3, 1.15, -1))
	return 0.85
end

-- CARTZILLA: a shopping cart that learned to bite
function STYLES.Cart(b: Builder, c: Color3, a: Color3): number
	box(b, "Basket", Vector3.new(6.6, 4.2, 8.6), c, CFrame.new())
	box(b, "Inside", Vector3.new(5.6, 0.4, 7.6), rgb(60, 64, 76), CFrame.new(0, 2.05, 0))
	for i = -1, 1 do
		box(b, "Wire", Vector3.new(6.7, 0.25, 0.25), c:Lerp(BLACK, 0.25), CFrame.new(0, 0.3 + i * 1.1, -4.31))
	end
	box(b, "Handle", Vector3.new(7.4, 0.7, 0.7), a, CFrame.new(0, 3, 4.9))
	box(b, "Seat", Vector3.new(5.6, 0.4, 2.2), a, CFrame.new(0, 2.4, 3.2) * CFrame.Angles(-0.5, 0, 0))
	for _, x in { -2.8, 2.8 } do
		for _, z in { -3.6, 3.6 } do
			ball(b, "Wheel", 1.6, BLACK, Vector3.new(x, -2.9, z))
		end
	end
	googlyEyes(b, 1.7, 1.5, 1.1, -4.5)
	for i = -2, 2 do
		box(b, "Tooth", Vector3.new(0.7, 0.8, 0.3), WHITE, CFrame.new(i * 1.0, -0.9, -4.45) * CFrame.Angles(0, 0, if i % 2 == 0 then 0.3 else -0.3))
	end
	box(b, "PriceTag", Vector3.new(1.8, 1.1, 0.15), GOLD, CFrame.new(3.4, 1.6, -3.2) * CFrame.Angles(0, 0.4, 0.3))
	return 3.7
end

-- JACKPOT JIMMY: a slot machine on little legs (the reels are drawn by the renderer)
function STYLES.Slots(b: Builder, c: Color3, a: Color3): number
	box(b, "Cabinet", Vector3.new(7, 7.4, 5), c, CFrame.new())
	box(b, "Crown", Vector3.new(7.4, 1.6, 5.4), a, CFrame.new(0, 4.4, 0))
	ball(b, "Light", 1.6, rgb(255, 90, 90), Vector3.new(0, 5.8, 0), NEON)
	box(b, "Window", Vector3.new(5.8, 2.8, 0.3), rgb(30, 24, 46), CFrame.new(0, 0.9, -2.55))
	for i = -1, 1 do
		box(b, "Reel", Vector3.new(1.6, 2.2, 0.2), WHITE, CFrame.new(i * 1.85, 0.9, -2.72))
	end
	box(b, "Tray", Vector3.new(5, 0.8, 1.2), a, CFrame.new(0, -2.6, -2.8))
	box(b, "LeverArm", Vector3.new(0.5, 4, 0.5), rgb(200, 200, 210), CFrame.new(4.1, 1.6, 0))
	ball(b, "LeverBall", 1.5, rgb(236, 50, 60), Vector3.new(4.1, 3.8, 0))
	googlyEyes(b, 1.4, 1.5, 3.1, -2.6)
	for _, side in { -1, 1 } do
		box(b, "Leg", Vector3.new(1.2, 1.8, 1.2), rgb(40, 36, 52), CFrame.new(side * 2.2, -4.5, 0))
		box(b, "Shoe", Vector3.new(1.6, 0.8, 2.2), a, CFrame.new(side * 2.2, -5.2, -0.4))
	end
	return 5.6
end

function STYLES.CoinStack(b: Builder, c: Color3, a: Color3): number
	-- a small plinth is the root (a root keeps no rotation; the coins are flat cylinders)
	box(b, "Plinth", Vector3.new(3.2, 0.5, 3.2), a:Lerp(BLACK, 0.3), CFrame.new())
	for i = 0, 4 do
		local d = 3.2 - i * 0.18
		disc(b, "Coin", d, 0.7, if i % 2 == 0 then c else a, Vector3.new(0.1 * (i % 2), 0.6 + i * 0.72, 0))
	end
	ball(b, "Glint", 0.5, WHITE, Vector3.new(0.8, 4, -1), NEON)
	return 0.25
end

-- SIX and SEVEN: walking seven-segment digits with googly eyes. They face -Z, so the digit's
-- right side (seen from the front) is -X. The root part keeps no offset (the renderer places
-- it), so the digit is shifted to put its first segment at the origin.
local function digitBody(b: Builder, ch: string, c: Color3, a: Color3, s: number, t: number, depth: number): number
	local spots = {
		g = { 0, 0, true },
		a = { 0, s, true },
		d = { 0, -s, true },
		b = { -s / 2, s / 2, false },
		c = { -s / 2, -s / 2, false },
		e = { s / 2, -s / 2, false },
		f = { s / 2, s / 2, false },
	}
	-- the root first (the segment that flashes): the middle bar of a 6, the top of a 7
	local order = if ch == "6" then { "g", "a", "f", "e", "d", "c" } else { "a", "b", "c" }
	local shift = -spots[order[1]][2]
	for _, seg in order do
		local spot = spots[seg]
		local size = if spot[3] then Vector3.new(s + t, t, depth) else Vector3.new(t, s, depth)
		box(b, "Seg" .. seg, size, c, CFrame.new(spot[1], spot[2] + shift, 0))
	end
	googlyEyes(b, s * 0.375, s * 0.25, s + 0.2 * s / 3.2 + shift, -depth * 0.62)
	box(b, "Glow", Vector3.new(s + t + 0.3, 0.3, depth + 0.3), a, CFrame.new(0, s + t / 2 + 0.1 + shift, 0), NEON)
	local feet = if ch == "6" then { -s * 0.375, s * 0.375 } else { -s / 2 }
	for _, x in feet do
		box(b, "Foot", Vector3.new(s * 0.44, s * 0.25, depth * 1.1), a:Lerp(BLACK, 0.3), CFrame.new(x, -s - t / 2 - s * 0.16 + shift, -0.2))
	end
	return s + t / 2 + s * 0.28 - shift
end

function STYLES.Six(b: Builder, c: Color3, a: Color3): number
	return digitBody(b, "6", c, a, 3.2, 1.3, 1.8)
end

function STYLES.Seven(b: Builder, c: Color3, a: Color3): number
	return digitBody(b, "7", c, a, 3.2, 1.3, 1.8)
end

-- TICK TOCK: a round alarm clock with two bells, running late (the root is the round body:
-- a root keeps no rotation, so the face is its own disc)
function STYLES.Clock(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", 7, c, Vector3.zero)
	cyl(b, "Bezel", 0.4, 6.2, GOLD, CFrame.new(0, 0.2, -2.9) * FRONT)
	cyl(b, "Face", 0.4, 5.4, a, CFrame.new(0, 0.2, -3.1) * FRONT)
	box(b, "HandLong", Vector3.new(0.35, 2.3, 0.15), BLACK, CFrame.new(0.45, 1.0, -3.35) * CFrame.Angles(0, 0, -0.5))
	box(b, "HandShort", Vector3.new(0.4, 1.4, 0.15), BLACK, CFrame.new(-0.3, -0.35, -3.35) * CFrame.Angles(0, 0, 2.6))
	ball(b, "Pin", 0.5, rgb(236, 60, 60), Vector3.new(0, 0.2, -3.4))
	for _, side in { -1, 1 } do
		ball(b, "Bell", 2.4, GOLD, Vector3.new(side * 2.1, 3.7, 0))
		box(b, "Leg", Vector3.new(0.7, 2, 0.7), BLACK, CFrame.new(side * 1.9, -3.6, 0) * CFrame.Angles(0, 0, side * 0.35))
	end
	box(b, "Hammer", Vector3.new(0.4, 1.6, 0.4), BLACK, CFrame.new(0, 4.2, 0))
	googlyEyes(b, 1.3, 1.1, 1.9, -3.2)
	return 4.5
end

---------------------------------------------------------------------------- lair bosses of the harder tiers
-- SIR SNAILSALOT: a huge spiral shell on a pale slug, eye stalks, a knight's helmet
function STYLES.Snail(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", Vector3.new(4.0, 2.4, 8.4), c, Vector3.new(0, 0, 0))
	ball(b, "Shell", Vector3.new(4.6, 6.0, 6.0), a, Vector3.new(0, 2.6, 1.3))
	for i, d in { 4.0, 2.6, 1.2 } do
		cyl(b, "Spiral", 0.15 + i * 0.05, d, rgb(250, 232, 200), CFrame.new(2.32 + i * 0.05, 2.6 + (i - 1) * 0.35, 1.3 + (i - 1) * 0.3))
		cyl(b, "Spiral", 0.15 + i * 0.05, d, rgb(250, 232, 200), CFrame.new(-2.32 - i * 0.05, 2.6 + (i - 1) * 0.35, 1.3 + (i - 1) * 0.3))
	end
	ball(b, "Head", Vector3.new(3.0, 2.6, 2.6), c:Lerp(WHITE, 0.1), Vector3.new(0, 0.9, -3.4))
	box(b, "Helmet", Vector3.new(2.6, 1.0, 2.2), rgb(190, 196, 210), CFrame.new(0, 2.15, -3.4))
	box(b, "Plume", Vector3.new(0.4, 1.4, 1.6), rgb(90, 120, 220), CFrame.new(0, 3.1, -3.2))
	for _, side in { -1, 1 } do
		box(b, "Stalk", Vector3.new(0.35, 2.0, 0.35), c, CFrame.new(side * 0.8, 3.2, -4.0) * CFrame.Angles(0.3, 0, side * -0.25))
	end
	googlyEyes(b, 1.0, 1.05, 4.25, -4.4)
	-- the soft spot it shows when it peeks out (its weak point)
	ball(b, "SoftSpot", Vector3.new(1.6, 1.0, 0.6), rgb(255, 150, 200), Vector3.new(0, 0.2, -4.6), NEON)
	return 1.2
end

-- THE SCARECROW: a wide cross of stick arms, a straw body, a glowing pumpkin head
function STYLES.Scarecrow(b: Builder, c: Color3, a: Color3): number
	box(b, "Body", Vector3.new(2.6, 3.6, 1.8), c, CFrame.new())
	box(b, "Pole", Vector3.new(0.6, 9, 0.6), rgb(120, 86, 56), CFrame.new(0, -1.0, 0.6))
	box(b, "Arms", Vector3.new(11, 0.6, 0.6), rgb(120, 86, 56), CFrame.new(0, 1.2, 0.5))
	for _, side in { -1, 1 } do
		box(b, "Sleeve", Vector3.new(3.2, 1.3, 1.3), rgb(90, 120, 170), CFrame.new(side * 2.4, 1.2, 0.3))
		ball(b, "Straw", Vector3.new(1.4, 1.2, 1.2), c:Lerp(WHITE, 0.2), Vector3.new(side * 5.4, 1.2, 0.5))
	end
	box(b, "Patch", Vector3.new(0.9, 0.9, 0.1), rgb(180, 80, 120), CFrame.new(0.6, -0.4, -0.92))
	ball(b, "Pumpkin", Vector3.new(2.9, 2.4, 2.7), a, Vector3.new(0, 3.3, 0))
	box(b, "Stem", Vector3.new(0.35, 0.7, 0.35), rgb(80, 120, 60), CFrame.new(0, 4.7, 0))
	box(b, "EyeL", Vector3.new(0.6, 0.5, 0.1), rgb(255, 245, 190), CFrame.new(-0.55, 3.55, -1.32) * CFrame.Angles(0, 0, math.pi / 4), NEON)
	box(b, "EyeR", Vector3.new(0.6, 0.5, 0.1), rgb(255, 245, 190), CFrame.new(0.55, 3.55, -1.32) * CFrame.Angles(0, 0, math.pi / 4), NEON)
	box(b, "Grin", Vector3.new(1.4, 0.3, 0.1), rgb(255, 245, 190), CFrame.new(0, 2.85, -1.3), NEON)
	box(b, "HatBrim", Vector3.new(3.8, 0.2, 3.6), rgb(110, 90, 60), CFrame.new(0, 4.55, 0))
	box(b, "HatTop", Vector3.new(2.0, 1.2, 2.0), rgb(110, 90, 60), CFrame.new(0, 5.2, 0) * CFrame.Angles(0, 0, 0.1))
	return 5.5
end

-- SELF-CHECKOUT: a white pillar with a big blue screen (googly eyes on it) and a scanner
function STYLES.Checkout(b: Builder, c: Color3, a: Color3): number
	box(b, "Pillar", Vector3.new(4.2, 6.6, 3.4), c, CFrame.new())
	box(b, "Base", Vector3.new(5.2, 0.8, 4.4), c:Lerp(BLACK, 0.35), CFrame.new(0, -3.6, 0))
	box(b, "ScreenFrame", Vector3.new(4.0, 3.2, 0.5), rgb(50, 54, 64), CFrame.new(0, 4.6, -0.6) * CFrame.Angles(-0.25, 0, 0))
	box(b, "Screen", Vector3.new(3.4, 2.6, 0.2), a, CFrame.new(0, 4.62, -0.9) * CFrame.Angles(-0.25, 0, 0), NEON)
	googlyEyes(b, 0.95, 0.8, 4.85, -1.35)
	box(b, "Scanner", Vector3.new(3.4, 0.4, 2.0), rgb(40, 44, 54), CFrame.new(0, 1.2, -2.0))
	box(b, "ScanLine", Vector3.new(2.8, 0.1, 0.2), a, CFrame.new(0, 1.43, -2.0), NEON)
	box(b, "Bagging", Vector3.new(2.6, 0.3, 2.6), c:Lerp(BLACK, 0.2), CFrame.new(3.4, 0.4, -0.4))
	box(b, "Bag", Vector3.new(1.6, 1.8, 1.4), rgb(230, 225, 210), CFrame.new(3.4, 1.45, -0.4))
	box(b, "Pole", Vector3.new(0.3, 2.2, 0.3), c:Lerp(BLACK, 0.3), CFrame.new(-1.7, 4.4, 1.2))
	ball(b, "Light", 1.0, GOLD, Vector3.new(-1.7, 5.7, 1.2), NEON)
	return 3.9
end

-- THE MANNEQUIN: a tall beige store dummy with black joints and a stiff pose
function STYLES.Mannequin(b: Builder, c: Color3, a: Color3): number
	box(b, "Torso", Vector3.new(2.6, 3.4, 1.6), c, CFrame.new())
	box(b, "Hips", Vector3.new(2.4, 1.2, 1.5), c, CFrame.new(0, -2.4, 0))
	ball(b, "Neck", 0.7, a, Vector3.new(0, 2.0, 0))
	ball(b, "Head", Vector3.new(1.7, 2.1, 1.7), c, Vector3.new(0, 3.3, 0))
	googlyEyes(b, 0.6, 0.36, 3.45, -0.75)
	for _, side in { -1, 1 } do
		ball(b, "Shoulder", 0.8, a, Vector3.new(side * 1.6, 1.4, 0))
		box(b, "UpperArm", Vector3.new(0.6, 2.0, 0.6), c, CFrame.new(side * 2.1, 0.5, -0.2) * CFrame.Angles(0.3, 0, side * 0.3))
		ball(b, "Elbow", 0.6, a, Vector3.new(side * 2.4, -0.45, -0.5))
		box(b, "Forearm", Vector3.new(0.55, 1.9, 0.55), c, CFrame.new(side * 2.45, -0.1, -1.4) * CFrame.Angles(1.2, 0, 0))
		box(b, "Leg", Vector3.new(0.8, 3.2, 0.8), c, CFrame.new(side * 0.65, -4.4, 0))
		ball(b, "Knee", 0.7, a, Vector3.new(side * 0.65, -4.3, -0.3))
	end
	box(b, "Seam", Vector3.new(0.15, 2.6, 0.1), rgb(255, 150, 200), CFrame.new(0, 0.2, -0.82), NEON)
	disc(b, "Stand", 3.2, 0.4, a, Vector3.new(0, -5.8, 0))
	return 6.0
end

-- DJ DROP: a dark DJ booth on legs, two big speakers, headphones on a round head
function STYLES.DJ(b: Builder, c: Color3, a: Color3): number
	box(b, "Booth", Vector3.new(6.2, 3.2, 3.4), c, CFrame.new())
	box(b, "Front", Vector3.new(6.0, 2.0, 0.2), c:Lerp(a, 0.25), CFrame.new(0, -0.1, -1.8))
	cyl(b, "Deck", 0.3, 2.0, BLACK, CFrame.new(-1.4, 1.75, -0.4) * FLAT)
	cyl(b, "Deck", 0.3, 2.0, BLACK, CFrame.new(1.4, 1.75, -0.4) * FLAT)
	ball(b, "Head", 3.0, rgb(120, 100, 200), Vector3.new(0, 3.6, 0.4))
	box(b, "Phones", Vector3.new(3.4, 0.35, 0.5), BLACK, CFrame.new(0, 5.0, 0.4))
	for _, side in { -1, 1 } do
		cyl(b, "Cup", 0.6, 1.3, BLACK, CFrame.new(side * 1.6, 3.8, 0.4))
		box(b, "Speaker", Vector3.new(2.2, 4.2, 2.2), rgb(36, 32, 48), CFrame.new(side * 4.3, 0.5, 0))
		cyl(b, "Cone", 0.3, 1.6, a, CFrame.new(side * 4.3, 1.4, -1.15) * FRONT, NEON)
		cyl(b, "Woofer", 0.3, 1.0, a:Lerp(WHITE, 0.3), CFrame.new(side * 4.3, -0.4, -1.15) * FRONT, NEON)
		box(b, "Leg", Vector3.new(0.8, 2.0, 0.8), BLACK, CFrame.new(side * 1.8, -2.6, 0))
	end
	googlyEyes(b, 0.9, 0.6, 3.7, -1.0)
	return 3.6
end

-- ROULETTE ROLLER: a black-and-gold wheel standing on its edge, a white ball on top
function STYLES.Roulette(b: Builder, c: Color3, a: Color3): number
	ball(b, "Body", 3.0, c, Vector3.zero)
	cyl(b, "Wheel", 2.2, 9.0, c, CFrame.new() * FRONT)
	cyl(b, "Rim", 2.4, 9.4, a, CFrame.new(0, 0, 0.6) * FRONT)
	cyl(b, "Face", 0.3, 7.6, rgb(36, 90, 60), CFrame.new(0, 0, -1.15) * FRONT)
	for i = 0, 7 do
		local ang = i * TAU / 8
		box(b, "Pocket", Vector3.new(1.0, 1.0, 0.25), if i % 2 == 0 then rgb(190, 40, 50) else BLACK, CFrame.new(math.cos(ang) * 3.2, math.sin(ang) * 3.2, -1.35) * CFrame.Angles(0, 0, ang))
	end
	cyl(b, "Hub", 0.5, 2.2, a, CFrame.new(0, 0, -1.4) * FRONT)
	ball(b, "Ball", 1.4, WHITE, Vector3.new(0, 5.0, 0), NEON)
	googlyEyes(b, 0.9, 0.75, 0.4, -1.75)
	box(b, "Stand", Vector3.new(3.4, 0.7, 3.0), a:Lerp(BLACK, 0.4), CFrame.new(0, -4.6, 0))
	return 4.9
end

-- THE MIRROR: a tall oval mirror on two legs, a silver frame and a cyan glare
function STYLES.Mirror(b: Builder, c: Color3, a: Color3): number
	box(b, "Back", Vector3.new(3.0, 4.6, 0.5), c:Lerp(BLACK, 0.2), CFrame.new())
	cyl(b, "Frame", 0.8, 6.4, c, CFrame.new() * FRONT)
	cyl(b, "Glass", 0.3, 5.4, a:Lerp(WHITE, 0.4), CFrame.new(0, 0, -0.45) * FRONT)
	box(b, "Glare", Vector3.new(0.4, 3.0, 0.1), WHITE, CFrame.new(-1.2, 0.6, -0.62) * CFrame.Angles(0, 0, -0.5), NEON)
	box(b, "Crack", Vector3.new(0.18, 2.2, 0.1), a, CFrame.new(1.1, -1.0, -0.62) * CFrame.Angles(0, 0, 0.7), NEON)
	googlyEyes(b, 1.1, 0.9, 0.9, -0.95)
	box(b, "Crest", Vector3.new(2.6, 0.9, 0.9), c:Lerp(GOLD, 0.3), CFrame.new(0, 3.5, 0))
	for _, side in { -1, 1 } do
		box(b, "Leg", Vector3.new(0.5, 2.6, 0.5), c:Lerp(BLACK, 0.4), CFrame.new(side * 1.2, -3.9, 0.2) * CFrame.Angles(0, 0, side * 0.2))
		box(b, "Foot", Vector3.new(1.0, 0.4, 1.6), c:Lerp(BLACK, 0.4), CFrame.new(side * 1.5, -5.1, -0.1))
	end
	return 5.3
end

-- THE EVENT HORIZON: a black sphere inside a wide pale-violet ring; floats
function STYLES.Horizon(b: Builder, c: Color3, a: Color3): number
	ball(b, "Core", 6.2, c, Vector3.zero)
	disc(b, "Disk", 13, 0.25, a:Lerp(c, 0.45), Vector3.new(0, -0.2, 0))
	disc(b, "Glow", 7.6, 0.35, a, Vector3.new(0, -0.2, 0), NEON)
	googlyEyes(b, 1.4, 1.1, 0.9, -2.6)
	for i = 0, 2 do
		local ang = i * TAU / 3 + 0.4
		box(b, "Debris", Vector3.new(0.9, 0.7, 0.9), a:Lerp(WHITE, 0.3), CFrame.new(math.cos(ang) * 5.6, 0.4, math.sin(ang) * 5.6) * CFrame.Angles(0.5, ang, 0.3))
	end
	return 5
end

---------------------------------------------------------------------------- main bosses of the harder tiers
-- MAMA GOOBER: the biggest goober of all, pink cheeks, a tiny golden 67 crown, a nest of eggs
-- (phase 2: angry brows, her cheeks burn)
function STYLES.MamaGoober(b: Builder, c: Color3, a: Color3): number
	local body = ball(b, "Body", Vector3.new(13, 11, 12.5), c, Vector3.zero)
	ball(b, "Belly", Vector3.new(8.6, 6.2, 4), c:Lerp(WHITE, 0.35), Vector3.new(0, -2.0, -4.6))
	for _, side in { -1, 1 } do
		ball(b, "Cheek", Vector3.new(2.2, 1.4, 0.8), a, Vector3.new(side * 3.6, 0.2, -5.6))
		tag(ball(b, "CheekHot", Vector3.new(2.3, 1.5, 0.85), a, Vector3.new(side * 3.6, 0.2, -5.6), NEON), "Phase", 2)
		tag(box(b, "Brow", Vector3.new(2.6, 0.5, 0.5), a:Lerp(BLACK, 0.55), CFrame.new(side * 2.2, 4.6, -4.9) * CFrame.Angles(0, 0, side * 0.45)), "Phase", 2)
	end
	googlyEyes(b, 3.4, 2.2, 2.6, -4.6)
	ball(b, "Mouth", Vector3.new(2.6, 1.2, 0.6), a:Lerp(BLACK, 0.45), Vector3.new(0, -1.1, -6.0))
	for _, off in { Vector3.new(-4.6, 2.6, 1.4), Vector3.new(4.2, 3.4, 2.6), Vector3.new(-1.6, 4.2, 3.6) } do
		ball(b, "Spot", 2.0, c:Lerp(BLACK, 0.18), off)
	end
	-- a tiny crown, way too small for her
	cyl(b, "Crown", 0.8, 3.0, GOLD, CFrame.new(0.8, 5.9, 0.5) * FLAT)
	for i = 0, 2 do
		local ang = i * TAU / 3
		box(b, "CrownPoint", Vector3.new(0.5, 0.9, 0.5), GOLD, CFrame.new(0.8 + math.cos(ang) * 1.1, 6.6, 0.5 + math.sin(ang) * 1.1))
	end
	local plate = box(b, "Plate67", Vector3.new(1.4, 0.8, 0.2), GOLD, CFrame.new(0.8, 6.0, -1.0))
	paint(plate, "67", rgb(120, 40, 80), { Enum.NormalId.Front })
	-- the nest
	cyl(b, "Nest", 1.4, 15, rgb(150, 110, 70), CFrame.new(0, -5.2, 0) * FLAT)
	for i = 0, 2 do
		local ang = i * TAU / 3 + 0.7
		ball(b, "Egg", Vector3.new(1.8, 2.3, 1.8), rgb(206, 240, 176), Vector3.new(math.cos(ang) * 6.4, -3.9, math.sin(ang) * 6.4))
	end
	billboard(body, "67", GOLD, 4, 9)
	return 5.6
end

-- THE HORDEMASTER: a broad red-and-gold commander with a megaphone for a head
-- (phase 2: a gold plume, phase 3: its megaphone glows)
function STYLES.Hordemaster(b: Builder, c: Color3, a: Color3): number
	local body = box(b, "Torso", Vector3.new(6.4, 5.4, 3.8), c, CFrame.new())
	box(b, "Belt", Vector3.new(6.6, 1.0, 4.0), a, CFrame.new(0, -2.5, 0))
	box(b, "Buckle", Vector3.new(1.4, 1.0, 0.3), GOLD, CFrame.new(0, -2.5, -2.1))
	for _, side in { -1, 1 } do
		box(b, "Leg", Vector3.new(2.4, 3.8, 2.8), c:Lerp(BLACK, 0.45), CFrame.new(side * 1.5, -4.9, 0))
		box(b, "Boot", Vector3.new(2.6, 1.2, 3.4), BLACK, CFrame.new(side * 1.5, -6.7, -0.3))
		box(b, "Pad", Vector3.new(2.8, 1.4, 3.4), a, CFrame.new(side * 4.0, 2.4, 0))
		box(b, "Arm", Vector3.new(1.9, 4.6, 2.0), c, CFrame.new(side * 4.0, -0.3, 0))
		ball(b, "Fist", 2.4, c:Lerp(BLACK, 0.3), Vector3.new(side * 4.1, -2.9, -0.4))
	end
	box(b, "Sash", Vector3.new(0.9, 6.0, 4.0), a, CFrame.new(0.8, 0.2, 0) * CFrame.Angles(0, 0, 0.55))
	local medal = box(b, "Medal", Vector3.new(1.6, 1.6, 0.3), GOLD, CFrame.new(-1.6, 1.2, -2.0))
	paint(medal, "67", c, { Enum.NormalId.Front })
	-- the megaphone head: a cone of stacked rings, the bell facing you
	box(b, "Neck", Vector3.new(1.6, 1.0, 1.6), BLACK, CFrame.new(0, 3.2, 0))
	cyl(b, "Horn", 2.0, 2.6, rgb(230, 230, 236), CFrame.new(0, 4.6, 0.8) * FRONT)
	cyl(b, "Horn", 1.6, 3.8, rgb(230, 230, 236), CFrame.new(0, 4.6, -0.9) * FRONT)
	cyl(b, "Bell", 0.5, 5.0, a, CFrame.new(0, 4.6, -1.9) * FRONT)
	cyl(b, "Mouth", 0.3, 3.8, BLACK, CFrame.new(0, 4.6, -2.15) * FRONT)
	tag(cyl(b, "MouthGlow", 0.32, 3.9, GOLD, CFrame.new(0, 4.6, -2.17) * FRONT, NEON), "Phase", 3)
	googlyEyes(b, 1.0, 0.8, 6.5, -0.4)
	tag(box(b, "Plume", Vector3.new(0.6, 2.2, 3.0), GOLD, CFrame.new(0, 7.2, 0.6)), "Phase", 2)
	-- the banner pole on its back (thin from above)
	box(b, "Pole", Vector3.new(0.4, 9, 0.4), rgb(110, 80, 50), CFrame.new(-2.4, 3.0, 2.2))
	box(b, "Flag", Vector3.new(0.2, 2.6, 3.0), a, CFrame.new(-2.4, 6.1, 3.7))
	billboard(body, "67", GOLD, 4, 11)
	return 7.3
end

-- THE DREAD: a tall indigo shadow with one pale yellow moon eye and long thin arms
-- (phase 2: two more eyes open, phase 3: a crown of thorns)
function STYLES.Dread(b: Builder, c: Color3, a: Color3): number
	local body = ball(b, "Body", Vector3.new(5.6, 9.4, 4.8), c, Vector3.zero)
	cyl(b, "Hem", 2.4, 8.0, c:Lerp(BLACK, 0.3), CFrame.new(0, -4.4, 0) * FLAT)
	ball(b, "Hood", Vector3.new(4.8, 5.4, 4.6), c:Lerp(BLACK, 0.2), Vector3.new(0, 5.6, 0.2))
	ball(b, "Face", Vector3.new(3.6, 3.8, 1.6), BLACK, Vector3.new(0, 5.5, -1.75))
	-- the moon eye (its weak point)
	ball(b, "MoonEye", Vector3.new(3.0, 3.0, 1.0), a, Vector3.new(0, 5.8, -2.6), NEON)
	ball(b, "Pupil", Vector3.new(0.8, 1.8, 0.5), c:Lerp(BLACK, 0.5), Vector3.new(0, 5.8, -3.05))
	for _, side in { -1, 1 } do
		tag(ball(b, "EyeSmall", Vector3.new(0.9, 0.9, 0.4), a, Vector3.new(side * 1.25, 4.3, -2.2), NEON), "Phase", 2)
		box(b, "Arm", Vector3.new(0.8, 7.0, 0.8), c:Lerp(BLACK, 0.15), CFrame.new(side * 3.6, -0.2, -0.6) * CFrame.Angles(0.25, 0, side * 0.35))
		ball(b, "Hand", Vector3.new(1.6, 1.0, 1.4), c:Lerp(BLACK, 0.3), Vector3.new(side * 4.9, -3.6, -1.5))
		for k = -1, 1 do
			box(b, "Claw", Vector3.new(0.25, 1.4, 0.25), a:Lerp(WHITE, 0.4), CFrame.new(side * 4.9 + k * 0.4, -4.4, -1.9) * CFrame.Angles(0.3, 0, k * 0.2))
		end
		box(b, "Spike", Vector3.new(0.5, 2.2, 0.5), c:Lerp(BLACK, 0.4), CFrame.new(side * 2.6, 3.4, 0.4) * CFrame.Angles(0, 0, side * -0.6))
	end
	for i = -2, 2 do
		tag(box(b, "Thorn", Vector3.new(0.4, 1.6 - math.abs(i) * 0.25, 0.4), a, CFrame.new(i * 0.85, 8.1 - math.abs(i) * 0.3, 0.2) * CFrame.Angles(0, 0, -i * 0.25), NEON), "Phase", 3)
	end
	billboard(body, "67", a, 3.5, 10)
	return 5.6
end

-- THE FURNACE: a black iron golem with a chimney crown and a furnace door for a chest
-- (phase 3 MELTDOWN: the door hangs open, the fire shows)
function STYLES.Furnace(b: Builder, c: Color3, a: Color3): number
	local body = box(b, "Body", Vector3.new(7.4, 6.8, 5.4), c, CFrame.new())
	box(b, "Band", Vector3.new(7.6, 0.8, 5.6), c:Lerp(WHITE, 0.12), CFrame.new(0, 2.8, 0))
	box(b, "Band", Vector3.new(7.6, 0.8, 5.6), c:Lerp(WHITE, 0.12), CFrame.new(0, -2.8, 0))
	-- the door and the fire behind it (its weak point)
	box(b, "Fire", Vector3.new(3.6, 3.6, 0.3), a, CFrame.new(0, 0, -2.6), NEON)
	tag(box(b, "Door", Vector3.new(4.0, 4.0, 0.4), rgb(70, 66, 72), CFrame.new(0, 0, -2.85)), "PhaseHide", 3)
	for i = -1, 1 do
		tag(box(b, "Grill", Vector3.new(3.4, 0.35, 0.3), BLACK, CFrame.new(0, i * 1.0, -3.1)), "PhaseHide", 3)
	end
	tag(box(b, "DoorOpen", Vector3.new(0.4, 4.0, 4.0), rgb(70, 66, 72), CFrame.new(-2.2, 0, -4.8)), "Phase", 3)
	local plate = box(b, "Plate", Vector3.new(1.8, 0.9, 0.3), a:Lerp(WHITE, 0.3), CFrame.new(0, 2.8, -2.85))
	paint(plate, "67", c, { Enum.NormalId.Front })
	-- head with two ember eyes
	box(b, "Head", Vector3.new(3.4, 2.2, 3.2), c:Lerp(BLACK, 0.2), CFrame.new(0, 4.5, 0))
	box(b, "EyeL", Vector3.new(0.8, 0.35, 0.1), a, CFrame.new(-0.7, 4.6, -1.62), NEON)
	box(b, "EyeR", Vector3.new(0.8, 0.35, 0.1), a, CFrame.new(0.7, 4.6, -1.62), NEON)
	-- the chimney crown
	for i, x in { -2.4, 0, 2.4 } do
		local h = if i == 2 then 3.2 else 2.4
		cyl(b, "Chimney", h, 1.2, c:Lerp(WHITE, 0.08), CFrame.new(x, 5.6 + h / 2, 0.8) * FLAT)
		disc(b, "Smoke", 0.9, 0.2, a:Lerp(WHITE, 0.3), Vector3.new(x, 5.6 + h + 0.1, 0.8), NEON)
	end
	for _, side in { -1, 1 } do
		cyl(b, "Piston", 4.6, 1.6, rgb(150, 150, 160), CFrame.new(side * 4.6, -0.2, 0) * FLAT)
		box(b, "Arm", Vector3.new(2.2, 2.2, 2.8), c, CFrame.new(side * 4.6, 2.4, 0))
		box(b, "Fist", Vector3.new(2.6, 2.4, 2.8), c:Lerp(BLACK, 0.25), CFrame.new(side * 4.6, -3.0, -0.3))
		box(b, "Leg", Vector3.new(2.4, 3.2, 3.0), c:Lerp(BLACK, 0.35), CFrame.new(side * 1.9, -5.0, 0))
	end
	billboard(body, "67", a, 3.5, 11)
	return 6.6
end

-- THE ERASER: a giant white eraser in a paper sleeve, a graphite-smudged tip, sketch lines
-- (it wears down: the back crumbs away at phases 3 and 4)
function STYLES.Eraser(b: Builder, c: Color3, a: Color3): number
	local body = box(b, "Body", Vector3.new(6.2, 4.6, 7.2), c, CFrame.new())
	box(b, "Sleeve", Vector3.new(6.5, 4.9, 4.0), rgb(90, 130, 200), CFrame.new(0, 0, 1.4))
	box(b, "SleeveStripe", Vector3.new(6.6, 0.8, 4.05), WHITE, CFrame.new(0, 0.9, 1.4))
	local label = box(b, "Label", Vector3.new(3.0, 1.6, 0.1), WHITE, CFrame.new(3.27, -0.6, 1.4) * CFrame.Angles(0, math.pi / 2, 0))
	paint(label, "67", rgb(60, 60, 70), { Enum.NormalId.Front })
	-- the worn tip (its weak point) and its graphite smudge
	box(b, "Tip", Vector3.new(6.0, 4.4, 1.6), a:Lerp(c, 0.55), CFrame.new(0, -0.1, -4.2))
	box(b, "Smudge", Vector3.new(4.4, 1.2, 0.2), a:Lerp(c, 0.35), CFrame.new(0, -1.1, -5.05))
	box(b, "Worn", Vector3.new(2.2, 0.8, 0.2), rgb(255, 150, 200), CFrame.new(0, -1.85, -5.1), NEON)
	googlyEyes(b, 1.5, 1.3, 1.0, -5.3)
	-- the back end wears off
	tag(box(b, "BackEnd", Vector3.new(6.0, 4.4, 1.6), c, CFrame.new(0, 0, 4.4)), "PhaseHide", 3)
	tag(box(b, "BackEnd2", Vector3.new(6.0, 4.4, 1.2), c, CFrame.new(0, 0, 5.8)), "PhaseHide", 2)
	-- sketch lines around it
	for i, cf in { CFrame.new(-4.2, 1.5, -1) * CFrame.Angles(0, 0.2, 0.9), CFrame.new(4.3, -0.8, 0.5) * CFrame.Angles(0, -0.3, -0.7), CFrame.new(-3.6, -2.2, 2.6) * CFrame.Angles(0.4, 0, 0.3), CFrame.new(3.4, 2.4, -2.4) * CFrame.Angles(0, 0.6, 1.2) } do
		box(b, "Sketch", Vector3.new(0.12, 2.6 - i * 0.2, 0.12), a, cf)
	end
	billboard(body, "67", a, 3.5, 6)
	return 2.6
end

-- THE 67 PRIME, phase 1: a golden SIX and a black SEVEN with gold edges
function STYLES.PrimeSix(b: Builder, c: Color3, a: Color3): number
	local h = digitBody(b, "6", c, a, 4.2, 1.6, 2.2)
	cyl(b, "Crown", 0.6, 2.4, GOLD, CFrame.new(0, 5.9, 0) * FLAT)
	return h
end

function STYLES.PrimeSeven(b: Builder, c: Color3, a: Color3): number
	local h = digitBody(b, "7", c, a, 4.2, 1.6, 2.2)
	cyl(b, "Crown", 0.6, 2.4, GOLD, CFrame.new(0, 1.3, 0) * FLAT)
	return h
end

-- THE 67 PRIME: a huge fused golden 67 with a purple core between the digits
-- (phase 3: dark plates of THE DREAD and THE FURNACE, phase 4: erased white patches)
function STYLES.Prime67(b: Builder, c: Color3, a: Color3): number
	local s, t, depth = 5.2, 2.0, 2.6
	-- the root: the gold spine that fuses the two digits
	box(b, "Spine", Vector3.new(1.6, s * 1.6, depth * 0.8), c, CFrame.new())
	local function seg(name: string, x: number, y: number, horizontal: boolean)
		box(b, name, if horizontal then Vector3.new(s + t, t, depth) else Vector3.new(t, s, depth), c, CFrame.new(x, y, 0))
	end
	-- it faces -Z: seen from the front, +X is on your left, so the 6 sits at +X
	local six, seven = 4.2, -4.2
	seg("Seg6g", six, 0, true)
	seg("Seg6a", six, s, true)
	seg("Seg6f", six + s / 2, s / 2, false)
	seg("Seg6e", six + s / 2, -s / 2, false)
	seg("Seg6d", six, -s, true)
	seg("Seg6c", six - s / 2, -s / 2, false)
	seg("Seg7a", seven, s, true)
	seg("Seg7b", seven - s / 2, s / 2, false)
	seg("Seg7c", seven - s / 2, -s / 2, false)
	-- the fusion: a purple core (its weak point) in a gold ring
	cyl(b, "CoreRing", 0.6, 4.4, GOLD, CFrame.new(0, 0, -1.3) * FRONT)
	ball(b, "Core", 3.4, a, Vector3.new(0, 0, -1.4), NEON)
	googlyEyes(b, 1.6, 4.2, s + 1.4, -1.4)
	-- a crown over both digits
	box(b, "CrownBand", Vector3.new(15, 0.9, 3.0), GOLD, CFrame.new(0, s + 2.3, 0))
	for i = -2, 2 do
		box(b, "CrownSpike", Vector3.new(0.9, 1.8 - math.abs(i) * 0.25, 0.9), GOLD, CFrame.new(i * 3.2, s + 3.5 - math.abs(i) * 0.12, 0))
	end
	for _, x in { six, seven - s / 2 } do
		box(b, "Foot", Vector3.new(2.8, 1.2, 3.2), a:Lerp(BLACK, 0.4), CFrame.new(x, -s - t / 2 - 0.6, -0.3))
	end
	-- phase 3: dark plates (THE DREAD's indigo, THE FURNACE's iron)
	for i, cf in { CFrame.new(six, s, -1.4), CFrame.new(seven, s, -1.4), CFrame.new(six, -s, -1.4) } do
		tag(box(b, "DarkPlate", Vector3.new(s * 0.7, t * 0.8, 0.3), if i == 2 then rgb(64, 54, 124) else rgb(40, 38, 44), cf), "Phase", 2)
	end
	-- phase 4: erased white patches
	for _, cf in { CFrame.new(1.8, s * 0.5, -1.4), CFrame.new(seven - s / 2, -s * 0.4, -1.45), CFrame.new(six + s / 2, -s * 0.4, -1.45) } do
		tag(box(b, "Erased", Vector3.new(1.8, 2.2, 0.32), rgb(246, 246, 250), cf), "Phase", 3)
	end
	-- floating 6s and 7s around it
	for i = 0, 3 do
		local ang = i * TAU / 4 + math.pi / 4
		local plate = box(b, "Digit", Vector3.new(1.6, 1.8, 0.3), a, CFrame.new(math.cos(ang) * 8.8, s + 1.0, math.sin(ang) * 5.0) * CFrame.Angles(0, -ang + math.pi / 2, 0))
		paint(plate, if i % 2 == 0 then "6" else "7", GOLD, { Enum.NormalId.Front, Enum.NormalId.Back })
	end
	return s + t / 2 + 1.2
end

---------------------------------------------------------------------------- build
-- how far a (rotated) part reaches up from its centre
local function halfHeight(p: BasePart): number
	local up = p.CFrame:VectorToObjectSpace(Vector3.new(0, 1, 0))
	return (math.abs(up.X) * p.Size.X + math.abs(up.Y) * p.Size.Y + math.abs(up.Z) * p.Size.Z) / 2
end

-- floating models bob in the air instead of hopping
local FLOAT = { Diver = true, Ghost = true, The67 = true, VoidBoss = true, Crow = true, Horizon = true, Wailer = true }
local FLOAT_ANIM = { Float = true, Flap = true, Spin = true } -- (the bestiary: shared/EnemyData.lua AnimType)

local SKETCH = rgb(236, 236, 240)
local ELITE_GOLD = GOLD
local ELITE_PURPLE = rgb(190, 110, 255)

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
	local elite = string.find(v, "e", 1, true) ~= nil
	if elite then
		scale *= 1.3
	end
	local b: Builder = { Model = model, Root = nil, Scale = scale, Parts = {}, Anims = {} }
	local color, accent = def.Color, def.Accent
	if string.find(v, "g", 1, true) then
		color, accent = rgb(255, 205, 50), rgb(255, 245, 170)
	end
	local style = STYLES[def.Model] or STYLES.Blob
	local height = style(b, color, accent)
	local top = 0
	local root0 = b.Root :: BasePart
	for _, p in b.Parts do
		top = math.max(top, (p.Position.Y + halfHeight(p) - root0.Position.Y) / scale)
	end
	if elite then
		-- elites: a glowing ring at their feet and a crest over their head
		disc(b, "EliteRing", 3.8, 0.25, ELITE_GOLD, Vector3.new(0, -height + 0.15, 0), NEON)
		if def.Role ~= "Elite" then
			-- (a bestiary elite is an elite by its looks: the ring is enough)
			local crestY = math.min(top, 7) + 1.3
			box(b, "EliteCrest", Vector3.new(0.9, 0.9, 0.9), ELITE_PURPLE, CFrame.new(0, crestY, 0) * CFrame.Angles(0, math.pi / 4, math.pi / 4), NEON)
			box(b, "EliteWingL", Vector3.new(0.7, 0.25, 0.25), ELITE_GOLD, CFrame.new(-0.85, crestY, 0) * CFrame.Angles(0, 0, 0.4))
			box(b, "EliteWingR", Vector3.new(0.7, 0.25, 0.25), ELITE_GOLD, CFrame.new(0.85, crestY, 0) * CFrame.Angles(0, 0, -0.4))
		end
	end
	if def.Champion then
		-- a mini-boss stands in a red ring (readable in any crowd, from any zoom)
		local d = def.Radius * 2.4
		local ring = disc(b, "MiniRing", d / scale, 0.2, rgb(255, 70, 70), Vector3.new(0, -height + 0.12, 0), NEON)
		ring.Transparency = 0.45
	end
	if string.find(v, "s", 1, true) then
		-- a sketch (THE ERASER's redraw): pencil on paper
		for _, p in b.Parts do
			p.Color = SKETCH:Lerp(p.Color, 0.12)
			p.Material = Enum.Material.SmoothPlastic
			p.Transparency = math.max(p.Transparency, 0.25)
		end
	end
	local root = b.Root :: BasePart
	model.PrimaryPart = root
	-- parts that change with the state / the phase
	local toggles, phased = {}, {}
	for _, p in b.Parts do
		local show, hide = p:GetAttribute("ShowIn"), p:GetAttribute("HideIn")
		if show or hide then
			table.insert(toggles, { Part = p, ShowIn = show, HideIn = hide, Base = p.Transparency })
		end
		local ph, phHide = p:GetAttribute("Phase"), p:GetAttribute("PhaseHide")
		if ph or phHide then
			table.insert(phased, { Part = p, Phase = ph, PhaseHide = phHide, Base = p.Transparency })
		end
	end
	-- how far the model reaches above its root (name plates of mini-bosses sit above it)
	local reach = 0
	for _, p in b.Parts do
		reach = math.max(reach, p.Position.Y + halfHeight(p) - root.Position.Y)
	end
	local info = {
		Height = height * scale,
		Top = reach,
		BodyColor = root.Color,
		Scale = scale,
		Parts = b.Parts,
		Float = FLOAT[def.Model] == true or FLOAT_ANIM[def.AnimType or ""] == true,
		Toggles = if #toggles > 0 then toggles else nil,
		Phased = if #phased > 0 then phased else nil,
		Anims = if #b.Anims > 0 then b.Anims else nil,
		AnimType = def.AnimType,
		Regrow = b.Regrow,
		Light = model:FindFirstChildWhichIsA("PointLight", true), -- (Render/EnemyAnimator lights the nearest)
	}
	local item = { Root = root, Info = info }
	EnemyModels.Toggle(item, 0)
	EnemyModels.SetPhase(item, 1)
	return model, root, info
end

-- the parts that only show in some states (EState): a Snoozer's eyelids, a Shielder's shield
function EnemyModels.Toggle(item, state: number)
	local toggles = item.Info.Toggles
	if not toggles then
		return
	end
	for _, t in toggles do
		local visible = (t.ShowIn == nil or t.ShowIn == state) and t.HideIn ~= state
		t.Part.Transparency = if visible then t.Base else 1
	end
	-- (a broken shield stays broken until the model goes back to the pool)
	if state == 8 then
		item.Info.Broken = true
	elseif item.Info.Broken and not item.Info.Regrow then
		for _, t in toggles do
			if t.HideIn == 8 then
				t.Part.Transparency = 1
			end
		end
	end
end

-- a main boss's look in phase n
function EnemyModels.SetPhase(item, phase: number)
	item.Info.PhaseNow = phase -- (Render/EnemyAnimator: some parts move faster later in the fight)
	local phased = item.Info.Phased
	if not phased then
		return
	end
	for _, t in phased do
		local visible = (t.Phase == nil or phase >= t.Phase) and not (t.PhaseHide ~= nil and phase >= t.PhaseHide)
		t.Part.Transparency = if visible then t.Base else 1
	end
end

---------------------------------------------------------------------------- elite affixes
local AFFIX = {}

local function extraPart(item, name: string, size: Vector3, color: Color3, offset: CFrame, shape: Enum.PartType?, material: Enum.Material?): BasePart
	local root = item.Root
	local scale = item.Info.Scale
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size * scale
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Anchored = false
	if shape then
		p.Shape = shape
	end
	p.CFrame = root.CFrame * CFrame.new(offset.Position * scale) * offset.Rotation
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = root.Parent
	item.Extra = item.Extra or {}
	table.insert(item.Extra, p)
	return p
end

local function feet(item): number
	return -item.Info.Height / item.Info.Scale
end

-- SHIELDED: a pale blue shield ring around it
function AFFIX.Shielded(item)
	local ring = extraPart(item, "AffixShield", Vector3.new(0.3, 4.6, 4.6), rgb(150, 220, 255), CFrame.new(0, feet(item) + 1.2, 0) * FLAT, CYL, NEON)
	ring.Transparency = 0.55
end

-- CURSED: a pale yellow halo over its head
function AFFIX.Cursed(item)
	local y = item.Info.Top / item.Info.Scale + 0.4
	local halo = extraPart(item, "AffixCurse", Vector3.new(0.2, 2.2, 2.2), rgb(250, 240, 150), CFrame.new(0, y, 0) * FLAT, CYL, NEON)
	halo.Transparency = 0.2
end

-- BERSERK: red eyes
function AFFIX.Berserk(item)
	for _, p in item.Info.Parts do
		if p.Name == "Eye" or p.Name == "EyeL" or p.Name == "EyeR" then
			item.Recolored = item.Recolored or {}
			table.insert(item.Recolored, { Part = p, Color = p.Color, Material = p.Material })
			p.Color = rgb(255, 50, 50)
			p.Material = NEON
		end
	end
end

-- BURNING: a flame on its back
function AFFIX.Burning(item)
	local y = item.Info.Top / item.Info.Scale - 0.2
	extraPart(item, "AffixFlame", Vector3.new(0.9, 1.3, 0.9), rgb(255, 236, 150), CFrame.new(0, y, 0.6), BALL, NEON)
end

-- GRAVITY: a violet ring on the ground (its pull)
function AFFIX.Gravity(item)
	local ring = extraPart(item, "AffixGravity", Vector3.new(0.12, 9, 9), rgb(190, 150, 255), CFrame.new(0, feet(item) + 0.2, 0) * FLAT, CYL, NEON)
	ring.Transparency = 0.7
end

-- THORNED: spikes all around it
function AFFIX.Thorned(item)
	for i = 0, 5 do
		local a = i * TAU / 6
		extraPart(item, "AffixThorn", Vector3.new(0.3, 0.3, 1.2), rgb(230, 230, 236), CFrame.new(math.cos(a) * 1.4, 0.2, math.sin(a) * 1.4) * CFrame.Angles(0, -a + math.pi / 2, 0))
	end
end

-- ECHO: a cyan afterimage ring trailing it
function AFFIX.Echo(item)
	local ring = extraPart(item, "AffixEcho", Vector3.new(0.2, 3.4, 3.4), rgb(120, 230, 255), CFrame.new(0, 0, 1.2) * FRONT, CYL, NEON)
	ring.Transparency = 0.5
end

-- GILDED 67: all gold, a 67 over its head
function AFFIX.Gilded67(item)
	item.Recolored = item.Recolored or {}
	for _, p in item.Info.Parts do
		if p.Name ~= "Eye" and p.Name ~= "Pupil" and p.Name ~= "EliteCrest" then
			table.insert(item.Recolored, { Part = p, Color = p.Color, Material = p.Material })
			p.Color = GOLD:Lerp(p.Color, 0.15)
		end
	end
	item.BodyColor0 = item.Info.BodyColor
	item.Info.BodyColor = item.Root.Color
	local gui = Instance.new("BillboardGui")
	gui.Name = "Affix67"
	gui.Size = UDim2.fromScale(3, 1.8)
	gui.StudsOffset = Vector3.new(0, item.Info.Top + 1.4, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "67"
	label.TextScaled = true
	label.Font = Enum.Font.LuckiestGuy
	label.TextColor3 = GOLD
	label.Parent = gui
	gui.Parent = item.Root
	item.Gui = gui
end

-- an elite's affixes on its body (keys of shared/EnemyData.lua EliteAffixes)
function EnemyModels.DressAffixes(item, keys: { string })
	for _, key in keys do
		local dress = AFFIX[key]
		if dress then
			dress(item)
		end
	end
end

-- back to the pooled look: no affixes, normal state, phase 1
function EnemyModels.Reset(item)
	if item.Extra then
		for _, p in item.Extra do
			p:Destroy()
		end
		item.Extra = nil
	end
	if item.Recolored then
		for _, r in item.Recolored do
			r.Part.Color = r.Color
			r.Part.Material = r.Material
		end
		item.Recolored = nil
	end
	if item.BodyColor0 then
		item.Info.BodyColor = item.BodyColor0
		item.Root.Color = item.BodyColor0
		item.BodyColor0 = nil
	end
	if item.Gui then
		item.Gui:Destroy()
		item.Gui = nil
	end
	item.Info.Broken = nil
	EnemyModels.Toggle(item, 0)
	EnemyModels.SetPhase(item, 1)
	if item.Info.Anims then
		for _, a in item.Info.Anims do
			a.Motor.C0 = a.Base
			a.Part.Color = a.Color
		end
	end
	if item.Info.Mesh then
		item.Info.Mesh.Scale = Vector3.one -- (a hop's squash)
	end
	if item.Info.Light then
		item.Info.Light.Enabled = false
	end
end

EnemyModels.Styles = STYLES

-- the builders the bestiary's models use (Render/BestiaryModels.lua)
EnemyModels.Kit = {
	ball = ball,
	box = box,
	cyl = cyl,
	disc = disc,
	wedge = wedge,
	tag = tag,
	anim = anim,
	mark = mark,
	paint = paint,
	cartoonEyes = cartoonEyes,
	glowEyes = glowEyes,
	googlyEyes = googlyEyes,
	WHITE = WHITE,
	BLACK = BLACK,
	GOLD = GOLD,
	NEON = NEON,
	FLAT = FLAT,
	FRONT = FRONT,
}
require(script.Parent.BestiaryModels).Register(STYLES, EnemyModels.Kit)

return EnemyModels
