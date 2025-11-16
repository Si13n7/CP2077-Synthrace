--[[
==============================================
This file is distributed under the MIT License
==============================================

Synthrace - Race Music Overhaul

Filename: init.lua
Version: 2025-10-25, 16:56 UTC+01:00 (MEZ)

Copyright (c) 2025, Si13n7 Developments(tm)
All rights reserved.
______________________________________________

Development Environment:
 - Editor:    Visual Studio Code
 - Extension: sumneko.lua
   - Set `"Lua.runtime.version": "LuaJIT"` in `User Settings (JSON)`
   - Set `"Lua.codeLens.enable" = true`    in `User Settings (JSON)`
   - Make sure to open the entire project folder in VS Code
--]]


---Represents a recurring asynchronous timer.
---@class IAsyncTimer
---@field Interval number # The time interval in seconds between each callback execution.
---@field Time number # The next scheduled execution time (typically os.clock() + interval).
---@field Callback fun(id: integer) # The function to be executed when the timer triggers; receives the timer's unique ID.
---@field IsActive boolean # True if the timer is currently active, false if paused or canceled.

--Aliases for commonly used standard library functions to simplify code.
local format, concat, insert, unpack, abs, floor, random, randomseed, bxor =
	string.format,
	table.concat,
	table.insert,
	table.unpack,
	math.abs,
	math.floor,
	math.random,
	math.randomseed,
	bit32.bxor

---Loads all visible static string constants from `text.lua` into the global `Text` table.
---This is the most efficient way to manage display strings separately from logic and code.
---@type table<string, string>
local Text = dofile("text.lua")

---Constant names of audio options read from the game's user settings (used for mute/restore).
---@type string[]
local OptionVars = {
	"MusicVolume",
	"CarRadioVolume",
	"RadioportVolume"
}

---Audio playback, configuration, and persistence state.
local audio = {
	---True if a custom audio track is currently playing.
	isPlaying = false,

	---True if a looping track sequence is active.
	isLoopActive = false,

	---Async timer ID of the currently running loop.
	currentLoopId = -1,

	---Index of the last randomly played track to avoid repetition.
	lastLoopIndex = -1,

	---Number of valid `RaceStart` tracks in the current audio source. Automatically recalculated when set below 0.
	count = -1,

	---Index of the currently selected audio source.
	index = 1,

	---Name of the currently selected audio source folder.
	source = "#Default",

	---List of available audio source folder names.
	---@type string[]
	sources = {},

	---Global audio volume level (range 10–200).
	volume = 70,

	---True if configuration changes are pending.
	isUnsaved = false
}

---Contains runtime data related to in-game systems.
local game = {
	---Stores the original in-game audio channel volumes before custom playback overrides them.
	---Used to restore the game's volume mix after mod playback stops.
	---@type table<string, number>
	volumeRestoreStack = {}
}

---Overlay and UI visibility state.
local overlay = {
	---True if the overlay or settings menu is currently visible.
	isOpen = false
}

---Manages recurring asynchronous timers and their status.
local async = {
	---Stores all active recurring async timers, indexed by their unique ID.
	---@type table<integer, IAsyncTimer>
	timers = {},

	---Auto-incrementing ID used to assign unique keys to each timer.
	idCounter = 0,

	---Indicates whether at least one recurring timer is active.
	---Used to skip unnecessary processing in `onUpdate` event when no timers exist.
	isActive = false
}

---Reference to the loaded `nativeSettings` mod instance, or nil if unavailable.
local native = nil

---Writes a formatted log message to the CET console with a specified log level prefix.
---@param lvl string # Log level label (e.g. "Info", "Warning", "Error").
---@param fmt string # Format string (printf-style) for the log message.
---@param ... any # Optional arguments to be formatted into the message.
local function log(lvl, fmt, ...)
	if not lvl or not fmt then return end
	local prefix = format("[%s]  [%s]  ", Text.GUI_NAME, lvl)
	print(select("#", ...) and format(prefix .. fmt, ...) or fmt)
end

---Logs an error message to the CET console.
---@param fmt string # Format string for the error message.
---@param ... any # Optional arguments to be formatted into the message.
local function logErr(fmt, ...)
	log("Error", fmt, ...)
