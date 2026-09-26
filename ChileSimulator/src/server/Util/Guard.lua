--[[
	Guard - the only way remotes are connected on the server.

	Guard.On(remoteName, ratePerSecond, handler)
	  * ignores players whose data is not loaded yet
	  * per-player, per-remote token bucket (floods are dropped silently and counted)
	  * handler runs in pcall; errors are logged, never crash the server
	  * handler(session, player, ...args) - args are UNTRUSTED, validate them in the handler
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local Guard = {}

local buckets: { [Player]: { [string]: { Tokens: number, Last: number } } } = {}
local getSession: ((Player) -> any)? = nil

function Guard.SetSessionProvider(fn: (Player) -> any)
	getSession = fn
end

function Guard.Forget(player: Player)
	buckets[player] = nil
end

local function allow(player: Player, name: string, rate: number): boolean
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local b = perPlayer[name]
	local burst = math.max(2, rate * 2)
	if not b then
		b = { Tokens = burst, Last = now }
		perPlayer[name] = b
	end
	b.Tokens = math.min(burst, b.Tokens + (now - b.Last) * rate)
	b.Last = now
	if b.Tokens < 1 then
		return false
	end
	b.Tokens -= 1
	return true
end

function Guard.On(name: string, rate: number, handler: (any, Player, ...any) -> ())
	local remote = Net.Event(name)
	remote.OnServerEvent:Connect(function(player: Player, ...)
		local session = getSession and getSession(player)
		if not session or session.Leaving then
			return
		end
		if not allow(player, name, rate) then
			session.Flags.RemoteFlood = (session.Flags.RemoteFlood or 0) + 1
			return
		end
		local ok, err = pcall(handler, session, player, ...)
		if not ok then
			warn(string.format("[Guard] %s from %s failed: %s", name, player.Name, tostring(err)))
		end
	end)
end

return Guard
