-- Type coercion helpers for sanitizing saved variables: each returns the
-- value when it has the expected type, otherwise the given default. Used by
-- the profile sanitizer so a broken saved variable degrades to defaults
-- instead of crashing. No WoW API is touched.

local _, ns = ...

ns.Coerce = {}

function ns.Coerce.asBool(v, d)
	if type(v) == "boolean" then return v end
	return d
end

function ns.Coerce.asString(v, d)
	if type(v) == "string" then return v end
	return d
end

function ns.Coerce.asNumber(v, d)
	if type(v) == "number" then return v end
	local n = tonumber(v)
	if n then return n end
	return d
end
