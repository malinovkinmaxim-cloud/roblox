--[[
	RateLimiter
	Token bucket per player. Used to protect every client -> server remote.
]]

local Players = game:GetService("Players")

local RateLimiter = {}
RateLimiter.__index = RateLimiter

local allLimiters = setmetatable({}, { __mode = "k" })

function RateLimiter.new(maxPerSecond: number, burst: number?)
	local self = setmetatable({
		Rate = maxPerSecond,
		Burst = burst or maxPerSecond,
		Buckets = {},
	}, RateLimiter)
	allLimiters[self] = true
	return self
end

function RateLimiter:Allow(player: Player): boolean
	local now = os.clock()
	local bucket = self.Buckets[player]
	if not bucket then
		bucket = { Tokens = self.Burst, Last = now }
		self.Buckets[player] = bucket
	end
	bucket.Tokens = math.min(self.Burst, bucket.Tokens + (now - bucket.Last) * self.Rate)
	bucket.Last = now
	if bucket.Tokens >= 1 then
		bucket.Tokens -= 1
		return true
	end
	return false
end

Players.PlayerRemoving:Connect(function(player)
	for limiter in pairs(allLimiters) do
		limiter.Buckets[player] = nil
	end
end)

return RateLimiter
