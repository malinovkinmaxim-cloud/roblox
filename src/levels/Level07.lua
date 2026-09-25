--[[
	LEVEL 7 - PRESSURE PLATE
	New ability: FREEZE your shadow where it stands (Q / ABILITY), release with E / INTERACT.
	Doors and platforms only work while the shadow stays on a plate - leave it there.
]]

local K = require(game:GetService("ServerScriptService").Server.Level.LevelKit)
local V = Vector3.new

return K.Level({
	Id = 7,
	Name = "PRESSURE PLATE",
	Subtitle = "Leave your double in the right place.",
	ParTime = 70,
	Role = "Shadow",
	ShadowDelay = 0.7,
	AllowFreeze = true,
	Hint = "ABILITY freezes your shadow. Freeze it ON the plate.",

	Elements = {
		K.Start(0, 0, 0),
		K.Sign(12, 0, 0, "NEW: PRESS [Q] / ABILITY TO FREEZE YOUR SHADOW.\nPRESS AGAIN (OR [E]) TO RELEASE IT.", { Width = 28, Height = 4 }),
		K.Floor(22, 0, 0, 30, 8),

		-- A: plate in an alcove, door ahead
		K.Floor(30, 0, -11, 8, 14),
		K.Plate("P1", 30, 0, -14, { Activator = "Doppel", ReleaseDelay = 0.3, Targets = { "D1" } }),
		K.Sign(30, 0, -8, "STEP ON THE PLATE, WALK AWAY,\nTHEN FREEZE YOUR SHADOW ON IT.", { Width = 20, Height = 4 }),
		K.Floor(50, 0, 0, 26, 8),
		K.Gate("D1", 44, 0, 0, 8, 10),

		K.Checkpoint(1, 68, 0, 0),

		-- B: the platform only moves while the shadow holds the plate
		K.Floor(80, 0, 0, 14, 8),
		K.Plate("P2", 80, 0, 0, { Activator = "Doppel", ReleaseDelay = 0.3, Targets = { "M2" } }),
		K.Sign(80, 0, 0, "THE PLATFORM ONLY MOVES WHILE YOUR\nSHADOW HOLDS THE PLATE.", { Width = 22, Height = 4 }),
		K.Mover(91, 0, 0, 6, 6, { Kind = "Linear", Offset = V(22, 0, 0), Period = 7, Pause = 1.2 }, { Id = "M2", Powered = true }),
		K.Floor(126, 0, 0, 14, 8),

		K.Checkpoint(2, 138, 0, 0),

		-- C: freeze it before the laser comes back
		K.Floor(160, 0, 0, 34, 8),
		K.Plate("P3", 150, 0, 0, { Activator = "Doppel", ReleaseDelay = 0.3, Targets = { "D3" } }),
		K.Laser("L3", 150, 4, 0, 6.5, 8, 8, { Cycle = { On = 1.5, Off = 3.2, Phase = 0 } }),
		K.Sign(146, 0, 0, "FREEZE IT BEFORE THE LASER COMES BACK.", { Width = 22, Height = 3 }),
		K.Gate("D3", 164, 0, 0, 8, 10),
		K.Finish(183, 0, 0),
	},
})
