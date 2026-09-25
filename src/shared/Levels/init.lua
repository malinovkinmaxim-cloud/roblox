--[[
Tile legend (1 tile = Config.TILE studs):
  #  ground           S  spawn            K  key          D  door (2 tiles tall)
  ^  spikes           j  trampoline
  b  purple button    x  purple wall (opens while a purple button is pressed)
                      g  purple bridge (appears while a purple button is pressed)
  c  pink button      y  pink wall        h  pink bridge
  1-8  push box (adjacent same digits form one box, the digit = players needed)
  L  lift (adjacent L form one platform)
  M  moving platform (adjacent M form one platform, rides up and down on its own)
  o  sand block (crumbles shortly after someone stands on it, comes back later)
  <  cannon shooting left     >  cannon shooting right
  =  seesaw plank (a horizontal run tilts around its middle by the players' weight)
  F  checkpoint flag (flags are also placed automatically on safe ground)

Level options:
  button  = { need = 2, latch = true }   -- purple buttons; latch = stays on once pressed
  button2 = { need = 1, latch = false }  -- pink buttons
  lift    = { need = 99, rise = 5 }      -- rise in tiles
  mover   = { rise = 3, period = 4 }     -- moving platforms: rise in tiles, period in seconds
  cannon  = { interval = 2.5, speed = 14 }
  scroll  = { speed = 3.5, delay = 4 }   -- the screen scrolls right; whoever falls behind loses
  stopgo  = { go = 3.5, stop = 2.5 }     -- red light: nobody may move while it is red
  time    = 60                           -- time limit in seconds

Requirements are capped by the current player count, so 99 means "everyone".
]]

return {
	easy = require(script.Easy),
	medium = require(script.Medium),
	hard = require(script.Hard),
}
