--[[
	LEVEL 6 - DELAY
	The shadow is 1.5 s behind. The delay IS the puzzle - act in advance:
	  A. a gate that opens only while your shadow is on a plate behind you
	  B. two plates at once: cyan (shadow) + orange (you) -> your past self helps your present self
	  C. a laser your shadow switches off 1.5 s after you walked over its button
]]

local K = require(game:GetService("ServerScriptService").Server.Level.LevelKit)

return K.Level({
	Id = 6,
	Name = "DELAY",
	Subtitle = "Your shadow is 1.5 seconds behind. Plan ahead.",
	ParTime = 60,
	Role = "Shadow",
	ShadowDelay = 1.5,
	Hint = "Do things early - your shadow does them 1.5 s later.",

	Elements = {
		K.Start(0, 0, 0),
		K.Sign(12, 0, 0, "YOUR SHADOW IS SLOWER NOW: 1.5 SECONDS.\nPLAN AHEAD."),
		K.Floor(20, 0, 0, 26, 8),

		-- A: plate behind you, gate in front of you
		K.Floor(51.5, 0, 0, 37, 8),
		K.Plate("P1", 38, 0, 0, { Activator = "Doppel", ReleaseDelay = 0.25, Targets = { "G1" } }),
		K.Sign(46, 0, 0, "THE GATE ONLY OPENS WHILE YOUR SHADOW\nSTANDS ON THE PLATE. TIMING!", { Width = 24, Height = 4 }),
		K.Gate("G1", 56, 0, 0, 8, 10),

		K.Checkpoint(1, 75, 0, 0),

		-- B: both plates at once
		K.Floor(97, 0, 0, 34, 10),
		K.Plate("PC", 88, 0, 0, { Activator = "Doppel", ReleaseDelay = 0.5, Targets = { "G2" } }),
		K.Plate("PO", 100, 0, 0, { Activator = "Player", ReleaseDelay = 1.2, Targets = { "G2" } }),
		K.Sign(94, 0, 0, "BOTH PLATES AT THE SAME TIME.\nYOUR PAST SELF CAN HELP YOUR PRESENT SELF.", { Width = 26, Height = 4 }),
		K.Gate("G2", 108, 0, 0, 10, 10, { Logic = "All" }),

		K.Checkpoint(2, 119, 0, 0),

		-- C: the shadow disables the laser... later
		K.Floor(140, 0, 0, 32, 8),
		K.Button("B3", 128, 0, 0, { Activator = "Doppel", Mode = "Timed", Duration = 2.5, Targets = { "L3" } }),
		K.Laser("L4", 138, 4, 0, 0.6, 8, 8, { Cycle = { On = 1.0, Off = 1.4, Phase = 0 } }),
		K.Laser("L3", 150, 4, 0, 0.6, 8, 8),
		K.Finish(162, 0, 0),
	},
})
