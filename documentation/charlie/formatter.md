# Charlie Formatter

<a id="philosophy"></a>
## 1 Philosophy

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

<a id="cli"></a>
## 2 CLI

```
vibecode: {
	"section": "cli",
	"command": "charlie fmt",
	"in_place": true,
	"glob_support": true,
	"check_flag": "--check exits_nonzero_if_not_matching_personal_style"
}
```

```
charlie fmt file.charlie
```

Formats `file.charlie` in place using your personal style configuration. With no config,
the formatter applies a reasonable default style.

```
charlie fmt *.charlie
```

Formats multiple files.

```
charlie fmt --check file.charlie
```

Exits non-zero if the file does not match your personal style. Useful for pre-save hooks.

---

<a id="style-configuration"></a>
## 3 Style Configuration

```
vibecode: {
	"section": "style_configuration",
	"config_file": "~/.config/charlie/style.toml",
	"scope": "personal_not_project",
	"status": "exact_options_defined_as_formatter_is_implemented"
}
```

Personal style lives in `~/.config/charlie/style.toml`. Example:

```toml
indent = "spaces"
indent_size = 4
max_line_length = 100
```

The exact set of configurable options will be defined as the formatter is implemented.

---

<a id="vs-code-integration"></a>
## 4 VS Code Integration

```
vibecode: {
	"section": "vscode_integration",
	"features": ["format_on_save", "format_document_ShiftAltF"],
	"file_extension": ".charlie",
	"config_source": "~/.config/charlie/style.toml",
	"project_settings_needed": false
}
```

The Charlie VS Code extension integrates the formatter directly:

- **Format on save** — automatically applies your personal style when you save a `.charlie` file
- **Format Document** (`Shift+Alt+F`) — formats the current file on demand

The extension reads your `~/.config/charlie/style.toml` for its style settings. No
project-level VS Code settings are needed.

---

<a id="tooling-roadmap"></a>
## 5 Tooling Roadmap

```
vibecode: {
	"section": "tooling_roadmap",
	"tools": ["charlie fmt", "vscode_format_on_save", "charlie lint"],
	"lint_status": "optional_separate_from_formatting"
}
```

| Tool | Description |
|---|---|
| `charlie fmt` | Personal formatter |
| VS Code format-on-save | Calls `charlie fmt` on save |
| `charlie lint` | Optional linter (separate from formatting) |
