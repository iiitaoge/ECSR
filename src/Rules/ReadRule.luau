--!strict

local ReadRule = {}

function ReadRule.new(world, metrics)
	local view = {}
	metrics = metrics or {}
	metrics.gets = metrics.gets or 0
	metrics.contains = metrics.contains or 0
	metrics.sizes = metrics.sizes or 0
	metrics.queries = metrics.queries or 0
	metrics.queryDriverRows = metrics.queryDriverRows or 0
	metrics.queryRows = metrics.queryRows or 0
	metrics.queryComponentReads = metrics.queryComponentReads or 0

	function view:get(entityId: number, ...)
		metrics.gets += select("#", ...)
		return world:get(entityId, ...)
	end

	function view:contains(entityId: number): boolean
		metrics.contains += 1
		return world:contains(entityId)
	end

	function view:size(): number
		metrics.sizes += 1
		return world:size()
	end

	-- Query one stable driver and fetch an arbitrary number M of Components.
	function view:query(...)
		local componentTypes = table.pack(...)
		assert(componentTypes.n > 0, "A System query needs at least one Component")
		metrics.queries += 1
		local rows = {}

		for entityId in world:query(componentTypes[1]) do
			metrics.queryDriverRows += 1
			metrics.queryComponentReads += componentTypes.n
			local values = table.pack(world:get(entityId, table.unpack(componentTypes, 1, componentTypes.n)))
			local complete = true
			for index = 1, componentTypes.n do
				if values[index] == nil then
					complete = false
					break
				end
			end
			if complete then
				local row = { entityId }
				for index = 1, componentTypes.n do
					table.insert(row, values[index])
				end
				table.insert(rows, row)
				metrics.queryRows += 1
			end
		end

		table.sort(rows, function(a, b)
			return a[1] < b[1]
		end)
		return rows
	end

	return table.freeze(view)
end

return table.freeze(ReadRule)
