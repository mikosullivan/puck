/*
 * caspian — CLI entry point.
 *
 * V0 hello-world: embeds a Lua 5.4 interpreter statically and runs a
 * one-line "Hello world". Future versions will load the on-disk engine
 * (~/.local/share/caspian/lua/engine.lua) via require('engine') and
 * invoke it against the source file argv[1] names.
 */

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

int main(int argc, char *argv[]) {
	lua_State *L = luaL_newstate();
	luaL_openlibs(L);
	luaL_dostring(L, "print('Hello world')");
	lua_close(L);
	return 0;
}
