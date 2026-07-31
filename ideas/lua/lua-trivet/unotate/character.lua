#!/usr/bin/env lua5.4

local script_dir = arg[0]:match('(.*/)') or './'
local repo_root = script_dir .. '../../../../'
package.path = repo_root .. 'code/lua/?.lua;' .. script_dir .. '?.lua;' .. package.path

local trivet = require('trivet')
local unotate = require('unotate')

local target = arg[1]

if not target then
	io.stderr:write('usage: character.lua <character-name>\n')
	os.exit(1)
end

local ROMAN = {'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'}

local function to_roman(idx)
	local n = tonumber(idx)
	return n and ROMAN[n] or idx
end

local plays = unotate.load_plays()

local corpus = trivet.new({kind = 'corpus'})

for _, play in ipairs(plays) do
	local play_node = corpus:create_child(play)

	for _, act in ipairs(play.acts) do
		local act_node = play_node:create_child(act)

		for _, scene in ipairs(act.scenes) do
			local scene_node = act_node:create_child(scene)

			for _, character in ipairs(scene.characters or {}) do
				scene_node:create_child(character)
			end
		end
	end
end

local matches = {}

for node in corpus:descendants() do
	if type(node.value) == 'table' and node.value.name == target then
		table.insert(matches, node)
	end
end

if #matches == 0 then
	io.stderr:write('No scenes found for character: ' .. target .. '\n')
	os.exit(1)
end

local current_play = nil
local current_act = nil

for _, char_node in ipairs(matches) do
	local scene = char_node.parent.value
	local act = char_node.parent.parent.value
	local play = char_node.parent.parent.parent.value

	if play ~= current_play then
		print(play.title)
		current_play = play
		current_act = nil
	end

	if act ~= current_act then
		print('\tAct ' .. to_roman(act.index))
		current_act = act
	end

	print('\t\tScene ' .. scene.index .. ': ' .. scene.location)
end

return
