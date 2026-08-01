-- Kore.Net.Middleware — Per-remote middleware pipeline

local Types = require(script.Parent.Parent.Types)

local Middleware = {}

--- Run the inbound middleware pipeline for an incoming remote call.
--- Returns (pass: boolean, ...: any). If `pass` is false, the call is dropped.
function Middleware.RunInbound(middlewareDef: Types.MiddlewareDef?, player: Player, ...: any): (boolean, ...any)
	if not middlewareDef or not (middlewareDef :: Types.MiddlewareDef).Inbound then
		return true, ...
	end

	local result: { [number]: any, n: number } =
		table.pack((middlewareDef :: Types.MiddlewareDef).Inbound :: any)(player, ...)
	if result.n == 0 then
		-- Returning nothing drops the call
		return false
	end

	return true, table.unpack(result, 1, result.n)
end

--- Run the outbound middleware pipeline on the result before sending to the client.
function Middleware.RunOutbound(middlewareDef: Types.MiddlewareDef?, player: Player, result: any): any
	if not middlewareDef or not (middlewareDef :: Types.MiddlewareDef).Outbound then
		return result
	end

	return ((middlewareDef :: Types.MiddlewareDef).Outbound :: any)(player, result)
end

return Middleware
