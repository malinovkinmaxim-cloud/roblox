--[[
	LEVEL 9 - FAKE SAFE PLATFORM
	Rows of identical platforms. Some are fake (different ones every run).
	Your Rival races ahead and picks platforms at random - when it lands on a fake one,
	it falls and the fake is revealed. Use it as your tester... or take the risk and win the race.
]]

local K = require(game:GetService("ServerScriptService").Server.Level.LevelKit)

local LANES = { -7, 0, 7 }
local LANE_NAMES = { "a", "b", "c" }

local elements = {
	K.Start(0, 0, 0),
	K.Sign(12, 0, 0, "SOME PLATFORMS ARE FAKE.\nLET YOUR RIVAL TEST THEM... OR RACE IT."),
	K.Floor(18, 0, 0, 22, 10),
}
local route = {
	K.Node("s0", 0, 0, 0, { Checkpoint = 0 }),
	K.Node("s1", 27, 0, 0, { Safe = true, Next = { "r1a", "r1b", "r1c" } }),
}
local fakeGroups = {}

-- a field of rows; each row has `fakeCount` fake platforms out of 3
local function field(prefix: string, firstRow: number, xs: { number }, fakeCount: number, exitNode: string)
	for rowIndex, x in xs do
		local row = firstRow + rowIndex - 1
		local group = "row" .. row
		fakeGroups[group] = { Fake = fakeCount }
		for laneIndex, z in LANES do
			local id = string.format("F%d%s", row, LANE_NAMES[laneIndex])
			table.insert(elements, K.Fake(id, x, 0, z, 5, 5, { Group = group }))
			-- the rival can only jump to the same or a neighbouring lane
			local nextIds = {}
			if rowIndex == #xs then
				nextIds = { exitNode }
			else
				for nextLane = math.max(1, laneIndex - 1), math.min(3, laneIndex + 1) do
					table.insert(nextIds, string.format("%s%d%s", prefix, row + 1, LANE_NAMES[nextLane]))
				end
			end
			table.insert(route, K.Node(string.format("%s%d%s", prefix, row, LANE_NAMES[laneIndex]), x, 0, z, {
				On = id,
				Next = nextIds,
			}))
		end
	end
end

field("r", 1, { 34, 42, 50, 58 }, 1, "e1")
table.insert(elements, K.Floor(72, 0, 0, 14, 10))
table.insert(route, K.Node("e1", 70, 0, 0, { Safe = true }))
table.insert(elements, K.Checkpoint(1, 84, 0, 0))
table.insert(route, K.Node("cp1", 84, 0, 0, { Checkpoint = 1, Next = { "r5a", "r5b", "r5c" } }))

-- (one fake per row: the middle lane touches both others, so a real path always exists)
field("r", 5, { 95, 103, 111, 119, 127 }, 1, "e2")
table.insert(elements, K.Floor(139, 0, 0, 14, 10))
table.insert(route, K.Node("e2", 137, 0, 0, { Safe = true }))
table.insert(elements, K.Checkpoint(2, 151, 0, 0))
table.insert(route, K.Node("cp2", 151, 0, 0, { Checkpoint = 2 }))

-- last stretch: vanishing + falling platforms
table.insert(elements, K.Vanish(161, 1, 0, 6, 6, { Visible = 2.6, Hidden = 1.0, Phase = 0 }, { Id = "V1" }))
table.insert(elements, K.Vanish(169, 2, 0, 6, 6, { Visible = 2.6, Hidden = 1.0, Phase = -0.8 }, { Id = "V2" }))
table.insert(elements, K.Falling(177, 3, 0, 5, 5))
table.insert(elements, K.Falling(185, 4, 0, 5, 5))
table.insert(elements, K.Finish(196, 4, 0))
table.insert(route, K.Node("v1", 161, 1, 0, { On = "V1" }))
table.insert(route, K.Node("v2", 169, 2, 0, { On = "V2" }))
table.insert(route, K.Node("f1", 177, 3, 0))
table.insert(route, K.Node("f2", 185, 4, 0))
table.insert(route, K.Node("fin", 196, 4, 0, { Finish = true }))

return K.Level({
	Id = 9,
	Name = "FAKE SAFE PLATFORM",
	Subtitle = "Let your double test the floor.",
	ParTime = 60,
	Role = "Rival",
	Hint = "Fake platforms vanish. Watch where your Rival falls.",
	FakeGroups = fakeGroups,
	Elements = elements,
	Route = route,
})
