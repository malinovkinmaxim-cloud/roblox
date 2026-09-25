--[[
	LEVEL 11 - ALLY (chapter 2 preview)
	Your double is on your side - but it only helps when you tell it where:
	  ABILITY (SEND): face a cyan plate / button / platform -> it goes there and stays
	  INTERACT (RECALL): it comes back
	  A. hold a plate on an island you can't reach
	  B. test suspicious platforms for you (it falls instead of you)
	  C. aim from the right spot: a timed button far away
]]

local K = require(game:GetService("ServerScriptService").Server.Level.LevelKit)

local LANES = { -7, 0, 7 }
local LANE_NAMES = { "a", "b", "c" }

local elements = {
	K.Start(0, 0, 0),
	K.Sign(12, 0, 0, "YOUR DOUBLE WANTS TO HELP.\nFACE A CYAN PLATE AND PRESS [Q] / ABILITY TO SEND IT.\n[E] / INTERACT CALLS IT BACK.", { Width = 30, Height = 5 }),
	K.Floor(20, 0, 0, 26, 10),

	-- A: plate on an island
	K.Floor(50, 0, 0, 34, 10),
	K.Floor(38, 0, 20, 8, 8),
	K.Plate("P1", 38, 0, 20, { Activator = "Doppel", ReleaseDelay = 0.3, Targets = { "D1" } }),
	K.Gate("D1", 46, 0, 0, 10, 10),

	K.Checkpoint(1, 72, 0, 0),
}

-- B: which platform is real? send your double first
local fakeGroups = {}
for rowIndex, x in { 84, 92 } do
	local group = "t" .. rowIndex
	fakeGroups[group] = { Fake = 2 }
	for laneIndex, z in LANES do
		table.insert(elements, K.Fake(string.format("T%d%s", rowIndex, LANE_NAMES[laneIndex]), x, 0, z, 5, 5, { Group = group }))
	end
end

for _, element in {
	K.Sign(76, 0, 0, "TWO OF EACH THREE ARE FAKE.\nSEND YOUR DOUBLE TO TEST ONE.", { Width = 20, Height = 4 }),
	K.Floor(104, 0, 0, 14, 10),

	K.Checkpoint(2, 116, 0, 0),

	-- C: timed button on a high island - send it from near the door
	K.Floor(135, 0, 0, 28, 10),
	K.Floor(128, 3, -22, 6, 6),
	K.Button("B3", 128, 3, -22, { Activator = "Doppel", Mode = "Timed", Duration = 5, Targets = { "D3" } }),
	K.Sign(138, 0, 0, "THE DOOR STAYS OPEN FOR 5 SECONDS.\nSEND IT FROM CLOSE TO THE DOOR.", { Width = 22, Height = 4 }),
	K.Gate("D3", 146, 0, 0, 10, 10),
	K.Finish(155, 0, 0),
} do
	table.insert(elements, element)
end

return K.Level({
	Id = 11,
	Name = "ALLY",
	Subtitle = "Tell your double where to help.",
	ParTime = 75,
	Role = "Ally",
	RoleHidden = true,
	Chapter = 2,
	Hint = "ABILITY sends your double to what you're facing. INTERACT calls it back.",
	FakeGroups = fakeGroups,
	Elements = elements,
})
