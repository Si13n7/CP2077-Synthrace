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
Version: 2025-10-30, 03:30 UTC+01:00 (MEZ)

Copyright (c) 2025, Si13n7 Developments(tm)
All rights reserved.
______________________________________________
--]]


---Style variables used to override ImGui layout and appearance settings temporarily.
---@class ImGuiStyleVar
---@field ItemSpacing { x: number, y: number } # Controls the horizontal (`x`) and vertical (`y`) spacing between consecutive UI elements. Can be overridden temporarily using `ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, x, y)` or restored with `ImGui.PopStyleVar()`.
ImGuiStyleVar = ImGuiStyleVar

---Provides functions to create graphical user interface elements within the Cyber Engine Tweaks overlay.
---@class ImGui
---@field Begin fun(title: string, flags?: integer): boolean # Begins a new ImGui window with optional flags. Must be closed with `ImGui.End()`. Returns true if the window is open and should be rendered.
---@field End fun() # Ends the creation of the current ImGui window. Must always be called after `ImGui.Begin()`.
---@field Dummy fun(width: number, height: number) # Creates an invisible element of specified width and height, useful for spacing.
---@field SameLine fun(offsetX?: number, spacing?: number) # Places the next UI element on the same line. Optionally adds horizontal offset and spacing.
---@field Text fun(text: string) # Displays text within the current window or tooltip.
---@field PushTextWrapPos fun(wrapLocalPosX?: number) # Sets a maximum width (in pixels) for wrapping text. Applies to subsequent Text elements until `PopTextWrapPos()` is called. If no value is provided, wraps at the edge of the window.
---@field PopTextWrapPos fun() # Restores the previous text wrapping position. Should be called after `PushTextWrapPos()` to reset wrapping behavior.
---@field Button fun(label: string, width?: number, height?: number): boolean # Creates a clickable button with optional width and height. Returns true if the button was clicked.
---@field BeginCombo fun(label: string, previewValue: string, flags?: integer): boolean # Begins a combo box (drop-down list) with a preview value. Returns true if the combo is open and items should be drawn.
---@field Selectable fun(label: string, selected?: boolean, flags?: integer, sizeX?: number, sizeY?: number): boolean # Creates a selectable item inside a combo or list. Returns true if the item was clicked.
---@field InputInt fun(label: string, value: integer, step?: integer, stepFast?: integer, flags?: integer): integer, boolean # Creates an integer input field with optional increment and fast increment values. Returns the new value and a boolean indicating whether it was changed. In CET's Lua binding, the return order is reversed (`value, changed`).
---@field SetItemDefaultFocus fun() # Sets keyboard focus to the most recently added item if no other item is active. Commonly used inside combos or lists.
---@field EndCombo fun() # Ends the current combo box started with `ImGui.BeginCombo()`.
---@field IsItemHovered fun(): boolean # Returns true if the last item is hovered by the mouse cursor.
---@field PushStyleVar fun(var: ImGuiStyleVar, x: number, y?: number) # Temporarily overrides a style variable such as `ItemSpacing` or `FramePadding`. Must be followed by `ImGui.PopStyleVar()`. When two numbers are provided, they represent a vector value.
---@field PopStyleVar fun(count?: integer) # Restores the most recently pushed style variable(s). The optional count parameter allows reverting multiple pushes at once.
---@field SetNextItemWidth fun(width: number) # Sets a fixed width for the next item (e.g., combo box, slider, or text input). Affects layout and alignment.
---@field BeginTooltip fun() # Begins creating a tooltip. Must be paired with `ImGui.EndTooltip()`.
---@field EndTooltip fun() # Ends the creation of a tooltip. Must be called after `ImGui.BeginTooltip()`.
---@field GetStyle fun(): ImGuiStyleVar # Returns the current ImGui style object, which contains values for UI layout, spacing, padding, rounding, and more.
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
---@field GetQuestsSystem fun(): QuestsSystem # Retrieves the Quests System, used for getting and setting quest facts.
---@field GetSettingsSystem fun(): SettingsSystem # Provides access to the global settings system used to query and modify game options.
---@field GetPlayer fun(): any # Retrieves the current player instance if available.
---@field GetMountedVehicle fun(player: any): any # Returns the vehicle the player is currently mounted in, if any.
---@field IsDriver fun(player: any): boolean # True if the player is driving a vehicle; otherwise, false.
Game = Game

---Represents available vehicle race UI events used to trigger race-related overlays or effects.
---@class vehicleRaceUI
---@field RaceStart integer # Triggered when a vehicle race begins.
---@field RaceEnd integer # Triggered when a vehicle race finishes.
vehicleRaceUI = vehicleRaceUI

---Retrieves a reference to a loaded CET mod by name.
---@class GetMod # Not a class — provided by CET.
---@field GetMod fun(name: string): table? # Returns the mod object if found, or `nil` if the mod is not loaded.
GetMod = GetMod

---Provides functionality to observe game events, allowing custom functions to be executed when certain events occur.
---@class Observe # Not a class — provided by CET.
---@field Observe fun(className: string, functionName: string, callback: fun(...)) # Sets up an observer for a specified function within the game.
Observe = Observe

---Allows the registration of functions to be executed when certain game events occur, such as initialization or shutdown.
---@class registerForEvent # Not a class — provided by CET.
---@field registerForEvent fun(eventName: string, callback: fun(...)) # Registers a callback function for a specified event (e.g., `onInit`, `onIsDefault`).
registerForEvent = registerForEvent

---Allows the registration of custom keyboard shortcuts that trigger specific Lua functions.
---@class registerHotkey # Not a class — provided by CET.
---@field registerHotkey fun(id: string, label: string, callback: fun()) # Registers a hotkey with a unique identifier, a descriptive label shown in CET's Hotkey menu, and a callback function to execute when pressed.
registerHotkey = registerHotkey

---Allows the registration of input bindings that respond to key press and release events.
---@class registerInput # Not a class — provided by CET.
---@field registerInput fun(id: string, label: string, callback: fun(down: boolean)) # Registers an input action with a unique identifier, a descriptive label for CET’s Input menu, and a callback function that receives `true` on key press and `false` on key release.
registerInput = registerInput

---SQLite database handle.
---@class db # Not a class — provided by CET.
---@field exec fun(self: db, sql: string): boolean?, string? # Executes a SQL statement. Returns true on success, or nil and an error message.
---@field rows fun(self: db, sql: string): fun(): table # Executes a SELECT statement and returns an iterator. Each yielded row is an array (table) of column values.
db = db

---Scans a directory and returns its contents.
---@class dir # Not a class — provided by CET.
---@field dir fun(path: string): table # Returns a list of file/folder entries in the specified directory. Each entry is a table with at least a `name` field.
dir = dir

---Provides functions for encoding tables to JSON strings and decoding JSON strings to Lua tables.
---@class json
---@field encode fun(value: any): string # Converts a Lua table or value to a JSON-formatted string. Returns a string representation of the data.
---@field decode fun(jsonString: string): table # Converts a JSON-formatted string to a Lua table. Returns the parsed table if successful, or nil if the parsing fails.
json = json
