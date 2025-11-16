--[[
==============================================
This file is distributed under the MIT License
==============================================

Standard API Definitions for IntelliSense

All definitions included here are used in the
main code.

These definitions have no functionality. They
are already provided by Lua or CET and exist
only for documentation and coding convenience.

Filename: api.lua
Version: 2025-10-23, 20:43 UTC+01:00 (MEZ)

Copyright (c) 2025, Si13n7 Developments(tm)
All rights reserved.
______________________________________________
--]]


---Provides functions to create graphical user interface elements within the Cyber Engine Tweaks overlay.
---@class ImGui
---@field Begin fun(title: string, flags?: integer): boolean # Begins a new ImGui window with optional flags. Must be closed with `ImGui.End()`. Returns true if the window is open and should be rendered.
---@field End fun() # Ends the creation of the current ImGui window. Must always be called after `ImGui.Begin()`.
---@field Dummy fun(width: number, height: number) # Creates an invisible element of specified width and height, useful for spacing.
---@field SameLine fun(offsetX?: number, spacing?: number) # Places the next UI element on the same line. Optionally adds horizontal offset and spacing.
---@field BeginCombo fun(label: string, previewValue: string, flags?: integer): boolean # Begins a combo box (drop-down list) with a preview value. Returns true if the combo is open and items should be drawn.
---@field Selectable fun(label: string, selected?: boolean, flags?: integer, sizeX?: number, sizeY?: number): boolean # Creates a selectable item inside a combo or list. Returns true if the item was clicked.
---@field InputInt fun(label: string, value: integer, step?: integer, stepFast?: integer, flags?: integer): integer, boolean # Creates an integer input field with optional increment and fast increment values. Returns the new value and a boolean indicating whether it was changed. In CET's Lua binding, the return order is reversed (`value, changed`).
---@field SetItemDefaultFocus fun() # Sets keyboard focus to the most recently added item if no other item is active. Commonly used inside combos or lists.
---@field EndCombo fun() # Ends the current combo box started with `ImGui.BeginCombo()`.
---@field SetNextItemWidth fun(width: number) # Sets a fixed width for the next item (e.g., combo box, slider, or text input). Affects layout and alignment.
---@field GetFontSize fun(): number # Returns the height in pixels of the currently used font. Useful for vertical alignment calculations.
ImGui = ImGui

---Flags used to configure ImGui window behavior and appearance.
---@class ImGuiWindowFlags
---@field AlwaysAutoResize integer # Automatically resizes the window to fit its content each frame.
ImGuiWindowFlags = ImGuiWindowFlags

---Bitwise operations (Lua 5.1 compatibility).
---@class bit32
---@field bxor fun(...: integer): integer # Returns the bitwise XOR (exclusive OR) of all given integer arguments.
bit32 = bit32

---Handles the player's quick slot system, including equipped items, cyberware shortcuts, and radio controls.
---@class QuickSlotsManager
---@field SendRadioEvent fun(self: QuickSlotsManager, toggle: boolean, setStation: boolean, stationIndex: integer) # Sends a radio control event. `toggle` enables or disables the radio, `setStation` defines whether to change the current station, and `stationIndex` selects the station when `setStation` is true.

---Represents the player character in the game, providing functions to interact with the player instance.
---@class Player
---@field GetQuickSlotsManager fun(): QuickSlotsManager # Returns the player's quick slots manager, which handles equipped items, gadgets, and quick access slots. Used to query or modify quick slot states.

---Provides functions to interact with quest-related data, including reading and modifying facts.
---@class QuestsSystem
---@field GetFactStr fun(self: QuestsSystem, fact: string): number? # Retrieves the value of a specified fact. Returns nil if not found.

