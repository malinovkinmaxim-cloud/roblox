local LevelChunks = require(script.Parent.LevelChunks)

local LevelGenerator = {}

local HINTS = {
	"Случайный уровень: держитесь вместе!",
	"Ключ где-то на пути — не пропустите.",
	"Чем дальше, тем сложнее. Удачи!",
	"Помогайте тем, кто отстал.",
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

local function pickWeighted(rng, options, tier, avoid)
	local total = 0
	local weights = {}
	for i, chunk in options do
		local w = 0
		if chunk.tier <= tier and chunk ~= avoid then
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

-- Same (seed, index) always gives the same level, so a restart replays the same layout.
function LevelGenerator.generate(seed, index)
	local rng = Random.new(seed * 7919 + index)
	local tier = math.min(3, 1 + (index - 1) // 3)
	local count = math.min(9, 3 + index // 2)
	local maxDigit = math.min(4, tier + 1)

	local sequence = {}
	local previous = nil
	for _ = 1, count do
		local chunk = pickWeighted(rng, MIDDLE, tier, previous)
		table.insert(sequence, chunk)
		previous = chunk
	end
	local key = pickWeighted(rng, KEYS, math.min(tier, 2), nil)
	table.insert(sequence, rng:NextInteger(math.ceil(count / 2), count + 1), key)
	table.insert(sequence, 1, START)
	table.insert(sequence, DOOR)

	local rows = table.create(13, "")
	for _, chunk in sequence do
		local digit = tostring(rng:NextInteger(1, maxDigit))
		for r, row in chunk.map do
			rows[r] ..= string.gsub(row, "%?", digit)
		end
	end

	local data = {
		name = `Случайный #{index}`,
		hint = HINTS[rng:NextInteger(1, #HINTS)],
		map = rows,
		button = { need = 2, latch = true },
		button2 = { need = 1, latch = false },
		lift = { need = 99, rise = 4 },
		mover = { rise = 3, period = rng:NextNumber(3, 4.5) },
		cannon = { interval = 2.8, speed = 13 },
	}
	if tier >= 3 and rng:NextNumber() < 0.25 then
		data.scroll = { speed = math.min(5, 3 + index * 0.05), delay = 5 }
		data.hint = "Экран едет сам — не отставайте!"
	elseif tier >= 2 and rng:NextNumber() < 0.25 then
		data.time = 45 + count * 12
		data.hint = "На этот уровень есть ограничение по времени!"
	end
	return data
end

return LevelGenerator
