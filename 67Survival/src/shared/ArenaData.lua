--[[
	ArenaData - the battle map "67 TOWN": its zones, mini-boss lairs, 67 VAULTS, special spots
	and the RIFT gates. One table shared by the server that builds the map (Map/BattleMap), the
	run simulation (Sim/ArenaDirector: zone effects, threat, events) and the client (minimap,
	zone chip, per-run map visuals).

	Arena coordinates (x, z) in studs around GameConfig.Arena.Center; -Z is NORTH (up the
	screen: the run camera looks north). The map is a PINWHEEL around the start square:

	        x: -240 ........ -80 ....... 80 ........ 240
	  z -240  +---------------------------+----------+
	          |        THE RIFT  ****     |          |
	   -80    +----------+====gate====+---+  NEON    |
	          | GOOBER   |  67 SQUARE  |    STRIP    |
	    80    | GARDENS  |   (start)   +--------------+
	          |    *     +-------------+  HORDE MART  |
	   240    +----------+        LOT  **             |

	Every outer zone touches the square and its two neighbours, so the zones form a loop:
	SQUARE -> GARDENS -> LOT -> STRIP -> RIFT -> GARDENS. Danger (and reward) grows along it.
	THE RIFT is sealed by crystal cliffs with three gates until it opens (RiftOpensAt).
]]

local ArenaData = {}

local rgb = Color3.fromRGB

export type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }

export type Zone = {
	Index: number,
	Key: string,
	Name: string,
	Tagline: string,
	Stars: number, -- danger 0..4 (shown as stars)
	Rect: Rect,
	Color: Color3, -- minimap / zone chip colour
	Ground: { Color3 }, -- checker tones of the ground tiles
	-- effects on the horde around a player standing in the zone
	HP: number, -- enemy HP multiplier (spawned here)
	Damage: number,
	XP: number, -- XP of the gems dropped here
	Coins: number,
	Elite: number, -- elite chance multiplier
	Flavor: { [string]: number }?, -- extra spawn weight of the zone's own enemies (only when already in the mix)
	Decay: { After: number, XP: number }?, -- the zone pays less after a while (the square)
	Locked: boolean?, -- sealed until RiftOpensAt
}

ArenaData.Zones = {
	{
		Index = 1,
		Key = "Square",
		Name = "67 SQUARE",
		Tagline = "Safe-ish. For now.",
		Stars = 0,
		Rect = { MinX = -80, MaxX = 80, MinZ = -80, MaxZ = 80 },
		Color = rgb(255, 214, 120),
		Ground = { rgb(232, 222, 200), rgb(220, 208, 184) },
		HP = 1,
		Damage = 1,
		XP = 1,
		Coins = 1,
		Elite = 0.5,
		Decay = { After = 180, XP = 0.8 },
	},
	{
		Index = 2,
		Key = "Gardens",
		Name = "GOOBER GARDENS",
		Tagline = "Please don't feed the goobers.",
		Stars = 1,
		Rect = { MinX = -240, MaxX = -80, MinZ = -80, MaxZ = 240 },
		Color = rgb(120, 220, 110),
		Ground = { rgb(124, 206, 104), rgb(110, 192, 94) },
		HP = 1,
		Damage = 1,
		XP = 1.1,
		Coins = 1,
		Elite = 1,
		Flavor = { Goober = 1.6, Splitter = 1.6, Leaper = 1.4 },
	},
	{
		Index = 3,
		Key = "Lot",
		Name = "HORDE MART LOT",
		Tagline = "Everything must go. Especially you.",
		Stars = 2,
		Rect = { MinX = -80, MaxX = 240, MinZ = 80, MaxZ = 240 },
		Color = rgb(110, 170, 255),
		Ground = { rgb(96, 100, 122), rgb(88, 92, 114) },
		HP = 1.12,
		Damage = 1.05,
		XP = 1.25,
		Coins = 1.25,
		Elite = 1.3,
		Flavor = { Charger = 1.6, Bomber = 1.6, Brute = 1.3 },
	},
	{
		Index = 4,
		Key = "Strip",
		Name = "NEON STRIP",
		Tagline = "The house always wins. You are not the house.",
		Stars = 3,
		Rect = { MinX = 80, MaxX = 240, MinZ = -240, MaxZ = 80 },
		Color = rgb(255, 96, 210),
		Ground = { rgb(70, 58, 100), rgb(62, 50, 92) },
		HP = 1.25,
		Damage = 1.1,
		XP = 1.4,
		Coins = 1.5,
		Elite = 1.6,
		Flavor = { Blinker = 1.7, Sniper = 1.5, Spitter = 1.4 },
	},
	{
		Index = 5,
		Key = "Rift",
		Name = "THE RIFT",
		Tagline = "It's a small rift. It's fine.",
		Stars = 4,
		Rect = { MinX = -240, MaxX = 80, MinZ = -240, MaxZ = -80 },
		Color = rgb(176, 110, 255),
		Ground = { rgb(84, 64, 128), rgb(74, 56, 116) },
		HP = 1.45,
		Damage = 1.15,
		XP = 1.7,
		Coins = 1.6,
		Elite = 2.5,
		Flavor = { Ghost = 1.8, Summoner = 1.5, Blinker = 1.4 },
		Locked = true,
	},
} :: { Zone }

