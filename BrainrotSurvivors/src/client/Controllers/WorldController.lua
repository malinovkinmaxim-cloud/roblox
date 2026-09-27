--[[
	WorldController - small client-side world touches:
	  * other players who are in a run are drawn as semi-transparent "ghosts" (every player
	    fights their own horde, so ghosts show that others are surviving too)
	  * spinning / bobbing landmarks (parts with a Spin or Bob attribute, e.g. the floating brain)
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
			table.insert(self.Spinners, { Part = d, Base = d.CFrame, Spin = d:GetAttribute("Spin") or 0, Bob = d:GetAttribute("Bob") or 0 })
		end
	end
end

function WorldController:UpdateGhosts()
	local localPlayer = Players.LocalPlayer
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer and player.Character then
			local ghost = player:GetAttribute("InRun") == true
			local value = if ghost then GHOST else 0
			for _, d in player.Character:GetDescendants() do
				if d:IsA("BasePart") and d.LocalTransparencyModifier ~= value then
					d.LocalTransparencyModifier = value
				end
			end
		end
	end
end

function WorldController:Update(dt: number)
	local now = os.clock()
	for _, s in self.Spinners do
		s.Part.CFrame = s.Base * CFrame.new(0, math.sin(now * 1.5) * s.Bob, 0) * CFrame.Angles(0, now * s.Spin, 0)
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
	local _ = dt
end

function WorldController:Start()
	task.delay(2, function()
		self:FindSpinners()
	end)
	RunService.Heartbeat:Connect(function(dt)
		self:Update(dt)
	end)
end

return WorldController