end

---Logs a warning message to the CET console.
---@param fmt string # Format string for the warning message.
---@param ... any # Optional arguments to be formatted into the message.
local function logWarn(fmt, ...)
	log("Warning", fmt, ...)
end

---Logs an informational message to the CET console.
---@param fmt string # Format string for the info message.
---@param ... any # Optional arguments to be formatted into the message.
local function logInfo(fmt, ...)
	log("Info", fmt, ...)
end

---Stops and removes an active async timer with the given ID.
---Has no effect if the ID is invalid or already cleared.
---@param id integer Timer ID to stop.
local function asyncStop(id)
	if not id or id < 0 then return end
	async.timers[id] = nil
	async.isActive = next(async.timers) ~= nil
end

---Creates a recurring async timer that executes a callback every `interval` seconds.
---The first execution happens only after the initial interval has passed, not immediately at creation time.
---The callback receives the timer ID as its only argument.
---@param interval number Time in seconds between executions (absolute value is used).
---@param callback fun(id: integer) Function to execute each cycle.
---@return integer timerID Unique ID of the created timer, or -1 if invalid parameters were passed.
local function asyncRepeat(interval, callback)
	if not callback then return -1 end

	async.idCounter = async.idCounter + 1

	local id = async.idCounter
	local time = abs(tonumber(interval) or 0)
	async.timers[id] = {
		Interval = time,
		Callback = callback,
		Time = time,
		IsActive = true
	}

	async.isActive = true

	return id
end

---Creates a one-shot async timer that executes a callback once after `delay` seconds.
---@param delay number Time in seconds before execution (absolute value is used).
---@param callback fun(id: integer?) Function to execute once after the delay.
---@return integer timerID Unique ID of the created timer, or -1 if invalid parameters were passed.
local function asyncOnce(delay, callback)
	if not callback then return -1 end
	return asyncRepeat(delay, function(id)
		asyncStop(id)
		callback(id)
	end)
end

---Initializes a table in the database.
---Creates the table if it does not exist.
---@param tableName string # Name of the table to create.
---@param ... string # Column definitions, each as a separate string.
local function sqliteInit(tableName, ...)
	if not tableName or select("#", ...) < 1 then return end
	local columns = concat({ ... }, ", ")
	local query = format("CREATE TABLE IF NOT EXISTS %s(%s);", tableName, columns)
	db:exec(query)
end

---Begins a transaction.
local function sqliteBegin()
	db:exec("BEGIN;")
end

---Commits a transaction.
local function sqliteCommit()
	db:exec("COMMIT;")
end

---Returns an iterator over the rows of a table.
---Each yielded row is an array (table) of column values.
---@param tableName string # Name of the table.
---@param ... string # Optional column names to select, defaults to `*`.
---@return (fun(): table)? # Iterator returning a row table or nil when finished.
local function sqliteRows(tableName, ...)
	if not tableName then return nil end
	local columns = select("#", ...) > 0 and concat({ ... }, ", ") or "*"
	local query = format("SELECT %s FROM %s;", columns, tableName)
	return db:rows(query)
end

---Inserts or updates a row by primary key.
---If a conflict on the key occurs, the existing row will be updated.
---@param tableName string # Name of the table to insert into.
---@param keyColumn string # Column that acts as the primary key.
---@param colValPairs table # Key-value table of columns and their values.
---@return boolean? # True on success, nil on failure.
local function sqliteUpsert(tableName, keyColumn, colValPairs)
	if not tableName or not keyColumn or not colValPairs then return end

	local fields, values, updates = {}, {}, {}
	for c, v in pairs(colValPairs) do
		insert(fields, c)

		local kind = type(v)
		if kind == "boolean" or kind == "number" then
			insert(values, tostring(v))
		else
			if kind ~= "string" then
				v = tostring(v) --Serializer not added to this script.
			end
			v = v:gsub("'", "''")
			insert(values, "'" .. v .. "'")
		end

		insert(updates, c .. "=excluded." .. c)
	end
	local query = format("INSERT INTO %s(%s) VALUES(%s) ON CONFLICT(%s) DO UPDATE SET %s;",
		tableName,
		concat(fields, ","),
		concat(values, ","),
		keyColumn,
		concat(updates, ","))
	return db:exec(query)
