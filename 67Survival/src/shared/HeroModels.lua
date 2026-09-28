--[[
	HeroModels - the 15 minimalist hero models, built from a few parts each.

	Silhouette > detail: every hero has ONE thing you recognise from far above (a cap and a
	blaster, a huge shield, a hood and bow, a backpack with a magnet, a kabuto and katana, a
	wizard hat and staff, a drone, a top hat, a blob body, a faceless cube, a screen head
	showing 67...). A soft glowing ring under the hero keeps it readable inside a horde.

	Used by
	  * the server (CharacterManager): parts WELDED to an invisible character rig
	  * the client menus (UI/Previews): ANCHORED parts inside a ViewportFrame
	so a hero looks the same in the menu and in the arena.

	Coordinates are relative to the character's HumanoidRootPart centre: feet at y = -3,
	front = -Z. A piece: { Name, Size, At, Role, Shape?, Material?, Text?, Transparency? }
	Roles are coloured by the hero palette (or the equipped hero skin):
	  Primary Secondary Accent (glows) Skin Dark Metal White Eye Gold
]]

local HeroModels = {}

local rgb = Color3.fromRGB
local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
local NEON = Enum.Material.Neon
local UP = CFrame.Angles(0, 0, math.rad(90)) -- cylinders stand up
local FACE = CFrame.Angles(0, math.rad(90), 0) -- cylinders face the front

export type Piece = {
	Name: string,
	Size: Vector3,
	At: CFrame,
	Role: string?,
	Color: Color3?,
	Shape: Enum.PartType?,
	Material: Enum.Material?,
	Text: string?,
	TextColor: Color3?,
	Transparency: number?,
}

local function B(name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, role: string, extra: { [string]: any }?): Piece
	local p: any = { Name = name, Size = Vector3.new(sx, sy, sz), At = CFrame.new(x, y, z), Role = role }
	if extra then
		for k, v in extra do
			if k == "R" then
				p.At = p.At * v
			else
				p[k] = v
			end
		end
	end
	if role == "Accent" and p.Material == nil then
		p.Material = NEON
	end
	return p
end

local function S(name: string, d: number, x: number, y: number, z: number, role: string, extra: { [string]: any }?): Piece
	local p = B(name, d, d, d, x, y, z, role, extra)
	p.Shape = BALL
	return p
end

-- cylinder of height h and diameter d standing up (or facing front with extra.Front)
local function C(name: string, h: number, d: number, x: number, y: number, z: number, role: string, extra: { [string]: any }?): Piece
	local p = B(name, h, d, d, x, y, z, role, extra)
	p.Shape = CYL
	p.At = p.At * (if extra and extra.Front then FACE * UP else UP)
	p.Front = nil
	return p
end

local function eyes(y: number, z: number, spread: number?): { Piece }
	local s = spread or 0.28
	return {
		B("EyeL", 0.18, 0.32, 0.1, -s, y, z, "Eye"),
		B("EyeR", 0.18, 0.32, 0.1, s, y, z, "Eye"),
	}
end

local function legs(role: string?): { Piece }
	return {
		B("LegL", 0.7, 1.1, 0.8, -0.45, -2.45, 0, role or "Dark"),
		B("LegR", 0.7, 1.1, 0.8, 0.45, -2.45, 0, role or "Dark"),
	}
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

---------------------------------------------------------------------------
-- the heroes
---------------------------------------------------------------------------
HeroModels.Heroes = {}
local H = HeroModels.Heroes

-- cap + blaster
H.Rookie = {
	Palette = { Primary = rgb(70, 130, 255), Secondary = rgb(255, 150, 50), Accent = rgb(255, 170, 60), Skin = rgb(245, 205, 160) },
	HatAt = Vector3.new(0, 1.62, 0),
	Pieces = join(legs(), {
		B("Body", 1.9, 1.7, 1.2, 0, -1.05, 0, "Primary"),
		B("Belt", 1.95, 0.25, 1.25, 0, -1.75, 0, "Secondary"),
		B("ArmL", 0.5, 1.2, 0.55, -1.2, -1.0, 0, "Skin"),
		B("ArmR", 0.5, 1.2, 0.55, 1.2, -1.0, 0, "Skin"),
		S("Head", 1.6, 0, 0.75, 0, "Skin"),
		C("Cap", 0.55, 1.72, 0, 1.3, 0, "Primary"),
		B("Visor", 1.3, 0.14, 0.9, 0, 1.12, -0.85, "Secondary"),
		B("Blaster", 0.45, 0.55, 1.5, 1.25, -1.1, -0.65, "Metal"),
		B("BlasterTip", 0.32, 0.32, 0.3, 1.25, -1.05, -1.45, "Accent"),
	}, eyes(0.8, -0.78)),
}

