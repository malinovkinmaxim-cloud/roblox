--[[
	UpgradeData - the LEVEL UP upgrades (every card that is not an ability): the frequent,
	small decisions of a run. Every upgrade has several LEVELS (usually 5, 3-7); taking the
	card again raises it by one. Higher levels are not only bigger numbers: the level marked
	New changes how the upgrade works (a ricochet, a shield that knocks back, a free reroll...).

	Categories (the card shows them):
	  OFFENSE      damage, attack speed, crits, damage vs elites / bosses / low / high HP,
	               combo and kill-streak mechanics
	  PROJECTILES  more / faster / bigger shots, pierce, ricochet, split, homing, explosions,
	               return, chain (they change every PROJECTILE ability, Sim/CombatManager)
	  DEFENSE      max HP, armour, a plating shield, regeneration, damage reduction, dodge,
	               low-HP and emergency protection, lifesteal
	  MOVEMENT     move speed, momentum, attack speed while moving, stride pulses, dash
	  XP           XP gain, pickup range, XP streaks, elite / boss XP, conversions

	Fields (the shape every upgrade and item shares, see also shared/ItemData.lua)
	  Key          id (saved in the collection: never rename)
	  Name, Desc   the card; Desc is what the upgrade does in general
	  Category     one of UpgradeData.Categories
	  Rarity       shared/Rarity.lua: how often the card shows up
	  Symbol       the icon (UI/Icons categories)
	  Requires     only offered when this holds: { Category = "PROJECTILE" } (you own an
	               ability of that category) or { Dash = true } (you can dash)
	  Levels[n]    what level n gives IN TOTAL (not on top of n-1):
	                 Stats  shared/Stats.lua bonuses
	                 P      numbers of its mechanic (Sim/Perks.lua reads them by Key)
	                 Desc   the short change shown on the card ("+16% attack speed")
	                 New    this level unlocks a mechanic (highlighted on the card)
	  MaxLevel     #Levels
	  Secret       only offered after that secret was discovered
	  Synergies    shared/SynergyData.lua lists the builds each upgrade is part of

	Evolutions (shared/WeaponData.lua) need some of these at level 1 or more: RapidFire,
	OrbitalMastery, BurnMastery, CritMaster, Berserk, DoubleShot, Magnet, Wisdom, Expansion,
	Swiftness, Armor, Duration.
]]

export type Level = { Stats: { [string]: number }?, P: { [string]: any }?, Desc: string, New: string? }
export type PassiveDef = {
	Key: string,
	Name: string,
	Desc: string,
	Category: string,
	Rarity: string,
	Symbol: string,
	Requires: { [string]: any }?,
	Levels: { Level },
	MaxLevel: number,
	Secret: string?,
}

local UpgradeData = {}

UpgradeData.Categories = { "OFFENSE", "PROJECTILES", "DEFENSE", "MOVEMENT", "XP" }

-- levels from columns: stat(s) per level + one mechanic level
local function levels(n: number, build: (number) -> Level): { Level }
	local out = {}
	for i = 1, n do
		out[i] = build(i)
	end
	return out
end

local function pct(x: number): string
	return string.format("%d%%", math.floor(x * 100 + 0.5))
end