end

---Deletes a row from the table using a specific key.
---@param tableName string # Name of the table.
---@param keyColumn string # Column used as the key.
---@param keyValue any # Value of the key to delete.
local function sqliteDelete(tableName, keyColumn, keyValue)
	if not tableName or not keyColumn or not keyValue then return end
	db:exec(format("DELETE FROM %s WHERE %s='%s';", tableName, keyColumn, keyValue:gsub("'", "''")))
end

---Initializes the database structure and creates required tables if they do not exist.
---@param backup boolean? # If true, initializes the backup table (`VolumeRestoreStack`); otherwise initializes the main configuration table (`UserConfig`).
local function initDatabase(backup)
	sqliteInit(
		backup and "VolumeRestoreStack" or "UserConfig",
		"Name TEXT PRIMARY KEY",
		backup and "Value INTEGER" or "Value STRING"
	)
end

---Loads persisted data from the SQLite database into memory.
---@param backup boolean? # If true, loads the volume restoration stack; otherwise loads user configuration data.
local function loadDatabase(backup)
	initDatabase(backup)
	for row in sqliteRows(backup and "VolumeRestoreStack" or "UserConfig", "Name, Value") do
		local name, value = unpack(row)
		if backup then
			game.volumeRestoreStack[name] = value
		else
			local current = audio[name]
			if current then
				audio[name] = type(current) == "number" and tonumber(value) or value
			end
		end
	end
end

---Persists the current in-memory state back to the database.
---@param backup boolean? # If true, writes the volume restoration stack; otherwise writes user configuration data.
local function saveDatabase(backup)
	initDatabase(backup)

	sqliteBegin()

	if backup then
		if not next(game.volumeRestoreStack) then
			for _, name in ipairs(OptionVars) do
				sqliteDelete("VolumeRestoreStack", "Name", name)
			end

			sqliteCommit()
			return
		else
			for name, value in pairs(game.volumeRestoreStack) do
				sqliteUpsert("VolumeRestoreStack", "Name", {
					Name = name,
					Value = value
				})
			end
		end

		sqliteCommit()
		return
	end

	local configData = {
		source = audio.source,
		volume = format("%d", audio.volume)
	}
	for name, value in pairs(configData) do
		sqliteUpsert("UserConfig", "Name", {
			Name = name,
			Value = value
		})
	end

	sqliteCommit()
end

---Retrieves a configuration variable handle from the game's audio settings group.
---@param option string # The option key, e.g., "MusicVolume".
---@return ConfigVar? # The associated variable handle or nil if not found.
local function getConfigVar(option)
	local sys = Game.GetSettingsSystem()
	local group = sys and "/audio/volume"
	return sys and sys:HasVar(group, option) and sys:GetVar(group, option) or nil
end

---Mutes all global audio channels while preserving their original volume levels.
local function muteGlobalVolume()
	local backup = game.volumeRestoreStack
	for _, option in ipairs(OptionVars) do
		if backup[option] then goto continue end

		local var = getConfigVar(option)
		if not var then goto continue end

		backup[option] = tonumber(var:GetValue()) or nil
		if backup[option] then
			var:SetValue(0)
		end

		::continue::
	end
	saveDatabase(true)
end

---Restores previously muted audio channels to their original volume levels.
local function restoreGlobalVolume()
	local backup = game.volumeRestoreStack
	for _, option in ipairs(OptionVars) do
		if not backup[option] then goto continue end

		local var = getConfigVar(option)
		if not var then goto continue end

		var:SetValue(backup[option])
		backup[option] = nil

		::continue::
	end
	saveDatabase(true)
end

---Returns the base directory for all audio sources.
---@param isCetHome boolean? # If true, returns the CET-relative `music` path; otherwise returns the absolute mod path.
---@return string # Path to the audio base directory.
local function getAudioBaseDir(isCetHome)
	return isCetHome and "music" or "plugins\\cyber_engine_tweaks\\mods\\Synthrace\\music"
end

