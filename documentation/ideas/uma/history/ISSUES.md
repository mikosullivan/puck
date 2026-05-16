# Issues

## Open issues (Gaila)

### Expand Canonical Tag Coverage To Match Runtime Spec
- opened: 2026-04-02
- level: high

`lib/uma/canon.json` currently defines only a subset of tags in `tags`. A direct comparison against `lib/uma/tags.json` shows 70 tags present in the runtime spec but not represented as canonical tag definitions (examples: `article`, `section`, `nav`, `figure`, `figcaption`, `fieldset`, `label`, `audio`, `video`, `source`, `track`, `template`, `style`, `noscript`, `dl`, `dt`, `dd`, `ruby`, `rp`, `slot`).

Concern: the normalized source of truth cannot fully regenerate the runtime tag surface without additional canonical tag entries or canonical rule sources for these tags.

### Correct Canonical Document-Structure Rules For Root Tags
- opened: 2026-04-02
- level: high

`lib/uma/canon.json` models `html.children` as `body`, `link`, `meta`, `title`, and `script`, but does not include `head`. In HTML5, metadata elements (`link`, `meta`, `title`, `script` in this context) belong in `head`, not directly under `html`.

Concern: denormalization from canon can produce structurally invalid parent/child rules unless the root/head model is corrected and expanded.

### Add Canonical Metadata For Missing Attribute Semantics
- opened: 2026-04-02
- level: medium

The canonical file includes reusable attribute groups (`default`, `remote`, `form-fields`) but omits many tag-specific attributes that exist in `lib/uma/tags.json` (examples: `input.accept/min/max/step`, `textarea.wrap`, `select.multiple/disabled`, `table.border/summary`, media attributes like `video.poster`, `audio.controls`, and head metadata attributes like `meta.name/content/http-equiv`).

Concern: canon does not yet capture enough normalized attribute semantics to reliably regenerate the richer runtime schema for many HTML5 elements.


### Encode More HTML5 Content-Model Constraints In Canon
- opened: 2026-04-02
- level: medium

Current canonical sources (`blocks`, `inlines`, `most-inlines`, `list-items`, etc.) are useful but broad. They do not yet encode several important HTML5 constraints, such as specialized groups and restrictions for:
- table internals (`caption`, `colgroup`, sectioning and row/cell ordering nuances)
- form composition (`fieldset`/`legend`, `label` constraints, `optgroup` in `select`)
- interactive-content nesting restrictions and other invalid descendant combinations

Concern: without these constraints in canon, denormalization may over-permit invalid structures or under-specify valid ones.

