--!strict

local Dependencies = {}

local function findModuleRelative(name: string): ModuleScript?
	local packageRoot = script.Parent
	local cursor: Instance? = packageRoot and packageRoot.Parent or nil

	while cursor do
		local direct = cursor:FindFirstChild(name)
		if direct and direct:IsA("ModuleScript") and not direct:IsDescendantOf(packageRoot) then
			return direct
		end

		local packages = cursor:FindFirstChild("Packages")
		if packages then
			local packageModule = packages:FindFirstChild(name)
			if
				packageModule
				and packageModule:IsA("ModuleScript")
				and not packageModule:IsDescendantOf(packageRoot)
			then
				return packageModule
			end
		end

		cursor = cursor.Parent
	end

	return nil
end

function Dependencies.require(name: string): any?
	local moduleScript = findModuleRelative(name)
	if moduleScript then
		local ok, value = pcall(require, moduleScript)
		if ok then
			return value
		end

		warn(("[Unithub] Failed to require dependency %s: %s"):format(name, tostring(value)))
	end

	return nil
end

return Dependencies
