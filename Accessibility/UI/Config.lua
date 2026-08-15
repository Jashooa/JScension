-- The configuration panel.
--
-- A declarative AceConfig tree, opened via /acc or the Blizzard options. The
-- left sidebar shows "General", "Rotations" (one plain node per rotation, no
-- icons), and "Button". Selecting a rotation shows its rules in the content
-- area as a card list: each card has the spell icon in its title, ▲/▼ to
-- reorder, and a + toggle that expands the details (spell, unit, conditions).
-- Rules are inline groups, so they never appear in the sidebar tree.
--
-- The panel rebuilds on every structural change through NotifyChange, so the
-- rule and rotation groups are generated from the live profile. Adding a
-- condition type in Conditions.lua needs no work here.

local _, ns = ...

local Config = {}

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

local Profile = ns.Profile
local SpellPicker = ns.SpellPicker
local Conditions = ns.Conditions

local APP = "Accessibility"

local function currentProfile()
	return ns.addon.db.profile
end

-- mergeArgs combines two arg maps. The second map's entries are appended with
-- their orders offset past the first map's highest order, so a static group
-- (e.g. "New rotation") stays above the generated rotation groups.
local function mergeArgs(first, second)
	local maxOrder = 0
	for _, v in pairs(first) do
		local o = v.order or 0
		if o > maxOrder then maxOrder = o end
	end
	local merged = {}
	for k, v in pairs(first) do merged[k] = v end
	for k, v in pairs(second) do
		merged[k] = v
		-- offset every second-map order past the static entries so the tree
		-- renders "New rotation" above the rotation groups
		merged[k].order = (v.order or 0) + maxOrder
	end
	return merged
end

-- ---------------------------------------------------------------------------
-- value sets
-- ---------------------------------------------------------------------------

-- conditionTypes returns the { key = label } map for the type dropdown.
local function conditionTypes()
	local list = Conditions.TypeList()
	local values = {}
	for i = 1, #list do
		values[list[i].key] = list[i].label
	end
	return values
end

-- spellValues returns the { name = name } map for the spell dropdown. The
-- rule's current spell is added so a stale value still renders.
local function spellValues(rule)
	local list = SpellPicker.List()
	local values = {}
	for i = 1, #list do
		values[list[i]] = list[i]
	end
	if rule.spell and rule.spell ~= "" then
		values[rule.spell] = rule.spell
	end
	return values
end

-- ---------------------------------------------------------------------------
-- condition rendering
-- ---------------------------------------------------------------------------

-- fieldArgument renders one condition field as an AceConfig arg, driven by the
-- field type the registry declares.
local function fieldArgument(condition, field, fieldType)
	local name = field:gsub("_", " ")
	if fieldType == "number" then
		return {
			type = "range", name = name, min = 0, max = 100, step = 1,
			get = function() return condition[field] or 0 end,
			set = function(_, v) condition[field] = v end,
		}
	elseif fieldType == "op" then
		return {
			type = "select", name = name, values = Conditions.Ops,
			get = function() return condition[field] or "<" end,
			set = function(_, v) condition[field] = v end,
		}
	elseif fieldType == "unit" then
		return {
			type = "select", name = name, values = Conditions.Units,
			get = function() return condition[field] or "target" end,
			set = function(_, v) condition[field] = v end,
		}
	elseif fieldType == "kind" then
		return {
			type = "select", name = name, values = Conditions.Kinds,
			get = function() return condition[field] or "buff" end,
			set = function(_, v) condition[field] = v end,
		}
	elseif fieldType == "target_type" then
		return {
			type = "select", name = name, values = Conditions.TargetTypes,
			get = function() return condition[field] or "enemy" end,
			set = function(_, v) condition[field] = v end,
		}
	elseif fieldType == "bool" then
		return {
			type = "toggle", name = name,
			get = function() return condition[field] == true end,
			set = function(_, v) condition[field] = v and true or false end,
		}
	elseif fieldType == "code" then
		-- the custom-Lua condition's snippet is multi-line
		return {
			type = "input", name = name, multiline = true, width = "full",
			get = function() return condition[field] or "" end,
			set = function(_, v) condition[field] = v end,
		}
	else
		-- "spell", "string", and anything unknown render as a single-line input
		return {
			type = "input", name = name,
			get = function() return condition[field] or "" end,
			set = function(_, v) condition[field] = v end,
		}
	end
end

-- conditionExpanded tracks whether a condition's settings are shown. Keyed by
-- the condition table so it survives the NotifyChange rebuilds.
local conditionExpanded = {}

