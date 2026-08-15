--!strict

local StableRule = {}

function StableRule.copyMap(source)
	local result = {}
	for key, value in pairs(source or {}) do
		result[key] = value
	end
	return result
end

function StableRule.sortedKeys(source)
	local keys = {}
	for key in pairs(source) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

function StableRule.entityKey(entityId: number): string
	return string.format("%016d", entityId)
end

function StableRule.less(a, b): boolean
	if (a.phase or 50) ~= (b.phase or 50) then
		return (a.phase or 50) < (b.phase or 50)
	end
	if (a.priority or 0) ~= (b.priority or 0) then
		return (a.priority or 0) > (b.priority or 0)
	end
	if tostring(a.orderKey or "") ~= tostring(b.orderKey or "") then
		return tostring(a.orderKey or "") < tostring(b.orderKey or "")
	end
	if tostring(a.source or "") ~= tostring(b.source or "") then
		return tostring(a.source or "") < tostring(b.source or "")
	end
	return (a.sequence or 0) < (b.sequence or 0)
end

function StableRule.sort(values)
	table.sort(values, StableRule.less)
	return values
end

return table.freeze(StableRule)