-- long legs, sneakers, a headband with flowing ribbons
H.Runner = {
	Palette = { Primary = rgb(235, 60, 70), Secondary = rgb(255, 255, 255), Accent = rgb(255, 120, 120), Skin = rgb(230, 185, 145) },
	HatAt = Vector3.new(0, 1.45, 0),
	Pieces = join({
		B("LegL", 0.6, 1.55, 0.7, -0.4, -2.2, 0, "Primary"),
		B("LegR", 0.6, 1.55, 0.7, 0.4, -2.2, 0, "Primary"),
		B("ShoeL", 0.72, 0.42, 1.1, -0.4, -2.8, -0.18, "White"),
		B("ShoeR", 0.72, 0.42, 1.1, 0.4, -2.8, -0.18, "White"),
		B("Body", 1.5, 1.5, 1.0, 0, -0.75, 0, "Primary", { R = CFrame.Angles(math.rad(-8), 0, 0) }),
		B("Stripe", 1.55, 0.3, 1.05, 0, -0.62, 0, "White", { R = CFrame.Angles(math.rad(-8), 0, 0) }),
		S("Head", 1.45, 0, 0.75, -0.1, "Skin"),
		C("Headband", 0.35, 1.52, 0, 0.98, -0.1, "Secondary"),
		B("RibbonA", 0.14, 0.22, 1.5, 0.3, 0.95, 1.0, "Accent", { R = CFrame.Angles(math.rad(12), math.rad(10), 0) }),
		B("RibbonB", 0.14, 0.22, 1.2, -0.25, 0.85, 0.95, "Accent", { R = CFrame.Angles(math.rad(20), math.rad(-8), 0) }),
	}, eyes(0.8, -0.8)),
}

-- wide armour, visor helmet, a big round shield
H.Tank = {
	Palette = { Primary = rgb(90, 150, 90), Secondary = rgb(200, 205, 215), Accent = rgb(120, 255, 150), Skin = rgb(230, 185, 145), Metal = rgb(150, 155, 170) },
	HatAt = Vector3.new(0, 1.8, 0),
	Pieces = {
		B("LegL", 1.0, 1.0, 1.1, -0.7, -2.5, 0, "Dark"),
		B("LegR", 1.0, 1.0, 1.1, 0.7, -2.5, 0, "Dark"),
		B("Body", 3.0, 2.2, 1.9, 0, -0.95, 0, "Primary"),
		B("PadL", 1.1, 0.65, 1.5, -1.75, 0.15, 0, "Metal"),
		B("PadR", 1.1, 0.65, 1.5, 1.75, 0.15, 0, "Metal"),
		B("Helmet", 1.8, 1.55, 1.7, 0, 0.95, 0, "Metal"),
		B("Slit", 1.35, 0.22, 0.1, 0, 1.05, -0.88, "Accent"),
		C("Shield", 0.3, 2.8, -1.95, -0.85, -0.55, "Secondary", { Front = true }),
		S("ShieldBoss", 0.8, -1.95, -0.85, -0.75, "Metal"),
	},
}

-- hood, cloak, bow, quiver
H.Hunter = {
	Palette = { Primary = rgb(60, 120, 70), Secondary = rgb(150, 100, 60), Accent = rgb(170, 255, 140), Skin = rgb(230, 185, 145) },
	HatAt = Vector3.new(0, 1.85, 0.1),
	Pieces = join(legs("Secondary"), {
		B("Body", 1.7, 1.7, 1.1, 0, -1.0, 0, "Primary"),
		B("Cloak", 1.9, 2.5, 0.22, 0, -0.75, 0.7, "Dark"),
		S("Hood", 1.8, 0, 0.9, 0.18, "Primary"),
		B("HoodTip", 0.55, 0.55, 0.55, 0, 1.65, 0.45, "Primary", { R = CFrame.Angles(math.rad(45), 0, math.rad(45)) }),
		S("Head", 1.4, 0, 0.72, -0.2, "Skin"),
		B("BowTop", 0.16, 1.3, 0.16, -1.3, -0.35, -0.35, "Secondary", { R = CFrame.Angles(0, 0, math.rad(-18)) }),
		B("BowBottom", 0.16, 1.3, 0.16, -1.3, -1.55, -0.35, "Secondary", { R = CFrame.Angles(0, 0, math.rad(18)) }),
		B("BowString", 0.05, 2.5, 0.05, -1.06, -0.95, -0.35, "White"),
		C("Quiver", 1.5, 0.55, 0.55, -0.45, 0.78, "Secondary", { R = CFrame.Angles(0, 0, math.rad(-20)) }),
		B("ArrowTips", 0.45, 0.3, 0.3, 0.8, 0.35, 0.8, "Accent"),
	}, eyes(0.78, -0.88)),
}

