-- Test harness for the Accessibility addon. Run with: lua5.1 tests/run.lua
--
-- It loads the pure-Lua modules (Utils, Game, Core) with a fake WoW API and
-- a fake Compatibility global, then runs assertions against the observable
-- contracts: profile sanitization, conditions, the rotation engine, the
-- spellbook, and the Compatibility script seam. The AceGUI widgets
-- (RotationButton, RotationRules, RotationSettings, TitleButtonGroup) are not loaded: their
-- contracts are frame layout and mouse behaviour, which no harness fake can
-- verify - they are exercised in-game.

-- ---------------------------------------------------------------------------
-- fake world state
-- ---------------------------------------------------------------------------

local state = {
	time = 0,
	secure = true,
	inCombat = false,
	units = {},       -- unit -> { exists, dead, health, maxHealth, power, maxPower, hostile, speed, casting }
	auras = {},       -- unit -> array of { kind, name, count, remaining, mine }
	spells = {},      -- name -> { usable, noMana, cdStart, cdDuration, inRange }
	knownSpells = {}, -- array of spell names in the spellbook
	passiveSpells = {}, -- names reported as passive by the spellbook
}

local ns = {}

local function setUnit(id, t) state.units[id] = t end
local function setSpell(name, t) state.spells[name] = t end
local function setKnown(names)
	state.knownSpells = {}
	for i = 1, #names do state.knownSpells[i] = names[i] end
	if ns.SpellPicker then ns.SpellPicker.Refresh() end
end

-- ---------------------------------------------------------------------------
-- fake Compatibility global + WoW API
-- ---------------------------------------------------------------------------

local scripts = {}   -- every script the fake Compatibility received

local fake = {}

fake.Compatibility = function(script)
	scripts[#scripts + 1] = script
	if script:find("issecure", 1, true) then
		return true, (state.secure and 1 or nil), nil
	elseif script:find("Compatibility_Position ", 1, true) then
		local guid = script:match("Compatibility_Position%s+(.+)$")
		if guid == "0x1111" then return 1.25, 2.5, 3.75 end
		return 4.5, 5.75, 6.25
	elseif script:find("Compatibility_Scale ", 1, true) then
		local guid = script:match("Compatibility_Scale%s+(.+)$")
		return guid == "0x1111" and 1.0 or 1.5
	elseif script:find("Compatibility_UnitCountInRange ", 1, true) then
		local guid, relationship, radius =
			script:match("Compatibility_UnitCountInRange%s+(%S+)%s+(%d+)%s+([%d%.]+)$")
		if guid == "0x2222" and relationship == "1" and radius == "8.000000" then return 3 end
		if guid == "0x1111" and relationship == "2" and radius == "20.000000" then return 2 end
		if guid == "0xdead" then return nil end

		return 0
	elseif script:find("Compatibility_LOS ", 1, true) then
		return 1
	elseif script:find("Compatibility_PlaceGround ", 1, true) then
		return 1
	end
	return true, true, nil
end


-- Ace3 stubs so Config.lua loads and its option closures run in the harness.
fake.LibStub = function(name)
	if name == "AceConfig-3.0" then
		return { RegisterOptionsTable = function() end }
	elseif name == "AceConfigDialog-3.0" then
		return {
			AddToBlizOptions = function() end,
			Open = function() end,
			GetStatusTable = function() return _G.__dialogStatus end,
		}
	elseif name == "AceConfigRegistry-3.0" then
		return { NotifyChange = function() end }
	end
	return nil
end

local function clearScripts()
	for i = #scripts, 1, -1 do scripts[i] = nil end
end

fake.GetTime = function() return state.time end
fake.UnitExists = function(u) local x = state.units[u]; return x and x.exists end
fake.UnitGUID = function(u) local x = state.units[u]; return x and x.guid end
fake.UnitIsDeadOrGhost = function(u) local x = state.units[u]; return x and x.dead end
fake.UnitHealth = function(u) local x = state.units[u]; return x and x.health or 0 end
fake.UnitHealthMax = function(u) local x = state.units[u]; return x and x.maxHealth or 0 end
-- power fakes accept an optional powerType (0 mana, 1 rage, ...). A unit
-- table may set per-pool values via powers = { [1] = 22 } and maxPowers,
-- falling back to the plain power/maxPower fields (the current pool).
fake.UnitPower = function(u, t)
	local x = state.units[u]
	if not x then return 0 end
	if t ~= nil and x.powers and x.powers[t] ~= nil then return x.powers[t] end
	return x.power or 0
end
fake.UnitPowerMax = function(u, t)
	local x = state.units[u]
	if not x then return 0 end
	if t ~= nil and x.maxPowers and x.maxPowers[t] ~= nil then return x.maxPowers[t] end
	return x.maxPower or 0
end
fake.UnitCanAttack = function(_, u) local x = state.units[u]; return x and x.hostile end
fake.UnitName = function(u) local x = state.units[u]; return x and x.name end
fake.UnitIsEnemy = function(_, u) local x = state.units[u]; return x and x.enemy end
fake.UnitIsFriendly = function(_, u) local x = state.units[u]; return x and x.friendly end

-- UnitCastingInfo/UnitChannelInfo return (name, subText, text, texture,
-- startTime, endTime, ...) in this client. The unit table may set
-- castingEndMs / channelEndMs to simulate a cast and castingSpell to name
-- it; notInterruptible simulates an un-interruptible cast.
fake.UnitCastingInfo = function(u)
	local x = state.units[u]
	if x and x.castingEndMs then
		return x.castingSpell or "Cast", "", "", 0, 0, x.castingEndMs, false, 1, x.notInterruptible or false
	end
	return nil
end
fake.UnitChannelInfo = function(u)
	local x = state.units[u]
	if x and x.channelEndMs then
		return x.channelSpell or "Channel", "", "", 0, 0, x.channelEndMs, false, x.notInterruptible or false
	end
	return nil
end
fake.UnitLevel = function(u) local x = state.units[u]; return x and x.level end
fake.UnitIsPlayer = function(u) local x = state.units[u]; return x and x.isPlayer end
fake.UnitClassification = function(u) local x = state.units[u]; return x and x.classification end
fake.GetComboPoints = function(_, u) local x = state.units[u]; return x and x.comboPoints or 0 end
fake.UnitDetailedThreatSituation = function(_, u)
	local x = state.units[u]
	if x and x.threatPercent then return x.isTanking or false, 3, x.threatPercent, x.threatPercent, 0 end
	return nil
end
fake.UnitThreatSituation = function(_, u)
	local x = state.units[u]
	if x and x.threatPercent then return x.isTanking and 3 or 1 end
	return nil
end
fake.GetShapeshiftForm = function() return state.shapeshiftForm or 0 end
fake.GetShapeshiftFormInfo = function(index)
	local forms = state.shapeshiftForms or {}
	local name = forms[index]
	if name then return "Interface\\Icons\\TEMP", name, index == (state.shapeshiftForm or 0), true end
	return "Interface\\Icons\\TEMP", nil, false, false
end
fake.IsShiftKeyDown = function() return state.shiftKey and 1 or nil end
fake.IsControlKeyDown = function() return state.controlKey and 1 or nil end
fake.IsAltKeyDown = function() return state.altKey and 1 or nil end
fake.GetScreenWidth = function() return 1920 end
fake.GetScreenHeight = function() return 1080 end
fake.GetScreenPosition = function() return 0.5, 0.5 end
fake.GetCursorPosition = function() return 960, 540 end
fake.SetCursorPosition = function() end
fake.UnitAffectingCombat = function() return state.inCombat end
fake.GetUnitSpeed = function(u) local x = state.units[u]; return x and x.speed or 0 end
fake.IsUsableSpell = function(s) local x = state.spells[s]; if x then return x.usable, x.noMana end end
fake.GetSpellCooldown = function(s) local x = state.spells[s]; if x then return x.cdStart, x.cdDuration end; return 0, 0 end
fake.GetSpellCharges = function(id)
	local x = state.spells[id]
	if not x then
		local link = "spell:" .. tostring(id)
		for _, spell in pairs(state.spells) do
			if type(spell) == "table" and spell.testLink == link then
				x = spell
				break
			end
		end
	end
	if x and x.maxCharges then
		return x.currentCharges or 0, x.maxCharges, nil, x.rechargeTime or 0
	end
	return 0, 0, nil, 0
end
fake.IsSpellInRange = function(s) local x = state.spells[s]; if x then return x.inRange end end
fake.GetSpellTexture = function() return "Interface\\Icons\\TEMP" end
-- GetSpellInfo returns (name, rank, icon, powerCost, isFunnel, powerType,
-- castingTime, minRange, maxRange) in this client. The spell table may set
-- castMs to simulate a cast-time spell (used by the engine's anti-spam
-- gate, which reads the 7th return).
fake.GetSpellInfo = function(id)
	local x = type(id) == "string" and state.spells[id] or nil
	local castMs = x and x.castMs or 0
	local minRange = x and x.minRange or 0
	local maxRange = x and x.maxRange or 0
	if id == 8921 then return "Moonfire", "", "Interface\\Icons\\TEMP", 0, false, 0, castMs, minRange, maxRange end
	return "spell", "", "Interface\\Icons\\TEMP", 0, false, 0, castMs, minRange, maxRange
end
-- GetSpellLink returns a hyperlink for a name or ID. The spell table may
-- set testLink to simulate a resolved link; unknown spells return nil.
fake.GetSpellLink = function(ref)
	local x = type(ref) == "string" and state.spells[ref] or nil
	if x and x.testLink then return x.testLink end
	if type(ref) == "number" then return ("spell:%d"):format(ref) end
	return nil
end
fake.GetNumSpellTabs = function() return state.knownSpells[1] and 1 or 0 end
fake.GetSpellTabInfo = function() return "General", "", 0, #state.knownSpells end
fake.GetSpellName = function(i) return state.knownSpells[i] end
-- IsPassiveSpell is the client's passive detector; the fake reports a name
-- in state.passiveSpells as passive.
fake.IsPassiveSpell = function(i)
	local name = state.knownSpells[i]
	return name and state.passiveSpells and state.passiveSpells[name] == true or false
end
fake.BOOKTYPE_SPELL = "spell"

local function auraAt(unit, kind, index)
	local list = state.auras[unit]
	if not list then return nil end
	local seen = 0
	for i = 1, #list do
		if list[i].kind == kind then
			seen = seen + 1
			if seen == index then
				local a = list[i]
				local expires = a.remaining and (state.time + a.remaining) or 0
				local caster = "other"
				if a.mine then caster = (a.casterName and fake.UnitName()) or "player" end
				return a.name, "", "", a.count or 1, "", a.remaining or 0, expires, caster
			end
		end
	end
	return nil
end

fake.UnitBuff = function(u, i) return auraAt(u, "buff", i) end
fake.UnitDebuff = function(u, i) return auraAt(u, "debuff", i) end
fake.UnitName = function(u)
	local x = state.units[u]
	return (x and x.name) or "TestMage"
end

-- ---------------------------------------------------------------------------
-- module loader
-- ---------------------------------------------------------------------------

local function loadModule(path, ns)
	local chunk = assert(loadfile(path))
	local env = setmetatable({}, {
		__index = function(_, k)
			if fake[k] ~= nil then return fake[k] end
			return _G[k]
		end,
	})
	env._G = env
	setfenv(chunk, env)
	chunk("Accessibility", ns)
end

-- ---------------------------------------------------------------------------
-- assertions
-- ---------------------------------------------------------------------------

local passed, failed = 0, 0

local function ok(name, cond)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. name)
	end
