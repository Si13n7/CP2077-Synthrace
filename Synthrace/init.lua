--[[
==============================================
This file is distributed under the MIT License
==============================================

Synthrace - Race Music Overhaul

Filename: init.lua
Version: 2025-10-30, 03:30 UTC+01:00 (MEZ)

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

---Represents the `RadioExt` RED4ext mod interface, providing methods to play and control external audio.
---@class RadioExt
---@field SetVolume fun(channel: number, volume: number) # Sets the volume of a specific channel; returns true on success (if provided), otherwise nil.
---@field GetSongLength fun(filePath: string): integer # Returns the duration of the specified audio file in milliseconds. Supported formats include: `.mp3`, `.mp2`, `.flac`, `.ogg`, `.wav`, `.wax`, `.wma`, `.opus`, `.aiff`, `.aif`, and `.aifc`.
---@field Stop fun(channel: integer) # Stops playback on the specified channel. Use `-1` to stop all currently playing audio.
---@field Play fun(channel: integer, filePath: string, time: integer, volume: number, fadeIn: number) # Plays an audio file on the given channel. `time` defines the playback start position in milliseconds; use `-1` to open the file as a stream instead of preloading it. `volume` sets the initial playback volume (1.0 = 100%), and `fadeIn` specifies the fade-in duration in seconds before reaching the target volume.

---Represents the `nativeSettings` CET mod interface used to create and manage custom settings tabs.
---@class NativeSettings
---@field pathExists fun(path: string): boolean # Checks whether a given settings path exists in the current UI hierarchy.
---@field addTab fun(path: string, label: string) # Adds a new main tab to the Native Settings UI with the specified path and label.
---@field addSubcategory fun(path: string, label: string) # Creates a new subcategory under the given path with the specified label.
---@field removeSubcategory fun(path: string) # Removes the specified subcategory if it exists.
---@field addSelectorString fun(path: string, label: string, desc: string, items: string[], value: integer, default: integer, setValue: fun(value: integer)) # Adds a string selector dropdown with a list of options and a callback triggered when a selection is made.
---@field addRangeInt fun(path: string, label: string, desc: string, min: integer?, max: integer?, step: integer?, value: integer, default: integer, setValue: fun(value: integer)) # Adds an integer slider or range input to the settings UI, with min/max limits and a value change callback.
---@field addButton fun(path: string, label: string?, desc: string, buttonText: string, textSize: number, callback: fun()) # Adds a button element to the settings UI. `label` is optional and can be nil for unlabeled buttons.
---@field currentTab string # The path of the currently opened tab, or an empty string if none is active.

---Represents the `CyberTrials` CET mod interface, exposing its runtime state.
---@class CyberTrials
---@field raceActive boolean # Indicates whether a CyberTrials race event is currently active.

--Aliases for commonly used standard library functions to simplify code.
local format, concat, insert, unpack, abs, floor, random, randomseed =
	string.format,
	table.concat,
	table.insert,
	table.unpack,
	math.abs,
	math.floor,
	math.random,
	math.randomseed

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

	---Prevents the active audio track from being stopped during certain transitions, such as scene changes.
	isProtected = false,

	---Index of the last randomly played track to avoid repetition.
	lastLoopIndex = -1,

	---Index of the currently selected audio source.
	index = 1,

	---Name of the currently selected audio source folder.
	source = "#Default",

	---List of available audio source folder names.
	---@type string[]
	sources = {},

	---Active audio playlist containing song and outro file paths for the current source.
	---@type { songs: string[], outros: string[] }
	playlist = {},

	---Determines whether the custom audio playback is currently muted without being stopped.
	isMuted = false,

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

---Stores references to external mods for extended functionality.
local refs = {
	---Reference to the `RadioExt` RED4ext mod instance, which is required for this mod to function.
	---@type RadioExt
	radioExt = nil,

	---Reference to the `Native Settings UI` CET mod instance, which is optional and only used if available.
	---@type NativeSettings
	nativeSettings = nil,

	---Reference to the `CyberTrials` CET mod instance, which is optional and only used if available.
	---@type CyberTrials
	cyberTrials = nil
}

---Safely retrieves a nested value from a table (e.g., table[one][two][three]).
---Returns a nil if any level is missing or invalid.
---@param t table # The root table to access.
---@param ... any # One or more keys representing the path.
---@return any # The nested value if it exists, or the default value.
local function get(t, ...)
	if type(t) ~= "table" then return nil end
	local v = t
	for i = 1, select("#", ...) do
		local k = select(i, ...)
		if type(v) ~= "table" or k == nil then
			return nil
		end
		v = rawget(v, k)
	end
	return v ~= nil and v or nil
end

---Checks if a string starts or ends with a given affix.
---@param s string # The string to check.
---@param v string # The prefix or suffix to match.
---@param atEnd boolean # If true, checks suffix (ends with); if false, checks prefix (starts with).
---@param caseInsensitive boolean? # If true, ignores case when comparing.
---@return boolean # True if the condition is met, false otherwise.
local function hasAffix(s, v, atEnd, caseInsensitive)
	if not s or not v then return false end
	s, v = tostring(s), tostring(v)
	if caseInsensitive then
		s = s:lower()
		v = v:lower()
	end
	local len = #v
	if #s == len then return s == v end
	if #s < len then return false end
	return (atEnd and s:sub(-len) or s:sub(1, len)) == v
end

---Checks if a string starts with a given prefix.
---@param s string # The string to check.
---@param v string # The prefix to match.
---@param caseInsensitive boolean? # True if string comparisons ignore letter case.
---@return boolean # True if `s` starts with `v`, false otherwise.
local function startsWith(s, v, caseInsensitive)
	return hasAffix(s, v, false, caseInsensitive)
end

---Extracts the file extension from a given file path in a safe and cross-platform way.
---Supports both Windows (`\`) and Unix (`/`) path separators and ignores dots in folder names.
---@param path string # The file path to extract the extension from.
---@return string? # The lowercase file extension, or nil if none exists or input is invalid.
local function getFileExtension(path)
	if type(path) ~= "string" or #path < 1 then return nil end
	local ext = path:match("^.+%.([^/\\%.]+)$")
	return ext and ext:lower() or nil
end

---Reads the full content of a file and returns it as a string.
---@param path string # The path to the file to read.
---@return string? # The file content as a string, or nil if the file could not be read.
local function getFileContent(path)
	if type(path) ~= "string" or #path < 1 then return nil end
	local file = io.open(path, "r")
	if not file then return nil end
	local content = file:read("*a")
	file:close()
	return content
end

---Writes a formatted log message to the CET console with a specified log level prefix.
---@param lvl string # Log level label (e.g. "Info", "Warning", "Error").
---@param fmt string # Format string (printf-style) for the log message.
---@param ... any # Optional arguments to be formatted into the message.
local function log(lvl, fmt, ...)
	if not lvl or not fmt then return end
	local pfx = format("[%s]  [%s]  ", Text.GUI_NAME, lvl)
	print(select("#", ...) and format(pfx .. fmt, ...) or fmt)
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

---Stops and removes all active async timers.
local function asyncStopAll()
	if not async.isActive then return end
	for id in pairs(async.timers) do
		async.timers[id] = nil
	end
	async.isActive = false
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

---Returns the absolute path to the Cyber Engine Tweaks mods directory.
---@return string # The CET mods directory path.
local function getCetModsDir()
	return "plugins\\cyber_engine_tweaks\\mods"
end

---Returns the base directory for all audio sources.
---@param isCetHome boolean? # If true, returns the CET-relative `music` path; otherwise returns the absolute mod path.
---@return string # Path to the audio base directory.
local function getAudioBaseDir(isCetHome)
	return isCetHome and "music" or (getCetModsDir() .. "\\Synthrace\\music")
end

---Builds the path to a specific audio source folder.
---@param isCetHome boolean? # If true, returns a CET-relative path; otherwise an absolute mod path.
---@param source string? # Source folder name. If nil, the current source from `audio.sources[audio.index]` is used.
---@return string # Path to the selected audio source directory
local function getAudioSourceDir(isCetHome, source)
	return format("%s\\%s", getAudioBaseDir(isCetHome), source and source or audio.sources[audio.index])
end

---Builds the full file path for a given audio track.
---@param name string # Base filename with extension.
---@param source string? # Source folder name. If nil, the current active audio source is used.
---@return string # The full path to the audio file, or an empty string if the name is invalid.
local function getAudioPath(name, source)
	if not name then return "" end
	return format("%s\\%s", getAudioSourceDir(false, source), name)
end

---Checks whether a given audio file exists.
---Uses `RadioExt.GetSongLength()` to verify if the file can be opened and decoded successfully.
---@param name string # The audio file name or path to check.
---@param source string? # Optional source directory or identifier used to resolve the full audio path.
---@return boolean # True if the file exists and is a valid audio file, false otherwise.
local function audioFileExists(name, source)
	if not name then return false end
	local path = source and getAudioPath(name, source) or name
	local time = refs.radioExt.GetSongLength(path)
	return type(time) == "number" and time > 0
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

		local isValid = false

		if getFileExtension(source) == "json" then
			local content = getFileContent(getAudioSourceDir(true, source))
			local playlist = content and json.decode(content)
			if type(playlist) == "table" and next(playlist) then
				local song = get(playlist, "songs", 1)
				local path = song and format("%s\\%s", getCetModsDir(), song)
				if audioFileExists(path) then
					local kind = getFileExtension(song)
					isValid = kind == "mp3" or kind == "ogg"
				end
			end
		else
			local files = dir(getAudioSourceDir(true, source))
			for _, file in ipairs(files) do
				local name = file.name
				local kind = getFileExtension(name)
				if kind == "mp3" or kind == "ogg" then
					isValid = true
					break
				end
			end
		end

		if isValid then
			insert(sources, source)
			logInfo(Text.LOG_FOLDER_ADDED, source)
		else
			logErr(Text.LOG_SOURCE_INVALID, source)
		end

		::continue::
	end

	audio.sources = sources
	return sources
end

---Builds an audio playlist from either a JSON file or a directory structure.
---If a JSON file is provided, it loads the defined `songs` and optional `outros` lists.
---If a directory is provided, it scans for playable audio files and automatically separates songs and outros.
---Missing outro files are replaced with the default ones from `#Default`.
---@param source string? # Optional name of the audio source to look up. Defaults to `audio.source` if not specified.
---@return table<string, string[]> # A table containing two arrays: `songs` (main playlist) and `outros` (outro tracks).
local function getAudioPlaylist(source)
	source = source or audio.source
	if not source then return {} end

	local list = {
		songs = {},
		outros = {}
	}

	if getFileExtension(source) == "json" then
		local content = getFileContent(getAudioSourceDir(true, source))
		local playlist = content and json.decode(content)
		if type(playlist) == "table" then
			for _, key in ipairs({ "songs", "outros" }) do
				local entries = get(playlist, key) or {}
				for _, song in ipairs(entries) do
					local path = song and format("%s\\%s", getCetModsDir(), song)
					if audioFileExists(path) then
						insert(list[key], path)
					end
				end
			end
		end
	else
		local files = dir(getAudioSourceDir(true, source))
		for _, file in ipairs(files) do
			local name = file.name
			if audioFileExists(name, source) then
				local isOutro = startsWith(name, "RaceEnd", true)
				local path = getAudioPath(name, source)
				insert(isOutro and list.outros or list.songs, path)
			end
		end
	end

	if #list.outros > 1 then return list end

	for i = 1, 2 do
		list.outros[i] = list.outros[i] or getAudioPath("RaceEnd" .. i .. ".mp3", "#Default")
	end

	return list
end

---Returns the index of a given audio source name.
---@param source string? # Optional name of the audio source to look up. Defaults to `audio.source` if not specified.
---@return integer # Index position in the source list, or 0 if not found.
local function getAudioIndex(source)
	source = source or audio.source
	local sources = getAudioSources()
	for i, name in ipairs(sources) do
		if name == source then
			return i
		end
	end
	logWarn(Text.LOG_SOURCE_MISSING, source)
	return 0
end

---Retrieves a song from the active audio playlist by index or at random if no index is provided.
---@param index integer? # Optional index of the song to retrieve. If omitted, a random song is selected.
---@return string?, integer # The selected song path and its index, or nil and 0 if no valid song is available.
local function getSongPath(index)
	local songs = get(audio.playlist, "songs")
	if type(songs) ~= "table" or #songs == 0 then
		return nil, 0
	end
	if type(index) == "number" then
		if index < 1 then
			index = 1
		elseif index > #songs then
			index = #songs
		end
	else
		index = random(1, #songs)
	end
	return songs[index], index
end

---Retrieves the outro track used when the player wins a race.
---@return string # The file path of the win outro track.
local function getWinOutroPath()
	return get(audio.playlist, "outros", 1) or getAudioPath("RaceEnd1.mp3", "#Default")
end

---Retrieves the outro track used when the player loses a race.
---@return string # The file path of the loss outro track.
local function getLossOutroPath()
	return get(audio.playlist, "outros", 2) or getAudioPath("RaceEnd2.mp3", "#Default")
end

---Mutes the currently playing custom audio without stopping it.
local function muteAudio()
	if not audio.isPlaying or audio.isMuted then return end
	audio.isMuted = true
	refs.radioExt.SetVolume(-1, 0)
end

---Restores volume for the currently playing custom audio.
local function unmuteAudio()
	if not audio.isPlaying or not audio.isMuted or audio.volume < 0 then return end
	audio.isMuted = false
	refs.radioExt.SetVolume(-1, audio.volume / 100)
end

---Completely stops the currently playing custom audio and resets state.
local function stopAudio()
	if not audio.isPlaying then return end

	audio.isPlaying = false
	audio.isLoopActive = false
	audio.isProtected = false

	asyncStopAll()

	refs.radioExt.Stop(-1)

	restoreGlobalVolume()
end

---Plays the specified audio file once, optionally restoring global volume afterward.
---@param path string # The full absolute path to the song file.
---@param doRestore boolean? # If true, restores global volume after playback finishes.
---@return number # Duration in milliseconds, or 0 if unavailable.
local function playAudio(path, doRestore)
	if not path then return 0 end

	stopAudio()

	audio.isPlaying = true

	local volume = audio.volume / 100
	muteGlobalVolume()

	local time = refs.radioExt.GetSongLength(path)
	refs.radioExt.Play(-1, path, time, audio.isMuted and 0 or volume, 0.5)

	if not doRestore then return time end

	local delay = floor(time / 1000)
	asyncOnce(delay, function()
		audio.isProtected = false
		restoreGlobalVolume()
	end)

	return time
end

---Starts an asynchronous randomized audio loop for continuous race music playback.
local function playAudioRandomLoop()
	local path, i
	for _ = 1, 10 do
		path, i = getSongPath()
		if not path then
			logErr(Text.LOG_PLAYLIST_INVALID)
			return
		end
		if audio.lastLoopIndex ~= i then
			break
		end
	end

	audio.lastLoopIndex = i

	local delay = playAudio(path) / 1000
	if delay < 40 then return end

	audio.isLoopActive = true
	asyncRepeat(delay, function()
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

---Checks whether the player is currently seated in a vehicle and occupying the driver seat.
---@return boolean # True if the player exists, is mounted in a vehicle, and is the driver; otherwise false.
local function isVehicleDriver()
	local player = Game.GetPlayer()
	return player and Game.GetMountedVehicle(player) and Game.IsDriver(player)
end

---Initializes and registers all mod settings within the Native Settings UI.
local function createNativeMenu()
	local ns = refs.nativeSettings
	if not ns then return end

	local tab = "/Synthrace"
	if not ns.pathExists(tab) then
		ns.addTab(tab, Text.GUI_NAME)
	end

	--Ensures that multiple save queues aren't started simultaneously.
	local isSavePending = false

	---Asynchronous queue that delays saving until the settings tab is closed.
	local function saveToFile()
		if isSavePending then return end

		isSavePending = true
		asyncRepeat(3, function(timerID)
			if not ns.currentTab or #ns.currentTab < 1 then
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
	---@param default any # Default value for the option.
	---@param value any # Current value of the option.
	---@param min integer? # Minimum numeric value (for sliders).
	---@param max integer? # Maximum numeric value (for sliders).
	---@param speed integer? # Step size for numeric options; fractional speeds imply float sliders.
	---@param list string[]? # Optional list of selectable string values.
	---@param setValue function # Callback used when the value changes.
	local function addOption(section, label, desc, default, value, min, max, speed, list, setValue)
		if type(list) == "table" and next(list) then
			ns.addSelectorString(section, label, desc, list, value, default, setValue)
		elseif type(default) == "number" then
			speed = speed or 1
			ns.addRangeInt(
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
	if ns.pathExists(cat) then
		ns.removeSubcategory(cat)
	end
	ns.addSubcategory(cat, Text.GUI_TITLE)

	local sources = getAudioSources()
	addOption(cat, Text.GUI_PLAYLIST, Text.GUI_PLAYLIST_TIP, 1, audio.index, 1, #sources, 1, sources,
		function(value)
			audio.index = value
			audio.source = sources[value]
			saveToFile()
		end
	)

	ns.addButton(cat, nil, Text.GUI_REFRESH_TIP, Text.GUI_REFRESH, 40,
		function()
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

	--Handle hard dependency.
	---@diagnostic disable-next-line: undefined-global
	refs.radioExt = RadioExt
	if type(refs.radioExt) ~= "userdata" then
		logWarn(Text.LOG_MOD_DISABLED)
		return
	end

	---Initializes the random number generator with a mixed seed based on CPU clock.
	---Ensures more varied randomness across CET sessions.
	randomseed(os.clock())

	--If the game crashed for any reason, this ensures that all
	--changes made by this mod are reverted on the next startup.
	loadDatabase(true)
	restoreGlobalVolume()

	--Load user config.
	loadDatabase()

	--Validate user config data.
	audio.index = getAudioIndex()
	if audio.index < 1 then
		audio.index = 1
		audio.source = "#Default"
	end
	audio.playlist = getAudioPlaylist()

	--Observes race UI events to control custom race music playback.
	Observe("hudCarRaceController", "OnForwardVehicleRaceUIEvent", function(_, event)
		local mode = event and event.mode
		if not mode then return end
		if not isVehicleDriver() then
			stopAudio()
			return
		end
		local ct = refs.cyberTrials
		if mode == vehicleRaceUI.RaceStart then
			if ct.raceActive then
				ct.curTrackHook = ct.getTrackName()
				ct.prevTimeHook = ct.getBestTimeHook(ct.curTrackHook)
			end
			playAudioRandomLoop()
			logInfo(Text.LOG_RACE_STARTED)
		elseif mode == vehicleRaceUI.RaceEnd then
			if ct.raceActive then
				local isTraveling = ct.backToStartOnFinishHook()
				local isCompleted = ct.isRaceCompletedHook()

				stopAudio()
				muteGlobalVolume()

				audio.isProtected = isCompleted and isTraveling
				asyncRepeat(1, function(id)
					if audio.isProtected then return end
					asyncStop(id)

					local isBestTime = ct.getBestTimeHook(ct.curTrackHook) < ct.prevTimeHook
					playAudio(isBestTime and getWinOutroPath() or getLossOutroPath(), true)
				end)

				logInfo(Text.LOG_RACE_ENDED)
				return
			end

			local position = tonumber(Game.GetQuestsSystem():GetFactStr("sq024_current_race_player_position")) or 0
			playAudio(position > 1 and getLossOutroPath() or getWinOutroPath(), true)
			logInfo(Text.LOG_RACE_FINISHED, position)
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
				Observe(scenario, event, function(_, x)
					if audio.isProtected and event == "SetProgress" then
						if type(x) == "number" then
							audio.isProtected = x < 1.0
						end
						return
					end
					handler()
				end)
			end
		end
	end

	--Handle optional dependencies.
	asyncOnce(2, function()
		local ns = GetMod("nativeSettings")
		if type(ns) == "table" then
			refs.nativeSettings = ns
			logInfo(Text.LOG_DEP_REFERENCED, "Native Settings UI")
			createNativeMenu()
		end

		local ct = GetMod("CyberTrials")
		if type(ct) == "table" then
			refs.cyberTrials = ct
			logInfo(Text.LOG_DEP_REFERENCED, "Cyber Trials")

			---Checks if the current race is completed.
			---Requires `CyberTrials-Patch.bat` to inject `raceLogicHook`.
			---@return boolean # Checks if the race has been completed based on current and total checkpoints.
			ct.isRaceCompletedHook = function()
				if not ct.isPatched then return true end
				if not ct.raceActive then return false end
				local current = get(ct.raceLogicHook, "cpNumber") or 0
				local total = get(ct.raceLogicHook, "track", "totalCheckpoints") or 0
				return abs(current - total) < 1e-4
			end

			---Reads the 'back to start' option from user settings.
			---Requires `CyberTrials-Patch.bat` to inject `userHook`.
			---@return boolean # Returns true if the user setting 'backToStartOnFinish' is enabled.
			ct.backToStartOnFinishHook = function()
				if not ct.isPatched then return false end
				return (get(ct.userHook, "settings", "backToStartOnFinish") or false) == true
			end

			---Retrieves the current race track name from the active race logic.
			---Requires `CyberTrials-Patch.bat` to inject `raceLogicHook`.
			---@return string? # The current track name, or nil if not available.
			ct.getTrackName = function()
				if not ct.isPatched then return nil end
				return get(ct.raceLogicHook, "track", "name")
			end

			---Retrieves the best recorded race time for a given track.
			---Requires `CyberTrials-Patch.bat` to inject `userHook`.
			---@param name string # The track name used to look up recorded times.
			---@return number # The best recorded time in milliseconds, or infinity if unavailable.
			ct.getBestTimeHook = function(name)
				if not ct.isPatched or not name then return math.huge end
				local times = get(ct.userHook, "recentTimes") or {}
				local current = times[name]
				if current then
					table.sort(current, function(a, b)
						return a.totalMillisecs < b.totalMillisecs
					end)
					if current[1] then
						local ms = current[1].totalMillisecs
						return ms > 1 and ms or math.huge
					end
				end
				return math.huge
			end
		else
			refs.cyberTrials = { raceActive = false }
		end
	end)
end)

--Detects when the CET overlay is opened.
registerForEvent("onOverlayOpen", function()
	overlay.isOpen = true
end)

--Detects when the CET overlay is closed.
registerForEvent("onOverlayClose", function()
	overlay.isOpen = false

	if not audio.isUnsaved then return end

	saveDatabase()
	if refs.nativeSettings then
		createNativeMenu()
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
				audio.index = i
				audio.source = sources[i]
				audio.playlist = getAudioPlaylist()
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
