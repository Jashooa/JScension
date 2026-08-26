-- The configuration options.
--
-- Builds the declarative AceConfig option tree (rotations, button, log) and
-- registers it with AceConfigRegistry. The rotation rule cards and settings
-- are rendered by custom panel widgets; this file only wires the tree that
-- contains them. No UI widgets are created here.
--
-- ADDON_NAME comes from the TOC via the ... vararg, the same way
-- Accessibility.lua receives it; the name is never hardcoded twice.

local ADDON_NAME, ns = ...

local Config = {}

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local DEFAULT_DIALOG_WIDTH = 700
local DEFAULT_DIALOG_HEIGHT = 500
local TARGET_DIALOG_WIDTH = 900
local TARGET_DIALOG_HEIGHT = DEFAULT_DIALOG_HEIGHT * 1.5


local Profile = ns.Profile
assert(Profile, "load order: Core/Config before Profile")

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
		-- the settings (name, set active, duplicate, delete) are rendered by
		-- the RotationSettings widget. The widget finds its rotation from its
		-- option path (InjectInfo stores it in userdata).
		settings = {
			type = "execute", name = "", control = "RotationSettings",
			width = "full", order = 1,
		},
		-- the rule cards are rendered by the RotationRules widget. The widget
		-- finds its rotation from its option path (InjectInfo stores it in
		-- userdata), so the option carries no custom fields (AceConfig rejects
		-- unknown parameters).
		rotationRules = {
			type = "execute", name = "", control = "RotationRules",
			width = "full", order = 2,
		},
	}

	return {
		type = "group",
		name = function()
			if Profile.activeName() == rotation.name then return rotation.name .. " (Active)" end
			return rotation.name
		end,
		order = index,
		childGroups = "tree",
		args = args,
	}
end

-- rotationKey builds the AceConfig option key for a rotation by list index.
-- RotationRules parses the key back with rotationIndexFromKey, so the
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

function Config.BuildOptions()
	return {
		type = "group",
		name = ADDON_NAME,   -- becomes the window title (Open reads it)
		childGroups = "tree",
		args = {
			rotations = {
				type = "group", name = "Rotations", order = 1,
				childGroups = "tree",
				args = mergeArgs({
					rotationMainSettings = {
						type = "execute", name = "", control = "RotationMainSettings",
						width = "full", order = 1,
					},
				}, rotationArgs()),
			},
			button = {
				type = "group", name = "Button", order = 2,
				args = {
					buttonSettings = {
						type = "execute", name = "", control = "ButtonSettings",
						width = "full", order = 1,
					},
				},
			},
			log = {
				type = "group", name = "Log", order = 3,
				args = {
					logPanel = {
						type = "execute", name = "", control = "Log",
						width = "full", order = 1,
					},
				},
			},
		},
	}
end
local function ensureDialogSize()
	local status = AceConfigDialog:GetStatusTable(ADDON_NAME)
	if not status.width or status.width == DEFAULT_DIALOG_WIDTH then
		status.width = TARGET_DIALOG_WIDTH
	end
	if not status.height or status.height == DEFAULT_DIALOG_HEIGHT then
		status.height = TARGET_DIALOG_HEIGHT
	end
end


-- ---------------------------------------------------------------------------
-- registration
-- ---------------------------------------------------------------------------

function Config.Setup()
	if Config.setupDone then return end
	Config.setupDone = true
	AceConfig:RegisterOptionsTable(ADDON_NAME, Config.BuildOptions)
	ensureDialogSize()
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
