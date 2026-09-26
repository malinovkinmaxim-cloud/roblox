--[[
	Session - per-player runtime state around the saved Data.

	All gameplay logic (Logic/*) works on a Session and never touches Roblox instances, so it
	can be unit-tested offline. Side effects are queued:
	  session.Dirty[section] = true      -> PlayerService sends a Sync of that section
	  session.Out                          -> list of { Type = "Notify"|"Effect", ... } to send
	  session.AttrDirty = true             -> replicated player attributes need refresh
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Session = {}

export type Session = {
	UserId: number,
	Name: string,
	Data: any,
	Passes: { [string]: boolean },
	ZoneIndex: number,
	Tokens: number,
	LastRefill: number,
	JoinClock: number,
	PlaytimeClaimed: { [number]: boolean },
	EventTapped: boolean,
	RecordArmed: boolean,
	PetMultCache: number?,
	Dirty: { [string]: boolean },
	AttrDirty: boolean,
	Out: { any },
	Flags: { [string]: number },
	InVIPArea: boolean?,
	Percentile: number?,
	Leaving: boolean?,
	Released: boolean?,
	NextAutoHatch: number?,
	AutoZone: number?, -- one-button mode: highest zone we already moved the player to
	EggBudget: number?, -- one-button mode: coins set aside for eggs
	CoinsSeen: number?, -- one-button mode: coins at the end of the last autopilot tick
	IncomeRate: number?, -- one-button mode: smoothed coins per second
}

function Session.new(userId: number, name: string, data: any, clock: number): Session
	return {
		UserId = userId,
		Name = name,
		Data = data,
		Passes = {},
		ZoneIndex = 1,
		Tokens = Config.Tap.Burst,
		LastRefill = clock,
		JoinClock = clock,
		PlaytimeClaimed = {},
		EventTapped = false,
		-- "NEW HEIGHT RECORD!" fires once per rebirth cycle when you pass your old best
		RecordArmed = data.Rebirths > 0 and data.Height < data.BestHeight,
		PetMultCache = nil,
		Dirty = { All = true },
		AttrDirty = true,
		Out = {},
		Flags = {}, -- anti-cheat counters (ignored taps etc.)
	}
end

function Session.MarkDirty(session: Session, ...: string)
	for _, section in { ... } do
		session.Dirty[section] = true
	end
end

-- Toast / banner for this player. Kind: "Info" | "Success" | "Error" | "Big" | "Reward"
function Session.Notify(session: Session, kind: string, text: string, extra: { [string]: any }?)
	local payload = { Type = "Notify", Kind = kind, Text = text }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	table.insert(session.Out, payload)
end

-- One-shot visual effect for this player (and optionally everyone: payload.Broadcast = true)
function Session.Effect(session: Session, name: string, payload: { [string]: any }?)
	local out = payload or {}
	out.Type = "Effect"
	out.Name = name
	table.insert(session.Out, out)
end

function Session.TakeOut(session: Session): { any }
	local out = session.Out
	session.Out = {}
	return out
end

return Session
