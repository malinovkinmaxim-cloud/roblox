--[[
	EventMapData - what the lobby map ("67 LAND") shows, shared by the server that builds it
	(Map/EventMap) and the client that brings it to life (EventMapController).

	The map is the difficulty ladder you can walk: every tier is an EVENT GATE in its own zone,
	from the calm park to THE 67 on its floating summit.
	  SPAWN -> THE PLAZA (THE GREAT BALANCE) -> THE PARK (I, II) -> THE HORDE YARD (III, IV)
	  -> THE RIFT (V, VI) -> THE 67 SUMMIT (VII)
	Each player sees their own gates: open, selected, NEXT (with the goal and the progress) or
	locked. Walking into an open gate starts a run on that tier (the server checks the unlock).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DifficultyData = require(ReplicatedStorage:WaitForChild("Modules").DifficultyData)

local EventMapData = {}

export type Zone = { Key: string, Name: string, Tagline: string, Tiers: { number } }

EventMapData.Zones = {
	{ Key = "Park", Name = "THE PARK", Tagline = "Where every hero starts.", Tiers = { 1, 2 } },
	{ Key = "Yard", Name = "THE HORDE YARD", Tagline = "Authorized survivors only.", Tiers = { 3, 4 } },
	{ Key = "Rift", Name = "THE RIFT", Tagline = "It's only a small rift.", Tiers = { 5, 6 } },
	{ Key = "Summit", Name = "THE 67 SUMMIT", Tagline = "Nobody knows why.", Tiers = { 7 } },
} :: { Zone }

--[[
	NPCs: real hero models standing around, each with a few short lines (shown in a speech
	bubble when you come close, one after the other). Dry, absurd, short.
]]
export type Npc = { Key: string, Hero: string, Name: string, Lines: { string }, Skin: string? }

EventMapData.Npcs = {
	{
		Key = "Guide",
		Hero = "Lucky", -- a host in a suit (not the Rookie: that is probably you)
		Name = "TOUR GUIDE",
		Lines = {
			"Welcome to 67 LAND!",
			"Every gate is an event. Walk in to play it.",
			"Locked gates open when you beat the one before.",
			"The big hands? Don't ask them anything.",
		},
	},
	{
		Key = "Security",
		Hero = "Tank",
		Name = "YARD SECURITY",
		Lines = {
			"Horde Yard. Authorized survivors only.",
			"Nothing to see here. Just a horde.",
			"I've guarded this gate for 67 years.",
			"No, you can't pet the horde.",
		},
	},
	{
		Key = "Starer",
		Hero = "Goober",
		Name = "???",
		Lines = {
			"...",
			"The wall is winning.",
			"Shh. Almost done.",
			"...",
		},
	},
	{
		Key = "Keeper",
		Hero = "Mage",
		Name = "RIFT KEEPER",
		Lines = {
			"It's only a small rift. Don't feed it.",
			"Beyond these gates: pain, mostly.",
			"The floor really is lava. I checked.",
		},
	},
	{
		Key = "The67",
		Hero = "SixSeven",
		Name = "THE 67",
		Lines = { "6.", "7.", "...", "6?" },
	},
} :: { Npc }

EventMapData.NpcByKey = {} :: { [string]: Npc }
for _, npc in EventMapData.Npcs do
	EventMapData.NpcByKey[npc.Key] = npc
end

EventMapData.TalkRange = 16 -- studs: a bubble shows when you are this close
EventMapData.LineTime = 3.4 -- seconds per line

--[[
	The state of a tier's gate for one player (from the synced data.Difficulty):
	  Selected  open, and the tier PLAY uses
	  Open      open
	  Next      the first locked tier (the goal and the progress are shown)
	  Locked    further away
]]
export type GateState = "Selected" | "Open" | "Next" | "Locked"

function EventMapData.GateState(index: number, difficulty: any?): GateState
	local unlocked = if difficulty and type(difficulty.Unlocked) == "number" then difficulty.Unlocked else 1
	local selected = if difficulty and type(difficulty.Selected) == "number" then difficulty.Selected else 1
	if index <= unlocked then
		return if index == selected then "Selected" else "Open"
	end
	return if index == unlocked + 1 then "Next" else "Locked"
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- the three lines over a gate: title, state, detail
function EventMapData.GateLines(index: number, difficulty: any?): (string, string, string)
	local tier = DifficultyData.Get(index)
	local state = EventMapData.GateState(index, difficulty)
	local title = tier.Numeral .. "  " .. tier.Name
	local cleared = difficulty and difficulty.Cleared and (difficulty.Cleared[index] == true or difficulty.Cleared[tostring(index)] == true)
	local reward = if tier.Reward ~= 1 then string.format("x%s rewards", tostring(tier.Reward)) else "normal rewards"
	if state == "Selected" or state == "Open" then
		local detail = if cleared
			then "CLEARED · " .. reward
			else string.format("FIRST WIN: +%s coins +%d fragments", commas(tier.FirstClear.Coins), tier.FirstClear.Fragments)
		return title, if state == "Selected" then "SELECTED · WALK IN" else "OPEN · WALK IN", detail
	elseif state == "Next" then
		local u = tier.Unlock
		local progress = if difficulty and difficulty.Best then DifficultyData.GoalProgress(tier, difficulty.Best) else ""
		return title, "NEXT: " .. string.upper(if u then u.Text else ""), progress
	end
	return title, "LOCKED", if tier.Unlock then tier.Unlock.Text else ""
end

-- the text of the EVENTS board on the plaza (limited-time events of today)
function EventMapData.BoardText(liveEvents: { any }?): (string, string)
	local list = liveEvents or {}
	if #list == 0 then
		return "NO EVENTS TODAY", "Suspicious. Very suspicious."
	end
	local titles, subs = {}, {}
	for _, e in list do
		table.insert(titles, tostring(e.Title))
		table.insert(subs, tostring(e.Sub))
	end
	return table.concat(titles, " + "), table.concat(subs, " · ")
end

return EventMapData
