-- The configuration options.
--
-- Builds the declarative AceConfig option tree (rotations, button, log) and
-- registers it with AceConfigRegistry. The rotation rule cards themselves are
-- rendered by the RotationPanel widget; this file only wires the tree that
-- contains it. No UI widgets are created here.
--
-- ADDON_NAME comes from the TOC via the ... vararg, the same way
-- Accessibility.lua receives it; the name is never hardcoded twice.

local ADDON_NAME, ns = ...

local Config = {}

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

local Profile = ns.Profile
local Constants = ns.Constants

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
-- rotation rendering
-- ---------------------------------------------------------------------------

-- rotationGroup: a plain tree node (no icon) whose content is two sections:
-- a "Rotation settings" section (rename, set active, duplicate, delete) at the
-- top, then a "Rules" section (add rule, then the rule cards). childGroups is
-- "tree" only so the node shows in the sidebar; the rules are inline and never
-- become tree nodes.
local function rotationGroup(rotation, index)
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
		-- the rule cards are rendered by the RotationPanel widget. The widget
		-- finds its rotation from its option path (InjectInfo stores it in
		-- userdata), so the option carries no custom fields (AceConfig rejects
		-- unknown parameters).
		rotationPanel = {
			type = "execute", name = "", control = "RotationPanel",
			width = "full", order = 2,
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

-- rotationKey builds the AceConfig option key for a rotation by list index.
-- RotationPanel parses the key back with rotationIndexFromKey, so the
-- "rotation<N>" format lives in one place.
function Config.rotationKey(index)
	return "rotation" .. index
end

-- rotationIndexFromKey parses an option key back to a 1-based rotation
-- index, or nil when the key is not a rotation key.
function Config.rotationIndexFromKey(key)
	local index = key:match("^rotation(%d+)$")
	return index and tonumber(index) or nil
end

local function rotationArgs()
	local args = {}
	local list = Profile.rotations() or {}
	for i = 1, #list do
		args[Config.rotationKey(i)] = rotationGroup(list[i], i)
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
				ns.RotationButton.SetVisible(v)
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
			set = function(_, v) b.scale = v; ns.RotationButton.ApplyPosition(b) end,
		},
		reset = {
			type = "execute", name = "Reset position",
			func = function()
				b.point, b.relativePoint, b.x, b.y = "CENTER", "CENTER", 0, 0
				ns.RotationButton.ApplyPosition(b)
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
						get = function() return p.queueWindow or Constants.DEFAULT_QUEUE_WINDOW end,
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
	AceConfig:RegisterOptionsTable(ADDON_NAME, Config.BuildOptions)
	AceConfigDialog:AddToBlizOptions(ADDON_NAME, "Accessibility")

end

-- ensureRotationsExpanded marks the Rotations tree node expanded in the
-- dialog status. Called on every Open so it takes effect regardless of when
-- the status table is created.
local function ensureRotationsExpanded()
	local status = AceConfigDialog:GetStatusTable(ADDON_NAME)
	if not status.groups then status.groups = {} end
	status.groups["rotations"] = true
end

function Config.Open()
	ensureRotationsExpanded()
	AceConfigDialog:Open(ADDON_NAME)
end

function Config.NotifyOptionsChanged()
	AceConfigRegistry:NotifyChange(ADDON_NAME)
end

ns.Config = Config
