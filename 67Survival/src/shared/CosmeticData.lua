--[[
	CosmeticData - every cosmetic. Pure looks: no cosmetic changes a run.

	Categories (one equipped per category):
	  Hat         a hat on any hero (shared/HeroModels.lua Hats)
	  HeroSkin    a palette for any hero (HeroModels.Skins)
	  WeaponSkin  the colour of your ability effects
	  KillEffect  what enemies do when you defeat them
	  SpawnEffect how you enter the arena
	  Trail       behind you while you move
	  Emote       played from the lobby (Emote button)
	  NameEffect  your name tag
	  LobbyDecor  a pedestal under you in the lobby
	  VictoryAnim your hero on the victory screen
	  UITheme     the menu colours
	  Aura        a glow around your hero

	Id: "Category.Style" (unique). Style: the visual key used by the client.
	Source (how to get it):
	  Default     owned by everyone
	  Cost        coins (shop)
	  Achievement unlocked by an achievement
	  Pass        included in a game pass
	  Level       reaching an account level
	  Collection  collecting N entries of the Collection Book
]]

export type CosmeticDef = {
	Id: string,
	Category: string,
	Style: string,
	Name: string,
	Desc: string,
	Rarity: string,
	Default: boolean?,
	Cost: number?,
	Achievement: string?,
	Pass: string?,
	Level: number?,
	Collection: number?,
	Color: Color3?,
	Color2: Color3?,
}

local rgb = Color3.fromRGB

local CosmeticData = {}

CosmeticData.Categories = {
	{ Key = "Hat", Name = "Hats" },
	{ Key = "HeroSkin", Name = "Hero Skins" },
	{ Key = "WeaponSkin", Name = "Ability Skins" },
	{ Key = "KillEffect", Name = "Kill Effects" },
	{ Key = "SpawnEffect", Name = "Spawns" },
	{ Key = "Trail", Name = "Trails" },
	{ Key = "Emote", Name = "Emotes" },
	{ Key = "NameEffect", Name = "Name Effects" },
	{ Key = "LobbyDecor", Name = "Lobby Decor" },
	{ Key = "VictoryAnim", Name = "Victory" },
	{ Key = "UITheme", Name = "UI Themes" },
	{ Key = "Aura", Name = "Auras" },
}

local function c(category: string, style: string, t: { [string]: any }): CosmeticDef
	t.Id = category .. "." .. style
	t.Category = category
	t.Style = style
	t.Rarity = t.Rarity or "Common"
	return t :: any
end