-- a huge backpack with a magnet on top
H.Collector = {
	Palette = { Primary = rgb(40, 170, 170), Secondary = rgb(150, 105, 60), Accent = rgb(255, 215, 80), Skin = rgb(240, 200, 155) },
	HatAt = Vector3.new(0, 1.52, 0),
	Pieces = join(legs(), {
		B("Body", 1.8, 1.7, 1.2, 0, -1.05, 0, "Primary"),
		S("Head", 1.5, 0, 0.72, 0, "Skin"),
		B("Backpack", 2.3, 2.6, 1.6, 0, -0.45, 1.4, "Secondary"),
		B("MagnetL", 0.5, 1.1, 0.5, -0.6, 1.4, 1.4, "Primary", { Color = rgb(230, 50, 60) }),
		B("MagnetR", 0.5, 1.1, 0.5, 0.6, 1.4, 1.4, "Primary", { Color = rgb(230, 50, 60) }),
		B("MagnetBase", 1.7, 0.5, 0.5, 0, 0.95, 1.4, "Primary", { Color = rgb(230, 50, 60) }),
		B("TipL", 0.52, 0.32, 0.52, -0.6, 2.05, 1.4, "Metal"),
		B("TipR", 0.52, 0.32, 0.52, 0.6, 2.05, 1.4, "Metal"),
		S("Pouch", 0.75, 0.85, -1.75, -0.55, "Gold"),
	}, eyes(0.78, -0.73)),
}

-- kabuto with a golden crest, katana
H.Samurai = {
	Palette = { Primary = rgb(200, 40, 50), Secondary = rgb(30, 30, 36), Accent = rgb(255, 90, 90), Skin = rgb(235, 195, 150), Gold = rgb(255, 200, 70) },
	HatAt = Vector3.new(0, 1.75, 0),
	Pieces = join({
		B("Hakama", 1.9, 1.25, 1.2, 0, -2.38, 0, "Secondary"),
		B("Body", 1.8, 1.6, 1.2, 0, -1.0, 0, "Primary"),
		B("PlateL", 0.95, 0.25, 1.3, -1.25, -0.25, 0, "Primary", { R = CFrame.Angles(0, 0, math.rad(22)) }),
		B("PlateR", 0.95, 0.25, 1.3, 1.25, -0.25, 0, "Primary", { R = CFrame.Angles(0, 0, math.rad(-22)) }),
		S("Head", 1.45, 0, 0.7, 0, "Skin"),
		C("Kabuto", 0.7, 1.72, 0, 1.25, 0, "Secondary"),
		B("Brim", 2.1, 0.15, 1.9, 0, 0.95, 0, "Secondary"),
		B("CrestL", 0.16, 1.05, 0.12, -0.32, 1.85, -0.72, "Gold", { R = CFrame.Angles(0, 0, math.rad(25)), Material = NEON }),
		B("CrestR", 0.16, 1.05, 0.12, 0.32, 1.85, -0.72, "Gold", { R = CFrame.Angles(0, 0, math.rad(-25)), Material = NEON }),
		B("Blade", 0.14, 0.35, 3.1, 1.3, -1.25, -1.5, "Metal", { Material = Enum.Material.Metal }),
		B("Guard", 0.55, 0.55, 0.1, 1.3, -1.25, 0.05, "Gold"),
		B("Handle", 0.2, 0.26, 0.9, 1.3, -1.25, 0.52, "Secondary"),
	}, eyes(0.75, -0.72)),
}