end

local function eq(name, got, want)
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(("FAIL: %s (got %q, want %q)"):format(name, tostring(got), tostring(want)))
	end
end

-- ---------------------------------------------------------------------------
-- load the modules
-- ---------------------------------------------------------------------------

-- Resolve the addon root from the script path, so the runner works from the
-- addon root or one directory above it.
local script = arg and arg[0] or "tests/run.lua"
local dir = script:match("^(.*)[/\\]") or "."
local ROOT = dir .. "/../"

loadModule(ROOT .. "Utils/Constants.lua", ns)
loadModule(ROOT .. "Utils/Compare.lua", ns)
loadModule(ROOT .. "Utils/Coerce.lua", ns)
loadModule(ROOT .. "Utils/Log.lua", ns)
loadModule(ROOT .. "Game/CastState.lua", ns)
loadModule(ROOT .. "Game/Unit.lua", ns)
loadModule(ROOT .. "Game/Player.lua", ns)
loadModule(ROOT .. "Game/Spell.lua", ns)
loadModule(ROOT .. "Game/Aura.lua", ns)
loadModule(ROOT .. "Game/Cast.lua", ns)
loadModule(ROOT .. "Game/Cooldown.lua", ns)
loadModule(ROOT .. "Game/Input.lua", ns)
loadModule(ROOT .. "Core/Compatibility.lua", ns)
loadModule(ROOT .. "Core/Profile.lua", ns)
loadModule(ROOT .. "Utils/SpellPicker.lua", ns)
loadModule(ROOT .. "Core/ConditionDefinitions.lua", ns)
loadModule(ROOT .. "Core/Conditions.lua", ns)
loadModule(ROOT .. "Core/Rotation.lua", ns)

ns.addon = { db = { profile = {} } }   -- Accessibility.lua (the entry) is not loaded; provide the db stub
ns.RotationButton = { ApplyPosition = function() end }   -- Config's button settings call it
_G.__dialogStatus = {}   -- the AceConfigDialog:GetStatusTable stub returns this

loadModule(ROOT .. "Core/Config.lua", ns)

local Compatibility = ns.Compatibility
local Profile = ns.Profile
local SpellPicker = ns.SpellPicker
local Spell = ns.Spell
local Conditions = ns.Conditions
local Rotation = ns.Rotation
local Config = ns.Config
local Log = ns.Log

local function prof() return ns.addon.db.profile end

-- ---------------------------------------------------------------------------
-- Compatibility tests
-- ---------------------------------------------------------------------------

ok("IsAvailable true with global", Compatibility.IsAvailable() == true)

-- the hostile-name round-trip: any string must become a valid literal
do
	local name = 'Fire"Ball\\0x'
	local escaped = string.format("%q", name)
	clearScripts()
	Compatibility.Call("return CastSpellByName(%s)", name)
	eq("hostile name escaped via %q", scripts[1], "return CastSpellByName(" .. escaped .. ")")
	local f = loadstring("return " .. escaped)
	ok("hostile name is a valid literal", f ~= nil and f() == name)
end

-- a NUL byte and an 8-bit byte must round-trip too
do
	local name = "a" .. string.char(0) .. "b" .. string.char(255)
	local escaped = string.format("%q", name)
	local f = loadstring("return " .. escaped)
	ok("NUL and 8-bit bytes round-trip", f ~= nil and f() == name)
end

-- numbers pass through, not %q'd
do
	clearScripts()
	Compatibility.Call("return UseAction(%d)", 7)
	eq("number passes through", scripts[1], "return UseAction(7)")
end

-- self-cast uses the player unit
do
	clearScripts()
	Compatibility.Cast("Renew", "player")
	eq("self cast template", scripts[1], 'CastSpellByName("Renew", "player")')
end

-- unlock probe
do
	state.secure = true
	ok("Recheck true when secure", Compatibility.Recheck() == true)
	ok("IsCompatible caches true", Compatibility.IsCompatible() == true)
	state.secure = false
	ok("Recheck false when insecure", Compatibility.Recheck() == false)
	ok("IsCompatible reflects recheck", Compatibility.IsCompatible() == false)
	state.secure = true
end

-- a shim attached after addon load must be picked up: a cached false must
-- re-probe once the Compatibility global appears
do
	local savedCompatibility = fake.Compatibility
	fake.Compatibility = nil                       -- shim not injected yet
	ok("IsAvailable false before attach", Compatibility.IsAvailable() == false)
	ok("IsCompatible false without shim", Compatibility.IsCompatible() == false)
	fake.Compatibility = savedCompatibility        -- shim attaches
	state.secure = true
	ok("IsCompatible recovers after attach", Compatibility.IsCompatible() == true)
end

-- ---------------------------------------------------------------------------
-- Cast and compatibility command boundary tests
-- ---------------------------------------------------------------------------

do
	local Cast = ns.Cast
	local CastState = ns.CastState
	local Unit = ns.Unit
	state.units.player = { exists = true, guid = "0x1111", castingEndMs = 900, castingSpell = "Fireball" }
	local normal = CastState.Read("player")
	ok("normal cast state name", normal ~= nil and normal.name == "Fireball")
	eq("normal cast end time", normal.endTimeMilliseconds, 900)
	ok("normal cast interruptible", normal.interruptible == true)
	eq("Cast.currentCast name", Cast.currentCast(), "Fireball")
	eq("Cast.currentCast end time", select(2, Cast.currentCast()), 900)
	ok("Unit.isCasting uses shared state", Unit.isCasting("player") == true)
	ok("Unit.isCastingSpell uses shared state", Unit.isCastingSpell("player", "Fireball") == true)
	ok("Unit.castInterruptible uses shared state", Unit.castInterruptible("player") == true)

	state.units.player = { exists = true, guid = "0x1111", castingEndMs = 900, castingSpell = "Fireball", notInterruptible = true }
	ok("uninterruptible cast state", Unit.castInterruptible("player") == false)
	state.units.player = { exists = true, guid = "0x1111", channelEndMs = 1200, channelSpell = "Mind Flay" }
	local channel = CastState.Read("player")
	ok("channel state used when no normal cast", channel ~= nil and channel.name == "Mind Flay" and channel.endTimeMilliseconds == 1200)
	ok("channel interruptible", Unit.castInterruptible("player") == true)
	state.units.player = { exists = true, guid = "0x1111" }
	ok("idle cast state is nil", CastState.Read("player") == nil and Cast.currentCast() == nil)

	state.units.target = { exists = true, guid = "0x2222" }
	clearScripts()
	local x, y, z = Compatibility.Position("target")
	eq("Position x", x, 4.5)
	eq("Position y", y, 5.75)
	eq("Position z", z, 6.25)
	eq("Position command", scripts[1], "Compatibility_Position 0x2222")

	clearScripts()
	eq("Scale result", Compatibility.Scale("target"), 1.5)
	eq("Scale command", scripts[1], "Compatibility_Scale 0x2222")
	clearScripts()
	eq("UnitCountInRange result", Compatibility.UnitCountInRange("target", "enemy", 8), 3)
	eq("UnitCountInRange command", scripts[1], "Compatibility_UnitCountInRange 0x2222 1 8.000000")
	ok("UnitCountInRange rejects unknown target type",
		Compatibility.UnitCountInRange("target", "unknown", 8) == nil)
	clearScripts()
	eq("friendly UnitCountInRange result", Compatibility.UnitCountInRange("player", "friendly", 20), 2)
	eq("friendly UnitCountInRange command", scripts[1], "Compatibility_UnitCountInRange 0x1111 2 20.000000")



	clearScripts()
	Compatibility.ConfirmGround("target")
	eq("ground position command", scripts[1], "Compatibility_Position 0x2222")
	eq("ground placement command", scripts[2], "Compatibility_PlaceGround 4.500000 5.750000 6.250000")

	clearScripts()
	local los = Compatibility.LoS("target")
	ok("LoS result", los == 1)
	eq("LoS player position command", scripts[1], "Compatibility_Position 0x1111")
	eq("LoS target position command", scripts[2], "Compatibility_Position 0x2222")
	eq("LoS player scale command", scripts[3], "Compatibility_Scale 0x1111")
	eq("LoS target scale command", scripts[4], "Compatibility_Scale 0x2222")
	eq("LoS command", scripts[5], "Compatibility_LOS 1.250000 2.500000 3.750000 4.500000 5.750000 6.250000 1.000000 1.500000")
end

-- ---------------------------------------------------------------------------
-- SpellPicker tests
-- ---------------------------------------------------------------------------

