--[[
	LiveEvents - limited-time events, computed from the UTC date (no server config needed,
	every server agrees). Shown as a small chip on the hub; the modifiers reach runs
	(Run options LiveEvent) and rewards.

	  67 WEEKEND   Saturday + Sunday: 67 events come twice as often, +20% fragments
	  GOLD RUSH    Friday: +25% coins from runs
	  BOSS WEEK    the first 7 days of every month: bosses drop +1 fragment
]]

export type LiveEvent = {
	Key: string,
	Title: string,
	Sub: string,
	EndsAt: number, -- unix time
	Mods: { [string]: number },
}

local LiveEvents = {}

local DAY = 86400

-- weekday of a unix time, 1 = Monday .. 7 = Sunday (1970-01-01 was a Thursday)
local function weekday(t: number): number
	return (math.floor(t / DAY) + 3) % 7 + 1
end

local function dayStart(t: number): number
	return math.floor(t / DAY) * DAY
end

function LiveEvents.Active(now: number): { LiveEvent }
	local out = {}
	local wd = weekday(now)
	local today = dayStart(now)
	if wd >= 6 then
		table.insert(out, {
			Key = "Weekend67",
			Title = "67 WEEKEND",
			Sub = "67 events twice as often, +20% fragments",
			EndsAt = today + (8 - wd) * DAY,
			Mods = { EventRate = 2, FragmentBonus = 0.2 },
		})
	elseif wd == 5 then
		table.insert(out, {
			Key = "GoldRush",
			Title = "GOLD RUSH",
			Sub = "+25% coins from runs today",
			EndsAt = today + DAY,
			Mods = { CoinBonus = 0.25 },
		})
	end
	local date = os.date("!*t", now)
	if date.day <= 7 then
		table.insert(out, {
			Key = "BossWeek",
			Title = "BOSS WEEK",
			Sub = "Bosses drop +1 fragment",
			EndsAt = today + (8 - date.day) * DAY,
			Mods = { BossFragments = 1 },
		})
	end
	return out
end

-- all modifiers of the active events, merged (numbers add up, EventRate multiplies)
function LiveEvents.Mods(now: number): { [string]: number }
	local mods = {}
	for _, e in LiveEvents.Active(now) do
		for k, v in e.Mods do
			if k == "EventRate" then
				mods[k] = (mods[k] or 1) * v
			else
				mods[k] = (mods[k] or 0) + v
			end
		end
	end
	return mods
end

return LiveEvents
