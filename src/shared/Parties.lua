-- Party sizes. Every party size has its own level packs and its own progress, so clearing
-- Easy as SOLO opens Medium for SOLO only - DUO still starts from Easy.
local Parties = {}

Parties.order = { "solo", "duo", "squad", "party" }

Parties.list = {
	solo = { id = "solo", name = "SOLO", min = 1, max = 1, color = Color3.fromRGB(95, 155, 240) },
	duo = { id = "duo", name = "DUO", min = 2, max = 2, color = Color3.fromRGB(80, 195, 110) },
	squad = { id = "squad", name = "SQUAD 3-4", min = 3, max = 4, color = Color3.fromRGB(255, 150, 50) },
	party = { id = "party", name = "PARTY 5-8", min = 5, max = 8, color = Color3.fromRGB(235, 90, 170) },
}

function Parties.get(id)
	if type(id) == "string" then
		return Parties.list[id]
	end
	return nil
end

function Parties.forCount(count)
	if count <= 1 then
		return Parties.list.solo
	elseif count == 2 then
		return Parties.list.duo
	elseif count <= 4 then
		return Parties.list.squad
	end
	return Parties.list.party
end

-- Friends loop: rewards grow with the number of players who reach the finish TOGETHER
function Parties.squadMultiplier(finishers)
	if finishers >= 5 then
		return 2.5
	elseif finishers >= 3 then
		return 2
	elseif finishers == 2 then
		return 1.5
	end
	return 1
end

return Parties
