--[[
	LEVEL 2 - RIVAL
	Your doppelgänger races you to the finish. It is a bit faster... but it hesitates,
	picks random paths and sometimes falls. "DOPPELGÄNGER IS AHEAD!"
]]

local K = require(game:GetService("ServerScriptService").Server.Level.LevelKit)
local V = Vector3.new

return K.Level({
	Id = 2,
	Name = "RIVAL",
	Subtitle = "Race your double to the finish",
	ParTime = 45,
	Role = "Rival",
	Hint = "Beat your doppelgänger to the finish for a bonus!",

	Elements = {
		K.Start(0, 0, 0),
		K.Sign(12, 0, 0, "YOUR DOPPELGÄNGER WANTS TO WIN.\nBEAT IT TO THE FINISH!"),
		K.Floor(20, 0, 0, 26, 10),

		-- split: left = jumps, right = walkway with kill strips
		K.Floor(38, 0, -8, 5, 5),
		K.Floor(45, 0, -8, 5, 5),
		K.Floor(52, 0, -8, 5, 5),
		K.Floor(59, 0, -8, 5, 5),
		K.Floor(48, 0, 8, 30, 5),
		K.KillStrip(42, 0, 8, 2, 5),
		K.KillStrip(54, 0, 8, 2, 5),
		K.Floor(70, 0, 0, 14, 22),

		K.Checkpoint(1, 82, 0, 0),

		-- vanishing steps
		K.Vanish(93, 1, 0, 6, 6, { Visible = 2.4, Hidden = 1.2, Phase = 0 }, { Id = "V1" }),
		K.Vanish(101, 2, 0, 6, 6, { Visible = 2.4, Hidden = 1.2, Phase = 0.9 }, { Id = "V2" }),
		K.Vanish(109, 3, 0, 6, 6, { Visible = 2.4, Hidden = 1.2, Phase = 1.8 }, { Id = "V3" }),
		K.Floor(119, 3, 0, 14, 10),

		-- moving platform
		K.Mover(131, 3, 0, 6, 6, { Kind = "Linear", Offset = V(10, 0, 0), Period = 5, Pause = 0.8 }, { Id = "M1" }),
		K.Floor(155, 3, 0, 16, 10),

		K.Checkpoint(2, 168, 3, 0),

		-- final sprint: jump the spinning beam
		K.Floor(185, 3, 0, 24, 12),
		K.Sign(176, 3, 0, "JUMP OVER THE BEAM!", { Width = 14, Height = 3 }),
		K.Beam(185, 5, 0, 11, 1.6),
		K.Finish(204, 3, 0),
	},

	Route = {
		K.Node("n0", 0, 0, 0, { Checkpoint = 0 }),
		K.Node("n1", 30, 0, 0, { Next = { "l1", "r1" } }),
		K.Node("l1", 38, 0, -8),
		K.Node("l2", 45, 0, -8),
		K.Node("l3", 52, 0, -8),
		K.Node("l4", 59, 0, -8, { Next = { "m" } }),
		K.Node("r1", 36, 0, 8),
		K.Node("r2", 48, 0, 8, { Jump = true }),
		K.Node("r3", 60, 0, 8, { Jump = true, Next = { "m" } }),
		K.Node("m", 70, 0, 0),
		K.Node("cp1", 82, 0, 0, { Checkpoint = 1 }),
		K.Node("v1", 93, 1, 0, { On = "V1" }),
		K.Node("v2", 101, 2, 0, { On = "V2" }),
		K.Node("v3", 109, 3, 0, { On = "V3" }),
		K.Node("f1", 124, 3, 0),
		K.Node("mv", 131, 3, 0, { On = "M1" }),
		K.Node("f2", 150, 3, 0, { Safe = true }),
		K.Node("cp2", 168, 3, 0, { Checkpoint = 2, Hazard = true }),
		K.Node("b1", 196, 3, 3),
		K.Node("fin", 204, 3, 0, { Finish = true }),
	},
})
