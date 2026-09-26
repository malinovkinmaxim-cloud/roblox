--[[
	Replaces the default "Animate" script on purpose.

	The real R15 rig is invisible (CharacterService) and every client draws a stretched body
	with its own procedural walk animation (BodyController), so playing the default
	animations would only waste CPU on every device for every player.
]]
