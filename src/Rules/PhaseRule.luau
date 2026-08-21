--!strict

local PhaseRule = {}

export type System = {
	name: string,
	evaluate: any,
}

export type Definition = {
	name: string,
	systems: { System },
	advanceTick: boolean?,
}

export type Phase = {
	name: string,
	systems: { System },
	advanceTick: boolean,
}

export type Rule = {
	phases: () -> { Phase },
}

local function normalizeSystem(system: System, phaseName: string, seenSystems: { [string]: boolean }): System
	assert(type(system) == "table", string.format("Phase %s contains a non-System value", phaseName))
	assert(type(system.name) == "string" and system.name ~= "", string.format("Phase %s has a System without a name", phaseName))
	assert(type(system.evaluate) == "function", string.format("System %s has no evaluate(view, emit)", system.name))
	assert(not seenSystems[system.name], string.format("System %s is scheduled more than once", system.name))
	seenSystems[system.name] = true
	return table.freeze({
		name = system.name,
		evaluate = system.evaluate,
	})
end

-- A Phase Rule is immutable law, not mutable world state. Every phase is one
-- complete X -> Systems -> Compose -> State Update transition.
function PhaseRule.new(definitions: { Definition }): Rule
	assert(type(definitions) == "table" and #definitions > 0, "PhaseRule needs at least one phase")
	local seenPhases: { [string]: boolean } = {}
	local seenSystems: { [string]: boolean } = {}
	local phases: { Phase } = {}

	for phaseIndex, definition in ipairs(definitions) do
		assert(type(definition) == "table", string.format("Phase %d is not a Rule definition", phaseIndex))
		local name = definition.name
		assert(type(name) == "string" and name ~= "", string.format("Phase %d needs a name", phaseIndex))
		assert(not seenPhases[name], string.format("Phase %s is declared more than once", name))
		seenPhases[name] = true
		assert(type(definition.systems) == "table" and #definition.systems > 0, string.format("Phase %s needs at least one System", name))

		local systems = {}
		for _, system in ipairs(definition.systems) do
			table.insert(systems, normalizeSystem(system, name, seenSystems))
		end
		table.freeze(systems)
		table.insert(phases, table.freeze({
			name = name,
			systems = systems,
			advanceTick = definition.advanceTick == true,
		}))
	end

	table.freeze(phases)
	return table.freeze({
		phases = function()
			return phases
		end,
	})
end

return table.freeze(PhaseRule)