---Builds the path to a specific audio source folder.
---@param isCetHome boolean? # If true, returns a CET-relative path; otherwise an absolute mod path.
---@param source string? # Source folder name. If nil, the current source from `audio.sources[audio.index]` is used.
---@return string # Path to the selected audio source directory
local function getAudioSourceDir(isCetHome, source)
	return format("%s\\%s", getAudioBaseDir(isCetHome), source and source or audio.sources[audio.index])
end

---Builds the full file path for a given audio track.
---@param name string # Base filename without extension.
---@param isCetHome boolean? # If true, returns a CET-relative path; otherwise the full absolute path.
---@param source string? # Source folder name. If nil, the current active audio source is used.
---@return string # The full path to the MP3 file, or an empty string if the name is invalid.
local function getAudioPath(name, isCetHome, source)
	if not name then return "" end
	return format("%s\\%s.mp3", getAudioSourceDir(isCetHome, source), name)
end

---Checks whether a music file with the given name exists in the `music` directory.
---@param name string # The base filename (without path or extension).
---@param source string? # Source folder name. If nil, the current active audio source is used.
---@return boolean # True if the corresponding MP3 file exists, false otherwise.
local function audioFileExists(name, source)
	if not name then return false end
	local path = getAudioPath(name, true, source)
	local handle = io.open(path, "r")
	if handle then
		handle:close()
		return true
	end
	return false
end

---Retrieves and validates available audio source folders.
---Only accepts folder names that start with a letter and contain only alphanumeric characters, underscores, or dashes.
---Skips invalid entries and populates `audio.sources` with verified sources.
---@return string[] # List of valid audio source folder names.
local function getAudioSources()
	local sources = audio.sources or {}
	if next(sources) then return sources end

	local folders = dir(getAudioBaseDir(true))
	for _, folder in ipairs(folders) do
		local source = folder.name
		if source ~= "#Default" and not source:match('^%w[^<>:"/\\|%?%*]*$') then
			logErr(Text.LOG_FOLDER_INVALID, source)
			goto continue
		end

		local isValid = true
		for _, prefix in ipairs({ "RaceEnd", "RaceStart" }) do
			for i = 1, 2 do
				local name = prefix .. i
				if not audioFileExists(name, source) then
					isValid = false
					logErr(Text.LOG_FILE_MISSING, name, source)
					break
				end
			end
			if not isValid then break end
		end
		if isValid then
			insert(sources, source)
			logInfo(Text.LOG_FOLDER_ADDED, source)
		end

		::continue::
	end

	audio.sources = sources
	return sources
end

---Returns the index of a given audio source name.
---@param name string # Audio source name to look up.
---@return integer # Index position in the source list, or 0 if not found.
local function getAudioIndex(name)
	local sources = getAudioSources()
	for i, source in ipairs(sources) do
		if source == name then
			return i
		end
	end
	logErr(Text.LOG_FILE_NOT_FOUND, name)
	return 0
end

---Counts the number of sequentially indexed `RaceStart` tracks in the current source directory.
---@return integer # Number of valid `RaceStart` tracks found.
local function getAudioCount()
	if audio.count >= 0 then return audio.count end

	local src = audio.source
	if not src then return 0 end

	local files = dir(getAudioSourceDir(true, src))
	if not files or not next(files) then return 0 end

	local map = {}
	for _, file in ipairs(files) do
		local name = file.name:lower()
		local num = tonumber(name:match("^racestart(%d+)%.mp3$"))
		if num then map[num] = true end
	end

	for i = 1, 99 do
		if not map[i] then
			audio.count = i - 1
			break
		end
	end
	return audio.count
end

---Retrieves the duration of an audio file in seconds.
---@param name string # The song name without extension.
---@return number # Duration in seconds, or 0 if unavailable.
local function getAudioDuration(name)
	if not name then return 0 end
	local path = getAudioPath(name)
	local length = RadioExt.GetSongLength(path)
	return floor((length or 0) / 1000)
end

---Mutes the currently playing custom audio without stopping it.
local function muteAudio()
	if not audio.isPlaying then return end
	RadioExt.SetVolume(-1, 0)
end

---Restores volume for the currently playing custom audio.
local function unmuteAudio()
	if not audio.isPlaying or audio.volume < 0 then return end
	RadioExt.SetVolume(-1, audio.volume / 100)
end