do
	state.knownSpells = { "Fireball", "Heroic Strike", "Blood Frenzy" }
	state.passiveSpells = { ["Blood Frenzy"] = true }
	SpellPicker.Refresh()

	ok("castable spell listed", SpellPicker.IsKnown("Fireball"))
	ok("castable spell listed 2", SpellPicker.IsKnown("Heroic Strike"))
	ok("passive spell filtered", not SpellPicker.IsKnown("Blood Frenzy"))
	ok("unknown spell not listed", not SpellPicker.IsKnown("Nope"))

	-- verifyShape: a known spell with the documented shape passes
	ok("verifyShape true on a known spell", ns.Spell.verifyShape() == true)

	-- Link resolution: a name resolves via GetSpellLink; no usable spell nil
	setSpell("Fireball", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1, testLink = "spell:133" })
	setUnit("player", { exists = true, dead = false, guid = "0x1111" })
	setUnit("target", { exists = true, dead = false, guid = "0x2222" })
	setSpell("DistanceSpell", {
		testLink = "spell:456", inRange = nil, minRange = 5, maxRange = 6
	})
	ok("range fallback uses player distance", Spell.inRange("DistanceSpell", "target") == true)
	state.spells.DistanceSpell.minRange = 6
	state.spells.DistanceSpell.maxRange = 7
	ok("range fallback rejects outside minimum", Spell.inRange("DistanceSpell", "target") == false)
	eq("Link from name", SpellPicker.Link({ spell = "Fireball" }), "spell:133")
	eq("Link nil without spell", SpellPicker.Link({}), nil)
	eq("Link nil with empty name", SpellPicker.Link({ spell = "" }), nil)
	setSpell("ChargeSpell", { testLink = "spell:123", currentCharges = 1, maxCharges = 2 })
	ok("hasCharges recognizes charge spell", ns.Spell.hasCharges("ChargeSpell") == true)
	eq("maxCharges returns charge maximum", ns.Spell.maxCharges("ChargeSpell"), 2)
	eq("currentCharges returns available charges", ns.Spell.currentCharges("ChargeSpell"), 1)
	setSpell("Fireball", { testLink = "spell:133", maxCharges = 0, currentCharges = 0 })
	ok("hasCharges rejects non-charge spell", ns.Spell.hasCharges("Fireball") == false)
	eq("non-charge maxCharges is zero", ns.Spell.maxCharges("Fireball"), 0)
	eq("non-charge currentCharges is zero", ns.Spell.currentCharges("Fireball"), 0)

	-- clean up so rotation tests rebuild the spellbook fresh
	state.knownSpells = {}
	state.passiveSpells = {}
end


-- ---------------------------------------------------------------------------
-- Profile sanitization tests
-- ---------------------------------------------------------------------------

