--[[
	LEVEL 12 - TRUST?
	Your double is either an ALLY (usually) or a TROLL (rare) - you are not told which.
	A troll always has tells: it hesitates before obeying, its outline flickers magenta,
	and fake platforms shimmer under its feet when it waves you over.
	Every section has a harder route that doesn't need the double at all.
]]

local K = require(game:GetService("ServerScriptService").Server.Level.LevelKit)
local V = Vector3.new

local LANES = { -7, 0, 7 }
local LANE_NAMES = { "a", "b", "c" }

local elements = {
	K.Start(0, 0, 0),
	K.Sign(12, 0, 0, "YOUR DOUBLE SAYS IT WANTS TO HELP.\nDO YOU TRUST IT?"),
	K.Floor(20, 0, 0, 26, 10),

	-- A: good button (left island), trap button (right island), or the hard way around (right pads)
	K.Floor(45.5, 0, 0, 25, 10),
	K.Floor(44, 2, -18, 6, 6),
	K.Button("BG", 44, 2, -18, { Activator = "Doppel", Mode = "Timed", Duration = 6, Targets = { "D1" } }),
	K.Sign(44, 2, -18, "OPENS THE DOOR", { Width = 12, Height = 2.5 }),
	K.Floor(44, 2, 18, 6, 6),
	K.Button("BX", 44, 2, 18, { Activator = "Doppel", Mode = "Timed", Duration = 5, Bad = true, Targets = { "T1", "T2" } }),
	K.Laser("T1", 48, 1.2, 0, 0.6, 1.2, 10, { Trap = true }),
	K.Laser("T2", 53, 1.2, 0, 0.6, 1.2, 10, { Trap = true }),
	K.Gate("D1", 58, 0, 0, 10, 10, { Wing = 1 }),
	-- hard route
	K.Floor(50, 1, 10, 4, 4),
	K.Floor(57, 2, 10, 4, 4),
	K.Floor(64, 1, 10, 4, 4),
	K.Floor(69, 0, 0, 22, 10),

	K.Checkpoint(1, 85, 0, 0),
}

-- B: rows with fake platforms (a troll likes to wave you onto those)
local fakeGroups = {}
for rowIndex, x in { 97, 105, 113 } do
	local group = "u" .. rowIndex
	fakeGroups[group] = { Fake = 1 }
	for laneIndex, z in LANES do
		table.insert(elements, K.Fake(string.format("U%d%s", rowIndex, LANE_NAMES[laneIndex]), x, 0, z, 5, 5, { Group = group, Lure = true }))
	end
end

for _, element in {
	K.Floor(125, 0, 0, 14, 10),
	K.Checkpoint(2, 137, 0, 0),

	-- C: plate on an island opens the door... or ride the platform around it
	K.Floor(152, 0, 0, 20, 10),
	K.Floor(148, 2, 18, 6, 6),
	K.Plate("P2", 148, 2, 18, { Activator = "Doppel", ReleaseDelay = 0.3, Targets = { "D2" } }),
	K.Gate("D2", 156, 0, 0, 10, 10, { Wing = 1 }),
	K.Mover(150, 0, -12, 6, 6, { Kind = "Linear", Offset = V(14, 0, 0), Period = 6, Pause = 1 }),
	K.Floor(172, 0, 0, 20, 10),
	K.Finish(188, 0, 0),
} do
	table.insert(elements, element)
end

return K.Level({
	Id = 12,
	Name = "TRUST?",
	Subtitle = "Ally... or Troll?",
	ParTime = 90,
	Role = { Pool = { "Ally", "Troll" } },
	RoleHidden = true,
	Chapter = 2,
	Hint = "Is it helping you? Watch for hesitation and flickers.",
	FakeGroups = fakeGroups,
	Elements = elements,
})
