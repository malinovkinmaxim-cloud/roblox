--[[
	DuoService (Phase 9)
	Two players, one level:
	  Host    = the player
	  Partner = the DOPPELGÄNGER, controlled by a real person. The partner's character counts
	            as the doppelgänger for every interaction (CYAN buttons, plates...).
	Modes:
	  Trust     - work together
	  Betrayal  - the partner MIGHT secretly be a traitor (60%). Secret goal: make the host die
	              Config.BETRAYAL_DEATHS_REQUIRED times. The host never knows until the end.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local RoleConfig = require(ReplicatedStorage.Shared.RoleConfig)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local DuoService = {}
DuoService.Invites = {} :: { [Player]: { From: Player, At: number } }
DuoService.Pairs = {} :: { [Player]: any }

local INVITE_TIMEOUT = 30
local TRAITOR_CHANCE = 0.6

local function sendState(player: Player?, state)
	if player and player.Parent then
		Net.Event("DuoState"):FireClient(player, state)
	end
end

function DuoService:Init(services)
	self.Services = services
end

function DuoService:Start()
	local limiter = RateLimiter.new(3, 6)
	Net.Event("DuoAction").OnServerEvent:Connect(function(player, action, payload)
		if not limiter:Allow(player) or type(action) ~= "string" then
			return
		end
		if action == "Invite" then
			if type(payload) == "number" then
				self:Invite(player, payload)
			end
		elseif action == "Accept" then
			if type(payload) == "number" then
				self:Accept(player, payload)
			end
		elseif action == "Decline" then
			self.Invites[player] = nil
		elseif action == "SetMode" then
			if payload == "Trust" or payload == "Betrayal" then
				self:SetMode(player, payload)
			end
		elseif action == "Start" then
			if type(payload) == "number" and payload % 1 == 0 then
				self:StartDuoLevel(player, payload)
			end
		elseif action == "Leave" then
			self:Dissolve(player, "left the duo")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.Invites[player] = nil
		for target, invite in self.Invites do
			if invite.From == player then
				self.Invites[target] = nil
			end
		end
		local pair = self.Pairs[player]
		if pair then
			-- RoundService handles the active run itself; here we only break the pair
			self.Pairs[pair.Host] = nil
			self.Pairs[pair.Partner] = nil
			local other = if player == pair.Host then pair.Partner else pair.Host
			sendState(other, { Type = "Dissolved", Text = player.DisplayName .. " left the game." })
		end
	end)
end

function DuoService:_pairState(pair, forPlayer: Player)
	return {
		Type = "Paired",
		IsHost = forPlayer == pair.Host,
		Host = pair.Host.DisplayName,
		Partner = pair.Partner.DisplayName,
		Mode = pair.Mode,
	}
end

function DuoService:Invite(player: Player, targetUserId: number)
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return
	end
	if self.Pairs[player] or self.Pairs[target] then
		sendState(player, { Type = "Error", Text = "One of you is already in a duo." })
		return
	end
	self.Invites[target] = { From = player, At = os.clock() }
	sendState(target, { Type = "Invite", From = player.DisplayName, FromUserId = player.UserId })
	sendState(player, { Type = "InviteSent", To = target.DisplayName })
end

function DuoService:Accept(player: Player, fromUserId: number)
	local invite = self.Invites[player]
	self.Invites[player] = nil
	if not invite or invite.From.UserId ~= fromUserId or os.clock() - invite.At > INVITE_TIMEOUT then
		sendState(player, { Type = "Error", Text = "That invite expired." })
		return
	end
	local host = invite.From
	if not host.Parent or self.Pairs[host] or self.Pairs[player] then
		sendState(player, { Type = "Error", Text = "Invite no longer valid." })
		return
	end
	-- nobody can be in a solo run while pairing
	for _, member in { host, player } do
		local run = self.Services.RoundService:GetRun(member)
		if run then
			self.Services.RoundService:EndRun(run, "Duo")
		end
	end
	local pair = { Host = host, Partner = player, Mode = "Trust" }
	self.Pairs[host] = pair
	self.Pairs[player] = pair
	sendState(host, self:_pairState(pair, host))
	sendState(player, self:_pairState(pair, player))
end

function DuoService:SetMode(player: Player, mode: string)
	local pair = self.Pairs[player]
	if not pair or pair.Host ~= player then
		return
	end
	pair.Mode = mode
	sendState(pair.Host, self:_pairState(pair, pair.Host))
	sendState(pair.Partner, self:_pairState(pair, pair.Partner))
end

function DuoService:Dissolve(player: Player, reason: string)
	local pair = self.Pairs[player]
	if not pair then
		return
	end
	self.Pairs[pair.Host] = nil
	self.Pairs[pair.Partner] = nil
	local run = self.Services.RoundService:GetRun(pair.Host)
	if run and run.Partner == pair.Partner and player.Parent then
		self.Services.RoundService:EndRun(run, "DuoEnded")
	end
	local other = if player == pair.Host then pair.Partner else pair.Host
	sendState(other, { Type = "Dissolved", Text = player.DisplayName .. " " .. reason .. "." })
	sendState(player, { Type = "Dissolved" })
end

function DuoService:StartDuoLevel(host: Player, levelId: number)
	local pair = self.Pairs[host]
	if not pair or pair.Host ~= host then
		return
	end
	local services = self.Services
	if not services.RoundService:IsUnlocked(host, levelId) then
		Net.Event("Toast"):FireClient(host, "The host must unlock that level first.", "Error")
		return
	end
	local def = services.LevelService:GetLevel(levelId)
	if not def or def.DuoFriendly == false then
		Net.Event("Toast"):FireClient(host, "That level can't be played in Duo.", "Error")
		return
	end
	services.RoundService:StartRun(host, levelId, {
		Force = true,
		Partner = pair.Partner,
		Mode = if pair.Mode == "Betrayal" then "DuoBetrayal" else "DuoTrust",
	})
end

---------------------------------------------------------------------------
-- Run hooks
---------------------------------------------------------------------------

function DuoService:OnRunStarted(run)
	run.RoleName = "Partner"
	run.RoleRevealed = true
	run.Traitor = nil
	run.TraitorDeaths = 0
	if run.Mode == "DuoBetrayal" and run.Instance.Rng:NextNumber() < TRAITOR_CHANCE then
		run.Traitor = run.Partner
	end
	local info = RoleConfig.Get("Partner")
	Net.Event("RoleState"):FireClient(run.Player, {
		Role = "Partner",
		Display = run.Partner.DisplayName,
		Color = info.Color,
		Description = if run.Mode == "DuoBetrayal" then "Can you trust your doppelgänger?" else info.Description,
	})
	Net.Event("RoleState"):FireClient(run.Partner, {
		Role = "Partner",
		Display = "YOU ARE THE DOPPELGÄNGER",
		Color = info.Color,
		Description = "CYAN buttons and plates only work for you. Help " .. run.Player.DisplayName .. " reach the finish!",
	})
	if run.Mode == "DuoBetrayal" then
		sendState(run.Partner, {
			Type = "Secret",
			Traitor = run.Traitor == run.Partner,
			Goal = if run.Traitor == run.Partner
				then string.format("SECRET: make %s die %d times. Don't get caught!", run.Player.DisplayName, Config.BETRAYAL_DEATHS_REQUIRED)
				else "You are LOYAL. Help your partner - they might not trust you.",
		})
		sendState(run.Player, { Type = "Secret", Traitor = false, Goal = "BETRAYAL MODE: your doppelgänger might be a traitor..." })
	end
	self:OnPartnerSpawned(run)
end

-- Doppel visuals on the partner's character (the partner is "the double")
function DuoService:OnPartnerSpawned(run)
	local partner = run.Partner
	local character = partner and partner.Character
	if not character or character:FindFirstChild("DoppelHighlight") then
		return
	end
	local color = RoleConfig.Get("Partner").Color
	local highlight = Instance.new("Highlight")
	highlight.Name = "DoppelHighlight"
	highlight.FillColor = color
	highlight.FillTransparency = 0.82
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0.25
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
	local head = character:FindFirstChild("Head")
	if head then
		local tag = Instance.new("BillboardGui")
		tag.Name = "DoppelTag"
		tag.Size = UDim2.new(7, 0, 1, 0)
		tag.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		tag.MaxDistance = 100
		tag.Adornee = head
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.3
		label.Text = "DOPPELGÄNGER"
		label.Parent = tag
		tag.Parent = character
	end
end

local function removePartnerVisuals(player: Player?)
	local character = player and player.Character
	if not character then
		return
	end
	for _, name in { "DoppelHighlight", "DoppelTag" } do
		local child = character:FindFirstChild(name)
		if child then
			child:Destroy()
		end
	end
end

function DuoService:OnRunEnded(run, _reason: string)
	if run.Partner then
		removePartnerVisuals(run.Partner)
	end
end

function DuoService:OnPartnerLeft(run)
	local partner = run.Partner
	local rounds = self.Services.RoundService
	if rounds.RunsByPlayer[partner] == run then
		rounds.RunsByPlayer[partner] = nil
	end
	run.Partner = nil
	run.Mode = "Solo"
	run.Traitor = nil
	if run.Player.Parent and not run.Ended then
		Net.Event("Toast"):FireClient(run.Player, "Your partner left. An AI doppelgänger takes over!", "Info")
		self.Services.DoppelgangerService:SpawnForRun(run)
	end
end

function DuoService:OnPlayerDied(run, player: Player)
	if run.Traitor and player == run.Player then
		run.TraitorDeaths = (run.TraitorDeaths or 0) + 1
		sendState(run.Traitor, {
			Type = "SecretProgress",
			Count = run.TraitorDeaths,
			Goal = Config.BETRAYAL_DEATHS_REQUIRED,
		})
	end
end

function DuoService:OnCheckpoint(_run, _index: number, _byPlayer: Player?) end

function DuoService:GetBetrayalSummary(run, _forPlayer: Player)
	if run.Mode ~= "DuoBetrayal" then
		return nil
	end
	local isTraitor = run.Traitor ~= nil
	return {
		IsTraitor = isTraitor,
		Succeeded = isTraitor and (run.TraitorDeaths or 0) >= Config.BETRAYAL_DEATHS_REQUIRED,
		Deaths = run.TraitorDeaths or 0,
		Goal = Config.BETRAYAL_DEATHS_REQUIRED,
		PartnerName = run.Partner and run.Partner.DisplayName or "?",
	}
end

return DuoService
