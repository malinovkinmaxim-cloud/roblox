local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PALETTE = Config.PALETTE
local T = Config.TILE
local HALF_W = Config.CHAR_HALF_WIDTH

local Mechanics = {}

local function setText(holder, text)
	if holder.shownText ~= text then
		holder.shownText = text
		holder.label.Text = text
	end
end

local function canPlace(level, part, cframe)
	local hits = workspace:GetPartBoundsInBox(cframe, part.Size - Vector3.new(0.2, 0.02, 0.2), level.overlapParams)
	for _, hit in hits do
		if hit ~= part then
			return false
		end
	end
	return true
end

-- Players standing on (or stacked above) a horizontal surface
local function countAbove(active, x, halfWidth, top)
	local count = 0
	for _, info in active do
		local p = info.pos
		if math.abs(p.X - x) < halfWidth + HALF_W * 0.8 and p.Y > top and p.Y < top + Config.STACK_REACH then
			count += 1
		end
	end
	return count
end

local function touchesHazard(level, pos)
	local minX, maxX = pos.X - HALF_W, pos.X + HALF_W
	local minY, maxY = pos.Y - Config.CHAR_BOTTOM, pos.Y + Config.CHAR_TOP
	for _, h in level.hazards do
		if maxX > h.minX and minX < h.maxX and maxY > h.minY and minY < h.maxY then
			return true
		end
	end
	return false
end

local function applyChannel(channel)
	local on = channel.on
	for _, part in channel.bridges do
		part.CanCollide = on
		part.Transparency = if on then 0 else 0.8
	end
	for _, part in channel.walls do
		part.CanCollide = not on
		part.Transparency = if on then 0.85 else 0
	end
end

local function updateButtons(level, active, playerCount)
	for _, channel in level.channels do
		local need = Config.needFor(channel.need, playerCount)
		local anyPressed = false
		for _, button in channel.buttons do
			local count = countAbove(active, button.x, button.halfWidth, button.top)
			local pressed = count >= need
			if pressed ~= button.pressed then
				button.pressed = pressed
				button.part.Material = if pressed then Enum.Material.Neon else Enum.Material.SmoothPlastic
				button.part.CFrame = CFrame.new(button.x, button.restY - (if pressed then 0.3 else 0), 0)
			end
			setText(button, `{count}/{need}`)
			anyPressed = anyPressed or pressed
		end
		local on = anyPressed or (channel.latch and channel.on)
		if on ~= channel.on then
			channel.on = on
			applyChannel(channel)
		end
	end
end

-- Counts a chain of players pushing the box in direction dir (players pushing players count too)
local function countPushers(box, dir, active)
	local part = box.part
	local face = part.Position.X - dir * part.Size.X / 2
	local boxBottom = part.Position.Y - part.Size.Y / 2
	local boxTop = part.Position.Y + part.Size.Y / 2

	local counted = {}
	local chain = {}
	for _, info in active do
		if info.dir == dir then
			local p = info.pos
			local leadingEdge = p.X + dir * HALF_W
			local overlapsY = p.Y - Config.CHAR_BOTTOM < boxTop - 0.3 and p.Y + Config.CHAR_TOP > boxBottom + 0.3
			if overlapsY and math.abs(leadingEdge - face) < 0.7 then
				counted[info] = true
				table.insert(chain, info)
			end
		end
	end

	local grew = true
	while grew do
		grew = false
		for _, info in active do
			if info.dir == dir and not counted[info] then
				local leadingEdge = info.pos.X + dir * HALF_W
				for _, other in chain do
					local trailingEdge = other.pos.X - dir * HALF_W
					if math.abs(leadingEdge - trailingEdge) < 0.7 and math.abs(info.pos.Y - other.pos.Y) < 1.5 then
						counted[info] = true
						table.insert(chain, info)
						grew = true
						break
					end
				end
			end
		end
	end
	return #chain
end

local function tryMove(level, part, offset)
	local step = offset
	while step.Magnitude > 0.01 do
		local target = part.CFrame + step
		if canPlace(level, part, target) then
			part.CFrame = target
			return true
		end
		step /= 2
	end
	return false
end

local function updateBoxes(level, dt, active, playerCount)
	for _, box in level.boxes do
		local need = Config.needFor(box.need, playerCount)
		setText(box, tostring(need))

		for _, dir in { 1, -1 } do
			if countPushers(box, dir, active) >= need then
				tryMove(level, box.part, Vector3.new(dir * Config.BOX_SPEED * dt, 0, 0))
				break
			end
		end

		box.vy = math.min(box.vy + workspace.Gravity * dt, 80)
		if not tryMove(level, box.part, Vector3.new(0, -box.vy * dt, 0)) then
			box.vy = 0
		end
	end
