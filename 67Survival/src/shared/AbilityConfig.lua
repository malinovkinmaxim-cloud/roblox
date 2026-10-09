--[[
	AbilityConfig - THE ABILITY CONFIG: how every ability LOOKS and SELLS (what an ability DOES:
	shared/WeaponData.lua; its behaviour: Sim/CombatManager.lua, Sim/PremiumAbilities.lua).

	ONE EFFECT STYLE (Controllers/WeaponFx.lua):
	  * bright flat shapes from Neon primitives, thick lines (Beam / line width >= MinLineWidth),
	    few particles (<= MaxParticles per effect, lifetime <= MaxParticleLife), no smoke clouds
	  * the main colour of an effect is its RARITY colour (EffectColors), with a little of the
	    ability's own colour mixed in (OwnColor) so two abilities of one rarity still differ;
	    an evolution (Mythic) cycles through the Mythic colours; an ABILITY SKIN overrides both
	  * every effect: appear (Back easing) -> act -> fade (Quad / Sine): Ease
	  * bigger and brighter with every level (Level), and at its max level a MAX FORM: its own
	    shape accent and colour (MaxForms, by Kind)
	  * every hit: a small neon flash (HitFlash), a damage number, a little knockback
	  * sounds: Sounds[key] = { Cast, Hit } (empty ids: -- TODO, see the list at the bottom)

	RARITY CARDS (UI/Cards.lua): the hero cards' layout; the border in the rarity colour; a
	Mythic card has an animated pink -> cyan -> gold gradient and a running shine.

	PREMIUM (Mythic, Robux): Premium[key] = { ProductId, Type } (ProductId = 0: not on sale yet,
	the button says COMING SOON; in Studio a test purchase), the daily TRIAL (Trial) and the
	power cap (PowerCap: never more than +30% over the best free ability of the same role).
	ABILITY SKINS (shared/CosmeticData.lua WeaponSkin) and the TRAIL PACK are pure cosmetics.
]]

local Rarity = require(script.Parent.Rarity)

local AbilityConfig = {}

local rgb = Color3.fromRGB

-- the main colour of the effects of each rarity (the cards and menus keep shared/Rarity.lua)
AbilityConfig.EffectColors = {
	Common = rgb(229, 231, 235), -- #E5E7EB
	Uncommon = rgb(74, 222, 128), -- #4ADE80
	Rare = rgb(59, 130, 246), -- #3B82F6
	Epic = rgb(168, 85, 247), -- #A855F7
	Legendary = rgb(250, 204, 21), -- #FACC15
	Mythic = rgb(34, 211, 238), -- (animated: MythicColors)
	Secret = rgb(245, 245, 250),
}
-- Mythic: an animated gradient pink -> cyan -> gold (cards) / a colour cycle (effects)
AbilityConfig.MythicColors = { rgb(244, 114, 182), rgb(34, 211, 238), rgb(250, 204, 21) }
AbilityConfig.MythicCycle = 2.4 -- seconds for one turn of the cycle
AbilityConfig.OwnColor = 0.35 -- how much of the ability's own colour is mixed into its rarity colour

AbilityConfig.MaxParticles = 12 -- per effect
AbilityConfig.MaxParticleLife = 0.6 -- seconds
AbilityConfig.MinLineWidth = 0.6 -- beams, lasers, lightning

-- bigger and brighter with every level: size x (1 + Size * (level - 1)), a second ring from
-- RingAt, a longer trail (x Trail per level)
AbilityConfig.Level = { Size = 0.06, Trail = 0.12, RingAt = 4 }

