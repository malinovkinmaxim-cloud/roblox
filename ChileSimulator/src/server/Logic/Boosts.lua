--[[
	Boosts (logic) - inventory, activation, timers, multipliers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoostConfig = require(Shared.BoostConfig)

local Session = require(script.Parent.Session)

local Boosts = {}

function Boosts.Add(session, boostId: string, count: number?): boolean
	local def = BoostConfig.Boosts[boostId]
	if not def then
		return false
	end
	local inv = session.Data.Boosts.Inventory
	inv[boostId] = math.min(9999, (inv[boostId] or 0) + math.max(1, math.floor(count or 1)))
	Session.MarkDirty(session, "Boosts")
	return true
end

function Boosts.Activate(session, boostId: string): (boolean, string?)
	local def = BoostConfig.Boosts[boostId]
	if not def then
		return false, "Unknown boost"
	end
	local inv = session.Data.Boosts.Inventory
	if (inv[boostId] or 0) <= 0 then
		return false, "You don't have this boost"
	end
	local active = session.Data.Boosts.Active
	local left = active[boostId] or 0
	if left + def.Duration > BoostConfig.MaxStackedSeconds then
		return false, "Boost timer is full"
	end
	inv[boostId] -= 1
	if inv[boostId] <= 0 then
		inv[boostId] = nil
	end
	active[boostId] = left + def.Duration
	Session.MarkDirty(session, "Boosts", "Rates")
	Session.Notify(session, "Success", def.Icon .. " " .. def.Name .. " ACTIVATED!")
	Session.Effect(session, "Boost", { Id = boostId })
	return true
end

-- Timers only run while online (called once per server tick)
function Boosts.Tick(session, dt: number)
	local active = session.Data.Boosts.Active
	local changed = false
	for id, left in active do
		local newLeft = left - dt
		if newLeft <= 0 then
			active[id] = nil
			changed = true
			local def = BoostConfig.Boosts[id]
			if def then
				Session.Notify(session, "Info", def.Icon .. " " .. def.Name .. " ended")
			end
		else
			active[id] = newLeft
		end
	end
	if changed then
		Session.MarkDirty(session, "Boosts", "Rates")
	end
end

-- Product of all active boost multipliers
function Boosts.Multipliers(session): (number, number, boolean)
	local height, coins, autoTap = 1, 1, false
	for id in session.Data.Boosts.Active do
		local def = BoostConfig.Boosts[id]
		if def then
			height *= def.Height or 1
			coins *= def.Coins or 1
			autoTap = autoTap or def.AutoTap == true
		end
	end
	return height, coins, autoTap
end

return Boosts