-- tall wizard hat, robe, staff with a glowing orb
H.Mage = {
	Palette = { Primary = rgb(120, 70, 220), Secondary = rgb(140, 95, 60), Accent = rgb(90, 230, 255), Skin = rgb(240, 205, 165), Gold = rgb(255, 205, 80) },
	HatAt = Vector3.new(0, 2.95, 0.3),
	Pieces = join({
		B("Robe", 2.1, 2.4, 1.5, 0, -1.8, 0, "Primary"),
		B("Chest", 1.7, 1.2, 1.2, 0, -0.4, 0, "Primary"),
		B("Belt", 1.75, 0.2, 1.25, 0, -0.9, 0, "Gold"),
		S("Head", 1.4, 0, 0.72, 0, "Skin"),
		C("Brim", 0.15, 2.5, 0, 1.25, 0, "Primary"),
		C("Band", 0.22, 1.36, 0, 1.42, 0, "Accent"),
		C("HatA", 0.6, 1.3, 0, 1.62, 0, "Primary"),
		C("HatB", 0.6, 0.86, 0, 2.15, 0.1, "Primary"),
		C("HatC", 0.5, 0.46, 0, 2.6, 0.25, "Primary"),
		C("Staff", 5, 0.26, 1.35, -0.75, -0.25, "Secondary"),
		S("StaffOrb", 0.85, 1.35, 1.95, -0.25, "Accent"),
	}, eyes(0.75, -0.68)),
}

-- hardhat, goggles, backpack antenna, a little drone over the shoulder
H.Engineer = {
	Palette = { Primary = rgb(255, 150, 40), Secondary = rgb(50, 70, 120), Accent = rgb(90, 220, 255), Skin = rgb(235, 190, 150), Gold = rgb(255, 215, 60) },
	HatAt = Vector3.new(0, 2.02, 0),
	Pieces = join(legs("Secondary"), {
		B("Body", 1.9, 1.7, 1.2, 0, -1.05, 0, "Primary"),
		S("Head", 1.5, 0, 0.72, 0, "Skin"),
		S("Hardhat", 1.72, 0, 1.12, 0, "Gold"),
		B("HatBrim", 1.95, 0.12, 1.95, 0, 1.02, -0.05, "Gold"),
		C("LensL", 0.12, 0.46, -0.3, 0.82, -0.74, "Accent", { Front = true }),
		C("LensR", 0.12, 0.46, 0.3, 0.82, -0.74, "Accent", { Front = true }),
		B("Pack", 1.3, 1.4, 0.7, 0, -0.8, 0.95, "Metal"),
		C("Antenna", 1.3, 0.1, 0.45, 0.4, 1.05, "Metal"),
		S("AntennaTip", 0.28, 0.45, 1.1, 1.05, "Accent"),
		B("Drone", 0.85, 0.3, 0.85, 1.55, 1.25, 0.25, "Metal"),
		B("Rotor", 1.7, 0.06, 0.22, 1.55, 1.5, 0.25, "Dark"),
		S("DroneEye", 0.28, 1.55, 1.15, -0.15, "Accent"),
		B("Wrench", 0.2, 1.3, 0.2, -1.25, -1.35, -0.3, "Metal"),
		B("WrenchHead", 0.55, 0.3, 0.2, -1.25, -0.72, -0.3, "Metal"),
	}),
}

-- round body, top hat with a clover, lucky coin
H.Lucky = {
	Palette = { Primary = rgb(60, 190, 90), Secondary = rgb(30, 30, 36), Accent = rgb(255, 215, 80), Skin = rgb(240, 205, 165), Gold = rgb(255, 205, 60) },
	HatAt = Vector3.new(0, 2.8, 0),
	Pieces = join(legs(), {
		S("Body", 2.3, 0, -1.2, 0, "Primary"),
		B("Bowtie", 0.8, 0.32, 0.15, 0, -0.18, -0.95, "Accent"),
		S("Head", 1.5, 0, 0.78, 0, "Skin"),
		B("Smile", 0.5, 0.1, 0.1, 0, 0.48, -0.74, "Eye"),
		C("HatBrim", 0.15, 2.0, 0, 1.42, 0, "Secondary"),
		C("HatCrown", 1.3, 1.3, 0, 2.1, 0, "Secondary"),
		C("HatBand", 0.3, 1.34, 0, 1.66, 0, "Primary"),
		S("CloverA", 0.32, -0.16, 1.72, -0.66, "Primary"),
		S("CloverB", 0.32, 0.16, 1.72, -0.66, "Primary"),
		S("CloverC", 0.32, 0, 1.95, -0.66, "Primary"),
		C("Coin", 0.12, 0.85, 1.35, -1.1, -0.4, "Gold", { Front = true, Material = NEON }),
	}, eyes(0.85, -0.74)),
}

