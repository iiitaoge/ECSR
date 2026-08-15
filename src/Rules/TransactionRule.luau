--!strict

local StableRule = require(script.Parent.StableRule)

local TransactionRule = {}
TransactionRule.kind = "Transaction"

local function stableClaims(claims)
	local result = table.clone(claims or {})
	table.sort(result, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return result
end

function TransactionRule.resolve(transactions)
	StableRule.sort(transactions)
	local claimed = {}
	local resolved = {}

	for _, transaction in ipairs(transactions) do
		local claims = stableClaims(transaction.claims)
		local conflict = false
		for _, claim in ipairs(claims) do
			if claimed[claim] then
				conflict = true
				break
			end
		end

		if not conflict then
			for _, claim in ipairs(claims) do
				claimed[claim] = true
			end
		end

		table.insert(resolved, {
			kind = "Resolved",
			source = transaction.source,
			phase = transaction.phase,
			priority = transaction.priority,
			orderKey = transaction.orderKey,
			channel = transaction.channel,
			label = transaction.label,
			accepted = if conflict then false else transaction.accepted ~= false,
			conflict = conflict,
			claims = claims,
			effects = if conflict then transaction.conflictEffects else transaction.effects,
		})
	end

	return resolved
end

return table.freeze(TransactionRule)
