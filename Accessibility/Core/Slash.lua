-- The slash-command dispatch and its helpers.
--
-- Install attaches HandleSlash, PrintStatus, and PrintHelp to the addon
-- object (AceConsole's RegisterChatCommand looks the handler up on the
-- addon), but the implementation lives here so the entry file stays pure
-- wiring.

local _, ns = ...

local Slash = {}

local Config = ns.Config
local Rotation = ns.Rotation
local Log = ns.Log
local Profile = ns.Profile
local Compatibility = ns.Compatibility
assert(Config and Rotation and Log and Profile and Compatibility,
	"load order: Core/Slash before its dependencies")

-- Install wires the slash handler and its print helpers onto the addon.
function Slash.Install(addon)
	function addon:HandleSlash(input)
		input = (input or ""):lower():match("^%s*(.-)%s*$")

		if input == "" or input == "config" or input == "options" then
			Config.Open()
		elseif input == "cast" or input == "once" then
			self:PulseOnce()
		elseif input == "auto" or input == "toggle" then
			self:ToggleAuto()
		elseif input == "simulate" or input == "sim" then
			local lines = Rotation.Simulate()
			for _, line in ipairs(lines) do self:Print(line) end
		elseif input == "log" or input:match("^log%s+%d+$") then
			-- print the recent debug log to chat (default 50 lines)
			local n = tonumber((input):match("^log%s+(%d+)$")) or 50
			local lines = Log.Dump(n)
			if #lines == 0 then
				self:Print("log is empty")
			else
				self:Print(("log (%d entries):"):format(#lines))
				for _, line in ipairs(lines) do self:Print(line) end
			end
		elseif input == "log clear" then
			Log.Clear()
			self:Print("log cleared")
		elseif input == "status" then
			self:PrintStatus()
		elseif input == "help" then
			self:PrintHelp()
		else
			self:Print("unknown command. /acc help")
		end
	end

	function addon:PrintStatus()
		local profile = self.db.profile
		self:Print(("auto=%s compatible=%s rules=%d"):format(
			tostring(profile.auto), tostring(Compatibility.IsCompatible()), #Profile.activeRules()))
		local r = Rotation.lastResult
		if r and r.spell then
			self:Print(("last cast: %s ok=%s err=%s"):format(r.spell, tostring(r.ok), tostring(r.err)))
		end
	end

	function addon:PrintHelp()
		self:Print("/acc            open the editor")
		self:Print("/acc cast       cast the next spell once")
		self:Print("/acc auto       toggle auto cast")
		self:Print("/acc simulate   report what would cast")
		self:Print("/acc status     show state and last cast")
		self:Print("/acc log [n]    print the debug log (default 50)")
		self:Print("/acc log clear  empty the debug log")
	end
end

ns.Slash = Slash
