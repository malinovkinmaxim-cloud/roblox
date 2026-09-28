--[[
	HeroModels - the 15 hero models: smooth, clean, minimal.

	Visual language: "few high-quality shapes". Bodies, heads and limbs are ELLIPSOIDS (a part
	with a SpecialMesh of type Sphere fills its box exactly, so any egg / capsule-like
	proportion is one smooth shape), balls and cylinders for round details, blocks only where
	a crisp edge IS the design (a katana blade, a screen, THE GLITCH's cube head). Materials:
	SmoothPlastic, Metal (weapons, armour, gold), Glass (lenses, visors) and Neon ONLY for
	energy (orbs, flames, visors of energy, THE 67's screen).

	Every hero has its own silhouette + weapon + accessory + accent colour (a cap and a
	blaster, a huge round shield, a hood and a bow, a backpack with a magnet, a kabuto and a
	katana, a wizard hat, beard and staff, a hardhat and a drone, a top hat and a lucky coin,
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

-- THE ROOKIE: a baseball cap and a chunky blaster
H.Rookie = {
	Palette = { Primary = rgb(72, 128, 250), Secondary = rgb(255, 150, 48), Accent = rgb(255, 176, 72), Skin = rgb(246, 206, 164), Dark = rgb(48, 54, 78) },
	HatAt = Vector3.new(0, 1.58, 0),
	Top = 1.78,
	Pieces = join(legs(), {
		E("Body", 1.84, 1.86, 1.32, 0, -1.02, 0, "Primary"),
		E("Hoodie", 1.5, 0.5, 1.15, 0, -0.14, 0.16, "Primary"),
		E("Pocket", 1.1, 0.34, 0.2, 0, -1.5, -0.6, "Secondary"),
	}, arms(), head(), {
		E("Cap", 1.86, 0.96, 1.8, 0, 1.24, 0.03, "Primary", { Headgear = true }),
		E("Visor", 1.26, 0.16, 1.02, 0, 1.08, -0.74, "Secondary", { Headgear = true, R = ang(-0.1, 0, 0) }),
		S("CapButton", 0.2, 0, 1.72, 0.03, "Secondary", { Headgear = true }),
	}, inFrame(CFrame.new(1.2, -1.58, -0.55), {
		C("Blaster", 1.3, 0.5, 0, 0, -0.2, "Metal", { Axis = "Z" }),
		E("Grip", 0.3, 0.55, 0.34, 0, -0.26, 0.2, "Dark"),
		C("Stripe", 0.14, 0.54, 0, 0, -0.55, "Secondary", { Axis = "Z" }),
		S("Muzzle", 0.36, 0, 0, -0.88, "Glow"),
	}, { Limb = "ArmR" })),
}

-- THE RUNNER: long legs, big sneakers, a headband with flowing ribbons
H.Runner = {
	Palette = { Primary = rgb(236, 62, 72), Secondary = rgb(250, 250, 252), Accent = rgb(255, 124, 124), Skin = rgb(232, 186, 146), Dark = rgb(40, 40, 52) },
	HatAt = Vector3.new(0, 1.37, -0.08),
	Top = 1.6,
	Pivots = { LegL = Vector3.new(-0.38, -1.62, 0), LegR = Vector3.new(0.38, -1.62, 0) },
	Pieces = join(legs({ X = 0.38, Leg = Vector3.new(0.54, 1.28, 0.58), LegY = -2.2, Role = "Primary", Shoe = Vector3.new(0.74, 0.5, 1.16), ShoeRole = "White", ShoeZ = -0.16 }), {
		E("SoleL", 0.76, 0.14, 1.18, -0.38, -2.93, -0.16, "Primary", { Limb = "LegL" }),
		E("SoleR", 0.76, 0.14, 1.18, 0.38, -2.93, -0.16, "Primary", { Limb = "LegR" }),
		E("Body", 1.56, 1.66, 1.16, 0, -0.86, 0, "Primary", { R = ang(-0.1, 0, 0) }),
		E("Stripe", 1.6, 0.28, 1.2, 0, -0.72, 0, "Secondary", { R = ang(-0.1, 0, 0) }),
	}, arms({ X = 0.96, Y = -0.86, Arm = Vector3.new(0.44, 1.02, 0.5), Swing = 0.28, Hand = 0.46 }), head({ Y = 0.62, Z = -0.08, Size = Vector3.new(1.62, 1.5, 1.56) }), {
		C("Headband", 0.32, 1.52, 0, 0.95, -0.08, "Secondary", { Headgear = true }),
		E("RibbonA", 0.14, 0.26, 1.25, 0.24, 0.95, 0.92, "Accent", { Headgear = true, R = ang(0.25, 0.15, 0) }),
		E("RibbonB", 0.14, 0.22, 1.0, -0.2, 0.86, 0.86, "Accent", { Headgear = true, R = ang(0.38, -0.12, 0) }),
	}),
}

-- THE TANK: wide armour, round pauldrons, a visor helmet and a huge round shield
H.Tank = {
	Palette = { Primary = rgb(92, 152, 94), Secondary = rgb(210, 214, 224), Accent = rgb(120, 255, 156), Skin = rgb(230, 186, 146), Metal = rgb(150, 158, 174), Dark = rgb(46, 52, 64) },
	HatAt = Vector3.new(0, 1.7, 0),
	HatScale = 1.08,
	Top = 1.95,
	Pivots = { ArmL = Vector3.new(-1.45, -0.3, 0), ArmR = Vector3.new(1.45, -0.3, 0), LegL = Vector3.new(-0.62, -2.0, 0), LegR = Vector3.new(0.62, -2.0, 0) },
	Pieces = join(legs({ X = 0.62, Leg = Vector3.new(0.92, 0.95, 0.96), LegY = -2.4, Shoe = Vector3.new(1.02, 0.56, 1.22), ShoeRole = "Metal" }), {
		E("Body", 2.8, 2.26, 2.0, 0, -0.95, 0, "Primary"),
		E("Belt", 2.24, 0.34, 1.62, 0, -1.72, 0, "Metal"),
		E("ChestPlate", 1.7, 1.2, 0.5, 0, -0.7, -0.84, "Secondary"),
		E("PadL", 1.36, 0.86, 1.6, -1.55, 0.02, 0, "Metal"),
		E("PadR", 1.36, 0.86, 1.6, 1.55, 0.02, 0, "Metal"),
	}, arms({ X = 1.62, Y = -0.95, Arm = Vector3.new(0.72, 1.22, 0.82), Splay = 0.1, Hand = 0.74, HandRole = "Metal" }), {
		E("Helmet", 1.92, 1.76, 1.92, 0, 0.84, 0, "Metal"),
		E("Visor", 1.46, 0.3, 0.3, 0, 0.9, -0.82, "Glow"),
		E("Fin", 0.22, 0.62, 1.34, 0, 1.64, 0.05, "Primary", { Headgear = true }),
	}, inFrame(CFrame.new(-2.02, -1.02, -0.5), {
		C("ShieldRim", 0.24, 3.0, 0, 0, 0.06, "Metal", { Axis = "Z" }),
		C("Shield", 0.28, 2.66, 0, 0, -0.04, "Secondary", { Axis = "Z" }),
		C("ShieldBand", 0.3, 1.5, 0, 0, -0.06, "Primary", { Axis = "Z" }),
		S("ShieldBoss", 0.78, 0, 0, -0.2, "Metal"),
	}, { Limb = "ArmL" })),
}

-- THE HUNTER: a pointed hood, a cloak, a bow and a quiver
H.Hunter = {
	Palette = { Primary = rgb(62, 128, 78), Secondary = rgb(150, 102, 62), Accent = rgb(176, 255, 146), Skin = rgb(232, 188, 148), Dark = rgb(38, 64, 46) },
	HatAt = Vector3.new(0, 1.72, 0.12),
	Top = 1.92,
	Pieces = join(legs({ Role = "Dark", ShoeRole = "Secondary" }), {
		E("Body", 1.7, 1.82, 1.22, 0, -1.02, 0, "Primary"),
		E("Belt", 1.74, 0.26, 1.26, 0, -1.56, 0, "Secondary"),
		E("Cloak", 1.92, 2.5, 0.4, 0, -0.95, 0.62, "Dark", { R = ang(0.08, 0, 0) }),
	}, arms({ Role = "Primary" }), {
		E("Hood", 1.96, 1.86, 1.92, 0, 0.82, 0.14, "Primary"),
		E("HoodTip", 0.5, 0.96, 0.5, 0, 1.52, 0.78, "Primary", { R = ang(0.95, 0, 0) }),
	}, head({ Y = 0.74, Z = -0.22, Size = Vector3.new(1.46, 1.38, 1.4) }), inFrame(CFrame.new(-1.32, -1.06, -0.4), {
		C("BowTop", 1.36, 0.15, -0.14, 0.62, 0, "Secondary", { R = ang(0, 0, -0.36) }),
		C("BowBottom", 1.36, 0.15, -0.14, -0.62, 0, "Secondary", { R = ang(0, 0, 0.36) }),
		E("BowGrip", 0.22, 0.4, 0.22, 0.08, 0, 0, "Dark"),
		B("BowString", 0.05, 2.36, 0.05, 0.3, 0, 0, "White"),
	}, { Limb = "ArmL" }), {
		C("Quiver", 1.5, 0.5, 0.5, -0.55, 0.8, "Secondary", { R = ang(0, 0, -0.35) }),
		E("FletchA", 0.16, 0.42, 0.06, 0.7, 0.26, 0.8, "Accent", { R = ang(0, 0, -0.35) }),
		E("FletchB", 0.16, 0.42, 0.06, 0.86, 0.2, 0.72, "Accent", { R = ang(0, 0, -0.35) }),
		E("FletchC", 0.16, 0.42, 0.06, 0.76, 0.14, 0.9, "Accent", { R = ang(0, 0, -0.35) }),
	}),
}

-- THE COLLECTOR: a huge backpack with a red horseshoe magnet, a gold pouch
H.Collector = {
	Palette = { Primary = rgb(42, 172, 172), Secondary = rgb(152, 106, 62), Accent = rgb(255, 216, 84), Skin = rgb(242, 202, 158), Dark = rgb(44, 58, 70) },
	HatAt = Vector3.new(0, 1.6, 0),
	Top = 2.25,
	Pieces = join(legs({ ShoeRole = "Secondary" }), {
		E("Body", 1.82, 1.84, 1.3, 0, -1.02, 0, "Primary"),
		E("StrapL", 0.22, 1.5, 0.12, -0.46, -0.86, -0.62, "Secondary"),
		E("StrapR", 0.22, 1.5, 0.12, 0.46, -0.86, -0.62, "Secondary"),
	}, arms(), head(), {
		E("Hair", 1.36, 0.5, 1.26, 0, 1.46, 0.12, "Secondary", { Headgear = true }),
		E("Backpack", 2.3, 2.46, 1.56, 0, -0.52, 1.36, "Secondary"),
		E("TopPocket", 1.9, 0.8, 1.3, 0, 0.62, 1.34, "Secondary", { Color = rgb(176, 128, 78) }),
		C("MagnetL", 0.96, 0.5, -0.55, 1.42, 1.36, "Primary", { Color = rgb(232, 54, 66) }),
		C("MagnetR", 0.96, 0.5, 0.55, 1.42, 1.36, "Primary", { Color = rgb(232, 54, 66) }),
		C("MagnetBase", 1.6, 0.5, 0, 0.96, 1.36, "Primary", { Axis = "X", Color = rgb(232, 54, 66) }),
		C("TipL", 0.3, 0.52, -0.55, 2.0, 1.36, "Metal"),
		C("TipR", 0.3, 0.52, 0.55, 2.0, 1.36, "Metal"),
		E("Pouch", 0.72, 0.76, 0.62, 0.98, -1.68, -0.36, "Gold"),
		E("PouchTie", 0.5, 0.12, 0.46, 0.98, -1.33, -0.36, "Secondary"),
	}),
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
