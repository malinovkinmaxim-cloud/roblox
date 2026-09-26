--[[
	Config - ALL core balance of CHILE SIMULATOR in one place.

	Units: Height is stored in CENTIMETRES (start = 1 cm = 0.01 m, "+1 Height" = +1 cm).
	Every number here is read by the shared Formulas module, which the server uses for the real
	calculation and the client uses only for display / prediction.

	Balance is checked by `lune run tests/balance.luau` (simulated player, prints a timeline).
]]

local Config = {}

Config.GAME_NAME = "CHILE SIMULATOR"
Config.DATA_VERSION = 1

---------------------------------------------------------------------------
-- Height
---------------------------------------------------------------------------
Config.START_HEIGHT = 1 -- cm (0.01 m): a nearly flat little guy

---------------------------------------------------------------------------
-- Tapping + anti-cheat
---------------------------------------------------------------------------
Config.Tap = {
	-- the server accepts at most this many taps per second (token bucket)
	MaxPerSecond = 16,
	-- short bursts above the rate are allowed up to this many stored tokens
	Burst = 20,
	-- one Tap remote may carry at most this many taps (client batches every 0.1 s)
	MaxBatch = 12,
	-- the client flushes its tap batch this often
	ClientFlushInterval = 0.1,
	-- Auto Tap (boost / gamepass): taps per second the server performs for you
	AutoTapRate = 6,
	-- manual taps + auto taps together are capped at this rate
	CombinedMax = 18,
}

---------------------------------------------------------------------------
-- Coins
---------------------------------------------------------------------------
Config.Coins = {
	-- coins per tap = PerTapBase * (height gained by the tap in cm) ^ GainExponent
	--                 * coin multipliers * heightBonus
	PerTapBase = 1,
	GainExponent = 0.8,
	-- taller = richer: heightBonus = 1 + HeightBonusPerDecade * log10(1 + height in metres)
	HeightBonusPerDecade = 0.3,
	-- auto growth pays this fraction of what the same growth would pay when tapped
	AutoCoinFactor = 0.3,
}

---------------------------------------------------------------------------
-- Upgrades (bought with Coins, kept through Rebirth)
---------------------------------------------------------------------------
Config.Upgrades = {
	TapPower = {
		Name = "TAP POWER",
		Icon = "👆",
		MaxLevel = 150,
		BaseCost = 40,
		-- level n+1 costs (RatioStart - RatioDecay * n) times more than level n, never below RatioMin
		RatioStart = 6,
		RatioDecay = 0.3,
		RatioMin = 2.3,
	},
	AutoGrow = {
		Name = "AUTO GROW",
		Icon = "🌱",
		MaxLevel = 150,
		BaseCost = 150,
		RatioStart = 6.4,
		RatioDecay = 0.3,
		RatioMin = 2.5,
	},
}

---------------------------------------------------------------------------
-- Rebirth
---------------------------------------------------------------------------
Config.Rebirth = {
	BaseCost = 10000, -- first rebirth: cm = 100 m
	-- rebirth i+1 costs RatioStart - RatioDecay * i times more than rebirth i (never below RatioMin)
	RatioStart = 8,
	RatioDecay = 0.5,
	RatioMin = 1.8,
	-- multiplier = round(1 + r + Quadratic * r^2): R1 x2, R2 x3, R3 x5, R10 x21, R100 x1101
	Quadratic = 0.1,
	-- gems for rebirth number r (1-based): Base + PerRebirth * r
	GemsBase = 3,
	GemsPerRebirth = 1,
	GemsMax = 250,
}

---------------------------------------------------------------------------
-- Titles over the head (by current height in metres)
---------------------------------------------------------------------------
Config.Titles = {
	{ Min = 0, Name = "Tiny", Color = Color3.fromRGB(190, 190, 200) },
	{ Min = 1, Name = "Small", Color = Color3.fromRGB(150, 220, 255) },
	{ Min = 10, Name = "Normal", Color = Color3.fromRGB(120, 235, 140) },
	{ Min = 100, Name = "Tall", Color = Color3.fromRGB(90, 200, 255) },
	{ Min = 1e3, Name = "Giant", Color = Color3.fromRGB(255, 200, 60) },
	{ Min = 1e5, Name = "Massive", Color = Color3.fromRGB(255, 140, 50) },
	{ Min = 1e7, Name = "Colossal", Color = Color3.fromRGB(255, 80, 90) },
	{ Min = 1e10, Name = "Titan", Color = Color3.fromRGB(200, 90, 255) },
	{ Min = 1e14, Name = "God", Color = Color3.fromRGB(255, 240, 150) },
	{ Min = 1e20, Name = "UNREAL", Color = Color3.fromRGB(255, 60, 220) },
}

---------------------------------------------------------------------------
-- Height milestones: big "viral moment" announcements (metres). Each one fires once per
-- player ever; world props are sized so that the text is literally true.
---------------------------------------------------------------------------
Config.Milestones = {
	{ Id = "grass", Meters = 1, Text = "🌱 YOU GREW OUT OF THE GRASS!" },
	{ Id = "house", Meters = 1e3, Text = "🏠 YOU ARE TALLER THAN A HOUSE!" },
	{ Id = "tower", Meters = 1e5, Text = "🏙️ YOU ARE TALLER THAN A SKYSCRAPER!" },
	{ Id = "chile", Meters = 4.3e6, Text = "🇨🇱 YOU ARE AS LONG AS CHILE! (4,300 km)" },
	{ Id = "city", Meters = 1e7, Text = "🌆 YOU ARE BIGGER THAN THE CITY!" },
	{ Id = "clouds", Meters = 1e8, Text = "☁️ YOUR HEAD REACHED THE CLOUDS!" },
	{ Id = "moon", Meters = 1e9, Text = "🌕 YOU TOUCHED THE MOON!" },
	{ Id = "galaxy", Meters = 1e13, Text = "🌌 YOU ARE BIGGER THAN THE GALAXY!" },
	{ Id = "unreal", Meters = 1e20, Text = "😱 THIS IS NOT EVEN REAL ANYMORE" },
}

-- Global "taller than X% of players" announcements (percent thresholds)
Config.PercentileAnnouncements = { 50, 75, 90, 95, 99, 99.9 }
-- percentiles are only announced when at least this many players are in the histogram
Config.PercentileMinPlayers = 40

---------------------------------------------------------------------------
-- Character / world
---------------------------------------------------------------------------
Config.Character = {
	BaseWalkSpeed = 18,
	-- walk speed grows with the visual body height (long legs = long steps)
	MaxWalkSpeed = 60,
	WalkSpeedPerStud = 0.12,
}

Config.Save = {
	AutosaveInterval = 90,
	MaxRetries = 5,
	-- another server holding the session lock longer than this is considered dead
	SessionLockTimeout = 60 * 10,
}

Config.Leaderboards = {
	RefreshInterval = 75,
	TopCount = 10,
}

-- Studio-only / admin cheat commands (see AdminService). Add UserIds for live-game admins.
Config.ADMIN_USER_IDS = {}

return Config
