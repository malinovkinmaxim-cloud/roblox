--[[
	BodyShape - THE core visual joke: height -> stretched body.

	The character is NOT scaled uniformly. Height stretches the body up and makes it thinner:

	  0.01 m   flat "cutlet":   0.8 studs tall, 4 studs wide, big head on top
	  10 m     normal Roblox:   4 studs tall, 2 wide
	  1 K m    lanky:           16 tall, 2.1 wide
	  1 M m    pole:            75 tall, 3.4 wide
	  1 B m    absurd pole:     150 tall, 5 wide, tiny head
	  1e30 m   UNREAL:          600 tall

	Everything is interpolated in log10(metres) between keyframes, so every tap changes the
	shape a bit (early taps a lot). Limits keep the body readable:
	  * aspect ratio (height / width) is capped at 60, so it never becomes an invisible line;
	  * the head grows slowly (1.05 -> 26 studs) so it stays visible from far away, but next to
	    a 150-stud body it is hilariously small.

	Used by the client (BodyController builds the body from these numbers) and by the server
	world builder (clouds / moon are placed at the height a body reaches at that milestone).
]]

local Num = require(script.Parent.Util.Num)

local BodyShape = {}

-- L = log10(metres), B = legs+torso height (studs), A = aspect (B / torso width),
-- H = head size (studs), Leg = legs share of B
local KEYS = {
	{ L = -2, B = 0.8, A = 0.2, H = 1.05, Leg = 0.3 },
	{ L = -1, B = 1.5, A = 0.45, H = 1.1, Leg = 0.36 },
	{ L = 0, B = 2.7, A = 1.1, H = 1.15, Leg = 0.44 },
	{ L = 1, B = 4, A = 2.0, H = 1.2, Leg = 0.5 },
	{ L = 2, B = 8, A = 4.2, H = 1.45, Leg = 0.53 },
	{ L = 3, B = 16, A = 7.5, H = 1.9, Leg = 0.55 },
	{ L = 4, B = 30, A = 12, H = 2.6, Leg = 0.56 },
	{ L = 5, B = 50, A = 17, H = 3.4, Leg = 0.57 },
	{ L = 6, B = 75, A = 22, H = 4.3, Leg = 0.58 },
	{ L = 9, B = 150, A = 30, H = 7, Leg = 0.58 },
	{ L = 12, B = 230, A = 36, H = 9.5, Leg = 0.58 },
	{ L = 15, B = 310, A = 40, H = 12, Leg = 0.58 },
	{ L = 18, B = 380, A = 44, H = 14, Leg = 0.58 },
	{ L = 24, B = 500, A = 48, H = 17, Leg = 0.58 },
	{ L = 30, B = 600, A = 52, H = 20, Leg = 0.58 },
	{ L = 60, B = 800, A = 60, H = 26, Leg = 0.58 },
}
BodyShape.KEYS = KEYS
BodyShape.MAX_ASPECT = 60
BodyShape.MIN_WIDTH = 0.5

export type Shape = {
	Body: number, -- legs + torso height
	Legs: number,
	Torso: number,
	Width: number, -- torso width (X)
	Depth: number, -- torso depth (Z)
	LimbWidth: number,
	ArmWidth: number,
	ArmLength: number,
	Head: number,
	Total: number, -- body + head
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- smoothstep inside each segment keeps growth speed continuous-looking
local function ease(t: number): number
	return t * t * (3 - 2 * t) * 0.35 + t * 0.65
end

function BodyShape.LogMeters(heightCm: number): number
	local meters = Num.NonNeg(heightCm) / 100
	return Num.Log10(meters, KEYS[1].L)
end

-- Raw keyframe values at log10(metres) = L
function BodyShape.Sample(L: number): (number, number, number, number)
	if L <= KEYS[1].L then
		local k = KEYS[1]
		return k.B, k.A, k.H, k.Leg
	end
	local last = KEYS[#KEYS]
	if L >= last.L then
		return last.B, last.A, last.H, last.Leg
	end
	for i = 1, #KEYS - 1 do
		local a, b = KEYS[i], KEYS[i + 1]
		if L <= b.L then
			local t = ease((L - a.L) / (b.L - a.L))
			return lerp(a.B, b.B, t), lerp(a.A, b.A, t), lerp(a.H, b.H, t), lerp(a.Leg, b.Leg, t)
		end
	end
	return last.B, last.A, last.H, last.Leg
end

--[[
	Full shape for a height.
	  stretch: squash/stretch factor from the tap animation (1 = none, 1.2 = 20% taller & thinner)
	  visualScale: event visual (GIANT MODE = 3, TINY MODE = 0.3), scales everything uniformly
]]
function BodyShape.FromHeight(heightCm: number, stretch: number?, visualScale: number?): Shape
	local B, A, H, legShare = BodyShape.Sample(BodyShape.LogMeters(heightCm))
	return BodyShape.Build(B, A, H, legShare, stretch, visualScale)
end

function BodyShape.Build(B: number, A: number, H: number, legShare: number, stretch: number?, visualScale: number?): Shape
	local s = math.clamp(stretch or 1, 0.4, 2)
	local v = math.clamp(visualScale or 1, 0.05, 20)
	A = math.min(A, BodyShape.MAX_ASPECT)
	local body = B * s
	-- squash & stretch roughly preserves volume: taller -> thinner
	local width = math.max(BodyShape.MIN_WIDTH, B / A) / math.sqrt(s)
	local torso = body * (1 - legShare)
	local legs = body * legShare
	local head = H * (1 + (s - 1) * 0.25)
	local limb = width * 0.48
	-- flat bodies get thin little arms (not flippers) that never reach through the floor
	local armWidth = math.min(limb, math.max(0.2, torso * 0.75))
	local shoulder = legs + torso - armWidth * 0.35
	local armLength = math.max(0.1, math.min(torso * 0.92, shoulder - 0.05))
	return {
		Body = body * v,
		Legs = legs * v,
		Torso = torso * v,
		Width = width * v,
		Depth = width * 0.55 * v,
		LimbWidth = limb * v,
		ArmWidth = armWidth * v,
		ArmLength = armLength * v,
		Head = head * v,
		Total = (body + head) * v,
	}
end

-- Total visual height (studs) of a body at `meters` (no animation) - used to place props
function BodyShape.TotalAtMeters(meters: number): number
	local shape = BodyShape.FromHeight(meters * 100)
	return shape.Total
end

return BodyShape
