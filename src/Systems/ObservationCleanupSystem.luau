--!strict

local ECSR = script.Parent.Parent
local Contribution = require(ECSR.Components.Contribution)
local StableRule = require(ECSR.Rules.StableRule)

-- Generic lifecycle only: interpreting an Observation belongs to application
-- Systems. This final System merely removes observations after every interested
-- System has read the same snapshot.
return function(C)
	return {
		name = "ObservationCleanupSystem",
		evaluate = function(view, emit)
			for _, row in ipairs(view:query(C.Observation)) do
				local observationEntity = row[1]
				emit(Contribution.transaction("ObservationCleanupSystem", {
					phase = 100,
					orderKey = StableRule.entityKey(observationEntity),
					label = "ConsumeObservation",
					claims = { "observation:" .. tostring(observationEntity) },
					effects = { Contribution.despawn(observationEntity) },
				}))
			end
		end,
	}
end

