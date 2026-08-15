-- Test harness for the Accessibility addon. Run with: lua5.1 tests/run.lua
--
-- It loads the pure-Lua modules with a fake WoW API and a fake Compatibility
-- global, then runs assertions against the observable contracts. Core, Button
-- and Config are not loaded: they need Ace3 and frames, which this harness
-- does not provide.

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

local function setUnit(id, t) state.units[id] = t end
local function setSpell(name, t) state.spells[name] = t end
local function setKnown(names)
	state.knownSpells = {}
	for i = 1, #names do state.knownSpells[i] = names[i] end
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
fake.GetSpellInfo = function() return "spell", "", "Interface\\Icons\\TEMP" end
fake.GetSpellTexture = function() return "Interface\\Icons\\TEMP" end
fake.GetNumSpellTabs = function() return 0 end
fake.GetSpellTabInfo = function() return "General", "", 0, 0 end
fake.GetSpellName = function() return nil end

local function clearScripts()
	for i = #scripts, 1, -1 do scripts[i] = nil end
end

fake.GetTime = function() return state.time end
fake.UnitExists = function(u) local x = state.units[u]; return x and x.exists end
fake.UnitIsDeadOrGhost = function(u) local x = state.units[u]; return x and x.dead end
fake.UnitHealth = function(u) local x = state.units[u]; return x and x.health or 0 end
fake.UnitHealthMax = function(u) local x = state.units[u]; return x and x.maxHealth or 0 end
fake.UnitPower = function(u) local x = state.units[u]; return x and x.power or 0 end
fake.UnitPowerMax = function(u) local x = state.units[u]; return x and x.maxPower or 0 end
fake.UnitCanAttack = function(_, u) local x = state.units[u]; return x and x.hostile end
-- UnitCastingInfo/UnitChannelInfo return (name, _, _, startMs, endMs, ...).
-- The unit table may set castingEndMs / channelEndMs to simulate a cast.
fake.UnitCastingInfo = function(u)
	local x = state.units[u]
	if x and x.castingEndMs then return "Cast", "", "", 0, x.castingEndMs end
	return nil
end
fake.UnitChannelInfo = function(u)
	local x = state.units[u]
	if x and x.channelEndMs then return "Channel", "", "", 0, x.channelEndMs end
	return nil
end
fake.UnitAffectingCombat = function() return state.inCombat end
fake.GetUnitSpeed = function(u) local x = state.units[u]; return x and x.speed or 0 end
fake.IsUsableSpell = function(s) local x = state.spells[s]; if x then return x.usable, x.noMana end end
fake.GetSpellCooldown = function(s) local x = state.spells[s]; if x then return x.cdStart, x.cdDuration end; return 0, 0 end
fake.IsSpellInRange = function(s) local x = state.spells[s]; if x then return x.inRange end end
fake.GetSpellTexture = function() return "Interface\\Icons\\TEMP" end
-- GetSpellInfo returns (name, rank, icon, powerCost, ...) in this client.
-- The spell table may set castMs to simulate a cast-time spell (used by the
-- engine's anti-spam gate, which reads the 4th return).
fake.GetSpellInfo = function(id)
	local x = type(id) == "string" and state.spells[id] or nil
	local castMs = x and x.castMs or 0
	if id == 8921 then return "Moonfire", "", "Interface\\Icons\\TEMP", castMs end
	return "spell", "", "Interface\\Icons\\TEMP", castMs
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
fake.UnitName = function() return "TestMage" end

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

local ns = {}
-- Resolve the addon root from the script path, so the runner works from the
-- addon root or one directory above it.
local script = arg and arg[0] or "tests/run.lua"
local dir = script:match("^(.*)[/\\]") or "."
local ROOT = dir .. "/../"

loadModule(ROOT .. "Utils/Constants.lua", ns)
loadModule(ROOT .. "Utils/Compare.lua", ns)
loadModule(ROOT .. "Utils/Coerce.lua", ns)
loadModule(ROOT .. "Utils/Log.lua", ns)
loadModule(ROOT .. "Utils/SpellTooltip.lua", ns)
loadModule(ROOT .. "Game/Unit.lua", ns)
loadModule(ROOT .. "Game/Aura.lua", ns)
loadModule(ROOT .. "Game/Cast.lua", ns)
loadModule(ROOT .. "Core/Compatibility.lua", ns)
loadModule(ROOT .. "Core/Profile.lua", ns)
loadModule(ROOT .. "Game/SpellPicker.lua", ns)
loadModule(ROOT .. "Core/Conditions.lua", ns)
loadModule(ROOT .. "Core/Rotation.lua", ns)

ns.addon = { db = { profile = {} } }   -- Accessibility.lua (the entry) is not loaded; provide the db stub
ns.RotationButton = { ApplyPosition = function() end }   -- Config's button settings call it
_G.__dialogStatus = {}   -- the AceConfigDialog:GetStatusTable stub returns this

loadModule(ROOT .. "Core/Config.lua", ns)

local Compatibility = ns.Compatibility
local Profile = ns.Profile
local SpellPicker = ns.SpellPicker
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
	Compatibility.Call("return CastSpellByID(%d)", 8921)
	eq("number passes through", scripts[1], "return CastSpellByID(8921)")
end

-- self-cast uses the player unit
do
	clearScripts()
	Compatibility.Cast("Renew", nil, true)
	eq("self cast template", scripts[1], 'return CastSpellByName("Renew", "player")')
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

	-- Link resolution: stored ID wins; a name resolves via GetSpellLink;
	-- no usable spell returns nil
	setSpell("Fireball", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1, testLink = "spell:133" })
	eq("Link from name", SpellPicker.Link({ spell = "Fireball" }), "spell:133")
	eq("Link stored ID wins", SpellPicker.Link({ spell = "Fireball", spellID = 999 }), "spell:999")
	eq("Link nil without spell", SpellPicker.Link({}), nil)
	eq("Link nil with empty name", SpellPicker.Link({ spell = "" }), nil)

	-- clean up so rotation tests rebuild the spellbook fresh
	state.knownSpells = {}
	state.passiveSpells = {}