-- a big friendly blob with googly eyes, an antenna and a mini goober friend
H.Goober = {
	Palette = { Primary = rgb(120, 220, 90), Secondary = rgb(80, 160, 60), Accent = rgb(255, 110, 190), Skin = rgb(120, 220, 90) },
	HatAt = Vector3.new(0, 0.2, 0),
	Pieces = {
		B("Blob", 3.0, 2.6, 3.0, 0, -1.55, 0, "Primary", { Shape = BALL }),
		S("FootL", 0.9, -0.75, -2.75, -0.3, "Secondary"),
		S("FootR", 0.9, 0.75, -2.75, -0.3, "Secondary"),
		S("EyeL", 0.85, -0.5, -0.85, -1.2, "White"),
		S("EyeR", 0.85, 0.5, -0.85, -1.2, "White"),
		S("PupilL", 0.4, -0.42, -0.95, -1.6, "Eye"),
		S("PupilR", 0.4, 0.6, -0.8, -1.6, "Eye"),
		B("Mouth", 0.7, 0.15, 0.1, 0, -1.55, -1.48, "Eye"),
		C("Stalk", 1.0, 0.12, 0, 0.2, 0, "Secondary"),
		S("Bobble", 0.6, 0, 0.8, 0, "Accent"),
		S("Buddy", 0.95, 1.45, -0.55, 0.3, "Primary"),
		S("BuddyEyeL", 0.22, 1.32, -0.45, -0.1, "White"),
		S("BuddyEyeR", 0.22, 1.58, -0.45, -0.1, "White"),
	},
}

-- a faceless dark shape with glowing eyes and floating shards
H.Void = {
	Palette = { Primary = rgb(60, 30, 100), Secondary = rgb(40, 34, 60), Accent = rgb(170, 90, 255), Skin = rgb(28, 24, 40), Dark = rgb(22, 20, 32) },
	HatAt = Vector3.new(0, 1.62, 0),
	Pieces = {
		B("Tail", 1.1, 1.3, 0.85, 0, -2.1, 0, "Dark", { R = CFrame.Angles(0, 0, math.rad(45)) * CFrame.Angles(math.rad(35), 0, 0) }),
		B("Body", 1.8, 1.8, 1.2, 0, -0.75, 0, "Dark"),
		B("Collar", 2.1, 0.4, 1.45, 0, 0.15, 0, "Primary"),
		B("Head", 1.4, 1.4, 1.4, 0, 0.92, 0, "Dark"),
		B("EyeL", 0.42, 0.15, 0.1, -0.3, 0.98, -0.72, "Accent"),
		B("EyeR", 0.42, 0.15, 0.1, 0.3, 0.98, -0.72, "Accent"),
		B("ShardA", 0.3, 0.75, 0.3, -1.6, -0.3, -0.4, "Accent", { R = CFrame.Angles(0, 0, math.rad(35)) }),
		B("ShardB", 0.3, 0.75, 0.3, 1.6, -0.6, 0.5, "Accent", { R = CFrame.Angles(0, 0, math.rad(-30)) }),
		B("ShardC", 0.26, 0.6, 0.26, 1.1, 0.9, -0.6, "Accent", { R = CFrame.Angles(math.rad(30), 0, math.rad(20)) }),
		C("Wisp", 0.1, 1.8, 0, -2.9, 0, "Accent", { Transparency = 0.45 }),
	},
}

-- a cube head with RGB-split pixels, a body with a missing chunk
H.Glitch = {
	Palette = { Primary = rgb(40, 220, 230), Secondary = rgb(255, 60, 200), Accent = rgb(255, 60, 200), Skin = rgb(240, 240, 245), White = rgb(240, 240, 245) },
	HatAt = Vector3.new(0, 1.65, 0),
	Pieces = join(legs(), {
		B("Body", 1.8, 1.7, 1.2, 0, -1.05, 0, "Primary"),
		B("Hole", 0.62, 0.62, 1.26, 0.62, -0.62, 0, "Dark"),
		B("Head", 1.6, 1.6, 1.6, 0, 0.85, 0, "White"),
		B("Ghost", 1.6, 1.6, 0.06, 0.16, 0.92, 0.84, "Accent", { Transparency = 0.35 }),
		B("PixelEyeL", 0.3, 0.3, 0.1, -0.35, 0.9, -0.82, "Eye"),
		B("PixelEyeR", 0.3, 0.3, 0.1, 0.35, 0.9, -0.82, "Eye"),
		B("PixelA", 0.32, 0.32, 0.32, 1.25, 1.45, 0, "Accent"),
		B("PixelB", 0.28, 0.28, 0.28, -1.35, 0.1, -0.3, "Primary", { Material = NEON }),
		B("PixelC", 0.3, 0.3, 0.3, 0.95, -2.0, 0.4, "Accent"),
	}),
}

