# Named blocks

~~~vibecode
{"vibecode": {
	"doc": "ideas_named_blocks",
	"role": "note: Miko hasn't totally given up on named-block attachments — the `~name` sigil-prefix form he adopted then killed on 2026-08-04 (see git log around commit 9097566). Not a spec, not a plan, just a placeholder so the idea doesn't drop entirely off the map.",
	"status": "parked — the removal decision stands; this file exists so the idea can be revisited later without starting from a blank page"
}}
~~~

Miko, 2026-08-05: not fully given up on named blocks yet. The shape he still likes:

~~~caspian
$foo.each do($item)
end

~bar
end

~gup
end
~~~

`~bar` and `~gup` are arbitrary named blocks that attach to the preceding call. Not tied to any specific set of loop-hook names — the general mechanism, available to any DSL that wants named attached blocks.

Nothing else committed here. Placeholder.
