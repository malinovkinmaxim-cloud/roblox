local Config = {}

Config.GAME_TITLE = "HOP PALS"

-- Place IDs from the Creator Dashboard (see README). 0 = not set up yet.
Config.HUB_PLACE_ID = 0
Config.GAME_PLACE_ID = 0

-- Hub rooms: one pad per capacity. A room starts with at least MIN players.
Config.ROOM_CAPACITIES = { 2, 3, 4, 5, 6, 8 }
Config.ROOM_MIN_PLAYERS = 2
Config.ROOM_WAIT = 20 -- countdown once MIN players are in
Config.ROOM_FULL_WAIT = 5 -- countdown once the room is full
Config.ROOM_START_NOW_WAIT = 3

-- Game server waits this long for the whole room to arrive before level 1
Config.TEAM_ARRIVAL_TIMEOUT = 20

Config.TILE = 3
Config.TILE_DEPTH = 6
Config.GRAVITY = 150
Config.WALK_SPEED = 14
Config.JUMP_HEIGHT = 7.5

Config.CHAR_SIZE = Vector3.new(2.2, 2, 2.2)
Config.CHAR_HIP = 0.5
Config.CHAR_HALF_WIDTH = 1.1
Config.CHAR_BOTTOM = 1.5 -- root center to feet
Config.CHAR_TOP = 1.0 -- root center to head top

-- Max horizontal distance between players (shared screen)
Config.TETHER_WIDTH = 54

Config.CAMERA_FOV = 40
Config.CAMERA_MIN_DIST = 40
Config.CAMERA_MARGIN_X = 14
Config.CAMERA_MARGIN_Y = 9

Config.BOX_SPEED = 7
Config.LIFT_SPEED = 6
Config.KEY_PICKUP_RADIUS = 2.8
Config.DOOR_UNLOCK_RADIUS = 4
Config.STACK_REACH = 9 -- how high above a button/lift a stacked player still counts
Config.SPAWN_SPACING = 2.6

Config.FAIL_DELAY = 1.5
Config.COMPLETE_DELAY = 2.5

Config.PLAYER_COLORS = {
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(255, 95, 95),
	Color3.fromRGB(255, 210, 60),
	Color3.fromRGB(80, 210, 130),
	Color3.fromRGB(255, 150, 50),
	Color3.fromRGB(255, 130, 200),
	Color3.fromRGB(160, 110, 240),
	Color3.fromRGB(60, 200, 200),
}

Config.PALETTE = {
	background = Color3.fromRGB(255, 244, 228),
	cloud = Color3.fromRGB(255, 255, 255),
	ground = Color3.fromRGB(74, 85, 120),
	groundTop = Color3.fromRGB(120, 200, 150),
	box = Color3.fromRGB(239, 170, 64),
	boxText = Color3.fromRGB(90, 55, 20),
	lift = Color3.fromRGB(100, 180, 210),
	button = Color3.fromRGB(230, 80, 80),
	buttonPressed = Color3.fromRGB(90, 200, 110),
	gate = Color3.fromRGB(150, 120, 220),
	key = Color3.fromRGB(255, 205, 60),
	doorFrame = Color3.fromRGB(70, 50, 40),
	doorLocked = Color3.fromRGB(150, 100, 70),
	doorOpen = Color3.fromRGB(30, 30, 40),
	spike = Color3.fromRGB(60, 60, 70),
	text = Color3.fromRGB(50, 50, 70),
}

function Config.needFor(n, playerCount)
	return math.clamp(n, 1, math.max(1, playerCount))
end

return Config
