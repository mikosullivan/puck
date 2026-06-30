# `%engine.dir`
<!--index: 4 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_engine_dir",
	"role": "spec for %engine.dir — the directory the program is running in (the host's notion of working directory at engine start)"
}}
~~~

`%engine.dir` is the directory the program is running in — the host's notion of the working directory at the moment the engine was created. It's a string, holding an absolute path.

`%engine.dir` is a snapshot: changing the host process's working directory after the engine starts does not change what `%engine.dir` returns. If a program needs to know where the host now is, it asks the host explicitly; `%engine.dir` remembers where things started.

Relative file paths handed to other engine slots (or to libraries that work with the filesystem) are typically resolved against `%engine.dir` unless a doc says otherwise.
