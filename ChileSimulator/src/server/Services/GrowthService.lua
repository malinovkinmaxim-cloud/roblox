--[[
	GrowthService - remotes of the core loop: Tap, BuyUpgrade, BuyGemUpgrade, Rebirth.
	All validation lives in Logic/Growth (unit-tested in tests/run.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Logic = script.Parent.Parent.Logic
local Growth = require(Logic.Growth)
local Session = require(Logic.Session)
local Guard = require(script.Parent.Parent.Util.Guard)

local GrowthService = {}

function GrowthService:Init(services)
	self.Services = services
end

function GrowthService:Start()
	local PlayerService = self.Services.PlayerService

	-- The client batches taps every Config.Tap.ClientFlushInterval, so ~10 remotes per second.
	-- Guard drops floods above 30/s; Growth.Tap enforces the real tap-rate limit.
	Guard.On("Tap", 30, function(session, _player, count)
		local accepted = Growth.Tap(session, count, PlayerService:World(), os.clock())
		if accepted > 0 and session.Data.Tutorial < 1 and session.Data.Taps >= 10 then
			session.Data.Tutorial = 1
			Session.MarkDirty(session, "Stats")
		end
		-- a client that keeps hammering far above the limit is only logged (never trusted)
		if (session.Flags.Throttled or 0) > Config.Tap.MaxPerSecond * 60 and not session.Flags.Warned then
			session.Flags.Warned = 1
			warn(string.format("[AntiCheat] %s sends taps far above the limit (ignored)", session.Name))
		end
	end)

	Guard.On("BuyUpgrade", 8, function(session, _player, kind)
		local ok, err = Growth.BuyUpgrade(session, kind)
		if not ok and err then
			Session.Notify(session, "Error", err)
		end
	end)

	Guard.On("BuyGemUpgrade", 6, function(session, _player, id)
		local ok, err = Growth.BuyGemUpgrade(session, id)
		if not ok and err then
			Session.Notify(session, "Error", err)
		end
	end)

	Guard.On("Rebirth", 1, function(session, _player)
		local ok, err = Growth.Rebirth(session, PlayerService:World())
		if not ok and err then
			Session.Notify(session, "Error", err)
		end
	end)
end

return GrowthService
