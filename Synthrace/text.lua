--[[
==============================================
This file is distributed under the MIT License
==============================================

Synthrace - Race Music Overhaul

Filename: text.lua
Version: 2025-10-25, 16:20 UTC+01:00 (MEZ)

Copyright (c) 2025, Si13n7 Developments(tm)
All rights reserved.
______________________________________________
--]]


return {
	--GUI: 🧩 General
	GUI_TITLE = "Synthrace - Race Music Overhaul",
	GUI_NAME = "Synthrace",

	--GUI: ⚒️ Settings
	GUI_PLAYLIST = "Playlist",
	GUI_PLAYLIST_TIP = "Select an audio source to use for race music playback.",
	GUI_REFRESH = "Refresh",
	GUI_REFRESH_TIP = "Reloads all playlists and rescans the music folders for new or changed files.",
	GUI_VOLUME = "Volume",
	GUI_VOLUME_TIP = "Adjust the volume to balance race music with the game's ambient sounds.",

	--HK: 🎮 Input & Hotkey
	HK_NEXT = "Skip Current Song and Play Next Song",
	HK_STOP = "Stop Current Playback",

	--LOG: ℹ️ Info
	LOG_FOLDER_ADDED = "Folder '%s' has been added as an audio source.",
	LOG_RACE_STARTED = "The race has started.",
	LOG_RACE_ENDED = "The race has ended. You finished in position %d.",

	--LOG: ⚠️ Warnings
	LOG_EXT_NOT_FOUND = "RadioExt not found - mod has been disabled!",

	--LOG: ❌ Errors
	LOG_FOLDER_INVALID = "Folder name '%s' uses an unsupported format.",
	LOG_FILE_MISSING = "File '%s.mp3' is missing in folder '%s'.",
	LOG_FILE_NOT_FOUND = "No file named '%s' found."
}