---Completely stops the currently playing custom audio and resets state.
local function stopAudio()
	if not audio.isPlaying then return end

	audio.isPlaying = false
	audio.isLoopActive = false

	asyncStop(audio.currentLoopId)
	audio.currentLoopId = -1

	RadioExt.Stop(-1)

	restoreGlobalVolume()
end

---Plays the specified audio file once, optionally restoring global volume afterward.
---@param name string # The song name without extension.
---@param doRestore boolean? # If true, restores global volume after playback finishes.
local function playAudio(name, doRestore)
	if not name then return end

	stopAudio()

	audio.isPlaying = true

	local volume = audio.volume / 100
	muteGlobalVolume()

	local path = getAudioPath(name)
	RadioExt.Play(-1, path, -1, volume, 0)

	if not doRestore then return end

	local delay = getAudioDuration(name)
	asyncOnce(delay, function()
		restoreGlobalVolume()
	end)
end

---Starts an asynchronous randomized audio loop for continuous race music playback.
local function playAudioRandomLoop()
	local num, name
	for _ = 1, 10 do
		num = random(1, getAudioCount())
		name = "RaceStart" .. num
		if audioFileExists(name) and audio.lastLoopIndex ~= num then
			break
		end
	end
	audio.lastLoopIndex = num

	playAudio(name)

	local delay = getAudioDuration(name)
	if delay <= 1 then return end

	audio.isLoopActive = true
	audio.currentLoopId = asyncRepeat(delay, function()
		if not audio.isLoopActive then return end
		playAudioRandomLoop()
	end)
end

---Stops all custom playback and restores the previous in-game audio state.
---Resets global volume to their original values.
local function reset()
	stopAudio()
	restoreGlobalVolume()
end

---Initializes and registers all mod settings within the Native Settings UI.
local function createNativeMenu()
	local instance = native or GetMod("nativeSettings")
	if not instance then return end
	native = instance

	local tab = "/Synthrace"
	if not instance.pathExists(tab) then
		instance.addTab(tab, Text.GUI_NAME)
	end

	--Ensures that multiple save queues aren't started simultaneously.
	local isSavePending = false

	---Asynchronous queue that delays saving until the settings tab is closed.
	local function saveToFile()
		if isSavePending then return end

		isSavePending = true
		asyncRepeat(3, function(timerID)
			if not instance.currentTab or #instance.currentTab < 1 then
				asyncStop(timerID)
				saveDatabase()
				isSavePending = false
			end
		end)
	end

	---Adds a settings option dynamically based on its type (list, boolean, or numeric).
	---Used internally to register configuration entries with the native settings system.
	---@param section string # The subcategory where the option appears in the Settings UI.
	---@param label string # Display name shown in the settings UI.
	---@param desc string # Description text.
	---@param default number|boolean # Default value for the option.
	---@param value number|boolean # Current value of the option.
	---@param min number? # Minimum numeric value (for sliders).
	---@param max number? # Maximum numeric value (for sliders).
	---@param speed number? # Step size for numeric options; fractional speeds imply float sliders.
	---@param list string[]? # Optional list of selectable string values.
	---@param setValue function # Callback used when the value changes.
	local function addOption(section, label, desc, default, value, min, max, speed, list, setValue)
		if type(list) == "table" and next(list) then
			instance.addSelectorString(section, label, desc, list, value, default, setValue)
		elseif type(default) == "number" then
			speed = speed or 1
			instance.addRangeInt(
				section,
				label,
				desc,
				min,
				max,
				speed,
				value,
				default,
				setValue
			)
		end
	end

	local cat = tab .. "/Settings"
	if instance.pathExists(cat) then
		instance.removeSubcategory(cat)
	end
	instance.addSubcategory(cat, Text.GUI_TITLE)

	local sources = getAudioSources()
	addOption(cat, Text.GUI_PLAYLIST, Text.GUI_PLAYLIST_TIP, 1, audio.index, 1, #sources, 1, sources,
		function(value)
			audio.count = -1
			audio.index = value
			audio.source = sources[value]
			saveToFile()
		end
	)

	instance.addButton(cat, nil, Text.GUI_REFRESH_TIP, Text.GUI_REFRESH, 40,
		function()
			audio.count = -1
			audio.index = 1
			audio.sources = {}
			createNativeMenu()
		end
	)

	addOption(cat, Text.GUI_VOLUME, Text.GUI_VOLUME_TIP, 70, audio.volume, 10, 200, 1, nil,
		function(value)
			audio.volume = math.max(10, math.min(200, floor(value)))
			saveToFile()
		end
	)
