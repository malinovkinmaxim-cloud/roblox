-- Replaces Roblox's default Animate script (the bunny rig has no limbs to animate).
-- Adds a small local squash-and-hop wobble instead.
local RunService = game:GetService("RunService")

local character = script.Parent
local root = character:WaitForChild("HumanoidRootPart")
local head = character:WaitForChild("Head")
local humanoid = character:WaitForChild("Humanoid")
local weld = head:WaitForChild("WeldConstraint")

-- WeldConstraint has no offset to animate, so swap it for a Weld with a C0 we can drive.
local motor = Instance.new("Weld")
motor.Part0 = root
motor.Part1 = head
motor.C0 = CFrame.new()
motor.Parent = head
weld:Destroy()

local t = 0
RunService.RenderStepped:Connect(function(dt)
	if not head.Parent then
		return
	end
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	if moving and grounded then
		t += dt * 14
		motor.C0 = CFrame.new(0, math.abs(math.sin(t)) * 0.25, 0) * CFrame.Angles(math.sin(t) * 0.12, 0, 0)
	else
		t = 0
		motor.C0 = motor.C0:Lerp(CFrame.new(), math.min(1, dt * 10))
	end
end)
