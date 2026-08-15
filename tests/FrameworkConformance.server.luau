--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Matter = require(ReplicatedStorage.Packages.Matter)
local ECSR = ReplicatedStorage.ECSR

local Components = require(ECSR.Components)
local Contribution = require(ECSR.Components.Contribution)
local ObservationCleanupSystem = require(ECSR.Systems.ObservationCleanupSystem)
local CompositionRule = require(ECSR.Rules.CompositionRule)
local FrameworkRule = require(ECSR.Rules.FrameworkRule)
local NumericRule = require(ECSR.Rules.NumericRule)
local PhaseRule = require(ECSR.Rules.PhaseRule)
local TransactionRule = require(ECSR.Rules.TransactionRule)

local C = Components.define(Matter, { "Value", "Bag" })
assert(C.StateRoot ~= nil and C.Observation ~= nil, "protocol Components were not defined")
assert(C.Value ~= nil and table.isfrozen(C), "domain Components were not closed into an immutable registry")

local reservedAccepted = pcall(function()
	Components.define(Matter, { "StateRoot" })
end)
assert(not reservedAccepted, "applications must not redefine protocol Components")

local function initial(value: number)
	return {
		root = {
			C.Value({ amount = value }),
			C.Bag({ values = {} }),
			C.EvolutionTrace({ entries = {}, maxEntries = 16 }),
			C.ObservationJournal({ nextSequence = 1, entries = {}, maxEntries = 16 }),
		},
		entities = {},
	}
end

local duplicateSystem = {
	name = "DuplicateSystem",
	evaluate = function(_view, _emit) end,
}
local duplicateScheduleAccepted = pcall(function()
	PhaseRule.new({
		{ name = "first", systems = { duplicateSystem } },
		{ name = "second", systems = { duplicateSystem } },
	})
end)
assert(not duplicateScheduleAccepted, "PhaseRule must reject duplicate System scheduling")

local closedComposition = CompositionRule.new({}, TransactionRule)
local unknownAccepted = pcall(function()
	closedComposition.compose({ Contribution.of("Unknown", "Probe", { value = 1 }) })
end)
assert(not unknownAccepted, "unregistered Contribution kinds must be rejected")

local invalidAtomicSystem = {
	name = "InvalidAtomicSystem",
	evaluate = function(view, emit)
		assert(view.world == nil and view.insert == nil, "System received a write capability")
		emit(Contribution.transaction("InvalidAtomicSystem", {
			label = "RejectWholeTransition",
			effects = {
				Contribution.insert(1, { C.Value({ amount = 99 }) }),
				Contribution.mapSet(999999, C.Bag, "values", "invalid", 1),
			},
		}))
	end,
}
local atomicEvolution = FrameworkRule.new(Matter, C, {
	initial = initial(0),
	phases = { { name = "atomic", systems = { invalidAtomicSystem }, advanceTick = true } },
})
local atomicAccepted = pcall(function()
	atomicEvolution:step()
end)
assert(not atomicAccepted, "invalid total Contribution must fail")
assert(atomicEvolution:view():get(1, C.Value).amount == 0, "failed transition leaked a partial write")
assert(atomicEvolution:view():get(1, C.StateRoot).tick == 0, "failed transition advanced logical time")

local VectorRule = {
	kind = "VectorProbe",
	resolve = function(contributions)
		local total = 0
		for _, contribution in ipairs(contributions) do
			total += contribution.value
		end
		return {
			Contribution.transaction("VectorProbeRule", {
				label = "MaterializeVectorProbe",
				effects = { Contribution.insert(1, { C.Value({ amount = total }) }) },
			}),
		}
	end,
}
local vectorSystem = {
	name = "VectorProbeSystem",
	evaluate = function(_view, emit)
		emit(Contribution.of("VectorProbe", "A", { value = 2, orderKey = "a" }))
		emit(Contribution.of("VectorProbe", "B", { value = 3, orderKey = "b" }))
	end,
}
local extensionEvolution = FrameworkRule.new(Matter, C, {
	initial = initial(0),
	contributionRules = { VectorRule },
	phases = { { name = "extension", systems = { vectorSystem }, advanceTick = true } },
})
extensionEvolution:step()
assert(extensionEvolution:view():get(1, C.Value).amount == 5, "custom Composition Rule did not materialize C*")

local numericSystem = {
	name = "NumericSystem",
	evaluate = function(view, emit)
		local current = view:get(1, C.Value).amount
		emit(Contribution.numeric("NumericSystem", {
			channel = "value:1",
			mode = "add",
			value = 4,
			initial = current,
			materialize = function(value)
				return {
					label = "MaterializeValue",
					effects = { Contribution.insert(1, { C.Value({ amount = value }) }) },
				}
			end,
		}))
	end,
}
local implicitNumericEvolution = FrameworkRule.new(Matter, C, {
	initial = initial(1),
	phases = { { name = "implicit", systems = { numericSystem } } },
})
local implicitNumericAccepted = pcall(function()
	implicitNumericEvolution:step()
end)
assert(not implicitNumericAccepted, "FrameworkRule must not silently select NumericRule")
assert(implicitNumericEvolution:view():get(1, C.Value).amount == 1, "rejected implicit algebra changed state")

local explicitNumericEvolution = FrameworkRule.new(Matter, C, {
	initial = initial(1),
	contributionRules = { NumericRule },
	phases = { { name = "explicit", systems = { numericSystem }, advanceTick = true } },
})
explicitNumericEvolution:step()
assert(explicitNumericEvolution:view():get(1, C.Value).amount == 5, "explicit NumericRule did not compose values")

local lowerPrioritySystem = {
	name = "LowerPrioritySystem",
	evaluate = function(_view, emit)
		emit(Contribution.transaction("LowerPrioritySystem", {
			priority = 1,
			claims = { "value:1" },
			effects = { Contribution.insert(1, { C.Value({ amount = 10 }) }) },
		}))
	end,
}
local higherPrioritySystem = {
	name = "HigherPrioritySystem",
	evaluate = function(_view, emit)
		emit(Contribution.transaction("HigherPrioritySystem", {
			priority = 10,
			claims = { "value:1" },
			effects = { Contribution.insert(1, { C.Value({ amount = 20 }) }) },
		}))
	end,
}
local conflictEvolution = FrameworkRule.new(Matter, C, {
	initial = initial(0),
	phases = { { name = "conflict", systems = { lowerPrioritySystem, higherPrioritySystem } } },
})
conflictEvolution:step()
assert(conflictEvolution:view():get(1, C.Value).amount == 20, "TransactionRule did not deterministically resolve the claim")

local cleanupEvolution = FrameworkRule.new(Matter, C, {
	initial = initial(0),
	phases = { { name = "cleanup", systems = { ObservationCleanupSystem(C) }, advanceTick = true } },
})
local observationEntity = cleanupEvolution:observe("FrameworkProbe", { nested = { value = 7 } })
local observation = cleanupEvolution:view():get(observationEntity, C.Observation)
assert(observation ~= nil and observation.sequence == 1, "Observation ingress did not create explicit state")
local payloadMutable = pcall(function()
	observation.payload.nested.value = 9
end)
assert(not payloadMutable, "Observation payload must be an immutable snapshot")
cleanupEvolution:step()
assert(not cleanupEvolution:view():contains(observationEntity), "Observation cleanup did not consume transient state")
local journal = cleanupEvolution:view():get(1, C.ObservationJournal)
assert(journal.entries[1].entity == observationEntity, "ObservationJournal lost the causal input identity")

print("[ECSRFrameworkConformance] PASS")