do
	local p = {
		auto = 0,
		pulseInterval = -5,
		gcdProbeSpell = 123,
		rules = {
		{ spell = "Fireball", enabled = false, unit = "banana", conditions = { { type = "unit_target_type", value = "enemy" }, { type = "nope" } } },
			{ spell = "", enabled = true },
			"garbage",
			{ spell = "Renew" },
		},
		button = { scale = 99, x = "0", locked = 1 },
	}
	Profile.sanitizeProfile(p)

	eq("auto coerced", p.auto, false)
	eq("pulseInterval clamped", p.pulseInterval, 0.05)
	eq("gcdProbeSpell coerced", p.gcdProbeSpell, "")
	eq("queueWindow defaulted", p.queueWindow, 0.4)
	eq("antiSpamWindow defaulted", p.antiSpamWindow, 1.0)
	eq("jitterWindow defaulted", p.jitterWindow, 0.0)
	eq("legacy rules migrated to one rotation", #p.rotations, 1)
	eq("migrated rotation named Default", p.rotations[1].name, "Default")
	eq("active set to Default", p.active, "Default")
	eq("legacy rules field removed", p.rules, nil)
	local rules = p.rotations[1].rules
	eq("rules length", #rules, 2)

	local r1 = rules[1]
	eq("rule spell kept", r1.spell, "Fireball")
	eq("rule enabled coerced", r1.enabled, false)
	eq("rule unit kept (no whitelist)", r1.unit, "banana")
	eq("condition count (unknown dropped)", #r1.conditions, 1)
	eq("condition type migrated", r1.conditions[1].type, "unit_is_enemy")

	eq("button scale clamped", p.button.scale, 2.0)
	eq("button locked coerced", p.button.locked, false)
	eq("button enabled defaulted", p.button.enabled, true)
	local lowAnti = { antiSpamWindow = -1 }
	Profile.sanitizeProfile(lowAnti)
	eq("antiSpamWindow clamps low", lowAnti.antiSpamWindow, 0.0)
	local highAnti = { antiSpamWindow = 3 }
	Profile.sanitizeProfile(highAnti)
	eq("antiSpamWindow clamps high", highAnti.antiSpamWindow, 2.0)
	local lowJitter = { jitterWindow = -1 }
	Profile.sanitizeProfile(lowJitter)
	eq("jitterWindow clamps low", lowJitter.jitterWindow, 0.0)
	local highJitter = { jitterWindow = 1.2 }
	Profile.sanitizeProfile(highJitter)
	eq("jitterWindow clamps high", highJitter.jitterWindow, 1.0)
end

-- ---------------------------------------------------------------------------
-- Conditions tests
-- ---------------------------------------------------------------------------

do
	ok("Eval unknown type fails closed", Conditions.Eval({ type = "nope" }) == false)
	local expectedTypes = {
		"unit_exists", "unit_alive", "unit_name", "unit_is_enemy", "unit_is_friendly", "unit_hostile",
		"unit_is_player", "unit_classification", "unit_level", "unit_in_combat",
		"unit_moving",
		"unit_health_percent", "unit_health", "unit_power_percent", "unit_power",
		"unit_aura_present", "unit_aura_stacks", "unit_aura_remains",
		"unit_casting", "unit_casting_spell", "unit_cast_interruptible", "unit_spell_range", "unit_range", "unit_nearby_count",
		"spell_ready", "spell_usable", "spell_cooldown_remaining",
		"player_combo_points", "player_shapeshift_form",
		"player_is_tanking_unit", "player_unit_threat_percent", "modifier_keys", "lua",
	}
	eq("unit health label", Conditions.Registry.unit_health_percent.label, "Unit health percentage")
	eq("spell ready label", Conditions.Registry.spell_ready.label, "Spell is ready")
	eq("spell range label", Conditions.Registry.unit_spell_range.label, "Unit is in spell range")
	eq("unit range label", Conditions.Registry.unit_range.label, "Unit distance")
	eq("nearby count label", Conditions.Registry.unit_nearby_count.label, "Units near unit")
	eq("aura remaining label stays consistent", Conditions.Registry.unit_aura_remains.label, "Unit aura time remaining")
	local typeList = Conditions.TypeList()
	local seenTypes = {}
	local orderedTypes = #typeList == #expectedTypes
	for i = 1, #typeList do
		orderedTypes = orderedTypes and typeList[i].key == expectedTypes[i] and not seenTypes[typeList[i].key]
		seenTypes[typeList[i].key] = true
	end
	ok("condition registry order is stable and unique", orderedTypes)
	ok("Eval non-table fails closed", Conditions.Eval("x") == false)

	-- unit_name and explicit relationship conditions
	setUnit("target", { exists = true, dead = false, hostile = true, enemy = true, friendly = false, name = "Enemy" })
	ok("unit_name matches", Conditions.Eval({ type = "unit_name", unit = "target", value = "Enemy" }) == true)
	ok("unit_is_enemy passes on hostile", Conditions.Eval({ type = "unit_is_enemy", unit = "target" }) == true)
	ok("unit_is_friendly fails on hostile", Conditions.Eval({ type = "unit_is_friendly", unit = "target" }) == false)
	setUnit("target", { exists = true, dead = false, hostile = false, enemy = false, friendly = true, name = "Ally" })
	ok("unit_is_friendly passes on friendly", Conditions.Eval({ type = "unit_is_friendly", unit = "target" }) == true)
	ok("unit_is_enemy fails on friendly", Conditions.Eval({ type = "unit_is_enemy", unit = "target" }) == false)
	setUnit("target", { exists = true, dead = true, hostile = true })
	ok("unit_exists passes for dead unit", Conditions.Eval({ type = "unit_exists", unit = "target" }) == true)
	ok("unit_alive fails for dead unit", Conditions.Eval({ type = "unit_alive", unit = "target" }) == false)
	setUnit("target", { exists = true, dead = false, hostile = true })
	ok("unit_alive passes for living unit", Conditions.Eval({ type = "unit_alive", unit = "target" }) == true)

	-- health_percent
	setUnit("target", { exists = true, dead = false, health = 30, maxHealth = 100, hostile = true })
	ok("unit_health_percent < 50 passes", Conditions.Eval({ type = "unit_health_percent", unit = "target", op = "<", value = 50 }) == true)
	ok("unit_health_percent > 50 fails", Conditions.Eval({ type = "unit_health_percent", unit = "target", op = ">", value = 50 }) == false)

	-- in_combat
	state.inCombat = true
	ok("unit_in_combat passes in combat", Conditions.Eval({ type = "unit_in_combat", unit = "player" }) == true)
	state.inCombat = false
	ok("unit_in_combat fails out of combat", Conditions.Eval({ type = "unit_in_combat", unit = "player" }) == false)

	-- aura_missing / aura_present
	state.auras.target = {}
	ok("aura_missing passes with no aura", Conditions.Eval({ type = "unit_aura_missing", unit = "target", aura = "Moonfire", kind = "debuff", mine = true }) == true)
	state.auras.target = { { kind = "debuff", name = "Moonfire", count = 1, remaining = 10, mine = true } }
	ok("aura_present passes with the aura", Conditions.Eval({ type = "unit_aura_present", unit = "target", aura = "Moonfire", kind = "debuff" }) == true)
	ok("aura_missing fails with the aura", Conditions.Eval({ type = "unit_aura_missing", unit = "target", aura = "Moonfire", kind = "debuff", mine = true }) == false)

	-- bug fix: the game reports the player's own auras with the character
	-- name as caster; mineOnly must still count that as ours
	state.auras.target = { { kind = "debuff", name = "Moonfire", count = 1, remaining = 10, mine = true, casterName = true } }
	ok("mineOnly accepts caster as name", Conditions.Eval({ type = "unit_aura_missing", unit = "target", aura = "Moonfire", kind = "debuff", mine = true }) == false)

	-- bug fix: a permanent aura (no expiry) reports 0 remaining; that is
	-- PRESENT, not missing
	state.auras.target = { { kind = "buff", name = "Frost Armor", count = 1, remaining = nil, mine = true } }
	ok("permanent aura present (0 remaining)", Conditions.Eval({ type = "unit_aura_present", unit = "target", aura = "Frost Armor", kind = "buff" }) == true)
	ok("permanent aura not missing", Conditions.Eval({ type = "unit_aura_missing", unit = "target", aura = "Frost Armor", kind = "buff" }) == false)

	-- a stranger's copy still does not satisfy mineOnly
	state.auras.target = { { kind = "debuff", name = "Moonfire", count = 1, remaining = 10, mine = false } }
	ok("stranger dot not mine", Conditions.Eval({ type = "unit_aura_missing", unit = "target", aura = "Moonfire", kind = "debuff", mine = true }) == true)

	-- bug fix: 3.3.5a reports auras with a rank suffix; the plain name must
	-- still match, so "Aura missing" is false while the aura is up
	state.auras.target = { { kind = "debuff", name = "Moonfire (Rank 2)", count = 1, remaining = 10, mine = true } }
	ok("ranked aura matches plain name (present)", Conditions.Eval({ type = "unit_aura_present", unit = "target", aura = "Moonfire", kind = "debuff" }) == true)
	ok("ranked aura not missing", Conditions.Eval({ type = "unit_aura_missing", unit = "target", aura = "Moonfire", kind = "debuff" }) == false)
	-- and the reverse: a configured name with the rank matches a plain report
	state.auras.target = { { kind = "debuff", name = "Moonfire", count = 1, remaining = 10, mine = true } }
	ok("plain aura matches ranked name", Conditions.Eval({ type = "unit_aura_missing", unit = "target", aura = "Moonfire (Rank 2)", kind = "debuff" }) == false)

	-- spell_ready GCD trick
	setSpell("Fireball", { cdStart = 10, cdDuration = 1.5 })
	state.time = 10.5
	ok("spell_ready treats 1.5s as the GCD (ready)", Conditions.Eval({ type = "spell_ready", spell = "Fireball" }) == true)

	-- describe returns a string for a known type
	ok("Describe returns a string", type(Conditions.Describe({ type = "unit_in_combat", unit = "player" })) == "string")
	setUnit("target", { exists = true, dead = false, health = 30, maxHealth = 100, hostile = true })
	ok("negated passing condition fails", Conditions.Eval({
		type = "unit_health_percent", unit = "target", op = "<", value = 50, negated = true
	}) == false)
	ok("negated failing condition passes", Conditions.Eval({
		type = "unit_health_percent", unit = "target", op = ">", value = 50, negated = true
	}) == true)
	ok("incomplete negated condition still fails", Conditions.Eval({
		type = "unit_health_percent", unit = "target", negated = true
	}) == false)
	ok("negated evaluator error fails closed", Conditions.Eval({
		type = "lua", code = "error('broken')", negated = true
	}) == false)
	eq("negated description is explicit",
		Conditions.Describe({ type = "unit_health_percent", unit = "target", op = "<", value = 50, negated = true }),
		"not target health < 50%")

	-- Removed inverse conditions migrate to their positive type with negation.
	local missingClean = Conditions.Sanitize({
		type = "unit_aura_missing", unit = "target", aura = "Moonfire", kind = "debuff"
	})
	ok("aura_missing migrates to negated aura_present",
		missingClean ~= nil and missingClean.type == "unit_aura_present" and missingClean.negated == true)
	local stillClean = Conditions.Sanitize({ type = "unit_standing_still", unit = "player" })
	ok("standing_still migrates to negated moving",
		stillClean ~= nil and stillClean.type == "unit_moving" and stillClean.negated == true)

	-- sanitize drops unknown fields
	local clean = Conditions.Sanitize({ type = "unit_health_percent", unit = "target", op = "<", value = 30, junk = "x" })
	ok("Sanitize keeps declared fields", clean ~= nil and clean.unit == "target" and clean.op == "<" and clean.value == 30)
	ok("Sanitize drops unknown fields", clean ~= nil and clean.junk == nil)
	local disabledClean = Conditions.Sanitize({ type = "unit_in_combat", unit = "player", enabled = false })
	eq("Sanitize preserves condition enabled", disabledClean.enabled, false)
	local negatedClean = Conditions.Sanitize({ type = "unit_in_combat", unit = "player", negated = true })
	eq("Sanitize preserves condition negated", negatedClean.negated, true)
	local invalidNegated = Conditions.Sanitize({ type = "unit_in_combat", unit = "player", negated = "yes" })
	eq("Sanitize defaults invalid negated", invalidNegated.negated, false)
	ok("Sanitize drops unknown type", Conditions.Sanitize({ type = "nope" }) == nil)

	-- legacy type keys from before the rename migrate on sanitize
	local legacy = Conditions.Sanitize({ type = "health_pct", unit = "target", op = "<", value = 40 })
	ok("legacy health_pct migrates", legacy ~= nil and legacy.type == "unit_health_percent" and legacy.value == 40)
	local legacyPower = Conditions.Sanitize({ type = "power_pct", unit = "player", op = ">", value = 60 })
	ok("legacy power_pct migrates", legacyPower ~= nil and legacyPower.type == "unit_power_percent" and legacyPower.value == 60)

	-- legacy keys also evaluate without a sanitize pass (fresh rotation data)
	setUnit("target", { exists = true, dead = false, health = 30, maxHealth = 100, hostile = true, enemy = true })
	ok("legacy health_pct evals", Conditions.Eval({ type = "health_pct", unit = "target", op = "<", value = 50 }) == true)
	ok("ResolveType maps legacy key", Conditions.ResolveType("health_pct") == "unit_health_percent")
	ok("ResolveType passes current key", Conditions.ResolveType("unit_health_percent") == "unit_health_percent")

	-- target_type condition values migrate to explicit condition types
	local legacyEnemy = Conditions.Sanitize({ type = "unit_target_type", unit = "target", value = "enemy" })
	local legacyFriendly = Conditions.Sanitize({ type = "target_type", unit = "target", value = "friendly" })
	local legacyAny = Conditions.Sanitize({ type = "unit_target_type", unit = "target", value = "any" })
	local legacyPlayer = Conditions.Sanitize({ type = "target_type", unit = "target", value = "player" })
	ok("target_type enemy migrates", legacyEnemy ~= nil and legacyEnemy.type == "unit_is_enemy" and legacyEnemy.value == nil)
	ok("target_type friendly migrates", legacyFriendly ~= nil and legacyFriendly.type == "unit_is_friendly" and legacyFriendly.value == nil)
	ok("target_type any migrates", legacyAny ~= nil and legacyAny.type == "unit_alive" and legacyAny.value == nil)
	ok("target_type player migrates", legacyPlayer ~= nil and legacyPlayer.type == "unit_is_player" and legacyPlayer.value == nil)
	ok("target_type legacy evals", Conditions.Eval({
		type = "unit_target_type", unit = "target", value = "enemy"
	}) == true)
	ok("rename: in_combat -> unit_in_combat", Conditions.ResolveType("in_combat") == "unit_in_combat")
	ok("rename: range -> unit_spell_range", Conditions.ResolveType("range") == "unit_spell_range")
	ok("rename: cooldown_remaining -> spell_cooldown_remaining", Conditions.ResolveType("cooldown_remaining") == "spell_cooldown_remaining")
	ok("rename: combo_points -> player_combo_points", Conditions.ResolveType("combo_points") == "player_combo_points")
	ok("rename: shapeshift_form -> player_shapeshift_form", Conditions.ResolveType("shapeshift_form") == "player_shapeshift_form")
	ok("rename: cast_interruptible -> unit_cast_interruptible", Conditions.ResolveType("cast_interruptible") == "unit_cast_interruptible")
	ok("rename: threat_pct -> player_unit_threat_percent", Conditions.ResolveType("threat_pct") == "player_unit_threat_percent")
	ok("rename: is_tanking -> player_is_tanking_unit", Conditions.ResolveType("is_tanking") == "player_is_tanking_unit")
	ok("rename: aura_remains -> unit_aura_remains", Conditions.ResolveType("aura_remains") == "unit_aura_remains")
	-- legacy renames evaluate after migration without a sanitize pass
	ok("legacy in_combat evals", Conditions.Eval({ type = "in_combat", unit = "player" }) == false)

	-- completeness check: conditions with missing required fields fail eval
	ok("incomplete condition fails (nil unit)", Conditions.Eval({ type = "unit_in_combat" }) == false)
	ok("incomplete condition fails (empty aura)", Conditions.Eval({ type = "unit_aura_missing", unit = "target", kind = "debuff" }) == false)
	-- optional fields (power, mine) do not make a condition incomplete
	ok("optional mine=nil passes", Conditions.Eval({ type = "unit_aura_missing", unit = "target", aura = "NotPresent", kind = "buff" }) == true)
	-- ordered condition descriptors are the shared editor and runtime contract
	local function fieldKeys(conditionType)
		local keys = {}
		local fields = Conditions.Fields(conditionType)
		for i = 1, #fields do keys[i] = fields[i].key end
		return table.concat(keys, ",")
	end
	eq("unit_power_percent field order", fieldKeys("unit_power_percent"), "unit,power,op,value")
	eq("spell cooldown field order", fieldKeys("spell_cooldown_remaining"), "spell,op,value")
	eq("player combo field order", fieldKeys("player_combo_points"), "op,value")
	eq("modifier field order", fieldKeys("modifier_keys"), "key")
	eq("aura presence field order", fieldKeys("unit_aura_present"), "unit,aura,kind,mine")
	eq("nearby count field order", fieldKeys("unit_nearby_count"), "unit,value,radius,op,count")

	local presenceClean = Conditions.Sanitize({
		type = "unit_aura_present", unit = "target", aura = "Moonfire",
		kind = "debuff", op = ">", value = 3
	})
	ok("aura presence drops time comparison fields",
		presenceClean.op == nil and presenceClean.value == nil)
	eq("optional power descriptor", Conditions.Fields("unit_power_percent")[2].type, "power")
	eq("condition field label", Conditions.FieldLabel("target_type"), "target type")
	ok("unknown condition fields are nil", Conditions.Fields("not_a_condition") == nil)
	ok("IsComplete rejects unknown condition", Conditions.IsComplete({ type = "not_a_condition" }) == false)
	ok("IsComplete matches incomplete Eval", Conditions.IsComplete({ type = "unit_in_combat" }) == false and
		Conditions.Eval({ type = "unit_in_combat" }) == false)
	ok("IsComplete matches complete Eval shape", Conditions.IsComplete({ type = "unit_in_combat", unit = "player" }) == true)

	-- raw health and power values, and the power pool selector. The player
	-- has mana 100/120 and rage 22/100 (hybrid, per the live probe).
	setUnit("player", { exists = true, dead = false, health = 80, maxHealth = 100,
		power = 100, maxPower = 120, powers = { [0] = 100, [1] = 22 }, maxPowers = { [0] = 120, [1] = 100 } })
	ok("unit_health raw < 90 passes", Conditions.Eval({ type = "unit_health", unit = "player", op = "<", value = 90 }) == true)
	ok("unit_health raw < 70 fails", Conditions.Eval({ type = "unit_health", unit = "player", op = "<", value = 70 }) == false)
	ok("unit_health_percent still works", Conditions.Eval({ type = "unit_health_percent", unit = "player", op = "<", value = 90 }) == true)
	ok("unit_power raw current pool >= 100 passes", Conditions.Eval({ type = "unit_power", unit = "player", op = ">=", value = 100 }) == true)
	ok("unit_power raw rage >= 20 passes", Conditions.Eval({ type = "unit_power", unit = "player", power = 1, op = ">=", value = 20 }) == true)
	ok("unit_power raw rage >= 30 fails", Conditions.Eval({ type = "unit_power", unit = "player", power = 1, op = ">=", value = 30 }) == false)
	ok("unit_power_percent rage >= 20 passes", Conditions.Eval({ type = "unit_power_percent", unit = "player", power = 1, op = ">=", value = 20 }) == true)
	ok("unit_power_percent rage >= 30 fails", Conditions.Eval({ type = "unit_power_percent", unit = "player", power = 1, op = ">=", value = 30 }) == false)
	ok("unit_power_percent current pool passes", Conditions.Eval({ type = "unit_power_percent", unit = "player", op = ">=", value = 80 }) == true)
	-- sanitize coerces the power field to a number and drops junk
	local powerClean = Conditions.Sanitize({ type = "unit_power", unit = "player", power = "1", op = ">=", value = 20, junk = "x" })
	ok("unit_power sanitize coerces power", powerClean ~= nil and powerClean.power == 1 and powerClean.junk == nil)
	-- describe renders the pool name without erroring (upvalue ordering bug)
	ok("unit_power describe names the pool", Conditions.Describe({ type = "unit_power", unit = "player", power = 1, op = ">=", value = 20 }) == "player rage >= 20")
	ok("unit_power describe current pool", Conditions.Describe({ type = "unit_power", unit = "player", op = ">=", value = 20 }) == "player power >= 20")

	-- bug fix: switching a condition's type must not leak the old type's
	-- fields. A string "value" from unit_target_type ("enemy") assigned to a
	-- number-typed field must be dropped, or the editor's slider crashes on
	-- render (AceGUI Slider:SetValue requires a number).
	local switched = Conditions.Sanitize({ type = "spell_cooldown_remaining", spell = "Fireball", op = "<", value = "enemy" })
	ok("type switch drops stale string value", switched ~= nil and switched.value == nil and switched.spell == "Fireball")
	local switched2 = Conditions.Sanitize({ type = "unit_health", unit = "target", op = "<", value = "enemy" })
	ok("type switch to unit_health drops stale value", switched2 ~= nil and switched2.value == nil)

	-- combo_points (always on the player's target; no unit field)
	setUnit("target", { exists = true, dead = false, hostile = true, comboPoints = 4 })
	ok("player_combo_points >= 3 passes", Conditions.Eval({ type = "player_combo_points", op = ">=", value = 3 }) == true)
	ok("player_combo_points >= 5 fails", Conditions.Eval({ type = "player_combo_points", op = ">=", value = 5 }) == false)
	local comboClean = Conditions.Sanitize({ type = "player_combo_points", unit = "focus", op = ">=", value = 3 })
	ok("player_combo_points sanitize drops unit", comboClean ~= nil and comboClean.unit == nil and comboClean.op == ">=" and comboClean.value == 3)

	-- shapeshift_form (name-based, form 1 active)
	state.shapeshiftForms = { "Bear Form" }
	state.shapeshiftForm = 1
	ok("player_shapeshift_form matches active form", Conditions.Eval({ type = "player_shapeshift_form", form = "Bear Form" }) == true)
	ok("player_shapeshift_form rejects other form", Conditions.Eval({ type = "player_shapeshift_form", form = "Cat Form" }) == false)
	state.shapeshiftForm = 0
	ok("player_shapeshift_form fails when not in a form", Conditions.Eval({ type = "player_shapeshift_form", form = "Bear Form" }) == false)
	state.shapeshiftForm = nil
	state.shapeshiftForms = nil

	-- unit_casting_spell + cast_interruptible
	setUnit("target", { exists = true, dead = false, castingEndMs = 500, castingSpell = "Fireball" })
	ok("unit_casting_spell matches cast name", Conditions.Eval({ type = "unit_casting_spell", unit = "target", spell = "Fireball" }) == true)
	ok("unit_casting_spell rejects other spell", Conditions.Eval({ type = "unit_casting_spell", unit = "target", spell = "Frostbolt" }) == false)
	ok("unit_cast_interruptible passes on interruptible cast", Conditions.Eval({ type = "unit_cast_interruptible", unit = "target" }) == true)
	setUnit("target", { exists = true, dead = false, castingEndMs = 500, castingSpell = "Fireball", notInterruptible = true })
	ok("unit_cast_interruptible fails on un-interruptible cast", Conditions.Eval({ type = "unit_cast_interruptible", unit = "target" }) == false)
	setUnit("target", { exists = true, dead = false })
	ok("unit_cast_interruptible fails when not casting", Conditions.Eval({ type = "unit_cast_interruptible", unit = "target" }) == false)

	-- unit_level
	setUnit("target", { exists = true, dead = false, hostile = true, level = 80 })
	ok("unit_level >= 80 passes", Conditions.Eval({ type = "unit_level", unit = "target", op = ">=", value = 80 }) == true)
	ok("unit_level >= 81 fails", Conditions.Eval({ type = "unit_level", unit = "target", op = ">=", value = 81 }) == false)

	-- unit_is_player
	setUnit("target", { exists = true, dead = false, hostile = true, isPlayer = true })
	ok("unit_is_player passes on player", Conditions.Eval({ type = "unit_is_player", unit = "target" }) == true)
	setUnit("target", { exists = true, dead = false, hostile = true, isPlayer = false })
	ok("unit_is_player fails on mob", Conditions.Eval({ type = "unit_is_player", unit = "target" }) == false)

	-- unit_classification
	setUnit("target", { exists = true, dead = false, hostile = true, classification = "elite" })
	ok("unit_classification elite passes", Conditions.Eval({ type = "unit_classification", unit = "target", value = "elite" }) == true)
	ok("unit_classification worldboss fails", Conditions.Eval({ type = "unit_classification", unit = "target", value = "worldboss" }) == false)

	-- unit_spell_range uses a spell-range query; unit_range compares distance.
	setSpell("Fireball", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1 })
	setUnit("player", { exists = true, dead = false, guid = "0x1111" })
	setUnit("target", { exists = true, dead = false, guid = "0x2222", hostile = true })
	local distance = ns.Unit.distance("player", "target")
	ok("Unit.distance uses shim positions", distance > 5 and distance < 6)
	ok("unit_range compares unit distance", Conditions.Eval({ type = "unit_range", unit = "target", op = "<", value = 6 }) == true)
	ok("unit_range rejects distant unit", Conditions.Eval({ type = "unit_range", unit = "target", op = ">", value = 6 }) == false)
	ok("unit_spell_range evaluates spell range", Conditions.Eval({ type = "unit_spell_range", spell = "Fireball", unit = "target" }) == true)
	ok("unit_nearby_count compares enemy count",
		Conditions.Eval({ type = "unit_nearby_count", unit = "target", value = "enemy",
			radius = 8, op = ">=", count = 3 }) == true)
	ok("unit_nearby_count description",
		Conditions.Describe({ type = "unit_nearby_count", unit = "target", value = "enemy",
			radius = 8, op = ">=", count = 3 }) == "enemy units within 8 yards of target >= 3")
	ok("unit_nearby_count rejects a higher threshold",
		Conditions.Eval({ type = "unit_nearby_count", unit = "target", value = "enemy",
			radius = 8, op = ">=", count = 5 }) == false)
	ok("unit_nearby_count rejects missing radius",
		Conditions.Eval({ type = "unit_nearby_count", unit = "target", value = "enemy",
			op = ">=", count = 3 }) == false)
	ok("unit_nearby_count supports negation",
		Conditions.Eval({ type = "unit_nearby_count", unit = "target", value = "enemy",
			radius = 8, op = ">=", count = 5, negated = true }) == true)
	setUnit("target", { exists = true, dead = false, guid = "0xdead" })
	ok("unit_nearby_count fails closed on native failure",
		Conditions.Eval({ type = "unit_nearby_count", unit = "target", value = "enemy",
			radius = 8, op = ">=", count = 1 }) == false)
	setUnit("target", { exists = true, dead = false, guid = "0x2222", hostile = true })
	local nearbySwitched = Conditions.Sanitize({
		type = "unit_target_type", unit = "target", value = "enemy", radius = 8, count = 3
	})
	ok("nearby count fields do not leak across type switches",
		nearbySwitched.radius == nil and nearbySwitched.count == nil)


	local migratedSpellRange = Conditions.Sanitize({ type = "unit_range", spell = "Fireball", unit = "target" })
	eq("old unit_range migrates to unit_spell_range", migratedSpellRange.type, "unit_spell_range")

	-- threat_pct + is_tanking
	setUnit("target", { exists = true, dead = false, hostile = true, threatPercent = 120, isTanking = true })
	ok("player_unit_threat_percent >= 100 passes", Conditions.Eval({ type = "player_unit_threat_percent", unit = "target", op = ">=", value = 100 }) == true)
	ok("player_is_tanking_unit passes when tanking", Conditions.Eval({ type = "player_is_tanking_unit", unit = "target" }) == true)
	setUnit("target", { exists = true, dead = false, hostile = true, threatPercent = 50, isTanking = false })
	ok("player_unit_threat_percent >= 100 fails at 50", Conditions.Eval({ type = "player_unit_threat_percent", unit = "target", op = ">=", value = 100 }) == false)
	ok("player_is_tanking_unit fails when not tanking", Conditions.Eval({ type = "player_is_tanking_unit", unit = "target" }) == false)

	-- aura_remains: presence implied, compares remaining
	state.auras.target = { { kind = "buff", name = "Frost Armor", count = 1, remaining = 5, mine = true } }
	ok("unit_aura_remains > 3 passes", Conditions.Eval({ type = "unit_aura_remains", unit = "target", aura = "Frost Armor", kind = "buff", op = ">", value = 3 }) == true)
	ok("unit_aura_remains > 8 fails", Conditions.Eval({ type = "unit_aura_remains", unit = "target", aura = "Frost Armor", kind = "buff", op = ">", value = 8 }) == false)
	state.auras.target = {}
	ok("unit_aura_remains fails when absent", Conditions.Eval({ type = "unit_aura_remains", unit = "target", aura = "Frost Armor", kind = "buff", op = ">", value = 3 }) == false)

	-- modifier_keys
	state.shiftKey = true
	ok("modifier_keys shift passes", Conditions.Eval({ type = "modifier_keys", key = "shift" }) == true)
	state.shiftKey = nil
	ok("modifier_keys shift fails when released", Conditions.Eval({ type = "modifier_keys", key = "shift" }) == false)
	state.controlKey = true
	ok("modifier_keys control passes", Conditions.Eval({ type = "modifier_keys", key = "control" }) == true)
	state.controlKey = nil
	state.altKey = true
	ok("modifier_keys alt passes", Conditions.Eval({ type = "modifier_keys", key = "alt" }) == true)
	state.altKey = nil
end

-- ---------------------------------------------------------------------------
-- Rotation tests
-- ---------------------------------------------------------------------------

-- A monotonically increasing clock. Each scenario starts far past the last
-- cast, so the module-local GCD and anti-spam timers do not leak across
-- scenarios.
local scenarioTime = 0

-- rules() returns the active rotation's rule array; setRules() installs one.
-- The engine reads Profile.activeRules(), so the profile must carry a
-- rotations array and an active name.
local function setRules(t)
	prof().rotations = { { name = "Default", rules = t } }
	prof().active = "Default"
end

local function rules()
	return prof().rotations[1].rules
end


-- a helper to reset the world for one rotation scenario
local function resetRotation()
	scenarioTime = scenarioTime + 1000
	state.time = scenarioTime
	state.secure = true
	Rotation.ClearJitter()
	prof().antiSpamWindow = ns.Constants.DEFAULT_ANTI_SPAM_WINDOW
	setKnown({ "Fireball", "Renew", "probe" })
	setSpell("Fireball", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1 })
	setSpell("Renew", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1 })
	setSpell("probe", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1 })
	setUnit("player", { exists = true, dead = false })
	setUnit("target", { exists = true, dead = false, hostile = true, health = 100, maxHealth = 100 })
	setRules({ { name = "", spell = "Fireball", enabled = true, unit = "target", conditions = {} } })
	Compatibility.Recheck()
	clearScripts()
