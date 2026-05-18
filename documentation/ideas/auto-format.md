# Idea: Auto-Format on Post

~~~json
{"vibecode": {
	"doc": "auto-format",
	"role": "speculative note: platforms could auto-render Charlie code through the viewer's personal formatter so every reader sees code in their own style, treating formatting as a presentation layer",
	"key_concepts": ["per_viewer_formatting", "presentation_layer_formatting",
		"platform_integration"],
	"status": "brainstorm"
}}
~~~

When Charlie code is posted to a platform — a forum, a chat tool, a code review system,
a documentation site — the platform could automatically render it through the viewer's
personal formatter before displaying it.

The idea: code has one author style, but every reader sees it in their own style. Formatting
becomes a true presentation layer, invisible to the workflow.

This extends the formatter philosophy naturally: just as a developer runs `charlie fmt`
locally before reading someone's code, a platform could do it automatically on their behalf.

Not designed yet. Questions to answer when revisiting:

- How does the platform know the viewer's style preferences?
- Does the platform reformat on the fly, or store pre-formatted versions per user?
- How does this interact with syntax highlighting and diffs?
- Is this a platform feature or a Charlie ecosystem convention?
