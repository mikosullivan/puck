# Filesystem Access in KScript

KScript filesystem access is provided through **jail objects** — directory-scoped handles
injected by the host. A jail gives access to a specific directory tree and nothing outside
it. The underlying real path is never exposed to KScript code.

---

## The Jail

```
vibecode: {
	"section": "the_jail",
	"concept": "directory_scoped_handle_injected_by_host",
	"real_path": "never_exposed_to_kscript_code",
	"access": "%engine['name']",
	"subscript_sugar": "$jail['path'] == $jail.file('path')",
	"jail_is_directory": true
}
```

A jail is itself a directory object rooted at the injected path. All operations are
relative to that root.

```
$jail = %engine['docs']
```

The `[]` operator is a shorthand for `.file()`:

```
$jail.file('tmp/draft.txt')   # explicit
$jail['tmp/draft.txt']        # same thing
```

Because the jail is a directory object, all directory operations work directly on it:

```
$jail.files
$jail.dirs
$jail.children
$jail['readme.txt'].read
```

---

## File Objects

```
vibecode: {
	"section": "file_objects",
	"operations": ["read", "write", "append", "delete", "exists?", "name", "path",
		"size", "sha256", "copy", "move"],
	"copy_returns": "new_file_object_at_destination",
	"move_mutates": "object_path_in_place",
	"notes": ["move_is_only_operation_that_changes_objects_own_path"]
}
```

A file object holds its path relative to the jail root. All operations work from that
path alone.

```
$file = $jail['docs/readme.txt']
```

### Operations

```
$file.read              # returns file contents as a string
$file.write($data)      # overwrites the file with $data
$file.append($data)     # appends $data to the file
$file.delete            # deletes the file
$file.exists?           # returns true/false
$file.name              # filename only, no path
$file.path              # full path from jail root
$file.size              # size in bytes
$file.sha256            # SHA-256 hex digest of contents
```

### Operations that return a new file object

```
$new_file = $file.copy('other/path.txt')   # copies file; returns new file object at destination
```

### Operations that mutate the object's path

```
$file.move('new/path.txt')   # moves the file; updates $file's path in place
```

`move` is the only operation that changes the object's own path. All other operations
leave the path unchanged.

---

## Directory Objects

```
vibecode: {
	"section": "directory_objects",
	"operations": ["children", "files", "dirs", "exists?", "name", "path",
		"create", "delete"],
	"subscript": "$dir['name'] returns file or directory object based_on_what_exists",
	"lazy": "object_created_without_hitting_filesystem_failure_on_actual_operation",
	"chaining": "$jail.dir('a').dir('b')['file.txt'].read"
}
```

A directory object holds its path relative to the jail root.

```
$dir = $jail.dir('docs/shakespeare')
```

### Operations

```
$dir.children            # all entries — files and directories
$dir.files               # file objects only
$dir.dirs                # directory objects only
$dir.exists?             # returns true/false
$dir.name                # directory name only, no path
$dir.path                # full path from jail root
$dir.create              # creates the directory
$dir.delete              # deletes the directory
```

### Navigating

```
$dir['hamlet.txt']       # returns a file object
$dir['subdir']           # returns a directory object
```

`[]` returns the appropriate type based on what exists at that path. It is lazy — the
object is created without hitting the filesystem; failure occurs on the actual operation.

Directories can be chained:

```
$text = $jail.dir('docs').dir('shakespeare')['hamlet.txt'].read
```

---

## Iteration

```
vibecode: {
	"section": "iteration",
	"iterables": ["children", "files", "dirs"],
	"pattern": "$dir.X.each do($item) end"
}
```

```
$dir.children.each do($child)
    puts($child.name)
end

$dir.files.each do($file)
    puts($file.path)
end

$dir.dirs.each do($dir)
    puts($dir.name)
end
```

---

## Notes

```
vibecode: {
	"section": "notes",
	"path_restriction": "relative_to_jail_root_only",
	"rejected": ["absolute_paths", "dotdot_traversal"],
	"api_status": "basics_covered_more_may_be_added"
}
```

- All paths are relative to the jail root. Absolute paths and `..` traversal are rejected
  by the runtime.
- This API covers the basics. Additional features may be added later.
