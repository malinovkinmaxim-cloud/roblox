--[[
	BestiaryModels - the models of the BESTIARY (shared/EnemyData.lua, Role Regular / Elite /
	Boss / Minion): 2 regulars, 1 elite and 1 main boss per difficulty, plus their minions.
	Built with the same builders as Render/EnemyModels.lua (EnemyModels.Kit), registered into
	its styles.

	THE SAME WORLD AS THE HEROES (chibi):
	  * a big round head / body (about half the height), short body, tiny limbs (balls, capsules)
	  * simple rounded shapes; small sharp details only (horns, fangs, spikes: wedges)
	  * SmoothPlastic, flat colours: one main colour, a dark accent, a light highlight; Neon only
	    for eyes, cores, cracks and crystals
	  * a face: big cartoon eyes (white oval, black pupil, a white shine) or two glowing ovals
	  * the 67 mark: some carry a "6" or a "7" (a SurfaceGui, FredokaOne), not all of them
	  * front = -Z; the root is the first part (at the origin, it never rotates on its own)
	Sizes against a hero (H ~ 4.7 studs): regulars 0.5-0.9 H, elites 1.3-1.8 H once dressed as
	elites (x1.3), bosses 3-5 H, THE 67 up to 6 H.
	Budget: a regular <= 10 parts, an elite <= 18 (with its elite ring), a boss <= 45.
	Moving parts (wings, capes, jaws, tails, orbiting moons...) are tagged with anim():
	Render/EnemyAnimator.lua moves them. Each style returns the root's height above the ground.
]]

local BestiaryModels = {}

local rgb = Color3.fromRGB
local TAU = math.pi * 2