-- the MAX FORM of each Kind (max level): a colour of its own and a shape accent drawn with
-- the effect (Halo: a ring around it, Crown: points, Twin: a second copy, Star: a cross, Spiral)
AbilityConfig.MaxForms = {
	Projectile = { Color = rgb(255, 255, 255), Accent = "Star" },
	Missile = { Color = rgb(244, 114, 182), Accent = "Halo" },
	Boomerang = { Color = rgb(251, 146, 60), Accent = "Twin" },
	Lob = { Color = rgb(250, 204, 21), Accent = "Halo" },
	Aura = { Color = rgb(253, 224, 71), Accent = "Crown" },
	FireRing = { Color = rgb(255, 120, 40), Accent = "Crown" },
	Field = { Color = rgb(186, 230, 253), Accent = "Crown" },
	Cloud = { Color = rgb(163, 230, 53), Accent = "Spiral" },
	Meteor = { Color = rgb(255, 160, 60), Accent = "Halo" },
	Slam = { Color = rgb(147, 197, 253), Accent = "Halo" },
	Lightning = { Color = rgb(186, 230, 253), Accent = "Star" },
	Chain = { Color = rgb(56, 189, 248), Accent = "Star" },
	Beam = { Color = rgb(134, 239, 172), Accent = "Twin" },
	Vortex = { Color = rgb(192, 132, 252), Accent = "Spiral" },
	Slash = { Color = rgb(226, 232, 240), Accent = "Twin" },
	Hammer = { Color = rgb(250, 204, 21), Accent = "Halo" },
	Swords = { Color = rgb(226, 232, 240), Accent = "Star" },
	Orbit = { Color = rgb(244, 114, 182), Accent = "Halo" },
	Drone = { Color = rgb(125, 211, 252), Accent = "Halo" },
	Clone = { Color = rgb(147, 197, 253), Accent = "Halo" },
	Allies = { Color = rgb(134, 239, 172), Accent = "Crown" },
	Barrier = { Color = rgb(147, 197, 253), Accent = "Crown" },
	Glitch = { Color = rgb(244, 114, 182), Accent = "Star" },
	Chaos = { Color = rgb(250, 204, 21), Accent = "Spiral" },
	Blast67 = { Color = rgb(250, 204, 21), Accent = "Crown" },
	Stare = { Color = rgb(255, 255, 255), Accent = "Star" },
}

AbilityConfig.HitFlash = { Size = 1.3, Time = 0.15, PerFrame = 16 } -- (PerFrame: at most this many at once)

-- easing of every effect (Controllers/WeaponFx uses TweenService:GetValue with these)
AbilityConfig.Ease = {
	In = { Style = Enum.EasingStyle.Back, Direction = Enum.EasingDirection.Out }, -- appearing
	Out = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In }, -- fading
	Soft = { Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.InOut },
}

-- the colour of an ability's effects (no skin): its rarity colour with a bit of its own colour;
-- now = os.clock() for a Mythic colour cycle
function AbilityConfig.EffectColor(def, now: number?): Color3
	local rarity = def.Rarity or "Common"
	if rarity == "Mythic" then
		return AbilityConfig.MythicAt(now or 0, def.Id or 0)
	end
	local main = AbilityConfig.EffectColors[rarity] or AbilityConfig.EffectColors.Common
	if def.Color then
		return main:Lerp(def.Color, AbilityConfig.OwnColor)
	end
	return main
end

-- the Mythic colour cycle (pink -> cyan -> gold -> pink) at time t, shifted per ability
function AbilityConfig.MythicAt(t: number, shift: number): Color3
	local colors = AbilityConfig.MythicColors
	local u = ((t / AbilityConfig.MythicCycle + shift * 0.13) % 1) * #colors
	local i = math.floor(u)
	local f = u - i
	local a = colors[i + 1]
	local b = colors[(i + 1) % #colors + 1]
	return a:Lerp(b, f)
end

-- size multiplier of an effect at a level
function AbilityConfig.LevelScale(level: number?): number
	return 1 + AbilityConfig.Level.Size * math.max(0, (level or 1) - 1)
end

-- the menus' colour of a rarity (the cards keep shared/Rarity.lua's colours)
function AbilityConfig.CardColor(rarity: string): Color3
	return Rarity.Colors[rarity] or Rarity.Colors.Common