---Represents a single settings variable within the game's SettingsSystem.
---@class ConfigVar
---@field GetType fun(self: ConfigVar): { value: string } # Returns the data type of the variable (e.g., "Bool", "Int", "Float", etc.).
---@field GetValue fun(self: ConfigVar): any # Returns the current value of the variable.
---@field GetDefaultValue fun(self: ConfigVar): any # Returns the default value of the variable.
---@field GetMinValue fun(self: ConfigVar): number? # Returns the minimum allowed value for numeric variables.
---@field GetMaxValue fun(self: ConfigVar): number? # Returns the maximum allowed value for numeric variables.
---@field GetStepValue fun(self: ConfigVar): number? # Returns the step size for numeric variables.
---@field GetValues fun(self: ConfigVar): any[]? # Returns all possible values for list-type variables.
---@field GetIndex fun(self: ConfigVar): integer? # Returns the current index for list-type variables.
---@field GetDefaultIndex fun(self: ConfigVar): integer? # Returns the default index for list-type variables.
---@field SetValue fun(self: ConfigVar, value: any) # Sets the new value for the variable.

---Provides access to game settings and configuration variables.
---@class SettingsSystem
---@field HasVar fun(self: SettingsSystem, group: string, option: string): boolean # Checks if a variable exists in the given group.
---@field GetVar fun(self: SettingsSystem, group: string, option: string): ConfigVar # Retrieves a variable object if it exists.

---Provides various global game functions, such as getting the player, mounted vehicles, and converting names to strings.
---@class Game
---@field GetPlayer fun(): Player? # Retrieves the current player instance if available.
---@field GetQuestsSystem fun(): QuestsSystem # Retrieves the Quests System, used for getting and setting quest facts.
---@field GetSettingsSystem fun(): SettingsSystem # Provides access to the global settings system used to query and modify game options.
Game = Game

---Represents available vehicle race UI events used to trigger race-related overlays or effects.
---@class vehicleRaceUI
---@field RaceStart integer # Triggered when a vehicle race begins.
---@field RaceEnd integer # Triggered when a vehicle race finishes.
vehicleRaceUI = vehicleRaceUI

---Provides functionality to replace or modify existing game functions at runtime.
---@class Override # Not a class — provided by CET.
---@field Override fun(className: string, functionName: string, callback: fun(self: any, wrapper: fun(...): any, ...)) # Replaces the specified game function. The callback receives the instance (`self`) and the original function (`wrapper`), which can be called manually to preserve original behavior.
Override = Override

---Provides functionality to observe game events, allowing custom functions to be executed when certain events occur.
---@class Observe # Not a class — provided by CET.
---@field Observe fun(className: string, functionName: string, callback: fun(...)) # Sets up an observer for a specified function within the game.
Observe = Observe

---Allows the registration of functions to be executed when certain game events occur, such as initialization or shutdown.
---@class registerForEvent # Not a class — provided by CET.
---@field registerForEvent fun(eventName: string, callback: fun(...)) # Registers a callback function for a specified event (e.g., `onInit`, `onIsDefault`).
registerForEvent = registerForEvent

---SQLite database handle.
---@class db # Not a class — provided by CET.
---@field exec fun(self: db, sql: string): boolean?, string? # Executes a SQL statement. Returns true on success, or nil and an error message.
---@field rows fun(self: db, sql: string): fun(): table # Executes a SELECT statement and returns an iterator. Each yielded row is an array (table) of column values.
db = db

---Scans a directory and returns its contents.
---@class dir # Not a class — provided by CET.
---@field dir fun(path: string): table # Returns a list of file/folder entries in the specified directory. Each entry is a table with at least a `name` field.
dir = dir

---Provides access to the external RadioExt audio system, used to play and control custom music or sound effects.
---@class RadioExt # Another CET mod.
---@field SetVolume fun(channel: number, volume: number) # Sets channel volume; returns true on success (if provided), otherwise nil.
---@field GetSongLength fun(filePath: string): integer # Returns the duration of the specified audio file in milliseconds. The path must point to a valid sound file recognized by RadioExt (e.g., `.ogg`, `.wav`, `.mp3`).
---@field Stop fun(channel: integer) # Stops playback on the specified channel. Use `-1` to stop all currently playing audio.
---@field Play fun(channel: integer, filePath: string, priority: integer, volume: number, fadeIn: number) # Plays an audio file on the given channel. `priority` defines playback priority (use `-1` for default). `volume` sets the initial playback volume (1.0 = 100%), and `fadeIn` specifies the fade-in duration in seconds before reaching the target volume.
RadioExt = RadioExt
