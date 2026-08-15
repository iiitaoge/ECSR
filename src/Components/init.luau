--!strict

local Components = {}

local PROTOCOL_NAMES = table.freeze({
	"StateRoot",
	"EvolutionTrace",
	"ObservationJournal",
	"Observation",
})

local RESERVED = {}
for _, name in ipairs(PROTOCOL_NAMES) do
	RESERVED[name] = true
end
table.freeze(RESERVED)

-- Component identity must be created from the consumer's single Matter
-- instance. This factory closes the ECSR protocol Components together with
-- the application's domain Components into one immutable registry.
function Components.define(matter, domainNames)
	assert(type(matter) == "table" and type(matter.component) == "function", "Components.define needs Matter")
	domainNames = domainNames or {}
	assert(type(domainNames) == "table", "Components.define needs an array of domain Component names")

	local registry = {}
	for _, name in ipairs(PROTOCOL_NAMES) do
		registry[name] = matter.component(name)
	end

	local seen = {}
	for index, name in ipairs(domainNames) do
		assert(type(name) == "string" and name ~= "", string.format("Domain Component %d needs a name", index))
		assert(not RESERVED[name], string.format("Component %s is owned by the ECSR protocol", name))
		assert(not seen[name], string.format("Domain Component %s is declared more than once", name))
		seen[name] = true
		registry[name] = matter.component(name)
	end

	return table.freeze(registry)
end

function Components.protocolNames()
	return PROTOCOL_NAMES
end

return table.freeze(Components)