end

-- a rule that should pass every gate and cast
local function castOnce(name)
	rules()[1].spell = name
	setSpell(name, { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1 })
	return Rotation.CastBest()
end

resetRotation()
ok("CastBest casts the passing rule", castOnce("Fireball") == true)
ok("a cast script was emitted", #scripts >= 1 and scripts[1] == 'CastSpellByName("Fireball")')
resetRotation()
setKnown({ "ChargeSpell" })
setSpell("ChargeSpell", {
	usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1,
	testLink = "spell:123", currentCharges = 0, maxCharges = 2
})
rules()[1].spell = "ChargeSpell"
ok("charge spell with no charges is blocked", Rotation.CastBest() == false)
state.spells.ChargeSpell.currentCharges = 1
ok("charge spell with charges casts", Rotation.CastBest() == true)

resetRotation()
state.secure = false
Compatibility.Recheck()
ok("not unlocked blocks the cast", Rotation.CastBest() == false)
ok("log says not compatible", Log.Dump(1)[1]:find("not compatible", 1, true) ~= nil)
state.secure = true

resetRotation()
setUnit("player", { exists = true, dead = true })
ok("dead player blocks the cast", Rotation.CastBest() == false)
ok("log says player dead", Log.Dump(1)[1]:find("player dead", 1, true) ~= nil)

resetRotation()
prof().gcdProbeSpell = "probe"
setSpell("probe", { cdStart = state.time, cdDuration = 1.5 })
ok("on GCD blocks the cast", Rotation.CastBest() == false)

resetRotation()
setUnit("target", { exists = false })
ok("missing target blocks the cast", Rotation.CastBest() == false)

	rules()[1].spell = "Unknown"
ok("unknown spell blocks the cast", Rotation.CastBest() == false)

resetRotation()
setSpell("Fireball", { usable = false, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1 })
ok("not usable blocks the cast", Rotation.CastBest() == false)

resetRotation()
setSpell("Fireball", { usable = true, noMana = false, cdStart = state.time, cdDuration = 5, inRange = 1 })
ok("on cooldown blocks the cast", Rotation.CastBest() == false)

resetRotation()
setSpell("Fireball", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 0 })
ok("out of range blocks the cast", Rotation.CastBest() == false)

	rules()[1].conditions = { { type = "unit_in_combat", unit = "player" } }
