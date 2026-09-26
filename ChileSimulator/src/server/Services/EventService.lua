--[[
	EventService - short random server events (MEGA GROWTH, GOLDEN MINUTE, GIANT MODE,
	TINY MODE, DOUBLE TAP).

	State is replicated through Workspace attributes so every client (and late joiners) can
	show the banner + countdown and apply the GIANT / TINY visual:
	  Workspace.EventId      string ("" = none)
	  Workspace.EventEndsAt  number (workspace:GetServerTimeNow() based)
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventConfig = require(Shared.EventConfig)

local Logic = script.Parent.Parent.Logic
local Session = require(Logic.Session)
local Rewards = require(Logic.Rewards)

local EventService = {}

function EventService:Init(services)
	self.Services = services
	self.Rng = Random.new()
	self.Current = nil -- { Id, Def, EndsAt (os.clock) }
	Workspace:SetAttribute("EventId", "")
	Workspace:SetAttribute("EventEndsAt", 0)
end

-- The world context every gameplay calculation uses
function EventService:World()
	local current = self.Current
	return {
		Now = os.time(),
		Event = if current and os.clock() < current.EndsAt then current.Def else nil,
	}
end

function EventService:Pick(): string
	local total = 0
	for _, id in EventConfig.Order do
		total += EventConfig.Events[id].Weight
	end
	local r = self.Rng:NextNumber(0, total)
	for _, id in EventConfig.Order do
		r -= EventConfig.Events[id].Weight
		if r <= 0 then
			return id
		end
	end
	return EventConfig.Order[1]
end

function EventService:StartEvent(id: string)
	local def = EventConfig.Events[id]
	if not def then
		return
	end
	if self.Current then
		self:EndEvent()
	end
	local PlayerService = self.Services.PlayerService
	for _, session in PlayerService:GetSessions() do
		session.EventTapped = false
		Session.MarkDirty(session, "Rates")
	end
	self.Current = { Id = id, Def = def, EndsAt = os.clock() + def.Duration }
	Workspace:SetAttribute("EventId", id)
	Workspace:SetAttribute("EventEndsAt", Workspace:GetServerTimeNow() + def.Duration)
	PlayerService:NotifyAll("Big", def.Icon .. " " .. def.Name .. "! " .. def.Text, { Sound = "Event", Event = id })
end

function EventService:EndEvent()
	local current = self.Current
	if not current then
		return
	end
	self.Current = nil
	Workspace:SetAttribute("EventId", "")
	Workspace:SetAttribute("EventEndsAt", 0)
	local world = self:World()
	for _, session in self.Services.PlayerService:GetSessions() do
		Session.MarkDirty(session, "Rates")
		if session.EventTapped then
			session.EventTapped = false
			session.Data.Stats.Events += 1
			local labels = Rewards.Grant(session, { Kind = "Gems", Amount = EventConfig.ParticipationGems }, world, self.Rng)
			Rewards.CheckAchievements(session)
			Session.Notify(session, "Reward", current.Def.Name .. " is over!  " .. table.concat(labels, " "), { Sound = "Reward" })
		end
	end
end

function EventService:Start()
	task.spawn(function()
		local nextAt = os.clock() + EventConfig.FirstDelay
		while true do
			task.wait(0.5)
			if self.Current then
				if os.clock() >= self.Current.EndsAt then
					self:EndEvent()
					nextAt = os.clock() + self.Rng:NextNumber(EventConfig.MinInterval, EventConfig.MaxInterval)
				end
			elseif os.clock() >= nextAt then
				-- no point running an event for an empty server
				if next(self.Services.PlayerService:GetSessions()) then
					self:StartEvent(self:Pick())
				else
					nextAt = os.clock() + 30
				end
			end
		end
	end)
end

return EventService