end

---------------------------------------------------------------------------
-- PREMIUM abilities (Mythic, bought with Robux; shared/WeaponData.lua Premium = true)
---------------------------------------------------------------------------
-- Type "Gamepass" (owned forever) or "Product" (a developer product). ProductId = 0 until the
-- pass / product exists on create.roblox.com: the game shows COMING SOON (Studio: a test buy).
-- Prices are set on the dashboard, never here.
AbilityConfig.Premium = {
	SolarBeam67 = { ProductId = 0, Type = "Gamepass" }, -- TODO: insert ID
	BlackHolePet = { ProductId = 0, Type = "Gamepass" }, -- TODO: insert ID
	GoldenMeteors = { ProductId = 0, Type = "Gamepass" }, -- TODO: insert ID
	TimeBubble = { ProductId = 0, Type = "Gamepass" }, -- TODO: insert ID
	PhoenixFamiliar = { ProductId = 0, Type = "Gamepass" }, -- TODO: insert ID
	ChainStorm = { ProductId = 0, Type = "Gamepass" }, -- TODO: insert ID
	AuraCrown = { ProductId = 0, Type = "Gamepass" }, -- TODO: insert ID
}
-- the TRIAL: once a day a player may take one premium ability into a run for free (the Premium
-- tab: TRY IT; the next run starts with it). Which one: a different one every day, one the
-- player does not own. Hours = the length of a "day" for the trial.
AbilityConfig.Trial = { PerDay = 1, Hours = 24 }
-- a premium ability is never more than PowerCap x the best free ability of its role (DPS)
AbilityConfig.PowerCap = 1.3
-- the premium abilities in the level-up offers of their owners (weight, like Legendary x 2)
AbilityConfig.PremiumWeight = 0.13

---------------------------------------------------------------------------
-- COSMETICS for Robux (no balance): ability skins and the trail pack
---------------------------------------------------------------------------
-- the ability skins on sale (shared/CosmeticData.lua WeaponSkin; the colours live there).
-- Bought here or got the old way (a pass, the Collection Book, coins); the equipped one is saved
-- in the profile (Cosmetics.Equipped.WeaponSkin)
AbilityConfig.SkinOrder = { "Gold", "Rainbow", "Void", "Ice" }
AbilityConfig.Skins = {
	Gold = { ProductId = 0, Type = "Gamepass" }, -- TODO: insert ID (today: in the VIP Cosmetics pass)
	Rainbow = { ProductId = 0, Type = "Gamepass" }, -- TODO: insert ID (today: in the Cosmetic Collection pass)
	Void = { ProductId = 0, Type = "Product" }, -- TODO: insert ID (today: 25 Collection Book entries)
	Ice = { ProductId = 0, Type = "Product" }, -- TODO: insert ID (today: 1500 coins)
}
-- the TRAIL PACK: trails behind you while you run (one at a time; shared/CosmeticData.lua Trail)
AbilityConfig.TrailPack = { ProductId = 0, Type = "Gamepass", Trails = { "Comet", "Sakura", "Pixel" } } -- TODO: insert ID

---------------------------------------------------------------------------
-- SOUNDS (placeholders: an empty id plays nothing). TODO: put your own sound ids here
---------------------------------------------------------------------------
AbilityConfig.Sounds = {
	Default = { Cast = "", Hit = "" }, -- TODO
	SolarBeam67 = { Cast = "", Hit = "" }, -- TODO
	BlackHolePet = { Cast = "", Hit = "" }, -- TODO
	GoldenMeteors = { Cast = "", Hit = "" }, -- TODO
	TimeBubble = { Cast = "", Hit = "" }, -- TODO
	PhoenixFamiliar = { Cast = "", Hit = "" }, -- TODO
	ChainStorm = { Cast = "", Hit = "" }, -- TODO
	AuraCrown = { Cast = "", Hit = "" }, -- TODO
}

return AbilityConfig
