-- Kore.Loader — Auto-discovery of services/controllers with dependency resolution

local Log = require(script.Parent.Log)
local Types = require(script.Parent.Types)

type NamedModule = Types.NamedModule

local Loader = {}

--- Topological sort using Kahn's algorithm with cycle detection.
--- Returns modules in dependency-first order.
function Loader.TopologicalSort(modules: { NamedModule }): { NamedModule }
	local nameToModule: { [string]: NamedModule } = {}
	local inDegree: { [string]: number } = {}
	local adjacency: { [string]: { string } } = {}
	local allNames: { string } = {}

	for _, mod in ipairs(modules) do
		local name: string = mod.Name
		nameToModule[name] = mod
		inDegree[name] = 0
		adjacency[name] = {}
		table.insert(allNames, name)
	end

	-- Build edges from dependencies
	for _, mod in ipairs(modules) do
		local deps: { string }? = mod.Dependencies
		if deps then
			for _, depName in ipairs(deps) do
				if not nameToModule[depName] then
					Log.Warn("Kore", "'%s' declares dependency '%s' which is not registered", mod.Name, depName)
					continue
				end
				table.insert(adjacency[depName], mod.Name)
				inDegree[mod.Name] = inDegree[mod.Name] + 1
			end
		end
	end

	-- Kahn's algorithm
	local queue: { string } = {}
	for _, name in ipairs(allNames) do
		if inDegree[name] == 0 then
			table.insert(queue, name)
		end
	end

	local sorted: { NamedModule } = {}
	while #queue > 0 do
		local current: string = table.remove(queue, 1) :: string
		table.insert(sorted, nameToModule[current])

		for _, neighbor in ipairs(adjacency[current]) do
			inDegree[neighbor] = inDegree[neighbor] - 1
			if inDegree[neighbor] == 0 then
				table.insert(queue, neighbor)
			end
		end
	end

	-- Cycle detection
	if #sorted ~= #modules then
		local inCycle: { [string]: boolean } = {}
		for _, name in ipairs(allNames) do
			if inDegree[name] > 0 then
				inCycle[name] = true
			end
		end

		local cycleTrace: string = Loader._traceCycle(inCycle, modules)
		error("[Kore] Circular dependency detected:\n  " .. cycleTrace, 0)
	end

	return sorted
end

--- Trace a single cycle path for error reporting.
function Loader._traceCycle(inCycle: { [string]: boolean }, modules: { NamedModule }): string
	local nameToModule: { [string]: NamedModule } = {}
	for _, mod in ipairs(modules) do
		nameToModule[mod.Name] = mod
	end

	local startName: string? = nil
	for name in pairs(inCycle) do
		startName = name
		break
	end

	if not startName then
		return "unknown cycle"
	end

	local path: { string } = { startName :: string }
	local visited: { [string]: boolean } = { [startName :: string] = true }
	local current: string = startName :: string

	while true do
		local mod: NamedModule? = nameToModule[current]
		local nextNode: string? = nil

		if mod and mod.Dependencies then
			for _, depName in ipairs(mod.Dependencies :: { string }) do
				if inCycle[depName] then
					if visited[depName] then
						table.insert(path, depName)
						return table.concat(path, " -> ")
					end
					nextNode = depName
					break
				end
			end
		end

		if not nextNode then
			break
		end

		visited[nextNode :: string] = true
		table.insert(path, nextNode :: string)
		current = nextNode :: string
	end

	return table.concat(path, " -> ")
end

--- Auto-discover all ModuleScripts under a given parent.
--- Each module must return a table with a `Name` field.
function Loader.DiscoverModules(parent: Instance): { NamedModule }
	local modules: { NamedModule } = {}

	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("ModuleScript") then
			local ok, result = pcall(require, child)
			if ok and type(result) == "table" then
				if result.Name then
					-- Validate name matches filename
					if result.Name ~= child.Name then
						Log.Warn(
							"Kore",
							"'%s' has Name = '%s' which does not match its filename",
							child.Name,
							result.Name
						)
					end
					table.insert(modules, result)
				else
					Log.Warn("Kore", "Module '%s' is missing a Name field", child.Name)
				end
			elseif not ok then
				Log.ErrorNoThrow("Kore", "Failed to require '%s': %s", child.Name, tostring(result))
			end
		end
	end

	return modules
end

return Loader :: Types.LoaderModule
