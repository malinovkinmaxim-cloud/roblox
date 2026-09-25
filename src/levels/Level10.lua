--[[
	LEVEL 10 - FINAL TEST (end of chapter 1)
	Everything at once:
	  Part 1 (SHADOW + FREEZE): plate & door, moving platforms, delayed button
	  Checkpoint 2 switches the role -> "DOPPELGÄNGER ... IS ... THE RIVAL."
	  Part 2 (RIVAL): fake platform rows, the two-button room, trap lasers, a spinning beam,
	                  falling platforms, and a race to the finish.
]]

local K = require(game:GetService("ServerScriptService").Server.Level.LevelKit)
local V = Vector3.new

local LANES = { -7, 0, 7 }
local LANE_NAMES = { "a", "b", "c" }

local elements = {
	K.Start(0, 0, 0),
	K.Sign(12, 0, 0, "FINAL TEST.\nEVERYTHING YOU LEARNED."),
	K.Floor(20, 0, 0, 26, 8),

	-- plate in an alcove + door (freeze!)
	K.Floor(28, 0, -9, 8, 10),
	K.Plate("P1", 28, 0, -10, { Activator = "Doppel", ReleaseDelay = 0.3, Targets = { "D1" } }),
	K.Floor(46, 0, 0, 26, 8),
	K.Gate("D1", 40, 0, 0, 8, 10),

	-- moving platforms (circular, then vertical)
	K.Mover(69, 0, 0, 6, 6, { Kind = "Circle", Radius = 3, Period = 5 }),
	K.Mover(78, 0, 0, 6, 6, { Kind = "Linear", Offset = V(0, 6, 0), Period = 4.4, Pause = 0.9 }),
	K.Floor(90, 6, 0, 14, 8),

	K.Checkpoint(1, 102, 6, 0),

	-- delayed cyan button
	K.Floor(115, 6, 0, 16, 8),
	K.Button("B2", 111, 6, 0, { Activator = "Doppel", Mode = "Timed", Duration = 4, Targets = { "D2" } }),
	K.Gate("D2", 120, 6, 0, 8, 10),

	-- the role changes here
	K.Checkpoint(2, 128, 6, 0, { SetRole = "Rival" }),
}

local route = {
	K.Node("c2", 128, 6, 0, { Checkpoint = 2, Next = { "q1a", "q1b", "q1c" } }),
}
local fakeGroups = {}

-- fake rows (the rival tests them for you)
local rows = { 138, 146, 154 }
for rowIndex, x in rows do
	local group = "q" .. rowIndex
	fakeGroups[group] = { Fake = 1 }
	for laneIndex, z in LANES do
		local id = string.format("Q%d%s", rowIndex, LANE_NAMES[laneIndex])
		table.insert(elements, K.Fake(id, x, 6, z, 5, 5, { Group = group }))
		local nextIds = {}
		if rowIndex == #rows then
			nextIds = { "e" }
		else
			for nextLane = math.max(1, laneIndex - 1), math.min(3, laneIndex + 1) do
				table.insert(nextIds, string.format("q%d%s", rowIndex + 1, LANE_NAMES[nextLane]))
			end
		end
		table.insert(route, K.Node(string.format("q%d%s", rowIndex, LANE_NAMES[laneIndex]), x, 6, z, { On = id, Next = nextIds }))
	end
end

-- two-button room
for _, element in {
	K.Floor(164, 6, 0, 12, 10),
	K.Floor(184, 6, 0, 28, 20),
	K.Wall(184, 6, 10.5, 28, 10, 1),
	K.Wall(184, 6, -10.5, 28, 10, 1),
	K.Button("BA", 186, 6, -6, { Label = "?", Mode = "Timed", Duration = 6, Shuffle = "pick", Targets = { "Exit" } }),
	K.Button("BB", 186, 6, 6, { Label = "?", Mode = "Timed", Duration = 6, Shuffle = "pick", Bad = true, Targets = { "T1", "T2" } }),
	K.Laser("T1", 180, 7.2, 0, 0.6, 1.2, 20, { Trap = true }),
	K.Laser("T2", 192, 7.2, 0, 0.6, 1.2, 20, { Trap = true }),
	K.Gate("Exit", 198, 6, 0, 8, 10, { Wing = 6 }),

	K.Checkpoint(3, 203, 6, 0),

	-- spinning beam, falling platforms, finish
	K.Floor(216, 6, 0, 16, 12),
	K.Beam(216, 8, 0, 11, 1.8),
	K.Falling(229, 7, 0, 5, 5),
	K.Falling(236, 8, 0, 5, 5),
	K.Falling(243, 9, 0, 5, 5),
	K.Finish(254, 9, 0),
} do
	table.insert(elements, element)
end

for _, node in {
	K.Node("e", 162, 6, 0, { Safe = true }),
	K.Node("hub", 174, 6, 0, { Next = { "ba", "bb" }, Hazard = true }),
	K.Node("ba", 186, 6, -6, { Next = { "ef" }, Fallback = { "bb" }, Hazard = true }),
	K.Node("bb", 186, 6, 6, { Next = { "ef" }, Fallback = { "ba" }, Hazard = true }),
	K.Node("ef", 195, 6, 0, { Gate = "Exit", Timeout = 2.5, Fallback = { "ba", "bb" }, Next = { "c3" }, Hazard = true }),
	K.Node("c3", 203, 6, 0, { Checkpoint = 3, Hazard = true }),
	K.Node("bx", 223, 6, 3),
	K.Node("f1", 229, 7, 0),
	K.Node("f2", 236, 8, 0),
	K.Node("f3", 243, 9, 0),
	K.Node("fin", 254, 9, 0, { Finish = true }),
} do
	table.insert(route, node)
end

return K.Level({
	Id = 10,
	Name = "FINAL TEST",
	Subtitle = "Chapter 1 exam: Shadow, then Rival.",
	ParTime = 110,
	Role = "Shadow",
	ShadowDelay = 0.7,
	AllowFreeze = true,
	RivalStartCheckpoint = 2,
	Hint = "Checkpoint 2 changes your doppelgänger's role.",
	FakeGroups = fakeGroups,
	Elements = elements,
	Route = route,
})