end

local function updateLifts(level, dt, active, playerCount)
	for _, lift in level.lifts do
		local part = lift.part
		local top = part.Position.Y + part.Size.Y / 2
		local count = countAbove(active, part.Position.X, part.Size.X / 2, top)
		local need = Config.needFor(lift.need, playerCount)
		setText(lift, `{count}/{need}`)

		local y = part.Position.Y
		local targetY = y
		if count >= need then
			targetY = lift.topY
		elseif count == 0 then
			targetY = lift.baseY
		end
		if targetY ~= y then
			local maxStep = Config.LIFT_SPEED * dt
			local newY = y + math.clamp(targetY - y, -maxStep, maxStep)
			part.CFrame = CFrame.new(part.Position.X, newY, part.Position.Z)
		end
	end
end

local function unlockDoor(level)
	local door = level.door
	door.unlocked = true
	door.panel.Color = PALETTE.doorOpen
	door.panel.Material = Enum.Material.SmoothPlastic
	door.label.Parent.BackgroundColor3 = PALETTE.buttonPressed
	door.label.TextColor3 = Color3.new(1, 1, 1)
	if level.key then
		level.key.model:Destroy()
		level.key = nil
	end
end

local function updateKey(level, dt, active, now)
	local key = level.key
	if not key then
		return
	end

	local carrierInfo
	if key.carrier then
		for _, info in active do
			if info.player == key.carrier then
				carrierInfo = info
				break
			end
		end
		if not carrierInfo then
			key.carrier = nil
		end
	end

	if not carrierInfo then
		for _, info in active do
			local d = Vector2.new(info.pos.X - key.current.X, info.pos.Y - key.current.Y)
			if d.Magnitude < Config.KEY_PICKUP_RADIUS then
				key.carrier = info.player
				carrierInfo = info
				break
			end
		end
	end

	local target
	if carrierInfo then
		target = carrierInfo.pos + Vector3.new(0, 2.8, 0)
		local door = level.door
		if door and not door.unlocked then
			local d = Vector2.new(carrierInfo.pos.X - door.center.X, carrierInfo.pos.Y - door.center.Y)
			if d.Magnitude < Config.DOOR_UNLOCK_RADIUS then
				unlockDoor(level)
				return
			end
		end
	else
		target = key.home + Vector3.new(0, math.sin(now * 3) * 0.3, 0)
	end

	key.current = key.current:Lerp(Vector3.new(target.X, target.Y, 0), math.min(1, dt * 12))
	key.model:PivotTo(CFrame.new(key.current + Vector3.new(0, 0, 1.5)) * CFrame.Angles(0, math.rad(90), math.sin(now * 2) * 0.2))
end

local function enterDoor(level, info)
	local door = level.door
	info.player:SetAttribute("InDoor", true)
	for _, item in info.character:GetDescendants() do
		if item:IsA("BasePart") then
			item.Transparency = 1
			item.CanCollide = false
		elseif item:IsA("BillboardGui") then
			item.Enabled = false
		end
	end
	info.root.Anchored = true
	info.character:PivotTo(CFrame.new(door.x, door.bottom + 1.5, -1))
end

local function updateDoor(level, infos, active, playerCount)
	local door = level.door
	if not door then
		return
	end
	if door.unlocked then
		for _, info in active do
			local p = info.pos
			if math.abs(p.X - door.x) < 1.6 and p.Y > door.bottom and p.Y < door.bottom + 2 * T then
				enterDoor(level, info)
			end
		end
		local inside = 0
		for _, info in infos do
			if info.player:GetAttribute("InDoor") == true then
				inside += 1
			end
		end
		setText(door, `{inside}/{playerCount}`)
	end
end

-- Advances all level mechanics by dt. Returns "fail" when someone died.
function Mechanics.step(level, dt, infos, playerCount, now)
	local active = {}
	for _, info in infos do
		if not info.inDoor then
			table.insert(active, info)
		end
	end

	for _, info in active do
		if info.pos.Y < level.killY or touchesHazard(level, info.pos) then
			return "fail"
		end
	end

	updateButtons(level, active, playerCount)
	updateBoxes(level, dt, active, playerCount)
	updateLifts(level, dt, active, playerCount)
	updateKey(level, dt, active, now)
	updateDoor(level, infos, active, playerCount)
	return nil
end

return Mechanics
