--[[
	SkinData - cosmetic hats, worn with any character. Pure looks: no stats.
	Some are bought with BRAIN COINS, the best ones are only earned through achievements
	(so a crown on someone's head in the lobby means they actually beat the game).
]]

export type SkinDef = {
	Key: string,
	Name: string,
	Icon: string,
	Desc: string,
	Default: boolean?,
	Cost: number?,
	Achievement: string?,
}

local SkinData = {}

SkinData.List = {
	{ Key = "None", Name = "No Hat", Icon = "🚫", Desc = "Just your head.", Default = true },
	{ Key = "Cone", Name = "Traffic Cone", Icon = "🚧", Desc = "Caution: brainrot ahead.", Cost = 400 },
	{ Key = "BrainHat", Name = "Exposed Brain", Icon = "🧠", Desc = "Big thoughts, no skull.", Cost = 800 },
	{ Key = "Shades", Name = "Sigma Shades", Icon = "🕶️", Desc = "Never blink again.", Cost = 1200 },
	{ Key = "Propeller", Name = "Propeller Cap", Icon = "🧢", Desc = "It spins. Obviously.", Cost = 2500 },
	{ Key = "Headband67", Name = "67 Headband", Icon = "6️⃣", Desc = "Witness a 67 EVENT.", Achievement = "SixSeven" },
	{ Key = "Halo", Name = "Untouchable Halo", Icon = "😇", Desc = "3 minutes without a scratch.", Achievement = "Untouchable" },
	{ Key = "GoldAntenna", Name = "Golden Antenna", Icon = "🥇", Desc = "Defeat a Golden Goober.", Achievement = "GoldenGoober" },
	{ Key = "Crown", Name = "Survivor Crown", Icon = "👑", Desc = "Defeat THE FINAL GOOBER.", Achievement = "Victory" },
} :: { SkinDef }

SkinData.ByKey = {} :: { [string]: SkinDef }
for _, def in SkinData.List do
	SkinData.ByKey[def.Key] = def
end

SkinData.Default = "None"

return SkinData
