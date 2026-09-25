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

-- Weight of players standing on (or stacked above) a horizontal surface; a bear weighs 2
local function countAbove(active, x, halfWidth, top, reach)
	local count = 0
	for _, info in active do
		local p = info.pos
		if math.abs(p.X - x) < halfWidth + HALF_W * 0.8 and p.Y > top and p.Y < top + (reach or Config.STACK_REACH) then
			count += info.weight
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

-- Weight of the single pal standing on the middle of a heavy plate (towers do not count)
local function weightOnHeavyPlate(active, button)
	local weight = 0
	for _, info in active do
		local p = info.pos
		if math.abs(p.X - button.x) < 0.8 and p.Y > button.top and p.Y < button.top + Config.CHAR_BOTTOM + 0.7 then
			weight = math.max(weight, info.weight)
		end
	end
	return weight
end

local function updateButtons(level, active, playerCount)
	for _, channel in level.channels do
		local need = if channel.heavy then channel.need else Config.needFor(channel.need, playerCount)
		local anyPressed = false
		for _, button in channel.buttons do
			local count = if channel.heavy
				then weightOnHeavyPlate(active, button)
				else countAbove(active, button.x, button.halfWidth, button.top)
			local pressed = count >= need
			if pressed ~= button.pressed then
				button.pressed = pressed
				button.part.Material = if pressed then Enum.Material.Neon else Enum.Material.SmoothPlastic
				button.part.CFrame = CFrame.new(button.x, button.restY - (if pressed then 0.3 else 0), 0)
			end
			setText(button, if channel.heavy then `🐻 {count}/{need}` else `{count}/{need}`)
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

local function updateCrumbles(level, dt, active)
	for _, sand in level.crumbles do
		local part = sand.part
		if sand.state == "solid" then
			if countAbove(active, sand.x, T / 2, sand.top, Config.CHAR_BOTTOM + 0.7) > 0 then
				sand.state = "shaking"
				sand.timer = Config.SAND_DELAY
				part.Color = PALETTE.sandShake
			end
		elseif sand.state == "shaking" then
			sand.timer -= dt
			part.CFrame = sand.home + Vector3.new((math.random() - 0.5) * 0.3, 0, 0)
			if sand.timer <= 0 then
				sand.state = "gone"
				sand.timer = Config.SAND_RESPAWN
				part.CFrame = sand.home
				part.CanCollide = false
				part.Transparency = 1
			end
		else
			sand.timer -= dt
			if sand.timer <= 0 then
				local blocked = false
				for _, info in active do
					local p = info.pos
					if
						math.abs(p.X - sand.x) < T / 2 + HALF_W
						and p.Y - Config.CHAR_BOTTOM < sand.top
						and p.Y + Config.CHAR_TOP > sand.top - T
					then
						blocked = true
						break
					end
				end
				if not blocked then
					sand.state = "solid"
					part.CanCollide = true
					part.Transparency = 0
					part.Color = PALETTE.sand
				end
			end
		end
	end
end

local function updateMovers(level)
	for _, mover in level.movers do
		local angle = level.time / mover.period * 2 * math.pi + mover.phase
		local y = mover.baseY + mover.rise * (0.5 - 0.5 * math.cos(angle))
		mover.part.CFrame = CFrame.new(mover.part.Position.X, y, 0)
	end
end

local function updateCannons(level, dt, active, knocked)
	if #level.cannons == 0 then
		return
	end
	local interval = level.cannonOptions.interval or 2.5
	local speed = level.cannonOptions.speed or 14

	for _, cannon in level.cannons do
		cannon.timer -= dt
		if cannon.timer <= 0 then
			cannon.timer = interval
			local ball = Instance.new("Part")
			ball.Name = "Bullet"
			ball.Shape = Enum.PartType.Ball
			ball.Size = Vector3.new(1.3, 1.3, 1.3)
			ball.Anchored = true
			ball.CanCollide = false
			ball.CanQuery = false
			ball.CanTouch = false
			ball.CastShadow = false
			ball.Color = PALETTE.bullet
			ball.Material = Enum.Material.SmoothPlastic
			ball.CFrame = CFrame.new(cannon.muzzle)
			ball.Parent = level.bulletFolder
			table.insert(level.bullets, { part = ball, dir = cannon.dir, pos = cannon.muzzle })
		end
	end

	for i = #level.bullets, 1, -1 do
		local bullet = level.bullets[i]
		bullet.pos += Vector3.new(bullet.dir * speed * dt, 0, 0)
		local hits = workspace:GetPartBoundsInBox(CFrame.new(bullet.pos), Vector3.new(0.8, 0.8, 0.8), level.overlapParams)
		local hitPlayer = nil
		for _, info in active do
			local p = info.pos
			if
				math.abs(p.X - bullet.pos.X) < HALF_W + 0.6
				and bullet.pos.Y > p.Y - Config.CHAR_BOTTOM - 0.5
				and bullet.pos.Y < p.Y + Config.CHAR_TOP + 0.5
			then
				hitPlayer = info
				break
			end
		end
		if hitPlayer then
			knocked[hitPlayer.player] = "shot"
		end
		if hitPlayer or #hits > 0 or bullet.pos.X < -5 or bullet.pos.X > level.width + 5 then
			bullet.part:Destroy()
			table.remove(level.bullets, i)
		else
			bullet.part.CFrame = CFrame.new(bullet.pos)
		end
	end
