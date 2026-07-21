local path = assert(arg[1], "Lua source path is required")
assert(loadfile(path))
io.write("LUA_OK\n")