CosmeticData.List = {
	-- hats
	c("Hat", "None", { Name = "No Hat", Desc = "Just your hero.", Default = true }),
	c("Hat", "Cone", { Name = "Traffic Cone", Desc = "Caution: horde ahead.", Cost = 400 }),
	c("Hat", "PartyHat", { Name = "Party Hat", Desc = "Every run is a party.", Cost = 800 }),
	c("Hat", "Shades", { Name = "Cool Shades", Desc = "Never blink again.", Cost = 1200, Rarity = "Uncommon" }),
	c("Hat", "Propeller", { Name = "Propeller Cap", Desc = "It spins. Obviously.", Cost = 2500, Rarity = "Rare" }),
	c("Hat", "Headband67", { Name = "67 Headband", Desc = "Witness a 67 EVENT.", Achievement = "SixSeven", Rarity = "Epic" }),
	c("Hat", "Halo", { Name = "Untouchable Halo", Desc = "3 minutes without a scratch.", Achievement = "Untouchable", Rarity = "Epic" }),
	c("Hat", "GoldAntenna", { Name = "Golden Antenna", Desc = "Defeat a Golden Goober.", Achievement = "GoldenGoober", Rarity = "Epic" }),
	c("Hat", "Crown", { Name = "Survivor Crown", Desc = "Defeat THE FINAL ONE.", Achievement = "Victory", Rarity = "Legendary" }),
	-- hero skins
	c("HeroSkin", "Default", { Name = "Original", Desc = "The hero's own colours.", Default = true }),
	c("HeroSkin", "Midnight", { Name = "Midnight", Desc = "Deep blue for any hero.", Cost = 1500, Rarity = "Uncommon" }),
	c("HeroSkin", "Candy", { Name = "Candy", Desc = "Pink and sky blue.", Cost = 1500, Rarity = "Uncommon" }),
	c("HeroSkin", "Frost", { Name = "Frost", Desc = "Ice cold.", Cost = 2500, Rarity = "Rare" }),
	c("HeroSkin", "Neon", { Name = "Neon", Desc = "Black with glowing edges.", Pass = "VIPCosmetics", Rarity = "Epic" }),
	c("HeroSkin", "Glitched", { Name = "Glitched", Desc = "Colours that should not exist.", Pass = "CosmeticPass", Rarity = "Epic" }),
	c("HeroSkin", "Shadow67", { Name = "Shadow 67", Desc = "Collect 60 Collection Book entries.", Collection = 60, Rarity = "Legendary" }),
	c("HeroSkin", "Gold", { Name = "Solid Gold", Desc = "Reach account level 50.", Level = 50, Rarity = "Legendary" }),
	-- ability skins (effect colours)
	c("WeaponSkin", "Default", { Name = "Original", Desc = "Every ability in its own colour.", Default = true }),
	c("WeaponSkin", "Crimson", { Name = "Crimson", Desc = "Everything red.", Cost = 1000, Color = rgb(255, 60, 80), Rarity = "Uncommon" }),
	c("WeaponSkin", "Toxic", { Name = "Toxic", Desc = "Everything green.", Cost = 1000, Color = rgb(120, 255, 80), Rarity = "Uncommon" }),
	c("WeaponSkin", "Ice", { Name = "Ice", Desc = "Everything frozen.", Cost = 1500, Color = rgb(140, 220, 255), Rarity = "Rare" }),
	c("WeaponSkin", "Void", { Name = "Void", Desc = "Collect 25 Collection Book entries.", Collection = 25, Color = rgb(150, 80, 255), Rarity = "Epic" }),
	c("WeaponSkin", "Gold", { Name = "Gold", Desc = "Shiny.", Pass = "VIPCosmetics", Color = rgb(255, 205, 60), Rarity = "Epic" }),
	c("WeaponSkin", "Rainbow", { Name = "Rainbow", Desc = "Every colour at once.", Pass = "CosmeticPass", Rarity = "Legendary" }),
	-- kill effects
	c("KillEffect", "Pop", { Name = "Pop", Desc = "A clean pop.", Default = true }),
	c("KillEffect", "Confetti", { Name = "Confetti", Desc = "Every kill is a celebration.", Cost = 1200, Rarity = "Uncommon" }),
	c("KillEffect", "Pixel", { Name = "Pixels", Desc = "Enemies break into pixels.", Cost = 1800, Rarity = "Rare" }),
	c("KillEffect", "Coins", { Name = "Coin Burst", Desc = "Cha-ching (just looks).", Pass = "VIPCosmetics", Rarity = "Epic" }),
	c("KillEffect", "Pop67", { Name = "67 Pop", Desc = "Enemies pop into sixes and sevens.", Achievement = "Witness67", Rarity = "Legendary" }),
	-- spawn effects
	c("SpawnEffect", "Beam", { Name = "Beam", Desc = "A beam of light.", Default = true }),
	c("SpawnEffect", "Lightning", { Name = "Lightning", Desc = "Strike down into the arena.", Cost = 1000, Rarity = "Uncommon" }),
	c("SpawnEffect", "Portal", { Name = "Portal", Desc = "Step out of a portal.", Cost = 2000, Rarity = "Rare" }),
	c("SpawnEffect", "Fireworks67", { Name = "67 Fireworks", Desc = "Reach account level 20.", Level = 20, Rarity = "Epic" }),
	c("SpawnEffect", "Meteor", { Name = "Meteor", Desc = "Land like a meteor.", Pass = "CosmeticPass", Rarity = "Epic" }),
	-- trails
	c("Trail", "None", { Name = "No Trail", Desc = "Clean.", Default = true }),
	c("Trail", "Sparkle", { Name = "Sparkle", Desc = "A little glitter.", Cost = 800, Color = rgb(255, 240, 180) }),
	c("Trail", "Fire", { Name = "Fire", Desc = "Leave a flame behind.", Cost = 1500, Color = rgb(255, 120, 40), Color2 = rgb(255, 220, 80), Rarity = "Uncommon" }),
	c("Trail", "Rainbow", { Name = "Rainbow", Desc = "All the colours.", Pass = "VIPCosmetics", Rarity = "Epic" }),
	c("Trail", "Trail67", { Name = "67 Trail", Desc = "Reach account level 35.", Level = 35, Color = rgb(255, 205, 50), Color2 = rgb(170, 90, 255), Rarity = "Legendary" }),
	-- emotes
	c("Emote", "Wave", { Name = "Wave", Desc = "Hi!", Default = true }),
	c("Emote", "Jump", { Name = "Hype", Desc = "Jump for joy.", Default = true }),
	c("Emote", "Dance", { Name = "Dance", Desc = "Left, right, left.", Cost = 600 }),
	c("Emote", "Flex", { Name = "Flex", Desc = "Show them.", Cost = 900, Rarity = "Uncommon" }),
	c("Emote", "Spin", { Name = "Spin", Desc = "Round and round.", Cost = 1200, Rarity = "Uncommon" }),
	c("Emote", "SixSeven", { Name = "6 7", Desc = "Six. Seven. (Witness a 67 EVENT)", Achievement = "SixSeven", Rarity = "Epic" }),
	-- name effects
	c("NameEffect", "Default", { Name = "Plain", Desc = "White name tag.", Default = true }),
	c("NameEffect", "Fire", { Name = "Hot", Desc = "Reach account level 10.", Level = 10, Color = rgb(255, 130, 60), Rarity = "Uncommon" }),
	c("NameEffect", "Gold", { Name = "Gold", Desc = "A golden name.", Pass = "VIPCosmetics", Color = rgb(255, 205, 60), Rarity = "Epic" }),
	c("NameEffect", "Rainbow", { Name = "Rainbow", Desc = "A name in every colour.", Pass = "CosmeticPass", Rarity = "Epic" }),
	c("NameEffect", "Glitch", { Name = "Glitch", Desc = "Defeat THE 67.", Achievement = "DefeatThe67", Color = rgb(0, 255, 210), Rarity = "Secret" }),
	-- lobby decor
	c("LobbyDecor", "None", { Name = "Nothing", Desc = "Just the floor.", Default = true }),
	c("LobbyDecor", "NeonRing", { Name = "Neon Ring", Desc = "A glowing ring under you.", Cost = 1000, Color = rgb(0, 225, 255), Rarity = "Uncommon" }),
	c("LobbyDecor", "GrassPatch", { Name = "Grass Patch", Desc = "You touched grass.", Achievement = "TouchGrass", Color = rgb(90, 200, 90), Rarity = "Rare" }),
	c("LobbyDecor", "Tile67", { Name = "67 Tile", Desc = "Collect 100 Collection Book entries.", Collection = 100, Color = rgb(255, 205, 50), Rarity = "Legendary" }),
	c("LobbyDecor", "GoldPedestal", { Name = "Gold Pedestal", Desc = "Stand tall.", Pass = "VIPCosmetics", Color = rgb(255, 205, 60), Rarity = "Epic" }),
	-- victory animations
	c("VictoryAnim", "Jump", { Name = "Jump", Desc = "Jump for joy.", Default = true }),
	c("VictoryAnim", "Spin", { Name = "Spin", Desc = "A victory spin.", Cost = 800, Rarity = "Uncommon" }),
	c("VictoryAnim", "Flex", { Name = "Flex", Desc = "Show them who won.", Cost = 1200, Rarity = "Rare" }),
	c("VictoryAnim", "SixSeven", { Name = "6 7", Desc = "Six. Seven. (Seen It All)", Achievement = "Witness67", Rarity = "Legendary" }),
	-- UI themes
	c("UITheme", "Default", { Name = "Night", Desc = "The standard look.", Default = true }),
	c("UITheme", "Sunset", { Name = "Sunset", Desc = "Warm orange accents.", Cost = 500, Color = rgb(255, 140, 70) }),
	c("UITheme", "Mint", { Name = "Mint", Desc = "Fresh green accents.", Cost = 500, Color = rgb(70, 220, 160) }),
	c("UITheme", "Ocean", { Name = "Ocean", Desc = "Cool blue accents.", Cost = 500, Color = rgb(70, 160, 255) }),
	c("UITheme", "Gold67", { Name = "67 Gold", Desc = "Gold accents everywhere.", Pass = "CosmeticPass", Color = rgb(255, 205, 50), Rarity = "Epic" }),
	-- auras
	c("Aura", "None", { Name = "No Aura", Desc = "No glow.", Default = true }),
	c("Aura", "Void", { Name = "Void Aura", Desc = "Defeat all 8 bosses.", Achievement = "BossCollector", Color = rgb(150, 80, 255), Rarity = "Legendary" }),
	c("Aura", "Gold", { Name = "Gold Aura", Desc = "A soft golden glow.", Pass = "VIPCosmetics", Color = rgb(255, 205, 60), Rarity = "Epic" }),
	c("Aura", "Aura67", { Name = "67 Aura", Desc = "Reach account level 67 (or a 67 Aura boost).", Level = 67, Color = rgb(255, 205, 50), Color2 = rgb(170, 90, 255), Rarity = "Mythic" }),
} :: { CosmeticDef }

