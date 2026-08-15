--!strict

local CompositionRule = require(script.Parent.CompositionRule)
local EvolutionRule = require(script.Parent.EvolutionRule)
local PhaseRule = require(script.Parent.PhaseRule)
local TransactionRule = require(script.Parent.TransactionRule)

local FrameworkRule = {}

-- The only public constructor for an ECSR world. Application Rules provide
-- Components, Systems and Rule declarations; the framework closes all write,
-- ordering and composition capabilities before execution starts.
function FrameworkRule.new(matter, components, specification)
	assert(type(specification) == "table", "FrameworkRule needs an application Rule specification")
	assert(type(specification.initial) == "table", "FrameworkRule needs initial Components")

	local phaseRule = specification.phaseRule
	if phaseRule == nil then
		phaseRule = PhaseRule.new(assert(specification.phases, "FrameworkRule needs phase Rules"))
	end

	local compositionRule = specification.compositionRule
	if compositionRule == nil then
		-- No composition policy is implicit. Transaction is the terminal protocol;
		-- every other Contribution algebra must be selected by the application Rule.
		local contributionRules = specification.contributionRules or {}
		compositionRule = CompositionRule.new(contributionRules, specification.transactionRule or TransactionRule)
	end

	return EvolutionRule.new(matter, components, {
		initial = specification.initial,
		phaseRule = phaseRule,
		compositionRule = compositionRule,
	})
end

return table.freeze(FrameworkRule)