-- titleKey appends an invisible index suffix to a card title. The title
-- button registry is keyed by the exact title string AceConfig passes to
-- SetTitle; two cards with the same visible title (e.g. two Fireball rules
-- with different conditions, or the same spell in two rotations) would
-- otherwise share one spec. The suffix is a NUL byte plus the indices: the
-- widget strips it for display (the fontstring never receives it), while the
-- full string stays the unique registry key. The group's name function must
-- return the same string the registration used.
local function titleKey(title, rotationIndex, ruleIndex, conditionIndex)
	local suffix = ("\0%d:%d:%d"):format(
		rotationIndex, ruleIndex or 0, conditionIndex or 0)
	return title .. suffix
end

-- conditionGroup renders one condition card. The summary is the title; the
-- settings live in a nested group toggled by an in-body +/− button. Title
-- buttons on condition cards freeze the client (mid-layout frame creation),
-- so the toggle is in-body and the card never registers a TitleButtonGroup.
local function conditionGroup(rule, condIndex)
	local condition = rule.conditions[condIndex]
	local def = Conditions.Registry[condition.type]

	local settings = {
		type = {
			type = "select", name = "Condition", order = 1, width = "full",
			values = conditionTypes,
			get = function() return condition.type end,
			set = function(_, v)
				condition.type = v
				Config.NotifyOptionsChanged()
			end,
		},
	}
	if def then
		for field, fieldType in pairs(def.fields) do
			settings[field] = fieldArgument(condition, field, fieldType)
		end
	end
	settings.delete = {
		type = "execute", name = "Delete condition", order = math.huge, width = "full",
		func = function()
			table.remove(rule.conditions, condIndex)
			conditionExpanded[condition] = nil
			Config.NotifyOptionsChanged()
		end,
	}

	return {
		type = "group",
		name = function() return Conditions.Describe(condition) end,
		inline = true,
		args = {
			toggle = {
				type = "execute", order = 1, width = "full",
				name = function() return conditionExpanded[condition] and "−" or "+" end,
				func = function()
					conditionExpanded[condition] = not conditionExpanded[condition]
					Config.NotifyOptionsChanged()
				end,
			},
			settings = {
				type = "group", inline = true, name = "", order = 2,
				hidden = function() return not conditionExpanded[condition] end,
				args = settings,
			},
		},
	}
end

local function conditionArgs(rule)
	local args = {}
	for i = 1, #rule.conditions do
		args["condition" .. i] = conditionGroup(rule, i)
	end
	return args
end

-- ---------------------------------------------------------------------------
-- rule rendering
-- ---------------------------------------------------------------------------

-- Rules are inline groups, never tree nodes: selecting a rotation shows its
-- rules as a card list in the content area. Each card title carries the spell
-- icon (a |T texture escape) plus ▲/▼/Delete title buttons.

-- ruleIcon returns the first spell's icon for the rule title.
local function ruleIcon(rule)
	return SpellPicker.Icon(rule) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- ruleTitle renders the icon + label as the card title.
local function ruleTitle(rule, index)
	local label = ""
	if rule.name and rule.name ~= "" then
		label = rule.name
	elseif rule.spell and rule.spell ~= "" then
		label = rule.spell
	else
		label = "Rule " .. index
	end
	return ("|T%s:16:16|t %s"):format(ruleIcon(rule), label)
end