end

---Displays a tooltip when the current UI item is hovered.
---@param scale number? # The resolution scale for wrapping text.
---@param text string # The tooltip text.
local function addTooltip(scale, text)
	if not ImGui.IsItemHovered() then return end

	ImGui.BeginTooltip()

	local wrap = scale and floor(210 * scale) or nil
	if wrap then
		ImGui.PushTextWrapPos(wrap)
	end

	ImGui.Text(text)

	if wrap then
		ImGui.PopTextWrapPos()
	end

	ImGui.EndTooltip()
end

---This event is triggered when the CET initializes this mod.
registerForEvent("onInit", function()
	--Ensures the log file is fresh when the mod initializes.
	pcall(function()
		local file = io.open("Synthrace.log", "w")
		if file then file:close() end
	end)

	--RadioExt dependencies.
	if type(RadioExt) ~= "userdata" then
		logWarn(Text.LOG_EXT_NOT_FOUND)
		return
	end

	---Initializes the random number generator with a mixed seed based on system time and CPU clock.
	---Ensures more varied randomness across CET sessions.
	randomseed(os.clock())

	--If the game crashed for any reason, this ensures that all
	--changes made by this mod are reverted on the next startup.
	loadDatabase(true)
	restoreGlobalVolume()

	--Load user config.
	loadDatabase()

	--Validate user config data.
	audio.index = getAudioIndex(audio.source)
	if audio.index < 1 then
		audio.count = -1
		audio.index = 1
		audio.source = "#Default"
	end

	--Observes race UI events to control custom race music playback.
	Observe("hudCarRaceController", "OnForwardVehicleRaceUIEvent", function(_, event)
		if not event or not event.mode then return end
		if event.mode == vehicleRaceUI.RaceStart then
			playAudioRandomLoop()
			logInfo(Text.LOG_RACE_STARTED)
		elseif event.mode == vehicleRaceUI.RaceEnd then
			local position = tonumber(Game.GetQuestsSystem():GetFactStr("sq024_current_race_player_position")) or 0
			if position > 1 then
				playAudio("RaceEnd2", true)
			else
				playAudio("RaceEnd1", true)
			end
			logInfo(Text.LOG_RACE_ENDED, position)
		end
	end)

	--Registers menu event observers that determine when the music should be muted or stopped.
	local function muteToggle(self, value)
		if type(value) ~= "boolean" then
			value = self
		end
		if value == true then
			muteAudio()
		else
			unmuteAudio()
		end
	end
	local menuObservers = {
		[muteAudio] = {
			OnEnterScenario  = {
				"MenuScenario_ArcadeMinigame",
				"MenuScenario_BenchmarkResults",
				"MenuScenario_CharacterCustomization",
				"MenuScenario_CharacterCustomizationMirror",
				"MenuScenario_NetworkBreach",
				"MenuScenario_PreGameSubMenu"
			},
			OnLeaveScenario  = "MenuScenario_Idle",
			OnSelectMenuItem = "MenuScenario_HubMenu",
			OnLoadGame       = "MenuScenario_SingleplayerMenu",
			OnShow           = "gameuiPhotoModeMenuController"
		},
		[unmuteAudio] = {
			OnLeaveScenario = "MenuScenario_BaseMenu",
			OnCloseHubMenu  = "MenuScenario_HubMenu",
			OnHide          = "gameuiPhotoModeMenuController"
		},
		[muteToggle] = {
			OnIsActiveUpdated           = "BraindanceGameController",
			OnQuickHackUIVisibleChanged = "HUDManager"
		},
		[reset] = {
			OnUninitialize          = "QuestTrackerGameController",
			SetProgress             = "LoadingScreenProgressBarController",
			OnLoadingScreenFinished = "FastTravelSystem"
		}
	}
	for handler, events in pairs(menuObservers) do
		for event, scenarios in pairs(events) do
			scenarios = type(scenarios) == "table" and scenarios or { scenarios }
			for _, scenario in ipairs(scenarios) do
				Observe(scenario, event, handler)
			end
		end
	end

	--Initializes the Native Settings UI addon.
	asyncOnce(3, createNativeMenu)
end)

