--!strict
--[[
	BuiltInTypes — every built-in argument type, grouped by family.

	`handles` is the record exposed as `Kmdr.types` (each handle keeps its
	precise payload type for ArgsOf derivation); `all` is the erased flat list
	the realm singletons feed to `registry.registerType`.
]]

local Colors = require(script.Colors)
local Duration = require(script.Duration)
local Misc = require(script.Misc)
local PlayerTypes = require(script.PlayerTypes)
local Primitives = require(script.Primitives)
local TeamTypes = require(script.TeamTypes)
local Vectors = require(script.Vectors)

local handles = {
	string = Primitives.string,
	strings = Primitives.strings,
	text = Primitives.text,
	number = Primitives.number,
	numbers = Primitives.numbers,
	integer = Primitives.integer,
	integers = Primitives.integers,
	boolean = Primitives.boolean,
	booleans = Primitives.booleans,
	player = PlayerTypes.player,
	players = PlayerTypes.players,
	playerId = PlayerTypes.playerId,
	playerIds = PlayerTypes.playerIds,
	team = TeamTypes.team,
	teams = TeamTypes.teams,
	teamPlayers = TeamTypes.teamPlayers,
	color3 = Colors.color3,
	color3s = Colors.color3s,
	brickColor = Colors.brickColor,
	brickColors = Colors.brickColors,
	vector2 = Vectors.vector2,
	vector2s = Vectors.vector2s,
	vector3 = Vectors.vector3,
	vector3s = Vectors.vector3s,
	positionVector3 = Vectors.positionVector3,
	duration = Duration.duration,
	durations = Duration.durations,
	userInput = Misc.userInput,
	command = Misc.command,
	typeName = Misc.typeName,
	url = Misc.url,
	json = Misc.json,
}

-- Erased on purpose: the handles all carry different payload types.
local all: { any } = {
	handles.string,
	handles.strings,
	handles.text,
	handles.number,
	handles.numbers,
	handles.integer,
	handles.integers,
	handles.boolean,
	handles.booleans,
	handles.player,
	handles.players,
	handles.playerId,
	handles.playerIds,
	handles.team,
	handles.teams,
	handles.teamPlayers,
	handles.color3,
	handles.color3s,
	handles.brickColor,
	handles.brickColors,
	handles.vector2,
	handles.vector2s,
	handles.vector3,
	handles.vector3s,
	handles.positionVector3,
	handles.duration,
	handles.durations,
	handles.userInput,
	handles.command,
	handles.typeName,
	handles.url,
	handles.json,
}

return {
	handles = handles,
	all = all,
}
