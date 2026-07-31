local home = os.getenv('HOME') or '.'
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath
package.path  = home .. '/.luarocks/share/lua/5.4/?.lua;' .. package.path

local cjson = require('cjson')

local M = {}

local function script_dir()
	local src = debug.getinfo(1, 'S').source
	if src:sub(1, 1) == '@' then src = src:sub(2) end
	return src:match('(.*/)') or './'
end

function M.load_plays()
	local path = script_dir() .. 'plays.json'
	local f = assert(io.open(path, 'r'))
	local data = f:read('*a')
	f:close()
	return cjson.decode(data)
end

return M