state.inCombat = false
ok("failing condition blocks the cast", Rotation.CastBest() == false)

-- anti-spam: cast, then advance past the GCD but inside the 1.0s window
resetRotation()
local t0 = state.time
ok("first cast succeeds", Rotation.CastBest() == true)
state.time = t0 + 0.5
ok("anti-spam blocks a fast re-cast", Rotation.CastBest() == false)
state.time = t0 + 1.1
ok("cast succeeds after the anti-spam window", Rotation.CastBest() == true)
-- jitter delays automatic casts once, then preserves the selected candidate.
local originalRandom = math.random
math.random = function() return 0.5 end
resetRotation()
prof().jitterWindow = 0.4
clearScripts()
local jitterStart = state.time
	ok("automatic jitter holds the first pulse", Rotation.CastBest(true) == false)
	eq("automatic jitter emits nothing while waiting", #scripts, 0)
state.time = jitterStart + 0.19
ok("automatic jitter still holds before deadline", Rotation.CastBest(true) == false)
state.time = jitterStart + 0.2
ok("automatic jitter emits at deadline", Rotation.CastBest(true) == true)

-- Manual casts bypass the automatic jitter delay.
resetRotation()
prof().jitterWindow = 0.4
clearScripts()
ok("manual cast bypasses jitter", Rotation.CastBest(false) == true)

-- A sampled release inside the queue window still uses the client queue.
resetRotation()
prof().jitterWindow = 0.2
state.units.player.castingEndMs = (state.time + 0.5) * 1000
state.units.player.castingSpell = "LongCast"
clearScripts()
local queuedStart = state.time
ok("queue jitter arms while casting", Rotation.CastBest(true) == false)
state.time = queuedStart + 0.1
ok("queue jitter submits inside queue window", Rotation.CastBest(true) == true)

-- A sampled release after cast end creates a real inter-cast gap.
resetRotation()
prof().jitterWindow = 0.4
state.units.player.castingEndMs = (state.time + 0.2) * 1000
state.units.player.castingSpell = "LongCast"
clearScripts()
local gapStart = state.time
ok("gap jitter arms while casting", Rotation.CastBest(true) == false)
state.time = gapStart + 0.25
state.units.player.castingEndMs = nil
ok("gap jitter emits after cast end", Rotation.CastBest(true) == true)
-- A cancelled cast retries without a new jitter delay.
resetRotation()
prof().jitterWindow = 0.4
clearScripts()
local cancelledStart = state.time
ok("cancel retry arms the original cast", Rotation.CastBest(true) == false)
state.time = cancelledStart + 0.2
ok("cancel retry emits the first cast", Rotation.CastBest(true) == true)
Rotation.OnCastStarted("Fireball")
Rotation.OnCastCancelled("Fireball")
clearScripts()
ok("cancelled cast retries without jitter", Rotation.CastBest(true) == true)
math.random = originalRandom

resetRotation()
setRules({
	{ spell = "Blocked", enabled = true, unit = "target", conditions = { { type = "unit_in_combat", unit = "player" } } },
	{ spell = "Fireball", enabled = true, unit = "target", conditions = {} },
})
state.inCombat = false
clearScripts()
ok("walk skips a blocked rule", Rotation.CastBest() == true)
ok("walk cast the second rule", scripts[1] == 'CastSpellByName("Fireball")')

-- priority walk: the first passing rule wins, the walk stops
resetRotation()
setRules({
	{ spell = "Fireball", enabled = true, unit = "target", conditions = {} },
	{ spell = "Renew", enabled = true, unit = "target", conditions = {} },
})
clearScripts()
ok("walk casts the first passing rule", Rotation.CastBest() == true)
ok("only one cast was emitted", #scripts >= 1 and scripts[1] == 'CastSpellByName("Fireball")')
ok("the first rule won", scripts[1] == 'CastSpellByName("Fireball")')

-- NextRule: the button icon must show the first PASSING rule, so a blocked
-- first rule does not pin a stale icon
resetRotation()
setRules({
	{ spell = "Blocked", enabled = true, unit = "target", conditions = { { type = "unit_in_combat", unit = "player" } } },
	{ spell = "Fireball", enabled = true, unit = "target", conditions = {} },
})
state.inCombat = false
ok("NextRule skips a blocked rule", Rotation.NextRule() ~= nil)
ok("NextRule returns the passing rule", Rotation.NextRule().spell == "Fireball")

resetRotation()
setRules({
	{ spell = "Fireball", enabled = true, unit = "target", conditions = { { type = "unit_in_combat", unit = "player" } } },
	{ spell = "Renew", enabled = true, unit = "target", conditions = { { type = "unit_in_combat", unit = "player" } } },
})
state.inCombat = false
ok("NextRule nil when every rule blocked", Rotation.NextRule() == nil)
-- selection and simulation are read-only with respect to cast state.
resetRotation()
local selectedBefore = Rotation.NextRule()
Rotation.Simulate()
local selectedAfter = Rotation.NextRule()
ok("simulation preserves next selection", selectedBefore and selectedAfter and
	selectedBefore.spell == selectedAfter.spell)

local simulationEvaluations = 0
local previousCounter = Conditions.Registry.simulation_counter
Conditions.Registry.simulation_counter = {
	fields = {},
	eval = function()
		simulationEvaluations = simulationEvaluations + 1
		return true
	end,
}
resetRotation()
setRules({ { spell = "Fireball", enabled = true, unit = "target",
	conditions = { { type = "simulation_counter" } } } })
local simulationLines = Rotation.Simulate()
ok("simulation reports passing rule", simulationLines[1]:find("would cast", 1, true) ~= nil)
eq("simulation evaluates each condition once", simulationEvaluations, 1)
Conditions.Registry.simulation_counter = previousCounter


-- spell queue window: casting normally blocks, but inside the window the
-- cast is sent early so the client queues it. state.time is left at the
-- reset value (scenarioTime) so the GCD gate is clear; endMs is set relative
-- to it (endMs/1000 - state.time = remaining seconds).
resetRotation()
setUnit("player", { exists = true, dead = false, castingEndMs = (state.time + 4) * 1000 })
ok("mid-cast outside queue window blocks", Rotation.CastBest() == false)

resetRotation()
setUnit("player", { exists = true, dead = false, castingEndMs = (state.time + 0.2) * 1000 })
clearScripts()
ok("mid-cast inside queue window casts", Rotation.CastBest() == true)
eq("queue-window cast emitted", scripts[1], 'CastSpellByName("Fireball")')

-- queueWindow = 0 disables the early send: casting always blocks
resetRotation()
prof().queueWindow = 0
setUnit("player", { exists = true, dead = false, castingEndMs = (state.time + 0.2) * 1000 })
ok("queueWindow 0 blocks any mid-cast", Rotation.CastBest() == false)
prof().queueWindow = nil

-- channeling follows the same window logic
resetRotation()
setUnit("player", { exists = true, dead = false, channelEndMs = (state.time + 0.2) * 1000 })
clearScripts()
ok("mid-channel inside queue window casts", Rotation.CastBest() == true)

-- anti-spam must NOT block re-queueing a cast-time spell inside the window
-- (the cast itself is the spacer, and the 1.0s window would break the queue)
resetRotation()
setSpell("Fireball", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1, castMs = 2000 })
local tq = state.time
ok("cast-time spell first cast succeeds", Rotation.CastBest() == true)
-- 1.6s into a 2s cast: inside the 0.4s queue window, past the GCD fallback
state.time = tq + 1.6
setUnit("player", { exists = true, dead = false, castingEndMs = (tq + 2.0) * 1000 })
clearScripts()
ok("cast-time spell re-queues inside window (anti-spam bypassed)", Rotation.CastBest() == true)
eq("re-queue emitted the same spell", scripts[1], 'CastSpellByName("Fireball")')

-- an instant spell is still anti-spammed: 0.5s after casting it, blocked
resetRotation()
setSpell("Fireball", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1 })  -- instant
local ti = state.time
ok("instant spell first cast succeeds", Rotation.CastBest() == true)
state.time = ti + 0.5
ok("instant spell still anti-spammed", Rotation.CastBest() == false)
state.time = ti + 1.1
ok("instant spell casts again after the window", Rotation.CastBest() == true)