-- flame hair, a glowing core, visor
H.Overdrive = {
	Palette = { Primary = rgb(255, 110, 30), Secondary = rgb(35, 30, 40), Accent = rgb(255, 235, 80), Skin = rgb(240, 200, 155) },
	HatAt = Vector3.new(0, 2.0, 0),
	Pieces = join(legs(), {
		B("Body", 1.9, 1.7, 1.2, 0, -1.05, 0, "Primary"),
		S("Core", 0.75, 0, -0.9, -0.6, "Accent"),
		B("StripeL", 0.18, 1.62, 1.24, -0.62, -1.05, 0, "Accent"),
		B("StripeR", 0.18, 1.62, 1.24, 0.62, -1.05, 0, "Accent"),
		S("Head", 1.5, 0, 0.75, 0, "Skin"),
		B("Visor", 1.35, 0.32, 0.18, 0, 0.85, -0.72, "Secondary"),
		B("FlameA", 0.38, 1.0, 0.38, 0, 1.55, 0, "Accent", { R = CFrame.Angles(0, math.rad(45), 0) }),
		B("FlameB", 0.34, 0.85, 0.34, -0.45, 1.4, 0.1, "Accent", { R = CFrame.Angles(0, 0, math.rad(28)) }),
		B("FlameC", 0.34, 0.85, 0.34, 0.45, 1.4, 0.1, "Accent", { R = CFrame.Angles(0, 0, math.rad(-28)) }),
		B("FlameD", 0.3, 0.8, 0.3, 0, 1.35, 0.5, "Primary", { R = CFrame.Angles(math.rad(-30), 0, 0), Material = NEON }),
	}),
}

-- a screen head that shows 67, antennas, a gold chain
H.SixSeven = {
	Palette = { Primary = rgb(120, 60, 200), Secondary = rgb(35, 30, 45), Accent = rgb(255, 205, 50), Skin = rgb(240, 200, 155), Gold = rgb(255, 205, 50) },
	HatAt = Vector3.new(0, 1.65, 0),
	Pieces = join(legs(), {
		B("Body", 1.9, 1.7, 1.2, 0, -1.05, 0, "Primary"),
		B("Chain", 1.4, 0.15, 0.1, 0, -0.35, -0.63, "Gold"),
		C("Pendant", 0.1, 0.62, 0, -0.72, -0.66, "Gold", { Front = true, Material = NEON }),
		B("Head", 1.95, 1.5, 1.3, 0, 0.85, 0, "Secondary"),
		B("Screen", 1.65, 1.15, 0.06, 0, 0.85, -0.66, "Accent", { Text = "67", TextColor = rgb(60, 25, 90) }),
		B("AntennaL", 0.12, 0.65, 0.12, -0.6, 1.85, 0, "Gold", { R = CFrame.Angles(0, 0, math.rad(20)) }),
		B("AntennaR", 0.12, 0.65, 0.12, 0.6, 1.85, 0, "Gold", { R = CFrame.Angles(0, 0, math.rad(-20)) }),
	}),
}

-- a hooded shape with no face, only a question
H.Unknown = {
	Palette = { Primary = rgb(24, 24, 30), Secondary = rgb(40, 40, 50), Accent = rgb(240, 240, 255), Skin = rgb(10, 10, 14), Dark = rgb(18, 18, 24) },
	HatAt = Vector3.new(0, 1.85, 0.1),
	Pieces = {
		B("Robe", 2.0, 2.8, 1.4, 0, -1.5, 0, "Dark"),
		S("Hood", 1.95, 0, 0.8, 0.12, "Primary"),
		S("Void", 1.35, 0, 0.75, -0.38, "Skin"),
		B("Mark", 0.8, 0.8, 0.05, 0, 0.78, -1.02, "Skin", { Text = "?", TextColor = rgb(240, 240, 255), Transparency = 1 }),
		C("Halo", 0.08, 1.45, 0, 1.95, 0, "Accent", { Transparency = 0.25 }),
	},
}

-- a soft glowing ring under every hero (readability inside a horde)
HeroModels.Ring = { Name = "HeroRing", Size = Vector3.new(0.08, 3.4, 3.4), At = CFrame.new(0, -2.96, 0) * UP, Role = "Accent", Shape = CYL, Material = NEON, Transparency = 0.55 }

