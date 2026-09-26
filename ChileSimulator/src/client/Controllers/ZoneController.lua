--[[
	ZoneController - how each world LOOKS for you, plus your own gates.

	  * lighting / atmosphere / colour grading tween to the zone you stand in
	    (Tiny Land bright & green ... Space at night with stars ... Galaxy purple)
	  * gates of unlocked zones open locally (the server still verifies position + unlock)
	  * the VIP lounge door opens for VIP owners
	  * "Welcome to <zone>!" the first time you enter a zone in a session
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneConfig = require(Shared.ZoneConfig)
local Format = require(Shared.Util.Format)

local LocalPlayer = Players.LocalPlayer

local ZoneController = {}

local function ensure(className: string, name: string, parent: Instance): any
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

function ZoneController:Init(controllers)
	self.Controllers = controllers
	self.CurrentZone = 0
	self.Visited = {}
	self.Atmosphere = ensure("Atmosphere", "ChileAtmosphere", Lighting)
	self.Grade = ensure("ColorCorrectionEffect", "ChileGrade", Lighting)
	self.Bloom = ensure("BloomEffect", "ChileBloom", Lighting)
	self.Bloom.Intensity = 0.6
	self.Bloom.Size = 30
	self.Bloom.Threshold = 1.6
	self.Sky = ensure("Sky", "ChileSky", Lighting)
	self.Sky.StarCount = 3000
	self.Sky.CelestialBodiesShown = true
end

function ZoneController:ApplyZone(index: number, instant: boolean?)
	local zone = ZoneConfig.Zones[index]
	if not zone then
		return
	end
	local l = zone.Lighting
	local info = TweenInfo.new(if instant then 0 else 2.5, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, { ClockTime = l.ClockTime, Brightness = l.Brightness }):Play()
	TweenService:Create(self.Atmosphere, info, {
		Density = l.Density,
		Haze = l.Haze,
		Color = l.Color,
		Decay = l.Color:Lerp(Color3.new(0, 0, 0), 0.3),
		Glare = if index >= 6 then 0 else 0.3,
		Offset = 0.1,
	}):Play()
	TweenService:Create(self.Grade, info, { TintColor = l.Tint, Saturation = l.Saturation, Contrast = 0.05 }):Play()
end

function ZoneController:RefreshGates()
	local stats = self.Controllers.ClientData:Get("Stats")
	local passes = self.Controllers.ClientData:Get("Passes") or {}
	local unlocked = stats and stats.HighestZone or 1
	local map = Workspace:FindFirstChild("ChileMap")
	if not map then
		return
	end
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == "Gate" then
			local zone = descendant:GetAttribute("Zone")
			local open = type(zone) == "number" and zone <= unlocked
			descendant.CanCollide = not open
			descendant.Transparency = if open then 0.85 else 0.35
			local label = descendant:FindFirstChild("LockLabel")
			if label and label:IsA("BillboardGui") then
				label.Enabled = not open
			end
		elseif descendant:IsA("BasePart") and descendant.Name == "VIPDoor" then
			descendant.CanCollide = passes.VIP ~= true
			descendant.Transparency = if passes.VIP then 0.8 else 0.3
		end
	end
end

function ZoneController:Start()
	self:ApplyZone(1, true)
	local data = self.Controllers.ClientData
	data.Changed:Connect(function(section)
		if section == "Stats" or section == "Passes" then
			local stats = data:Get("Stats")
			local unlocked = stats and stats.HighestZone or 1
			if unlocked ~= self.LastUnlocked or section == "Passes" then
				self.LastUnlocked = unlocked
				self:RefreshGates()
			end
		end
	end)
	-- the map is built by the server; it may replicate a bit after we start
	task.spawn(function()
		Workspace:WaitForChild("ChileMap", 30)
		task.wait(1)
		self:RefreshGates()
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			local character = LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local index = ZoneConfig.IndexFromX(root.Position.X)
				if index ~= self.CurrentZone then
					self.CurrentZone = index
					self:ApplyZone(index)
					if not self.Visited[index] then
						self.Visited[index] = true
						if index > 1 then
							local zone = ZoneConfig.Zones[index]
							self.Controllers.NotifyController:Notify({
								Kind = "Success",
								Text = string.format("🌍 Welcome to %s!  %s growth here", zone.Name, Format.Mult(zone.Multiplier)),
								Sound = "NewZone",
							})
						end
					end
				end
			end
		end
	end)
end

return ZoneController
