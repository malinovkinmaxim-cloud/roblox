--[[
	ZoneConfig - the 7 worlds, laid out one after another along +X.

	A zone unlocks when your BEST height ever reaches Unlock (metres), so zones stay open
	after Rebirth. Standing in a zone multiplies your growth and coins (server decides which
	zone you are in from your position AND your unlocks, so teleport exploits gain nothing).
]]

local ZoneConfig = {}

ZoneConfig.Length = 360 -- studs along X per zone
ZoneConfig.Width = 300 -- studs along Z
ZoneConfig.Gap = 0 -- zones touch; a gate sits on the border

ZoneConfig.Zones = {
	{
		Id = 1,
		Name = "Tiny Land",
		Unlock = 0,
		Multiplier = 1,
		Ground = Color3.fromRGB(110, 205, 90),
		Accent = Color3.fromRGB(255, 120, 190),
		Lighting = { ClockTime = 13.5, Tint = Color3.fromRGB(255, 255, 255), Density = 0.28, Haze = 1.2, Color = Color3.fromRGB(205, 235, 255), Brightness = 2.4, Saturation = 0.12 },
		Description = "Giant grass and flowers. Everything is bigger than you. For now.",
	},
	{
		Id = 2,
		Name = "Normal World",
		Unlock = 10,
		Multiplier = 1.5,
		Ground = Color3.fromRGB(95, 175, 80),
		Accent = Color3.fromRGB(230, 90, 70),
		Lighting = { ClockTime = 15, Tint = Color3.fromRGB(255, 250, 240), Density = 0.3, Haze = 1.4, Color = Color3.fromRGB(215, 230, 250), Brightness = 2.3, Saturation = 0.05 },
		Description = "A normal little town. Houses, trees, a road.",
	},
	{
		Id = 3,
		Name = "Giant City",
		Unlock = 100,
		Multiplier = 2,
		Ground = Color3.fromRGB(80, 84, 96),
		Accent = Color3.fromRGB(255, 190, 60),
		Lighting = { ClockTime = 17.2, Tint = Color3.fromRGB(255, 225, 200), Density = 0.34, Haze = 2, Color = Color3.fromRGB(255, 205, 170), Brightness = 2.1, Saturation = 0.1 },
		Description = "Skyscrapers. Grow until the city is at your ankles.",
	},
	{
		Id = 4,
		Name = "Cloud World",
		Unlock = 1000,
		Multiplier = 3,
		Ground = Color3.fromRGB(235, 242, 255),
		Accent = Color3.fromRGB(140, 200, 255),
		Lighting = { ClockTime = 12, Tint = Color3.fromRGB(245, 250, 255), Density = 0.4, Haze = 2.5, Color = Color3.fromRGB(240, 248, 255), Brightness = 2.8, Saturation = 0 },
		Description = "Walk on clouds.",
	},
	{
		Id = 5,
		Name = "Sky World",
		Unlock = 1e4,
		Multiplier = 4,
		Ground = Color3.fromRGB(120, 175, 255),
		Accent = Color3.fromRGB(255, 255, 255),
		Lighting = { ClockTime = 10, Tint = Color3.fromRGB(220, 235, 255), Density = 0.25, Haze = 0.6, Color = Color3.fromRGB(150, 200, 255), Brightness = 2.6, Saturation = 0.2 },
		Description = "Floating islands high above the world.",
	},
	{
		Id = 6,
		Name = "Space",
		Unlock = 1e6,
		Multiplier = 6,
		Ground = Color3.fromRGB(70, 70, 90),
		Accent = Color3.fromRGB(120, 255, 240),
		Lighting = { ClockTime = 0, Tint = Color3.fromRGB(210, 220, 255), Density = 0.05, Haze = 0, Color = Color3.fromRGB(40, 40, 70), Brightness = 1.4, Saturation = 0.15 },
		Description = "Moon rocks, planets, zero air.",
	},
	{
		Id = 7,
		Name = "Galaxy",
		Unlock = 1e9,
		Multiplier = 10,
		Ground = Color3.fromRGB(60, 25, 110),
		Accent = Color3.fromRGB(255, 80, 230),
		Lighting = { ClockTime = 0, Tint = Color3.fromRGB(235, 200, 255), Density = 0.18, Haze = 1.5, Color = Color3.fromRGB(150, 70, 220), Brightness = 1.6, Saturation = 0.35 },
		Description = "The end of everything. Or is it?",
	},
}

-- Centre of zone i on the X axis
function ZoneConfig.CenterX(index: number): number
	return (index - 1) * (ZoneConfig.Length + ZoneConfig.Gap)
end

-- Zone index from an X position (clamped to the valid range)
function ZoneConfig.IndexFromX(x: number): number
	local i = math.floor((x + ZoneConfig.Length / 2) / (ZoneConfig.Length + ZoneConfig.Gap)) + 1
	return math.clamp(i, 1, #ZoneConfig.Zones)
end

-- Highest zone unlocked by a best height (cm)
function ZoneConfig.HighestUnlocked(bestHeightCm: number): number
	local meters = bestHeightCm / 100
	local best = 1
	for i, zone in ZoneConfig.Zones do
		if meters >= zone.Unlock then
			best = i
		end
	end
	return best
end

return ZoneConfig
