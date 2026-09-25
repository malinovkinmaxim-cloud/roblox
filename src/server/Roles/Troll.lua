--[[
	Troll - Phase 6 (rare)
	Pretends to be an Ally. Never unfair - it always shows tells:
	  - it hesitates for a moment before obeying (Config.TROLL_HESITATION)
	  - its outline flickers magenta every few seconds
	  - it can stand on FAKE platforms without breaking them, but they shimmer under it
	Betrayals (then it reveals itself: "DOPPELGÄNGER ... IS ... THE TROLL."):
	  - goes to a different target than the one you chose (prefers trap buttons)
	  - holds the plate... and suddenly walks away
	  - lures you onto fake platforms by standing on them and waving
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ally = require(script.Parent.Ally)
local RoleBase = require(script.Parent.RoleBase)

local Troll = RoleBase.Extend("Troll", Ally)
Troll.ReplaysPlayer = true

local MAGENTA = Color3.fromRGB(255, 70, 200)

function Troll.new(ctx)
	local self = setmetatable(Ally.new(ctx), Troll)
	self.Pending = nil -- delayed command (hesitation tell)
	self.NextGlitch = os.clock() + self.Rng:NextNumber(Config.TROLL_GLITCH_INTERVAL[1], Config.TROLL_GLITCH_INTERVAL[2])
	self.NextLure = os.clock() + self.Rng:NextNumber(Config.TROLL_LURE_INTERVAL[1], Config.TROLL_LURE_INTERVAL[2])
	self.AbandonAt = nil
	self.Luring = false
	self.LureUntil = 0
	self.Betrayed = false
	self.Helped = true -- honest help never reveals a troll (Ally reveals itself on first help)
	return self
end

function Troll:Start()
	Ally.Start(self)
	self.Actor.Ghost = true -- fake platforms don't break under a troll
end

function Troll:Stop()
	Ally.Stop(self)
	self.Actor.Ghost = false
end

function Troll:_revealed(): boolean
	return self.Run.RoleRevealed == true
end

function Troll:_betray()
	self.Betrayed = true
	self.Actor:SetEmote("Laugh")
	task.delay(1.4, function()
		if not self.Stopped and self.Actor.Emote == "Laugh" then
			self.Actor:SetEmote(nil)
		end
	end)
	self:Reveal()
end

---------------------------------------------------------------------------
-- Commands (with the hesitation tell)
---------------------------------------------------------------------------

function Troll:UseAbility(): (boolean, string?)
	local now = os.clock()
	if now - self.LastCommand < Config.ALLY_COOLDOWN or self.Pending then
		return false, nil
	end
	if not self.Actor:IsControllable() then
		return false, "Your doppelgänger is not here right now."
	end
	local target = self:FindTarget()
	if not target then
		return false, "Face a CYAN button, a plate or a platform, then SEND."
	end
	self.LastCommand = now
	self.Pending = { Target = target, At = now + Config.TROLL_HESITATION }
	return true
end

function Troll:_decideCommand(target)
	local chance = if self:_revealed() then Config.TROLL_REVEALED_BETRAY_CHANCE else Config.TROLL_BETRAY_CHANCE
	if self.Rng:NextNumber() >= chance then
		self.AbandonAt = nil
		Ally.SendTo(self, target)
		return
	end
	-- betrayal #1: a different target, trap buttons first
	local wrong, wrongScore = nil, math.huge
	local root = self:GetPlayerRoot()
	for _, element in self.Instance.AllyTargets do
		if element ~= target and root then
			local distance = (element.Part.Position - root.Position).Magnitude
			if distance < Config.ALLY_SEND_RANGE * 1.3 then
				local score = distance - (if element.Bad then 1000 else 0)
				if score < wrongScore then
					wrong, wrongScore = element, score
				end
			end
		end
	end
	if wrong and (wrong.Bad or self.Rng:NextNumber() < 0.5) then
		self.AbandonAt = nil
		Ally.SendTo(self, wrong)
		self.BetrayOnArrive = true
		return
	end
	-- betrayal #2: obey... then walk away
	Ally.SendTo(self, target)
	self.AbandonAt = os.clock() + self.Rng:NextNumber(1.2, 2.6)
end

function Troll:_onArrived(thenMode: string, now: number)
	if thenMode == "Hold" and self.BetrayOnArrive then
		self.BetrayOnArrive = false
		self.Mode = "Hold"
		self.HoldPosition = self.Actor.Position
		self:_betray()
		return
	end
	if thenMode == "Return" and self.Luring then
		self.Luring = false
	end
	Ally._onArrived(self, thenMode, now)
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

function Troll:Update(dt: number, now: number)
	local actor = self.Actor
	if not actor:IsControllable() or not self.Run.AIEnabled then
		Ally.Update(self, dt, now)
		return
	end

	-- tell: magenta flicker
	if now >= self.NextGlitch then
		self.NextGlitch = now + self.Rng:NextNumber(Config.TROLL_GLITCH_INTERVAL[1], Config.TROLL_GLITCH_INTERVAL[2])
		actor:FlashColor(MAGENTA, 0.18)
	end

	-- hesitation finished -> decide
	if self.Pending and now >= self.Pending.At then
		local target = self.Pending.Target
		self.Pending = nil
		self:_decideCommand(target)
	end

	-- sudden stop: leaves the plate you trusted it with
	if self.AbandonAt and self.Mode == "Hold" and now >= self.AbandonAt then
		self.AbandonAt = nil
		self:Recall()
		self:_betray()
	end

	-- lure: stand on a fake platform ahead of you and wave
	if self.Mode == "Follow" and now >= self.NextLure then
		self.NextLure = now + self.Rng:NextNumber(Config.TROLL_LURE_INTERVAL[1], Config.TROLL_LURE_INTERVAL[2])
		self:_tryLure(now)
	end
	if self.Luring and self.Mode == "Hold" and now >= self.LureUntil then
		actor:SetEmote(nil)
		self:Recall()
	end

	Ally.Update(self, dt, now)
end

function Troll:_tryLure(now: number)
	local root = self:GetPlayerRoot()
	if not root then
		return
	end
	local best, bestDistance = nil, math.huge
	for _, element in self.Instance.Elements do
		if element.Type == "Fake" and element.IsFake and element.Lure and not element.Revealed then
			local offset = element.Part.Position - root.Position
			local distance = offset.Magnitude
			if distance < 40 and offset.X > -2 and distance < bestDistance then
				best, bestDistance = element, distance
			end
		end
	end
	if best then
		Ally.SendTo(self, best)
		self.Luring = true
		self.LureUntil = now + 4.5
		task.delay(0.9, function()
			if self.Luring and not self.Stopped then
				self.Actor:SetEmote("Wave")
			end
		end)
	end
end

function Troll:OnSourcePressed(source, presser)
	-- pressing a trap button on purpose is a betrayal
	if presser and presser.Actor == self.Actor and source.Bad and not self:_revealed() then
		self:_betray()
	end
end

function Troll:OnPlayerRespawn(checkpoint)
	self.Pending = nil
	self.AbandonAt = nil
	self.Luring = false
	self.BetrayOnArrive = false
	Ally.OnPlayerRespawn(self, checkpoint)
	self.Actor.Ghost = true
end

function Troll:OnDoppelRespawned()
	Ally.OnDoppelRespawned(self)
	self.Actor.Ghost = true
end

return Troll
