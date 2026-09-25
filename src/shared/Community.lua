-- Server-only: Roblox group membership bonus and badges. Everything is off while the IDs in
-- Config are 0, so the game works before the group and badges exist on the Creator Dashboard.
local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")

local Config = require(script.Parent.Config)

local Community = {}

local awarded = {}

-- Sets the "InGroup" attribute (used for the Paws bonus and the hub banner)
local function checkGroup(player)
	if Config.GROUP_ID == 0 then
		player:SetAttribute("InGroup", false)
		return
	end
	local ok, inGroup = pcall(function()
		return player:IsInGroup(Config.GROUP_ID)
	end)
	player:SetAttribute("InGroup", ok and inGroup == true)
end

function Community.pawsMultiplier(player)
	return if player:GetAttribute("InGroup") == true then 1 + Config.GROUP_PAWS_BONUS else 1
end

-- Awards a badge from Config.BADGES by name; safe to call often (skips owned badges)
function Community.award(player, badgeName)
	local badgeId = Config.BADGES[badgeName]
	if not badgeId or badgeId == 0 then
		return
	end
	awarded[player] = awarded[player] or {}
	if awarded[player][badgeName] then
		return
	end
	awarded[player][badgeName] = true
	task.spawn(function()
		local ok, err = pcall(function()
			if not BadgeService:UserHasBadgeAsync(player.UserId, badgeId) then
				BadgeService:AwardBadge(player.UserId, badgeId)
			end
		end)
		if not ok then
			awarded[player][badgeName] = nil
			warn(`[HopPals] Could not award badge {badgeName}:`, err)
		end
	end)
end

function Community.start()
	Players.PlayerAdded:Connect(checkGroup)
	for _, player in Players:GetPlayers() do
		task.spawn(checkGroup, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		awarded[player] = nil
	end)
end

return Community