-- ruleGroup returns one rule card. The card title carries ▲/▼/Delete buttons
-- (via TitleButtonGroup - this worked and stays); the main options are always
-- visible, and the Conditions section is in-body (title buttons on conditions
-- were what froze, so conditions stay plain inline groups).
local function ruleGroup(rotation, rotationIndex, ruleIndex)
	local rule = rotation.rules[ruleIndex]
	local ruleKey = titleKey(ruleTitle(rule, ruleIndex), rotationIndex, ruleIndex)
	local conditionsKey = titleKey("Conditions", rotationIndex, ruleIndex)

	-- title buttons: up, down, delete (right-to-left order). Up is disabled
	-- on the first rule, down on the last.
	ns.UI.Widgets.TitleButtonGroups[ruleKey] = {
		{ label = "▲", order = 1, disabled = function() return ruleIndex <= 1 end, func = function()
			Profile.moveRule(rotation, ruleIndex, ruleIndex - 1)
			Config.NotifyOptionsChanged()
		end },
		{ label = "▼", order = 2, disabled = function() return ruleIndex >= #rotation.rules end, func = function()
			Profile.moveRule(rotation, ruleIndex, ruleIndex + 1)
			Config.NotifyOptionsChanged()
		end },
		{ label = "Delete", order = 3, func = function()
			Profile.deleteRule(rotation, ruleIndex)
			Config.NotifyOptionsChanged()
		end },
	}

	local args = {
		enabled = {
			type = "toggle", name = "Enabled", width = "half", order = 1,
			get = function() return rule.enabled end,
			set = function(_, v) rule.enabled = v end,
		},
		name = {
			type = "input", name = "Label", width = "full", order = 2,
			get = function() return rule.name or "" end,
			set = function(_, v) rule.name = v end,
		},
		spell = {
			type = "select", name = "Spell", width = "full", order = 3,
			values = function() return spellValues(rule) end,
			get = function() return rule.spell end,
			set = function(_, v) rule.spell = v end,
		},
		spellID = {
			type = "input", name = "Spell ID (optional)", width = "half", order = 4,
			get = function() return rule.spellID and tostring(rule.spellID) or "" end,
			set = function(_, v) rule.spellID = tonumber(v) end,
		},
		unit = {
			type = "select", name = "Target unit", width = "half", order = 5,
			values = Conditions.Units,
			get = function() return rule.unit or "target" end,
			set = function(_, v) rule.unit = v end,
		},
		conditions = {
			type = "group", name = conditionsKey, inline = true, order = 6,
			args = conditionArgs(rule),
		},
	}

	ns.UI.Widgets.TitleButtonGroups[conditionsKey] = {
		{
			label = "Add condition",
			order = 1,
			func = function()
  			rule.conditions[#rule.conditions + 1] = { type = "target_type", value = "enemy" }
  			Config.NotifyOptionsChanged()
			end,
		},
	}

	return {
		type = "group",
		name = function() return ruleKey end,
		inline = true,
		order = ruleIndex,
		args = args,
	}
end

-- ruleArgs returns the rules of a rotation as inline card groups.
local function ruleArgs(rotation, rotationIndex)
	local args = {}
	for i = 1, #rotation.rules do
		args["rule" .. i] = ruleGroup(rotation, rotationIndex, i)
	end
	return args
end

-- ---------------------------------------------------------------------------
-- rotation rendering
-- ---------------------------------------------------------------------------

-- rotationGroup: a plain tree node (no icon) whose content is two sections:
-- a "Rotation settings" section (rename, set active, duplicate, delete) at the
-- top, then a "Rules" section (add rule, then the rule cards). childGroups is
-- "tree" only so the node shows in the sidebar; the rules are inline and never
-- become tree nodes.
local function rotationGroup(rotation, index)
	local rulesKey = titleKey("Rules", index)
	local args = {
		settings = {
			type = "group", name = "Settings", inline = true, order = 1,
			args = {
				rename = {
					type = "input", name = "Name", width = "full",
					order = 1,
					get = function() return rotation.name end,
					set = function(_, v)
						Profile.renameRotation(rotation, v)
						Config.NotifyOptionsChanged()
					end,
				},
				setActive = {
					type = "execute", name = "Set active", width = "full",
					order = 2,
					disabled = function() return Profile.current().active == rotation.name end,
					func = function()
						Profile.setActive(rotation)
						Config.NotifyOptionsChanged()
					end,
				},
				duplicate = {
					type = "execute", name = "Duplicate", width = "full",
					order = 3,
					func = function()
						Profile.duplicateRotation(rotation)
						Config.NotifyOptionsChanged()
					end,
				},
				delete = {
					type = "execute", name = "Delete", width = "full",
					order = 4,
					disabled = function() return #Profile.rotations() <= 1 end,
					func = function()
						Profile.deleteRotation(rotation)
						Config.NotifyOptionsChanged()
					end,
				},
			},
		},
		rules = {
			type = "group", name = rulesKey, inline = true, order = 2,
			args = ruleArgs(rotation, index),
		},
	}

	-- the title-bar "Add rule" button, keyed by the group's title text.
	ns.UI.Widgets.TitleButtonGroups[rulesKey] = {
		{
			label = "Add rule",
			order = 1,
			func = function()
				Profile.addRule(rotation)
				Config.NotifyOptionsChanged()
			end,
		},
	}

	return {
		type = "group",
		name = function()
			if Profile.current().active == rotation.name then return rotation.name .. " (Active)" end
			return rotation.name
		end,
		order = index,
		childGroups = "tree",
		args = args,
	}
end

local function rotationArgs()
	local args = {}
	local list = Profile.rotations() or {}
	for i = 1, #list do
		args["rotation" .. i] = rotationGroup(list[i], i)
	end
	return args
end

-- ---------------------------------------------------------------------------
-- the panel
-- ---------------------------------------------------------------------------

-- logDescription renders the recent log ring as a block of text for the Log
-- section. It caps the shown lines so the description stays readable.
local LOG_DISPLAY_LINES = 30
local function logDescription()
	local lines = ns.Log.Dump(LOG_DISPLAY_LINES)
	if #lines == 0 then return "" end
	return table.concat(lines, "\n")
end

local function buttonArgs()
	local b = currentProfile().button
	return {
		visible = {
			type = "toggle", name = "Show button",
			get = function() return b.enabled ~= false end,
			set = function(_, v)
				b.enabled = v
				ns.Button.SetVisible(v)
			end,
		},
		locked = {
			type = "toggle", name = "Lock position",
			get = function() return b.locked end,
			set = function(_, v) b.locked = v end,
		},
		scale = {
			type = "range", name = "Scale", min = 0.5, max = 2.0, step = 0.1,
			get = function() return b.scale or 1.0 end,
			set = function(_, v) b.scale = v; ns.Button.ApplyPosition(b) end,
		},
		reset = {
			type = "execute", name = "Reset position",
			func = function()
				b.point, b.relativePoint, b.x, b.y = "CENTER", "CENTER", 0, 0
				ns.Button.ApplyPosition(b)
			end,
		},
	}
end

-- rotationValues returns the { name = name } map for the active-rotation
-- dropdown, from the live rotation list.
local function rotationValues()
	local list = Profile.rotations()
	local values = {}
	for i = 1, #list do
		values[list[i].name] = list[i].name
	end
	return values
end

function Config.BuildOptions()
	local p = currentProfile()
	return {
		type = "group",
		name = "Accessibility",   -- becomes the window title (Open reads it)
		childGroups = "tree",
		args = {
			rotations = {
				type = "group", name = "Rotations", order = 1,
				childGroups = "tree",
				args = mergeArgs({
					activeRotation = {
						type = "select", name = "Active rotation", order = 1,
						values = rotationValues,
						get = function() return Profile.current().active end,
						set = function(_, v)
							Profile.setActiveByName(v)
							Config.NotifyOptionsChanged()
						end,
					},
					auto = {
						type = "toggle", name = "Auto cast", order = 2,
						desc = "Cast continuously while on.",
						get = function() return p.auto end,
						set = function() ns.addon:ToggleAuto() end,
					},
					pulseInterval = {
						type = "range", name = "Pulse interval", order = 3,
						desc = "Seconds between auto checks.",
						min = 0.05, max = 1.0, step = 0.05,
						get = function() return p.pulseInterval end,
						set = function(_, v) p.pulseInterval = v end,
					},
					gcdProbeSpell = {
						type = "input", name = "GCD probe spell", order = 4,
						desc = "A known no-cooldown spell used to detect the global cooldown. Empty uses last-cast timing.",
						get = function() return p.gcdProbeSpell or "" end,
						set = function(_, v) p.gcdProbeSpell = v end,
					},
					queueWindow = {
						type = "range", name = "Spell queue window", order = 5,
						desc = "Start the next cast this many seconds before the current one ends, so the client queues it and casts back to back. 0 casts only when idle.",
						min = 0, max = 1.0, step = 0.05,
						get = function() return p.queueWindow or 0.4 end,
						set = function(_, v) p.queueWindow = v end,
					},
					newRotation = {
						type = "execute", name = "New rotation", order = 6,
						func = function()
							Profile.addRotation("Rotation")
							Config.NotifyOptionsChanged()
						end,
					},
				}, rotationArgs()),
			},
			button = {
				type = "group", name = "Button", order = 2,
				args = buttonArgs(),
			},
			log = {
				type = "group", name = "Log", order = 3,
				args = {
					refresh = {
						type = "execute", name = "Refresh", order = 1,
						func = function()
							Config.NotifyOptionsChanged()
						end,
					},
					clear = {
						type = "execute", name = "Clear", order = 2,
						func = function()
							ns.Log.Clear()
							Config.NotifyOptionsChanged()
						end,
					},
					output = {
						type = "description", name = logDescription, order = 3,
					},
				},
			},
		},
	}
end

-- ---------------------------------------------------------------------------
-- registration
-- ---------------------------------------------------------------------------

function Config.Setup()
	if Config.setupDone then return end
	Config.setupDone = true
	AceConfig:RegisterOptionsTable(APP, Config.BuildOptions)
	AceConfigDialog:AddToBlizOptions(APP, "Accessibility")

end

-- ensureRotationsExpanded marks the Rotations tree node expanded in the
-- dialog status. Called on every Open so it takes effect regardless of when
-- the status table is created.
local function ensureRotationsExpanded()
	local status = AceConfigDialog:GetStatusTable(APP)
	if not status.groups then status.groups = {} end
	status.groups["rotations"] = true
end

function Config.Open()
	ensureRotationsExpanded()
	AceConfigDialog:Open(APP)
end

function Config.NotifyOptionsChanged()
	AceConfigRegistry:NotifyChange(APP)
end

ns.Config = Config