CosmeticData.ById = {} :: { [string]: CosmeticDef }
CosmeticData.ByCategory = {} :: { [string]: { CosmeticDef } }
CosmeticData.DefaultOf = {} :: { [string]: string }
for _, cat in CosmeticData.Categories do
	CosmeticData.ByCategory[cat.Key] = {}
end
for _, def in CosmeticData.List do
	CosmeticData.ById[def.Id] = def
	table.insert(CosmeticData.ByCategory[def.Category], def)
	if def.Default and not CosmeticData.DefaultOf[def.Category] then
		CosmeticData.DefaultOf[def.Category] = def.Id
	end
end

-- the Style equipped in a category (the default one when nothing valid is equipped)
function CosmeticData.Style(equipped: { [string]: string }?, category: string): string
	local id = equipped and equipped[category]
	local def = id and CosmeticData.ById[id]
	if def and def.Category == category then
		return def.Style
	end
	return CosmeticData.ById[CosmeticData.DefaultOf[category]].Style
end

-- how a cosmetic is obtained, in words (menu text)
function CosmeticData.SourceText(def: CosmeticDef): string
	if def.Default then
		return "Owned"
	elseif def.Cost then
		return tostring(def.Cost)
	elseif def.Pass then
		return if def.Pass == "VIPCosmetics" then "VIP Cosmetics pass" else "Cosmetic Collection pass"
	elseif def.Level then
		return "Account level " .. def.Level
	elseif def.Collection then
		return "Collection " .. def.Collection
	elseif def.Achievement then
		return "Achievement"
	end
	return ""
end

return CosmeticData
