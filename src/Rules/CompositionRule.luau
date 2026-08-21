--!strict

local StableRule = require(script.Parent.StableRule)

local CompositionRule = {}

export type Rule = {
	compose: (contributions: { any }) -> { any },
}

-- Pure configurable ⊗: registered Rules receive only Contributions and never X_t.
function CompositionRule.new(contributionRules: { any }, transactionRule: any): Rule
	assert(type(contributionRules) == "table", "CompositionRule needs Contribution Rules")
	assert(type(transactionRule) == "table" and transactionRule.kind == "Transaction", "CompositionRule needs a Transaction terminal Rule")
	assert(type(transactionRule.resolve) == "function", "Transaction Rule needs resolve")

	local orderedRules: { any } = {}
	local byKind: { [string]: any } = {}
	for ruleIndex, rule in ipairs(contributionRules) do
		assert(type(rule) == "table", string.format("Contribution Rule %d is invalid", ruleIndex))
		assert(type(rule.kind) == "string" and rule.kind ~= "" and rule.kind ~= "Transaction", "Contribution Rule needs a unique non-Transaction kind")
		assert(type(rule.resolve) == "function", string.format("Contribution Rule %s needs resolve", rule.kind))
		assert(byKind[rule.kind] == nil, string.format("Contribution kind %s has more than one Rule", rule.kind))
		byKind[rule.kind] = rule
		table.insert(orderedRules, rule)
	end
	table.freeze(orderedRules)

	local function compose(contributions: { any }): { any }
		assert(type(contributions) == "table", "CompositionRule.compose needs Contributions")
		local orderedContributions = table.clone(contributions)
		StableRule.sort(orderedContributions)
		local buckets: { [string]: { any } } = {}
		local transactions: { any } = {}

		for _, contribution in ipairs(orderedContributions) do
			assert(type(contribution) == "table" and type(contribution.kind) == "string", "System emitted an invalid Contribution")
			if contribution.kind == transactionRule.kind then
				table.insert(transactions, contribution)
			else
				local rule = byKind[contribution.kind]
				assert(rule ~= nil, string.format("No Composition Rule registered for Contribution kind %s", tostring(contribution.kind)))
				local bucket = buckets[contribution.kind]
				if bucket == nil then
					bucket = {}
					buckets[contribution.kind] = bucket
				end
				table.insert(bucket, contribution)
			end
		end

		for _, rule in ipairs(orderedRules) do
			local bucket = buckets[rule.kind]
			if bucket ~= nil then
				local materialized = rule.resolve(bucket)
				assert(type(materialized) == "table", string.format("Composition Rule %s did not return Transactions", rule.kind))
				for _, transaction in ipairs(materialized) do
					assert(type(transaction) == "table" and transaction.kind == transactionRule.kind, string.format("Composition Rule %s emitted a non-Transaction", rule.kind))
					table.insert(transactions, transaction)
				end
			end
		end

		return transactionRule.resolve(transactions)
	end

	return table.freeze({ compose = compose })
end

return table.freeze(CompositionRule)