function BestiaryModels.Register(STYLES, K)
	local ball, box, cyl, disc, wedge, tag, anim, mark = K.ball, K.box, K.cyl, K.disc, K.wedge, K.tag, K.anim, K.mark
	local cartoonEyes, glowEyes = K.cartoonEyes, K.glowEyes
	local WHITE, BLACK, GOLD, NEON, FRONT = K.WHITE, K.BLACK, K.GOLD, K.NEON, K.FRONT
	local V = Vector3.new
	local CF = CFrame.new
	local ANG = CFrame.Angles
	local FRONT_FACE = Enum.NormalId.Front

	-- a horizontal triangle (a bat wing, a flipper seen from above) on side -1 / +1: the right
	-- angle sits at the body, the tip points out and back
	local function flatWing(b, name: string, side: number, size: Vector3, color: Color3, pos: Vector3): BasePart
		return wedge(b, name, size, color, CF(pos) * ANG(0, 0, -side * math.pi / 2))
	end

	-- a spike / horn / fang pointing up (a wedge seen from the side); down = pointing down
	local function spike(b, name: string, size: Vector3, color: Color3, pos: Vector3, tilt: number?, down: boolean?, material: Enum.Material?): BasePart
		local cf = CF(pos) * ANG(0, 0, tilt or 0)
		if down then
			cf *= ANG(math.pi, 0, 0)
		end
		return wedge(b, name, size, color, cf, material)
	end

	-- a triangle facing the front (carved pumpkin eyes)
	local function frontTriangle(b, name: string, w: number, h: number, color: Color3, pos: Vector3, material: Enum.Material?): BasePart
		return wedge(b, name, V(0.15, h, w), color, CF(pos) * ANG(0, math.pi / 2, 0), material)
	end

	--------------------------------------------------------------------------------- I CALM · Meadow
	-- Gloopy: a squashed see-through slime with a lighter core, big eyes, a "6" on its belly
	function STYLES.Gloopy(b, c: Color3, a: Color3): number
		local body = ball(b, "Body", V(3, 2.6, 3), c, Vector3.zero)
		body.Transparency = 0.15
		ball(b, "Core", V(1.7, 1.35, 1.7), rgb(182, 245, 160), V(0, -0.25, 0.15))
		cartoonEyes(b, 0.78, 0.55, 0.35, -1.22)
		mark(body, "6", a, FRONT_FACE, 0.5, 0.8, 0.3)
		return 1.3
	end

	-- Mini Gloop: MEGA SIX's orbiting slime (a little lighter, no mark)
	function STYLES.MiniGloop(b, c: Color3, _a: Color3): number
		local body = ball(b, "Body", V(2.5, 2.2, 2.5), c, Vector3.zero)
		body.Transparency = 0.1
		cartoonEyes(b, 0.68, 0.46, 0.3, -1.0)
		return 1.1
	end

	-- Buzz Bat: a round purple ball with triangle wings, pointy ears, yellow eyes, two fangs
	function STYLES.BuzzBat(b, c: Color3, a: Color3): number
		ball(b, "Body", 2.0, c, Vector3.zero)
		for _, side in { -1, 1 } do
			local w = flatWing(b, "Wing", side, V(0.16, 1.7, 1.5), a, V(side * 1.7, 0.2, 0.2))
			anim(b, w, "Flap", 0.7, 14, 0)
			spike(b, "Ear", V(0.2, 0.75, 0.55), a, V(side * 0.5, 1.05, 0.1), -side * 0.25)
			spike(b, "Fang", V(0.12, 0.3, 0.16), WHITE, V(side * 0.2, -0.48, -0.86), 0, true)
		end
		glowEyes(b, V(0.42, 0.55, 0.25), 0.36, 0.22, -0.86, rgb(253, 224, 71))
		return 3.0
	end

	-- King Gloop: a big Gloopy with a paper crown, a curly moustache, three little slimes inside
	function STYLES.KingGloop(b, c: Color3, a: Color3): number
		local body = ball(b, "Body", V(6.4, 5.4, 6.4), c, Vector3.zero)
		body.Transparency = 0.2
		ball(b, "Core", V(3.8, 3.0, 3.8), rgb(182, 245, 160), V(0, -0.6, 0.3))
		for i = 0, 2 do
			local ang = i * TAU / 3 + 0.4
			ball(b, "Inside", 0.9, c:Lerp(BLACK, 0.25), V(math.cos(ang) * 1.0, -0.6 + (i - 1) * 0.35, 0.3 + math.sin(ang) * 1.0))
		end
		cartoonEyes(b, 1.45, 1.15, 0.85, -2.62, nil, false)
		-- the moustache: two thin curls under the eyes
		for _, side in { -1, 1 } do
			cyl(b, "Moustache", 1.5, 0.28, rgb(92, 64, 40), CF(side * 0.75, -0.35, -3.05) * ANG(0, side * 0.35, side * 0.35))
		end
		-- the paper crown: a band and five points
		local crown = disc(b, "Crown", 2.9, 1.0, a, V(0, 3.0, 0))
		anim(b, crown, "Bob", 0.18, 6, 1.2)
		for i = 0, 4 do
			local ang = i * TAU / 5
			wedge(b, "CrownTip", V(0.25, 0.9, 0.7), a, CF(math.cos(ang) * 1.15, 3.85, math.sin(ang) * 1.15) * ANG(0, -ang - math.pi / 2, 0))
		end
		return 2.7
	end

	-- MEGA SIX: a giant slime shaped like a fat 6 (the round body, a curled tail on top), a huge face
	function STYLES.MegaSix(b, c: Color3, a: Color3): number
		local body = ball(b, "Body", V(15, 12, 14), c, Vector3.zero)
		body.Transparency = 0.12
		ball(b, "Core", V(9, 7, 8.5), rgb(182, 245, 160), V(0, -1, 0.8))
		-- little slimes floating inside the core
		for i = 0, 2 do
			local ang = i * TAU / 3
			ball(b, "Inside", 1.6, c:Lerp(BLACK, 0.25), V(math.cos(ang) * 2.4, -1 + i * 0.6, 0.8 + math.sin(ang) * 2.2))
		end
		-- the hook of the 6: rises at +X (your left when it faces you) and curls over the top
		local chain = {
			{ 5.2, V(4.6, 5.6, 0.8) },
			{ 4.6, V(4.6, 9.4, 0.8) },
			{ 4.0, V(3.0, 12.4, 0.8) },
			{ 3.4, V(0.4, 13.7, 0.8) },
			{ 2.8, V(-2.2, 13.0, 0.8) },
		}
		for i, link in chain do
			local p = ball(b, "Hook", link[1], c, link[2])
			p.Transparency = 0.12
			if i >= 4 then
				anim(b, p, "Bob", 0.35, 2.2, i * 0.6)
			end
		end
		cartoonEyes(b, 4.0, 3.0, 1.4, -5.9)
		box(b, "Mouth", V(2.6, 0.45, 0.4), a:Lerp(BLACK, 0.5), CF(0, -2.2, -6.7))
		-- gloss
		ball(b, "Gloss", V(1.6, 0.9, 0.6), WHITE, V(-4.4, 3.4, -4.6))
		ball(b, "Gloss", V(0.9, 0.5, 0.4), WHITE, V(-5.4, 2.4, -3.8))
		-- phase 2: SWELL (a puffed-out layer, angry brows)
		local puff = tag(ball(b, "Puff", V(16.6, 13.2, 15.4), c:Lerp(WHITE, 0.2), V(0, -0.2, 0)), "Phase", 2)
		puff.Transparency = 0.6
		for _, side in { -1, 1 } do
			tag(box(b, "Brow", V(2.6, 0.6, 0.5), a:Lerp(BLACK, 0.4), CF(side * 2.6, 3.7, -6.2) * ANG(0, 0, side * 0.35)), "Phase", 2)
		end
		return 6
	end

	--------------------------------------------------------------------------------- II HUNT · Graveyard
	-- Boo Sheet: a see-through ghost head on a wavy skirt, pit eyes, an oval mouth, tiny hands
	function STYLES.BooSheet(b, c: Color3, a: Color3): number
		local head = ball(b, "Head", 3.0, c, Vector3.zero)
		head.Transparency = 0.25
		for i = -1, 1 do
			local s = ball(b, "Skirt", V(1.35, 1.3, 1.35), c, V(i * 0.92, -1.35 - (if i == 0 then 0.25 else 0), 0.15 - (if i == 0 then 0.15 else 0)))
			s.Transparency = 0.25
			anim(b, s, "Sway", 0.25, 3.5, i * 1.3)
		end
		for _, side in { -1, 1 } do
			ball(b, "Eye", V(0.5, 0.8, 0.3), BLACK, V(side * 0.5, 0.3, -1.33))
			local hand = ball(b, "Hand", 0.75, c, V(side * 1.62, -0.45, -0.35))
			hand.Transparency = 0.25
		end
		ball(b, "Mouth", V(0.45, 0.62, 0.22), a:Lerp(BLACK, 0.6), V(0, -0.4, -1.38))
		local light = Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = rgb(170, 200, 255)
		light.Brightness = 0.7
		light.Range = 9
		light.Shadows = false
		light.Enabled = false -- (Render/EnemyAnimator lights the nearest few)
		light.Parent = head
		return 2.6
	end

	-- Bonk Skull: a round skull, red dots in empty sockets, a crack, a clacking jaw
	function STYLES.BonkSkull(b, c: Color3, a: Color3): number
		ball(b, "Skull", 2.6, c, Vector3.zero)
		for _, side in { -1, 1 } do
			ball(b, "Socket", V(0.78, 0.82, 0.32), a, V(side * 0.5, 0.18, -1.14))
			ball(b, "Spark", 0.26, rgb(255, 60, 60), V(side * 0.5, 0.14, -1.3), NEON)
		end
		local jaw = ball(b, "Jaw", V(1.9, 0.7, 1.55), c:Lerp(BLACK, 0.06), V(0, -1.15, -0.35))
		anim(b, jaw, "Jaw", 0.35, 9)
		box(b, "Teeth", V(1.1, 0.22, 0.14), WHITE, CF(0, -0.85, -1.12))
		wedge(b, "Crack", V(0.12, 0.6, 0.5), a, CF(0.35, 0.95, -0.92) * ANG(0.6, 0, 0.3))
		return 1.3
	end

	-- Pumpkin Knight: a carved pumpkin head with a glowing face, a purple body, a round "7" shield,
	-- a short sword
	function STYLES.PumpkinKnight(b, c: Color3, a: Color3): number
		ball(b, "Pumpkin", V(3.4, 2.8, 3.1), c, Vector3.zero)
		for _, side in { -1, 1 } do
			ball(b, "Rib", V(1.5, 2.7, 2.9), c:Lerp(BLACK, 0.12), V(side * 1.05, 0, 0.05))
		end
		cyl(b, "Stem", 0.7, 0.45, rgb(74, 130, 60), CF(0, 1.65, 0) * ANG(0, 0, math.pi / 2))
		local glow = rgb(253, 224, 71)
		for _, side in { -1, 1 } do
			frontTriangle(b, "Eye", 0.7, 0.6, glow, V(side * 0.65, 0.4, -1.5), NEON)
		end
		box(b, "Smile", V(1.7, 0.35, 0.15), glow, CF(0, -0.55, -1.5), NEON)
		box(b, "Tooth", V(0.3, 0.2, 0.16), c, CF(0.2, -0.45, -1.53))
		ball(b, "Body", V(2.4, 2.2, 2.0), a, V(0, -2.45, 0.1))
		for _, side in { -1, 1 } do
			ball(b, "Hand", 0.7, a:Lerp(WHITE, 0.15), V(side * 1.45, -2.4, -0.6))
		end
		local shield = cyl(b, "Shield", 0.3, 2.4, a:Lerp(BLACK, 0.15), CF(0.95, -2.2, -1.45) * FRONT)
		mark(shield, "7", WHITE, Enum.NormalId.Right, 0.5, 0.5, 0.7)
		wedge(b, "Sword", V(0.16, 0.35, 1.9), rgb(210, 216, 228), CF(-1.45, -2.2, -1.5) * ANG(0, 0, 0))
		return 3.6
	end

	-- COUNT SEVEN: a huge pale chibi head, a black hair swoop, red eyes, a tall collar, a cape with
	-- a red lining, white gloves, a golden 7 on the chest
	function STYLES.CountSeven(b, c: Color3, a: Color3): number
		ball(b, "Head", V(9, 8.4, 8.4), c, Vector3.zero)
		local hair = rgb(24, 22, 30)
		-- the hair: a cap over the top and the back, two swoops at the front
		ball(b, "Hair", V(9.4, 4.8, 9.0), hair, V(0, 2.5, 0.45))
		wedge(b, "Swoop", V(3.4, 1.6, 2.8), hair, CF(-2.1, 3.1, -3.3) * ANG(-0.55, 0.35, 0.3))
		wedge(b, "Swoop", V(3.4, 1.6, 2.8), hair, CF(2.1, 3.1, -3.3) * ANG(-0.55, -0.35, -0.3))
		spike(b, "Peak", V(0.8, 1.6, 1.0), hair, V(0, 2.4, -4.0), 0, true)
		glowEyes(b, V(1.3, 1.7, 0.6), 1.6, 0.1, -3.85, rgb(255, 50, 60))
		for _, side in { -1, 1 } do
			ball(b, "Shine", 0.45, WHITE, V(side * 1.6 + 0.3, 0.6, -4.15))
			spike(b, "Fang", V(0.3, 0.7, 0.35), WHITE, V(side * 0.6, -2.2, -3.7), 0, true)
			-- the collar: two big wedges standing behind the head
			wedge(b, "Collar", V(0.5, 5.2, 3.6), hair, CF(side * 3.6, -3.0, 1.2) * ANG(0, side * 0.5, -side * 0.25))
			ball(b, "Glove", 1.6, WHITE, V(side * 3.3, -6.4, -1.6))
			ball(b, "Foot", V(1.8, 1.0, 2.4), hair, V(side * 1.5, -9.2, -0.3))
			tag(box(b, "Brow", V(2.2, 0.45, 0.4), hair, CF(side * 1.7, 1.75, -3.95) * ANG(0, 0, side * 0.4)), "Phase", 2)
		end
		box(b, "Mouth", V(2.0, 0.25, 0.3), hair, CF(0, -2.0, -3.85))
		local torso = ball(b, "Torso", V(5, 4.6, 4), hair, V(0, -6.4, 0.4))
		mark(torso, "7", GOLD, FRONT_FACE, 0.5, 0.45, 0.45)
		-- the cape: four black panels and a red lining, behind and below (never over the top)
		box(b, "Lining", V(5.6, 5.2, 0.3), a, CF(0, -6.2, 2.5))
		for i = -1.5, 1.5 do
			local panel = wedge(b, "Cape", V(1.6, 6.2, 1.4), hair, CF(i * 1.55, -6.0, 3.1) * ANG(math.pi, 0, 0))
			anim(b, panel, "Sway", 0.22, 4, i)
		end
		return 9.7
	end

	--------------------------------------------------------------------------------- III HORDE · Desert
	-- Wrappy: a mummy head wrapped in three tilted bandages, one green glowing eye, arms forward
	function STYLES.Wrappy(b, c: Color3, a: Color3): number
		ball(b, "Head", 2.5, c, Vector3.zero)
		local wrap = rgb(245, 235, 203)
		for i, tilt in { 0.35, -0.25, 0.1 } do
			cyl(b, "Wrap", 0.34, 2.62, wrap, CF(0, (i - 2) * 0.55, 0) * ANG(tilt, 0, math.pi / 2 + tilt * 0.6))
		end
		ball(b, "Eye", 0.46, a, V(0.45, 0.22, -1.17), NEON)
		ball(b, "Body", V(1.7, 1.4, 1.4), wrap, V(0, -1.85, 0.05))
		for _, side in { -1, 1 } do
			local arm = cyl(b, "Arm", 1.4, 0.5, wrap, CF(side * 0.78, -1.55, -0.95) * FRONT)
			anim(b, arm, "Sway", 0.18, 4, side)
		end
		box(b, "Legs", V(1.3, 0.7, 1.0), c:Lerp(BLACK, 0.2), CF(0, -2.85, 0.05))
		return 3.2
	end

	-- Scorp: a flat amber body, two ball claws, a tail of four balls arched over its back with a
	-- glowing stinger, a block of legs
	function STYLES.Scorp(b, c: Color3, a: Color3): number
		ball(b, "Body", V(2.6, 1.2, 3.0), c, Vector3.zero)
		for _, side in { -1, 1 } do
			ball(b, "Claw", V(1.1, 0.8, 1.2), c:Lerp(BLACK, 0.15), V(side * 1.4, 0, -1.8))
			ball(b, "Eye", 0.32, BLACK, V(side * 0.35, 0.45, -1.3))
		end
		ball(b, "Tail", 0.85, c, V(0, 0.8, 1.55))
		local t2 = ball(b, "Tail", 0.72, c, V(0, 1.8, 1.65))
		local t3 = ball(b, "Tail", 0.62, c, V(0, 2.55, 1.0))
		local sting = ball(b, "Stinger", 0.52, rgb(251, 146, 60), V(0, 2.65, 0.3), NEON)
		for i, p in { t2, t3, sting } do
			anim(b, p, "Sway", 0.1, 3, i * 0.5)
		end
		box(b, "Legs", V(3.3, 0.24, 1.7), a, CF(0, -0.45, 0.1))
		return 0.85
	end

	-- Sand Golem: floating sandstone blocks (no joints): a head with turquoise eyes, a torso with a
	-- golden stripe, hips, two fists that trail behind
	function STYLES.SandGolem(b, c: Color3, a: Color3): number
		box(b, "Torso", V(3.6, 3.0, 2.4), c, CF())
		box(b, "Head", V(2.4, 2.0, 2.0), c:Lerp(WHITE, 0.08), CF(0, 2.9, -0.1))
		for _, side in { -1, 1 } do
			box(b, "Eye", V(0.55, 0.32, 0.12), a, CF(side * 0.5, 3.0, -1.12), NEON)
			box(b, "Shoulder", V(1.2, 1.0, 1.6), c:Lerp(BLACK, 0.1), CF(side * 2.2, 1.6, 0))
			local fist = ball(b, "Fist", V(1.9, 1.7, 1.9), c:Lerp(BLACK, 0.12), V(side * 2.9, -0.6, -0.7))
			anim(b, fist, "Bob", 0.35, 2.4, side * 1.2 + 1)
		end
		box(b, "Stripe", V(2.6, 0.32, 0.12), GOLD, CF(0, 0.45, -1.23))
		local hips = box(b, "Hips", V(2.6, 1.2, 1.8), c:Lerp(BLACK, 0.06), CF(0, -2.45, 0))
		anim(b, hips, "Bob", 0.15, 2.4, 2.5)
		return 3.6
	end

	-- Sand Spout: PHARAOH SIXSEVEN's whirlwind: stacked sand discs, wider at the top, two dust balls
	function STYLES.SandSpout(b, c: Color3, a: Color3): number
		local core = disc(b, "Core", 2.0, 0.7, c, Vector3.zero)
		core.Transparency = 0.3
		for i, d in { 1.2, 2.8, 3.6 } do
			local p = disc(b, "Ring", d, 0.6, if i % 2 == 0 then a else c, V(0.15 * i, (i - 1.4) * 1.05, 0))
			p.Transparency = 0.35
			anim(b, p, "Spin", 1, 6 + i)
		end
		for i = 0, 1 do
			local dust = ball(b, "Dust", 0.6, a, V(2.1, 0.4 + i * 1.4, 0))
			anim(b, dust, "Orbit", 1, 5 + i * 2, i * math.pi)
		end
		return 1.6
	end

	-- PHARAOH SIXSEVEN: a floating golden mask with a striped headdress, glowing eyes, a false
	-- beard; two giant hands under it, a tail of three balls, a ring of 6 and 7 tiles around it
	function STYLES.PharaohSixseven(b, c: Color3, a: Color3): number
		ball(b, "Mask", V(8, 9.5, 5), c, Vector3.zero)
		local dark = rgb(24, 24, 30)
		-- the nemes: a band over the head and two striped flaps
		ball(b, "Nemes", V(10.2, 5.6, 7.2), c, V(0, 3.4, 1.2))
		box(b, "Stripe", V(10.0, 0.5, 6.4), a, CF(0, 4.6, 1.2))
		box(b, "Stripe", V(8.6, 0.5, 5.4), dark, CF(0, 5.6, 1.2))
		for _, side in { -1, 1 } do
			wedge(b, "Flap", V(1.3, 7.5, 3.2), a, CF(side * 4.9, -0.8, 1.6) * ANG(math.pi, 0, 0))
			box(b, "FlapStripe", V(1.36, 0.5, 3.0), dark, CF(side * 4.9, -1.2, 1.6))
			box(b, "Liner", V(1.9, 0.55, 0.3), dark, CF(side * 1.7, 1.5, -2.45))
			box(b, "Eye", V(1.3, 0.75, 0.3), a, CF(side * 1.7, 0.85, -2.45), NEON)
			-- the hands: a palm and two fingers each, hovering under the mask
			local palm = ball(b, "Palm", V(4.0, 2.6, 4.6), c:Lerp(WHITE, 0.15), V(side * 6.6, -6.0, -2.0))
			anim(b, palm, "Bob", 0.6, 1.8, side + 1.5)
			for k = 0, 1 do
				local finger = box(b, "Finger", V(0.9, 0.9, 2.4), c:Lerp(WHITE, 0.15), CF(side * (5.9 + k * 1.3), -6.2, -4.6))
				anim(b, finger, "Bob", 0.6, 1.8, side + 1.5)
			end
		end
		wedge(b, "Nose", V(1.2, 1.6, 1.0), c:Lerp(BLACK, 0.08), CF(0, -0.6, -2.6))
		box(b, "Mouth", V(2.2, 0.3, 0.3), dark, CF(0, -2.3, -2.3))
		cyl(b, "Beard", 2.4, 1.2, c, CF(0, -5.2, -1.5) * ANG(0, 0, math.pi / 2))
		disc(b, "BeardBand", 1.3, 0.35, a, V(0, -5.0, -1.5))
		spike(b, "Cobra", V(0.6, 1.4, 0.8), c, V(0, 6.0, -2.0))
		-- the tail: three shrinking balls under the mask
		for i, d in { 3.0, 2.3, 1.6 } do
			local t = ball(b, "Tail", d, if i % 2 == 0 then dark else c, V(0, -6.5 - i * 2.2, 1.0 + i * 0.6))
			anim(b, t, "Sway", 0.08, 1.6, i)
		end
		-- the ring of tiles: 6 and 7 in turn, orbiting (faster in phase 2)
		for i = 0, 5 do
			local ang = i * TAU / 6
			local tile = box(b, "Tile", V(1.9, 2.5, 0.32), c, CF(math.cos(ang) * 9.5, -1.5, math.sin(ang) * 9.5) * ANG(0, -ang - math.pi / 2, 0))
			mark(tile, if i % 2 == 0 then "6" else "7", dark, Enum.NormalId.Front, 0.5, 0.5, 0.85)
			mark(tile, if i % 2 == 0 then "6" else "7", dark, Enum.NormalId.Back, 0.5, 0.5, 0.85)
			anim(b, tile, "Orbit", 1, 0.6)
		end
		return 13.5
	end

	--------------------------------------------------------------------------------- IV NIGHTMARE · Frostbite
	-- Snowy Pal: two snowballs, a carrot nose, coal eyes, stick arms, a red scarf, a bucket hat
	function STYLES.SnowyPal(b, c: Color3, a: Color3): number
		ball(b, "Base", 2.6, c, Vector3.zero)
		ball(b, "Head", 2.0, c, V(0, 2.0, 0))
		wedge(b, "Nose", V(0.35, 0.35, 0.95), rgb(249, 115, 22), CF(0, 1.95, -1.3))
		for _, side in { -1, 1 } do
			ball(b, "Coal", 0.32, BLACK, V(side * 0.36, 2.32, -0.86))
			local arm = cyl(b, "Arm", 1.7, 0.18, rgb(110, 76, 48), CF(side * 1.75, 0.95, 0) * ANG(0, 0, side * 0.55))
			anim(b, arm, "Flap", 0.3, 6, side)
		end
		disc(b, "Scarf", 1.95, 0.42, a, V(0, 1.12, 0))
		box(b, "ScarfTail", V(0.5, 1.0, 0.18), a, CF(0.55, 0.6, -1.0) * ANG(0, 0, 0.15))
		cyl(b, "Hat", 1.0, 1.3, rgb(30, 30, 36), CF(0.35, 3.15, 0) * ANG(0, 0, math.pi / 2 - 0.3))
		return 1.3
	end

	-- Frost Wisp: a floating ice diamond around a light core, three shards circling it
	function STYLES.FrostWisp(b, c: Color3, a: Color3): number
		ball(b, "Core", 0.95, a, Vector3.zero, NEON)
		local shell = box(b, "Crystal", V(1.4, 1.4, 1.4), c, CF() * ANG(math.pi / 4, 0, math.pi / 4), NEON)
		shell.Transparency = 0.3
		box(b, "Tip", V(0.8, 0.8, 0.8), c, CF(0, 0.95, 0) * ANG(math.pi / 4, 0, math.pi / 4), NEON).Transparency = 0.2
		box(b, "Tip", V(0.8, 0.8, 0.8), c, CF(0, -0.95, 0) * ANG(math.pi / 4, 0, math.pi / 4), NEON).Transparency = 0.2
		for i = 0, 2 do
			local ang = i * TAU / 3
			local shard = box(b, "Shard", V(0.35, 0.55, 0.35), c:Lerp(WHITE, 0.4), CF(math.cos(ang) * 1.7, 0.2 * (i - 1), math.sin(ang) * 1.7) * ANG(0.5, 0, 0.5), NEON)
			anim(b, shard, "Orbit", 1, 2.5 + i * 0.9, ang)
		end
		for _, side in { -1, 1 } do
			ball(b, "Eye", 0.28, rgb(20, 40, 70), V(side * 0.3, 0.15, -0.95))
		end
		return 2.6
	end

	-- Yeti Chonk: a huge fluffy white head-body with tufts on top, a blue oval face, big paws and an
	-- ice club of three glowing crystals
	function STYLES.YetiChonk(b, c: Color3, a: Color3): number
		ball(b, "Fluff", V(4.6, 4.4, 4.2), c, Vector3.zero)
		for i = 0, 3 do
			local ang = i * TAU / 4 + 0.4
			local tuft = ball(b, "Tuft", 1.5, c:Lerp(rgb(200, 215, 235), 0.25), V(math.cos(ang) * 1.1, 2.0, math.sin(ang) * 1.0))
			anim(b, tuft, "Bob", 0.12, 3, i)
		end
		ball(b, "Face", V(2.8, 2.2, 0.7), rgb(147, 197, 253), V(0, -0.1, -1.92))
		cartoonEyes(b, 0.8, 0.55, 0.15, -2.24, nil, false)
		for _, side in { -1, 1 } do
			ball(b, "Paw", 1.5, c:Lerp(rgb(200, 215, 235), 0.4), V(side * 2.25, -1.3, -0.6))
			ball(b, "Foot", V(1.4, 0.9, 1.7), rgb(147, 197, 253), V(side * 1.05, -2.35, -0.2))
		end
		for i = 0, 2 do
			box(b, "Club", V(0.7, 1.0, 0.7), a, CF(2.45, -0.4 + i * 0.85, -1.0 - i * 0.15) * ANG(math.pi / 4, 0, math.pi / 4), NEON)
		end
		return 2.8
	end

	-- EMPEROR PENGUIN PRIME: a giant black penguin with a white belly (a blue 6), a yellow beak,
	-- flippers, and a crown of ice crystals
	function STYLES.PenguinPrime(b, c: Color3, a: Color3): number
		ball(b, "Body", V(13, 15, 12), c, Vector3.zero)
		local belly = ball(b, "Belly", V(9, 11, 3.2), rgb(248, 250, 252), V(0, -1.2, -4.7))
		mark(belly, "6", rgb(59, 130, 246), FRONT_FACE, 0.5, 0.62, 0.42)
		local beak = rgb(250, 204, 21)
		ball(b, "Beak", V(2.8, 1.3, 3.4), beak, V(0, 3.2, -6.3))
		ball(b, "Beak", V(2.2, 0.9, 2.6), beak:Lerp(rgb(249, 115, 22), 0.3), V(0, 2.4, -6.0))
		cartoonEyes(b, 2.3, 2.4, 5.2, -5.0)
		for _, side in { -1, 1 } do
			local flipper = wedge(b, "Flipper", V(0.9, 7.5, 3.0), c:Lerp(WHITE, 0.08), CF(side * 6.7, -1.2, 0.4) * ANG(math.pi, 0, side * 0.25))
			anim(b, flipper, "Flap", 0.3, 4, 0)
			ball(b, "Foot", V(3.2, 1.0, 4.2), beak:Lerp(rgb(249, 115, 22), 0.5), V(side * 3.0, -7.6, -2.0))
			tag(box(b, "Frost", V(2.2, 1.4, 2.2), a, CF(side * 4.6, 5.4, 0.5) * ANG(math.pi / 4, 0.4, math.pi / 4), NEON), "Phase", 2)
		end
		-- the ice crown
		disc(b, "Crown", 5.2, 0.8, rgb(186, 230, 253), V(0, 7.6, 0))
		for i = 0, 4 do
			local ang = i * TAU / 5
			box(b, "Crystal", V(0.9, 2.2 - (i % 2) * 0.6, 0.9), a, CF(math.cos(ang) * 2.0, 8.9 - (i % 2) * 0.3, math.sin(ang) * 2.0) * ANG(0, ang, 0.2), NEON)
		end
		return 8.0
	end

	--------------------------------------------------------------------------------- V INFERNO · Volcano
	-- Magma Bun: a dark bun with glowing cracks, slit eyes and a little flame on top
	function STYLES.MagmaBun(b, c: Color3, a: Color3): number
		ball(b, "Bun", V(3, 2.4, 3), c, Vector3.zero)
		for i, cf in { CF(0, 0.9, -0.4) * ANG(0, 0.5, 0.3), CF(0.5, 0.4, -1.2) * ANG(0, -0.4, -0.5), CF(-0.7, 0.7, 0.6) * ANG(0, 1.2, 0.2) } do
			local crack = box(b, "Crack", V(1.8, 0.16, 0.2), a, cf, NEON)
			anim(b, crack, "Pulse", 1, 3, i)
		end
		for _, side in { -1, 1 } do
			box(b, "Eye", V(0.55, 0.16, 0.12), rgb(253, 224, 71), CF(side * 0.5, 0.3, -1.38) * ANG(0, 0, -side * 0.25), NEON)
		end
		for i = -1, 1 do
			local flame = spike(b, "Flame", V(0.25, 0.9 - math.abs(i) * 0.25, 0.6), if i == 0 then rgb(253, 224, 71) else a, V(i * 0.32, 1.55 - math.abs(i) * 0.12, 0), -i * 0.3, false, NEON)
			anim(b, flame, "Bob", 0.08, 8, i)
		end
		return 1.2
	end

	-- Imp Pop: a red chibi imp: big head, two horns, yellow eyes, a little body, a spear-tipped
	-- tail and a mini trident
	function STYLES.ImpPop(b, c: Color3, a: Color3): number
		ball(b, "Head", 2.2, c, Vector3.zero)
		for _, side in { -1, 1 } do
			spike(b, "Horn", V(0.24, 0.75, 0.42), a, V(side * 0.55, 1.15, 0), -side * 0.3)
		end
		glowEyes(b, V(0.4, 0.5, 0.2), 0.42, 0.15, -0.95, rgb(253, 224, 71))
		ball(b, "Body", V(1.2, 1.2, 1.0), c:Lerp(BLACK, 0.15), V(0, -1.5, 0.1))
		local tail = cyl(b, "Tail", 1.4, 0.16, c:Lerp(BLACK, 0.15), CF(0, -1.5, 1.2) * FRONT)
		anim(b, tail, "Sway", 0.3, 5)
		spike(b, "TailTip", V(0.2, 0.45, 0.3), a, V(0, -1.3, 1.95))
		cyl(b, "Trident", 2.2, 0.14, rgb(120, 110, 100), CF(0.85, -1.1, -0.5) * ANG(0, 0, math.pi / 2))
		box(b, "Fork", V(0.7, 0.15, 0.12), rgb(120, 110, 100), CF(0.85, 0.05, -0.5))
		return 2.25
	end

	-- Obsidian Crab: a black shell with glowing cracks (it bursts off when broken), two huge claws,
	-- eyes on stalks, six little legs
	function STYLES.ObsidianCrab(b, c: Color3, a: Color3): number
		b.Regrow = true -- its shell grows back
		ball(b, "Body", V(4.6, 2.0, 3.8), c:Lerp(a, 0.25), Vector3.zero)
		local plate = tag(ball(b, "Shell", V(5.2, 1.6, 4.3), c, V(0, 0.7, 0.1)), "HideIn", 8)
		plate.Name = "Shell"
		for i, cf in { CF(0, 1.4, -0.5) * ANG(0, 0.4, 0), CF(1.2, 1.25, 0.6) * ANG(0, -0.7, 0), CF(-1.3, 1.25, 0.4) * ANG(0, 0.9, 0) } do
			local crack = tag(box(b, "Crack", V(2.0, 0.15, 0.2), a, cf, NEON), "HideIn", 8)
			anim(b, crack, "Pulse", 1, 2.5, i)
		end
		for _, side in { -1, 1 } do
			ball(b, "Claw", 1.8, c:Lerp(WHITE, 0.08), V(side * 2.8, 0, -2.1))
			local pincer = wedge(b, "Pincer", V(0.5, 0.7, 1.5), c:Lerp(WHITE, 0.08), CF(side * 2.8, 0.75, -3.1))
			anim(b, pincer, "Jaw", -0.35, 7, side)
			cyl(b, "Stalk", 1.2, 0.2, c, CF(side * 0.6, 1.6, -1.5) * ANG(0, 0, math.pi / 2))
			ball(b, "Eye", 0.6, WHITE, V(side * 0.6, 2.3, -1.5))
			ball(b, "Pupil", 0.3, BLACK, V(side * 0.6, 2.3, -1.78))
			box(b, "Legs", V(1.4, 0.25, 2.6), c, CF(side * 2.4, -0.9, 0.4) * ANG(0, 0, side * 0.35))
		end
		return 1.4
	end

	-- DRAKO 67: a chibi red dragon: a big head with three horns and glowing eyes, an opening jaw,
	-- a yellow belly with "67", small wings, a tail with a fiery tip
	function STYLES.Drako67(b, c: Color3, a: Color3): number
		ball(b, "Head", V(10, 9, 9.5), c, Vector3.zero)
		ball(b, "Snout", V(6, 3.4, 4.2), c:Lerp(WHITE, 0.05), V(0, -1.6, -5.0))
		local jaw = ball(b, "Jaw", V(5.4, 1.6, 4.0), c:Lerp(BLACK, 0.12), V(0, -3.5, -4.4))
		anim(b, jaw, "Jaw", 0.25, 3)
		glowEyes(b, V(1.6, 2.0, 0.6), 2.4, 1.2, -4.3, rgb(251, 146, 60))
		local horn = rgb(250, 240, 220)
		for i = -1, 1 do
			spike(b, "Horn", V(0.7, 2.6 - math.abs(i) * 0.6, 1.4), horn, V(i * 2.4, 4.6 - math.abs(i) * 0.4, 0.4), -i * 0.35)
		end
		for _, side in { -1, 1 } do
			ball(b, "Shine", 0.5, WHITE, V(side * 2.4 + 0.35, 1.7, -4.6))
			local wing = flatWing(b, "Wing", side, V(0.3, 4.2, 3.2), c:Lerp(BLACK, 0.25), V(side * 4.4, -5.0, 3.6))
			anim(b, wing, "Flap", 0.45, 5, 0)
			ball(b, "Arm", 1.6, c, V(side * 3.2, -7.5, -1.8))
			ball(b, "Foot", V(2.2, 1.2, 2.8), c:Lerp(BLACK, 0.2), V(side * 2.0, -10.9, -0.6))
			tag(ball(b, "Smoke", 0.7, rgb(253, 186, 116), V(side * 1.0, -1.1, -7.1), NEON), "Phase", 2)
		end
		ball(b, "Body", V(7, 7, 6), c, V(0, -7.5, 1))
		local belly = ball(b, "Belly", V(5, 5.6, 2), a, V(0, -7.5, -1.7))
		mark(belly, "67", c:Lerp(BLACK, 0.3), FRONT_FACE, 0.5, 0.5, 0.6)
		-- the tail, and a fiery tip
		local tail = { { 3.0, V(0, -9.3, 5.0) }, { 2.4, V(1.0, -9.8, 7.6) }, { 1.8, V(2.4, -10.0, 9.6) } }
		for i, t in tail do
			local p = ball(b, "Tail", t[1], c, t[2])
			anim(b, p, "Sway", 0.05, 2.5, i * 0.4)
		end
		local tip = ball(b, "TailFire", 1.4, rgb(251, 146, 60), V(3.6, -9.8, 11.2), NEON)
		anim(b, tip, "Pulse", 1, 6)
		for i = 0, 2 do
			spike(b, "Spike", V(0.4, 1.3, 1.2), horn, V(0, -3.6 - i * 2.2, 4.6 + i * 0.2), 0)
		end
		return 11.5
	end

	--------------------------------------------------------------------------------- VI OBLIVION · Cyber
	-- Pixel Bit: eight neon cubes (2 x 2 x 2) around an invisible root; a pixel face on the front
	function STYLES.PixelBit(b, c: Color3, a: Color3): number
		local root = box(b, "Root", V(1.5, 1.5, 1.5), BLACK, CF())
		root.Transparency = 1
		local lime = rgb(163, 230, 53)
		local colors = { c, a, lime, c, a, lime, c, a }
		local k = 0
		for x = -1, 1, 2 do
			for y = -1, 1, 2 do
				for z = -1, 1, 2 do
					k += 1
					local cube = box(b, "Pixel", V(0.8, 0.8, 0.8), colors[k], CF(x * 0.42, y * 0.42, z * 0.42), NEON)
					anim(b, cube, "Jitter", 0.1, 10, k)
					if z < 0 and y > 0 then
						-- the face: a black square "eye" on each upper front cube
						local gui = Instance.new("SurfaceGui")
						gui.Face = Enum.NormalId.Front
						gui.LightInfluence = 0
						gui.CanvasSize = Vector2.new(100, 100)
						gui.Parent = cube
						local f = Instance.new("Frame")
						f.AnchorPoint = Vector2.new(0.5, 0.5)
						f.Position = UDim2.fromScale(0.5 - x * 0.12, 0.55)
						f.Size = UDim2.fromScale(0.42, 0.42)
						f.BackgroundColor3 = BLACK
						f.BorderSizePixel = 0
						f.Parent = gui
					end
				end
			end
		end
		return 1.2
	end

	-- Drone Pod: a white ball with one big blue eye, two propellers and a red-ball antenna
	function STYLES.DronePod(b, c: Color3, a: Color3): number
		ball(b, "Body", 2.2, c, Vector3.zero)
		ball(b, "Eye", V(1.15, 1.15, 0.6), a, V(0, 0.08, -0.85), NEON)
		ball(b, "Shine", 0.28, WHITE, V(0.22, 0.32, -1.15))
		for _, side in { -1, 1 } do
			cyl(b, "Arm", 0.9, 0.2, c:Lerp(BLACK, 0.3), CF(side * 1.4, 0.4, 0))
			local prop = disc(b, "Prop", 1.5, 0.1, c:Lerp(BLACK, 0.45), V(side * 1.9, 0.55, 0))
			prop.Transparency = 0.3
			anim(b, prop, "Spin", 1, 25)
		end
		cyl(b, "Antenna", 0.9, 0.1, c:Lerp(BLACK, 0.3), CF(0, 1.5, 0.2) * ANG(0, 0, math.pi / 2))
		ball(b, "Tip", 0.35, rgb(255, 60, 60), V(0, 2.0, 0.2), NEON)
		return 3.0
	end

	-- Firewall Bot: a monitor head (a smiley that turns angry when its shield breaks), a block
	-- body with a red-orange stripe, block arms, a holographic shield on a chain in front
	function STYLES.FirewallBot(b, c: Color3, a: Color3): number
		box(b, "Monitor", V(3.6, 2.8, 1.6), c, CF())
		box(b, "Screen", V(3.0, 2.2, 0.12), rgb(15, 30, 40), CF(0, 0, -0.82))
		for _, side in { -1, 1 } do
			box(b, "Eye", V(0.4, 0.5, 0.1), a, CF(side * 0.65, 0.35, -0.9), NEON)
			tag(box(b, "Cheek", V(0.35, 0.3, 0.1), a, CF(side * 0.7, -0.35, -0.9), NEON), "HideIn", 8) -- the smile's corners
			tag(box(b, "Brow", V(0.6, 0.18, 0.1), rgb(255, 80, 90), CF(side * 0.6, 0.8, -0.9) * ANG(0, 0, side * 0.45), NEON), "ShowIn", 8)
			box(b, "Arm", V(0.8, 1.8, 0.8), c:Lerp(WHITE, 0.15), CF(side * 1.9, -2.5, -0.2))
		end
		tag(box(b, "Smile", V(1.0, 0.25, 0.1), a, CF(0, -0.5, -0.9), NEON), "HideIn", 8)
		tag(box(b, "Frown", V(1.2, 0.2, 0.1), rgb(255, 80, 90), CF(0, -0.45, -0.9), NEON), "ShowIn", 8)
		box(b, "Body", V(2.8, 2.2, 1.8), c:Lerp(WHITE, 0.1), CF(0, -2.6, 0.1))
		box(b, "Stripe", V(2.9, 0.35, 1.9), rgb(249, 115, 22), CF(0, -2.3, 0.1))
		-- the holo shield on its chain (it breaks: Broken = 8)
		tag(box(b, "Chain", V(0.15, 0.15, 1.6), rgb(150, 160, 180), CF(0, -1.6, -1.6)), "HideIn", 8)
		local shield = tag(box(b, "Holo", V(4.0, 2.6, 0.3), rgb(56, 189, 248), CF(0, -2.0, -2.6), NEON), "HideIn", 8)
		shield.Transparency = 0.5
		return 3.9
	end

	-- OVERCLOCK-6: a giant robot with a square screen face, spinning ring antennas, a neon 6 on
	-- its chest, a floating diamond core (green: the real one)
	function STYLES.Overclock6(b, c: Color3, a: Color3): number
		box(b, "Head", V(11, 9, 8), c, CF())
		box(b, "Screen", V(9.2, 7, 0.3), rgb(10, 20, 30), CF(0, 0, -4.05))
		local red = rgb(255, 70, 80)
		for _, side in { -1, 1 } do
			tag(box(b, "Eye", V(1.6, 1.9, 0.2), a, CF(side * 2.2, 1.0, -4.25), NEON), "PhaseHide", 2)
			tag(box(b, "EyeRed", V(1.9, 1.1, 0.2), red, CF(side * 2.2, 0.9, -4.25) * ANG(0, 0, side * 0.3), NEON), "Phase", 2)
			local ring = cyl(b, "Ring", 0.5, 4.2, a, CF(side * 6.0, 1.0, 0), NEON)
			anim(b, ring, "Spin", 1, 3 * side)
			cyl(b, "RingHub", 0.6, 2.6, c:Lerp(BLACK, 0.3), CF(side * 6.0, 1.0, 0))
			box(b, "Pad", V(2.6, 1.6, 3.4), c:Lerp(WHITE, 0.12), CF(side * 5.0, -5.4, 0.5))
			ball(b, "Hand", 2.6, c:Lerp(WHITE, 0.2), V(side * 5.4, -8.6, -1.2))
			cyl(b, "Leg", 3.2, 2.4, c:Lerp(BLACK, 0.2), CF(side * 2.0, -12.4, 0.5) * ANG(0, 0, math.pi / 2))
			box(b, "Foot", V(3.0, 1.0, 3.6), c, CF(side * 2.0, -14.1, -0.1))
		end
		box(b, "Mouth", V(3.4, 0.5, 0.2), a, CF(0, -1.9, -4.25), NEON)
		local torso = box(b, "Torso", V(8, 6, 6), c:Lerp(WHITE, 0.06), CF(0, -8.0, 0.5))
		mark(torso, "6", a, FRONT_FACE, 0.5, 0.5, 0.75)
		-- the floating core (Core: OVERCLOCK-6's holograms turn it red)
		for i = 0, 1 do
			local core = box(b, "Core", V(2.0 - i * 0.8, 2.0 - i * 0.8, 2.0 - i * 0.8), rgb(74, 222, 128), CF(0, 7.8, 0) * CFrame.Angles(math.pi / 4, 0, math.pi / 4), NEON)
			anim(b, core, "Spin", 1, 2 + i)
		end
		return 14.6
	end

	-- OVERCLOCK-6's hologram: the same robot, see-through, with a red core
	function STYLES.OverclockHolo(b, c: Color3, a: Color3): number
		local h = STYLES.Overclock6(b, c, a)
		for _, p in b.Parts do
			p.Transparency = math.max(p.Transparency, 0.55)
			if p.Name == "Core" then
				p.Color = rgb(255, 70, 80)
			elseif p.Material ~= NEON then
				p.Color = p.Color:Lerp(rgb(150, 220, 255), 0.5)
			end
		end
		return h
	end

	--------------------------------------------------------------------------------- VII THE 67 · Void
	-- Voidling: a black ball with a faint purple halo, glowing purple eyes, little horns and three
	-- tiny tentacles (no arms or legs: that is how you tell it from the hero THE VOID)
	function STYLES.Voidling(b, c: Color3, a: Color3): number
		ball(b, "Body", 2.4, c, Vector3.zero)
		local halo = ball(b, "Halo", 2.9, a, Vector3.zero, NEON)
		halo.Transparency = 0.75
		anim(b, halo, "Pulse", 1, 3)
		glowEyes(b, V(0.5, 0.75, 0.25), 0.42, 0.2, -1.05, a)
		for _, side in { -1, 1 } do
			spike(b, "Horn", V(0.2, 0.55, 0.35), c:Lerp(a, 0.3), V(side * 0.6, 1.15, 0), -side * 0.3)
		end
		for i = 0, 2 do
			local ang = i * TAU / 3 + math.pi / 2
			local t = ball(b, "Tentacle", 0.55, c:Lerp(a, 0.2), V(math.cos(ang) * 0.6, -1.3, math.sin(ang) * 0.6))
			anim(b, t, "Bob", 0.25, 6, i * 2)
		end
		return 2.4
	end

	-- Star Eater: a black planet with one big eye, a tilted purple orbit ring and three moons
	function STYLES.StarEater(b, c: Color3, a: Color3): number
		ball(b, "Body", 3.2, c, Vector3.zero)
		local ring = cyl(b, "Orbit", 0.12, 5.4, a, ANG(0, 0, math.pi / 2 + 0.35), NEON)
		ring.Transparency = 0.35
		anim(b, ring, "Spin", 1, 1.2)
		for i, col in { rgb(253, 224, 71), rgb(125, 211, 252), rgb(244, 114, 182) } do
			local ang = i * TAU / 3
			local moon = ball(b, "Moon", 0.75, col, V(math.cos(ang) * 3.0, 0.4 * (i - 2), math.sin(ang) * 3.0))
			anim(b, moon, "Orbit", 1, 1.0 + i * 0.45, ang)
		end
		ball(b, "Eye", V(1.7, 1.7, 0.6), WHITE, V(0, 0.15, -1.42))
		ball(b, "Pupil", 0.8, BLACK, V(0, 0.1, -1.7))
		ball(b, "Shine", 0.26, WHITE, V(0.25, 0.4, -1.84))
		return 2.8
	end

	-- Eclipse Knight: dark purple armour, a round helmet with a golden visor slit, a big golden
	-- halo ring behind the head (an eclipse), a round "7" shield, a spear, a short cape
	function STYLES.EclipseKnight(b, c: Color3, a: Color3): number
		ball(b, "Armour", V(2.6, 3.0, 2.2), c, Vector3.zero)
		ball(b, "Helmet", 2.4, c:Lerp(BLACK, 0.2), V(0, 2.4, 0))
		box(b, "Visor", V(1.6, 0.25, 0.12), a, CF(0, 2.45, -1.18), NEON)
		local halo = cyl(b, "Halo", 0.2, 4.4, a, CF(0, 2.8, 1.4) * FRONT, NEON)
		anim(b, halo, "Pulse", 1, 1.5)
		cyl(b, "Eclipse", 0.25, 3.4, rgb(10, 6, 20), CF(0, 2.8, 1.25) * FRONT)
		for _, side in { -1, 1 } do
			ball(b, "Pauldron", 1.2, c:Lerp(WHITE, 0.1), V(side * 1.45, 1.1, 0))
			ball(b, "Foot", V(0.9, 0.7, 1.2), c:Lerp(BLACK, 0.3), V(side * 0.6, -1.75, -0.1))
		end
		local shield = cyl(b, "Shield", 0.3, 2.2, c:Lerp(WHITE, 0.1), CF(1.35, -0.2, -1.25) * FRONT)
		mark(shield, "7", a, Enum.NormalId.Right, 0.5, 0.5, 0.7)
		cyl(b, "Spear", 4.4, 0.18, rgb(200, 190, 160), CF(-1.4, 0.2, -0.8) * ANG(0, math.pi / 2, 0) * ANG(0, 0, 0.15))
		spike(b, "SpearTip", V(0.18, 0.4, 0.9), a, V(-1.4, 0.55, -3.1), 0, false, NEON)
		for i = -1, 1 do
			local cape = wedge(b, "Cape", V(0.9, 2.6, 0.7), c:Lerp(BLACK, 0.35), CF(i * 0.8, -0.3, 1.2) * ANG(math.pi, 0, 0))
			anim(b, cape, "Sway", 0.2, 3.5, i)
		end
		return 2.1
	end

	-- THE 67: two giant floating digits (a 6 and a 7: neon outline, dark body) around a crowned
	-- void face with huge eyes; in phase 3 a golden bar fuses them into "67"
	function STYLES.Final67(b, c: Color3, a: Color3): number
		ball(b, "Face", 9, c, Vector3.zero)
		local halo = ball(b, "Halo", 10.2, a, Vector3.zero, NEON)
		halo.Transparency = 0.8
		anim(b, halo, "Pulse", 1, 1.4)
		cartoonEyes(b, 2.8, 2.0, 0.9, -3.75)
		box(b, "Smile", V(3.0, 0.45, 0.3), a, CF(0, -2.2, -4.3), NEON)
		for _, side in { -1, 1 } do
			tag(box(b, "Brow", V(2.2, 0.5, 0.4), a, CF(side * 2.0, 3.0, -3.9) * ANG(0, 0, side * 0.4), NEON), "Phase", 3)
		end
		-- the crown
		disc(b, "Crown", 5.0, 1.0, GOLD, V(0, 5.0, 0))
		for i = 0, 3 do
			local ang = i * TAU / 4 + math.pi / 4
			spike(b, "CrownTip", V(0.5, 1.5, 1.0), GOLD, V(math.cos(ang) * 1.9, 6.1, math.sin(ang) * 1.9), 0)
		end
		-- the 6: at +X (your left when it faces you): a thick ring and an arc rising from it
		local six, seven = 11.5, -11.5
		local dark = c:Lerp(rgb(60, 40, 110), 0.35)
		local sixParts = {
			cyl(b, "SixGlow", 1.2, 9.4, a, CF(six, -3.0, 0.5) * FRONT, NEON),
			cyl(b, "Six", 2.4, 8.2, dark, CF(six, -3.0, 0.2) * FRONT),
			cyl(b, "SixHole", 2.6, 3.4, c, CF(six, -3.0, 0.2) * FRONT),
			box(b, "SixArc", V(2.4, 4.6, 2.4), dark, CF(six + 3.0, 2.2, 0.2) * ANG(0, 0, 0.12)),
			box(b, "SixArc", V(2.4, 3.6, 2.4), dark, CF(six + 2.4, 5.8, 0.2) * ANG(0, 0, -0.35)),
			box(b, "SixArc", V(2.4, 3.2, 2.4), dark, CF(six + 0.6, 8.2, 0.2) * ANG(0, 0, -0.95)),
			box(b, "SixArcGlow", V(0.6, 11, 0.6), a, CF(six + 3.3, 3.8, -1.1) * ANG(0, 0, 0.05), NEON),
		}
		for _, p in sixParts do
			anim(b, p, "Bob", 0.9, 1.1, 0)
		end
		-- the 7: a bar and a diagonal of three blocks
		local sevenParts = {
			box(b, "SevenBar", V(8.4, 2.4, 2.4), dark, CF(seven, 7.2, 0.2)),
			box(b, "SevenBarGlow", V(8.8, 0.6, 0.6), a, CF(seven, 8.4, -1.1), NEON),
			box(b, "SevenDiag", V(2.4, 4.4, 2.4), dark, CF(seven - 2.6, 3.6, 0.2) * ANG(0, 0, -0.45)),
			box(b, "SevenDiag", V(2.4, 4.4, 2.4), dark, CF(seven - 1.0, -0.2, 0.2) * ANG(0, 0, -0.45)),
			box(b, "SevenDiag", V(2.4, 4.4, 2.4), dark, CF(seven + 0.6, -4.0, 0.2) * ANG(0, 0, -0.45)),
			box(b, "SevenDiagGlow", V(0.6, 12.5, 0.6), a, CF(seven - 1.0, -0.2, -1.1) * ANG(0, 0, -0.45), NEON),
		}
		for _, p in sevenParts do
			anim(b, p, "Bob", 0.9, 1.1, 1.7)
		end
		-- phase 3: fused (golden bars join the digits to the face)
		for _, side in { -1, 1 } do
			tag(box(b, "Fuse", V(7.0, 1.6, 1.6), GOLD, CF(side * 7.2, 0, 0.3), NEON), "Phase", 3)
		end
		return 12
	end
end

return BestiaryModels