--Detects when the CET overlay is opened.
registerForEvent("onOverlayOpen", function()
	overlay.isOpen = true
end)

--Detects when the CET overlay is closed.
registerForEvent("onOverlayClose", function()
	overlay.isOpen = false
	if audio.isUnsaved then
		saveDatabase()
		if native then
			createNativeMenu()
		end
	end
end)

--Display a simple GUI with some options.
registerForEvent("onDraw", function()
	if not overlay.isOpen or not ImGui.Begin(Text.GUI_NAME, ImGuiWindowFlags.AlwaysAutoResize) then return end

	local scale = ImGui.GetFontSize() / 18
	local buttonSize = 24 * scale
	local widthPadding = 4 * scale
	local heightPadding = 2 * scale
	local style = ImGui.GetStyle()
	ImGui.Dummy(0, heightPadding)

	local sources = getAudioSources()
	local current = audio.index
	local preview = sources[current]
	ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, widthPadding, style.ItemSpacing.y)
	ImGui.SetNextItemWidth(120 * scale)
	if ImGui.BeginCombo("##Source", preview) then
		for i, item in ipairs(sources) do
			local isSelected = current == i
			if ImGui.Selectable(item, isSelected) and current ~= i then
				audio.count = -1
				audio.index = i
				audio.source = sources[i]
				audio.isUnsaved = true
			end
			if isSelected then
				ImGui.SetItemDefaultFocus()
			end
		end
		ImGui.EndCombo()
	end
	addTooltip(scale, Text.GUI_PLAYLIST_TIP)
	ImGui.SameLine()
	if ImGui.Button("\u{f0450}", buttonSize, buttonSize) then
		audio.count = -1
		audio.index = 1
		audio.sources = {}
		createNativeMenu()
	end
	addTooltip(scale, Text.GUI_REFRESH_TIP)
	ImGui.PopStyleVar()
	ImGui.SameLine()
	ImGui.Text(Text.GUI_PLAYLIST)
	addTooltip(scale, Text.GUI_PLAYLIST_TIP)
	ImGui.Dummy(0, heightPadding)

	ImGui.SetNextItemWidth(148 * scale)
	local volume, changed = ImGui.InputInt("##Volume", audio.volume, 5, 10)
	addTooltip(scale, Text.GUI_VOLUME_TIP)
	if changed then
		volume = floor(volume)
		if audio.volume ~= volume then
			audio.volume = math.max(10, math.min(200, floor(volume)))
			audio.isUnsaved = true
		end
	end
	ImGui.SameLine()
	ImGui.Text(Text.GUI_VOLUME)
	addTooltip(scale, Text.GUI_VOLUME_TIP)
	ImGui.Dummy(0, heightPadding)

	ImGui.End()
end)

---Called every frame to update active timers.
---Processes all running async timers and executes their callbacks when their interval elapses.
registerForEvent("onUpdate", function(deltaTime)
	if not async.isActive then return end

	for id, timer in pairs(async.timers) do
		if not timer.IsActive then goto continue end

		timer.Time = timer.Time - deltaTime
		if timer.Time > 0 then goto continue end

		timer.Callback(id)
		timer.Time = timer.Interval

		::continue::
	end
end)

---Restores all changes upon mod shutdown.
registerForEvent("onShutdown", reset)

---Hotkey that skips to the next random track.
registerHotkey("synthraceNextHotkey", Text.HK_NEXT, function()
	if audio.isLoopActive then
		playAudioRandomLoop()
	end
end)

---Input binding that plays the next random track when the assigned key is released.
registerInput("synthraceNextInput", Text.HK_NEXT, function(down)
	if not down and audio.isLoopActive then
		playAudioRandomLoop()
	end
end)

---Hotkey that stops all playback and restores the previous game audio state.
registerHotkey("synthraceStopHotkey", Text.HK_STOP, reset)

---Input binding that stops all playback and restores game audio when the assigned key is released.
registerInput("synthraceStopInput", Text.HK_STOP, function(down)
	if not down then reset() end
end)
