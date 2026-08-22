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
	-- Default interval that spaces repeated no-cooldown instant casts.
	DEFAULT_ANTI_SPAM_WINDOW = 1.0,
	-- Maximum configured random delay before an automatic cast.
	DEFAULT_JITTER_WINDOW = 0.0,
	MAX_JITTER_WINDOW = 1.0,
	-- The valid unit tokens, in editor display order. An ordered array, not
	-- a map: the dropdown builder derives the AceGUI map from it, and the
	-- first element ("player") is the default when a new condition is added.
	UNIT_TOKENS = { "player", "target", "focus", "pet", "mouseover" },
}
