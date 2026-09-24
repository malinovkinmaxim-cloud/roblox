local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Ui = require(script:WaitForChild("Ui"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local inputRemote = remotes:WaitForChild("Input")
local restartRemote = remotes:WaitForChild("Restart")
local gameState = ReplicatedStorage:WaitForChild("GameState")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local controls = nil
task.spawn(function()
	local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	controls = playerModule:GetControls()
	controls:Disable()
end)

local ui = Ui.new(player, gameState, function()
	restartRemote:FireServer()
end)

local facing = 1
local lastSentDir = 0
local cameraFocus = nil

local function onCharacterAdded(character)
	facing = 1
	if controls then
		controls:Disable()
	end
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
end
player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.R then
		restartRemote:FireServer()
	end
end)

local function readInput()
	if UserInputService:GetFocusedTextBox() then
		return 0, false
	end
	local dir = 0
	local jump = false
	local isDown = function(key)
		return UserInputService:IsKeyDown(key)
	end
	if isDown(Enum.KeyCode.A) or isDown(Enum.KeyCode.Left) then
		dir -= 1
	end
	if isDown(Enum.KeyCode.D) or isDown(Enum.KeyCode.Right) then
		dir += 1
	end
	if isDown(Enum.KeyCode.Space) or isDown(Enum.KeyCode.W) or isDown(Enum.KeyCode.Up) then
		jump = true
	end

	if UserInputService.GamepadEnabled then
		local pad = Enum.UserInputType.Gamepad1
		for _, state in UserInputService:GetGamepadState(pad) do
			if state.KeyCode == Enum.KeyCode.Thumbstick1 then
				if state.Position.X > 0.4 then
					dir += 1
				elseif state.Position.X < -0.4 then
					dir -= 1
				end
			end
		end
		if UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.DPadLeft) then
			dir -= 1
		end
		if UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.DPadRight) then
			dir += 1
		end
		if UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.ButtonA) then
			jump = true
		end
	end

	local touch = ui.touch
	if touch.left then
		dir -= 1
	end
	if touch.right then
		dir += 1
	end
	jump = jump or touch.jump

	return math.clamp(dir, -1, 1), jump
end

local function isActive(p)
	if p:GetAttribute("InDoor") == true then
		return nil
	end
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return root
	end
	return nil
end

-- Keeps the character on the Z = 0 plane, facing left or right
local function lockToPlane(root)
	local pos = root.Position
	local look = root.CFrame.LookVector
	if math.abs(pos.Z) > 0.05 or look.X * facing < 0.99 then
		local flat = Vector3.new(pos.X, pos.Y, 0)
		root.CFrame = CFrame.lookAt(flat, flat + Vector3.new(facing, 0, 0))
	end
	local v = root.AssemblyLinearVelocity
	if math.abs(v.Z) > 0.01 then
		root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, 0)
	end
	local w = root.AssemblyAngularVelocity
	if w.Magnitude > 0.01 then
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

-- Shared screen: nobody may walk further than TETHER_WIDTH from the farthest teammate
local function applyTether(root, dir)
	local minX, maxX = math.huge, -math.huge
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherRoot = isActive(other)
			if otherRoot then
				minX = math.min(minX, otherRoot.Position.X)
				maxX = math.max(maxX, otherRoot.Position.X)
			end
		end
	end
	if minX == math.huge then
		return dir
	end
	local x = root.Position.X
	local v = root.AssemblyLinearVelocity
	if x >= minX + Config.TETHER_WIDTH then
		if dir > 0 then
			dir = 0
		end
		if v.X > 0 then
			root.AssemblyLinearVelocity = Vector3.new(0, v.Y, v.Z)
		end
	elseif x <= maxX - Config.TETHER_WIDTH then
		if dir < 0 then
			dir = 0
		end
		if v.X < 0 then
			root.AssemblyLinearVelocity = Vector3.new(0, v.Y, v.Z)
		end
	end
	return dir
end

local function updateCharacter()
	local dir, jump = readInput()

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = isActive(player)
	if not root or not humanoid then
		dir = 0
	else
		dir = applyTether(root, dir)
		if dir ~= 0 then
			facing = dir
		end
		lockToPlane(root)
		humanoid:Move(Vector3.new(dir, 0, 0), false)
		if jump then
			humanoid.Jump = true
		end
	end

	if dir ~= lastSentDir then
		lastSentDir = dir
		inputRemote:FireServer(dir)
	end
end

local function updateCamera(dt)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Config.CAMERA_FOV

	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, p in Players:GetPlayers() do
		local root = isActive(p)
		if root then
			local pos = root.Position
			minX, maxX = math.min(minX, pos.X), math.max(maxX, pos.X)
			minY, maxY = math.min(minY, pos.Y), math.max(maxY, pos.Y)
		end
	end
	if minX == math.huge then
		if not cameraFocus then
			return
		end
		minX, maxX, minY, maxY = cameraFocus.X, cameraFocus.X, cameraFocus.Y - 2, cameraFocus.Y - 2
	end

	local tanHalf = math.tan(math.rad(camera.FieldOfView / 2))
	local viewport = camera.ViewportSize
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local dist = math.max(
		Config.CAMERA_MIN_DIST,
		((maxX - minX) / 2 + Config.CAMERA_MARGIN_X) / (tanHalf * aspect),
		((maxY - minY) / 2 + Config.CAMERA_MARGIN_Y) / tanHalf
	)
	local target = Vector3.new((minX + maxX) / 2, (minY + maxY) / 2 + 2, dist)

	if cameraFocus then
		cameraFocus = cameraFocus:Lerp(target, 1 - math.exp(-dt * 6))
	else
		cameraFocus = target
	end
	camera.CFrame = CFrame.lookAt(cameraFocus, Vector3.new(cameraFocus.X, cameraFocus.Y, 0))
end

RunService:BindToRenderStep("HopPalsControl", Enum.RenderPriority.Input.Value + 1, updateCharacter)
RunService:BindToRenderStep("HopPalsCamera", Enum.RenderPriority.Camera.Value + 1, updateCamera)
