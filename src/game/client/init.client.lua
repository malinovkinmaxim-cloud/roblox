local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Effects = require(script:WaitForChild("Effects"))
local Ui = require(script:WaitForChild("Ui"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local inputRemote = remotes:WaitForChild("Input")
local restartRemote = remotes:WaitForChild("Restart")
local toHubRemote = remotes:WaitForChild("ToHub")
local chooseModeRemote = remotes:WaitForChild("ChooseMode")
local selectBuddyRemote = remotes:WaitForChild("SelectBuddy")
local grabRemote = remotes:WaitForChild("Grab")
local wriggleRemote = remotes:WaitForChild("Wriggle")
local thrownRemote = remotes:WaitForChild("Thrown")
local rewardRemote = remotes:WaitForChild("Reward")
local gameState = ReplicatedStorage:WaitForChild("GameState")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera


local facing = 1
local lastSentDir = 0
local cameraFocus = nil
local jumpWasDown = false
local extraJumpReady = false
local clingTime = 0
local lastBounce = 0

local function requestGrab()
	grabRemote:FireServer(facing)
end

local ui = Ui.new(player, gameState, {
	restart = function()
		restartRemote:FireServer()
	end,
	hub = function()
		toHubRemote:FireServer()
	end,
	chooseMode = function(modeId)
		chooseModeRemote:FireServer(modeId)
	end,
	selectBuddy = function(kind, id)
		selectBuddyRemote:FireServer(kind, id)
	end,
	grab = requestGrab,
})

local function onCharacterAdded(character)
	facing = 1
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
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		ui.requestRestart()
	elseif input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX then
		requestGrab()
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
	if p:GetAttribute("InDoor") == true or p:GetAttribute("KnockedOut") == true then
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

local function playerByUserId(userId)
	for _, p in Players:GetPlayers() do
		if p.UserId == userId then
			return p
		end
	end
	return nil
end

-- Keeps the character on the Z = 0 plane, facing left or right
local function lockToPlane(root, keepSpin)
	local pos = root.Position
	local look = root.CFrame.LookVector
	if not keepSpin and (math.abs(pos.Z) > 0.05 or look.X * facing < 0.99) then
		local flat = Vector3.new(pos.X, pos.Y, 0)
		root.CFrame = CFrame.lookAt(flat, flat + Vector3.new(facing, 0, 0))
	elseif keepSpin and math.abs(pos.Z) > 0.05 then
		root.CFrame = root.CFrame - Vector3.new(0, 0, pos.Z)
	end
	local v = root.AssemblyLinearVelocity
	if math.abs(v.Z) > 0.01 then
		root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, 0)
	end
	if not keepSpin and root.AssemblyAngularVelocity.Magnitude > 0.01 then
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

-- Trampolines are handled on the client because each player simulates their own character
local function checkSprings(root, humanoid)
	if os.clock() - lastBounce < 0.25 then
		return
	end
	local pos = root.Position
	local velocity = root.AssemblyLinearVelocity
	if velocity.Y > 1 then
		return
	end
	for _, spring in CollectionService:GetTagged("Spring") do
		local top = spring.Position.Y + spring.Size.Y / 2
		local dy = pos.Y - top
		if math.abs(pos.X - spring.Position.X) < spring.Size.X / 2 + Config.CHAR_HALF_WIDTH * 0.6 and dy > 0 and dy < Config.CHAR_BOTTOM + 0.4 then
			lastBounce = os.clock()
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			local speed = math.sqrt(2 * workspace.Gravity * Config.SPRING_HEIGHT)
			root.AssemblyLinearVelocity = Vector3.new(velocity.X, speed, 0)
			return
		end
	end
end

local function jumpSpeed()
	return math.sqrt(2 * workspace.Gravity * Config.JUMP_HEIGHT)
end

-- Frog passive: teammates near a frog get one extra jump in the air
local function frogNearby(root)
	for _, other in Players:GetPlayers() do
		if other ~= player and (other:GetAttribute("LoanClass") or other:GetAttribute("Class")) == "frog" then
			local otherRoot = isActive(other)
			if otherRoot and (otherRoot.Position - root.Position).Magnitude < Config.FROG_RADIUS then
				return true
			end
		end
	end
	return false
end

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Include

-- Gecko passive: holding towards a wall in the air sticks to it for a while; jump pushes off
local function geckoCling(root, dir, jumpPressed, dt)
	local level = workspace:FindFirstChild("Level")
	local solids = level and level:FindFirstChild("Solids")
	if not solids or dir == 0 or clingTime >= Config.GECKO_CLING_TIME then
		return false
	end
	wallParams.FilterDescendantsInstances = { solids }
	local hit = workspace:Raycast(root.Position, Vector3.new(dir * (Config.CHAR_HALF_WIDTH + 0.4), 0, 0), wallParams)
	if not hit then
		return false
	end
	if jumpPressed then
		clingTime = Config.GECKO_CLING_TIME
		root.AssemblyLinearVelocity = Vector3.new(-dir * Config.GECKO_WALL_JUMP.X, Config.GECKO_WALL_JUMP.Y, 0)
		facing = -dir
		Effects.puff(root.Position)
		return true
	end
	clingTime += dt
	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	return true
end

-- While carried we ride on the carrier's head; jumping wriggles free
local function followCarrier(root, jumpPressed)
	local carrier = playerByUserId(player:GetAttribute("CarriedBy"))
	local carrierRoot = carrier and carrier.Character and carrier.Character:FindFirstChild("HumanoidRootPart")
	if not carrierRoot then
		return false
	end
	if jumpPressed then
		wriggleRemote:FireServer()
	end
	local position = carrierRoot.Position + Vector3.new(0, 2.6, 0)
	root.CFrame = CFrame.lookAt(position, position + Vector3.new(facing, 0, 0))
	root.AssemblyLinearVelocity = carrierRoot.AssemblyLinearVelocity
	return true
end

rewardRemote.OnClientEvent:Connect(function(reward)
	if type(reward) == "table" then
		ui.showReward(reward)
	end
end)

thrownRemote.OnClientEvent:Connect(function(velocity)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and typeof(velocity) == "Vector3" then
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		root.AssemblyLinearVelocity = velocity
		facing = if velocity.X < 0 then -1 else 1
	end
end)

-- Tumble when knocked out: a small fling and a spin, then the server puts us back
player:GetAttributeChangedSignal("KnockedOut"):Connect(function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end
	if player:GetAttribute("KnockedOut") == true then
		humanoid.PlatformStand = true
		root.AssemblyLinearVelocity = Vector3.new(math.random(-10, 10), 38, 0)
		root.AssemblyAngularVelocity = Vector3.new(0, 0, if math.random() < 0.5 then -14 else 14)
	else
		humanoid.PlatformStand = false
		root.AssemblyAngularVelocity = Vector3.zero
	end
end)

local celebrationSeen = gameState:GetAttribute("CelebrateId")
gameState:GetAttributeChangedSignal("CelebrateId"):Connect(function()
	local id = gameState:GetAttribute("CelebrateId")
	if id == celebrationSeen then
		return
	end
	celebrationSeen = id
	local origin = gameState:GetAttribute("CelebrateAt")
	if typeof(origin) == "Vector3" then
		Effects.confetti(origin, 100)
		task.delay(0.6, Effects.confetti, origin + Vector3.new(-6, 2, 0), 50)
		task.delay(0.9, Effects.confetti, origin + Vector3.new(6, 2, 0), 50)
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		facing = if root.CFrame.LookVector.X < 0 then -1 else 1
	end
end)

local function updateCharacter(dt)
	local dir, jump = readInput()
	local jumpPressed = jump and not jumpWasDown
	jumpWasDown = jump

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local celebrating = gameState:GetAttribute("Celebrating") == true

	if not root or not humanoid or humanoid.Health <= 0 or player:GetAttribute("InDoor") == true then
		dir = 0
	elseif player:GetAttribute("KnockedOut") == true then
		dir = 0
		lockToPlane(root, true)
		humanoid:Move(Vector3.zero, false)
	elseif celebrating then
		dir = 0
		lockToPlane(root)
		humanoid:Move(Vector3.zero, false)
		humanoid.Jump = true
	elseif player:GetAttribute("CarriedBy") and followCarrier(root, jumpPressed) then
		dir = 0
		humanoid:Move(Vector3.zero, false)
	else
		dir = applyTether(root, dir)
		if dir ~= 0 then
			facing = dir
		end
		lockToPlane(root)
		checkSprings(root, humanoid)

		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		if grounded then
			extraJumpReady = true
			clingTime = 0
		end

		local clinging = false
		if not grounded and (player:GetAttribute("LoanClass") or player:GetAttribute("Class")) == "gecko" then
			clinging = geckoCling(root, dir, jumpPressed, dt)
		end

		humanoid:Move(Vector3.new(dir, 0, 0), false)
		if jump and grounded then
			humanoid.Jump = true
		elseif jumpPressed and not grounded and not clinging and extraJumpReady and frogNearby(root) then
			extraJumpReady = false
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X, jumpSpeed(), 0)
			Effects.puff(root.Position - Vector3.new(0, 1.5, 0))
		end
		ui.setFrogBoost(frogNearby(root))
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
	local minDist = if gameState:GetAttribute("Celebrating") == true then Config.CAMERA_MIN_DIST * 0.7 else Config.CAMERA_MIN_DIST
	local dist = math.max(
		minDist,
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
