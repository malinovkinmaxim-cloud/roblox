local Config = {}

Config.GAME_TITLE = "HOP PALS"

-- Place IDs from the Creator Dashboard (see README). 0 = not set up yet.
Config.HUB_PLACE_ID = 0
Config.GAME_PLACE_ID = 0

-- Hub rooms (kiosks): one pad per entry; each party size has its own min/max players.
Config.ROOMS = { "solo", "duo", "duo", "squad", "squad", "party" }
Config.ROOM_SOLO_WAIT = 3
Config.ROOM_WAIT = 20 -- countdown once MIN players are in
Config.ROOM_FULL_WAIT = 5 -- countdown once the room is full
Config.ROOM_START_NOW_WAIT = 3

-- In Studio every mode is unlocked so all levels can be tested (DataStores are often off there)
Config.STUDIO_UNLOCK_ALL = true

-- Rewards for finishing a level, before the squad bonus (Parties.squadMultiplier) and win streak.
-- Paws are spent in the wardrobe; Stars are score only (leaderboard, never spent).
Config.PAWS = { easy = 10, medium = 15, hard = 20, hardcore = 30, endless = 10 }
Config.STARS = { easy = 1, medium = 2, hard = 3, hardcore = 4, endless = 1 }
Config.STARS_NO_FALL_BONUS = 1
Config.STREAK_STEP = 0.1 -- +10% per level cleared in a row
Config.STREAK_CAP = 10 -- so the streak bonus tops out at +100%

-- Robux products (0 = not sold). Robux only buys colour skins and Paw packs, never buddies.
Config.SKIN_PRODUCTS = { mint = 0, caramel = 0, candy = 0, night = 0, gold = 0 }
Config.PAW_PACK = { productId = 0, paws = 500 }

-- Retention: the first clear of a new UTC day pays more; replaying an already cleared level pays less
Config.DAILY_FIRST_CLEAR_MULT = 2
Config.REPLAY_MULT = 0.5

-- Referral: a brand-new player invited by a friend, clearing their first level together with them
Config.REFERRAL_PAWS = 100

-- Roblox group (0 = none yet). Members get a Paws bonus; the hub shows a "join our group" banner.
Config.GROUP_ID = 0
Config.GROUP_PAWS_BONUS = 0.1

-- Badge IDs from the Creator Dashboard (0 = not created yet, nothing is awarded)
Config.BADGES = {
	firstClear = 0, -- clear any level
	noFalls = 0, -- clear a Hard level with nobody falling
	squadOf4 = 0, -- finish a level with 4+ pals at the door
	partyOf8 = 0, -- finish a level with 8 pals at the door
	endless10 = 0, -- reach level 10 in Endless
	hardcoreHero = 0, -- clear Hardcore
}

Config.LEADERBOARD_REFRESH = 3
Config.INVITE_COOLDOWN = 6

-- Falling is a gag: a short tumble, then back to the last checkpoint
Config.KO_TIME = 1.6
Config.CHECKPOINT_SPACING = 14 -- columns between automatic checkpoints

-- Carry & throw
Config.CARRY_REACH = 4.5
Config.CARRY_WALK_SPEED = 11
Config.THROW_VELOCITY = Vector2.new(26, 50)

-- Seesaw
Config.SEESAW_TILT = math.rad(4) -- radians per stud of torque
Config.SEESAW_MAX = math.rad(60)
Config.SEESAW_SPEED = math.rad(55)
Config.SEESAW_DEADZONE = 3
Config.MAX_SLOPE = 42 -- steeper planks make characters slide off

-- Buddy passives
Config.FROG_RADIUS = 12
Config.GECKO_CLING_TIME = 2
Config.GECKO_WALL_JUMP = Vector2.new(20, 50)

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
Config.SPRING_HEIGHT = 17 -- studs a trampoline throws a player up
Config.SAND_DELAY = 0.6 -- seconds a sand block holds a player before crumbling
Config.SAND_RESPAWN = 3
Config.STOP_GRACE = 0.3 -- seconds to react when the light turns red
Config.STOP_SPEED = 3 -- horizontal speed that counts as "moving" on red
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
	buttonPressed = Color3.fromRGB(90, 200, 110),
	gate = Color3.fromRGB(150, 120, 220),
	gate2 = Color3.fromRGB(235, 100, 170),
	spring = Color3.fromRGB(255, 110, 90),
	springStripe = Color3.fromRGB(70, 60, 80),
	sand = Color3.fromRGB(230, 195, 130),
	sandShake = Color3.fromRGB(245, 160, 90),
	mover = Color3.fromRGB(120, 200, 190),
	cannon = Color3.fromRGB(60, 60, 80),
	bullet = Color3.fromRGB(35, 35, 45),
	scrollWall = Color3.fromRGB(240, 80, 80),
	seesaw = Color3.fromRGB(190, 140, 90),
	flag = Color3.fromRGB(190, 190, 200),
	flagActive = Color3.fromRGB(90, 200, 110),
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
