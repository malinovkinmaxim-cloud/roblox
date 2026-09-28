--[[
	Guard - protection for RemoteEvent handlers.

	Guard.Connect(remote, { Rate = n per second, Burst = m }, handler) wraps a handler with:
	  * a token-bucket rate limit per player (spam is dropped, heavy spam is logged)
	  * pcall (a bad request never breaks the handler for everyone)
	Type checks helpers: Guard.Int, Guard.Str, Guard.Bool
]]

local Players = game:GetService("Players")

local Guard = {}

local buckets = {} -- [player][remoteName] = { Tokens, Last }
local strikes = {}

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
	strikes[player] = nil
end)

local function allow(player: Player, name: string, rate: number, burst: number): boolean
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local b = perPlayer[name]
	if not b then
		b = { Tokens = burst, Last = now }
		perPlayer[name] = b
	end
	b.Tokens = math.min(burst, b.Tokens + (now - b.Last) * rate)
	b.Last = now
	if b.Tokens < 1 then
		strikes[player] = (strikes[player] or 0) + 1
		if strikes[player] % 50 == 0 then
			warn(string.format("[Guard] %s is spamming %s (%d dropped)", player.Name, name, strikes[player]))
		end
		return false
	end
	b.Tokens -= 1
	return true
end

export type Limits = { Rate: number?, Burst: number? }

function Guard.Connect(remote: RemoteEvent, limits: Limits, handler: (Player, ...any) -> ())
	local rate = limits.Rate or 5
	local burst = limits.Burst or math.max(2, rate)
	local name = remote.Name
	return remote.OnServerEvent:Connect(function(player: Player, ...)
		if typeof(player) ~= "Instance" or not player.Parent then
			return
		end
		if not allow(player, name, rate, burst) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Guard] %s from %s failed: %s", name, player.Name, tostring(err)))
		end
	end)
end

function Guard.Int(v: any, lo: number, hi: number): number?
	if type(v) ~= "number" or v ~= v or v ~= math.floor(v) or v < lo or v > hi then
		return nil
	end
	return v
end

function Guard.Str(v: any, maxLen: number?): string?
	if type(v) ~= "string" or #v > (maxLen or 64) then
		return nil
	end
	return v
end

function Guard.Bool(v: any): boolean?
	if type(v) ~= "boolean" then
		return nil
	end
	return v
end

return Guard