end

-- ---------------------------------------------------------------------------
-- SpellTooltip tests
-- ---------------------------------------------------------------------------

do
	-- Attach wires OnEnter/OnLeave on a frame; hovering with a rule shows the
	-- spell link, without a rule nothing shows, leaving hides.
	local tooltip = { owner = nil, link = nil, shown = 0, hidden = 0 }
	fake.GameTooltip = {
		SetOwner = function(self, owner, anchor) tooltip.owner = owner; tooltip.anchor = anchor end,
		SetHyperlink = function(self, link) tooltip.link = link end,
		Show = function() tooltip.shown = tooltip.shown + 1 end,
		Hide = function() tooltip.hidden = tooltip.hidden + 1 end,
	}

	local frame = {
		scripts = {},
		EnableMouse = function(self, enabled) self.mouseEnabled = enabled end,
		SetScript = function(self, name, fn) self.scripts[name] = fn end,
	}
	local SpellTooltip = ns.SpellTooltip
	ok("SpellTooltip exported", type(SpellTooltip.Attach) == "function")

	local frameRule = { spell = "Fireball" }
	SpellTooltip.Attach(frame, function() return frameRule end, "ANCHOR_CURSOR")
	ok("mouse enabled", frame.mouseEnabled == true)
	ok("OnEnter wired", frame.scripts.OnEnter ~= nil)
	ok("OnLeave wired", frame.scripts.OnLeave ~= nil)

	frame.scripts.OnEnter(frame)
	eq("tooltip shows link", tooltip.link, "spell:133")
	eq("tooltip shown once", tooltip.shown, 1)
	eq("tooltip anchors at cursor", tooltip.anchor, "ANCHOR_CURSOR")

	frameRule = nil
	frame.scripts.OnEnter(frame)
	eq("no link without rule", tooltip.link, "spell:133")   -- unchanged
	eq("tooltip not re-shown", tooltip.shown, 1)

	frame.scripts.OnLeave(frame)
	eq("tooltip hidden on leave", tooltip.hidden, 1)

	fake.GameTooltip = nil
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
		{ spell = "Fireball", enabled = false, unit = "banana", spellID = "42", conditions = { { type = "target_type", value = "enemy" }, { type = "nope" } } },
			{ spell = "", enabled = true },
			"garbage",
			{ spell = "Renew", spellID = -3 },
		},
		button = { scale = 99, x = "0", locked = 1 },
	}
	Profile.sanitizeProfile(p)

	eq("auto coerced", p.auto, false)
	eq("pulseInterval clamped", p.pulseInterval, 0.05)
	eq("gcdProbeSpell coerced", p.gcdProbeSpell, "")
	eq("queueWindow defaulted", p.queueWindow, 0.4)
	eq("legacy rules migrated to one rotation", #p.rotations, 1)
	eq("migrated rotation named Default", p.rotations[1].name, "Default")
	eq("active set to Default", p.active, "Default")
	eq("legacy rules field removed", p.rules, nil)
	local rules = p.rotations[1].rules
	eq("rules length", #rules, 2)

	local r1 = rules[1]
	eq("rule spell kept", r1.spell, "Fireball")
	eq("rule enabled coerced", r1.enabled, false)
	eq("rule unit defaulted", r1.unit, "target")
	eq("rule spellID coerced", r1.spellID, 42)
	eq("condition count (unknown dropped)", #r1.conditions, 1)
	eq("condition type kept", r1.conditions[1].type, "target_type")

	eq("second rule spellID dropped (negative)", rules[2].spellID, nil)
	eq("button scale clamped", p.button.scale, 2.0)
	eq("button locked coerced", p.button.locked, false)
	eq("button enabled defaulted", p.button.enabled, true)
end

-- ---------------------------------------------------------------------------
-- Conditions tests
-- ---------------------------------------------------------------------------

do
	ok("Eval unknown type fails closed", Conditions.Eval({ type = "nope" }) == false)
	ok("Eval non-table fails closed", Conditions.Eval("x") == false)

	-- target_type enemy
	setUnit("target", { exists = true, dead = false, hostile = true })
	ok("target_type enemy passes on hostile", Conditions.Eval({ type = "target_type", value = "enemy", unit = "target" }) == true)
	ok("target_type friendly fails on hostile", Conditions.Eval({ type = "target_type", value = "friendly", unit = "target" }) == false)

	-- health_percent
	setUnit("target", { exists = true, dead = false, health = 30, maxHealth = 100, hostile = true })
	ok("health_percent < 50 passes", Conditions.Eval({ type = "health_percent", unit = "target", op = "<", value = 50 }) == true)
	ok("health_percent > 50 fails", Conditions.Eval({ type = "health_percent", unit = "target", op = ">", value = 50 }) == false)

	-- in_combat
	state.inCombat = true
	ok("in_combat passes in combat", Conditions.Eval({ type = "in_combat" }) == true)
	state.inCombat = false
	ok("in_combat fails out of combat", Conditions.Eval({ type = "in_combat" }) == false)

	-- aura_missing / aura_present
	state.auras.target = {}
	ok("aura_missing passes with no aura", Conditions.Eval({ type = "aura_missing", unit = "target", aura = "Moonfire", kind = "debuff", mine = true }) == true)
	state.auras.target = { { kind = "debuff", name = "Moonfire", count = 1, remaining = 10, mine = true } }
	ok("aura_present passes with the aura", Conditions.Eval({ type = "aura_present", unit = "target", aura = "Moonfire", kind = "debuff" }) == true)
	ok("aura_missing fails with the aura", Conditions.Eval({ type = "aura_missing", unit = "target", aura = "Moonfire", kind = "debuff", mine = true }) == false)

	-- bug fix: the game reports the player's own auras with the character
	-- name as caster; mineOnly must still count that as ours
	state.auras.target = { { kind = "debuff", name = "Moonfire", count = 1, remaining = 10, mine = true, casterName = true } }
	ok("mineOnly accepts caster as name", Conditions.Eval({ type = "aura_missing", unit = "target", aura = "Moonfire", kind = "debuff", mine = true }) == false)

	-- bug fix: a permanent aura (no expiry) reports 0 remaining; that is
	-- PRESENT, not missing
	state.auras.target = { { kind = "buff", name = "Frost Armor", count = 1, remaining = nil, mine = true } }
	ok("permanent aura present (0 remaining)", Conditions.Eval({ type = "aura_present", unit = "target", aura = "Frost Armor", kind = "buff" }) == true)
	ok("permanent aura not missing", Conditions.Eval({ type = "aura_missing", unit = "target", aura = "Frost Armor", kind = "buff" }) == false)

	-- a stranger's copy still does not satisfy mineOnly
	state.auras.target = { { kind = "debuff", name = "Moonfire", count = 1, remaining = 10, mine = false } }
	ok("stranger dot not mine", Conditions.Eval({ type = "aura_missing", unit = "target", aura = "Moonfire", kind = "debuff", mine = true }) == true)

	-- bug fix: 3.3.5a reports auras with a rank suffix; the plain name must
	-- still match, so "Aura missing" is false while the aura is up
	state.auras.target = { { kind = "debuff", name = "Moonfire (Rank 2)", count = 1, remaining = 10, mine = true } }
	ok("ranked aura matches plain name (present)", Conditions.Eval({ type = "aura_present", unit = "target", aura = "Moonfire", kind = "debuff" }) == true)
	ok("ranked aura not missing", Conditions.Eval({ type = "aura_missing", unit = "target", aura = "Moonfire", kind = "debuff" }) == false)
	-- and the reverse: a configured name with the rank matches a plain report
	state.auras.target = { { kind = "debuff", name = "Moonfire", count = 1, remaining = 10, mine = true } }
	ok("plain aura matches ranked name", Conditions.Eval({ type = "aura_missing", unit = "target", aura = "Moonfire (Rank 2)", kind = "debuff" }) == false)

	-- spell_ready GCD trick
	setSpell("Fireball", { cdStart = 10, cdDuration = 1.5 })
	state.time = 10.5
	ok("spell_ready treats 1.5s as the GCD (ready)", Conditions.Eval({ type = "spell_ready", spell = "Fireball" }) == true)

	-- describe returns a string for a known type
	ok("Describe returns a string", type(Conditions.Describe({ type = "in_combat" })) == "string")

	-- the "Aura is not up" condition was renamed to "Aura missing"
	eq("aura_missing label renamed", Conditions.Registry.aura_missing.label, "Aura missing")

	-- sanitize drops unknown fields
	local clean = Conditions.Sanitize({ type = "health_percent", unit = "target", op = "<", value = 30, junk = "x" })
	ok("Sanitize keeps declared fields", clean ~= nil and clean.unit == "target" and clean.op == "<" and clean.value == 30)
	ok("Sanitize drops unknown fields", clean ~= nil and clean.junk == nil)
	ok("Sanitize drops unknown type", Conditions.Sanitize({ type = "nope" }) == nil)

	-- legacy type keys from before the rename migrate on sanitize
	local legacy = Conditions.Sanitize({ type = "health_pct", unit = "target", op = "<", value = 40 })
	ok("legacy health_pct migrates", legacy ~= nil and legacy.type == "health_percent" and legacy.value == 40)
	local legacyPower = Conditions.Sanitize({ type = "power_pct", unit = "player", op = ">", value = 60 })
	ok("legacy power_pct migrates", legacyPower ~= nil and legacyPower.type == "power_percent" and legacyPower.value == 60)

	-- legacy keys also evaluate without a sanitize pass (fresh rotation data)
	setUnit("target", { exists = true, dead = false, health = 30, maxHealth = 100, hostile = true })
	ok("legacy health_pct evals", Conditions.Eval({ type = "health_pct", unit = "target", op = "<", value = 50 }) == true)
	ok("ResolveType maps legacy key", Conditions.ResolveType("health_pct") == "health_percent")
	ok("ResolveType passes current key", Conditions.ResolveType("health_percent") == "health_percent")
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
	state.inCombat = false
	setKnown({ "Fireball", "Renew", "probe" })
	setSpell("Fireball", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1 })
	setSpell("Renew", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1 })
	setSpell("probe", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1 })
	setUnit("player", { exists = true, dead = false })
	setUnit("target", { exists = true, dead = false, hostile = true, health = 100, maxHealth = 100 })
	setRules({ { name = "", spell = "Fireball", spellID = nil, enabled = true, unit = "target", conditions = {} } })
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
ok("a cast script was emitted", #scripts == 1 and scripts[1] == 'return CastSpellByName("Fireball")')

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

	rules()[1].conditions = { { type = "in_combat" } }
state.inCombat = false
ok("failing condition blocks the cast", Rotation.CastBest() == false)

-- anti-spam: cast, then advance past the GCD but inside the 2.5s window
resetRotation()
local t0 = state.time
ok("first cast succeeds", Rotation.CastBest() == true)
state.time = t0 + 2
ok("anti-spam blocks a fast re-cast", Rotation.CastBest() == false)
state.time = t0 + 3
ok("cast succeeds after the anti-spam window", Rotation.CastBest() == true)

-- priority walk: a blocked first rule must yield to the next
resetRotation()
setRules({
	{ spell = "Blocked", spellID = nil, enabled = true, unit = "target", conditions = { { type = "in_combat" } } },
	{ spell = "Fireball", spellID = nil, enabled = true, unit = "target", conditions = {} },
})
state.inCombat = false
clearScripts()
ok("walk skips a blocked rule", Rotation.CastBest() == true)
ok("walk cast the second rule", scripts[1] == 'return CastSpellByName("Fireball")')

-- priority walk: the first passing rule wins, the walk stops
resetRotation()
setRules({
	{ spell = "Fireball", spellID = nil, enabled = true, unit = "target", conditions = {} },
	{ spell = "Renew", spellID = nil, enabled = true, unit = "target", conditions = {} },
})
clearScripts()
ok("walk casts the first passing rule", Rotation.CastBest() == true)
eq("only one cast was emitted", #scripts, 1)
ok("the first rule won", scripts[1] == 'return CastSpellByName("Fireball")')

-- NextRule: the button icon must show the first PASSING rule, so a blocked
-- first rule does not pin a stale icon
resetRotation()
setRules({
	{ spell = "Blocked", spellID = nil, enabled = true, unit = "target", conditions = { { type = "in_combat" } } },
	{ spell = "Fireball", spellID = nil, enabled = true, unit = "target", conditions = {} },
})
state.inCombat = false
ok("NextRule skips a blocked rule", Rotation.NextRule() ~= nil)
ok("NextRule returns the passing rule", Rotation.NextRule().spell == "Fireball")

resetRotation()
setRules({
	{ spell = "Fireball", spellID = nil, enabled = true, unit = "target", conditions = { { type = "in_combat" } } },
	{ spell = "Renew", spellID = nil, enabled = true, unit = "target", conditions = { { type = "in_combat" } } },
})
state.inCombat = false
ok("NextRule nil when every rule blocked", Rotation.NextRule() == nil)

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
eq("queue-window cast emitted", scripts[1], 'return CastSpellByName("Fireball")')

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
-- (the cast itself is the spacer, and the 2.5s window would break the queue)
resetRotation()
setSpell("Fireball", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1, castMs = 2000 })
local tq = state.time
ok("cast-time spell first cast succeeds", Rotation.CastBest() == true)
-- 1.6s into a 2s cast: inside the 0.4s queue window, past the GCD fallback
state.time = tq + 1.6
setUnit("player", { exists = true, dead = false, castingEndMs = (tq + 2.0) * 1000 })
clearScripts()
ok("cast-time spell re-queues inside window (anti-spam bypassed)", Rotation.CastBest() == true)
eq("re-queue emitted the same spell", scripts[1], 'return CastSpellByName("Fireball")')

-- an instant spell is still anti-spammed: 1.6s after casting it, blocked
resetRotation()
setSpell("Fireball", { usable = true, noMana = false, cdStart = 0, cdDuration = 0, inRange = 1 })  -- instant
local ti = state.time
ok("instant spell first cast succeeds", Rotation.CastBest() == true)
state.time = ti + 1.6
ok("instant spell still anti-spammed", Rotation.CastBest() == false)
state.time = ti + 3
ok("instant spell casts again after the window", Rotation.CastBest() == true)

-- aura condition accepts a numeric spell ID in the aura field
state.auras.target = {}
ok("aura missing resolves by name", Conditions.Eval({ type = "aura_missing", unit = "target", aura = "Moonfire", kind = "debuff" }) == true)
state.auras.target = { { kind = "debuff", name = "Moonfire (Rank 2)", count = 1, remaining = 10, mine = true } }
ok("aura field accepts spell ID", Conditions.Eval({ type = "aura_missing", unit = "target", aura = 8921, kind = "debuff" }) == false)

-- ---------------------------------------------------------------------------
-- Rotation management tests
-- ---------------------------------------------------------------------------

do
	-- start from a clean profile with the new schema
	prof().rotations = { { name = "Single", rules = { { spell = "Fireball", spellID = nil, enabled = true, unit = "target", conditions = {} } } } }
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
	local rotation = { name = "R", rules = { { spell = "One", spellID = nil, enabled = true, unit = "target", conditions = {} }, { spell = "Two", spellID = nil, enabled = true, unit = "target", conditions = {} }, { spell = "Three", spellID = nil, enabled = true, unit = "target", conditions = {} } } }
	Profile.moveRule(rotation, 1, 3)
	eq("moveRule reorders", rotation.rules[3].spell, "One")
	eq("moveRule shifts middle", rotation.rules[1].spell, "Two")
	ok("moveRule clamps low", (function() Profile.moveRule(rotation, 1, 0); return rotation.rules[1].spell == "Two" end)())
	ok("moveRule clamps high", (function() Profile.moveRule(rotation, 1, 99); return rotation.rules[3].spell == "One" end)())
end

-- ---------------------------------------------------------------------------
-- Config tree structure tests
-- ---------------------------------------------------------------------------

do
	prof().rotations = {
		{ name = "Single", rules = { { name = "", spell = "Fireball", spellID = nil, enabled = true, unit = "target", conditions = {} } } },
		{ name = "AoE", rules = {} },
	}
	prof().active = "Single"

	local opts = Config.BuildOptions()
	local rotGroup = opts.args.rotations

	ok("rotations is a group", rotGroup.type == "group")
	ok("rotations is a tree", rotGroup.childGroups == "tree")
	ok("newRotation present", rotGroup.args.newRotation ~= nil)
	ok("rotation1 present", rotGroup.args.rotation1 ~= nil)
	ok("rotation2 present", rotGroup.args.rotation2 ~= nil)
	ok("no rot3", rotGroup.args.rot3 == nil)
	ok("active rotation marked", rotGroup.args.rotation1.name() == "Single (Active)")
	ok("inactive rotation plain", rotGroup.args.rotation2.name() == "AoE")
	ok("rotation has no icon", rotGroup.args.rotation1.icon == nil)

	-- rotation content: a settings section, then the RotationPanel widget
	-- that renders the rule cards (the declarative rule/condition groups are
	-- gone; the panel is one execute leaf carrying the rotation reference)
	ok("rotation has settings section", rotGroup.args.rotation1.args.settings ~= nil)
	ok("settings section inline", rotGroup.args.rotation1.args.settings.inline == true)
	local panelOption = rotGroup.args.rotation1.args.rotationPanel
	ok("rotation panel option present", panelOption ~= nil)
	ok("panel is the custom widget", panelOption.control == "RotationPanel")
	ok("panel is an execute leaf", panelOption.type == "execute")
	ok("panel option has no custom fields", panelOption.rotation == nil and panelOption.func == nil)
	ok("no declarative rules group", rotGroup.args.rotation1.args.rules == nil)
	ok("no rule cards in the tree", rotGroup.args.rotation1.args.rule1 == nil)

	-- each rotation gets its own panel bound to its own rotation
	local panelTwo = rotGroup.args.rotation2.args.rotationPanel
	ok("rotation2 panel present", panelTwo ~= nil and panelTwo.control == "RotationPanel")

	-- general options live on the Rotations page, above its sub-tree
	ok("no root general options", opts.args.auto == nil and opts.args.general == nil)
	ok("active rotation dropdown", rotGroup.args.activeRotation ~= nil)
	ok("auto on rotations page", rotGroup.args.auto ~= nil)
	ok("pulseInterval on rotations page", rotGroup.args.pulseInterval ~= nil)
	ok("gcdProbeSpell on rotations page", rotGroup.args.gcdProbeSpell ~= nil)
	ok("queueWindow on rotations page", rotGroup.args.queueWindow ~= nil)
	ok("button group present", opts.args.button ~= nil)
	-- the Log section shows the debug ring
	ok("log group present", opts.args.log ~= nil)
	ok("log group is a tree node", opts.args.log.type == "group")
	ok("log has refresh/clear", opts.args.log.args.refresh ~= nil and opts.args.log.args.clear ~= nil)
	ok("log description is a function", type(opts.args.log.args.output.name) == "function")

	-- Config.Open marks the Rotations tree node expanded before showing
	_G.__dialogStatus = {}
	Config.Open()
	ok("Rotations tree starts expanded", _G.__dialogStatus.groups ~= nil and _G.__dialogStatus.groups.rotations == true)

	-- rotation settings layout: rename first, then the three action buttons
	local s = rotGroup.args.rotation1.args.settings.args
	ok("rename is first", s.rename.order == 1)
	ok("setActive second", s.setActive.order == 2)
	ok("duplicate third", s.duplicate.order == 3)
	ok("delete fourth", s.delete.order == 4)

	-- actions mutate the profile; rebuild to get fresh closures (the tree is
	-- rebuilt by NotifyChange in game, so stale closures never run)
	rotGroup.args.rotation1.args.settings.args.setActive.func()
	eq("setActive via tree", prof().active, "Single")
	rotGroup.args.rotation1.args.settings.args.duplicate.func()
	eq("duplicate via tree", #prof().rotations, 3)
	rotGroup = Config.BuildOptions().args.rotations
	rotGroup.args.rotation2.args.settings.args.delete.func()
	eq("delete via tree", #prof().rotations, 2)
	rotGroup = Config.BuildOptions().args.rotations
	ok("panel rebuilt after rotation change", rotGroup.args.rotation1.args.rotationPanel ~= nil)
end

-- ---------------------------------------------------------------------------
-- condition CRUD tests
-- ---------------------------------------------------------------------------

do
	local rotation = { name = "R", rules = { { name = "", spell = "Fireball", spellID = nil, enabled = true, unit = "target", conditions = {} } } }
	Profile.addCondition(rotation.rules[1])
	eq("addCondition appends default", #rotation.rules[1].conditions, 1)
	eq("addCondition default type", rotation.rules[1].conditions[1].type, "target_type")
	eq("addCondition default value", rotation.rules[1].conditions[1].value, "enemy")

	Profile.addCondition(rotation.rules[1])
	eq("addCondition appends second", #rotation.rules[1].conditions, 2)
	Profile.deleteCondition(rotation.rules[1], 1)
	eq("deleteCondition removes first", #rotation.rules[1].conditions, 1)
	eq("deleteCondition keeps second", rotation.rules[1].conditions[1].type, "target_type")
	Profile.deleteCondition(rotation.rules[1], 1)
	eq("deleteCondition empties", #rotation.rules[1].conditions, 0)
end

-- ---------------------------------------------------------------------------
-- TitleButtonGroup widget tests
-- ---------------------------------------------------------------------------

do
	-- TitleButtonGroup is a reusable container with title-bar buttons: it
	-- must register, install buttons right-to-left, show them (AceGUI buttons
	-- start hidden), and release them on release.
	local created = {}
	local releasedButtons = 0
	local fakeAce = {
		RegisterWidgetType = function(self, name, ctor, ver) created[name] = ctor end,
		GetWidgetVersion = function() return nil end,
		Release = function(self, widget)
			if widget.type == "Button" then releasedButtons = releasedButtons + 1 end
			if widget.OnRelease then widget:OnRelease() end
		end,
		RegisterAsContainer = function(self, widget)
			widget.children = widget.children or {}
			widget.userdata = widget.userdata or {}
			widget.SetWidth = function() end
			widget.SetHeight = function() end
			widget.SetFullWidth = function() end
			widget.AddChild = function(self, child) self.children[#self.children + 1] = child end
			widget.SetUserData = function(self, k, v) self.userdata[k] = v end
			widget.GetUserData = function(self, k) return self.userdata[k] end
			widget.GetUserDataTable = function(self) return self.userdata end
			return widget
		end,
	}
	local widgetEnv = setmetatable({}, { __index = _G })
	widgetEnv.LibStub = function(name)
		if name == "AceGUI-3.0" then return fakeAce end
		return nil
	end
	local shown = 0
	widgetEnv.CreateFrame = function()
		local frame = { SetFrameStrata = function() end,
			CreateFontString = function() return { SetPoint = function() end, SetJustifyH = function() end, SetHeight = function() end, SetText = function() end } end,
			SetPoint = function() end, SetBackdrop = function() end, SetBackdropColor = function() end, SetBackdropBorderColor = function() end,
			Hide = function(self) self.hidden = true end,
			Show = function(self) self.hidden = false; shown = shown + 1 end,
			EnableMouse = function() end, SetHeight = function() end,
			SetScript = function() end,
			GetFrameLevel = function() return 1 end }
		return frame
	end
	widgetEnv.UIParent = {}

	-- the constructor creates Button children via AceGUI:Create; provide it
	fakeAce.Create = function(self, type)
		local w = { type = type, children = {}, userdata = {}, events = {},
			frame = { SetParent = function() end, SetPoint = function() end, GetWidth = function() return 10 end,
				GetHeight = function() end, ClearAllPoints = function() end, SetFrameLevel = function() end,
				SetHeight = function() end, Show = function() shown = shown + 1 end, Hide = function() end,
				GetFrameLevel = function() return 1 end },
			SetText = function() end, SetAutoWidth = function() end, SetHeight = function() end,
			SetDisabled = function(self, v) self.disabled = v end,
			SetCallback = function(self, name, fn) self.events[name] = fn end,
		}
		return w
	end

	local loadChunk = assert(loadfile(ROOT .. "UI/Widgets/TitleButtonGroup.lua"))
	setfenv(loadChunk, widgetEnv)
	loadChunk("Accessibility", ns)

	ok("TitleButtonGroup registered", created.TitleButtonGroup ~= nil)
	local section = created.TitleButtonGroup()
	section:OnAcquire()
	local clicked = 0
	section:SetTitleButtons({
		{ label = "A", func = function() clicked = clicked + 1 end },
		{ label = "B", disabled = true, func = function() end },
	})
	ok("title buttons installed", section.titleButtons ~= nil and #section.titleButtons == 2)
	ok("buttons were shown", shown >= 2)
	ok("first button enabled", section.titleButtons[1].disabled ~= true)
	ok("second button disabled", section.titleButtons[2].disabled == true)
	section.titleButtons[1].events.OnClick(section.titleButtons[1])
	eq("button OnClick fires", clicked, 1)
	releasedButtons = 0
	section:OnRelease()
	eq("OnRelease releases title buttons", releasedButtons, 2)

	-- a widget released with its border hidden (collapsed condition card)
	-- must come back border-visible when re-acquired from the pool
	section:SetBorderVisible(false)
	ok("border hidden when collapsed", section.border.hidden == true)
	section:OnAcquire()
	ok("border shown on re-acquire", section.border.hidden == false)
	ok("borderVisible reset on re-acquire", section.borderVisible == true)
end

-- ---------------------------------------------------------------------------
-- RotationPanel widget tests
-- ---------------------------------------------------------------------------

do
	-- PanelRotation resolves the panel's rotation from the option path
	-- AceConfig stores in userdata. Load the widget in a fake-AceGUI env and
	-- drive the resolution method directly.
	local created = {}
	local fakeAce = {
		RegisterWidgetType = function(self, name, ctor, ver) created[name] = ctor end,
		GetWidgetVersion = function() return nil end,
		RegisterAsContainer = function(self, widget)
			widget.userdata = widget.userdata or {}
			widget.SetUserData = function(self, k, v) self.userdata[k] = v end
			widget.GetUserData = function(self, k) return self.userdata[k] end
			widget.GetUserDataTable = function(self) return self.userdata end
			return widget
		end,
	}
	local widgetEnv = setmetatable({}, { __index = _G })
	widgetEnv.LibStub = function(name)
		if name == "AceGUI-3.0" then return fakeAce end
		return nil
	end
	widgetEnv.CreateFrame = function()
		return { SetFrameStrata = function() end,
			CreateFontString = function() return { SetPoint = function() end, SetJustifyH = function() end, SetHeight = function() end, SetText = function() end } end,
			SetPoint = function() end, SetBackdrop = function() end, SetBackdropColor = function() end, SetBackdropBorderColor = function() end,
			SetScript = function() end, Hide = function() end, Show = function() end,
			EnableMouse = function() end, SetHeight = function() end }
	end
	widgetEnv.UIParent = {}

	local rotationList = {
		{ name = "Single", rules = {} },
		{ name = "AoE", rules = {} },
	}
	local loadChunk = assert(loadfile(ROOT .. "UI/RotationPanel.lua"))
	setfenv(loadChunk, widgetEnv)
	local testNs = {
		Profile = { rotations = function() return rotationList end },
		Conditions = { Registry = {}, TypeList = function() return {} end, Describe = function() return "x" end,
			Units = {}, Ops = {}, Kinds = {}, TargetTypes = {} },
		SpellPicker = { Icon = function() return nil end, List = function() return {} end },
	}
	loadChunk("Accessibility", testNs)

	ok("RotationPanel registered", created.RotationPanel ~= nil)
	local panel = created.RotationPanel()
	panel:SetUserData("path", { "rotations", "rotation1", "rotationPanel" })
	ok("PanelRotation resolves rotation1", panel:PanelRotation() == rotationList[1])
	panel:SetUserData("path", { "rotations", "rotation2", "rotationPanel" })
	ok("PanelRotation resolves rotation2", panel:PanelRotation() == rotationList[2])
	panel:SetUserData("path", {})
	ok("PanelRotation nil without rotation key", panel:PanelRotation() == nil)
end

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
