# Dirs

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_dirs",
	"role": "spec for the dir class — Caspian's handle for a directory in the filesystem. Currently covers the .cd() method (two forms: permanent, or block-scoped with restore on exit) and the .cwd? predicate. Both are dir-object-general (available on any dir, including %fs.root and nested dirjails). The base dir-object surface (indexing, .read, .write, .each, .glob, .dirjail) is currently documented on global-methods/fs.md alongside %fs.root; that surface will migrate here as the filesystem-class docs get consolidated. First-cut home; may reorganize (e.g., under a filesystem/ subdirectory) as more filesystem-class content arrives.",
	"status": "spec — .cd() (permanent + block-scoped) and .cwd? spec'd; base dir-object methods still live on global-methods/fs.md pending migration",
	"audience": "Caspian developers working with directory handles; anyone wanting to change or query the process working directory"
}}
~~~

Dirs are Caspian's handle for a directory in the filesystem. You get one from `%fs.root`, from indexing an existing dir (`$dir['sub/path']`), from calling `.dirjail` on a dir, or from any method that returns a dir.

The base surface — indexing, `.read`, `.write`, `.each`, `.glob`, `.dirjail`, path-traversal / symlink-escape blocking, etc. — is currently spec'd on [%fs](https://puck.uno/documentation/requirements/caspian/global-methods/fs) since `%fs.root` is the primary entry point for it. That surface will migrate to this page as the filesystem-class docs get consolidated.

This page covers the methods that are **dir-object-general** — available on any dir, including `%fs.root` and any nested dirjail — as distinct from the additional methods that only exist on the `%fs` namespace (spec'd at [fs-additions](https://puck.uno/documentation/requirements/caspian/global-methods/fs-additions)).

## `.cd()`

Changes the process's current working directory to `$mydir` via `chdir(2)`. Two forms: **permanent** and **block-scoped**.

### Permanent form

~~~caspian
$mydir.cd()
~~~

Changes the process cwd and leaves it changed. Equivalent to `%fs.cwd = $mydir` on the `%fs` side.

**Returns the dir itself,** so calls can chain:

~~~caspian
$mydir.cd().glob('*.log')
~~~

### Block-scoped form

~~~caspian
$mydir.cd() do
	# process cwd is $mydir inside the block
	$file = %fs.cwd['config.json']
	&do_stuff $file
end
# cwd restored to whatever it was before .cd()
~~~

Runs the block with `$mydir` as the process cwd for the duration, then restores the previous cwd on exit — regardless of how the block exits (normal return, `raise`, exception propagating from a callee).

**Returns the block's evaluation result** — the value of the last expression in the block.

**Restore is unconditional.** If the block raises, cwd is still restored before the exception propagates.

**Nesting.** Inner `.cd() do ... end` calls form a stack; each block restores to the cwd it saw at entry:

~~~caspian
$dir_a.cd() do
	# cwd is $dir_a

	$dir_b.cd() do
		# cwd is $dir_b
	end

	# cwd is $dir_a again
end
# cwd is whatever it was originally
~~~

Direct permanent `.cd()` calls inside a `.cd() do ... end` block are overridden on block exit — the block's exit restores to the pre-block cwd regardless of what happened inside. The invariant: the block sees a controlled cwd on entry; code outside sees the original cwd on exit.

### Rules that apply to both forms

`.cd()` is user-only. See [grants](grants) for the rule and how to override it for a specific handle via `.grant(cd:true)`.

## `.cwd?`

~~~caspian
$mydir.cwd?     # => true or false
~~~

Predicate. Returns `true` if `$mydir` is currently the process cwd, `false` otherwise. Available on every dir; for most dirs the answer is always `false`.

## Related

- [%fs](https://puck.uno/documentation/requirements/caspian/global-methods/fs) — the filesystem namespace, with `%fs.root` as the root-dir accessor and the base dir-object surface (indexing, `.read`, `.write`, `.each`, `.glob`, `.dirjail`, escape blocking) currently documented there.
- [fs-additions § .cwd](https://puck.uno/documentation/requirements/caspian/global-methods/fs-additions#cwd) — the `%fs.cwd = $dir` form of setting the process cwd (property assignment on the `%fs` global; equivalent to `$dir.cd()`).
- [linux-support § Executing from a directory](https://puck.uno/documentation/requirements/caspian/linux-support/#executing-from-a-directory) — the `$dir.execute` mechanism for running executables from a dir handle.
