--[[
	WorldController - small client-side world touches:
	  * other players who are in a run are drawn as semi-transparent "ghosts" (every player
	    fights their own horde, so ghosts show that others are surviving too); your party
	    members stay solid
	  * spinning / bobbing landmarks (parts with a Spin or Bob attribute, e.g. the floating orb;
	    BobPhase / BobSpeed let groups move together or in turn, like the two hands of THE
	    GREAT BALANCE in 67 LAND)
	  * a boss "beat" (Music setting) while a boss is alive
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldController = {}

local GHOST = 0.65

function WorldController:Init(controllers)
	self.C = controllers
	self.Spinners = {}
	self.NextGhostCheck = 0
	self.NextBeat = 0
end

function WorldController:FindSpinners()
	local map = Workspace:FindFirstChild("Map")
	if not map then
		return
	end
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and (d:GetAttribute("Spin") or d:GetAttribute("Bob")) then
			table.insert(self.Spinners, {
				Part = d,
				Base = d.CFrame,
				Spin = d:GetAttribute("Spin") or 0,
				Bob = d:GetAttribute("Bob") or 0,
				Phase = d:GetAttribute("BobPhase") or 0,
				Speed = d:GetAttribute("BobSpeed") or 1.5,
			})
		end
	end
end

function WorldController:UpdateGhosts()
	local localPlayer = Players.LocalPlayer
	local party = {}
	for _, name in self.C.RunClient.Party or {} do
		party[name] = true
	end
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer and player.Character then
			local ghost = player:GetAttribute("InRun") == true and not party[player.DisplayName]
			local value = if ghost then GHOST else 0
			for _, d in player.Character:GetDescendants() do
				if d:IsA("BasePart") and d.LocalTransparencyModifier ~= value then
					d.LocalTransparencyModifier = value
				end
			end
		end
	end
end

function WorldController:Update()
	local now = os.clock()
	for _, s in self.Spinners do
		-- the bob moves along the world's up (tilted parts of one group stay together)
		s.Part.CFrame = CFrame.new(0, math.sin(now * s.Speed + s.Phase) * s.Bob, 0) * s.Base * CFrame.Angles(0, now * s.Spin, 0)
	end
	if now >= self.NextGhostCheck then
		self.NextGhostCheck = now + 0.5
		self:UpdateGhosts()
	end
	local run = self.C.RunClient
	if run.Active and run.Boss and not run.Paused and self.C.ClientData:Setting("Music") and now >= self.NextBeat then
		self.NextBeat = now + 0.5
		self.C.SoundController:Play("Beat")
	end
end

-- VIP chat tag (the server marks owners with the VIP attribute)
function WorldController:HookChat()
	local ok, TextChatService = pcall(function()
		return game:GetService("TextChatService")
	end)
	if not ok or not TextChatService then
		return
	end
	pcall(function()
		(TextChatService :: any).OnIncomingMessage = function(message)
			local source = message.TextSource
			local player = source and Players:GetPlayerByUserId(source.UserId)
			if player and player:GetAttribute("VIP") then
				local props = Instance.new("TextChatMessageProperties")
				props.PrefixText = "<font color='#FFD23C'>[VIP]</font> " .. message.PrefixText
				return props
			end
			return nil
		end
	end)
end

function WorldController:Start()
	self:HookChat()
	task.delay(2, function()
		self:FindSpinners()
	end)
	RunService.Heartbeat:Connect(function()
		self:Update()
	end)
end

return WorldController
