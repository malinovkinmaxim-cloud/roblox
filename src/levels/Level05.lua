--[[
	LEVEL 5 - SHADOW
	New role: the Shadow repeats everything you do 0.7 seconds later.
	  - it presses the cyan button you walked over... 0.7 s later
	  - it copies your laser timing (and may not survive it)
	  - special: it holds a plate that extends a bridge - but only after you stood on it
]]

local K = require(game:GetService("ServerScriptService").Server.Level.LevelKit)
local V = Vector3.new

return K.Level({
	Id = 5,
	Name = "SHADOW",
	Subtitle = "It repeats you. 0.7 seconds later.",
	ParTime = 55,
	Role = "Shadow",
	ShadowDelay = 0.7,
	Hint = "Your shadow copies your moves with a delay.",

	Elements = {
		K.Start(0, 0, 0),
		K.Sign(12, 0, 0, "NEW ROLE: SHADOW.\nIT REPEATS YOUR MOVES 0.7 SECONDS LATER."),
		K.Floor(20, 0, 0, 26, 8),
		K.Floor(38, 1, 0, 5, 5),
		K.Floor(45, 2, -3, 5, 5),
		K.Floor(52, 3, 0, 5, 5),
		K.Floor(59, 4, 3, 5, 5),

		K.Checkpoint(1, 69, 4, 0),

		-- delayed button
		K.Floor(90, 4, 0, 32, 8),
		K.Sign(78, 4, 0, "YOUR SHADOW PRESSES CYAN BUTTONS\n0.7 SECONDS AFTER YOU.", { Width = 22, Height = 4 }),
		K.Button("B1", 81, 4, 0, { Activator = "Doppel", Mode = "Timed", Duration = 3, Targets = { "D1" } }),
		K.Gate("D1", 90, 4, 0, 8, 10),

		-- lasers: it copies your timing too
		K.Floor(118, 4, 0, 24, 8),
		K.Sign(108, 4, 0, "CAREFUL: IT COPIES YOUR TIMING TOO.", { Width = 20, Height = 3 }),
		K.Laser("L1", 114, 8, 0, 0.6, 8, 8, { Cycle = { On = 1.3, Off = 1.6, Phase = 0 } }),
		K.Laser("L2", 122, 8, 0, 0.6, 8, 8, { Cycle = { On = 1.3, Off = 1.6, Phase = 1.2 } }),

		K.Checkpoint(2, 135, 4, 0),

		-- special: shadow bridge
		K.Floor(146, 4, 0, 12, 8),
		K.Plate("P1", 147, 4, 0, { Activator = "Doppel", ReleaseDelay = 1.6, Targets = { "BR1" } }),
		K.Sign(143, 4, 0, "STAND ON THE PLATE FOR A MOMENT...\nTHEN GO. YOUR SHADOW WILL HOLD IT.", { Width = 22, Height = 4 }),
		K.Bridge("BR1", 159, 4, 0, 14, 6),
		K.Floor(172, 4, 0, 12, 8),

		-- launch pad up to the finish (your shadow flies the same arc a moment later)
		K.Launch(174, 4, 0, V(0, 75, 0)),
		K.Sign(169, 4, 0, "LAUNCH PAD! STEER FORWARD IN THE AIR.", { Width = 20, Height = 3 }),
		K.Finish(184, 14, 0),
	},
})
