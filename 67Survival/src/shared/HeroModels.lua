--[[
	HeroModels - the 15 hero models: smooth, clean, minimal.

	Visual language: "few high-quality shapes". Bodies, heads and limbs are ELLIPSOIDS (a part
	with a SpecialMesh of type Sphere fills its box exactly, so any egg / capsule-like
	proportion is one smooth shape), balls and cylinders for round details, blocks only where
	a crisp edge IS the design (a katana blade, a screen, THE GLITCH's cube head). Materials:
	SmoothPlastic, Metal (weapons, armour, gold), Glass (lenses, visors) and Neon ONLY for
	energy (orbs, flames, visors of energy, THE 67's screen).

	Every hero has its own silhouette + weapon + accessory + accent colour (a cap and a
	blaster, swept hair and big sneakers, a huge round shield, a hood and a bow, a backpack
	with a glowing jar, a kabuto and a katana, a wizard hat, beard and staff, a hardhat and a drone, a top hat and a lucky coin,
	a blob, a hooded void, a cube head, flames, a screen that says 67, a faceless hood...).

	Used by
	  * the server (CharacterManager): parts WELDED to an invisible character rig; arms and
	    legs are joined with Motor6Ds ("Limb" .. name) so the client (HeroAnimator) swings
	    them while walking and poses them for emotes
	  * the client menus (UI/Previews) and the lobby: ANCHORED parts (a static pose)
	so a hero looks the same everywhere.

	Coordinates are relative to the character's HumanoidRootPart centre: feet at y = -3,
	front = -Z. A piece: { Name, Size, At, Role, Mesh?, Shape?, Material?, Limb?, Headgear?,
	Text?, Transparency? }. Roles are coloured by the hero palette (or the equipped hero skin):
	  Primary Secondary Accent Glow(accent, neon) Skin Dark Metal Gold White Eye Shine Glass
	Headgear pieces are left out when a hat cosmetic is worn (the hat replaces them).
	The first five heroes (Rookie, Runner, Tank, Hunter, Collector) share one chibi design
	system: face(), kitArms() and kitLegs() below.
]]

local HeroModels = {}

local rgb = Color3.fromRGB
local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
local NEON = Enum.Material.Neon
local UP = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis (X) turned up (Y)
local FRONT = CFrame.Angles(0, math.rad(90), 0) -- a cylinder's axis turned to the front (Z)
local ang = CFrame.Angles

export type Piece = {
	Name: string,
	Size: Vector3,
	At: CFrame,
	Role: string?,
	Color: Color3?,
	Shape: Enum.PartType?,
	Mesh: string?,
	Material: Enum.Material?,
	Limb: string?,
	Headgear: boolean?,
	Text: string?,
	TextColor: Color3?,
	Transparency: number?,
	Spin: number?, -- hats: turns around the hat's axis (radians per second; the client animates it)
}

---------------------------------------------------------------------------
-- shape helpers
---------------------------------------------------------------------------
local function mk(size: Vector3, at: CFrame, name: string, role: string, extra: { [string]: any }?): Piece
	local p: any = { Name = name, Size = size, At = at, Role = role }
	if extra then
		for k, v in extra do
			if k == "R" then
				p.At = p.At * v
			elseif k ~= "Axis" then
				p[k] = v
			end
		end
	end
	return p
end

-- ellipsoid filling a sx * sy * sz box (the main shape of the whole style)
local function E(name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, role: string, extra: { [string]: any }?): Piece
	local p = mk(Vector3.new(sx, sy, sz), CFrame.new(x, y, z), name, role, extra)
	p.Mesh = "Sphere"
	return p
end

-- ball of diameter d
local function S(name: string, d: number, x: number, y: number, z: number, role: string, extra: { [string]: any }?): Piece
	local p = mk(Vector3.new(d, d, d), CFrame.new(x, y, z), name, role, extra)
	p.Shape = BALL
	return p
end

-- cylinder of length h and diameter d; extra.Axis = "Y" (standing, default) | "Z" (facing front) | "X"
local function C(name: string, h: number, d: number, x: number, y: number, z: number, role: string, extra: { [string]: any }?): Piece
	local p = mk(Vector3.new(h, d, d), CFrame.new(x, y, z), name, role, extra)
	local axis = extra and extra.Axis or "Y"
	p.At = p.At * (if axis == "Z" then FRONT elseif axis == "X" then CFrame.identity else UP)
	p.Shape = CYL
	return p
end

-- block (only where a crisp edge is the design)
local function B(name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, role: string, extra: { [string]: any }?): Piece
	return mk(Vector3.new(sx, sy, sz), CFrame.new(x, y, z), name, role, extra)
end

local function join(...: { Piece }): { Piece }
	local out = {}
	for _, list in { ... } do
		for _, p in list do
			table.insert(out, p)
		end
	end
	return out
end

-- pieces modelled in their own frame (a weapon held at an angle), placed with `frame`
local function inFrame(frame: CFrame, list: { Piece }, extra: { [string]: any }?): { Piece }
	for _, p in list do
		p.At = frame * p.At
		if extra then
			for k, v in extra do
				(p :: any)[k] = v
			end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- body parts shared by the humanoid heroes (proportions: big head, small body)
---------------------------------------------------------------------------
type LegOpts = { X: number?, Leg: Vector3?, LegY: number?, Shoe: Vector3?, Role: string?, ShoeRole: string?, ShoeZ: number? }

local function legs(o: LegOpts?): { Piece }
	local opt = o or {}
	local x = opt.X or 0.43
	local leg = opt.Leg or Vector3.new(0.62, 1.0, 0.68)
	local legY = opt.LegY or -2.3
	local shoe = opt.Shoe or Vector3.new(0.74, 0.46, 1.0)
	local out = {}
	for _, side in { -1, 1 } do
		local limb = if side < 0 then "LegL" else "LegR"
		local s = if side < 0 then "L" else "R"
		table.insert(out, E("Leg" .. s, leg.X, leg.Y, leg.Z, side * x, legY, 0.02, opt.Role or "Dark", { Limb = limb }))
		table.insert(out, E("Shoe" .. s, shoe.X, shoe.Y, shoe.Z, side * x, -3 + shoe.Y / 2, opt.ShoeZ or -0.12, opt.ShoeRole or "White", { Limb = limb }))
	end
	return out
end

type ArmOpts = { X: number?, Y: number?, Arm: Vector3?, Splay: number?, Hand: number?, Role: string?, HandRole: string?, Swing: number?, NoHands: boolean? }

local function arms(o: ArmOpts?): { Piece }
	local opt = o or {}
	local x = opt.X or 1.08
	local y = opt.Y or -1.0
	local arm = opt.Arm or Vector3.new(0.5, 1.12, 0.56)
	local splay = opt.Splay or 0.16
	local swing = opt.Swing or 0
	local out = {}
	for _, side in { -1, 1 } do
		local limb = if side < 0 then "ArmL" else "ArmR"
		local s = if side < 0 then "L" else "R"
		local rot = ang(swing, 0, side * splay)
		table.insert(out, E("Arm" .. s, arm.X, arm.Y, arm.Z, side * x, y, 0, opt.Role or "Primary", { Limb = limb, R = rot }))
		if not opt.NoHands then
			local h = arm.Y / 2 - 0.02
			local hand = CFrame.new(side * x, y, 0) * rot * CFrame.new(0, -h, 0)
			local d = opt.Hand or 0.5
			table.insert(out, mk(Vector3.new(d, d, d), CFrame.new(hand.Position), "Hand" .. s, opt.HandRole or "Skin", { Limb = limb, Shape = BALL }))
		end
	end
	return out
end

type HeadOpts = { Y: number?, Z: number?, Size: Vector3?, Role: string?, EyeY: number?, Spread: number?, Eye: Vector3?, NoShine: boolean? }

-- head + glossy eyes (the eyes sit on the ellipsoid's surface)
local function head(o: HeadOpts?): { Piece }
	local opt = o or {}
	local y = opt.Y or 0.78
	local z0 = opt.Z or 0
	local size = opt.Size or Vector3.new(1.8, 1.62, 1.66)
	local out = { E("Head", size.X, size.Y, size.Z, 0, y, z0, opt.Role or "Skin") }
	local eye = opt.Eye or Vector3.new(0.2, 0.34, 0.1)
	local spread = opt.Spread or 0.3
	local ey = opt.EyeY or 0.03
	local a, b, c = size.X / 2, size.Y / 2, size.Z / 2
	local surface = c * math.sqrt(math.max(0, 1 - (spread / a) ^ 2 - (ey / b) ^ 2))
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		table.insert(out, E("Eye" .. s, eye.X, eye.Y, eye.Z, side * spread, y + ey, z0 - surface + 0.02, "Eye"))
		if not opt.NoShine then
			table.insert(out, S("Shine" .. s, eye.X * 0.42, side * spread - side * 0.035, y + ey + eye.Y * 0.22, z0 - surface - 0.03, "Shine"))
		end
	end
	return out
end

---------------------------------------------------------------------------
-- the heroes
---------------------------------------------------------------------------
HeroModels.Heroes = {}
local H = HeroModels.Heroes

---------------------------------------------------------------------------
-- THE FIRST FIVE (Rookie, Runner, Tank, Hunter, Collector): one design system, built from
-- scratch for 67 SURVIVAL.
--   * a big, slightly wide head (~40% of the height), two tall glossy eyes; the mood comes
--     from brows and lids only (no mouth, no nose)
--   * a compact torso narrower than the head, the jacket / pants split in two big shapes
--   * short arms with big mitten hands, short legs with chunky two-piece shoes
--   * 2-4 colours, few large pieces, one signature silhouette each:
--     CAP + BLASTER · SWEPT HAIR + SNEAKERS · SHOULDERS + SHIELD · HOOD + BOW + QUIVER ·
--     BACKPACK + GLOWING JAR
-- Joints: arms swing from `Shoulder`, legs from `Hip` (the hero's Pivots).
---------------------------------------------------------------------------
type FaceOpts = {
	Y: number, -- head centre height
	Z: number?, -- head centre depth
	Size: Vector3, -- the head ellipsoid
	EyeY: number?, -- eye height from the head centre (eyes a little low = friendlier)
	Spread: number?,
	Eye: Vector3?,
	Look: number?, -- both eyes shifted sideways (a curious glance)
	Brows: { number }?, -- tilt per side {left, right}: + = inner end up (soft), - = inner end down (focused)
	BrowLift: { number }?,
	Brow: Vector3?,
	BrowRole: string?, -- default Dark; the hair's role when the hair is recoloured by skins
	Lid: number?, -- 0..1 of each eye under a skin lid (calm, serious)
}

-- depth of the front surface of an ellipsoid head at (x, y) from its centre
local function surfaceZ(size: Vector3, x: number, y: number): number
	local a, b, c = size.X / 2, size.Y / 2, size.Z / 2
	return -c * math.sqrt(math.max(0, 1 - (x / a) ^ 2 - (y / b) ^ 2))
end

local function face(o: FaceOpts): { Piece }
	local eye = o.Eye or Vector3.new(0.27, 0.44, 0.1)
	local spread = o.Spread or 0.39
	local ey = o.EyeY or -0.06
	local z0 = o.Z or 0
	local look = o.Look or 0
	local out = {}
	for i, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local x = side * spread + look
		local z = z0 + surfaceZ(o.Size, x, ey)
		local y = o.Y + ey
		table.insert(out, E("Eye" .. s, eye.X, eye.Y, eye.Z, x, y, z + 0.01, "Eye"))
		-- one highlight, same corner on both eyes (one light)
		table.insert(out, S("Shine" .. s, eye.X * 0.42, x - eye.X * 0.16, y + eye.Y * 0.2, z - 0.04, "Shine"))
		if o.Lid then
			local top = y + eye.Y / 2
			table.insert(out, E("Lid" .. s, eye.X * 1.4, eye.Y * o.Lid * 2, eye.Z * 1.3, x, top, z - 0.015, "Skin"))
		end
		if o.Brows then
			local brow = o.Brow or Vector3.new(0.36, 0.1, 0.08)
			local by = ey + eye.Y / 2 + 0.13 + (if o.BrowLift then o.BrowLift[i] else 0)
			local bz = z0 + surfaceZ(o.Size, x, by)
			table.insert(out, E("Brow" .. s, brow.X, brow.Y, brow.Z, x, o.Y + by, bz + 0.01, o.BrowRole or "Dark", { R = ang(0, 0, o.Brows[i] * -side) }))
		end
	end
	return out
end

type KitArms = {
	Shoulder: Vector3, -- the right shoulder joint (mirrored for the left)
	Arm: Vector3,
	Hand: Vector3,
	Splay: number?,
	Swing: { number }?, -- forward (+) / back (-) per side {left, right}
	Role: string?,
	HandRole: string?,
}

local function kitArms(o: KitArms): { Piece }
	local out = {}
	for i, side in { -1, 1 } do
		local limb = if side < 0 then "ArmL" else "ArmR"
		local s = if side < 0 then "L" else "R"
		local pivot = CFrame.new(side * o.Shoulder.X, o.Shoulder.Y, o.Shoulder.Z)
		local rot = ang(if o.Swing then -o.Swing[i] else 0, 0, side * (o.Splay or 0.12))
		local arm = pivot * rot * CFrame.new(0, -o.Arm.Y / 2 + 0.12, 0)
		local hand = pivot * rot * CFrame.new(0, -o.Arm.Y + 0.08, 0)
		table.insert(out, mk(o.Arm, arm, "Arm" .. s, o.Role or "Primary", { Limb = limb, Mesh = "Sphere" }))
		table.insert(out, mk(o.Hand, hand, "Hand" .. s, o.HandRole or "Skin", { Limb = limb, Mesh = "Sphere" }))
	end
	return out
end

type KitLegs = {
	Hip: Vector3, -- the right hip joint (mirrored)
	Leg: Vector2, -- thickness (width, depth); the length runs from the hip down into the shoe
	Shoe: Vector3,
	ShoeZ: number?,
	Sole: number?, -- sole thickness
	Role: string?,
	ShoeRole: string?,
	SoleRole: string?,
}

local function kitLegs(o: KitLegs): { Piece }
	local out = {}
	local sole = o.Sole or 0.1
	local shoeY = -3 + sole + o.Shoe.Y / 2 - 0.04
	local top, bottom = o.Hip.Y + 0.08, shoeY + o.Shoe.Y / 2 - 0.12 -- the ankle sinks into the shoe
	for _, side in { -1, 1 } do
		local limb = if side < 0 then "LegL" else "LegR"
		local s = if side < 0 then "L" else "R"
		local x = side * o.Hip.X
		local z = o.ShoeZ or -0.1
		table.insert(out, E("Leg" .. s, o.Leg.X, top - bottom, o.Leg.Y, x, (top + bottom) / 2, 0, o.Role or "Dark", { Limb = limb }))
		table.insert(out, E("Shoe" .. s, o.Shoe.X, o.Shoe.Y, o.Shoe.Z, x, shoeY, z, o.ShoeRole or "White", { Limb = limb }))
		table.insert(out, E("Sole" .. s, o.Shoe.X + 0.05, sole * 2, o.Shoe.Z + 0.05, x, -3 + sole, z, o.SoleRole or "Dark", { Limb = limb }))
	end
	return out
end

-- THE ROOKIE: an open blue jacket over a white T-shirt, a cap with a real brim, white boots
-- and a small round blaster with a cyan tip. "An ordinary guy who just landed in 67 Survival."
local ROOKIE_HEAD = Vector3.new(2.04, 1.8, 1.9)
H.Rookie = {
	Palette = {
		Primary = rgb(52, 112, 226), -- blue
		Secondary = rgb(32, 42, 82), -- navy
		Dark = rgb(32, 42, 82),
		White = rgb(244, 246, 252),
		Accent = rgb(120, 224, 255), -- the blaster's energy
		Skin = rgb(246, 208, 170),
	},
	HatAt = Vector3.new(0, 1.5, 0),
	Top = 1.72,
	Pivots = { ArmL = Vector3.new(-0.74, -0.34, 0), ArmR = Vector3.new(0.74, -0.34, 0), LegL = Vector3.new(-0.36, -1.62, 0), LegR = Vector3.new(0.36, -1.62, 0) },
	Pieces = join(
		kitLegs({ Hip = Vector3.new(0.36, -1.62, 0), Leg = Vector2.new(0.48, 0.5), Shoe = Vector3.new(0.64, 0.46, 0.92) }),
		{
			E("Chest", 1.62, 1.3, 1.14, 0, -0.62, 0, "Primary"),
			E("Tee", 0.76, 1.0, 0.5, 0, -0.54, -0.37, "White"), -- the open jacket shows a white T-shirt
			E("Collar", 1.3, 0.36, 1.08, 0, -0.06, 0, "White"),
			E("Pants", 1.28, 0.9, 0.98, 0, -1.4, 0, "Dark"),
		},
		kitArms({ Shoulder = Vector3.new(0.74, -0.34, 0), Arm = Vector3.new(0.46, 0.92, 0.48), Hand = Vector3.new(0.52, 0.5, 0.54), Splay = 0.14 }),
		{ E("Head", ROOKIE_HEAD.X, ROOKIE_HEAD.Y, ROOKIE_HEAD.Z, 0, 0.62, 0, "Skin"), E("Hair", 2.1, 1.2, 1.9, 0, 0.78, 0.22, "Dark") },
		face({ Y = 0.62, Size = ROOKIE_HEAD, Brows = { 0.12, 0.12 } }),
		{
			E("Cap", 2.14, 1.16, 2.02, 0, 1.1, 0.02, "Primary", { Headgear = true }),
			E("Brim", 1.6, 0.18, 1.2, 0, 0.9, -1.1, "Secondary", { Headgear = true, R = ang(-0.2, 0, 0) }),
			S("CapButton", 0.2, 0, 1.68, 0.02, "White", { Headgear = true }),
		},
		inFrame(CFrame.new(0.98, -1.28, -0.28), {
			E("Blaster", 0.44, 0.42, 0.92, 0, 0.06, -0.2, "White"),
			C("BlasterBand", 0.16, 0.48, 0, 0.06, -0.26, "Primary", { Axis = "Z" }),
			S("BlasterTip", 0.26, 0, 0.06, -0.66, "Glow"),
			E("BlasterGrip", 0.2, 0.34, 0.24, 0, -0.14, 0.06, "Dark"),
		}, { Limb = "ArmR" })
	),
}

-- THE RUNNER: slim and light, leaning forward, arms mid-stride. Hair swept back by the wind,
-- a white chevron on the chest, track pants and big sneakers with a heel fin.
local RUNNER_HEAD = Vector3.new(1.94, 1.74, 1.84)
local RUNNER_LEAN = CFrame.new(0, 0, -0.06) * ang(-0.1, 0, 0) -- the upper body tips forward
H.Runner = {
	Palette = {
		Primary = rgb(222, 58, 62), -- red
		Secondary = rgb(128, 26, 38), -- dark red
		Dark = rgb(128, 26, 38),
		White = rgb(246, 246, 250),
		Accent = rgb(255, 214, 214),
		Skin = rgb(232, 182, 140),
	},
	HatAt = Vector3.new(0, 1.62, -0.12),
	Top = 1.78,
	Pivots = { ArmL = Vector3.new(-0.68, -0.28, -0.04), ArmR = Vector3.new(0.68, -0.28, -0.04), LegL = Vector3.new(-0.32, -1.5, 0), LegR = Vector3.new(0.32, -1.5, 0) },
	Pieces = join(
		kitLegs({ Hip = Vector3.new(0.32, -1.5, 0), Leg = Vector2.new(0.4, 0.42), Shoe = Vector3.new(0.6, 0.42, 1.12), ShoeZ = -0.16, Sole = 0.11, Role = "Secondary", ShoeRole = "White", SoleRole = "Primary" }),
		{
			E("FinL", 0.14, 0.4, 0.46, -0.32, -2.62, 0.36, "Primary", { Limb = "LegL", R = ang(0.5, 0, 0) }),
			E("FinR", 0.14, 0.4, 0.46, 0.32, -2.62, 0.36, "Primary", { Limb = "LegR", R = ang(0.5, 0, 0) }),
		},
		inFrame(RUNNER_LEAN, {
			E("Chest", 1.4, 1.26, 1.04, 0, -0.5, 0, "Primary"),
			E("ChevronL", 0.16, 0.86, 0.1, -0.21, -0.46, -0.5, "White", { R = ang(0, 0, 0.55) }),
			E("ChevronR", 0.16, 0.86, 0.1, 0.21, -0.46, -0.5, "White", { R = ang(0, 0, -0.55) }),
			E("Collar", 1.14, 0.3, 0.98, 0, 0.06, 0, "White"),
		}),
		{ E("Pants", 1.2, 0.78, 0.96, 0, -1.26, 0, "Secondary") },
		kitArms({ Shoulder = Vector3.new(0.68, -0.28, -0.04), Arm = Vector3.new(0.4, 0.88, 0.42), Hand = Vector3.new(0.46, 0.44, 0.48), Splay = 0.1, Swing = { 0.45, -0.45 } }),
		inFrame(RUNNER_LEAN, join(
			{ E("Head", RUNNER_HEAD.X, RUNNER_HEAD.Y, RUNNER_HEAD.Z, 0, 0.7, 0, "Skin") },
			face({ Y = 0.7, Size = RUNNER_HEAD, Eye = Vector3.new(0.27, 0.46, 0.1), Brows = { -0.16, -0.16 }, BrowLift = { 0.03, 0.03 }, BrowRole = "Secondary" }),
			{
				E("Hair", 1.98, 1.24, 1.9, 0, 1.1, 0.2, "Secondary", { R = ang(0.38, 0, 0) }),
				E("Quiff", 0.96, 0.46, 1.0, 0.1, 1.5, -0.4, "Secondary", { Headgear = true, R = ang(0.5, 0, 0.14) }),
				E("SweepTop", 0.72, 0.5, 1.9, 0, 1.46, 0.9, "Secondary", { Headgear = true, R = ang(-0.12, 0, 0) }),
				E("SweepL", 0.56, 0.42, 1.6, -0.58, 1.2, 0.86, "Secondary", { Headgear = true, R = ang(-0.04, -0.3, 0) }),
				E("SweepR", 0.56, 0.42, 1.6, 0.58, 1.2, 0.86, "Secondary", { Headgear = true, R = ang(-0.04, 0.3, 0) }),
			}
		))
	),
}

-- THE TANK: the widest hero. Big shoulders in light armour, a helmet with a green stripe,
-- heavy gauntlets and boots, and a thick round shield with a glowing green core.
local TANK_HEAD = Vector3.new(2.0, 1.76, 1.88)
H.Tank = {
	Palette = {
		Primary = rgb(74, 150, 82), -- green
		Secondary = rgb(204, 210, 216), -- light grey armour
		Dark = rgb(34, 74, 46), -- dark green
		Metal = rgb(146, 156, 168),
		Accent = rgb(126, 255, 150), -- the shield core
		Skin = rgb(232, 190, 150),
	},
	HatAt = Vector3.new(0, 1.66, 0),
	HatScale = 1.06,
	Top = 1.96,
	Pivots = { ArmL = Vector3.new(-1.36, -0.34, 0), ArmR = Vector3.new(1.36, -0.34, 0), LegL = Vector3.new(-0.6, -1.74, 0), LegR = Vector3.new(0.6, -1.74, 0) },
	Pieces = join(
		kitLegs({ Hip = Vector3.new(0.6, -1.74, 0), Leg = Vector2.new(0.74, 0.78), Shoe = Vector3.new(0.96, 0.6, 1.18), ShoeZ = -0.12, Sole = 0.12, Role = "Dark", ShoeRole = "Secondary", SoleRole = "Metal" }),
		{
			E("Chest", 2.36, 1.66, 1.74, 0, -0.66, 0, "Primary"),
			E("Plate", 1.56, 0.96, 0.44, 0, -0.56, -0.78, "Secondary"),
			E("Belt", 2.08, 0.32, 1.6, 0, -1.3, 0, "Metal"),
			E("Hips", 1.86, 0.8, 1.46, 0, -1.56, 0, "Dark"),
			E("PadL", 1.34, 0.84, 1.4, -1.38, -0.08, 0, "Secondary", { R = ang(0, 0, 0.26) }),
			E("PadR", 1.34, 0.84, 1.4, 1.38, -0.08, 0, "Secondary", { R = ang(0, 0, -0.26) }),
		},
		kitArms({ Shoulder = Vector3.new(1.36, -0.34, 0), Arm = Vector3.new(0.7, 1.0, 0.74), Hand = Vector3.new(0.84, 0.74, 0.86), Splay = 0.08, HandRole = "Secondary" }),
		{ E("Head", TANK_HEAD.X, TANK_HEAD.Y, TANK_HEAD.Z, 0, 0.78, 0, "Skin") },
		face({ Y = 0.78, Size = TANK_HEAD, Eye = Vector3.new(0.27, 0.4, 0.1), Lid = 0.42, Brows = { -0.04, -0.04 }, Brow = Vector3.new(0.42, 0.13, 0.09), BrowLift = { -0.04, -0.04 } }),
		{
			E("Helmet", 2.2, 1.24, 2.08, 0, 1.2, 0.04, "Secondary", { Headgear = true }),
			E("Ridge", 0.52, 1.44, 2.26, 0, 1.2, 0.04, "Primary", { Headgear = true }),
		},
		inFrame(CFrame.new(-1.78, -1.12, -0.62) * ang(0, 0.42, 0), {
			C("ShieldRim", 0.26, 2.9, 0, 0, 0.06, "Metal", { Axis = "Z" }),
			C("Shield", 0.34, 2.6, 0, 0, -0.02, "Secondary", { Axis = "Z" }),
			C("ShieldCore", 0.38, 1.08, 0, 0, -0.06, "Primary", { Axis = "Z" }),
			S("ShieldGem", 0.5, 0, 0, -0.2, "Glow"),
		}, { Limb = "ArmL" })
	),
}

-- THE HUNTER: a deep hood (the face peeks out of it) with a hanging tip, a shoulder capelet,
-- an olive jacket, a brown belt, a quiver on the back (3 arrows) and a curved bow.
local HUNTER_HEAD = Vector3.new(1.9, 1.72, 1.82)
H.Hunter = {
	Palette = {
		Primary = rgb(46, 88, 58), -- dark green (hood, cape)
		Secondary = rgb(126, 134, 66), -- olive (jacket)
		Brown = rgb(122, 84, 52),
		Dark = rgb(52, 50, 40),
		Accent = rgb(232, 226, 190), -- fletching
		Skin = rgb(238, 196, 156),
	},
	HatAt = Vector3.new(0, 1.62, 0.08),
	Top = 1.86,
	Pivots = { ArmL = Vector3.new(-0.72, -0.34, 0), ArmR = Vector3.new(0.72, -0.34, 0), LegL = Vector3.new(-0.34, -1.62, 0), LegR = Vector3.new(0.34, -1.62, 0) },
	Pieces = join(
		kitLegs({ Hip = Vector3.new(0.34, -1.62, 0), Leg = Vector2.new(0.46, 0.48), Shoe = Vector3.new(0.62, 0.52, 0.9), Sole = 0.08, Role = "Dark", ShoeRole = "Brown", SoleRole = "Dark" }),
		{
			E("Chest", 1.5, 1.26, 1.1, 0, -0.62, 0, "Secondary"),
			E("Belt", 1.46, 0.26, 1.08, 0, -1.1, 0, "Brown"),
			E("Pants", 1.28, 0.84, 0.98, 0, -1.4, 0, "Dark"),
			E("Capelet", 1.86, 0.6, 1.44, 0, -0.16, 0.06, "Primary"),
		},
		kitArms({ Shoulder = Vector3.new(0.72, -0.34, 0), Arm = Vector3.new(0.44, 0.9, 0.46), Hand = Vector3.new(0.5, 0.46, 0.52), Role = "Secondary", HandRole = "Brown" }),
		{
			E("Head", HUNTER_HEAD.X, HUNTER_HEAD.Y, HUNTER_HEAD.Z, 0, 0.62, -0.2, "Skin"),
			E("Hood", 2.24, 2.0, 2.14, 0, 0.8, 0.12, "Primary"),
			E("HoodTail", 0.6, 0.6, 1.3, 0, 0.98, 1.12, "Primary", { R = ang(1.0, 0, 0) }),
		},
		face({ Y = 0.62, Z = -0.2, Size = HUNTER_HEAD, Eye = Vector3.new(0.28, 0.3, 0.1), Spread = 0.36, EyeY = -0.1, Brows = { -0.2, -0.2 } }),
		{
			C("Quiver", 1.4, 0.44, 0.46, -0.3, 0.72, "Brown", { R = ang(0.2, 0, -0.35) }),
			E("ArrowA", 0.12, 0.36, 0.2, 0.62, 0.42, 0.9, "Accent", { R = ang(0.2, 0, -0.35) }),
			E("ArrowB", 0.12, 0.36, 0.2, 0.78, 0.34, 0.78, "Accent", { R = ang(0.2, 0, -0.35) }),
			E("ArrowC", 0.12, 0.36, 0.2, 0.7, 0.26, 1.0, "Accent", { R = ang(0.2, 0, -0.35) }),
		},
		inFrame(CFrame.new(-1.1, -1.18, -0.5) * ang(0, -0.35, 0.32), {
			E("BowTop", 0.17, 1.44, 0.24, 0, 0.64, -0.18, "Brown", { R = ang(0.3, 0, 0) }),
			E("BowBottom", 0.17, 1.44, 0.24, 0, -0.64, -0.18, "Brown", { R = ang(-0.3, 0, 0) }),
			E("BowGrip", 0.26, 0.46, 0.3, 0, 0, -0.36, "Dark"),
			B("BowString", 0.05, 2.56, 0.05, 0, 0, 0.04, "Accent"),
		}, { Limb = "ArmL" })
	),
}

-- THE COLLECTOR: tidy utility. A compact brown backpack with one big green pocket, a teal
-- bedroll on top and a glass jar with a glowing crystal on the side; teal goggles up on the
-- forehead; teal jacket, green gloves. A curious sideways glance.
local COLLECTOR_HEAD = Vector3.new(2.0, 1.78, 1.86)
H.Collector = {
	Palette = {
		Primary = rgb(38, 168, 170), -- teal
		Secondary = rgb(138, 96, 58), -- brown
		Accent = rgb(96, 184, 90), -- green
		Tan = rgb(178, 130, 82),
		Dark = rgb(58, 52, 50),
		Glass = rgb(170, 236, 236),
		Lens = rgb(84, 206, 214),
		Skin = rgb(242, 202, 160),
	},
	HatAt = Vector3.new(0, 1.52, 0),
	Top = 1.8,
	Pivots = { ArmL = Vector3.new(-0.74, -0.34, 0), ArmR = Vector3.new(0.74, -0.34, 0), LegL = Vector3.new(-0.36, -1.62, 0), LegR = Vector3.new(0.36, -1.62, 0) },
	Pieces = join(
		kitLegs({ Hip = Vector3.new(0.36, -1.62, 0), Leg = Vector2.new(0.48, 0.5), Shoe = Vector3.new(0.64, 0.5, 0.92), ShoeRole = "Secondary", SoleRole = "Dark" }),
		{
			E("Chest", 1.56, 1.28, 1.12, 0, -0.62, 0, "Primary"),
			E("Pants", 1.3, 0.86, 1.0, 0, -1.38, 0, "Dark"),
		},
		kitArms({ Shoulder = Vector3.new(0.74, -0.34, 0), Arm = Vector3.new(0.46, 0.9, 0.48), Hand = Vector3.new(0.52, 0.48, 0.54), HandRole = "Accent" }),
		{
			E("Head", COLLECTOR_HEAD.X, COLLECTOR_HEAD.Y, COLLECTOR_HEAD.Z, 0, 0.64, 0, "Skin"),
			E("Hair", 2.08, 1.18, 1.94, 0, 1.04, 0.14, "Dark"),
		},
		face({ Y = 0.64, Size = COLLECTOR_HEAD, Look = 0.07, Brows = { 0.22, -0.06 }, BrowLift = { 0.07, 0 } }),
		{
			C("GoggleBand", 0.2, 2.12, 0, 1.14, 0.04, "Dark", { Headgear = true }),
			C("GoggleL", 0.16, 0.5, -0.32, 1.18, -0.88, "Lens", { Headgear = true, Material = Enum.Material.Glass, Axis = "Z", R = ang(0.3, 0, 0) }),
			C("GoggleR", 0.16, 0.5, 0.32, 1.18, -0.88, "Lens", { Headgear = true, Material = Enum.Material.Glass, Axis = "Z", R = ang(0.3, 0, 0) }),
			E("Pack", 1.66, 1.8, 1.1, 0, -0.5, 0.9, "Secondary"),
			E("Pocket", 1.24, 0.96, 0.5, 0, -0.74, 1.38, "Accent"),
			C("Bedroll", 1.52, 0.46, 0, 0.5, 0.96, "Primary", { Axis = "X" }),
			C("Jar", 0.7, 0.5, 0.98, -0.56, 0.92, "Glass", { Transparency = 0.35 }),
			E("Crystal", 0.24, 0.44, 0.24, 0.98, -0.58, 0.92, "Glow"),
			C("JarLid", 0.12, 0.54, 0.98, -0.18, 0.92, "Metal"),
		}
	),
}

-- THE SAMURAI: a kabuto with a golden crest, shoulder plates, a katana
local katana = inFrame(CFrame.new(1.2, -1.6, -0.24) * ang(0.35, 0, 0), {
	C("Handle", 0.9, 0.2, 0, 0, 0.1, "Secondary", { Axis = "Z" }),
	C("Guard", 0.08, 0.56, 0, 0, -0.38, "Gold", { Axis = "Z" }),
	B("Blade", 0.1, 0.26, 2.9, 0, 0, -1.86, "Metal", { Material = Enum.Material.Metal }),
}, { Limb = "ArmR" })
H.Samurai = {
	Palette = { Primary = rgb(204, 42, 54), Secondary = rgb(32, 32, 40), Accent = rgb(255, 96, 96), Skin = rgb(236, 196, 152), Gold = rgb(255, 202, 72), Dark = rgb(32, 32, 40) },
	HatAt = Vector3.new(0, 1.58, 0),
	Top = 2.3,
	Pieces = join({
		E("LegL", 0.5, 0.62, 0.5, -0.4, -2.6, 0, "Secondary", { Limb = "LegL" }),
		E("LegR", 0.5, 0.62, 0.5, 0.4, -2.6, 0, "Secondary", { Limb = "LegR" }),
		E("SandalL", 0.64, 0.3, 0.96, -0.4, -2.85, -0.18, "Dark", { Limb = "LegL" }),
		E("SandalR", 0.64, 0.3, 0.96, 0.4, -2.85, -0.18, "Dark", { Limb = "LegR" }),
		E("Hakama", 2.0, 1.36, 1.46, 0, -2.2, 0, "Secondary"),
		E("Body", 1.8, 1.72, 1.3, 0, -0.95, 0, "Primary"),
		E("CollarL", 0.16, 1.0, 0.1, -0.2, -0.62, -0.63, "White", { R = ang(0, 0, -0.45) }),
		E("CollarR", 0.16, 1.0, 0.1, 0.2, -0.62, -0.63, "White", { R = ang(0, 0, 0.45) }),
		E("Obi", 1.86, 0.36, 1.36, 0, -1.55, 0, "Secondary"),
		E("Knot", 0.36, 0.3, 0.2, 0, -1.55, -0.7, "Gold"),
		E("SodeL", 1.06, 0.3, 1.36, -1.22, -0.2, 0, "Primary", { R = ang(0, 0, 0.42) }),
		E("SodeR", 1.06, 0.3, 1.36, 1.22, -0.2, 0, "Primary", { R = ang(0, 0, -0.42) }),
	}, arms(), head({ Eye = Vector3.new(0.26, 0.17, 0.1) }), {
		E("Kabuto", 1.9, 1.06, 1.9, 0, 1.24, 0, "Secondary", { Headgear = true }),
		E("NeckGuard", 2.46, 0.22, 2.3, 0, 0.98, 0.1, "Secondary", { Headgear = true, R = ang(0.1, 0, 0) }),
		E("CrestL", 0.14, 0.96, 0.12, -0.3, 1.94, -0.72, "Gold", { Headgear = true, R = ang(0, 0, 0.45) }),
		E("CrestR", 0.14, 0.96, 0.12, 0.3, 1.94, -0.72, "Gold", { Headgear = true, R = ang(0, 0, -0.45) }),
		C("CrestDisc", 0.08, 0.36, 0, 1.52, -0.9, "Gold", { Headgear = true, Axis = "Z" }),
	}, katana),
}

-- THE MAGE: a tall bent wizard hat, a white beard, a robe and a staff with an arcane orb
H.Mage = {
	Palette = { Primary = rgb(122, 72, 222), Secondary = rgb(140, 96, 62), Accent = rgb(92, 232, 255), Skin = rgb(242, 206, 166), Gold = rgb(255, 206, 84), Dark = rgb(40, 34, 60) },
	HatAt = Vector3.new(0, 1.4, 0.04),
	Top = 3.2,
	Pieces = join({
		E("ShoeL", 0.6, 0.32, 0.9, -0.38, -2.86, -0.26, "Dark", { Limb = "LegL" }),
		E("ShoeR", 0.6, 0.32, 0.9, 0.38, -2.86, -0.26, "Dark", { Limb = "LegR" }),
		E("Robe", 2.2, 1.9, 1.8, 0, -2.02, 0, "Primary"),
		E("Chest", 1.66, 1.42, 1.26, 0, -0.76, 0, "Primary"),
		E("Belt", 1.72, 0.22, 1.32, 0, -1.3, 0, "Gold"),
	}, arms({ Y = -0.86, Arm = Vector3.new(0.62, 1.14, 0.66), Role = "Primary", Hand = 0.46 }), head({ Y = 0.62, Size = Vector3.new(1.6, 1.5, 1.56) }), {
		E("Beard", 1.08, 0.94, 0.5, 0, 0.18, -0.6, "White"),
		E("Brim", 2.72, 0.16, 2.72, 0, 1.2, 0.05, "Primary", { Headgear = true }),
		E("HatBand", 1.62, 0.26, 1.62, 0, 1.38, 0.06, "Gold", { Headgear = true }),
		E("HatA", 1.56, 0.82, 1.56, 0, 1.56, 0.08, "Primary", { Headgear = true }),
		E("HatB", 1.1, 0.82, 1.1, 0, 2.12, 0.2, "Primary", { Headgear = true, R = ang(-0.12, 0, 0) }),
		E("HatC", 0.64, 0.76, 0.64, 0, 2.64, 0.4, "Primary", { Headgear = true, R = ang(-0.34, 0, 0) }),
		S("HatTip", 0.26, 0, 2.98, 0.6, "Gold", { Headgear = true }),
	}, inFrame(CFrame.new(1.32, -0.76, -0.28), {
		C("Staff", 4.5, 0.24, 0, 0, 0, "Secondary"),
		E("Cradle", 0.56, 0.36, 0.56, 0, 2.28, 0, "Gold"),
		S("Orb", 0.8, 0, 2.66, 0, "Glow"),
	}, { Limb = "ArmR" })),
}

-- THE ENGINEER: overalls, a hardhat with goggles, a generator backpack, a drone
H.Engineer = {
	Palette = { Primary = rgb(255, 150, 42), Secondary = rgb(52, 72, 122), Accent = rgb(92, 222, 255), Skin = rgb(236, 192, 152), Gold = rgb(255, 214, 64), Dark = rgb(40, 44, 58) },
	HatAt = Vector3.new(0, 1.66, 0),
	Top = 1.95,
	Pieces = join(legs({ Role = "Primary", ShoeRole = "Dark" }), {
		E("Body", 1.84, 1.84, 1.3, 0, -1.02, 0, "Secondary"),
		E("Bib", 1.3, 1.18, 0.32, 0, -1.12, -0.54, "Primary"),
		E("StrapL", 0.22, 0.9, 0.12, -0.46, -0.44, -0.55, "Primary"),
		E("StrapR", 0.22, 0.9, 0.12, 0.46, -0.44, -0.55, "Primary"),
		E("ToolBelt", 1.9, 0.3, 1.4, 0, -1.62, 0, "Dark"),
		E("Generator", 1.3, 1.46, 0.8, 0, -0.76, 0.9, "Metal"),
		C("Antenna", 1.2, 0.08, 0.4, 0.34, 1.05, "Dark"),
		S("AntennaTip", 0.22, 0.4, 0.96, 1.05, "Glow"),
	}, arms({ Role = "Secondary" }), head(), {
		E("Hardhat", 1.86, 1.0, 1.86, 0, 1.22, 0, "Hard", { Headgear = true }),
		E("HatBrim", 2.16, 0.14, 2.2, 0, 1.0, -0.08, "Hard", { Headgear = true }),
		E("HatRidge", 0.26, 0.36, 1.7, 0, 1.6, 0, "Hard", { Headgear = true }),
		C("LensL", 0.14, 0.44, -0.32, 1.2, -0.9, "Glass", { Headgear = true, Axis = "Z" }),
		C("LensR", 0.14, 0.44, 0.32, 1.2, -0.9, "Glass", { Headgear = true, Axis = "Z" }),
		E("DroneBody", 1.0, 0.4, 1.0, 1.62, 1.2, 0.3, "Metal"),
		C("Rotor", 0.05, 1.36, 1.62, 1.46, 0.3, "Dark", { Transparency = 0.35 }),
		S("DroneEye", 0.26, 1.62, 1.18, -0.16, "Glow"),
	}, inFrame(CFrame.new(-1.24, -1.62, -0.3), {
		C("WrenchHandle", 1.2, 0.18, 0, -0.34, 0, "Metal"),
		E("WrenchHead", 0.56, 0.3, 0.2, 0, 0.28, 0, "Metal"),
	}, { Limb = "ArmL" })),
}

-- THE LUCKY: a round body, a top hat with a clover, a bow tie, a shiny lucky coin
H.Lucky = {
	Palette = { Primary = rgb(62, 190, 94), Secondary = rgb(32, 32, 40), Accent = rgb(255, 216, 84), Skin = rgb(242, 206, 166), Gold = rgb(255, 204, 62), Dark = rgb(40, 44, 52) },
	HatAt = Vector3.new(0, 1.58, 0),
	Top = 2.8,
	Pieces = join(legs({ ShoeRole = "Secondary" }), {
		E("Body", 2.3, 2.2, 2.0, 0, -1.14, 0, "Primary"),
		S("ButtonA", 0.2, 0, -0.9, -0.99, "Gold"),
		S("ButtonB", 0.2, 0, -1.4, -0.99, "Gold"),
		E("BowL", 0.44, 0.32, 0.16, -0.21, -0.12, -0.92, "Accent"),
		E("BowR", 0.44, 0.32, 0.16, 0.21, -0.12, -0.92, "Accent"),
		S("BowKnot", 0.17, 0, -0.12, -1.0, "Accent"),
	}, arms({ X = 1.2, Y = -1.05 }), head({ Y = 0.8, Size = Vector3.new(1.62, 1.5, 1.56) }), {
		E("Smile", 0.44, 0.09, 0.06, 0, 0.44, -0.72, "Eye"),
		E("HatBrim", 2.1, 0.14, 2.1, 0, 1.5, 0, "Secondary", { Headgear = true }),
		C("HatCrown", 1.2, 1.3, 0, 2.12, 0, "Secondary", { Headgear = true }),
		C("HatBand", 0.28, 1.34, 0, 1.7, 0, "Primary", { Headgear = true }),
		S("CloverA", 0.28, -0.14, 1.8, -0.66, "Primary", { Headgear = true }),
		S("CloverB", 0.28, 0.14, 1.8, -0.66, "Primary", { Headgear = true }),
		S("CloverC", 0.28, 0, 2.04, -0.66, "Primary", { Headgear = true }),
	}, inFrame(CFrame.new(1.34, -1.62, -0.5), {
		C("Coin", 0.12, 0.92, 0, 0.34, 0, "Gold", { Axis = "Z" }),
		C("CoinFace", 0.14, 0.6, 0, 0.34, -0.01, "Accent", { Axis = "Z" }),
	}, { Limb = "ArmR" })),
}

-- THE GOOBER: a big friendly blob with googly eyes, an antenna and a mini goober friend
H.Goober = {
	Palette = { Primary = rgb(124, 222, 94), Secondary = rgb(82, 162, 62), Accent = rgb(255, 112, 192), Skin = rgb(124, 222, 94), Belly = rgb(186, 244, 156) },
	HatAt = Vector3.new(0, -0.28, 0),
	HatScale = 1.2,
	Top = 1.2,
	Pivots = { ArmL = Vector3.new(-1.4, -1.3, 0), ArmR = Vector3.new(1.4, -1.3, 0), LegL = Vector3.new(-0.72, -2.4, 0), LegR = Vector3.new(0.72, -2.4, 0) },
	Pieces = {
		E("FootL", 0.96, 0.5, 1.1, -0.72, -2.75, -0.24, "Secondary", { Limb = "LegL" }),
		E("FootR", 0.96, 0.5, 1.1, 0.72, -2.75, -0.24, "Secondary", { Limb = "LegR" }),
		E("Blob", 3.0, 2.64, 3.0, 0, -1.55, 0, "Primary"),
		E("Belly", 2.0, 1.6, 0.6, 0, -1.84, -1.14, "Belly"),
		E("ArmL", 0.46, 0.84, 0.46, -1.56, -1.62, -0.1, "Primary", { Limb = "ArmL", R = ang(0, 0, -0.6) }),
		E("ArmR", 0.46, 0.84, 0.46, 1.56, -1.62, -0.1, "Primary", { Limb = "ArmR", R = ang(0, 0, 0.6) }),
		E("EyeWhiteL", 0.86, 0.96, 0.5, -0.5, -0.86, -1.26, "White"),
		E("EyeWhiteR", 0.86, 0.96, 0.5, 0.5, -0.86, -1.26, "White"),
		E("PupilL", 0.38, 0.42, 0.2, -0.42, -0.92, -1.5, "Eye"),
		E("PupilR", 0.38, 0.42, 0.2, 0.58, -0.78, -1.5, "Eye"),
		S("ShineL", 0.12, -0.48, -0.8, -1.6, "Shine"),
		S("ShineR", 0.12, 0.52, -0.66, -1.6, "Shine"),
		E("Mouth", 0.7, 0.16, 0.1, 0, -1.62, -1.44, "Eye"),
		C("Stalk", 1.0, 0.12, 0, 0.18, 0, "Secondary", { Headgear = true }),
		S("Bobble", 0.6, 0, 0.78, 0, "Accent", { Headgear = true }),
		E("Buddy", 0.96, 0.86, 0.96, 1.5, -0.36, 0.3, "Primary"),
		S("BuddyEyeL", 0.22, 1.36, -0.28, -0.12, "White"),
		S("BuddyEyeR", 0.22, 1.62, -0.28, -0.12, "White"),
	},
}

-- THE VOID: a faceless hooded shape with glowing slit eyes and floating shards, no legs
H.Void = {
	Palette = { Primary = rgb(62, 32, 104), Secondary = rgb(42, 36, 62), Accent = rgb(172, 92, 255), Skin = rgb(28, 24, 42), Dark = rgb(24, 22, 34) },
	HatAt = Vector3.new(0, 1.78, 0.1),
	Top = 1.95,
	Pieces = join({
		E("Tail", 1.12, 1.4, 0.92, 0, -2.2, 0.1, "Dark"),
		E("Wisp", 0.6, 0.8, 0.5, 0, -2.78, 0.26, "Dark", { Transparency = 0.25 }),
		E("Body", 1.86, 2.0, 1.32, 0, -0.86, 0, "Dark"),
		E("Collar", 2.16, 0.46, 1.56, 0, 0.08, 0, "Primary"),
	}, arms({ X = 1.14, Y = -0.95, Arm = Vector3.new(0.46, 1.0, 0.5), Role = "Dark", HandRole = "Primary", Hand = 0.44 }), {
		E("Hood", 1.82, 1.72, 1.76, 0, 1.0, 0.12, "Primary"),
		E("Head", 1.56, 1.5, 1.5, 0, 0.9, -0.02, "Dark"),
		E("EyeL", 0.42, 0.13, 0.08, -0.3, 0.92, -0.74, "Glow"),
		E("EyeR", 0.42, 0.13, 0.08, 0.3, 0.92, -0.74, "Glow"),
		E("ShardA", 0.28, 0.76, 0.28, -1.66, -0.2, -0.3, "Glow", { R = ang(0, 0, 0.4) }),
		E("ShardB", 0.28, 0.76, 0.28, 1.72, -0.5, 0.46, "Glow", { R = ang(0, 0, -0.35) }),
		E("ShardC", 0.24, 0.62, 0.24, 1.16, 1.06, -0.56, "Glow", { R = ang(0.5, 0, 0.3) }),
	}),
}

-- THE GLITCH: a cube head with pixel eyes and an RGB split, a body with a missing chunk
H.Glitch = {
	Voxel = true, -- the only blocky hero on purpose: cubes are its look
	Palette = { Primary = rgb(42, 222, 232), Secondary = rgb(255, 62, 202), Accent = rgb(255, 62, 202), Skin = rgb(242, 242, 248), White = rgb(242, 242, 248), Dark = rgb(34, 36, 50) },
	HatAt = Vector3.new(0, 1.66, 0),
	Top = 1.86,
	Pieces = join(legs({ ShoeRole = "Primary" }), {
		E("Body", 1.84, 1.84, 1.3, 0, -1.02, 0, "Primary"),
		B("Chunk", 0.6, 0.6, 1.4, 0.56, -0.62, 0, "Dark"),
	}, arms({ HandRole = "White" }), {
		B("Head", 1.6, 1.6, 1.6, 0, 0.86, 0, "White"),
		B("Ghost", 1.62, 1.62, 1.62, 0.12, 0.92, 0.06, "Secondary", { Transparency = 0.62 }),
		B("PixelEyeL", 0.3, 0.3, 0.1, -0.35, 0.9, -0.82, "Eye"),
		B("PixelEyeR", 0.3, 0.3, 0.1, 0.35, 0.9, -0.82, "Eye"),
		B("PixelA", 0.3, 0.3, 0.3, 1.26, 1.46, 0, "Glow"),
		B("PixelB", 0.26, 0.26, 0.26, -1.36, 0.1, -0.3, "Primary", { Material = NEON }),
		B("PixelC", 0.28, 0.28, 0.28, 0.96, -2.0, 0.4, "Glow"),
	}),
}

-- THE OVERDRIVE: a racing suit, a glowing core, a glass visor and flame hair
H.Overdrive = {
	Palette = { Primary = rgb(255, 112, 32), Secondary = rgb(36, 32, 42), Accent = rgb(255, 236, 84), Skin = rgb(242, 202, 158), Glass = rgb(30, 34, 50), Dark = rgb(36, 32, 42) },
	HatAt = Vector3.new(0, 1.58, 0),
	Top = 2.35,
	Pieces = join(legs({ Role = "Secondary", ShoeRole = "Primary" }), {
		E("Body", 1.84, 1.84, 1.3, 0, -1.02, 0, "Primary"),
		E("StripeL", 0.16, 1.62, 1.3, -0.62, -1.02, 0, "Accent"),
		E("StripeR", 0.16, 1.62, 1.3, 0.62, -1.02, 0, "Accent"),
		S("Core", 0.6, 0, -0.86, -0.6, "Glow"),
	}, arms({ HandRole = "Secondary" }), head({ NoShine = true }), {
		E("Visor", 1.58, 0.38, 0.5, 0, 0.84, -0.62, "Glass"),
		E("FlameA", 0.5, 1.22, 0.5, 0, 1.72, 0.1, "Glow", { Headgear = true, R = ang(-0.25, 0, 0) }),
		E("FlameB", 0.42, 0.96, 0.42, -0.45, 1.55, 0.2, "Glow", { Headgear = true, R = ang(-0.2, 0, 0.45) }),
		E("FlameC", 0.42, 0.96, 0.42, 0.45, 1.55, 0.2, "Glow", { Headgear = true, R = ang(-0.2, 0, -0.45) }),
		E("FlameD", 0.36, 0.8, 0.36, 0, 1.5, 0.55, "Primary", { Headgear = true, R = ang(-0.7, 0, 0), Material = NEON }),
	}),
}

-- THE 67: a screen head that shows 67, gold antennas, a gold chain
H.SixSeven = {
	Palette = { Primary = rgb(122, 62, 202), Secondary = rgb(36, 32, 48), Accent = rgb(255, 206, 52), Skin = rgb(242, 202, 158), Gold = rgb(255, 204, 54), Dark = rgb(36, 32, 48) },
	HatAt = Vector3.new(0, 1.64, 0),
	Top = 2.25,
	Pieces = join(legs({ Role = "Secondary", ShoeRole = "Primary" }), {
		E("Body", 1.84, 1.84, 1.3, 0, -1.02, 0, "Primary"),
		E("Chain", 1.36, 0.12, 1.0, 0, -0.3, -0.12, "Gold"),
		C("Pendant", 0.1, 0.6, 0, -0.74, -0.66, "Gold", { Axis = "Z" }),
	}, arms(), {
		E("Head", 2.0, 1.6, 1.36, 0, 0.86, 0, "Secondary"),
		B("Screen", 1.54, 1.04, 0.06, 0, 0.86, -0.66, "Glow", { Text = "67", TextColor = rgb(64, 26, 92) }),
		C("AntennaL", 0.72, 0.1, -0.56, 1.82, 0, "Gold", { Headgear = true, R = ang(0, 0, 0.36) }),
		C("AntennaR", 0.72, 0.1, 0.56, 1.82, 0, "Gold", { Headgear = true, R = ang(0, 0, -0.36) }),
		S("TipL", 0.22, -0.7, 2.16, 0, "Glow", { Headgear = true }),
		S("TipR", 0.22, 0.7, 2.16, 0, "Glow", { Headgear = true }),
	}),
}

-- THE UNKNOWN: a hooded robe with no face, only a question, and a pale halo
H.Unknown = {
	Palette = { Primary = rgb(26, 26, 32), Secondary = rgb(42, 42, 52), Accent = rgb(240, 240, 255), Skin = rgb(10, 10, 14), Dark = rgb(18, 18, 24) },
	HatAt = Vector3.new(0, 1.76, 0.12),
	Top = 2.15,
	Pieces = join({
		E("Robe", 2.0, 2.9, 1.5, 0, -1.5, 0, "Dark"),
		E("Hem", 2.16, 0.5, 1.66, 0, -2.74, 0, "Primary"),
	}, arms({ X = 1.1, Arm = Vector3.new(0.56, 1.2, 0.6), Role = "Dark", HandRole = "Skin", Hand = 0.42 }), {
		E("Hood", 1.96, 1.9, 1.96, 0, 0.82, 0.12, "Primary"),
		E("Void", 1.36, 1.26, 0.5, 0, 0.76, -0.6, "Skin"),
		B("Mark", 0.8, 0.8, 0.05, 0, 0.78, -0.9, "Skin", { Text = "?", TextColor = rgb(240, 240, 255), Transparency = 1 }),
		C("Halo", 0.08, 1.46, 0, 2.0, 0.1, "Glow", { Transparency = 0.25 }),
	}),
}

-- a soft glowing ring under every hero (readability inside a horde)
HeroModels.Ring = { Name = "HeroRing", Size = Vector3.new(0.08, 3.3, 3.3), At = CFrame.new(0, -2.96, 0) * UP, Role = "Glow", Shape = CYL, Transparency = 0.55 } :: Piece

-- limb joints (hero space): where each arm / leg swings from
local PIVOTS = {
	ArmL = Vector3.new(-0.95, -0.44, 0),
	ArmR = Vector3.new(0.95, -0.44, 0),
	LegL = Vector3.new(-0.43, -1.9, 0),
	LegR = Vector3.new(0.43, -1.9, 0),
}
HeroModels.Limbs = { "ArmL", "ArmR", "LegL", "LegR" }

---------------------------------------------------------------------------
-- hero skins: palettes (and materials) that restyle any hero. Higher rarity = more than a
-- recolour: Solid Gold is polished metal, Frost is icy glass-like, Neon / Shadow 67 /
-- Oblivion light their accents up.
---------------------------------------------------------------------------
HeroModels.Skins = {
	Default = nil,
	Midnight = { Primary = rgb(38, 42, 78), Secondary = rgb(84, 90, 138), Accent = rgb(124, 184, 255) },
	Candy = { Primary = rgb(255, 152, 202), Secondary = rgb(152, 222, 255), Accent = rgb(255, 255, 255) },
	Frost = { Primary = rgb(192, 230, 255), Secondary = rgb(124, 172, 224), Accent = rgb(146, 242, 255), Materials = { Primary = Enum.Material.Glass }, Glow = true },
	Neon = { Primary = rgb(24, 24, 32), Secondary = rgb(52, 52, 72), Accent = rgb(0, 255, 204), Glow = true },
	Gold = { Primary = rgb(255, 202, 64), Secondary = rgb(204, 152, 42), Accent = rgb(255, 250, 204), Materials = { Primary = Enum.Material.Metal, Secondary = Enum.Material.Metal } },
	Shadow67 = { Primary = rgb(20, 14, 32), Secondary = rgb(92, 42, 162), Accent = rgb(255, 206, 52), Glow = true },
	Glitched = { Primary = rgb(255, 0, 202), Secondary = rgb(0, 255, 255), Accent = rgb(255, 255, 0), Glow = true },
	Oblivion = { Primary = rgb(16, 12, 28), Secondary = rgb(56, 26, 104), Accent = rgb(196, 120, 255), Materials = { Secondary = Enum.Material.Metal }, Glow = true },
}

local BASE = {
	Primary = rgb(120, 120, 140),
	Secondary = rgb(60, 60, 70),
	Accent = rgb(255, 255, 255),
	Skin = rgb(240, 200, 160),
	Dark = rgb(40, 42, 56),
	Metal = rgb(158, 164, 180),
	White = rgb(246, 246, 250),
	Eye = rgb(24, 22, 30),
	Shine = rgb(255, 255, 255),
	Gold = rgb(255, 205, 64),
	Hard = rgb(255, 214, 64),
	Glass = rgb(150, 220, 255),
	Belly = rgb(200, 240, 180),
}

local ROLE_MATERIAL = {
	Glow = NEON,
	Metal = Enum.Material.Metal,
	Gold = Enum.Material.Metal,
	Glass = Enum.Material.Glass,
}

-- the colour of a role for a hero (+ optional skin)
function HeroModels.Color(heroKey: string, role: string, skinKey: string?): Color3
	if role == "Glow" then
		role = "Accent"
	elseif role == "Hard" then
		local hero = H[heroKey]
		return (hero and hero.Palette.Gold) or BASE.Hard
	end
	local skin = skinKey and HeroModels.Skins[skinKey]
	if skin and skin[role] then
		return skin[role]
	end
	local hero = H[heroKey]
	local palette = hero and hero.Palette
	if role == "Glass" then
		return (palette and palette.Glass) or (palette and palette.Accent) or BASE.Glass
	end
	return (palette and palette[role]) or BASE[role] or BASE.Primary
end

local function materialOf(piece: Piece, skinKey: string?): Enum.Material
	local skin = skinKey and HeroModels.Skins[skinKey]
	local role = piece.Role or "Primary"
	if skin and skin.Materials and skin.Materials[role] then
		return skin.Materials[role]
	end
	if piece.Material then
		return piece.Material
	end
	if role == "Accent" and skin and skin.Glow then
		return NEON -- glowing skins light up the accents
	end
	return ROLE_MATERIAL[role] or Enum.Material.SmoothPlastic
end

---------------------------------------------------------------------------
-- hats (cosmetics). Pieces are placed on the hero's HatAt (the top of the head: y = 0 is
-- where the hat rests), sized for a ~1.8 stud head; a hat replaces the hero's Headgear.
---------------------------------------------------------------------------
local ORANGE, WHITE, GOLD = rgb(255, 122, 34), rgb(250, 250, 252), rgb(255, 204, 60)
local function hp(kind: string, name: string, size: Vector3, at: CFrame, color: Color3, extra: { [string]: any }?): Piece
	local p = mk(size, at, name, "Hat", extra)
	p.Color = color
	if kind == "E" then
		p.Mesh = "Sphere"
	elseif kind == "S" then
		p.Shape = BALL
	elseif kind == "C" then
		p.Shape = CYL
		p.At = p.At * UP
	end
	return p
end

HeroModels.Hats = {
	None = {},
	-- Common: simple shapes, one colour story
	Cone = {
		hp("C", "ConeBase", Vector3.new(0.12, 1.6, 1.6), CFrame.new(0, 0.02, 0), ORANGE),
		hp("C", "Cone1", Vector3.new(0.42, 1.12, 1.12), CFrame.new(0, 0.28, 0), ORANGE),
		hp("C", "Cone2", Vector3.new(0.4, 0.9, 0.9), CFrame.new(0, 0.68, 0), WHITE),
		hp("C", "Cone3", Vector3.new(0.38, 0.66, 0.66), CFrame.new(0, 1.06, 0), ORANGE),
		hp("S", "ConeTip", Vector3.new(0.46, 0.46, 0.46), CFrame.new(0, 1.3, 0), ORANGE),
	},
	PartyHat = {
		hp("C", "Party1", Vector3.new(0.36, 1.12, 1.12), CFrame.new(0, 0.16, 0), rgb(172, 92, 255)),
		hp("C", "Party2", Vector3.new(0.34, 0.86, 0.86), CFrame.new(0, 0.5, 0), GOLD),
		hp("C", "Party3", Vector3.new(0.32, 0.6, 0.6), CFrame.new(0, 0.82, 0), rgb(172, 92, 255)),
		hp("C", "Party4", Vector3.new(0.28, 0.36, 0.36), CFrame.new(0, 1.1, 0), GOLD),
		hp("S", "PartyPom", Vector3.new(0.42, 0.42, 0.42), CFrame.new(0, 1.36, 0), WHITE),
	},
	-- Uncommon: a clean accessory with a second material
	Shades = {
		hp("E", "LensL", Vector3.new(0.62, 0.34, 0.12), CFrame.new(-0.33, -0.72, -0.86), rgb(18, 18, 26), { Material = Enum.Material.Glass }),
		hp("E", "LensR", Vector3.new(0.62, 0.34, 0.12), CFrame.new(0.33, -0.72, -0.86), rgb(18, 18, 26), { Material = Enum.Material.Glass }),
		hp("E", "Bridge", Vector3.new(0.3, 0.08, 0.08), CFrame.new(0, -0.66, -0.88), GOLD, { Material = Enum.Material.Metal }),
	},
	-- Rare: more parts, moving (spun by the client), two colours
	Propeller = {
		hp("E", "Beanie", Vector3.new(1.84, 0.8, 1.8), CFrame.new(0, 0.02, 0), rgb(64, 142, 255)),
		hp("E", "BeanieRim", Vector3.new(1.9, 0.22, 1.86), CFrame.new(0, -0.18, 0), rgb(255, 214, 64)),
		hp("C", "Stick", Vector3.new(0.36, 0.12, 0.12), CFrame.new(0, 0.54, 0), rgb(60, 60, 70), { Material = Enum.Material.Metal }),
		hp("E", "BladeA", Vector3.new(1.7, 0.07, 0.32), CFrame.new(0, 0.72, 0), rgb(255, 64, 76), { Spin = 9 }),
		hp("E", "BladeB", Vector3.new(0.32, 0.07, 1.7), CFrame.new(0, 0.72, 0), rgb(255, 214, 64), { Spin = 9 }),
	},
	-- Epic: a unique design + a small light
	Headband67 = {
		hp("C", "Band", Vector3.new(0.34, 1.74, 1.74), CFrame.new(0, -0.5, 0), rgb(255, 204, 52)),
		hp("B", "Tag67", Vector3.new(0.64, 0.34, 0.05), CFrame.new(0, -0.5, -0.88), rgb(44, 22, 64), { Text = "67" }),
		hp("E", "Knot", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, -0.48, 0.86), rgb(255, 204, 52)),
		hp("E", "TailA", Vector3.new(0.14, 0.24, 0.9), CFrame.new(0.14, -0.62, 1.2), rgb(255, 204, 52), { R = CFrame.Angles(0.5, 0.2, 0) }),
	},
	Halo = {
		hp("C", "Halo", Vector3.new(0.1, 1.5, 1.5), CFrame.new(0, 0.62, 0), rgb(255, 246, 176), { Material = NEON, Transparency = 0.15 }),
		hp("C", "HaloCore", Vector3.new(0.12, 1.08, 1.08), CFrame.new(0, 0.62, 0), rgb(255, 255, 255), { Transparency = 0.7 }),
	},
	GoldAntenna = {
		hp("E", "Base", Vector3.new(0.5, 0.24, 0.5), CFrame.new(0, 0.04, 0), rgb(220, 170, 34), { Material = Enum.Material.Metal }),
		hp("C", "Stick", Vector3.new(0.86, 0.12, 0.12), CFrame.new(0, 0.48, 0), rgb(220, 170, 34), { Material = Enum.Material.Metal }),
		hp("S", "Ball", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0.98, 0), rgb(255, 216, 52), { Material = Enum.Material.Metal }),
		hp("S", "Spark", Vector3.new(0.22, 0.22, 0.22), CFrame.new(0.2, 1.14, -0.12), rgb(255, 244, 170), { Material = NEON }),
	},
	-- Legendary: a whole new look with gems that shine
	Crown = {
		hp("C", "Band", Vector3.new(0.42, 1.5, 1.5), CFrame.new(0, 0.14, 0), rgb(255, 202, 56), { Material = Enum.Material.Metal }),
		hp("E", "SpikeF", Vector3.new(0.3, 0.62, 0.3), CFrame.new(0, 0.56, -0.62), rgb(255, 214, 64), { Material = Enum.Material.Metal }),
		hp("E", "SpikeFL", Vector3.new(0.26, 0.5, 0.26), CFrame.new(-0.56, 0.5, -0.3), rgb(255, 214, 64), { Material = Enum.Material.Metal }),
		hp("E", "SpikeFR", Vector3.new(0.26, 0.5, 0.26), CFrame.new(0.56, 0.5, -0.3), rgb(255, 214, 64), { Material = Enum.Material.Metal }),
		hp("E", "SpikeBL", Vector3.new(0.26, 0.5, 0.26), CFrame.new(-0.46, 0.5, 0.42), rgb(255, 214, 64), { Material = Enum.Material.Metal }),
		hp("E", "SpikeBR", Vector3.new(0.26, 0.5, 0.26), CFrame.new(0.46, 0.5, 0.42), rgb(255, 214, 64), { Material = Enum.Material.Metal }),
		hp("S", "Ruby", Vector3.new(0.26, 0.26, 0.26), CFrame.new(0, 0.16, -0.76), rgb(255, 56, 110), { Material = NEON }),
		hp("S", "Sapphire", Vector3.new(0.18, 0.18, 0.18), CFrame.new(-0.62, 0.16, -0.42), rgb(80, 170, 255), { Material = NEON }),
		hp("S", "Emerald", Vector3.new(0.18, 0.18, 0.18), CFrame.new(0.62, 0.16, -0.42), rgb(90, 255, 150), { Material = NEON }),
	},
	-- Secret: the rarest look in the game (clear THE 67 difficulty)
	Crown67 = {
		hp("C", "Band", Vector3.new(0.46, 1.56, 1.56), CFrame.new(0, 0.16, 0), rgb(24, 20, 34), { Material = Enum.Material.Metal }),
		hp("C", "Trim", Vector3.new(0.1, 1.62, 1.62), CFrame.new(0, 0.38, 0), rgb(255, 206, 52), { Material = Enum.Material.Metal }),
		hp("E", "SpikeL", Vector3.new(0.3, 0.8, 0.3), CFrame.new(-0.5, 0.7, -0.4), rgb(255, 206, 52), { Material = Enum.Material.Metal, R = CFrame.Angles(0, 0, 0.2) }),
		hp("E", "SpikeR", Vector3.new(0.3, 0.8, 0.3), CFrame.new(0.5, 0.7, -0.4), rgb(255, 206, 52), { Material = Enum.Material.Metal, R = CFrame.Angles(0, 0, -0.2) }),
		hp("B", "Plate67", Vector3.new(0.7, 0.44, 0.06), CFrame.new(0, 0.2, -0.8), rgb(255, 206, 52), { Material = NEON, Text = "67", TextColor = rgb(40, 16, 60) }),
		-- three sparks orbit the crown (gold, violet, pink), each at its own height
		hp("S", "SparkA", Vector3.new(0.22, 0.22, 0.22), CFrame.new(1.05, 0.62, 0), rgb(255, 222, 96), { Material = NEON, Spin = 2.2 }),
		hp("S", "SparkB", Vector3.new(0.18, 0.18, 0.18), CFrame.new(-0.52, 0.86, 0.9), rgb(196, 120, 255), { Material = NEON, Spin = 2.2 }),
		hp("S", "SparkC", Vector3.new(0.18, 0.18, 0.18), CFrame.new(-0.52, 0.4, -0.9), rgb(255, 120, 196), { Material = NEON, Spin = 2.2 }),
	},
} :: { [string]: { Piece } }

---------------------------------------------------------------------------
-- builder
---------------------------------------------------------------------------
local function textGui(p: BasePart, text: string, color: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.CanvasSize = Vector2.new(120, 80)
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = if text == "67" then Enum.Font.LuckiestGuy else Enum.Font.BuilderSansExtraBold
	label.TextColor3 = color or rgb(255, 215, 50)
	label.Parent = gui
end

local function makePart(piece: Piece, color: Color3, material: Enum.Material, cf: CFrame, container: Instance, anchored: boolean, scale: number?): BasePart
	local p = Instance.new("Part")
	p.Name = piece.Name
	p.Size = if scale then piece.Size * scale else piece.Size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = piece.Size.Magnitude > 1.2 and material ~= NEON
	p.Transparency = piece.Transparency or 0
	if piece.Shape then
		p.Shape = piece.Shape
	end
	if piece.Mesh == "Sphere" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.CFrame = cf
	p.Anchored = anchored
	if not anchored then
		p.Massless = true
	end
	if piece.Text then
		textGui(p, piece.Text, piece.TextColor)
	end
	p.Parent = container
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

export type BuildOptions = {
	Skin: string?,
	Hat: string?,
	WeldTo: BasePart?, -- weld (a real character: arms / legs get Motor6Ds); nil = anchored (a preview)
	Ring: boolean?,
}

--[[
	Builds hero `key` around `origin` (the CFrame a HumanoidRootPart would have) into
	`container`. Returns the parts.
]]
function HeroModels.Build(key: string, origin: CFrame, container: Instance, opts: BuildOptions?): { BasePart }
	local o = opts or {}
	local hero = H[key] or H.Rookie
	local hat = o.Hat and HeroModels.Hats[o.Hat]
	local wearsHat = hat ~= nil and #hat > 0
	local anchored = o.WeldTo == nil
	local limbs = {} :: { [string]: BasePart }
	local out = {}
	for _, piece in hero.Pieces do
		if piece.Headgear and wearsHat then
			continue
		end
		local color = piece.Color or HeroModels.Color(key, piece.Role or "Primary", o.Skin)
		local p = makePart(piece, color, materialOf(piece, o.Skin), origin * piece.At, container, anchored)
		table.insert(out, p)
		local root = o.WeldTo
		if root then
			local limb = piece.Limb
			local main = limb and limbs[limb]
			if limb and not main then
				-- the first piece of a limb swings on a Motor6D around the joint
				limbs[limb] = p
				local pivot = CFrame.new((hero.Pivots and hero.Pivots[limb]) or PIVOTS[limb])
				local motor = Instance.new("Motor6D")
				motor.Name = "Limb" .. limb
				motor.Part0 = root
				motor.Part1 = p
				motor.C0 = pivot
				motor.C1 = piece.At:Inverse() * pivot
				motor.Parent = root
			elseif main then
				weld(p, main)
			else
				weld(p, root)
			end
		end
	end
	if o.Ring ~= false then
		local ring = HeroModels.Ring
		local p = makePart(ring, HeroModels.Color(key, "Accent", o.Skin), NEON, origin * ring.At, container, anchored)
		table.insert(out, p)
		if o.WeldTo then
			weld(p, o.WeldTo)
		end
	end
	if hat and wearsHat then
		for _, p in HeroModels.BuildHat(o.Hat :: string, origin * CFrame.new(hero.HatAt), container, hero.HatScale, o.WeldTo) do
			table.insert(out, p)
		end
	end
	return out
end

-- a hat resting on `base` (the top of a head); welded to weldTo, else anchored
function HeroModels.BuildHat(key: string, base: CFrame, container: Instance, scale: number?, weldTo: BasePart?): { BasePart }
	local out = {}
	local s = scale or 1
	for _, piece in HeroModels.Hats[key] or {} do
		local at = piece.At
		local cf = base * CFrame.new(at.Position * s) * at.Rotation
		local p = makePart(piece, piece.Color or rgb(255, 255, 255), piece.Material or Enum.Material.SmoothPlastic, cf, container, weldTo == nil, s)
		table.insert(out, p)
		if weldTo and piece.Spin then
			-- a motor on the hat's axis (at the piece's height): the client turns it
			-- (HeroAnimator), so blades spin and sparks orbit
			local motor = Instance.new("Motor6D")
			motor.Name = "Spin" .. piece.Name
			motor.Part0 = weldTo
			motor.Part1 = p
			motor.C0 = weldTo.CFrame:ToObjectSpace(base * CFrame.new(0, at.Position.Y * s, 0))
			motor.C1 = (CFrame.new(at.Position.X * s, 0, at.Position.Z * s) * at.Rotation):Inverse()
			motor:SetAttribute("Speed", piece.Spin)
			motor.Parent = weldTo
		elseif weldTo then
			weld(p, weldTo)
		end
	end
	return out
end

-- the plain head the hat menus show hats on (centre at the origin, top at y = 0.81)
HeroModels.PreviewHead = { Size = Vector3.new(1.8, 1.62, 1.66), Top = 0.81 }

-- height of the hero model above the root (for cameras / name tags)
function HeroModels.Top(key: string): number
	local hero = H[key] or H.Rookie
	return hero.Top or hero.HatAt.Y
end

return HeroModels