---------------------------------------------------------------------------
-- hero skins: palettes that recolour Primary / Secondary / Accent of any hero
---------------------------------------------------------------------------
HeroModels.Skins = {
	Default = nil,
	Midnight = { Primary = rgb(35, 38, 70), Secondary = rgb(80, 85, 130), Accent = rgb(120, 180, 255) },
	Candy = { Primary = rgb(255, 150, 200), Secondary = rgb(150, 220, 255), Accent = rgb(255, 255, 255) },
	Neon = { Primary = rgb(22, 22, 30), Secondary = rgb(50, 50, 70), Accent = rgb(0, 255, 200) },
	Frost = { Primary = rgb(190, 230, 255), Secondary = rgb(120, 170, 220), Accent = rgb(140, 240, 255) },
	Gold = { Primary = rgb(255, 200, 60), Secondary = rgb(200, 150, 40), Accent = rgb(255, 250, 200) },
	Shadow67 = { Primary = rgb(18, 12, 30), Secondary = rgb(90, 40, 160), Accent = rgb(255, 205, 50) },
	Glitched = { Primary = rgb(255, 0, 200), Secondary = rgb(0, 255, 255), Accent = rgb(255, 255, 0) },
}

local BASE = {
	Primary = rgb(120, 120, 140),
	Secondary = rgb(60, 60, 70),
	Accent = rgb(255, 255, 255),
	Skin = rgb(240, 200, 160),
	Dark = rgb(40, 42, 56),
	Metal = rgb(150, 155, 170),
	White = rgb(245, 245, 250),
	Eye = rgb(20, 20, 26),
	Gold = rgb(255, 205, 60),
}

-- the colour of a role for a hero (+ optional skin)
function HeroModels.Color(heroKey: string, role: string, skinKey: string?): Color3
	local skin = skinKey and HeroModels.Skins[skinKey]
	if skin and skin[role] then
		return skin[role]
	end
	local hero = H[heroKey]
	local palette = hero and hero.Palette
	return (palette and palette[role]) or BASE[role] or BASE.Primary
end

