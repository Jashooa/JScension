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
	ns.Slash.Install(self)
	self:Print(("Accessibility %s loaded. /acc for the editor, /acc help for commands."):format(self.version))
end

function A:OnEnable()
	self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")
	self:RegisterEvent("ADDON_ACTION_BLOCKED", "OnActionBlocked")
	self:RegisterEvent("ADDON_ACTION_FORBIDDEN", "OnActionBlocked")
	self:RegisterEvent("SPELLS_CHANGED", "OnSpellsChanged")
	self:RegisterEvent("UNIT_SPELLCAST_START", "OnSpellcastEvent")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastEvent")
	self:RegisterEvent("UNIT_SPELLCAST_FAILED", "OnSpellcastEvent")
	self:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET", "OnSpellcastEvent")
	self:RegisterEvent("UI_ERROR_MESSAGE", "OnUiErrorMessage")
	self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnSpellcastEvent")
	self:RegisterEvent("UNIT_SPELLCAST_STOP", "OnSpellcastEvent")
	ns.RotationButton.Create(self.db.profile.button)
	ns.Config.Setup()

	if self.db.profile.auto then
		self:StartPulse()
	end

	Compatibility.Recheck()
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------

-- OnPlayerLogin re-probes the trust gate, refreshes the spellbook, and checks
-- the spell-API return order (a client rebuild can shift it). It runs after
-- the shim re-registers, so a late-attached shim is picked up here.
function A:OnPlayerLogin()
	Compatibility.Recheck()
	SpellPicker.Refresh()
	if not ns.Spell.verifyShape() then
		self:Print("|cffff4444Accessibility: spell API return order changed - verify GetSpellInfo|r")
	end
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
function A:OnSpellcastEvent(event, unit, spell)
	if unit ~= "player" then return end
	if event == "UNIT_SPELLCAST_START" then
		Rotation.OnCastStarted(spell)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		Rotation.OnCastSucceeded(spell)
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
		Rotation.OnCastFailed(spell)
	else
		Rotation.OnCastCancelled(spell)
	end
end
function A:OnUiErrorMessage(_, message)
	Rotation.OnUiError(message)
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
	if self.pulseHandle then
		self:CancelTimer(self.pulseHandle)
		self.pulseHandle = nil
	end
	Rotation.ClearJitter()
end

-- Pulse is the auto-mode tick. It runs many times a second, so it must do as
-- little as possible when switched off.
function A:Pulse()
	if not self.db.profile.auto then return end
	Rotation.CastBest(true)
end

-- PulseOnce casts once, from a click or a keypress. Manual casts bypass jitter.
function A:PulseOnce()
	Rotation.CastBest(false)
end

function A:ToggleAuto()
	local enabled = not Profile.current().auto
	Profile.setAutoEnabled(enabled)
	if enabled then
		self:StartPulse()
		self:Print("auto on")
	else
		self:StopPulse()
		self:Print("auto off")
	end
	ns.Config.NotifyOptionsChanged()
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
