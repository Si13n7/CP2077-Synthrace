--[[
==============================================
This file is distributed under the MIT License
==============================================

Synthrace - Race Music Overhaul

Filename: init.lua
Version: 2025-10-23, 01:20 UTC+01:00 (MEZ)

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

---Holds runtime state for playback, looping, radio restore and volume backup.
local state = {
	---Determines whether a custom audio track is currently playing.
	isPlaying = false,

	---Stores the calculated maximum playback volume between 0 and 1.
	maxVolume = -1,

	---Determines whether a looping track sequence is active.
	isLoopActive = false,

	---Async timer ID for the currently active loop sequence.
	currentLoopId = -1,

	---Index of the last randomly played track to avoid repetition.
	lastLoopIndex = -1,

	---Prevents immediate reactivation of the last radio station when toggling between mod and in-game radio.
	isLastStationProtected = false,

	---Index of the last active in-game radio station, used for restoring playback.
	lastRadioStation = -1,

	---Stores previously active in-game audio channel volumes for restoration.
	---@type table<string, number>
	volumeRestoreStack = {},
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
	async.isActive = type(async.timers) == "table" and next(async.timers) ~= nil
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

---Initializes the database structure and creates necessary tables if missing.
local function initDatabase()
	sqliteInit(
		"VolumeRestoreStack",
		"Name TEXT PRIMARY KEY",
		"Volume INTEGER"
	)
end

---Loads persisted volume data from the database into memory.
local function loadDatabase()
	initDatabase()
	for row in sqliteRows("VolumeRestoreStack", "Name, Volume") do
		local key, volume = unpack(row)
		state.volumeRestoreStack[key] = volume
	end
end

---Writes current in-memory volume data back to the database.
local function saveDatabase()
	initDatabase()

	sqliteBegin()

	if next(state.volumeRestoreStack) == nil then
		for _, name in ipairs(OptionVars) do
			sqliteDelete("VolumeRestoreStack", "Name", name)
		end

		sqliteCommit()
		return
	end

	for name, volume in pairs(state.volumeRestoreStack) do
		sqliteUpsert("VolumeRestoreStack", "Name", {
			Name = name,
			Volume = volume
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

---Retrieves the numeric value of a configuration variable.
---@param option string # The option key, e.g., "MusicVolume".
---@return number # The option value or 0 if unavailable.
local function getConfigValue(option)
	local var = getConfigVar(option)
	local kind = var and var:GetType() ---@cast var ConfigVar
	return tonumber(kind and kind.value == "Int" and var:GetValue()) or 0
end

---Mutes all global audio channels while preserving their original volume levels.
local function muteGlobalVolume()
	local backup = state.volumeRestoreStack
	for _, option in ipairs(OptionVars) do
		local var = getConfigVar(option)
		if var then
			backup[option] = backup[option] or tonumber(var:GetValue()) or nil
			if backup[option] then
				var:SetValue(0)
			end
		end
	end
	saveDatabase()
end

---Restores previously muted audio channels to their original volume levels.
local function restoreGlobalVolume()
	local backup = state.volumeRestoreStack
	for _, option in ipairs(OptionVars) do
		local var = getConfigVar(option)
		if var and backup[option] then
			var:SetValue(backup[option])
			backup[option] = nil
		end
	end
	saveDatabase()
end

---Calculates the effective playback volume based on current audio settings.
---@return number # The normalized playback volume between 0.0 and 1.0.
local function getMaxVolume()
	local volume = 0
	for _, option in pairs(OptionVars) do
		volume = math.max(volume, getConfigValue(option))
	end
	return math.max(volume * 0.5, 30) / 100
end

---Stops any active in-game radio playback.
local function stopRadio()
	local manager = getQuickSlotsManager()
	if manager then
		state.isLastStationProtected = true
		manager:SendRadioEvent(false, false, -1)
	end
end

---Resumes the previously active in-game radio station.
local function resumeRadio()
	if state.lastRadioStation < 0 then return end

	local manager = getQuickSlotsManager()
	if manager then
		manager:SendRadioEvent(true, true, state.lastRadioStation)
	end
end

---Builds the full file path for a given audio track name.
---@param name string # The base filename (without extension).
---@param isCetHome boolean? # If true, returns the relative path from the CET `music` directory; otherwise returns the absolute mod path.
---@return string # The constructed file path to the MP3 file, or an empty string if the name is invalid.
local function getAudioPath(name, isCetHome)
	if not name then return "" end
	if isCetHome then
		return format("music\\%s.mp3", name)
	end
	return format("plugins\\cyber_engine_tweaks\\mods\\Synthrace\\music\\%s.mp3", name)
end

---Checks whether a music file with the given name exists in the `music` directory.
---@param name string # The base filename (without path or extension).
---@return boolean # True if the corresponding MP3 file exists, false otherwise.
local function audioFileExists(name)
	if not name then return false end
	local path = getAudioPath(name, true)
	local handle = io.open(path, "r")
	if handle then
		handle:close()
		return true
	end
	return false
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
	if not state.isPlaying then return end
	RadioExt.SetVolume(-1, 0)
end

---Restores volume for the currently playing custom audio.
local function unmuteAudio()
	if not state.isPlaying or state.maxVolume < 0 then return end
	RadioExt.SetVolume(-1, state.maxVolume)
end

---Completely stops the currently playing custom audio and resets state.
local function stopAudio()
	if not state.isPlaying then return end

	state.isPlaying = false
	state.isLoopActive = false

	asyncStop(state.currentLoopId)
	state.currentLoopId = -1

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

	state.isPlaying = true

	local volume = getMaxVolume()
	state.maxVolume = volume

	local path = getAudioPath(name)

	muteGlobalVolume()

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
		num = random(1, 8)
		name = "RaceStart" .. num
		if audioFileExists(name) and state.lastLoopIndex ~= num then
			break
		end
	end
	state.lastLoopIndex = num

	playAudio(name)

	local delay = getAudioDuration(name)
	if delay <= 1 then return end

	state.isLoopActive = true
	state.currentLoopId = asyncRepeat(delay, function()
		if not state.isLoopActive then return end
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

--This event is triggered when the CET initializes this mod.
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
	loadDatabase()
	restoreGlobalVolume()

	--Overrides the activation behavior of the vehicle radio menu to track the last selected radio station.
	Override("VehicleRadioPopupGameController", "Activate", function(self, wrapper)
		if state.isLastStationProtected then
			state.isLastStationProtected = false
			return
		end
		local selected = self.selectedItem
		local data = selected and selected:GetStationData()
		local record = data and data.record
		state.lastRadioStation = record and record:Index() or -1
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
		if not type(value) == "boolean" then
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

--Called every frame to update active timers.
--Processes all running async timers and executes their callbacks when their interval elapses.
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

--Restores all changes upon mod shutdown.
registerForEvent("onShutdown", reset)

--For testing...
--[[
GetMod("Synthrace").PlayStart(8)
GetMod("Synthrace").PlayEnd(2)
GetMod("Synthrace").PlayRandomLoop()
GetMod("Synthrace").Stop()
GetMod("Synthrace").Reset()
--]]
return {
	PlayStart = function(n) playAudio("RaceStart" .. n, true) end,
	PlayEnd = function(n) playAudio("RaceEnd" .. n, true) end,
	PlayRandomLoop = playAudioRandomLoop,
	Stop = stopAudio,
	Reset = reset,
}