-- (MaxLevel is filled in below from #Levels)
local passives: { any } = {
	-------------------------------------------------------------------- OFFENSE
	{
		Key = "Power",
		Name = "Power",
		Desc = "More damage for every ability.",
		Category = "OFFENSE",
		Rarity = "Common",
		Symbol = "Attack",
		Levels = levels(5, function(i)
			local v = ({ 0.08, 0.16, 0.25, 0.35, 0.48 })[i]
			return {
				Stats = { Might = v },
				P = if i == 5 then { Triple = 0.05 } else nil,
				Desc = "+" .. pct(v) .. " damage",
				New = if i == 5 then "Hits have a 5% chance to deal triple damage" else nil,
			}
		end),
	},
	{
		Key = "RapidFire",
		Name = "Fast Hands",
		Desc = "Abilities recharge faster.",
		Category = "OFFENSE",
		Rarity = "Common",
		Symbol = "Speed",
		Levels = levels(5, function(i)
			local v = ({ 0.08, 0.16, 0.25, 0.35, 0.5 })[i]
			return {
				Stats = { AttackSpeed = v },
				P = if i == 5 then { Echo = 10 } else nil,
				Desc = "+" .. pct(v) .. " attack speed",
				New = if i == 5 then "Every 10th cast of an ability fires twice" else nil,
			}
		end),
	},
	{
		Key = "CritMaster",
		Name = "Crit Master",
		Desc = "Critical hits (x2 damage) more often.",
		Category = "OFFENSE",
		Rarity = "Uncommon",
		Symbol = "Attack",
		Levels = levels(5, function(i)
			local v = i * 0.05
			return {
				Stats = { Crit = v },
				P = if i == 5 then { CritChain = 0.5 } else nil,
				Desc = "+" .. pct(v) .. " crit chance",
				New = if i == 5 then "Crits jump to a nearby enemy for 50% damage" else nil,
			}
		end),
	},
	{
		Key = "Brutal",
		Name = "Brutal",
		Desc = "Critical hits hit harder.",
		Category = "OFFENSE",
		Rarity = "Uncommon",
		Symbol = "Attack",
		Levels = levels(5, function(i)
			local v = ({ 0.2, 0.4, 0.65, 0.9, 1.2 })[i]
			return {
				Stats = { CritMult = v },
				P = if i == 5 then { Crack = 0.1, CrackTime = 3 } else nil,
				Desc = "+" .. pct(v) .. " crit damage",
				New = if i == 5 then "Crits crack armour: +10% damage taken for 3 s" else nil,
			}
		end),
	},
	{
		Key = "GiantSlayer",
		Name = "Giant Slayer",
		Desc = "More damage to elites and bosses.",
		Category = "OFFENSE",
		Rarity = "Uncommon",
		Symbol = "Attack",
		Levels = levels(5, function(i)
			local v = ({ 0.1, 0.2, 0.3, 0.4, 0.55 })[i]
			return {
				P = { Big = v, Exposed = if i == 5 then 0.5 else nil },
				Desc = "+" .. pct(v) .. " damage to elites and bosses",
				New = if i == 5 then "Weak points take +50% more" else nil,
			}
		end),
	},
	{
		Key = "Execution",
		Name = "Execution",
		Desc = "More damage to enemies below 35% HP; later: instant finishers.",
		Category = "OFFENSE",
		Rarity = "Rare",
		Symbol = "Attack",
		Levels = levels(5, function(i)
			local v = ({ 0.15, 0.25, 0.3, 0.38, 0.5 })[i]
			local ex = ({ 0, 0, 0.06, 0.08, 0.1 })[i]
			return {
				Stats = { Execute = ex },
				P = { Low = v },
				Desc = "+" .. pct(v) .. " damage to wounded enemies" .. (if ex > 0 then ", " .. pct(ex) .. " finishers" else ""),
				New = if i == 3 then "Hits can instantly finish normal enemies below 20% HP" else nil,
			}
		end),
	},
	{
		Key = "Bully",
		Name = "Opening Strike",
		Desc = "More damage to healthy enemies (above 80% HP).",
		Category = "OFFENSE",
		Rarity = "Common",
		Symbol = "Attack",
		Levels = levels(5, function(i)
			local v = ({ 0.15, 0.25, 0.35, 0.45, 0.55 })[i]
			return {
				P = { High = v, First = if i == 5 then 0.5 else nil },
				Desc = "+" .. pct(v) .. " damage to healthy enemies",
				New = if i == 5 then "Your first hit on every enemy deals +50%" else nil,
			}
		end),
	},
	{
		Key = "Combo",
		Name = "Combo",
		Desc = "Keep hitting: every 10 hits in a row add +1% damage. A pause resets it.",
		Category = "OFFENSE",
		Rarity = "Uncommon",
		Symbol = "Growth",
		Levels = levels(5, function(i)
			local v = ({ 0.1, 0.15, 0.2, 0.25, 0.3 })[i]
			return {
				P = { Max = v, Blast = if i == 5 then 40 else nil },
				Desc = "Combo up to +" .. pct(v) .. " damage",
				New = if i == 5 then "At full combo every 40th hit releases a blast" else nil,
			}
		end),
	},
	{
		Key = "Rampage",
		Name = "Rampage",
		Desc = "Kills within 2 s build a streak: +0.5% damage per kill.",
		Category = "OFFENSE",
		Rarity = "Uncommon",
		Symbol = "Growth",
		Levels = levels(5, function(i)
			local v = ({ 0.1, 0.15, 0.2, 0.25, 0.3 })[i]
			return {
				P = { Max = v, Wave = if i == 5 then 30 else nil },
				Desc = "Streak up to +" .. pct(v) .. " damage",
				New = if i == 5 then "Every 30 streak kills release a shockwave" else nil,
			}
		end),
	},
	{
		Key = "Expansion",
		Name = "Expansion",
		Desc = "Bigger abilities.",
		Category = "OFFENSE",
		Rarity = "Common",
		Symbol = "Area",
		Levels = levels(5, function(i)
			local v = i * 0.1
			return {
				Stats = { Area = v },
				P = if i == 5 then { AuraSlow = 0.2 } else nil,
				Desc = "+" .. pct(v) .. " area",
				New = if i == 5 then "Auras and fields also slow enemies by 20%" else nil,
			}
		end),
	},
	{
		Key = "Duration",
		Name = "Duration",
		Desc = "Effects last longer.",
		Category = "OFFENSE",
		Rarity = "Common",
		Symbol = "Area",
		Levels = levels(4, function(i)
			local v = ({ 0.12, 0.24, 0.36, 0.5 })[i]
			return {
				Stats = { Duration = v },
				P = if i == 4 then { Control = 1.5 } else nil,
				Desc = "+" .. pct(v) .. " effect duration",
				New = if i == 4 then "Your stuns and freezes last 50% longer" else nil,
			}
		end),
	},
	{
		Key = "BurnMastery",
		Name = "Burn Mastery",
		Desc = "Burning deals more damage.",
		Category = "OFFENSE",
		Rarity = "Uncommon",
		Symbol = "Area",
		Levels = levels(3, function(i)
			local v = i * 0.35
			return {
				Stats = { Burn = v },
				P = if i == 3 then { Spread = true } else nil,
				Desc = "+" .. pct(v) .. " burn damage",
				New = if i == 3 then "Burning enemies spread the fire when they die" else nil,
			}
		end),
	},
	{
		Key = "OrbitalMastery",
		Name = "Orbital Mastery",
		Desc = "Orbiting weapons spin faster and wider.",
		Category = "OFFENSE",
		Rarity = "Uncommon",
		Symbol = "Area",
		Levels = levels(3, function(i)
			local v = i * 0.2
			return {
				Stats = { Orbital = v },
				P = if i == 3 then { Big = 0.3 } else nil,
				Desc = "Orbits +" .. pct(v) .. " faster and wider",
				New = if i == 3 then "Orbiting weapons deal +30% to elites and bosses" else nil,
			}
		end),
	},
	{
		Key = "Percent67",
		Name = "67%",
		Desc = "Every hit: 67% chance to deal +67% damage. Something is coming...",
		Category = "OFFENSE",
		Rarity = "Legendary",
		Symbol = "Special",
		Levels = { { Desc = "67% chance: +67% damage" } },
	},
	-------------------------------------------------------------------- PROJECTILES
	{
		Key = "DoubleShot",
		Name = "Multishot",
		Desc = "+1 projectile for every ability.",
		Category = "PROJECTILES",
		Rarity = "Rare",
		Symbol = "Attack",
		Levels = levels(3, function(i)
			return {
				Stats = { Amount = math.min(i, 2) },
				P = if i == 3 then { Pierce = 1 } else nil,
				Desc = "+" .. math.min(i, 2) .. " projectile" .. (if i > 1 then "s" else ""),
				New = if i == 3 then "Projectiles pierce 1 more enemy" else nil,
			}
		end),
	},
	{
		Key = "Velocity",
		Name = "Velocity",
		Desc = "Faster projectiles that fly further.",
		Category = "PROJECTILES",
		Rarity = "Common",
		Symbol = "Speed",
		Requires = { Category = "PROJECTILE" },
		Levels = levels(5, function(i)
			local v = ({ 0.15, 0.3, 0.45, 0.6, 0.8 })[i]
			return {
				Stats = { ProjSpeed = v, Range = i * 0.05 },
				P = if i == 5 then { Pierce = 1 } else nil,
				Desc = "+" .. pct(v) .. " projectile speed, +" .. pct(i * 0.05) .. " range",
				New = if i == 5 then "Fast shots pierce 1 more enemy" else nil,
			}
		end),
	},
	{
		Key = "BigShots",
		Name = "Big Shots",
		Desc = "Bigger projectiles hit more enemies.",
		Category = "PROJECTILES",
		Rarity = "Common",
		Symbol = "Area",
		Requires = { Category = "PROJECTILE" },
		Levels = levels(5, function(i)
			local v = ({ 0.15, 0.3, 0.45, 0.6, 0.8 })[i]
			return {
				P = { Size = v, Knock = if i == 5 then 2 else nil },
				Desc = "+" .. pct(v) .. " projectile size",
				New = if i == 5 then "Projectiles knock enemies back 3x harder" else nil,
			}
		end),
	},
	{
		Key = "Penetration",
		Name = "Penetration",
		Desc = "Projectiles pierce through enemies.",
		Category = "PROJECTILES",
		Rarity = "Uncommon",
		Symbol = "Attack",
		Requires = { Category = "PROJECTILE" },
		Levels = levels(5, function(i)
			local v = ({ 1, 2, 2, 3, 4 })[i]
			return {
				P = { Pierce = v, Grow = if i >= 3 then 0.1 else nil },
				Desc = "+" .. v .. " pierce",
				New = if i == 3 then "Every enemy pierced adds +10% damage to the next" else nil,
			}
		end),
	},
	{
		Key = "Ricochet",
		Name = "Ricochet",
		Desc = "Projectiles bounce to another enemy instead of stopping.",
		Category = "PROJECTILES",
		Rarity = "Rare",
		Symbol = "Special",
		Requires = { Category = "PROJECTILE" },
		Levels = levels(5, function(i)
			local v = ({ 1, 1, 2, 2, 3 })[i]
			local range = ({ 14, 17, 17, 20, 20 })[i]
			return {
				P = { Ricochet = v, Range = range, Seek = if i == 5 then true else nil },
				Desc = v .. " ricochet" .. (if v > 1 then "s" else "") .. ", reach " .. range,
				New = if i == 5 then "Ricochets seek elites and bosses first" else nil,
			}
		end),
	},
	{
		Key = "Split",
		Name = "Split",
		Desc = "Projectiles can split into smaller shots when they hit.",
		Category = "PROJECTILES",
		Rarity = "Rare",
		Symbol = "Special",
		Requires = { Category = "PROJECTILE" },
		Levels = levels(5, function(i)
			local v = ({ 0.2, 0.35, 0.5, 0.65, 1 })[i]
			return {
				P = { Chance = v, Count = if i == 5 then 3 else 2 },
				Desc = pct(v) .. " chance to split in " .. (if i == 5 then 3 else 2),
				New = if i == 5 then "Every shot splits into 3" else nil,
			}
		end),
	},
	{
		Key = "Homing",
		Name = "Homing",
		Desc = "Projectiles curve towards enemies.",
		Category = "PROJECTILES",
		Rarity = "Uncommon",
		Symbol = "Speed",
		Requires = { Category = "PROJECTILE" },
		Levels = levels(5, function(i)
			local v = ({ 1.5, 2.5, 3.5, 4.5, 6 })[i]
			return {
				P = { Turn = v, Retarget = if i == 5 then true else nil },
				Desc = "Homing strength " .. i .. "/5",
				New = if i == 5 then "Shots pick a new target after every hit" else nil,
			}
		end),
	},
	{
		Key = "Explosive",
		Name = "Explosive Rounds",
		Desc = "Projectile hits can explode.",
		Category = "PROJECTILES",
		Rarity = "Rare",
		Symbol = "Area",
		Requires = { Category = "PROJECTILE" },
		Levels = levels(5, function(i)
			local v = ({ 0.15, 0.25, 0.35, 0.5, 1 })[i]
			return {
				P = { Chance = v, Radius = 2.8 + i * 0.2, Share = 0.4, Burn = if i == 5 then true else nil },
				Desc = pct(v) .. " of hits explode",
				New = if i == 5 then "Every hit explodes and sets enemies on fire" else nil,
			}
		end),
	},
	{
		Key = "Return",
		Name = "Return Policy",
		Desc = "Straight shots come back to you, hitting again on the way.",
		Category = "PROJECTILES",
		Rarity = "Uncommon",
		Symbol = "Speed",
		Requires = { Category = "PROJECTILE" },
		Levels = levels(5, function(i)
			local v = ({ 0.6, 0.7, 0.8, 0.9, 1 })[i]
			return {
				P = { Return = v, Pierce = if i == 5 then true else nil },
				Desc = "Returning shots deal " .. pct(v),
				New = if i == 5 then "Returning shots pierce everything" else nil,
			}
		end),
	},
	{
		Key = "ChainShot",
		Name = "Chain Reaction",
		Desc = "Projectile hits can zap a nearby enemy.",
		Category = "PROJECTILES",
		Rarity = "Uncommon",
		Symbol = "Special",
		Requires = { Category = "PROJECTILE" },
		Levels = levels(5, function(i)
			local v = ({ 0.15, 0.25, 0.35, 0.45, 0.6 })[i]
			return {
				P = { Chance = v, Share = 0.5, Jumps = if i == 5 then 2 else 1 },
				Desc = pct(v) .. " chance to zap",
				New = if i == 5 then "Zaps jump twice" else nil,
			}
		end),
	},
	-------------------------------------------------------------------- DEFENSE
	{
		Key = "Vitality",
		Name = "Vitality",
		Desc = "More max HP.",
		Category = "DEFENSE",
		Rarity = "Common",
		Symbol = "Health",
		Levels = levels(5, function(i)
			return {
				Stats = { MaxHP = i * 20 },
				P = if i == 5 then { Pulse = 20, Heal = 0.1 } else nil,
				Desc = "+" .. (i * 20) .. " max HP",
				New = if i == 5 then "Every 20 s you heal 10% of your max HP" else nil,
			}
		end),
	},
	{
		Key = "Armor",
		Name = "Armor",
		Desc = "Less damage from every hit.",
		Category = "DEFENSE",
		Rarity = "Uncommon",
		Symbol = "Defense",
		Levels = levels(4, function(i)
			return {
				Stats = { Armor = i },
				P = if i == 4 then { BossCut = 0.15 } else nil,
				Desc = "-" .. i .. " damage from every hit",
				New = if i == 4 then "Boss attacks deal 15% less" else nil,
			}
		end),
	},
	{
		Key = "Regeneration",
		Name = "Regeneration",
		Desc = "Heal over time.",
		Category = "DEFENSE",
		Rarity = "Common",
		Symbol = "Health",
		Levels = levels(5, function(i)
			local v = i * 0.4
			return {
				Stats = { Regen = v },
				P = if i == 5 then { Low = 2 } else nil,
				Desc = string.format("+%.1f HP per second", v),
				New = if i == 5 then "Regeneration doubles below 50% HP" else nil,
			}
		end),
	},
	{
		Key = "Plating",
		Name = "Plating",
		Desc = "A shield that soaks up damage and refills after 4 s without being hit.",
		Category = "DEFENSE",
		Rarity = "Uncommon",
		Symbol = "Defense",
		Levels = levels(5, function(i)
			return {
				P = { Max = i * 10, Delay = 4, Rate = 4 + i, Break = if i == 5 then true else nil },
				Desc = (i * 10) .. " shield",
				New = if i == 5 then "When your plating breaks it knocks enemies back" else nil,
			}
		end),
	},
	{
		Key = "ToughSkin",
		Name = "Tough Skin",
		Desc = "Take less damage.",
		Category = "DEFENSE",
		Rarity = "Uncommon",
		Symbol = "Defense",
		Levels = levels(5, function(i)
			local v = i * 0.04
			return {
				P = { Cut = v, Cap = if i == 5 then 0.25 else nil },
				Desc = "-" .. pct(v) .. " damage taken",
				New = if i == 5 then "No single hit can take more than 25% of your max HP" else nil,
			}
		end),
	},
	{
		Key = "Dodge",
		Name = "Slippery",
		Desc = "A chance to dodge a hit completely.",
		Category = "DEFENSE",
		Rarity = "Uncommon",
		Symbol = "Speed",
		Levels = levels(5, function(i)
			local v = i * 0.04
			return {
				P = { Chance = v, Slip = if i == 5 then true else nil },
				Desc = pct(v) .. " dodge chance",
				New = if i == 5 then "Dodging knocks nearby enemies off their feet" else nil,
			}
		end),
	},
	{
		Key = "LastStand",
		Name = "Last Stand",
		Desc = "Below 30% HP: more damage and less damage taken.",
		Category = "DEFENSE",
		Rarity = "Rare",
		Symbol = "Defense",
		Levels = levels(5, function(i)
			local v = ({ 0.1, 0.15, 0.2, 0.25, 0.3 })[i]
			return {
				P = { At = 0.3, Might = v, Cut = v, Regen = if i == 5 then 2 else nil },
				Desc = "Low HP: +" .. pct(v) .. " damage, -" .. pct(v) .. " damage taken",
				New = if i == 5 then "Below 30% HP you regenerate 2 HP per second" else nil,
			}
		end),
	},
	{
		Key = "PanicButton",
		Name = "Panic Button",
		Desc = "Falling below 25% HP blasts the horde away and makes you untouchable for 2 s.",
		Category = "DEFENSE",
		Rarity = "Rare",
		Symbol = "Defense",
		Levels = levels(4, function(i)
			local cd = ({ 90, 75, 60, 50 })[i]
			return {
				P = { At = 0.25, Cooldown = cd, Radius = 16, Invulnerable = 2, Heal = if i == 4 then 0.25 else nil },
				Desc = "Recharges in " .. cd .. " s",
				New = if i == 4 then "It also heals 25% of your max HP" else nil,
			}
		end),
	},
	{
		Key = "Vampire",
		Name = "Vampire",
		Desc = "A chance to heal 3 HP on every kill.",
		Category = "DEFENSE",
		Rarity = "Uncommon",
		Symbol = "Health",
		Levels = levels(4, function(i)
			local v = ({ 0.06, 0.1, 0.14, 0.18 })[i]
			return {
				Stats = { Lifesteal = v },
				P = if i == 4 then { EliteHeal = 0.15 } else nil,
				Desc = pct(v) .. " chance to heal on a kill",
				New = if i == 4 then "Killing an elite heals 15% of your max HP" else nil,
			}
		end),
	},
	{
		Key = "Berserk",
		Name = "Berserk",
		Desc = "The lower your HP, the faster you attack.",
		Category = "DEFENSE",
		Rarity = "Uncommon",
		Symbol = "Attack",
		Levels = levels(4, function(i)
			return {
				Stats = { Berserk = i * 0.2 },
				P = if i == 4 then { LowSpeed = 0.2 } else nil,
				Desc = "Up to +" .. pct(i * 0.2) .. " attack speed at low HP",
				New = if i == 4 then "Below 50% HP you also move 20% faster" else nil,
			}
		end),
	},
	-------------------------------------------------------------------- MOVEMENT
	{
		Key = "Swiftness",
		Name = "Swiftness",
		Desc = "Move faster.",
		Category = "MOVEMENT",
		Rarity = "Common",
		Symbol = "Speed",
		Levels = levels(5, function(i)
			local v = i * 0.08
			return {
				Stats = { MoveSpeed = v },
				P = if i == 5 then { NoSlow = true } else nil,
				Desc = "+" .. pct(v) .. " movement speed",
				New = if i == 5 then "Puddles, spills and frost can't slow you any more" else nil,
			}
		end),
	},
	{
		Key = "Momentum",
		Name = "Momentum",
		Desc = "Damage builds up while you keep moving. Stopping resets it.",
		Category = "MOVEMENT",
		Rarity = "Uncommon",
		Symbol = "Speed",
		Levels = levels(5, function(i)
			local v = ({ 0.08, 0.14, 0.2, 0.26, 0.35 })[i]
			return {
				P = { Max = v, Build = 3, Pierce = if i == 5 then 1 else nil },
				Desc = "Up to +" .. pct(v) .. " damage while moving",
				New = if i == 5 then "At full momentum your shots pierce 1 more enemy" else nil,
			}
		end),
	},
	{
		Key = "Tailwind",
		Name = "Tailwind",
		Desc = "Attack faster while you move.",
		Category = "MOVEMENT",
		Rarity = "Uncommon",
		Symbol = "Speed",
		Levels = levels(5, function(i)
			local v = i * 0.06
			return {
				P = { Rate = v, Magnet = if i == 5 then 1 else nil },
				Desc = "+" .. pct(v) .. " attack speed while moving",
				New = if i == 5 then "While moving your pickup range doubles" else nil,
			}
		end),
	},
	{
		Key = "Marathon",
		Name = "Marathon",
		Desc = "Keep moving non-stop: a stride pulse hurts the enemies around you.",
		Category = "MOVEMENT",
		Rarity = "Uncommon",
		Symbol = "Area",
		Levels = levels(5, function(i)
			local every = ({ 8, 7, 6, 5, 4 })[i]
			return {
				P = { Every = every, Radius = 8 + i * 0.5, Damage = 16 + i * 4, Heal = if i == 5 then 3 else nil },
				Desc = "A pulse every " .. every .. " s of running",
				New = if i == 5 then "Pulses also heal 3 HP and pull XP to you" else nil,
			}
		end),
	},
	{
		Key = "DashMaster",
		Name = "Dash Master",
		Desc = "A better DASH.",
		Category = "MOVEMENT",
		Rarity = "Rare",
		Symbol = "Speed",
		Requires = { Dash = true },
		Levels = levels(5, function(i)
			local v = ({ 0.2, 0.3, 0.35, 0.4, 0.5 })[i]
			return {
				P = { Recharge = v, Distance = ({ 0, 2, 2, 3, 3 })[i], Hit = if i >= 3 then true else nil, Frenzy = if i == 5 then 0.3 else nil },
				Desc = "Dash recharges " .. pct(v) .. " faster" .. (if i >= 2 then ", goes further" else ""),
				New = if i == 3 then "Dashing through enemies damages them"
					elseif i == 5 then "After a dash: +30% damage for 2 s"
					else nil,
			}
		end),
	},
	{
		Key = "Roadrunner",
		Name = "Roadrunner",
		Desc = "The longer you run, the faster you get.",
		Category = "MOVEMENT",
		Rarity = "Common",
		Symbol = "Speed",
		Levels = levels(5, function(i)
			local v = ({ 0.1, 0.15, 0.2, 0.25, 0.3 })[i]
			return {
				P = { Max = v, Build = 3, Ram = if i == 5 then true else nil },
				Desc = "Up to +" .. pct(v) .. " speed after 3 s of running",
				New = if i == 5 then "At top speed you trample the enemies you run into" else nil,
			}
		end),
	},
	-------------------------------------------------------------------- XP
	{
		Key = "Wisdom",
		Name = "Wisdom",
		Desc = "More XP.",
		Category = "XP",
		Rarity = "Common",
		Symbol = "Growth",
		Levels = levels(5, function(i)
			local v = i * 0.08
			return {
				Stats = { Growth = v },
				P = if i == 5 then { Reroll = 10 } else nil,
				Desc = "+" .. pct(v) .. " XP",
				New = if i == 5 then "Every 10th level up gives you a free reroll" else nil,
			}
		end),
	},
	{
		Key = "Magnet",
		Name = "Magnet",
		Desc = "Collect XP from further away.",
		Category = "XP",
		Rarity = "Common",
		Symbol = "Area",
		Levels = levels(4, function(i)
			return {
				Stats = { Magnet = i * 0.35 },
				P = if i == 4 then { Pull = 0.02 } else nil,
				Desc = "+" .. pct(i * 0.35) .. " pickup range",
				New = if i == 4 then "Every XP gem has a 2% chance to pull every gem on the map to you" else nil,
			}
		end),
	},
	{
		Key = "XPStreak",
		Name = "Collector's Streak",
		Desc = "Picking up XP quickly builds a streak: +1% XP for every 5 gems.",
		Category = "XP",
		Rarity = "Uncommon",
		Symbol = "Growth",
		Levels = levels(5, function(i)
			local v = ({ 0.1, 0.15, 0.2, 0.25, 0.3 })[i]
			return {
				P = { Max = v, Heal = if i == 5 then 0.2 else nil },
				Desc = "Streak up to +" .. pct(v) .. " XP",
				New = if i == 5 then "At a full streak XP gems also heal you" else nil,
			}
		end),
	},
	{
		Key = "BountyHunter",
		Name = "Bounty Hunter",
		Desc = "Elites give more XP and coins.",
		Category = "XP",
		Rarity = "Uncommon",
		Symbol = "Coin",
		Levels = levels(5, function(i)
			return {
				P = { XP = i * 0.5, Coins = i * 4, Snack = if i == 5 then true else nil },
				Desc = "Elites: +" .. pct(i * 0.5) .. " XP, +" .. (i * 4) .. " coins",
				New = if i == 5 then "Elites always drop a snack and pull the XP around them to you" else nil,
			}
		end),
	},
	{
		Key = "TrophyHunter",
		Name = "Trophy Hunter",
		Desc = "Bosses give more XP.",
		Category = "XP",
		Rarity = "Rare",
		Symbol = "Growth",
		Levels = levels(3, function(i)
			return {
				P = { XP = i * 0.5, Level = if i == 3 then true else nil },
				Desc = "Bosses: +" .. pct(i * 0.5) .. " XP",
				New = if i == 3 then "Beating a boss gives a free level up" else nil,
			}
		end),
	},
	{
		Key = "Alchemy",
		Name = "Alchemy",
		Desc = "Healing past full HP turns into XP.",
		Category = "XP",
		Rarity = "Uncommon",
		Symbol = "Growth",
		Levels = levels(3, function(i)
			return {
				P = { Rate = i * 0.5, Coins = if i == 3 then true else nil },
				Desc = "1 HP of overheal = " .. string.format("%.1f", i * 0.5) .. " XP",
				New = if i == 3 then "Coins you pick up also give XP" else nil,
			}
		end),
	},
	{
		Key = "XPStorm",
		Name = "XP Storm",
		Desc = "Every 45 s: a few seconds of double XP.",
		Category = "XP",
		Rarity = "Rare",
		Symbol = "Growth",
		Levels = levels(2, function(i)
			return {
				P = if i == 2 then { Move = 0.15 } else nil,
				Desc = (8 + (i - 1) * 3) .. " s of double XP every 45 s",
				New = if i == 2 then "During the storm you move 15% faster" else nil,
			}
		end),
	},
	{
		Key = "Greed",
		Name = "Greed",
		Desc = "More coins.",
		Category = "XP",
		Rarity = "Common",
		Symbol = "Coin",
		Levels = levels(4, function(i)
			return {
				Stats = { Greed = i * 0.15 },
				P = if i == 4 then { Jackpot = 0.05 } else nil,
				Desc = "+" .. pct(i * 0.15) .. " coins",
				New = if i == 4 then "Coins you pick up have a 5% chance to pay x6.7" else nil,
			}
		end),
	},
	{
		Key = "Luck",
		Name = "Luck",
		Desc = "Rarer cards and drops.",
		Category = "XP",
		Rarity = "Uncommon",
		Symbol = "Coin",
		Levels = levels(4, function(i)
			return {
				Stats = { Luck = i * 0.12 },
				P = if i == 4 then { EliteLoot = 1.5 } else nil,
				Desc = "+" .. pct(i * 0.12) .. " luck",
				New = if i == 4 then "Elites drop items 50% more often" else nil,
			}
		end),
	},
	{
		Key = "TouchGrass",
		Name = "Touch Grass",
		Desc = "Secret. +1.5 HP per second, +25 max HP.",
		Category = "DEFENSE",
		Rarity = "Secret",
		Symbol = "Special",
		Secret = "TouchGrass",
		Levels = { { Stats = { Regen = 1.5, MaxHP = 25 }, Desc = "+1.5 HP/s, +25 max HP" } },
	},
}
UpgradeData.Passives = passives :: { PassiveDef }

-- fallback cards when nothing else can be offered
UpgradeData.Fillers = {
	{ Key = "Snack", Name = "Snack", Desc = "Heal 30 HP" },
	{ Key = "Coins", Name = "Pocket Change", Desc = "+8 coins" },
}

UpgradeData.PassiveByKey = {} :: { [string]: PassiveDef }
for _, def in UpgradeData.Passives do
	def.MaxLevel = #def.Levels
	UpgradeData.PassiveByKey[def.Key] = def
end

-- what an upgrade gives at a level (nil below 1)
function UpgradeData.At(key: string, level: number): Level?
	local def = UpgradeData.PassiveByKey[key]
	if not def or level < 1 then
		return nil
	end
	return def.Levels[math.min(level, def.MaxLevel)]
end

-- a number of an upgrade's mechanic at a level (0 / nil when not owned)
function UpgradeData.P(key: string, level: number?, name: string): any
	if not level or level < 1 then
		return nil
	end
	local l = UpgradeData.At(key, level)
	return l and l.P and l.P[name]
end

return UpgradeData
