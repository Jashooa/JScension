-- The addon bootstrap.
--
-- It creates the AceAddon object, owns the saved variables, the pulse loop,
-- the slash commands, and the keybind entry points. The other files attach
-- their modules to the shared namespace; this file wires them together. It
-- loads last so it can read every module at the top level.

local ADDON_NAME, ns = ...

local addon = LibStub("AceAddon-3.0"):NewAddon("Accessibility",
	"AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")

ns.addon = addon
ns.ADDON_NAME = ADDON_NAME

local A = addon
local Compatibility = ns.Compatibility
local Profile = ns.Profile
local SpellPicker = ns.SpellPicker
local Rotation = ns.Rotation

A.version = GetAddOnMetadata(ADDON_NAME, "Version") or "0.1.0"

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function A:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("AccessibilityDB", Profile.defaults, true)
	Profile.sanitizeProfile(self.db.profile)
	ns.Log.Attach(self.db.profile)   -- debug ring persists in the saved profile
	ns.Log.Write("boot", "addon initialized")
	self:RegisterChatCommand("acc", "HandleSlash")
	self:RegisterChatCommand("accessibility", "HandleSlash")
	self:Print(("Accessibility %s loaded. /acc for the editor, /acc help for commands."):format(self.version))
end

function A:OnEnable()
	self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")
	self:RegisterEvent("ADDON_ACTION_BLOCKED", "OnActionBlocked")
	self:RegisterEvent("ADDON_ACTION_FORBIDDEN", "OnActionBlocked")
	self:RegisterEvent("SPELLS_CHANGED", "OnSpellsChanged")

	ns.Button.Create(self.db.profile.button)
	ns.Config.Setup()

	if self.db.profile.auto then
		self:StartPulse()
	end

	Compatibility.Recheck()
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------

-- OnPlayerLogin re-probes the trust gate and refreshes the spellbook. It runs
-- after the shim re-registers, so a late-attached shim is picked up here.
function A:OnPlayerLogin()
	Compatibility.Recheck()
	SpellPicker.Refresh()
end

-- OnActionBlocked is a canary. A protected call from addon code must never
-- fire; if one does, the shim owner changed and the trust gate is failing.
function A:OnActionBlocked(event, ...)
	Compatibility.Recheck()
	self:Print(("|cffff4444%s: a protected call was blocked. compatible=%s|r"):format(
		event, tostring(Compatibility.IsCompatible())))
end

function A:OnSpellsChanged()
	SpellPicker.Refresh()
end

-- ---------------------------------------------------------------------------
-- the pulse
-- ---------------------------------------------------------------------------

function A:StartPulse()
	if self.pulseHandle then return end
	local interval = self.db.profile.pulseInterval or 0.1
	self.pulseHandle = self:ScheduleRepeatingTimer("Pulse", interval)
end

function A:StopPulse()
	if not self.pulseHandle then return end
	self:CancelTimer(self.pulseHandle)
	self.pulseHandle = nil
end

-- Pulse is the auto-mode tick. It runs many times a second, so it must do as
-- little as possible when switched off.
function A:Pulse()
	if not self.db.profile.auto then return end
	Rotation.CastBest()
end

-- PulseOnce casts once, from a click or a keypress.
function A:PulseOnce()
	Rotation.CastBest()
end

function A:ToggleAuto()
	if self.db.profile.auto then
		self.db.profile.auto = false
		self:StopPulse()
		self:Print("auto off")
	else
		self.db.profile.auto = true
		self:StartPulse()
		self:Print("auto on")
	end
	ns.Config.NotifyOptionsChanged()
end

-- ---------------------------------------------------------------------------
-- slash
-- ---------------------------------------------------------------------------

function A:HandleSlash(input)
	input = (input or ""):lower():match("^%s*(.-)%s*$")

	if input == "" or input == "config" or input == "options" then
		ns.Config.Open()
	elseif input == "cast" or input == "once" then
		self:PulseOnce()
	elseif input == "auto" or input == "toggle" then
		self:ToggleAuto()
	elseif input == "simulate" or input == "sim" then
		local lines = Rotation.Simulate()
		for _, line in ipairs(lines) do self:Print(line) end
	elseif input == "log" or input == "log 50" then
		-- print the recent debug log to chat (default 50 lines)
		local n = tonumber((input):match("^log%s+(%d+)$")) or 50
		local lines = ns.Log.Dump(n)
		if #lines == 0 then
			self:Print("log is empty")
		else
			self:Print(("log (%d entries):"):format(#lines))
			for _, line in ipairs(lines) do self:Print(line) end
		end
	elseif input == "log clear" then
		ns.Log.Clear()
		self:Print("log cleared")
	elseif input == "status" then
		self:PrintStatus()
	elseif input == "help" then
		self:PrintHelp()
	else
		self:Print("unknown command. /acc help")
	end
end

function A:PrintStatus()
	local profile = self.db.profile
	self:Print(("auto=%s compatible=%s rules=%d"):format(
		tostring(profile.auto), tostring(Compatibility.IsCompatible()), #Profile.activeRules()))
	local r = Rotation.lastResult
	if r and r.spell then
		self:Print(("last cast: %s ok=%s err=%s"):format(r.spell, tostring(r.ok), tostring(r.err)))
	end
end

function A:PrintHelp()
	self:Print("/acc            open the editor")
	self:Print("/acc cast       cast the next spell once")
	self:Print("/acc auto       toggle auto cast")
	self:Print("/acc simulate   report what would cast")
	self:Print("/acc status     show state and last cast")
	self:Print("/acc log [n]    print the debug log (default 50)")
	self:Print("/acc log clear  empty the debug log")
end

-- ---------------------------------------------------------------------------
-- keybind entry points
-- ---------------------------------------------------------------------------

BINDING_HEADER_ACCESSIBILITY = "Accessibility"
BINDING_NAME_ACCESSIBILITY_CAST = "Cast the next spell once"
BINDING_NAME_ACCESSIBILITY_AUTO = "Toggle auto rotation"

function Accessibility_CastOnce()
	A:PulseOnce()
end

function Accessibility_ToggleAuto()
	A:ToggleAuto()
end
