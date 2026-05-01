# KScript Formatter

## Philosophy

```
vibecode: {
	"section": "philosophy",
	"model": "personal_formatter_not_team_policy",
	"no_canonical_style": true,
	"no_project_level_config": true,
	"social_contract": "run_formatter_before_complaining_about_formatting"
}
```

Formatting is a personal view, not a shared contract. Code is written and shared however
the author wrote it. When you receive someone else's code and want it formatted
differently, run it through your own formatter.

There is no canonical style. There is no project-level style config. You don't have to
settle the tabs vs. spaces debate. The formatter is a personal tool for reading and
writing, not a team policy.

The social contract is one rule: **run the formatter before complaining about formatting**.
If someone's code bothers you, format it to your taste before forming an opinion.

---

## CLI

```
vibecode: {
	"section": "cli",
	"command": "kscript fmt",
	"in_place": true,
	"glob_support": true,
	"check_flag": "--check exits_nonzero_if_not_matching_personal_style"
}
```

```
kscript fmt file.dc
```

Formats `file.dc` in place using your personal style configuration. With no config,
the formatter applies a reasonable default style.

```
kscript fmt *.dc
```

Formats multiple files.

```
kscript fmt --check file.dc
```

Exits non-zero if the file does not match your personal style. Useful for pre-save hooks.

---

## Style Configuration

```
vibecode: {
	"section": "style_configuration",
	"config_file": "~/.config/kscript/style.toml",
	"scope": "personal_not_project",
	"status": "exact_options_defined_as_formatter_is_implemented"
}
```

Personal style lives in `~/.config/kscript/style.toml`. Example:

```toml
indent = "spaces"
indent_size = 4
max_line_length = 100
```

The exact set of configurable options will be defined as the formatter is implemented.

---

## VS Code Integration

```
vibecode: {
	"section": "vscode_integration",
	"features": ["format_on_save", "format_document_ShiftAltF"],
	"file_extension": ".dc",
	"config_source": "~/.config/kscript/style.toml",
	"project_settings_needed": false
}
```

The KScript VS Code extension integrates the formatter directly:

- **Format on save** — automatically applies your personal style when you save a `.dc` file
- **Format Document** (`Shift+Alt+F`) — formats the current file on demand

The extension reads your `~/.config/kscript/style.toml` for its style settings. No
project-level VS Code settings are needed.

---

## Tooling Roadmap

```
vibecode: {
	"section": "tooling_roadmap",
	"tools": ["kscript fmt", "vscode_format_on_save", "kscript lint"],
	"lint_status": "optional_separate_from_formatting"
}
```

| Tool | Description |
|---|---|
| `kscript fmt` | Personal formatter |
| VS Code format-on-save | Calls `kscript fmt` on save |
| `kscript lint` | Optional linter (separate from formatting) |
