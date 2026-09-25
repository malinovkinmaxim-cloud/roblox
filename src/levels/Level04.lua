--[[
	LEVEL 4 - TWO BUTTONS
	Race the Rival into a room with two identical "?" buttons. One opens the exit, the other
	switches on trap lasers. Which is which is shuffled every run.
	Watch what your Rival presses - or gamble yourself.
]]

local K = require(game:GetService("ServerScriptService").Server.Level.LevelKit)

return K.Level({
	Id = 4,
	Name = "TWO BUTTONS",
	Subtitle = "One opens the door. One does not.",
	ParTime = 55,
	Role = "Rival",
	Hint = "Watch which button your Rival presses...",

	Elements = {
		K.Start(0, 0, 0),
		K.Floor(20, 0, 0, 26, 10),
		K.Floor(38, 1, 0, 6, 6),
		K.Floor(46, 2, 0, 6, 6),
		K.Floor(58, 2, 0, 18, 10),

		K.Checkpoint(1, 72, 2, 0),

		-- the room
		K.Floor(95, 2, 0, 36, 24),
		K.Wall(95, 2, 12.5, 36, 10, 1),
		K.Wall(95, 2, -12.5, 36, 10, 1),
		K.Sign(84, 2, 0, "TWO BUTTONS. ONE OPENS THE EXIT.\nTHE OTHER... DOESN'T.", { Width = 22, Height = 4 }),
		K.Button("BA", 98, 2, -8, { Label = "?", Mode = "Timed", Duration = 7, Shuffle = "pick", Targets = { "Exit" } }),
		K.Button("BB", 98, 2, 8, { Label = "?", Mode = "Timed", Duration = 7, Shuffle = "pick", Bad = true, Targets = { "T1", "T2", "T3" } }),
		K.Laser("T1", 87, 3.2, 0, 0.6, 1.2, 24, { Trap = true }),
		K.Laser("T2", 104, 3.2, 0, 0.6, 1.2, 24, { Trap = true }),
		K.Laser("T3", 110.5, 7, 0, 0.6, 10, 10, { Trap = true }),
		K.Gate("Exit", 113, 2, 0, 10, 10, { Wing = 7 }),

		K.Floor(125, 2, 0, 24, 10),
		K.Checkpoint(2, 142, 2, 0),

		-- falling platforms: whoever goes first changes the path for the other
		K.Falling(152, 2, 0, 5, 5),
		K.Falling(159, 3, 0, 5, 5),
		K.Falling(166, 4, 0, 5, 5),
		K.Falling(173, 5, 0, 5, 5),
		K.Finish(184, 5, 0),
	},

	Route = {
		K.Node("n0", 0, 0, 0, { Checkpoint = 0 }),
		K.Node("a", 30, 0, 0),
		K.Node("p1", 38, 1, 0),
		K.Node("p2", 46, 2, 0),
		K.Node("b", 64, 2, 0),
		K.Node("cp1", 72, 2, 0, { Checkpoint = 1 }),
		K.Node("hub", 82, 2, 0, { Next = { "ba", "bb" }, Hazard = true }),
		K.Node("ba", 98, 2, -8, { Next = { "ef" }, Fallback = { "bb" }, Hazard = true }),
		K.Node("bb", 98, 2, 8, { Next = { "ef" }, Fallback = { "ba" }, Hazard = true }),
		K.Node("ef", 108, 2, 0, { Gate = "Exit", Timeout = 2.5, Fallback = { "ba", "bb" }, Next = { "out" }, Hazard = true }),
		K.Node("out", 118, 2, 0, { Safe = true }),
		K.Node("cp2", 142, 2, 0, { Checkpoint = 2 }),
		K.Node("f1", 152, 2, 0),
		K.Node("f2", 159, 3, 0),
		K.Node("f3", 166, 4, 0),
		K.Node("f4", 173, 5, 0),
		K.Node("fin", 184, 5, 0, { Finish = true }),
	},
})