-- a zero anti-spam window permits an immediate second instant cast when the
-- explicit GCD probe is clear.
resetRotation()
prof().gcdProbeSpell = "probe"
prof().antiSpamWindow = 0.0
local immediateTime = state.time
ok("zero anti-spam first cast succeeds", Rotation.CastBest() == true)
state.time = immediateTime
ok("zero anti-spam permits immediate recast", Rotation.CastBest() == true)

-- aura condition accepts a numeric spell ID in the aura field
state.auras.target = {}
ok("aura missing resolves by name", Conditions.Eval({ type = "unit_aura_missing", unit = "target", aura = "Moonfire", kind = "debuff" }) == true)
state.auras.target = { { kind = "debuff", name = "Moonfire (Rank 2)", count = 1, remaining = 10, mine = true } }
ok("aura field accepts spell ID", Conditions.Eval({ type = "unit_aura_missing", unit = "target", aura = 8921, kind = "debuff" }) == false)
-- ---------------------------------------------------------------------------
-- Spell.stripRank tests
-- ---------------------------------------------------------------------------

do
	local Spell = ns.Spell
	eq("stripRank single rank", Spell.stripRank("Fireball (Rank 2)"), "Fireball")
	eq("stripRank multi rank", Spell.stripRank("Fireball (Ranks 2-3)"), "Fireball")
	eq("stripRank leaves plain name", Spell.stripRank("Fireball"), "Fireball")
end
-- ---------------------------------------------------------------------------
-- Cooldown helper tests
-- ---------------------------------------------------------------------------

do
	local Cooldown = ns.Cooldown

	ok("isGCD true for a 1.5s cooldown", Cooldown.isGCD(state.time, 1.5) == true)
	ok("isGCD false for a 5s cooldown", Cooldown.isGCD(state.time, 5) == false)
	ok("isGCD false with no start", Cooldown.isGCD(0, 1.5) == false)
	ok("isOwnCooldown true for a 5s cooldown", Cooldown.isOwnCooldown(state.time, 5) == true)
	ok("isOwnCooldown false for a 1.5s cooldown", Cooldown.isOwnCooldown(state.time, 1.5) == false)

	setSpell("Fireball", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1 })
	ok("isReady true off cooldown", Cooldown.isReady("Fireball") == true)
	setSpell("Fireball", { usable = false, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1 })
	ok("isReady false not usable", Cooldown.isReady("Fireball") == false)
	setSpell("Fireball", { usable = true, noMana = false, cdStart = state.time, cdDuration = 5, inRange = 1 })
	ok("isReady false on own cooldown", Cooldown.isReady("Fireball") == false)
	setSpell("Fireball", { usable = true, noMana = false, cdStart = state.time, cdDuration = 1.5, inRange = 1 })
	ok("isReady true on the GCD (not the spell's own)", Cooldown.isReady("Fireball") == true)
end

-- ---------------------------------------------------------------------------
-- Rotation management tests
-- ---------------------------------------------------------------------------

