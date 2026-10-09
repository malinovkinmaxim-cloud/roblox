--[[
	PremiumFx - the looks of the 7 PREMIUM abilities in a run (what they do: server
	Sim/PremiumAbilities.lua). Controllers/WeaponFx calls in here for their Kinds, so they use
	its pools, transients, ABILITY SKINS and the one effect style (shared/AbilityConfig.lua):
	Neon primitives, thick lines, few particles; appear with Back, fade with Quad / Sine.
	Premium effects are the most spectacular in the game: their own colour (shared/WeaponData
	Color) with the Mythic colours running through an accent.

	  Solar       a thick golden pillar from the sky, a ring on the ground, a fiery "6 7" over it;
	              the 7th pulse: a big golden blast (max level: two pillars at once)
	  HolePet     a black sphere with a turning purple ring, sparks sucked in; follows the
	              positions the server sends (Fx variant 1); max level: it implodes (variant 2)
	  GoldMeteor  golden comet balls with a tail, a golden flash where they land
	  Bubble      a see-through blue dome on you with ticking clock rings inside; variant 2 = the
	              max-level TIME STOP
	  Phoenix     a chibi phoenix (round orange body, wedge wings that flap, a flame tail) that
	              circles you (the server's formula); fireballs; variant 2 = its REBIRTH
	  Storm       thick electric-blue lightning with a little jitter and a flash at every link
	  Crown       a golden ring round you with floating 6s and 7s (the server's formula),
	              three rings at max level
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local AbilityConfig = require(Shared.AbilityConfig)
local WeaponData = require(Shared.WeaponData)

local PremiumFx = {}

local rgb = Color3.fromRGB
local TAU = math.pi * 2
local FLAT = CFrame.Angles(0, 0, math.rad(90))
local PARK = CFrame.new(0, -400, 0)
local WHITE = rgb(255, 255, 255)
local GOLD = rgb(255, 205, 60)
local FIRE = rgb(255, 120, 40)

-- the server's formulas (Sim/PremiumAbilities.lua): keep them the same
local PHOENIX_R, PHOENIX_SPIN = 3.2, 1.7
local CROWN_GAP = 3

PremiumFx.Kinds = { Solar = true, HolePet = true, GoldMeteor = true, Bubble = true, Phoenix = true, Storm = true, Crown = true }
local ALWAYS = { HolePet = true, Phoenix = true, Crown = true } -- drawn from the loadout every frame

local function ease(t: number, kind: string): number
	local e = AbilityConfig.Ease[kind]
	return TweenService:GetValue(math.clamp(t, 0, 1), e.Style, e.Direction)
end

local function newPart(name: string, size: Vector3, color: Color3, shape: Enum.PartType?, className: string?): BasePart
	local p = Instance.new(className or "Part") :: BasePart
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if shape then
		(p :: Part).Shape = shape
	end
	p.CFrame = PARK
	return p
end

local function trail(p: BasePart, color: Color3, width: number, life: number)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, width / 2, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -width / 2, 0)
	a1.Parent = p
	local t = Instance.new("Trail")
	t.Name = "Trail"
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = life
	t.Color = ColorSequence.new(color, FIRE)
	t.Transparency = NumberSequence.new(0.1, 1)
	t.LightEmission = 0.8
	t.FaceCamera = true
	t.Parent = p
end

-- a floating "6" / "7" (a BillboardGui on a small invisible part)
local function digitTag(text: string, size: number): BasePart
	local p = newPart("Digit", Vector3.new(0.2, 0.2, 0.2), GOLD)
	p.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromScale(size, size)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.TextStrokeColor3 = rgb(120, 60, 0)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	return p
end

-- part builders WeaponFx pools by style (WeaponFx.Styles)
PremiumFx.Styles = {
	Fireball = function()
		local p = newPart("Fireball", Vector3.new(1.4, 1.4, 1.4), FIRE, Enum.PartType.Ball)
		trail(p, rgb(255, 220, 90), 1.1, 0.25)
		return p
	end,
	Comet = function()
		local p = newPart("Comet", Vector3.new(2.4, 2.4, 2.4), GOLD, Enum.PartType.Ball)
		trail(p, rgb(255, 240, 160), 2, 0.35)
		return p
	end,
	Pillar = function()
		return newPart("Pillar", Vector3.new(40, 3, 3), GOLD, Enum.PartType.Cylinder)
	end,
}

-- the colour of a premium ability: an ABILITY SKIN if one is on, else its own colour
local function colorOf(wfx, def): Color3
	return wfx:ColorOf(def)
end

-- the Mythic accent (pink -> cyan -> gold running through)
local function accent(def, clock: number): Color3
	return AbilityConfig.MythicAt(clock, def.Id or 0)
end

function PremiumFx.Init(wfx)
	wfx.Premium = { Always = {}, Bubble = nil, PetAt = {} }
end

---------------------------------------------------------------------------
-- always-on models (pets, the crown) from the loadout
---------------------------------------------------------------------------
local function release(model)
	for _, p in model.Parts do
		p:Destroy()
	end
end

local function buildHolePet(wfx, folder)
	local parts = {}
	local core = newPart("HoleCore", Vector3.new(2.6, 2.6, 2.6), rgb(10, 6, 20), Enum.PartType.Ball)
	core.Material = Enum.Material.SmoothPlastic
	local ring = newPart("HoleRing", Vector3.new(0.2, 4.6, 4.6), rgb(150, 80, 255), Enum.PartType.Cylinder)
	local ring2 = newPart("HoleRing2", Vector3.new(0.15, 3.6, 3.6), rgb(230, 200, 255), Enum.PartType.Cylinder)
	ring2.Transparency = 0.4
	local area = newPart("HoleArea", Vector3.new(0.1, 1, 1), rgb(150, 80, 255), Enum.PartType.Cylinder)
	area.Transparency = wfx:Fade(0.85)
	parts = { core, ring, ring2, area }
	local sparks = {}
	for i = 1, 6 do
		local s = newPart("Spark", Vector3.new(0.35, 0.35, 0.35), rgb(230, 200, 255), Enum.PartType.Ball)
		table.insert(parts, s)
		sparks[i] = s
	end
	for _, p in parts do
		p.Parent = folder
	end
	return { Parts = parts, Core = core, Ring = ring, Ring2 = ring2, Area = area, Sparks = sparks }
end

local function buildPhoenix(_wfx, folder)
	local body = newPart("Body", Vector3.new(1.6, 1.6, 1.6), rgb(255, 130, 40), Enum.PartType.Ball)
	body.Material = Enum.Material.SmoothPlastic
	local head = newPart("Head", Vector3.new(1.15, 1.15, 1.15), rgb(255, 170, 70), Enum.PartType.Ball)
	head.Material = Enum.Material.SmoothPlastic
	local beak = newPart("Beak", Vector3.new(0.35, 0.35, 0.35), rgb(255, 225, 80), Enum.PartType.Ball)
	local eyeL = newPart("Eye", Vector3.new(0.22, 0.22, 0.22), rgb(24, 22, 30), Enum.PartType.Ball)
	local eyeR = newPart("Eye", Vector3.new(0.22, 0.22, 0.22), rgb(24, 22, 30), Enum.PartType.Ball)
	eyeL.Material, eyeR.Material = Enum.Material.SmoothPlastic, Enum.Material.SmoothPlastic
	local wingL = newPart("Wing", Vector3.new(0.25, 0.9, 1.8), rgb(255, 80, 40), nil, "WedgePart")
	local wingR = newPart("Wing", Vector3.new(0.25, 0.9, 1.8), rgb(255, 80, 40), nil, "WedgePart")
	local flames = {}
	local parts = { body, head, beak, eyeL, eyeR, wingL, wingR }
	for i = 1, 3 do
		local f = newPart("Flame", Vector3.one * (0.8 - i * 0.15), rgb(255, 220 - i * 45, 60), Enum.PartType.Ball)
		flames[i] = f
		table.insert(parts, f)
	end
	trail(flames[1], rgb(255, 200, 60), 0.6, 0.25)
	for _, p in parts do
		p.Parent = folder
	end
	return { Parts = parts, Body = body, Head = head, Beak = beak, Eyes = { eyeL, eyeR }, Wings = { wingL, wingR }, Flames = flames }
end

local function buildCrown(_wfx, folder, spec)
	local parts, rings, digits = {}, {}, {}
	local count = math.max(1, spec.Rings or 1)
	local n = math.max(1, spec.Amount or 2)
	for k = 1, count do
		local ring = newPart("CrownRing", Vector3.new(0.12, 1, 1), GOLD, Enum.PartType.Cylinder)
		ring.Transparency = 0.45
		rings[k] = ring
		table.insert(parts, ring)
		digits[k] = {}
		for i = 1, n do
			local d = digitTag(if i % 2 == 1 then "6" else "7", 3.2 + (spec.Radius or 2.4) * 0.6)
			local glow = newPart("CrownGlow", Vector3.one, GOLD, Enum.PartType.Ball)
			glow.Transparency = 0.55
			digits[k][i] = { Tag = d, Glow = glow }
			table.insert(parts, d)
			table.insert(parts, glow)
		end
	end
	for _, p in parts do
		p.Parent = folder
	end
	return { Parts = parts, Rings = rings, Digits = digits, Count = count, N = n }
end

function PremiumFx.SetLoadout(wfx, loadout)
	local state = wfx.Premium
	local keep = {}
	for _, w in loadout.Weapons or {} do
		local def = WeaponData.ByKey[w.Key]
		if def and ALWAYS[def.Kind] then
			keep[w.Key] = true
			local m = state.Always[w.Key]
			-- the crown is rebuilt when its digits / rings change
			if m and def.Kind == "Crown" and (m.Count ~= math.max(1, w.Rings or 1) or m.N ~= math.max(1, w.Amount or 2)) then
				release(m)
				m = nil
			end
			if not m then
				if def.Kind == "HolePet" then
					m = buildHolePet(wfx, wfx.Folder)
				elseif def.Kind == "Phoenix" then
					m = buildPhoenix(wfx, wfx.Folder)
				else
					m = buildCrown(wfx, wfx.Folder, w)
				end
				m.Kind = def.Kind
				m.Def = def
				state.Always[w.Key] = m
			end
			m.Spec = w
		end
	end
	for key, m in state.Always do
		if not keep[key] then
			release(m)
			state.Always[key] = nil
			state.PetAt[key] = nil
		end
	end
end

---------------------------------------------------------------------------
-- Fx records
---------------------------------------------------------------------------
function PremiumFx.Fx(wfx, def, x: number, z: number, angle: number, p1: number, p2: number, variant: number)
	local run = wfx.C.RunClient
	local fx = wfx.C.EffectsController
	local sound = wfx.C.SoundController
	local cam = wfx.C.CameraController
	local pos = run:World(x, z, 0)
	local color = colorOf(wfx, def)
	local kind = def.Kind
	local clock = os.clock()
	if kind == "Solar" then
		if p2 >= 7 then
			-- the 7th: a golden blast
			fx:Ring(pos, p1, color, 0.45, 1)
			fx:Ring(pos, p1 * 0.6, accent(def, clock), 0.35)
			fx:Emit("Big", pos + Vector3.new(0, 2, 0), color, 12)
			fx:WorldText(pos + Vector3.new(0, 8, 0), "67", rgb(255, 150, 40), 3, 0.9)
			cam:Shake(0.6)
			if not sound:PlayAbility(def.Key, "Hit") then
				sound:Play("Boom", 1.1, 0.6)
			end
			return
		end
		-- a pulse: the pillar slams down, a ring on the ground
		local pillar = wfx:Take("Pillar")
		local w = math.max(AbilityConfig.MinLineWidth, p1) * (if variant >= 2 then 0.9 else 1)
		pillar.Color = color
		wfx:Transient(0.2, function(t)
			local grow = if t < 0.35 then ease(t / 0.35, "In") else 1
			local width = w * grow
			pillar.Size = Vector3.new(40, width, width)
			pillar.CFrame = CFrame.new(pos + Vector3.new(0, 20, 0)) * FLAT
			pillar.Transparency = if t < 0.35 then 0.05 else ease((t - 0.35) / 0.65, "Out")
		end, function()
			wfx:Give("Pillar", pillar)
		end)
		fx:Ring(pos, p1 * 1.3, accent(def, clock), 0.22)
		if p2 == 1 then
			-- a fiery 6 and 7 hang over the first pulse
			fx:WorldText(pos + Vector3.new(-2, 7, 0), "6", FIRE, 2.4, 0.9)
			fx:WorldText(pos + Vector3.new(2, 8, 0), "7", FIRE, 2.4, 0.9)
			if not sound:PlayAbility(def.Key, "Cast") then
				sound:Play("Beam", 1.2, 0.6)
			end
		end
	elseif kind == "HolePet" then
		if variant == 1 then
			-- a position report: the pet glides there
			wfx.Premium.PetAt[def.Key] = { X = x, Z = z, R = p1 }
		elseif variant == 2 then
			fx:Ring(pos, p1, color, 0.4, p1 * 0.2)
			fx:Ring(pos, p1 * 0.5, rgb(230, 200, 255), 0.3)
			fx:Emit("Big", pos + Vector3.new(0, 2, 0), color, 10)
			cam:Shake(0.5)
			if not sound:PlayAbility(def.Key, "Hit") then
				sound:Play("Boom", 0.8, 0.6)
			end
		end
	elseif kind == "GoldMeteor" then
		if variant == 2 then
			-- a MOTHERLODE shard lands
			fx:Ring(pos, p1, color, 0.3)
			fx:HitFlash(pos + Vector3.new(0, 1, 0), color)
			return
		end
		local p = wfx:Take("Comet")
		local ground = pos
		local fall = math.max(0.15, p2)
		local shadow = wfx:Take("Disc")
		shadow.Color = rgb(60, 40, 0)
		p.Color = color
		wfx:Transient(fall, function(t)
			local y = (1 - t * t) * 45 + 1.2
			p.CFrame = CFrame.new(ground + Vector3.new((1 - t) * 10, y, (1 - t) * 4))
			local grow = ease(t, "Soft")
			shadow.Size = Vector3.new(0.12, p1 * 2 * grow, p1 * 2 * grow)
			shadow.CFrame = CFrame.new(ground + Vector3.new(0, 0.3, 0)) * FLAT
			shadow.Transparency = 1 - t * 0.5
		end, function()
			wfx:Give("Comet", p)
			wfx:Give("Disc", shadow)
			fx:Ring(ground, p1, color, 0.35, 0.5)
			fx:Emit("Big", ground + Vector3.new(0, 1, 0), color, 8)
			fx:HitFlash(ground + Vector3.new(0, 1.5, 0), WHITE)
			cam:Shake(0.3)
			if not sound:PlayAbility(def.Key, "Hit") then
				sound:Play("Coin", 0.9, 0.5)
			end
		end)
		if not sound:PlayAbility(def.Key, "Cast") then
			sound:Play("Whoosh", 1.2, 0.3)
		end
	elseif kind == "Bubble" then
		if variant == 2 then
			fx:Flash(rgb(170, 220, 255), 0.35)
			fx:Ring(pos, p1, WHITE, 0.5)
			fx:WorldText(pos + Vector3.new(0, 7, 0), "TIME STOP", rgb(200, 235, 255), 2.2, 1)
			return
		end
		PremiumFx.Bubble(wfx, def, p1, p2)
		if not sound:PlayAbility(def.Key, "Cast") then
			sound:Play("Freeze", 1.2, 0.5)
		end
	elseif kind == "Phoenix" then
		if variant == 2 then
			-- REBIRTH
			local px, pz = wfx:PlayerXZ(x, z)
			local here = run:World(px, pz, 0)
			fx:Ring(here, p1, FIRE, 0.6, 1)
			fx:Ring(here, p1 * 0.6, GOLD, 0.5)
			fx:Emit("Big", here + Vector3.new(0, 2, 0), FIRE, 12)
			fx:WorldText(here + Vector3.new(0, 8, 0), "REBIRTH", GOLD, 2.6, 1.2)
			fx:Flash(rgb(255, 160, 60), 0.4)
			cam:ZoomPunch(1, 0.4)
		end
	elseif kind == "Storm" then
		-- one link: thick electric lightning with jitter, a flash where it lands
		local from = pos + Vector3.new(math.cos(angle) * p2, 2, math.sin(angle) * p2)
		local to = pos + Vector3.new(0, 2, 0)
		local thick = math.max(AbilityConfig.MinLineWidth, 1.1 - p1 * 0.04)
		wfx:Bolt(from, to, color, thick, 0.22)
		wfx:Bolt(from, to, WHITE, thick * 0.4, 0.12)
		fx:HitFlash(to, WHITE)
		if p1 == 1 then
			if not sound:PlayAbility(def.Key, "Cast") then
				sound:Play("Zap", 1, 0.6)
			end
		end
	end
end

---------------------------------------------------------------------------
-- the TIME BUBBLE: a dome that follows you while it lasts
---------------------------------------------------------------------------
function PremiumFx.Bubble(wfx, def, radius: number, duration: number)
	local state = wfx.Premium
	if state.Bubble then
		state.Bubble.Until = os.clock() + duration
		return
	end
	local color = colorOf(wfx, def)
	local dome = newPart("TimeDome", Vector3.one, color, Enum.PartType.Ball)
	dome.Material = Enum.Material.ForceField
	local inner = newPart("TimeDomeInner", Vector3.one, color, Enum.PartType.Ball)
	inner.Material = Enum.Material.Glass
	local rings, hands = {}, {}
	for i = 1, 2 do
		local r = newPart("ClockRing", Vector3.new(0.15, 1, 1), WHITE, Enum.PartType.Cylinder)
		r.Transparency = 0.35
		rings[i] = r
	end
	for i = 1, 2 do
		hands[i] = newPart("ClockHand", Vector3.new(0.3, 0.3, 1), WHITE)
	end
	local parts = { dome, inner, rings[1], rings[2], hands[1], hands[2] }
	for _, p in parts do
		p.Parent = wfx.Folder
	end
	state.Bubble = { Parts = parts, Dome = dome, Inner = inner, Rings = rings, Hands = hands, R = radius, Born = os.clock(), Until = os.clock() + duration, Def = def }
end

local function stepBubble(wfx, b, clock: number, base: Vector3)
	local born = math.clamp((clock - b.Born) / 0.25, 0, 1)
	local left = b.Until - clock
	if left <= -0.3 then
		release(b)
		wfx.Premium.Bubble = nil
		return
	end
	local fade = if left < 0 then ease(-left / 0.3, "Out") else 0
	local r = b.R * ease(born, "In")
	local color = colorOf(wfx, b.Def)
	b.Dome.Size = Vector3.one * r * 2
	b.Dome.CFrame = CFrame.new(base)
	b.Dome.Color = color
	b.Dome.Transparency = 0.3 + 0.7 * fade
	b.Inner.Size = Vector3.one * r * 1.98
	b.Inner.CFrame = CFrame.new(base)
	b.Inner.Color = color
	b.Inner.Transparency = wfx:Fade(0.86) + 0.14 * fade
	-- clock rings turn slowly, the hands tick twice a second
	for i, ring in b.Rings do
		local rr = r * (if i == 1 then 0.7 else 0.45)
		ring.Size = Vector3.new(0.15, rr * 2, rr * 2)
		ring.CFrame = CFrame.new(base + Vector3.new(0, 0.4 + i * 0.3, 0)) * CFrame.Angles(0, clock * (if i == 1 then 0.6 else -0.9), 0) * FLAT
		ring.Transparency = 0.35 + 0.65 * fade
		ring.Color = if i == 2 then accent(b.Def, clock) else WHITE
	end
	local tick = math.floor(clock * 2)
	for i, hand in b.Hands do
		local len = r * (if i == 1 then 0.6 else 0.4)
		local a = tick * TAU / (if i == 1 then 12 else 60) * (if i == 1 then 1 else 5)
		hand.Size = Vector3.new(0.3, 0.3, len)
		hand.CFrame = CFrame.new(base + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0, -len / 2)
		hand.Transparency = fade
	end
end

---------------------------------------------------------------------------
-- every frame
---------------------------------------------------------------------------
function PremiumFx.Update(wfx, dt: number, now: number, clock: number, px: number, pz: number, center: Vector3, ground: number, hasRoot: boolean)
	local state = wfx.Premium
	if state.Bubble then
		stepBubble(wfx, state.Bubble, clock, Vector3.new(center.X + px, ground + 0.5, center.Z + pz))
	end
	if not hasRoot then
		return
	end
	for key, m in state.Always do
		local spec = m.Spec
		local color = colorOf(wfx, m.Def)
		if m.Kind == "HolePet" then
			local at = state.PetAt[key]
			local tx, tz = if at then at.X else px, if at then at.Z else pz
			m.X = if m.X then m.X + (tx - m.X) * math.min(1, 8 * dt) else tx
			m.Z = if m.Z then m.Z + (tz - m.Z) * math.min(1, 8 * dt) else tz
			local base = Vector3.new(center.X + m.X, ground + 3 + math.sin(clock * 2) * 0.3, center.Z + m.Z)
			m.Core.CFrame = CFrame.new(base)
			m.Ring.CFrame = CFrame.new(base) * CFrame.Angles(0.35, clock * 3, 0) * FLAT
			m.Ring.Color = color
			m.Ring2.CFrame = CFrame.new(base) * CFrame.Angles(-0.5, -clock * 4.5, 0.3) * FLAT
			m.Ring2.Color = accent(m.Def, clock)
			local r = if at then at.R else spec.Radius
			m.Area.Size = Vector3.new(0.1, r * 2, r * 2)
			m.Area.CFrame = CFrame.new(base.X, ground + 0.25, base.Z) * FLAT
			m.Area.Color = color
			-- sparks spiral in
			for i, s in m.Sparks do
				local u = (clock * 0.9 + i / #m.Sparks) % 1
				local a = i * 1.7 + u * 5
				local d = (1 - u) * r
				s.CFrame = CFrame.new(base + Vector3.new(math.cos(a) * d, (1 - u) * 1.5 - 0.5, math.sin(a) * d))
				s.Transparency = u * 0.8
			end
		elseif m.Kind == "Phoenix" then
			local a = now * PHOENIX_SPIN
			local pos = Vector3.new(center.X + px + math.cos(a) * PHOENIX_R, ground + 5.2 + math.sin(clock * 3) * 0.35, center.Z + pz + math.sin(a) * PHOENIX_R)
			local dir = Vector3.new(-math.sin(a), 0, math.cos(a))
			local cf = CFrame.lookAt(pos, pos + dir)
			local dim = if spec.Spent then 0.35 else 0 -- its rebirth is used up
			m.Body.CFrame = cf
			m.Head.CFrame = cf * CFrame.new(0, 0.75, -0.55)
			m.Beak.CFrame = cf * CFrame.new(0, 0.62, -1.15)
			m.Eyes[1].CFrame = cf * CFrame.new(-0.25, 0.9, -1.05)
			m.Eyes[2].CFrame = cf * CFrame.new(0.25, 0.9, -1.05)
			local flap = math.sin(clock * 12) * 0.6
			m.Wings[1].CFrame = cf * CFrame.new(-0.85, 0.2, 0.1) * CFrame.Angles(0, 0, 0.4 + flap) * CFrame.new(-0.5, 0, 0) * CFrame.Angles(0, math.pi, 0)
			m.Wings[2].CFrame = cf * CFrame.new(0.85, 0.2, 0.1) * CFrame.Angles(0, 0, -0.4 - flap) * CFrame.new(0.5, 0, 0) * CFrame.Angles(0, math.pi, 0)
			for i, f in m.Flames do
				f.CFrame = cf * CFrame.new(math.sin(clock * 9 + i) * 0.12, -0.3 - i * 0.25, 0.8 + i * 0.45)
				f.Transparency = dim + (i - 1) * 0.15
			end
			m.Body.Transparency = dim
			m.Wings[1].Color = color:Lerp(FIRE, 0.4)
			m.Wings[2].Color = color:Lerp(FIRE, 0.4)
		elseif m.Kind == "Crown" then
			local n = m.N
			for k = 1, m.Count do
				local dir = if k % 2 == 0 then -1 else 1
				local r = (spec.Orbit or 3.6) + (k - 1) * CROWN_GAP
				local ring = m.Rings[k]
				ring.Size = Vector3.new(0.12, r * 2, r * 2)
				ring.CFrame = CFrame.new(center.X + px, ground + 2.2 + (k - 1) * 0.25, center.Z + pz) * FLAT
				ring.Color = if k == 1 then color else accent(m.Def, clock + k)
				for i = 1, n do
					local a = now * (spec.Speed or 2.6) * dir + (i - 1) * TAU / n + (k - 1) * 0.5
					local at = Vector3.new(center.X + px + math.cos(a) * r, ground + 2.6 + math.sin(clock * 4 + i) * 0.2, center.Z + pz + math.sin(a) * r)
					local d = m.Digits[k][i]
					d.Tag.CFrame = CFrame.new(at)
					local size = (spec.Radius or 2.4) * 0.9
					d.Glow.Size = Vector3.one * size
					d.Glow.CFrame = CFrame.new(at)
					d.Glow.Color = color
				end
			end
		end
	end
end

function PremiumFx.Clear(wfx)
	local state = wfx.Premium
	for key, m in state.Always do
		release(m)
		state.Always[key] = nil
	end
	if state.Bubble then
		release(state.Bubble)
		state.Bubble = nil
	end
	table.clear(state.PetAt)
end

return PremiumFx
