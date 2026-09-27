--[[
	WeaponData - the 12 auto-attacking weapons.

	Every weapon fires by itself (Sim/CombatManager.lua has one behaviour per Kind).
	  Base     - stats at level 1
	  Levels   - [level] = additive changes + card text (levels 2..MaxLevel)
	  Rarity   - Common / Rare / Legendary (rarer weapons show up less in level-up offers)
	  Unlock   - Default = true, or unlocked by coins (Cost) or by an achievement
	  MinPlayerLevel - not offered before this run level

	Stat meaning (scaled by the player's stats in shared/Stats.lua):
	  Damage x Might          Cooldown x cooldown mult     Amount + Amount bonus (unless NoAmount)
	  Radius, Orbit, Length x Area       Speed x projectile speed      Duration x Duration
]]

export type WeaponDef = {
	Id: number,
	Key: string,
	Name: string,
	Icon: string,
	Desc: string,
	Kind: string,
	Rarity: string,
	Color: Color3,
	MaxLevel: number,
	NoAmount: boolean?,
	MinPlayerLevel: number?,
	Base: { [string]: number },
	Levels: { [number]: { [string]: any } },
	Unlock: { Default: boolean?, Cost: number?, Achievement: string? },
}

local rgb = Color3.fromRGB

local LIST: { WeaponDef } = ({
	{
		Key = "BrainBlast",
		Name = "Brain Blast",
		Icon = "🧠",
		Desc = "Fires pink energy blasts at the nearest enemy.",
		Kind = "Projectile",
		Rarity = "Common",
		Color = rgb(255, 110, 200),
		MaxLevel = 7,
		Base = { Damage = 10, Cooldown = 1.05, Amount = 1, Radius = 1.3, Speed = 70, Duration = 1.1, Pierce = 1, Knockback = 3, Range = 55 },
		Levels = {
			[2] = { Amount = 1, Desc = "+1 blast" },
			[3] = { Damage = 5, Desc = "+5 damage" },
			[4] = { Amount = 1, Desc = "+1 blast" },
			[5] = { Pierce = 1, Desc = "Blasts pierce 1 more enemy" },
			[6] = { Damage = 6, Cooldown = -0.15, Desc = "+6 damage, fires faster" },
			[7] = { Amount = 1, Damage = 6, Desc = "+1 blast, +6 damage" },
		},
		Unlock = { Default = true },
	},
	{
		Key = "Orb67",
		Name = "67 Orb",
		Icon = "🔮",
		Desc = "Orbs circle around you and bonk anything they touch.",
		Kind = "Orbit",
		Rarity = "Common",
		Color = rgb(170, 90, 255),
		MaxLevel = 7,
		Base = { Damage = 9, Cooldown = 1, Amount = 1, Radius = 1.7, Orbit = 6.7, Speed = 2.7, HitCooldown = 0.55, Knockback = 2.5 },
		Levels = {
			[2] = { Amount = 1, Desc = "+1 orb" },
			[3] = { Damage = 5, Desc = "+5 damage" },
			[4] = { Orbit = 1.5, Speed = 0.5, Desc = "Wider and faster orbit" },
			[5] = { Amount = 1, Desc = "+1 orb" },
			[6] = { Damage = 6, Desc = "+6 damage" },
			[7] = { Amount = 1, Desc = "+1 orb" },
		},
		Unlock = { Default = true },
	},
	{
		Key = "SigmaAura",
		Name = "Sigma Aura",
		Icon = "😎",
		Desc = "A mogging aura that damages every enemy near you.",
		Kind = "Aura",
		Rarity = "Common",
		Color = rgb(255, 205, 60),
		MaxLevel = 7,
		NoAmount = true,
		Base = { Damage = 6, Cooldown = 0.5, Radius = 8.5, Knockback = 0.5 },
		Levels = {
			[2] = { Radius = 1.5, Desc = "Bigger aura" },
			[3] = { Damage = 3, Desc = "+3 damage" },
			[4] = { Cooldown = -0.07, Desc = "Ticks faster" },
			[5] = { Radius = 1.5, Desc = "Bigger aura" },
			[6] = { Damage = 4, Desc = "+4 damage" },
			[7] = { Radius = 2, Damage = 3, Desc = "Bigger aura, +3 damage" },
		},
		Unlock = { Default = true },
	},
	{
		Key = "GoofyHammer",
		Name = "Goofy Hammer",
		Icon = "🔨",
		Desc = "A giant squeaky hammer falls on the biggest crowd.",
		Kind = "Hammer",
		Rarity = "Common",
		Color = rgb(255, 120, 60),
		MaxLevel = 7,
		Base = { Damage = 32, Cooldown = 3.1, Amount = 1, Radius = 7, Range = 42, Knockback = 9, Duration = 0.5 },
		Levels = {
			[2] = { Damage = 12, Desc = "+12 damage" },
			[3] = { Amount = 1, Desc = "+1 hammer" },
			[4] = { Radius = 2, Desc = "Bigger impact" },
			[5] = { Cooldown = -0.5, Desc = "Drops faster" },
			[6] = { Amount = 1, Desc = "+1 hammer" },
			[7] = { Damage = 25, Radius = 2, Desc = "+25 damage, bigger impact" },
		},
		Unlock = { Default = true },
	},
	{
		Key = "NPCMissile",
		Name = "NPC Missile",
		Icon = "🚀",
		Desc = "Homing missiles with tiny NPC pilots. They explode.",
		Kind = "Missile",
		Rarity = "Common",
		Color = rgb(90, 200, 255),
		MaxLevel = 7,
		Base = { Damage = 20, Cooldown = 1.7, Amount = 1, Radius = 4.5, Speed = 42, Duration = 3, Range = 70, Knockback = 5 },
		Levels = {
			[2] = { Amount = 1, Desc = "+1 missile" },
			[3] = { Damage = 8, Desc = "+8 damage" },
			[4] = { Radius = 1.5, Desc = "Bigger explosions" },
			[5] = { Amount = 1, Desc = "+1 missile" },
			[6] = { Cooldown = -0.3, Desc = "Fires faster" },
			[7] = { Amount = 1, Damage = 10, Desc = "+1 missile, +10 damage" },
		},
		Unlock = { Default = true },
	},
	{
		Key = "BrainrotBeam",
		Name = "Brainrot Beam",
		Icon = "🔦",
		Desc = "A beam of pure brainrot at the nearest enemy.",
		Kind = "Beam",
		Rarity = "Common",
		Color = rgb(120, 255, 170),
		MaxLevel = 7,
		Base = { Damage = 22, Cooldown = 1.8, Amount = 1, Radius = 1.6, Length = 44, Knockback = 2 },
		Levels = {
			[2] = { Amount = 1, Desc = "Also fires backwards" },
			[3] = { Damage = 8, Desc = "+8 damage" },
			[4] = { Length = 10, Radius = 0.6, Desc = "Longer, wider beam" },
			[5] = { Cooldown = -0.35, Desc = "Fires faster" },
			[6] = { Amount = 1, Desc = "+1 beam" },
			[7] = { Damage = 15, Desc = "+15 damage" },
		},
		Unlock = { Default = true },
	},
	{
		Key = "PizzaDisc",
		Name = "Pizza Disc",
		Icon = "🍕",
		Desc = "A spinning pizza flies out and comes back. Pierces everything.",
		Kind = "Boomerang",
		Rarity = "Common",
		Color = rgb(255, 180, 60),
		MaxLevel = 7,
		Base = { Damage = 13, Cooldown = 1.8, Amount = 1, Radius = 2.2, Speed = 38, Range = 26, HitCooldown = 0.35, Knockback = 3 },
		Levels = {
			[2] = { Damage = 6, Desc = "+6 damage" },
			[3] = { Amount = 1, Desc = "+1 pizza" },
			[4] = { Radius = 0.8, Range = 6, Desc = "Bigger pizza, flies further" },
			[5] = { Amount = 1, Desc = "+1 pizza" },
			[6] = { Speed = 10, Damage = 6, Desc = "Faster, +6 damage" },
			[7] = { Amount = 1, Desc = "+1 pizza" },
		},
		Unlock = { Default = true },
	},
	{
		Key = "ZapZap",
		Name = "Zap Zap",
		Icon = "⚡",
		Desc = "Lightning strikes random enemies around you.",
		Kind = "Lightning",
		Rarity = "Common",
		Color = rgb(120, 220, 255),
		MaxLevel = 7,
		Base = { Damage = 15, Cooldown = 1.5, Amount = 2, Radius = 2.8, Range = 48, Chain = 0, Knockback = 1 },
		Levels = {
			[2] = { Amount = 1, Desc = "+1 bolt" },
			[3] = { Damage = 8, Desc = "+8 damage" },
			[4] = { Radius = 1.2, Desc = "Bigger strikes" },
			[5] = { Amount = 1, Desc = "+1 bolt" },
			[6] = { Chain = 2, Desc = "Bolts chain to 2 more enemies" },
			[7] = { Amount = 1, Damage = 10, Desc = "+1 bolt, +10 damage" },
		},
		Unlock = { Default = true },
	},
	{
		Key = "BanHammer",
		Name = "Ban Hammer",
		Icon = "⛔",
		Desc = "Slams the ground around you. Massive damage, massive knockback.",
		Kind = "Slam",
		Rarity = "Rare",
		Color = rgb(255, 60, 60),
		MaxLevel = 7,
		NoAmount = true,
		Base = { Damage = 70, Cooldown = 5, Radius = 12, Knockback = 16 },
		Levels = {
			[2] = { Damage = 25, Desc = "+25 damage" },
			[3] = { Radius = 2, Desc = "Bigger slam" },
			[4] = { Cooldown = -0.8, Desc = "Slams faster" },
			[5] = { Damage = 35, Desc = "+35 damage" },
			[6] = { Radius = 3, Desc = "Bigger slam" },
			[7] = { Damage = 50, Cooldown = -0.7, Desc = "+50 damage, slams faster" },
		},
		Unlock = { Cost = 700, Achievement = "BossSlayer" },
	},
	{
		Key = "ChaosOrb",
		Name = "Chaos Orb",
		Icon = "🌀",
		Desc = "Does something random. Explosions, freezes, chain lightning, snacks.",
		Kind = "Chaos",
		Rarity = "Rare",
		Color = rgb(200, 80, 255),
		MaxLevel = 7,
		Base = { Damage = 24, Cooldown = 2.4, Amount = 1, Radius = 6.5, Range = 40, Knockback = 6 },
		Levels = {
			[2] = { Damage = 10, Desc = "+10 damage" },
			[3] = { Amount = 1, Desc = "+1 chaos" },
			[4] = { Radius = 1.5, Desc = "Bigger chaos" },
			[5] = { Cooldown = -0.4, Desc = "More often" },
			[6] = { Amount = 1, Desc = "+1 chaos" },
			[7] = { Damage = 20, Desc = "+20 damage" },
		},
		Unlock = { Cost = 1200, Achievement = "Level25" },
	},
	{
		Key = "Blast67",
		Name = "67 Blast",
		Icon = "💥",
		Desc = "Every 6.7 seconds: a 67 shockwave. Damage is a multiple of 67.",
		Kind = "Blast67",
		Rarity = "Rare",
		Color = rgb(255, 215, 40),
		MaxLevel = 7,
		NoAmount = true,
		Base = { Damage = 67, Cooldown = 6.7, Radius = 21, Knockback = 10 },
		Levels = {
			[2] = { Damage = 67, Desc = "+67 damage" },
			[3] = { Radius = 3, Desc = "Bigger shockwave" },
			[4] = { Damage = 67, Desc = "+67 damage" },
			[5] = { Cooldown = -0.67, Desc = "0.67s faster" },
			[6] = { Damage = 134, Desc = "+134 damage" },
			[7] = { Radius = 4, Damage = 134, Desc = "Bigger, +134 damage" },
		},
		Unlock = { Cost = 1670, Achievement = "SixSeven" },
	},
	{
		Key = "FinalAura",
		Name = "Final Aura",
		Icon = "👑",
		Desc = "Ultimate. A huge aura that melts a % of enemy HP and slows them.",
		Kind = "FinalAura",
		Rarity = "Legendary",
		Color = rgb(255, 240, 150),
		MaxLevel = 7,
		NoAmount = true,
		MinPlayerLevel = 20,
		Base = { Damage = 16, Cooldown = 0.5, Radius = 13, Percent = 0.012, Slow = 0.25, Knockback = 0 },
		Levels = {
			[2] = { Radius = 2, Desc = "Bigger aura" },
			[3] = { Damage = 8, Desc = "+8 damage" },
			[4] = { Percent = 0.006, Desc = "Melts more HP" },
			[5] = { Radius = 2, Desc = "Bigger aura" },
			[6] = { Damage = 10, Desc = "+10 damage" },
			[7] = { Radius = 3, Damage = 12, Desc = "Bigger aura, +12 damage" },
		},
		Unlock = { Cost = 5000, Achievement = "Victory" },
	},
} :: any)

local WeaponData = {}
WeaponData.List = LIST
WeaponData.ByKey = {} :: { [string]: WeaponDef }
WeaponData.ById = {} :: { [number]: WeaponDef }

-- Awakening a max level weapon (rare card)
WeaponData.Awaken = { Damage = 1.6, Radius = 1.25, Amount = 1 }

for id, def in LIST do
	def.Id = id
	WeaponData.ByKey[def.Key] = def
	WeaponData.ById[id] = def
end

function WeaponData.Get(key: string): WeaponDef
	local def = WeaponData.ByKey[key]
	assert(def, "unknown weapon " .. tostring(key))
	return def
end

-- Raw stats of a weapon at a level (before the player's stats)
function WeaponData.RawStats(key: string, level: number): { [string]: number }
	local def = WeaponData.Get(key)
	local out = table.clone(def.Base)
	for l = 2, math.clamp(level, 1, def.MaxLevel) do
		local delta = def.Levels[l]
		if delta then
			for stat, value in delta do
				if type(value) == "number" then
					out[stat] = (out[stat] or 0) + value
				end
			end
		end
	end
	return out
end

return WeaponData
