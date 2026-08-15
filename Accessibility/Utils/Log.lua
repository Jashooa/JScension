-- Ring-buffer logger for debugging the rotation.
--
-- Entries live in a plain table and are appended to the profile's log ring
-- by Accessibility.lua on load (see Log.Attach). The buffer is capped, so a
-- busy combat session cannot grow the saved variables without bound. The
-- entries persist to the SavedVariables file on logout/reload, which lets the
-- developer read them from disk when the user reports a problem.
--
-- GetTime() is the only WoW API used; it is faked in the test harness. No UI
-- is touched here - chat output is the slash command's job.

local _, ns = ...

ns.Log = {}

local MAX_ENTRIES = 200
local ring = {}   -- oldest first: { time, tag, message }
local attachedProfile = nil

-- Write appends one entry, dropping the oldest when the ring is full.
function ns.Log.Write(tag, message)
	ring[#ring + 1] = { time = GetTime(), tag = tag, message = message }
	if #ring > MAX_ENTRIES then
		table.remove(ring, 1)
	end
end

-- Clear empties the ring.
function ns.Log.Clear()
	ring = {}
end

-- Count returns the number of entries currently buffered.
function ns.Log.Count()
	return #ring
end

-- Dump returns the last n entries as strings, newest first, ready for chat or
-- the developer. A nil n returns everything.
function ns.Log.Dump(n)
	if not n or n < 0 then n = #ring end
	local lines = {}
	local first = math.max(1, #ring - n + 1)
	for i = #ring, first, -1 do
		local e = ring[i]
		lines[#lines + 1] = ("[%s] %s: %s"):format(e.time, e.tag, e.message)
	end
	return lines
end

-- Attach binds the ring to a profile table so the entries persist across
-- sessions. The profile carries { log = { <entries> } }; entries are loaded
-- on attach and written back on every Write.
function ns.Log.Attach(profile)
	attachedProfile = profile
	ring = {}
	if type(profile.log) == "table" then
		ring = profile.log
	end
end

-- Persist copies the ring back into the attached profile so AceDB saves it.
local function persist()
	if attachedProfile then
		attachedProfile.log = ring
	end
end

-- override Write to persist after appending
local baseWrite = ns.Log.Write
function ns.Log.Write(tag, message)
	baseWrite(tag, message)
	persist()
end
