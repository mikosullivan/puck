#!/usr/bin/env lua5.4

local script_dir = arg[0]:match('(.*/)') or './'
package.path = script_dir .. '../src/?.lua;' .. package.path

local trivet = require('trivet')

print(arg[1])
