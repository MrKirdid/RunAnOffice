-- Kore.Util — Re-exports Table, String, Math sub-modules

local Types = require(script.Parent.Types)

local Util: Types.UtilModule = {
	Table = require(script.Table) :: Types.TableUtil,
	String = require(script.String) :: Types.StringUtil,
	Math = require(script.Math) :: Types.MathUtil,
}

return Util