do
	-- start from a clean profile with the new schema
	prof().rotations = { { name = "Single", rules = { { spell = "Fireball", enabled = true, unit = "target", conditions = {} } } } }
	prof().active = "Single"

	ok("activeRules resolves the active rotation", Profile.activeRules() == prof().rotations[1].rules)

	-- add
	local second = Profile.addRotation("AoE")
	ok("addRotation appends", #prof().rotations == 2)
	eq("addRotation name kept", second.name, "AoE")
	eq("addRotation starts empty", #second.rules, 0)

	-- duplicate copies rules and names uniquely
	local dup = Profile.duplicateRotation(prof().rotations[1])
	eq("duplicate copies rules", #dup.rules, 1)
	eq("duplicate copies rule spell", dup.rules[1].spell, "Fireball")
	eq("duplicate unique name", dup.name, "Single copy")

	-- rename syncs the active pointer
	Profile.setActive(prof().rotations[1])
	eq("setActive sets name", prof().active, "Single")
	ok("setActiveByName matches", Profile.setActiveByName("AoE") == true)
	eq("setActiveByName changes active", prof().active, "AoE")
	ok("setActiveByName ignores unknown", Profile.setActiveByName("Nope") == false)
	eq("setActiveByName unknown keeps active", prof().active, "AoE")
	Profile.setActiveByName("Single")
	ok("renameRotation succeeds", Profile.renameRotation(prof().rotations[1], "ST"))
	eq("renameRotation syncs active", prof().active, "ST")

	-- rename refuses an empty name
	ok("renameRotation refuses empty", Profile.renameRotation(prof().rotations[1], "  ") == false)
	-- rename refuses a name already taken by another rotation
	prof().rotations = { { name = "One", rules = {} }, { name = "Two", rules = {} } }
	prof().active = "One"
	ok("renameRotation refuses duplicate", Profile.renameRotation(prof().rotations[1], "Two") == false)
	eq("renameRotation duplicate keeps name", prof().rotations[1].name, "One")

	-- delete refuses the last rotation
	prof().rotations = { { name = "Only", rules = {} } }
	prof().active = "Only"
	ok("deleteRotation refuses last", Profile.deleteRotation(prof().rotations[1]) == false)

	-- delete a non-last rotation reassigns active when needed
	prof().rotations = { { name = "A", rules = {} }, { name = "B", rules = {} } }
	prof().active = "A"
	ok("deleteRotation removes", Profile.deleteRotation(prof().rotations[1]) == true)
	eq("deleteRotation reassigns active", prof().active, "B")
	eq("deleteRotation shrinks list", #prof().rotations, 1)

	-- rule reorder within a rotation
	local rotation = { name = "R", rules = { { spell = "One", enabled = true, unit = "target", conditions = {} }, { spell = "Two", enabled = true, unit = "target", conditions = {} }, { spell = "Three", enabled = true, unit = "target", conditions = {} } } }
	Profile.moveRule(rotation, 1, 3)
	eq("moveRule reorders", rotation.rules[3].spell, "One")
	eq("moveRule shifts middle", rotation.rules[1].spell, "Two")
	ok("moveRule clamps low", (function() Profile.moveRule(rotation, 1, 0); return rotation.rules[1].spell == "Two" end)())
	ok("moveRule clamps high", (function() Profile.moveRule(rotation, 1, 99); return rotation.rules[3].spell == "One" end)())
end

-- ---------------------------------------------------------------------------
-- Profile mutation boundary tests
-- ---------------------------------------------------------------------------

do
	local rotation = Profile.newRotation("First")
	local duplicate = Profile.newRotation("Second")
	local rule = Profile.newRule()
	local condition = Profile.newCondition()
	eq("newRotation owns name", rotation.name, "First")
	eq("newRotation owns rules", #rotation.rules, 0)
	eq("newRule default spell", rule.spell, "")
	eq("newRule default enabled", rule.enabled, true)
	eq("newCondition default type", condition.type, "unit_exists")
	eq("newCondition default enabled", condition.enabled, true)
	eq("newCondition default negated", condition.negated, false)

	Profile.setRuleEnabled(rule, false)
	Profile.setRuleName(rule, "Primary")
	Profile.setRuleSpell(rule, "Fireball")
	Profile.setRuleUnit(rule, "target")
	eq("rule setters persist", rule.enabled, false)
	eq("rule name setter persists", rule.name, "Primary")
	eq("rule spell setter persists", rule.spell, "Fireball")
	eq("rule unit setter persists", rule.unit, "target")

	Profile.setConditionField(condition, "unit", "target")
	Profile.setConditionField(condition, "value", "enemy")
	Profile.setConditionNegated(condition, true)
	Profile.setConditionType(condition, "unit_health_percent")
	ok("condition type setter drops stale fields and preserves negation",
		condition.type == "unit_health_percent" and condition.value == nil and
		condition.unit == "target" and condition.negated == true)
	Profile.setConditionEnabled(condition, false)
	eq("condition enabled setter persists", condition.enabled, false)

	local live = Profile.current()
	live.rotations = { rotation, duplicate }
	live.active = "First"
	live.button = {}
	Profile.setAutoEnabled(true)
	Profile.setGcdProbeSpell("Fireball")
	Profile.setPulseInterval(0)
	Profile.setQueueWindow(9)
	Profile.setAntiSpamWindow(9)
	eq("auto setter persists", live.auto, true)
	eq("GCD setter persists", live.gcdProbeSpell, "Fireball")
	eq("pulse setter clamps", live.pulseInterval, 0.05)
	eq("queue setter clamps", live.queueWindow, 1.0)
	eq("anti-spam setter clamps", live.antiSpamWindow, 2.0)
	Profile.setButtonEnabled(live.button, false)
	Profile.setButtonLocked(live.button, true)
	Profile.setButtonPosition(live.button, "TOPLEFT", "BOTTOMRIGHT", 12, -8)
	Profile.setButtonScale(live.button, 9)
	eq("button enabled setter persists", live.button.enabled, false)
	eq("button locked setter persists", live.button.locked, true)
	eq("button position setter persists", live.button.point, "TOPLEFT")
	eq("button relative position persists", live.button.relativePoint, "BOTTOMRIGHT")
	eq("button x persists", live.button.x, 12)
	eq("button y persists", live.button.y, -8)
	eq("button scale clamps", live.button.scale, 2.0)
	Profile.renameRotation(rotation, "Renamed")
	eq("renamed active rotation remains active", live.active, "Renamed")
end

-- ---------------------------------------------------------------------------
-- Config tree structure tests
-- ---------------------------------------------------------------------------

do
	prof().rotations = {
		{ name = "Single", rules = { { name = "", spell = "Fireball", enabled = true, unit = "target", conditions = {} } } },
		{ name = "AoE", rules = {} },
	}
	prof().active = "Single"

	local opts = Config.BuildOptions()
	local rotGroup = opts.args.rotations

	ok("rotations is a group", rotGroup.type == "group")
	ok("rotations is a tree", rotGroup.childGroups == "tree")
	ok("rotationKey builds the option key", Config.rotationKey(3) == "rotation3")
	ok("rotationIndexFromKey parses the key", Config.rotationIndexFromKey("rotation2") == 2)
	ok("rotationIndexFromKey rejects a non-key", Config.rotationIndexFromKey("rotationPanel") == nil)
	ok("rotation1 present", rotGroup.args.rotation1 ~= nil)
	ok("rotation2 present", rotGroup.args.rotation2 ~= nil)
	ok("no rot3", rotGroup.args.rot3 == nil)
	ok("active rotation marked", rotGroup.args.rotation1.name() == "Single (Active)")
	ok("inactive rotation plain", rotGroup.args.rotation2.name() == "AoE")
	ok("rotation has no icon", rotGroup.args.rotation1.icon == nil)

	-- rotation content: a RotationSettings control for name/buttons, then a
	-- RotationRules control that renders the rule cards.
	ok("rotation has settings control", rotGroup.args.rotation1.args.settings ~= nil)
	ok("settings is RotationSettings", rotGroup.args.rotation1.args.settings.control == "RotationSettings")
	local panelOption = rotGroup.args.rotation1.args.rotationRules
	ok("rotation rules option present", panelOption ~= nil)
	ok("panel is the custom widget", panelOption.control == "RotationRules")
	ok("panel is an execute leaf", panelOption.type == "execute")
	ok("panel option has no custom fields", panelOption.rotation == nil and panelOption.func == nil)
	ok("no declarative rules group", rotGroup.args.rotation1.args.rules == nil)
	ok("no rule cards in the tree", rotGroup.args.rotation1.args.rule1 == nil)

	-- each rotation gets its own panel bound to its own rotation
	local panelTwo = rotGroup.args.rotation2.args.rotationRules
	ok("rotation2 panel present", panelTwo ~= nil and panelTwo.control == "RotationRules")

	-- general options live on the Rotations page, above its sub-tree
	ok("no root general options", opts.args.auto == nil and opts.args.general == nil)
	ok("rotation main settings control", rotGroup.args.rotationMainSettings ~= nil)
	ok("rotation main is RotationMainSettings", rotGroup.args.rotationMainSettings.control == "RotationMainSettings")
	ok("button group present", opts.args.button ~= nil and opts.args.button.type == "group")
	ok("button is ButtonSettings", opts.args.button.args.buttonSettings ~= nil and opts.args.button.args.buttonSettings.control == "ButtonSettings")
	ok("log group present", opts.args.log ~= nil and opts.args.log.type == "group")
	ok("log is Log", opts.args.log.args.logPanel ~= nil and opts.args.log.args.logPanel.control == "Log")

	-- Config.Open marks the Rotations tree node expanded before showing
	_G.__dialogStatus = {}
	Config.Open()
	ok("Rotations tree starts expanded", _G.__dialogStatus.groups ~= nil and _G.__dialogStatus.groups.rotations == true)

	-- settings is now a RotationSettings control (the button layout lives
	-- inside the widget, not in the AceConfig args tree). Actions are tested
	-- via direct Profile calls since the widget is not loaded in the harness.
	ok("settings is RotationSettings", rotGroup.args.rotation1.args.settings.control == "RotationSettings")
	ok("settings is execute leaf", rotGroup.args.rotation1.args.settings.type == "execute")

	-- actions mutate the profile; test via Profile directly
	local single = prof().rotations[1]
	Profile.setActive(single)
	eq("setActive via Profile", prof().active, "Single")
	Profile.duplicateRotation(single)
	eq("duplicate via Profile", #prof().rotations, 3)
	Profile.deleteRotation(prof().rotations[3])
	eq("delete via Profile", #prof().rotations, 2)
	rotGroup = Config.BuildOptions().args.rotations
	ok("panel rebuilt after rotation change", rotGroup.args.rotation1.args.rotationRules ~= nil)
end

-- ---------------------------------------------------------------------------
-- condition CRUD tests
-- ---------------------------------------------------------------------------

do
	local rotation = { name = "R", rules = { { name = "", spell = "Fireball", enabled = true, unit = "target", conditions = {} } } }
	Profile.addCondition(rotation.rules[1])
	eq("addCondition appends default", #rotation.rules[1].conditions, 1)
	eq("addCondition default type", rotation.rules[1].conditions[1].type, "unit_exists")
	eq("addCondition default value (unset)", rotation.rules[1].conditions[1].value, nil)

	Profile.addCondition(rotation.rules[1])
	eq("addCondition appends second", #rotation.rules[1].conditions, 2)
	Profile.deleteCondition(rotation.rules[1], 1)
	eq("deleteCondition removes first", #rotation.rules[1].conditions, 1)
	eq("deleteCondition keeps second", rotation.rules[1].conditions[1].type, "unit_exists")
	Profile.deleteCondition(rotation.rules[1], 1)
	eq("deleteCondition empties", #rotation.rules[1].conditions, 0)
end

-- ---------------------------------------------------------------------------
-- Log tests
-- ---------------------------------------------------------------------------

do
	Log.Clear()
	eq("log starts empty", Log.Count(), 0)

	state.time = 100
	Log.Write("test", "first")
	Log.Write("test", "second")
	eq("log counts entries", Log.Count(), 2)

	local lines = Log.Dump(1)
	eq("dump returns newest first", lines[1], "[100] test: second")
	eq("dump limited to n", #lines, 1)

	-- persist to a profile table (simulating Attach)
	local profile = { log = {} }
	Log.Attach(profile)
	Log.Clear()
	Log.Write("attach", "persisted")
	eq("attach writes through to profile", profile.log[1].message, "persisted")
	-- Clear must persist too, or the cleared ring comes back on the next save
	Log.Clear()
	eq("clear persists the empty ring", #profile.log, 0)

	-- cap: writing MAX_ENTRIES+1 drops the oldest
	Log.Clear()
	for i = 1, 205 do
		Log.Write("flood", tostring(i))
	end
	eq("ring caps at 200", Log.Count(), 200)
	local dump = Log.Dump(1)
	ok("ring keeps the newest", dump[1]:find("205") ~= nil)

	Log.Clear()
end

-- ---------------------------------------------------------------------------
-- summary
-- ---------------------------------------------------------------------------

print(("passed %d, failed %d"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
