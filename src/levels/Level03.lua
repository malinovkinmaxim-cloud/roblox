--[[
	LEVEL 3 - BUTTON
	"I need my double." Doors that only the doppelgänger can open:
	  1. a cyan button right on your path
	  2. a cyan button in a side alcove - walk in, walk out, your Echo follows and presses it
	  3. a cyan pressure plate before a door - wait at the door, your Echo stops on the plate
]]

local K = require(game:GetService("ServerScriptService").Server.Level.LevelKit)
local V = Vector3.new

return K.Level({
	Id = 3,
	Name = "BUTTON",
	Subtitle = "You need your double",
	ParTime = 50,
	Role = "Follower",
	Hint = "CYAN buttons only work for your doppelgänger.",

	Elements = {
		K.Start(0, 0, 0),
		K.Sign(12, 0, 0, "CYAN BUTTONS OPEN DOORS...\nBUT ONLY FOR YOUR DOPPELGÄNGER."),
		K.Floor(22, 0, 0, 30, 10),
		K.Button("B1", 26, 0, 0, { Activator = "Doppel", Mode = "Timed", Duration = 8, Targets = { "D1" } }),
		K.Gate("D1", 37, 0, 0, 10, 10),

		-- alcove button
		K.Floor(56, 0, 0, 38, 10),
		K.Floor(50, 0, -11, 7, 12),
		K.Button("B2", 50, 0, -13, { Activator = "Doppel", Mode = "Timed", Duration = 7, Targets = { "D2" } }),
		K.Sign(46, 0, 2, "LOCKED. MAYBE YOUR DOUBLE CAN HELP...", { Width = 18, Height = 3 }),
		K.Gate("D2", 63, 0, 0, 10, 10),

		K.Checkpoint(1, 80, 0, 0),

		-- jumps (your Echo copies them exactly)
		K.Floor(91, 1, 0, 6, 6),
		K.Floor(99, 2, 0, 6, 6),

		-- special: hold the plate
		K.Floor(115, 2, 0, 20, 10),
		K.Plate("P3", 117, 2, 0, { Activator = "Doppel", ReleaseDelay = 1.5, Targets = { "D3" } }),
		K.Sign(110, 2, 0, "WAIT AT THE DOOR.\nLET YOUR DOUBLE STAND ON THE PLATE.", { Width = 22, Height = 4 }),
		K.Gate("D3", 125, 2, 0, 10, 10),
		K.Floor(134, 2, 0, 18, 10),
		K.Finish(149, 2, 0),
	},
})
