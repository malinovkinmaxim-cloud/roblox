--[[
	LEVEL 8 - SPLIT
	Your shadow walks its OWN lane, 26 studs to your left, 0.3 s behind you.
	The lanes are different: you must jump where IT needs to jump, stand where IT needs to
	stand. Buttons in one lane open things in the other.
	LINKED: if your shadow falls, you fall.
]]

local K = require(game:GetService("ServerScriptService").Server.Level.LevelKit)
local V = Vector3.new

local LANE = -26 -- shadow lane z
local CYAN = K.Colors.Doppel

local function marker(x: number)
	-- a glowing stripe in YOUR lane that says "jump here for your shadow"
	return K.Decor(x, 0.06, 0, 2, 0.1, 8, { Color = CYAN, Material = Enum.Material.Neon })
end

return K.Level({
	Id = 8,
	Name = "SPLIT",
	Subtitle = "Two lanes. One fate.",
	ParTime = 55,
	Role = "Shadow",
	ShadowDelay = 0.3,
	ShadowOffset = V(0, 0, LANE),
	ShadowPhase = false,
	LinkedFate = true,
	Hint = "Move for BOTH of you. If your shadow falls, you fall.",

	Elements = {
		K.Start(0, 0, 0, { DoppelOffset = V(0, 0, LANE) }),
		K.Floor(0, 0, LANE, 14, 14),
		K.Sign(10, 0, -13, "SPLIT: YOUR SHADOW WALKS ITS OWN LANE.\nIF IT FALLS, YOU FALL.", { Width = 26, Height = 4 }),

		-- 1: its lane has a gap, yours doesn't -> jump anyway
		K.Floor(25, 0, 0, 36, 8),
		K.Floor(15, 0, LANE, 16, 8),
		K.Floor(36, 0, LANE, 14, 8),
		marker(22),
		K.Sign(22, 0, 0, "JUMP HERE - FOR YOUR SHADOW", { Width = 16, Height = 2.5 }),
		-- your gap, its floor
		K.Floor(55, 0, 0, 12, 8),
		K.Floor(52, 0, LANE, 18, 8),

		-- 2: its button, your door (move to your left edge!)
		K.Floor(72, 0, 0, 22, 8),
		K.Floor(72, 0, LANE, 22, 8),
		K.Button("B1", 68, 0, LANE - 3.5, { Activator = "Doppel", Mode = "Timed", Duration = 4, Targets = { "D1" } }),
		K.Sign(66, 0, 0, "ITS BUTTON IS OFF-CENTER.\nWALK ON YOUR LEFT EDGE.", { Width = 18, Height = 4 }),
		K.Gate("D1", 78, 0, 0, 8, 10),

		-- 3: your button, its bridge
		K.Floor(92, 0, 0, 18, 8),
		K.Button("B2", 84, 0, 0, { Activator = "Player", Mode = "Timed", Duration = 5, Targets = { "BR2" } }),
		K.Floor(86.5, 0, LANE, 7, 8),
		K.Bridge("BR2", 95.5, 0, LANE, 11, 8),

		K.Checkpoint(1, 106, 0, 0, { DoppelOffset = V(0, 0, LANE) }),
		K.Floor(106, 0, LANE, 10, 10),

		-- 4: lasers only in its lane -> jump over them from your lane
		K.Floor(125, 0, 0, 28, 8),
		K.Floor(125, 0, LANE, 28, 8),
		K.Laser("L1", 118, 0.9, LANE, 0.6, 1.2, 8),
		K.Laser("L2", 131, 0.9, LANE, 0.6, 1.2, 8),
		marker(116),
		marker(129),

		-- 5: it holds the finish gate open
		K.Floor(150, 0, 0, 22, 8),
		K.Floor(150, 0, LANE, 22, 8),
		K.Plate("FP", 144, 0, LANE, { Activator = "Doppel", ReleaseDelay = 1.0, Targets = { "FG" } }),
		K.Gate("FG", 147, 0, 0, 8, 10),
		K.Floor(167, 0, LANE, 12, 8),
		K.Finish(167, 0, 0),
	},
})
