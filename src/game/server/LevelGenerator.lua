local LevelChunks = require(script.Parent.LevelChunks)

local LevelGenerator = {}

local HINTS = {
	"Random level: stick together!",
	"The key is somewhere on the way - don't miss it.",
	"The further you go, the harder it gets. Good luck!",
	"Help the pals who fall behind.",
}

-- What each party size can handle: fewest players the chunk needs, crate weights and plate needs
local PARTY_RULES = {
	solo = { players = 1, digits = { 1, 1 }, button = 1 },
	duo = { players = 2, digits = { 1, 2 }, button = 2 },
	squad = { players = 3, digits = { 2, 4 }, button = 3 },
	party = { players = 5, digits = { 3, 6 }, button = 5 },
}

local function byKind(kind)
	local list = {}
	for _, chunk in LevelChunks do
		if chunk.kind == kind then
			table.insert(list, chunk)
		end
	end
	return list
end

local START = byKind("start")[1]
local DOOR = byKind("door")[1]
local KEYS = byKind("key")
local MIDDLE = byKind("mid")

-- Chunks of the current tier are 3x as likely as easier ones, so each step up in difficulty is felt
local function pick(rng, options, tier, avoid, scrollOnly, players)
	local total = 0
	local weights = {}
	for i, chunk in options do
		local w = 0
		if chunk.tier <= tier and chunk ~= avoid and chunk.minPlayers <= players and (not scrollOnly or chunk.scrollSafe) then
			w = if chunk.tier == tier then 3 else 1
		end
		weights[i] = w
		total += w
	end
	local roll = rng:NextNumber() * total
	for i, chunk in options do
		roll -= weights[i]
		if roll <= 0 and weights[i] > 0 then
			return chunk
		end
	end
	return options[1]
end

-- Same (seed, index, party) always gives the same level, so a restart replays the same layout.
-- Difficulty ramps up with index: harder chunks every 3 levels, longer levels, faster cannons,
-- quicker moving platforms and, later on, scrolling screens, time limits and red lights.
function LevelGenerator.generate(seed, index, partyId)
	local rules = PARTY_RULES[partyId] or PARTY_RULES.duo
	local rng = Random.new(seed * 7919 + index)
	local tier = math.min(4, 1 + (index - 1) // 3)
	local count = math.min(12, 3 + index // 2)
	local maxDigit = math.min(rules.digits[2], rules.digits[1] + tier - 1)
	local scrolling = tier >= 3 and rng:NextNumber() < 0.2

	local sequence = {}
	local previous = nil
	for _ = 1, count do
		local chunk = pick(rng, MIDDLE, tier, previous, scrolling, rules.players)
		table.insert(sequence, chunk)
		previous = chunk
	end
	local key = pick(rng, KEYS, tier, nil, scrolling, rules.players)
	table.insert(sequence, rng:NextInteger(math.ceil(count / 2), count + 1), key)
	table.insert(sequence, 1, START)
	table.insert(sequence, DOOR)

	local height = 0
	for _, chunk in sequence do
		height = math.max(height, #chunk.map)
	end
	local rows = table.create(height, "")
	for _, chunk in sequence do
		local digit = tostring(rng:NextInteger(rules.digits[1], maxDigit))
		local pad = height - #chunk.map
		local width = #chunk.map[1]
		for r = 1, height do
			local row = if r > pad then chunk.map[r - pad] else string.rep(" ", width)
			rows[r] ..= string.gsub(row, "%?", digit)
		end
	end

	local data = {
		name = `Random #{index}`,
		hint = HINTS[rng:NextInteger(1, #HINTS)],
		map = rows,
		button = { need = rules.button, latch = true },
		button2 = { need = 1, latch = false },
		lift = { need = 99, rise = 4 },
		mover = { rise = 3, period = math.max(2.6, 4.5 - index * 0.08) },
		cannon = { interval = math.max(1.7, 3 - index * 0.05), speed = math.min(17, 12 + index * 0.2) },
	}

	local hasCannon = false
	for _, row in rows do
		if string.find(row, "[<>]") then
			hasCannon = true
			break
		end
	end

	if scrolling then
		data.scroll = { speed = math.min(5, 3 + index * 0.05), delay = 5 }
		data.hint = "The screen scrolls by itself - keep up!"
	elseif tier >= 3 and not hasCannon and rng:NextNumber() < 0.15 then
		data.stopgo = { go = math.max(2.5, 4 - index * 0.04), stop = 2.5 }
		data.hint = "Red light: freeze when it turns red!"
	elseif tier >= 2 and rng:NextNumber() < 0.2 then
		data.time = 40 + count * 12
		data.hint = "This level has a time limit!"
	end
	return data
end

return LevelGenerator
