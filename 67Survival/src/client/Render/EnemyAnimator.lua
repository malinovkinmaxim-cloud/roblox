--[[
	EnemyAnimator - procedural enemy animation (no keyframes), run from the ONE enemy loop of
	Controllers/EnemyRenderer (RenderStepped): the server moves the enemy, the client adds the
	life.
	  Pose   the whole model, by its AnimType (shared/EnemyData.lua): Bob (a walking bounce),
	         Hop (hops with squash and stretch), Flap (flies: bob and roll), Roll (rolls along
	         the ground), Float (a slow drift), Spin (turns), Jitter (glitches in place), Boss
	         (breathes). Every enemy has its own phase (a crowd never moves in sync) and leans
	         5-10 degrees into the way it moves.
	  Parts  the moving parts of a model (Render/EnemyModels anim(): a Motor6D whose C0 is
	         offset): wings flap, capes and tails sway, jaws clack, moons orbit, cracks pulse,
	         pixels jitter.
	  Lights the few nearest glowing enemies (a Boo Sheet) light up, never more than MAX_LIGHTS.
	LOD: farther than LOD_DIST studs no part animation (and a plain bob); with more than CROWD
	enemies alive only the bob is left; at most PART_BUDGET models move their parts per frame
	(bosses always).
]]

local EnemyAnimator = {}

local sin, abs, floor, sqrt = math.sin, math.abs, math.floor, math.sqrt
local PI = math.pi
local WHITE = Color3.new(1, 1, 1)

EnemyAnimator.LOD_DIST = 70
EnemyAnimator.CROWD = 120
EnemyAnimator.PART_BUDGET = 60
EnemyAnimator.MAX_LIGHTS = 6

local HOP_EVERY = 0.8 -- (Gloopy's beat: shared/EnemyData.lua Params.HopEvery)

-- the root's mesh (an ellipsoid root squashes and stretches through its mesh scale)
local function rootMesh(info, root: BasePart): SpecialMesh?
	if info.Mesh == nil then
		info.Mesh = root:FindFirstChildOfClass("SpecialMesh") or false
	end
	return info.Mesh or nil
end

-- the pose of the whole model: y offset, pitch, roll, extra yaw (all in studs / radians)
-- e: the client enemy (Phase, RX, RZ); moving: studs moved this frame; simple: bob only
function EnemyAnimator.Pose(e, item, now: number, dt: number, moving: number, simple: boolean): (number, number, number, number)
	local info = item.Info
	local kind = info.AnimType
	local scale = info.Scale
	local ph = e.Phase
	local y, pitch, roll, yaw = 0, 0, 0, 0
	local lean = if moving > 0.02 then -0.12 else 0
	if simple then
		return abs(sin(now * 7 + ph)) * 0.2 * scale, lean, 0, 0
	end
	if kind == "Hop" then
		local u = ((now + ph) % HOP_EVERY) / HOP_EVERY
		local sy
		if u < 0.5 then
			local k = u / 0.5
			y = sin(k * PI) * 0.9 * scale
			sy = 1 + 0.12 * sin(k * PI)
		else
			local k = (u - 0.5) / 0.5
			sy = 0.85 + 0.15 * k
		end
		local mesh = rootMesh(info, item.Root)
		if mesh then
			local sx = 1 / sqrt(sy)
			mesh.Scale = Vector3.new(sx, sy, sx)
		end
		pitch = lean
	elseif kind == "Flap" then
		y = sin(now * 6 + ph) * 0.4 * scale
		roll = sin(now * 3 + ph) * 0.12
		pitch = lean * 1.5
	elseif kind == "Roll" then
		-- rolls: the turn follows the distance it moved
		e.RollA = (e.RollA or 0) + moving / math.max(0.5, info.Height)
		pitch = -e.RollA
	elseif kind == "Float" then
		y = sin(now * 2.2 + ph) * 0.45 * scale
		roll = sin(now * 1.5 + ph) * 0.06
		pitch = lean * 0.6
	elseif kind == "Spin" then
		y = sin(now * 3 + ph) * 0.3 * scale
		yaw = (now * 4 + ph) % (2 * PI)
	elseif kind == "Jitter" then
		y = abs(sin(now * 5 + ph)) * 0.2 * scale
		roll = if floor(now * 10 + ph) % 3 == 0 then 0.08 else 0
	elseif kind == "Boss" then
		-- breathing
		local b = sin(now * 1.6 + ph)
		y = b * 0.25 * scale
		local mesh = rootMesh(info, item.Root)
		if mesh then
			mesh.Scale = Vector3.new(1 + 0.02 * b, 1 + 0.04 * b, 1 + 0.02 * b)
		end
		pitch = lean * 0.4
	else -- Bob
		local s = sin(now * 8 + ph)
		y = abs(s) * 0.3 * scale
		roll = s * 0.07
		pitch = lean
	end
	return y, pitch, roll, yaw
end

-- the moving parts of one model
function EnemyAnimator.Parts(item, now: number)
	local info = item.Info
	local anims = info.Anims
	if not anims then
		return
	end
	local scale = info.Scale
	local speedUp = if (info.PhaseNow or 1) >= 2 then 1.8 else 1 -- a boss in phase 2+ spins faster
	for _, a in anims do
		local t = now * a.Freq + a.Phase
		local kind = a.Kind
		local base: CFrame = a.Base
		if kind == "Flap" then
			local side = if base.Position.X < 0 then -1 else 1
			a.Motor.C0 = CFrame.Angles(0, 0, side * a.Amp * sin(t)) * base
		elseif kind == "Sway" then
			a.Motor.C0 = base * CFrame.Angles(a.Amp * sin(t), 0, 0)
		elseif kind == "Jaw" then
			local open = 0.5 + 0.5 * sin(t)
			a.Motor.C0 = base * CFrame.new(0, -abs(a.Amp) * open * scale, 0) * CFrame.Angles(a.Amp * open, 0, 0)
		elseif kind == "Spin" then
			a.Motor.C0 = base * CFrame.Angles(0, t, 0)
		elseif kind == "Orbit" then
			a.Motor.C0 = CFrame.Angles(0, now * a.Freq * speedUp + a.Phase, 0) * base
		elseif kind == "Bob" then
			a.Motor.C0 = base + Vector3.new(0, a.Amp * sin(t) * scale, 0)
		elseif kind == "Pulse" then
			a.Part.Color = a.Color:Lerp(WHITE, 0.3 * (0.5 + 0.5 * sin(t)))
		elseif kind == "Jitter" then
			if floor(t) ~= a.Tick then
				a.Tick = floor(t)
				local j = a.Amp * scale
				a.Motor.C0 = base + Vector3.new((math.random() - 0.5) * 2 * j, (math.random() - 0.5) * 2 * j, (math.random() - 0.5) * 2 * j)
			end
		end
	end
end

-- the glowing enemies nearest to (px, pz) light up (each glow is a PointLight in the model)
function EnemyAnimator.Lights(list, px: number, pz: number)
	local lit = {}
	for _, e in list do
		local item = e.Item
		local light = item and item.Info.Light
		if light then
			local d = (e.RX - px) ^ 2 + (e.RZ - pz) ^ 2
			table.insert(lit, { Light = light, D = d })
		end
	end
	table.sort(lit, function(a, b)
		return a.D < b.D
	end)
	for i, l in lit do
		local on = i <= EnemyAnimator.MAX_LIGHTS and l.D < 60 * 60
		if l.Light.Enabled ~= on then
			l.Light.Enabled = on
		end
	end
end

return EnemyAnimator
