local Server = script.Parent.Parent

local EmployeeService = require(Server.Services.EmployeeService)

local Maximum = 25

return function(_Context, Amount: number, Type: string?): string
	if Amount < 1 or Amount > Maximum then
		return `Amount has to be between 1 and {Maximum}.`
	end

	local Lines = {}

	for _ = 1, Amount do
		local Employee = EmployeeService:RollEmployee(nil, Type)

		EmployeeService:NewEmployee(Employee)
		table.insert(Lines, EmployeeService:Describe(Employee))
	end

	return `Spawned {#Lines}:\n` .. table.concat(Lines, "\n")
end
