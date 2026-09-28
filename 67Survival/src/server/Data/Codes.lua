--[[
	Codes - promo codes (server only, so players cannot read the list from the client).
	Each code works once per profile. Keys are UPPERCASE; players can type any case.
	Add codes for updates / milestones here.
]]

return {
	["67"] = { Coins = 67, Text = "Six seven. +67 coins" },
	["SURVIVE"] = { Coins = 150, Text = "+150 coins" },
	["HORDE"] = { Coins = 100, Text = "+100 coins" },
	["FRAGMENTS"] = { Fragments = 5, Text = "+5 fragments" },
	["RELEASE"] = { Coins = 250, Fragments = 3, Text = "Thanks for playing! +250 coins, +3 fragments" },
} :: { [string]: { Coins: number?, Fragments: number?, Text: string } }