end

local function updateScroll(level, dt, active, knocked)
	local scroll = level.scroll
	if not scroll then
		return
	end
	if level.time > scroll.delay then
		scroll.x = math.min(scroll.stopX, scroll.x + scroll.speed * dt)
	end
	scroll.wall.CFrame = CFrame.new(scroll.x, scroll.wall.Position.Y, 0)
	for _, info in active do
		if info.pos.X - HALF_W < scroll.x then
			knocked[info.player] = "scroll"
		end
	end
end

local function updateStopGo(level, active, knocked)
	local stopgo = level.stopgo
	if not stopgo then
		level.signal = nil
		return
	end
	local t = level.time % (stopgo.go + stopgo.stop)
	if t < stopgo.go - 1 then
		level.signal = "go"
	elseif t < stopgo.go then
		level.signal = "warn"
	else
		level.signal = "stop"
		if t - stopgo.go > Config.STOP_GRACE then
			for _, info in active do
				if math.abs(info.root.AssemblyLinearVelocity.X) > Config.STOP_SPEED then
					knocked[info.player] = "stop"
				end
			end
		end
	end
end

-- A plank tilts towards the side with more torque (weight x distance from the pivot).
-- Balanced teams keep it level; alone on one end, it tips steeply and you slide off.
local function updateSeesaws(level, dt, active)
	for _, seesaw in level.seesaws do
		local cos, sin = math.cos(seesaw.angle), math.sin(seesaw.angle)
		local torque = 0
		for _, info in active do
			local rel = info.pos - seesaw.pivot
			local along = rel.X * cos + rel.Y * sin
			local up = -rel.X * sin + rel.Y * cos
			if math.abs(along) < seesaw.halfLen + 0.5 and up > 0.3 and up < Config.STACK_REACH then
				torque += along * info.weight
			end
		end
		local target = 0
		if math.abs(torque) > Config.SEESAW_DEADZONE then
			target = math.clamp(-torque * Config.SEESAW_TILT, -Config.SEESAW_MAX, Config.SEESAW_MAX)
		end
		local step = Config.SEESAW_SPEED * dt
		seesaw.angle += math.clamp(target - seesaw.angle, -step, step)
		seesaw.part.CFrame = CFrame.new(seesaw.pivot) * CFrame.Angles(0, 0, seesaw.angle)
	end
end

local function updateCheckpoints(level, active)
	local current = if level.checkpoint then level.checkpoint.X else -math.huge
	for _, checkpoint in level.checkpoints do
		if checkpoint.x > current then
			for _, info in active do
				local p = info.pos
				if math.abs(p.X - checkpoint.x) < 2.5 and p.Y > checkpoint.bottom and p.Y < checkpoint.bottom + 4 then
					checkpoint.active = true
					checkpoint.flag.Color = PALETTE.flagActive
					level.checkpoint = Vector3.new(checkpoint.x, checkpoint.bottom + 2, 0)
					current = checkpoint.x
					break
				end
			end
		end
	end
end

-- Advances all level mechanics by dt.
-- Returns (globalReason, knocked): globalReason is "time" when the whole team failed;
-- knocked maps each player that fell/got hit this frame to a reason ("death", "shot", "scroll", "stop").
function Mechanics.step(level, dt, infos, playerCount, now)
	level.time += dt
	local knocked = {}

	local active = {}
	for _, info in infos do
		if not info.inDoor and not info.knockedOut then
			table.insert(active, info)
		end
	end

	for _, info in active do
		if info.pos.Y < level.killY or touchesHazard(level, info.pos) then
			knocked[info.player] = "death"
		end
	end

	if level.timeLimit then
		level.timeLeft = math.max(0, math.ceil(level.timeLimit - level.time))
		if level.time >= level.timeLimit then
			return "time", knocked
		end
	end

	updateScroll(level, dt, active, knocked)
	updateStopGo(level, active, knocked)
	updateCannons(level, dt, active, knocked)

	local standing = {}
	for _, info in active do
		if not knocked[info.player] then
			table.insert(standing, info)
		end
	end

	updateCheckpoints(level, standing)
	updateButtons(level, standing, playerCount)
	updateCrumbles(level, dt, standing)
	updateMovers(level)
	updateSeesaws(level, dt, standing)
	updateBoxes(level, dt, standing, playerCount)
	updateLifts(level, dt, standing, playerCount)
	updateKey(level, dt, standing, now)
	updateDoor(level, infos, standing, playerCount)
	return nil, knocked
end

return Mechanics