ArenaData.ByKey = {} :: { [string]: Zone }
for _, zone in ArenaData.Zones do
	ArenaData.ByKey[zone.Key] = zone
end

ArenaData.RiftOpensAt = 270 -- seconds of run time (4:30)

local function inside(r: Rect, x: number, z: number): boolean
	return x >= r.MinX and x < r.MaxX and z >= r.MinZ and z < r.MaxZ
end
ArenaData.Inside = inside

-- the zone at an arena position (outside the map: the closest edge zone)
function ArenaData.ZoneAt(x: number, z: number): Zone
	local zones = ArenaData.Zones
	if inside(zones[1].Rect, x, z) then
		return zones[1]
	end
	for i = 2, #zones do
		if inside(zones[i].Rect, x, z) then
			return zones[i]
		end
	end
	-- on the border line / outside: clamp inside and retry
	local cx, cz = math.clamp(x, -239.9, 239.9), math.clamp(z, -239.9, 239.9)
	for i = 1, #zones do
		if inside(zones[i].Rect, cx, cz) then
			return zones[i]
		end
	end
	return zones[1]
end

--[[
	LAIRS: where a zone's mini-boss appears and stays (it guards its lair, it does not chase
	you across the map). Pads is only for encounters with more than one body (the twins).
]]
export type Lair = { Key: string, Zone: string, Name: string, X: number, Z: number, R: number, Pads: { { number } }? }

ArenaData.Lairs = {
	{ Key = "DuckPond", Zone = "Gardens", Name = "THE DUCK POND", X = -165, Z = 150, R = 24 },
	{ Key = "Checkout", Zone = "Lot", Name = "CHECKOUT 67", X = 168, Z = 162, R = 24 },
	{ Key = "Jackpot", Zone = "Strip", Name = "THE JACKPOT", X = 160, Z = -160, R = 24 },
	{ Key = "Altars", Zone = "Rift", Name = "THE TWIN ALTARS", X = -80, Z = -170, R = 28, Pads = { { -102, -170 }, { -58, -170 } } },
} :: { Lair }

ArenaData.LairByKey = {} :: { [string]: Lair }
ArenaData.LairOfZone = {} :: { [string]: Lair }
for _, lair in ArenaData.Lairs do
	ArenaData.LairByKey[lair.Key] = lair
	ArenaData.LairOfZone[lair.Zone] = lair
end

--[[
	67 VAULTS: one in every far corner of the map. A vault wakes up now and then (the run's
	director says which); stand on its pad to crack it open: a relic for your trouble.
]]
export type Vault = { Key: string, Zone: string, X: number, Z: number }

ArenaData.Vaults = {
	{ Key = "GardenVault", Zone = "Gardens", X = -218, Z = 218 },
	{ Key = "LotVault", Zone = "Lot", X = 218, Z = 218 },
	{ Key = "StripVault", Zone = "Strip", X = 218, Z = -218 },
	{ Key = "RiftVault", Zone = "Rift", X = -218, Z = -218 },
} :: { Vault }
ArenaData.VaultPad = 7 -- radius of the capture pad
ArenaData.VaultTime = 4 -- seconds on the pad to open it

-- 67 SPOTS: odd places where roaming mini-bosses (TICK TOCK) show up
ArenaData.Spots = {
	{ -40, 176 },
	{ -150, 30 },
	{ 128, 112 },
	{ 160, -50 },
	{ -150, -150 },
	{ 20, -160 },
}

-- the RIFT gates: gaps in the crystal cliffs (sealed until the rift opens)
export type Gate = { Key: string, X: number, Z: number, Axis: string, Width: number }

ArenaData.RiftGates = {
	{ Key = "GardenGate", X = -160, Z = -80, Axis = "X", Width = 22 }, -- the gap runs along X
	{ Key = "SquareGate", X = 0, Z = -80, Axis = "X", Width = 22 },
	{ Key = "StripGate", X = 80, Z = -160, Axis = "Z", Width = 22 },
} :: { Gate }

-- landmarks on the minimap (big things you can orient by)
ArenaData.Landmarks = {
	{ Key = "Arena67", Name = "THE 67 ARENA", X = 0, Z = 0 },
	{ Key = "Duck", Name = "BIG DUCK", X = -190, Z = 70 },
	{ Key = "Store", Name = "HORDE MART", X = 40, Z = 206 },
	{ Key = "Casino", Name = "67 CASINO", X = 212, Z = -40 },
	{ Key = "Obelisk", Name = "THE OBELISK", X = -170, Z = -150 },
}

--[[
	Secrets of the battle map. Region = the SecretRegion key of a trigger in the map (the server
	checks positions): every one is also an account secret (AchievementData). Once per run it
	also pays inside the run (RunReward).
]]
ArenaData.RunSecrets = {
	Backrooms = { Title = "NO-CLIP", Sub = "You found the Backrooms. Something was left here.", Item = "SuspiciousRock" },
	Parked67 = { Title = "PERFECT PARKING", Sub = "Space 67. Of course.", Coins = 67 },
	RiftCrack = { Title = "MIND THE GAP", Sub = "There was something in the crack.", Loot = "Secret" },
}

-- danger stars as text (zone chip, banners)
function ArenaData.StarText(stars: number): string
	if stars <= 0 then
		return "SAFE"
	end
	return string.rep("★", stars)
end

return ArenaData
