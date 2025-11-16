--[[
==============================================
This file is distributed under the MIT License
==============================================

Synthrace - Race Music Overhaul

Filename: init.lua
Version: 2025-10-23, 21:08 UTC+01:00 (MEZ)

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

---Contains runtime data related to in-game systems such as radio and audio channels.
local game = {
	---Prevents instant reactivation of the last in-game radio station.
	isRadioProtected = false,

	---Index of the last active in-game radio station for later restoration.
	lastRadioStation = -1,

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

---Retrieves the player's QuickSlotsManager instance, if available.
---@return QuickSlotsManager? # The active QuickSlotsManager or nil if unavailable.
local function getQuickSlotsManager()
	local player = Game.GetPlayer()
	return player and player:GetQuickSlotsManager() or nil
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

---Stops any active in-game radio playback.
local function stopRadio()
	local manager = getQuickSlotsManager()
	if manager then
		game.isRadioProtected = true
		manager:SendRadioEvent(false, false, game.lastRadioStation)
	end
end

---Resumes the previously active in-game radio station.
local function resumeRadio()
	if game.lastRadioStation < 0 then return end

	local manager = getQuickSlotsManager()
	if manager then
		manager:SendRadioEvent(true, true, game.lastRadioStation)
	end
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
---@param source string? # WIP
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
		if source ~= "#Default" and not source:match("^%a[%w_-]*$") then goto continue end

		local isValid = true
		for n, prefix in ipairs({ "RaceEnd", "RaceStart" }) do
			local count = n == 1 and 2 or 4
			for i = 1, count do
				if not audioFileExists(prefix .. i, source) then
					isValid = false
					break
				end
			end
			if not isValid then break end
		end
		if isValid then insert(sources, source) end

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
		local name = file.name
		local num = tonumber(name:match("^RaceStart(%d+)%.mp3$"))
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

---Plays the specified audio file once, optionally restoring radio and volume afterward.
---@param name string # The song name without extension.
---@param doRestore boolean? # If true, restores radio and volume after playback finishes.
local function playAudio(name, doRestore)
	if not name then return end

	stopAudio()
	stopRadio()

	audio.isPlaying = true

	local volume = audio.volume / 100
	muteGlobalVolume()

	local path = getAudioPath(name)
	RadioExt.Play(-1, path, -1, volume, 0)

	if not doRestore then return end

	local delay = getAudioDuration(name)
	asyncOnce(delay, function()
		resumeRadio()
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
---Resets radio and global volume to their original values.
local function reset()
	stopAudio()
	resumeRadio()
	restoreGlobalVolume()
end

---This event is triggered when the CET initializes this mod.
registerForEvent("onInit", function()
	if type(RadioExt) ~= "userdata" then
		print("[Synthrace] RadioExt not found - mod has been disabled!")
		return
	end

	---Initializes the random number generator with a mixed seed based on system time and CPU clock.
	---Ensures more varied randomness across CET sessions.
	randomseed(bxor(os.time() * 0xf4243, math.floor(os.clock() * 1e6)) % 0x7fffffff)

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

	--Overrides the activation behavior of the vehicle radio menu to track the last selected radio station.
	Override("VehicleRadioPopupGameController", "Activate", function(self, wrapper)
		if game.isRadioProtected then
			game.isRadioProtected = false
			return
		end
		local selected = self.selectedItem
		local data = selected and selected:GetStationData()
		local record = data and data.record
		game.lastRadioStation = record and record:Index() or -1
		wrapper()
	end)

	--Observes race UI events to control custom race music playback.
	Observe("hudCarRaceController", "OnForwardVehicleRaceUIEvent", function(_, event)
		if not event or not event.mode then return end
		if event.mode == vehicleRaceUI.RaceStart then
			playAudioRandomLoop()
		elseif event.mode == vehicleRaceUI.RaceEnd then
			if Game.GetQuestsSystem():GetFactStr("sq024_current_race_player_position") > 1 then
				playAudio("RaceEnd2", true)
			else
				playAudio("RaceEnd1", true)
			end
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
	end
end)

--Display a simple GUI with some options.
registerForEvent("onDraw", function()
	if not overlay.isOpen or not ImGui.Begin("\u{f023c} Synthrace", ImGuiWindowFlags.AlwaysAutoResize) then return end

	local scale = ImGui.GetFontSize() / 18
	local controlWidth = floor(120 * scale)
	local heightPadding = 2 * scale
	ImGui.Dummy(0, heightPadding)

	local sources = getAudioSources()
	local current = audio.index
	local preview = sources[current]
	ImGui.SetNextItemWidth(controlWidth)
	if ImGui.BeginCombo("Audio Source", preview) then
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
	ImGui.Dummy(0, heightPadding)

	ImGui.SetNextItemWidth(controlWidth)
	local volume, changed = ImGui.InputInt("Audio Volume", audio.volume, 5, 10)
	if changed then
		volume = floor(volume)
		if audio.volume ~= volume then
			audio.volume = math.max(10, math.min(200, floor(volume)))
			audio.isUnsaved = true
		end
	end
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

---For testing...
---@diagnostic disable
registerHotkey("synthrace1", "DEBUG: Play Random Track on Loop", function() playAudioRandomLoop() end)
registerHotkey("synthrace2", "DEBUG: Play Race Win Outro", function() playAudio("RaceEnd1", true) end)
registerHotkey("synthrace3", "DEBUG: Play Race Loss Outro", function() playAudio("RaceEnd2", true) end)
registerHotkey("synthrace4", "DEBUG: Stop Playback", function() reset() end)
