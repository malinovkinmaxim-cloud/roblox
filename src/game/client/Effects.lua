-- Client-only visual effects (not replicated): confetti bursts and small puffs.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Effects = {}

local folder = Instance.new("Folder")
folder.Name = "LocalEffects"
folder.Parent = workspace

local rng = Random.new()

local function flake(position, size, color, velocity, lifetime)
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.CFrame = CFrame.new(position) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
	part.AssemblyLinearVelocity = velocity
	part.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
	part.Parent = folder
	Debris:AddItem(part, lifetime)
	return part
end

-- A burst of team-coloured paper squares from `origin`
function Effects.confetti(origin, amount)
	local colors = Config.PLAYER_COLORS
	for i = 1, amount or 90 do
		local color = colors[(i - 1) % #colors + 1]
		local velocity = Vector3.new(rng:NextNumber(-22, 22), rng:NextNumber(35, 70), rng:NextNumber(0, 8))
		flake(origin + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(0, 3), 1.5), Vector3.new(0.5, 0.5, 0.08), color, velocity, 4)
	end
end

-- A little white puff, used for double jumps and wall jumps
function Effects.puff(position)
	for _ = 1, 6 do
		local velocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-6, 2), rng:NextNumber(0, 3))
		local part = flake(position, Vector3.new(0.6, 0.6, 0.6), Color3.new(1, 1, 1), velocity, 0.5)
		part.Shape = Enum.PartType.Ball
		part.Transparency = 0.2
	end
end

return Effects