---------------------------------------------------------------------------
-- hats (cosmetics): pieces around a 1.2 stud head centred 0.6 below the hero's HatAt
---------------------------------------------------------------------------
HeroModels.Hats = {
	None = {},
	Cone = {
		{ Name = "Cone0", Size = Vector3.new(0.55, 1.3, 1.3), Color = rgb(255, 120, 30), At = CFrame.new(0, 0.85, 0) * UP, Shape = CYL },
		{ Name = "Cone1", Size = Vector3.new(0.55, 0.95, 0.95), Color = rgb(255, 255, 255), At = CFrame.new(0, 1.35, 0) * UP, Shape = CYL },
		{ Name = "Cone2", Size = Vector3.new(0.55, 0.6, 0.6), Color = rgb(255, 120, 30), At = CFrame.new(0, 1.85, 0) * UP, Shape = CYL },
	},
	PartyHat = {
		{ Name = "Party0", Size = Vector3.new(0.5, 1.2, 1.2), Color = rgb(170, 90, 255), At = CFrame.new(0, 0.8, 0) * UP, Shape = CYL },
		{ Name = "Party1", Size = Vector3.new(0.5, 0.85, 0.85), Color = rgb(255, 215, 60), At = CFrame.new(0, 1.28, 0) * UP, Shape = CYL },
		{ Name = "Party2", Size = Vector3.new(0.5, 0.5, 0.5), Color = rgb(170, 90, 255), At = CFrame.new(0, 1.72, 0) * UP, Shape = CYL },
		{ Name = "PartyPom", Size = Vector3.new(0.4, 0.4, 0.4), Color = rgb(255, 255, 255), At = CFrame.new(0, 2.05, 0), Shape = BALL },
	},
	Shades = {
		{ Name = "HatShades", Size = Vector3.new(1.35, 0.32, 0.2), Color = rgb(10, 10, 15), At = CFrame.new(0, 0.15, -0.62) },
		{ Name = "HatShadesBridge", Size = Vector3.new(1.45, 0.08, 0.1), Color = rgb(255, 205, 60), At = CFrame.new(0, 0.3, -0.66) },
	},
	Propeller = {
		{ Name = "CapTop", Size = Vector3.new(0.5, 1.35, 1.35), Color = rgb(60, 140, 255), At = CFrame.new(0, 0.72, 0) * UP, Shape = CYL },
		{ Name = "CapStick", Size = Vector3.new(0.1, 0.4, 0.1), Color = rgb(40, 40, 40), At = CFrame.new(0, 1.15, 0) },
		{ Name = "Blade", Size = Vector3.new(1.6, 0.06, 0.25), Color = rgb(255, 60, 70), At = CFrame.new(0, 1.35, 0) },
		{ Name = "Blade2", Size = Vector3.new(0.25, 0.06, 1.6), Color = rgb(255, 215, 60), At = CFrame.new(0, 1.35, 0) },
	},
	Headband67 = {
		{ Name = "Headband", Size = Vector3.new(1.3, 0.3, 1.3), Color = rgb(255, 205, 50), At = CFrame.new(0, 0.35, 0), Material = NEON },
		{ Name = "Tag67", Size = Vector3.new(0.6, 0.3, 0.05), Color = rgb(40, 20, 60), At = CFrame.new(0, 0.35, -0.68), Text = "67" },
	},
	Halo = {
		{ Name = "Halo", Size = Vector3.new(0.15, 1.5, 1.5), Color = rgb(255, 245, 170), At = CFrame.new(0, 1.2, 0) * UP, Shape = CYL, Material = NEON },
	},
	GoldAntenna = {
		{ Name = "GoldStick", Size = Vector3.new(0.15, 0.9, 0.15), Color = rgb(220, 170, 30), At = CFrame.new(0, 0.95, 0) },
		{ Name = "GoldBall", Size = Vector3.new(0.55, 0.55, 0.55), Color = rgb(255, 215, 50), At = CFrame.new(0, 1.45, 0), Shape = BALL, Material = NEON },
	},
	Crown = {
		{ Name = "CrownBand", Size = Vector3.new(1.3, 0.35, 1.3), Color = rgb(255, 205, 50), At = CFrame.new(0, 0.8, 0), Material = NEON },
		{ Name = "CrownSpikeL", Size = Vector3.new(0.3, 0.45, 0.3), Color = rgb(255, 215, 60), At = CFrame.new(-0.45, 1.15, -0.5), Material = NEON },
		{ Name = "CrownSpikeM", Size = Vector3.new(0.3, 0.45, 0.3), Color = rgb(255, 215, 60), At = CFrame.new(0, 1.15, -0.5), Material = NEON },
		{ Name = "CrownSpikeR", Size = Vector3.new(0.3, 0.45, 0.3), Color = rgb(255, 215, 60), At = CFrame.new(0.45, 1.15, -0.5), Material = NEON },
		{ Name = "CrownGem", Size = Vector3.new(0.25, 0.25, 0.1), Color = rgb(255, 60, 120), At = CFrame.new(0, 0.8, -0.68), Shape = BALL },
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

local function makePart(piece: Piece, color: Color3, cf: CFrame, container: Instance, weldTo: BasePart?): BasePart
	local p = Instance.new("Part")
	p.Name = piece.Name
	p.Size = piece.Size
	p.Color = color
	p.Material = piece.Material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = piece.Transparency or 0
	if piece.Shape then
		p.Shape = piece.Shape
	end
	p.CFrame = cf
	if weldTo then
		p.Anchored = false
		p.Massless = true
		local w = Instance.new("WeldConstraint")
		w.Part0 = p
		w.Part1 = weldTo
		w.Parent = p
	else
		p.Anchored = true
	end
	if piece.Text then
		textGui(p, piece.Text, piece.TextColor)
	end
	p.Parent = container
	return p
end

export type BuildOptions = {
	Skin: string?,
	Hat: string?,
	WeldTo: BasePart?, -- weld (a real character); nil = anchored (a preview)
	Ring: boolean?,
}

--[[
	Builds hero `key` around `origin` (the CFrame a HumanoidRootPart would have) into
	`container`. Returns the parts.
]]
function HeroModels.Build(key: string, origin: CFrame, container: Instance, opts: BuildOptions?): { BasePart }
	local o = opts or {}
	local hero = H[key] or H.Rookie
	local out = {}
	for _, piece in hero.Pieces do
		local color = piece.Color or HeroModels.Color(key, piece.Role or "Primary", o.Skin)
		table.insert(out, makePart(piece, color, origin * piece.At, container, o.WeldTo))
	end
	if o.Ring ~= false then
		table.insert(out, makePart(HeroModels.Ring, HeroModels.Color(key, "Accent", o.Skin), origin * HeroModels.Ring.At, container, o.WeldTo))
	end
	local hat = o.Hat and HeroModels.Hats[o.Hat]
	if hat and #hat > 0 then
		local head = origin * CFrame.new(hero.HatAt - Vector3.new(0, 0.6, 0))
		for _, piece in hat do
			table.insert(out, makePart(piece, piece.Color or rgb(255, 255, 255), head * piece.At, container, o.WeldTo))
		end
	end
	return out
end

-- height of the hero model (for cameras / name tags)
function HeroModels.Top(key: string): number
	local hero = H[key] or H.Rookie
	return hero.HatAt.Y
end

return HeroModels
