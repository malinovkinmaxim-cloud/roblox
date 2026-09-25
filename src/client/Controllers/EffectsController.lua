--[[
	EffectsController
	  - animates spinning beams locally (smooth, deterministic from server time; the server checks hits with math)
	  - lobby pads (PLAY / DUO / SKINS) open the matching menu
	  - applies the Hints / ReducedEffects settings locally
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EffectsController = {}

local player = Players.LocalPlayer
local beams: { [BasePart]: boolean } = {}

function EffectsController:Init(controllers)
	self.Controllers = controllers
end

function EffectsController:Start()
	-- spinning beams
	local function addBeam(beam: Instance)
		if beam:IsA("BasePart") then
			beams[beam] = true
		end
	end
	CollectionService:GetInstanceAddedSignal("DoppelSpinBeam"):Connect(addBeam)
	CollectionService:GetInstanceRemovedSignal("DoppelSpinBeam"):Connect(function(beam)
		beams[beam :: BasePart] = nil
	end)
	for _, beam in CollectionService:GetTagged("DoppelSpinBeam") do
		addBeam(beam)
	end
	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for beam in beams do
			local pivot = beam:GetAttribute("PivotCFrame")
			local start = beam:GetAttribute("SpinStart")
			if typeof(pivot) == "CFrame" and type(start) == "number" then
				local angle = (beam:GetAttribute("StartAngle") or 0) + (beam:GetAttribute("Speed") or 0) * (now - start)
				beam.CFrame = pivot * CFrame.Angles(0, angle, 0)
			end
		end
	end)

	-- lobby pads
	task.spawn(function()
		local current: string? = nil
		while true do
			task.wait(0.25)
			local action = self:_padUnderPlayer()
			if action ~= current then
				current = action
				if action and not self.Controllers.ClientState.Run then
					local panel = if action == "Shop" then "Shop" elseif action == "Duo" then "Duo" else "Play"
					self.Controllers.MenuController:OpenPanel(panel)
				end
			end
		end
	end)

	-- settings
	self.Controllers.ClientState.Changed:Connect(function(key)
		if key == "Profile" then
			self:_applySettings()
		end
	end)
	Workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ParticleEmitter") and descendant.Name == "Aura" and self.Reduced then
			descendant.Enabled = false
		elseif descendant:IsA("BillboardGui") and descendant.Name == "SignGui" and self.HideHints then
			descendant.Enabled = false
		end
	end)
end

function EffectsController:_padUnderPlayer(): string?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local lobby = Workspace:FindFirstChild("Lobby")
	if not root or not lobby then
		return nil
	end
	for _, part in lobby:GetChildren() do
		local action = part:GetAttribute("LobbyAction")
		if action and part:IsA("BasePart") then
			local offset = part.CFrame:PointToObjectSpace(root.Position)
			local half = part.Size / 2
			if math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z and offset.Y > 0 and offset.Y < 6 then
				return action
			end
		end
	end
	return nil
end

function EffectsController:_applySettings()
	local profile = self.Controllers.ClientState.Profile
	if not profile or not profile.Settings then
		return
	end
	local reduced = profile.Settings.ReducedEffects == true
	local hideHints = profile.Settings.Hints == false
	if reduced ~= self.Reduced then
		self.Reduced = reduced
		Lighting.GlobalShadows = not reduced
		for _, descendant in Workspace:GetDescendants() do
			if descendant:IsA("ParticleEmitter") and descendant.Name == "Aura" then
				descendant.Enabled = not reduced
			end
		end
	end
	if hideHints ~= self.HideHints then
		self.HideHints = hideHints
		for _, descendant in Workspace:GetDescendants() do
			if descendant:IsA("BillboardGui") and descendant.Name == "SignGui" then
				descendant.Enabled = not hideHints
			end
		end
	end
end

return EffectsController
