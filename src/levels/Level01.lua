--[[
	LEVEL 1 - INTRO
	Role: Follower ("Echo"). Teaches: move, jump, avoid red, "this is your double".
	Special section: a gap only your doppelgänger can bridge (it presses the CYAN button
	it walks over - you can't).
]]

local K = require(game:GetService("ServerScriptService").Server.Level.LevelKit)
local V = Vector3.new

return K.Level({
	Id = 1,
	Name = "INTRO",
	Subtitle = "Meet your Doppelgänger",
	ParTime = 40,
	Role = "Follower",
	Hint = "Your doppelgänger follows your every step.",

	Elements = {
		K.Start(0, 0, 0),
		K.Sign(12, 0, 0, "THIS IS YOUR DOPPELGÄNGER.\nIT FOLLOWS YOUR EVERY STEP."),
		K.Floor(18.5, 0, 0, 23, 8),

		-- first jumps
		K.Sign(32, 0, 0, "JUMP! (it jumps too)", { Width = 14, Height = 3 }),
		K.Floor(36, 1, 0, 6, 6),
		K.Floor(44, 2, 0, 6, 6),
		K.Floor(52, 3, 0, 6, 6),

		K.Checkpoint(1, 62, 3, 0),

		-- red = danger
		K.Floor(80, 3, 0, 26, 8),
		K.Sign(70, 3, 0, "RED = DANGER. JUMP OVER IT.", { Width = 16, Height = 3 }),
		K.KillStrip(76, 3, 0, 2, 8),
		K.KillStrip(86, 3, 0, 2, 8),
		K.Floor(101, 3, 0, 16, 3), -- narrow beam

		-- the CYAN button: only the doppelgänger can press it
		K.Button("B1", 104, 3, 0, { Activator = "Doppel", Mode = "Once", Targets = { "BR1" }, Size = V(3, 0.5, 3) }),
		K.Sign(98, 3, 0, "CYAN BUTTON: ONLY YOUR DOUBLE CAN PRESS IT.\nWALK OVER IT AND KEEP GOING.", { Width = 26, Height = 4 }),

		K.Checkpoint(2, 114, 3, 0),

		-- special: the doppel-made bridge
		K.Bridge("BR1", 125, 3, 0, 12, 6),
		K.Floor(137, 3, 0, 12, 10),
		K.Finish(149, 3, 0),
	},
})
