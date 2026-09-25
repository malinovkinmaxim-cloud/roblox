local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

local T = Config.TILE
local DEPTH = Config.TILE_DEPTH
local PALETTE = Config.PALETTE

local LevelBuilder = {}

local function makePart(name, size, cframe, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function makeDecor(part)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

local function makeFaceLabel(part, text, color)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- the face that looks at the camera (+Z)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = UiStyle.fonts.logo
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	UiStyle.stroke(label, 4, Color3.new(1, 1, 1), Enum.ApplyStrokeMode.Contextual)
	label.Parent = gui
	gui.Parent = part
	return label
end

-- Channel "b" = purple buttons/walls/bridges, channel "c" = pink ones
local CHANNEL_TILES = {
	b = { button = "b", wall = "x", bridge = "g", color = PALETTE.gate, option = "button" },
	c = { button = "c", wall = "y", bridge = "h", color = PALETTE.gate2, option = "button2" },
}

local function parseGrid(map)
	local height = #map
	local width = 0
	for _, row in map do
		width = math.max(width, #row)
	end
	local grid = {}
	for r, row in map do
		grid[r] = {}
		for c = 1, width do
			local ch = string.sub(row, c, c)
			grid[r][c] = if ch == "" then " " else ch
		end
	end
	return grid, width, height
end

-- Calls fn(row, firstCol, lastCol) for each horizontal run of tiles matching pred
local function eachRun(width, height, pred, fn)
	for r = 1, height do
		local c = 1
		while c <= width do
			if pred(r, c) then
				local first = c
				while c <= width and pred(r, c) do
					c += 1
				end
				fn(r, first, c - 1)
			else
				c += 1
			end
		end
	end
end

-- Flood-fills groups of the same character and calls fn(ch, minR, maxR, minC, maxC)
local function eachGroup(grid, width, height, isGroupChar, fn)
	local visited = {}
	for r = 1, height do
		visited[r] = {}
	end
	for r = 1, height do
		for c = 1, width do
			local ch = grid[r][c]
			if isGroupChar(ch) and not visited[r][c] then
				local minR, maxR, minC, maxC = r, r, c, c
				local stack = { { r, c } }
				visited[r][c] = true
				while #stack > 0 do
					local cell = table.remove(stack)
					local cr, cc = cell[1], cell[2]
					minR, maxR = math.min(minR, cr), math.max(maxR, cr)
					minC, maxC = math.min(minC, cc), math.max(maxC, cc)
					for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
						local nr, nc = cr + d[1], cc + d[2]
						if nr >= 1 and nr <= height and nc >= 1 and nc <= width then
							if not visited[nr][nc] and grid[nr][nc] == ch then
								visited[nr][nc] = true
								table.insert(stack, { nr, nc })
							end
						end
					end
				end
				fn(ch, minR, maxR, minC, maxC)
			end
		end
	end
end

local function buildKey(position, parent)
	local model = Instance.new("Model")
	model.Name = "Key"
	local ring = makeDecor(
		makePart("Ring", Vector3.new(0.4, 1.3, 1.3), CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0), PALETTE.key, model)
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	local hole = makeDecor(
		makePart(
			"Hole",
			Vector3.new(0.45, 0.5, 0.5),
			CFrame.new(position + Vector3.new(0, 0, 0.02)) * CFrame.Angles(0, math.rad(90), 0),
			PALETTE.background,
			model
		)
	)
	hole.Shape = Enum.PartType.Cylinder
	makeDecor(makePart("Shaft", Vector3.new(1.6, 0.35, 0.3), CFrame.new(position + Vector3.new(1.3, 0, 0)), PALETTE.key, model)).Material =
		Enum.Material.Neon
	makeDecor(makePart("Tooth1", Vector3.new(0.3, 0.45, 0.26), CFrame.new(position + Vector3.new(1.75, -0.35, 0)), PALETTE.key, model)).Material =
		Enum.Material.Neon
	makeDecor(makePart("Tooth2", Vector3.new(0.3, 0.3, 0.26), CFrame.new(position + Vector3.new(1.3, -0.3, 0)), PALETTE.key, model)).Material =
		Enum.Material.Neon
	model.PrimaryPart = ring
	model.Parent = parent
	return model
end

local function buildClouds(width, height, levelIndex, parent)
	local rng = Random.new(levelIndex * 7919)
	for _ = 1, math.max(4, math.floor(width / 8)) do
		local base = Vector3.new(rng:NextNumber(0, width * T), height * T + rng:NextNumber(-4, 10), -14)
		for i = 1, 3 do
			local size = rng:NextNumber(4, 7)
			local ball = makeDecor(
				makePart("Cloud", Vector3.new(size, size, size), CFrame.new(base + Vector3.new((i - 2) * 3.2, (i == 2) and 1.2 or 0, 0)), PALETTE.cloud, parent)
			)
			ball.Shape = Enum.PartType.Ball
		end
	end
end

function LevelBuilder.build(data, levelIndex)
	local grid, width, height = parseGrid(data.map)

	local folder = Instance.new("Folder")
	folder.Name = "Level"
	local solids = Instance.new("Folder")
	solids.Name = "Solids"
	solids.Parent = folder
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = folder

	local function tileX(c)
		return (c - 0.5) * T
	end
	local function tileBottom(r)
		return (height - r) * T
	end
	local function charAt(r, c)
		if r < 1 or r > height or c < 1 or c > width then
			return " "
		end
		return grid[r][c]
	end

	local level = {
		index = levelIndex,
		name = data.name,
		folder = folder,
		solids = solids,
		width = width * T,
		height = height * T,
		killY = -3 * T,
		spawn = Vector3.new(tileX(1), tileBottom(height) + T, 0),
		key = nil,
		door = nil,
		channels = {},
		crumbles = {},
		seesaws = {},
		checkpoints = {},
		checkpoint = nil,
		koCount = 0,
		movers = {},
		cannons = {},
		bullets = {},
		cannonOptions = data.cannon or {},
		timeLimit = data.time,
		stopgo = data.stopgo and { go = data.stopgo.go or 3.5, stop = data.stopgo.stop or 2.5 } or nil,
		time = 0,
		boxes = {},
		lifts = {},
		hazards = {},
	}

	-- Background
	makeDecor(
		makePart(
			"Background",
			Vector3.new(width * T + 600, height * T + 400, 1),
			CFrame.new(width * T / 2, height * T / 2, -16),
			PALETTE.background,
			decor
		)
	)
	buildClouds(width, height, levelIndex, decor)

	-- Invisible side walls
	for _, x in { -0.5, width * T + 0.5 } do
		local wall = makePart("Bounds", Vector3.new(1, height * T + 200, DEPTH), CFrame.new(x, height * T / 2 + 60, 0), PALETTE.ground, solids)
		wall.Transparency = 1
	end

	local function runPart(name, r, c0, c1, color, parent)
		local len = c1 - c0 + 1
		return makePart(
			name,
			Vector3.new(len * T, T, DEPTH),
			CFrame.new((c0 - 1) * T + len * T / 2, tileBottom(r) + T / 2, 0),
			color,
			parent
		)
	end

	-- Ground
	eachRun(width, height, function(r, c)
		return grid[r][c] == "#"
	end, function(r, c0, c1)
		runPart("Ground", r, c0, c1, PALETTE.ground, solids)
	end)

	-- Grass strip on exposed ground tops. It is slightly bigger than the ground on every side
	-- so no face is coplanar with the ground block (coplanar faces flicker / z-fight).
	eachRun(width, height, function(r, c)
		return grid[r][c] == "#" and charAt(r - 1, c) ~= "#"
	end, function(r, c0, c1)
		local len = c1 - c0 + 1
		makeDecor(
			makePart(
				"Grass",
				Vector3.new(len * T + 0.1, 0.6, DEPTH + 0.1),
				CFrame.new((c0 - 1) * T + len * T / 2, tileBottom(r) + T - 0.24, 0),
				PALETTE.groundTop,
				decor
			)
		)
	end)

	-- Button channels with the walls and bridges they control
	for id, tiles in CHANNEL_TILES do
		local options = data[tiles.option] or {}
		local channel = {
			id = id,
			color = tiles.color,
			need = options.need or 1,
			latch = options.latch or false,
			on = false,
			buttons = {},
			walls = {},
			bridges = {},
		}
		eachRun(width, height, function(r, c)
			return grid[r][c] == tiles.bridge
		end, function(r, c0, c1)
			local bridge = runPart("Bridge", r, c0, c1, tiles.color, solids)
			bridge.CanCollide = false
			bridge.Transparency = 0.8
			table.insert(channel.bridges, bridge)
		end)
		eachRun(width, height, function(r, c)
			return grid[r][c] == tiles.wall
		end, function(r, c0, c1)
			table.insert(channel.walls, runPart("Wall", r, c0, c1, tiles.color, solids))
		end)
		for r = 1, height do
			for c = 1, width do
				if grid[r][c] == tiles.button then
					local x, bottom = tileX(c), tileBottom(r)
					local plate = makePart("Button", Vector3.new(T * 0.9, 0.5, 2.6), CFrame.new(x, bottom + 0.25, 0), tiles.color, solids)
					table.insert(channel.buttons, {
						part = plate,
						x = x,
						halfWidth = T * 0.45,
						top = bottom + 0.5,
						restY = bottom + 0.25,
						pressed = false,
						label = UiStyle.worldTag(plate, Vector3.new(0, 2.6, 0), "", tiles.color, Color3.new(1, 1, 1)),
						shownText = nil,
					})
				end
			end
		end
		if #channel.buttons > 0 then
			level.channels[id] = channel
		end
	end

	-- Sand blocks (one part per tile so each crumbles on its own)
	for r = 1, height do
		for c = 1, width do
			if grid[r][c] == "o" then
				local x, bottom = tileX(c), tileBottom(r)
				local home = CFrame.new(x, bottom + T / 2, 0)
				local part = makePart("Sand", Vector3.new(T, T, DEPTH - 1), home, PALETTE.sand, solids)
				part.Material = Enum.Material.Sand
				table.insert(level.crumbles, {
					part = part,
					home = home,
					x = x,
					top = bottom + T,
					state = "solid",
					timer = 0,
				})
			end
		end
	end

	-- Cannons
	for r = 1, height do
		for c = 1, width do
			local ch = grid[r][c]
			if ch == "<" or ch == ">" then
				local dir = if ch == "<" then -1 else 1
				local x, bottom = tileX(c), tileBottom(r)
				local center = Vector3.new(x, bottom + T / 2, 0)
				makePart("Cannon", Vector3.new(T, T, DEPTH - 2), CFrame.new(center), PALETTE.cannon, solids)
				local barrel = makeDecor(
					makePart(
						"Barrel",
						Vector3.new(1.4, 1.6, 1.6),
						CFrame.new(center + Vector3.new(dir * (T / 2 + 0.6), 0.2, 0)),
						PALETTE.cannon,
						decor
					)
				)
				barrel.Shape = Enum.PartType.Cylinder
				table.insert(level.cannons, {
					dir = dir,
					muzzle = center + Vector3.new(dir * (T / 2 + 1.4), 0, 0),
					timer = 1 + (c % 3) * 0.4,
				})
			end
		end
	end
	if #level.cannons > 0 then
		local bulletFolder = Instance.new("Folder")
		bulletFolder.Name = "Bullets"
		bulletFolder.Parent = folder
		level.bulletFolder = bulletFolder
	end

	-- Seesaws: each horizontal run of "=" is one plank balanced on its middle
	eachRun(width, height, function(r, c)
		return grid[r][c] == "="
	end, function(r, c0, c1)
		local len = (c1 - c0 + 1) * T
		local pivot = Vector3.new((c0 - 1) * T + len / 2, tileBottom(r) + T - 0.5, 0)
		local plank = makePart("Seesaw", Vector3.new(len, 1, DEPTH - 2), CFrame.new(pivot), PALETTE.seesaw, solids)
		makeDecor(makePart("SeesawPost", Vector3.new(0.8, 40, 0.8), CFrame.new(pivot - Vector3.new(0, 20.5, -0.6)), PALETTE.cannon, decor))
		local hinge = makeDecor(
			makePart("SeesawHinge", Vector3.new(0.6, 1.6, 1.6), CFrame.new(pivot + Vector3.new(0, 0, 2.2)) * CFrame.Angles(0, math.rad(90), 0), PALETTE.cannon, decor)
		)
		hinge.Shape = Enum.PartType.Cylinder
		table.insert(level.seesaws, { part = plank, pivot = pivot, halfLen = len / 2, angle = 0 })
	end)

	-- Trampolines
	for r = 1, height do
		for c = 1, width do
			if grid[r][c] == "j" then
				local x, bottom = tileX(c), tileBottom(r)
				local spring = makePart("Spring", Vector3.new(T * 0.9, 0.7, 2.6), CFrame.new(x, bottom + 0.35, 0), PALETTE.spring, solids)
				spring.Material = Enum.Material.Neon
				CollectionService:AddTag(spring, "Spring")
				for _, dy in { -0.15, 0.15 } do
					makeDecor(
						makePart("SpringStripe", Vector3.new(T * 0.7, 0.08, 0.1), CFrame.new(x, bottom + 0.35 + dy, 1.36), PALETTE.springStripe, decor)
					)
				end
			end
		end
	end

	-- Spikes
	eachRun(width, height, function(r, c)
		return grid[r][c] == "^"
	end, function(r, c0, c1)
		local bottom = tileBottom(r)
		for c = c0, c1 do
			for _, dx in { -T / 4, T / 4 } do
				local spike = makeDecor(
					makePart(
						"Spike",
						Vector3.new(1.1, 1.1, 2),
						CFrame.new(tileX(c) + dx, bottom, 0) * CFrame.Angles(0, 0, math.rad(45)),
						PALETTE.spike,
						decor
					)
				)
				spike.Material = Enum.Material.Metal
			end
		end
		table.insert(level.hazards, {
			minX = (c0 - 1) * T + 0.3,
			maxX = c1 * T - 0.3,
			minY = bottom - 1,
			maxY = bottom + 0.7,
		})
	end)

	-- Push boxes and lifts
	eachGroup(grid, width, height, function(ch)
		return string.match(ch, "%d") ~= nil or ch == "L" or ch == "M"
	end, function(ch, minR, maxR, minC, maxC)
		local w = (maxC - minC + 1) * T
		local h = (maxR - minR + 1) * T
		local center = Vector3.new((minC - 1) * T + w / 2, tileBottom(maxR) + h / 2, 0)
		if ch == "M" then
			local moverData = data.mover or {}
			local part = makePart("Mover", Vector3.new(w, h, DEPTH - 2), CFrame.new(center), PALETTE.mover, solids)
			table.insert(level.movers, {
				part = part,
				baseY = center.Y,
				rise = (moverData.rise or 3) * T,
				period = moverData.period or 4,
				phase = center.X / 11,
			})
		elseif ch == "L" then
			local liftData = data.lift or {}
			local part = makePart("Lift", Vector3.new(w, h, DEPTH - 2), CFrame.new(center), PALETTE.lift, solids)
			local need = liftData.need or 99
			table.insert(level.lifts, {
				part = part,
				need = need,
				baseY = center.Y,
				topY = center.Y + (liftData.rise or 4) * T,
				label = makeFaceLabel(part, "", PALETTE.text),
				shownText = nil,
			})
		else
			local part = makePart("Box", Vector3.new(w, h, DEPTH - 2), CFrame.new(center), PALETTE.box, solids)
			table.insert(level.boxes, {
				part = part,
				need = tonumber(ch),
				vy = 0,
				label = makeFaceLabel(part, ch, PALETTE.boxText),
				shownText = nil,
			})
		end
	end)

	-- Single-tile objects
	for r = 1, height do
		for c = 1, width do
			local ch = grid[r][c]
			local x, bottom = tileX(c), tileBottom(r)
			if ch == "S" then
				level.spawn = Vector3.new(x, bottom + 2, 0)
			elseif ch == "K" then
				local home = Vector3.new(x, bottom + T / 2, 0)
				level.key = {
					home = home,
					current = home,
					carrier = nil,
					model = buildKey(home + Vector3.new(0, 0, 1.5), folder),
				}
			elseif ch == "D" then
				local frame = makeDecor(
					makePart("DoorFrame", Vector3.new(T + 0.6, 2 * T + 0.3, 0.4), CFrame.new(x, bottom + T + 0.15, -1.9), PALETTE.doorFrame, folder)
				)
				local panel = makeDecor(
					makePart("Door", Vector3.new(T - 0.4, 2 * T - 0.4, 0.4), CFrame.new(x, bottom + T - 0.2, -1.6), PALETTE.doorLocked, folder)
				)
				level.door = {
					x = x,
					bottom = bottom,
					center = Vector3.new(x, bottom + T, 0),
					unlocked = false,
					frame = frame,
					panel = panel,
					label = UiStyle.worldTag(frame, Vector3.new(0, T + 1.6, 0), "🔒", UiStyle.colors.gold),
					shownText = nil,
				}
			end
		end
	end

	-- Checkpoints: "F" tiles plus automatic ones on safe open ground every CHECKPOINT_SPACING columns
	local function standingRow(c)
		if c < 1 or c > width then
			return nil
		end
		local r = height
		while r >= 1 and grid[r][c] == "#" do
			r -= 1
		end
		if r == height or r < 3 then
			return nil
		end
		local here = grid[r][c]
		if (here ~= " " and here ~= "F") or grid[r - 1][c] ~= " " or grid[r - 2][c] ~= " " then
			return nil
		end
		return r
	end
	local function addCheckpoint(c, r)
		local x, bottom = tileX(c), tileBottom(r)
		makeDecor(makePart("FlagPole", Vector3.new(0.3, 4.2, 0.3), CFrame.new(x, bottom + 2.1, -1.4), PALETTE.cannon, decor))
		local flag = makeDecor(makePart("Flag", Vector3.new(1.6, 1.1, 0.15), CFrame.new(x + 0.8, bottom + 3.55, -1.4), PALETTE.flag, decor))
		table.insert(level.checkpoints, { x = x, bottom = bottom, flag = flag, active = false })
	end
	for r = 1, height do
		for c = 1, width do
			if grid[r][c] == "F" then
				addCheckpoint(c, r)
			end
		end
	end
	local spawnCol = math.floor(level.spawn.X / T) + 1
	local lastCol = if level.door then math.floor(level.door.x / T) + 1 - 6 else width - 6
	local previous = spawnCol
	for c = spawnCol + Config.CHECKPOINT_SPACING, lastCol do
		if c - previous >= Config.CHECKPOINT_SPACING then
			local r = standingRow(c)
			if r and standingRow(c - 1) == r and standingRow(c + 1) == r then
				addCheckpoint(c, r)
				previous = c
			end
		end
	end
	table.sort(level.checkpoints, function(a, b)
		return a.x < b.x
	end)

	if data.scroll then
		local wall = makeDecor(
			makePart("ScrollWall", Vector3.new(1.5, height * T + 80, DEPTH + 0.6), CFrame.new(0, height * T / 2, 0), PALETTE.scrollWall, decor)
		)
		wall.Material = Enum.Material.Neon
		wall.Transparency = 0.3
		level.scroll = {
			speed = data.scroll.speed or 3.5,
			delay = data.scroll.delay or 4,
			x = 0,
			stopX = if level.door then level.door.x - 30 else width * T - 60,
			wall = wall,
		}
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { solids }
	overlapParams.RespectCanCollide = true
	level.overlapParams = overlapParams

	return level
end

return LevelBuilder
