-- Shared constants.
--
-- Literals used in more than one module live here so each value is written
-- once. A value used by a single module stays local to that module.

local _, ns = ...

ns.Constants = {
	GCD_DURATION = 1.5,   -- the global cooldown, in seconds
	MAX_AURAS = 40,       -- aura slots the client scans per unit
	-- Default spell queue window, in seconds. Matches the client's
	-- SpellQueueWindow CVar (400ms): a cast sent within this much of the
	-- current cast's end is queued by the client, so the next cast starts
	-- with no dead time.
	DEFAULT_QUEUE_WINDOW = 0.4,
	-- The valid unit tokens. The sanitizer whitelists against this, the
	-- editor dropdown reads it, and the engine's self-cast checks use it.
	UNIT_TOKENS = { player = "player", target = "target", focus = "focus", pet = "pet", mouseover = "mouseover" },
}
