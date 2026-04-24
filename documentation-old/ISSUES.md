# Issues

## Documentation Roles

Use the project docs with this time direction:

1. `documentation/VIBECODE.md` is present-facing and describes the code as it exists now.
2. `documentation/ISSUES.md` is future-facing and tracks plans, open questions, and proposed features.
3. `documentation/CHANGELOG.md` is past-facing and records concise completed changes.

## Product Open Issue

### Complete Q0 record write actions
- opened: 2026-04-06
- level: high

Q0 now supports `action: "select"` in both engines and a minimal record `action: "create"` in SQLite.

This issue tracks the remaining work to turn Q0 record writes into a complete, engine-agnostic public API for `create`, `update`, and `delete` without breaking the append-only model.

Current decisions:

1. Q0 will use separate actions: `create`, `update`, and `delete`.
2. `create` will generate the record `pk` inside the engine.
3. `update` will identify the target record by `pk` only.
4. `update` will replace the entire `bucket`.
5. `update` may change the record's class when a new class is supplied.
6. `update` does not require the class field when the class is unchanged.
7. Successful `create` and `update` responses return a normal hash with `success: true` and the affected record `pk` in `results`.
8. Expected write failures also return a normal hash, using `success: false`.
9. `create` may omit `class`. When `class` is omitted or `null`, the engine uses the tenant default class if one exists, otherwise the base class.
10. `custom_classes` is out of scope for the first write implementation.
11. The first version supports one record write per request only.
12. `delete` identifies the target record by `pk` only.
13. `delete` is append-only and works by writing a new version with `active = false`.
14. `create` writes new records as active.
15. `update` on a deleted record is prohibited.
16. `delete` on an already deleted record fails unless the request sets `if-exists: true`.
17. `delete` returns `success: true` with the record `pk` in `results`, and also includes a `deleted` boolean indicating whether a tombstone was written.
18. Failed writes return an `errors` array. Each error object has an `id` field and a `details` hash, allowing multiple errors in one response.
19. Failed write responses also include `success: false`.
20. Failed write responses omit `results`.
21. `create` requires a `bucket`.
22. `update` requires a `bucket` only when it changes the bucket; class-only updates do not require one.
23. A class-only `update` keeps the previous bucket unchanged.
24. `delete` writes a tombstone version with `active = false` and clears all business fields from that version.
25. In the first version, `create`, `update`, and `delete` each operate on only one record.
26. `create` fails with `class-not-found` when a supplied class path step does not resolve under its parent in the current tenant.
27. `update` fails with `class-not-found` when a supplied class path step does not resolve under its parent in the current tenant.
28. `update` fails if it supplies neither a new class nor a new bucket.
29. `delete` fails if the target `pk` does not exist in the current tenant, unless the request sets `if-exists: true`.
30. Q0 write requests use top-level fields rather than wrapping write details inside a nested object.
31. The first public write API allows no top-level write fields beyond `action`, `class`, `pk`, `bucket`, and delete-only `if-exists`, except that top-level `misc` and `enterprise` are always allowed and ignored by Mikobase.
32. Write behavior will be documented in `documentation/Q0.md` together with Q0 reads.
33. Successful `create` and `update` responses keep `results` minimal and return only the affected record `pk`.
34. Failed writes use error objects shaped like `{ "id": "...", "details": { ... } }`.
35. `delete` tombstones do not preserve `bucket`, `custom_classes`, or class information.
36. A deleted version stores only record identity, tenant identity, `active = false`, and engine-managed metadata.
37. Normal present-time Q0 `select` queries do not return records whose latest visible version is a delete tombstone.
38. Temporal Q0 reads using a cutoff timestamp may still return records that were active at that cutoff, even if they were deleted later.
39. `update` and strict `delete` use `record_not_found` when the target `pk` does not exist in the tenant.
40. `update` uses `record_deleted` when the target record exists historically but its latest visible version is a delete tombstone.
41. Strict `delete` also uses `record_deleted` when the target record is already deleted.
42. `delete` supports an optional top-level `if-exists` flag.
43. `if-exists` is supported only for `delete` in the first version.
44. `if-exists` defaults to `false` when omitted.
45. With `if-exists: true`, `delete` becomes idempotent: if the record is already deleted or never existed in the tenant, the request still returns success with `deleted: false`.
46. With `if-exists: true`, `deleted: true` means this request wrote the tombstone, and `deleted: false` means no tombstone was written.
47. `create` rejects `bucket: null` but allows an empty object.
48. `update` also rejects `bucket: null`.
49. Q0 request examples in the public docs use plain JSON objects rather than Ruby-specific syntax.
50. `create`, `update`, and `delete` reject unknown top-level fields.
51. Top-level `misc` and `enterprise` are permanent no-op fields on all Q0 actions, including `select`, `create`, `update`, and `delete`.
52. Top-level `misc` and `enterprise` may contain any JSON value and are always ignored by Mikobase itself.
53. Plugins may read `misc` and `enterprise`, but core Mikobase will never use them.
54. The `misc` and `enterprise` exceptions apply only at the top level of the Q0 request.
55. Request-shape validation uses `invalid_request` for missing fields, unknown fields, invalid field types, and invalid action values.
56. `invalid_request` uses one error object whose `details` hash may include `missing_fields`, `unknown_fields`, and `invalid_types` together.
57. In `invalid_request.details`, `missing_fields` and `unknown_fields` are arrays of public field names, while `invalid_types` is a hash keyed by public field name.
58. `invalid_request.details` omits keys that would otherwise be empty.
59. Public field names in `invalid_request.details` use the exact request spelling, such as `if-exists`.
60. `missing_fields`, `unknown_fields`, and `invalid_types` report all applicable request-shape problems rather than stopping at the first one.
61. Field names in request-shape validation details use a stable sorted order.
62. `invalid_types` describes type expectations by field name, for example `{"if-exists": "expected boolean"}`.
63. `action` must be a string.
64. The current valid public `action` values are `select`, `create`, `update`, and `delete`.
65. `class` and `pk` must be strings when supplied.
66. `bucket` must be a JSON object.
67. `create` requires `bucket` but does not require `class`.
68. When `create` omits `class` or receives `class: null`, the engine uses the tenant default record class if one exists, otherwise the built-in record base class.
69. The built-in record base class always exists and is not stored as a tenant-defined class.
70. Successful `create` responses remain minimal and do not report which class was used when a tenant default or the record base class is implied.
71. `update` may change a record to the built-in record base class.
72. Public docs should distinguish the record base class from the broader object root when that distinction matters.
73. `delete` requires `pk` even when `if-exists: true` is present.
74. The built-in record base class is named `mikobase.com/record`.
75. Records created without an explicit class path use the exact normalized class path `["mikobase.com/record"]`.
76. When a record changes class, the new version's class structure is recomputed from the new class path rather than merged with the old one.
77. Q0 docs should state explicitly that class matching works against the full resolved class structure, not only the leaf class.
78. A delete tombstone contributes no class structure for present-time matching.
79. For `select`, `{"action":"select"}` and `{"action":"select","class":["mikobase.com/record"]}` are exactly equivalent.
80. That equivalence also holds for historical reads at a cutoff timestamp, using the visibility snapshot at that timestamp.
81. In the public Q0 API, `class` is always an array when present, except that `class: null` is allowed and means the field is ignored.
82. In the first version, `select`, `create`, and `update` all use the same array shape for `class`.
83. `class` may be an array of zero or more strings.
84. In record-class contexts, `class: []` normalizes to the exact record base class path `["mikobase.com/record"]`.
85. The engine prepends `mikobase.com/record` to a non-null class array if it is not already present.
86. For `create`, omitted `class` and `class: null` mean use the tenant default record class if present, otherwise the record base class. `class: []` and `class: ["mikobase.com/record"]` mean the record base class explicitly.
87. For `update`, omitted `class` and `class: null` both mean no class change, while `class: []` means change the record to the record base class.
88. For `select`, omitted `class`, `class: null`, `class: []`, and `class: ["mikobase.com/record"]` are all equivalent.
89. In `invalid_request.details.invalid_types`, the `class` field should report `expected array or null` for non-array non-null values.
90. When `class` is an array, every element must be a string.
91. Array order matters; a class array is an ordered class path from broader to more specific.
92. The engine validates each adjacent class step in the supplied path rather than merely checking that all named classes exist.
93. `invalid_class_path` is used when a class array is malformed at one or more path steps.
94. Duplicate class ids in a class path are allowed if the full ordered path is valid.
95. A class id only needs to be unique within its parent class, not globally within a tenant.
96. Public docs should explain class paths as path-like traversal through the inheritance tree, where each segment is interpreted relative to its parent.
97. `mikobase.com/record` is the base class for records, not the root of every object class path.
98. An intermediate class path such as `["foo"]` names that exact class node even if deeper subclasses also exist.
99. In `select`, `class` is a prefix path filter over normalized class paths.
100. In `create` and `update`, `class` is an exact target path that must resolve to one exact class node.
101. `invalid_class_path.details` uses a `requested` array and a same-length `errors` array whose entries are `null` or stable per-step reason codes such as `not-string`, `invalid-step-name`, or `too-short`.
102. `class` arrays must not contain `null` elements.
103. Empty strings are not valid class ids.
104. Class ids must be at least one character long.
105. Class ids may contain only letters, numbers, dots, forward slashes, and underscores.
106. Class ids may not contain spaces or any space characters.
107. Error ids should identify one specific failure point and should not be reused across multiple failure modes.
108. A malformed class path step such as a non-string segment uses `invalid_class_path`, not `invalid_request`.
109. `invalid_class_path.details.errors` aligns with `invalid_class_path.details.requested` by index, so each step can report its own failure code.
110. `class-not-found` is reserved for syntactically valid class path steps that do not resolve to a child class under the current parent.
111. `class-not-found.details` should include `requested`, `valid`, and `invalid`, where `requested = valid + invalid` and `invalid` is non-empty.
112. `invalid_class_path` covers both non-string path steps and invalid step-name syntax; `class-not-found` is for missing resolved steps.
113. `request-too-large` is a recognized public Q0 error id even before request-size enforcement is implemented.
114. Future request-size enforcement is expected to be engine-configurable rather than part of core Q0 language semantics.
115. There is currently no public limit on class-path length or total request size.
116. An empty class path is always valid.
117. `["mikobase.com/record"]` is also always valid.
118. If a class path already starts with `mikobase.com/record`, validation proceeds from that explicit root exactly as written.
119. A class path that does not start with `mikobase.com/record` is normalized by prepending that root before internal resolution.
120. Normalization adds the base root only when absent and does not remove or deduplicate steps that the caller explicitly supplied.
121. The root class of all objects is `kiera.uno/object`, also called `object`.
122. There will be object classes such as `string` and `integer` that are not record classes.
123. Universal Namespace, or UNS, is Mikobase's globally unique naming style for objects and classes.
124. A UNS name is a domain name plus a short path, with `https://` implicit and omitted.
125. UNS allows globally unique class names such as `codex.com/foo` and `mikobase.com/record`.
126. `mikobase.com/record` is the base class for records only; broader object naming and class identity live under the wider object system.
127. In field and object-definition contexts, `class: []` means the immediate object base class `kiera.uno/object`.
128. Class resolution is context-sensitive: record-class contexts default under `mikobase.com/record`, while general field or object-class contexts default under `kiera.uno/object`.
129. The docs should explicitly distinguish record-class paths from field or object-class paths.
130. Built-in scalar-like classes such as `string`, `integer`, and `boolean` are object classes under `kiera.uno/object`.
131. Mikobase should do very little implicit class resolution.
132. If something is a record class, its implicit parent is `mikobase.com/record`.
133. Otherwise, its implicit parent is `kiera.uno/object`.
134. Beyond that one implicit parent step, full paths are required.
135. The one-step implicit-parent rule applies only when the class path has exactly one segment.
136. Multi-segment class paths are taken literally.
137. `class: []` means the immediate base class for the current context.
138. `null` means ignore the class field only in places where ignoring is already valid; it is not a synonym for the contextual base class.
139. Class definitions should explicitly state whether each class-valued slot is a record-class context or an object-class context.
140. The field definition itself should carry that distinction.
141. `mikobase.com/reference` is an object-class field type even though it points to records.
142. A reference field's own field object class is distinct from the referenced record class it may point to.
143. The docs should use separate terms such as field object class and referenced record class.
144. In a join field marked `left` or `right`, the field object class is `mikobase.com/reference` while the referenced record class is the allowed record-class target for that side.
145. `class-not-found.details.requested`, `valid`, and `invalid` are reported in the caller's original non-normalized path form.
146. Internal class-path resolution may normalize the path, but error reporting still uses the caller's original path coordinates.
147. `class: null` bypasses class-path validation entirely because it means the field is ignored.
148. `class: []` is guaranteed valid in the public API, but engines may choose their own internal handling strategy for that case.
149. If a class path is written as a string, it is treated as a one-element array.
150. This string shorthand applies anywhere a field means class path, including Q0 requests, class definitions, and class-target constraints.
151. Engines should normalize string class paths into arrays internally.
152. A multi-segment class path still requires the array form; a string such as `foo/bar` is one UNS step, not shorthand for multiple path segments.
153. `class: []` remains distinct from a string class path and still means the contextual base class.
154. `class: null` remains distinct from both string and array forms.
155. In declarative schema positions, `null` is invalid for class paths.
156. In operational request positions, `null` may mean ignore this class field where that behavior is explicitly supported.
157. The docs should explicitly distinguish declarative schema positions from operational request positions for class-path handling.
158. The top-level `name` in a class definition may also use string shorthand for a one-element class path.
159. In a record-class definition context, `"name": "person"` means the direct child `["mikobase.com/record", "person"]`.
160. In an object-class definition context, `"name": "string"` means the direct child `["kiera.uno/object", "string"]`.
161. A class definition should carry an explicit marker saying whether it defines a record class or an object class.
162. That marker should live on the class definition itself, near the top-level `name`.
163. The marker should use a short fixed vocabulary: `record-class` and `object-class`.
164. Class-context markers should be reserved mainly for ambiguous class-targeting fields, not for ordinary object-valued fields such as `credited_as`.
165. Q0 is named "query zero" because it is Mikobase's built-in first query language, not its only possible query language.
166. Mikobase is intended to support multiple query languages over time, including languages such as GraphQL.
167. Q0 is the built-in language that all engines can support as a common baseline.
168. Q0 defines pass-through top-level `misc` and `enterprise` fields so custom engines can carry extension metadata through the request.
169. Core storage engines such as PostgreSQL and SQLite ignore `misc` and `enterprise`.
170. Custom engines may use `misc` and `enterprise` however they want within Q0.
171. `misc` is intended for ad hoc extension metadata.
172. `enterprise` is intended for stricter organization-level metadata conventions.
173. Engines may be chained, and there may be any number of engines in a chain.
174. An engine in the chain may inspect, reject, modify, or forward a request.
175. An engine in the chain may inspect, reject, modify, or forward a response.
176. A firewall or business-rule engine may enforce custom policy independently of the storage engine.
177. The Q0 architecture is intended to provide many hooks where engines in the chain can customize the conversation.
178. Q0 reserves the public action names `transaction`, `commit`, and `rollback` even before full implementation lands.
179. `action: "transaction"` starts a new storage-engine transaction and returns a new transaction id string in `details.id`.
180. Transaction ids are storage-engine identifiers. Q0 requires only that they be strings; they do not need to be UUIDs.
181. The connection always has exactly one current transaction at a time.
182. Starting a nested transaction makes that new transaction the current transaction.
183. `commit` and `rollback` requests must supply `details.id`.
184. `transaction` does not require `details.id` in the request.
185. Missing `details.id` on `commit` or `rollback` is `invalid_request`.
186. Non-string `details.id` values on `commit` or `rollback` are `invalid_request`.
187. Unknown transaction ids use `transaction-not-found`.
188. Transaction ids invalidated by an ancestor rollback use `transaction-invalidated`.
189. A transaction id may be invalidated yet still remain known to the engine for later error reporting.
190. `commit` and `rollback` may target the current transaction or any open ancestor transaction in the current chain.
191. Q0 transaction management is intentionally not plain SQL-style transaction management.
192. In Q0, a transaction may commit and remain alive, and it may roll back and remain alive.
193. A self-commit keeps the current transaction alive and establishes a new checkpoint for that transaction.
194. A self-rollback keeps the current transaction alive and returns it to its state at its start or at its most recent commit checkpoint.
195. If `tr3` is current and the client commits ancestor `tr1`, the engine commits in descendant-first order: `tr3`, then `tr2`, then `tr1`.
196. After an ancestor commit cascade, the deepest current transaction remains current.
197. If `tr3` is current and the client rolls back ancestor `tr1`, the engine rolls back `tr1` and invalidates descendant transactions such as `tr2` and `tr3`.
198. An ancestor rollback invalidates every descendant transaction beneath the target transaction and those descendants must not be used afterward.
199. Transaction-control responses use a common success shape under `details` with `id`, `current`, and `invalidated`.
200. For `transaction`, the new transaction id appears in both `details.id` and `details.current`.
201. For `commit` and `rollback`, `details.id` is the targeted transaction id and `details.current` is the transaction that remains current afterward.
202. `commit` and `rollback` responses include an `invalidated` array listing any descendant transactions invalidated by the operation.
203. A self-commit or self-rollback returns an empty `invalidated` array.
204. Every Mikobase connection must be opened with an explicit mode. There is no default mode.
205. The only valid public mode strings are `rw`, `wr`, `r`, and `w`.
206. Mode parsing is case-insensitive.
207. Surrounding whitespace in the mode string is rejected rather than trimmed.
208. `rw` and `wr` are exactly equivalent and normalize to `rw`.
209. `r` means read-only mode.
210. `w` means write-only mode and is reserved for future support.
211. A mode string that is syntactically invalid uses `invalid-mode`.
212. A mode string that is syntactically valid but not implemented by a given engine uses `mode-not-supported`.
213. Shared engine initialization must parse and validate mode before engine-specific open work begins.
214. Engines keep semantic read/write flags rather than preserving the original mode string.
215. A connection with read and write enabled reports normalized mode `rw`.
216. A future write-only connection reports normalized mode `w`.
217. If a connection is opened read-only, state-changing Q0 actions use `read-only-connection`.
218. `read-only-connection` applies to any action that mutates state, including future actions.
219. `action-not-supported` is reserved for actions an engine or mounted context does not implement at all.
220. Mikobase open mode is part of the public engine model, while backend-specific enforcement of that mode is engine-specific.
221. If an engine accepts a requested mode, it must enforce that mode faithfully or fail to open.
222. Engines may support different subsets of the public modes, but unsupported modes must be rejected explicitly.
223. Mode support is part of an engine's declared capabilities.
224. Aggregator and adapter engines also declare their own supported open modes.
225. Mikobase supports bolting on external databases or services through engines.
226. An aggregator engine may mount multiple backends and present a consistent set of classes and records as one logical database.
227. Namespace collisions across mounted backends are handled by the engine before anything is presented to the client.
228. An aggregator may rewrite identifiers internally as needed, as long as the public view remains stable.
229. An aggregator may synthesize classes or records that do not exist verbatim in any one mounted backend, as long as the derived view is stable.
230. Writes through an aggregator are allowed only when the engine knows how to map them cleanly to underlying backends.
231. An aggregator may present some mounted backends as read-only and others as writable within one logical view.
232. Responses may include a top-level `provenance` field. Engines may omit it, and its format is engine-defined for now.
233. A Mikobase engine may present an external API or other non-database system as a virtual Mikobase database.
234. Such an adapter engine may support only part of the Mikobase model, such as read-only classes and records.
235. Unsupported actions in an engine or mounted context use `action-not-supported`.
236. Tenants may define a default class for new records, but they are not required to do so.
237. If no tenant default class exists, `create` falls back to the base class `mikobase.com/record`.
238. The tenant default class affects only `create` and does not change the meaning of `select`, `update`, or `delete`.
239. The tenant default class is represented by a boolean marker on class metadata stored in `classes_history`, not by a stored class-path array on the tenant.
240. At most one active class per tenant may be marked as the default class.
241. Marking one active class as default automatically ensures that no other active class remains default.
242. The absence of any tenant default means `create` falls back to the base class; the base class itself does not need to be marked default.
243. The default-class marker is versioned through class history rather than mutated in place.
244. Historical reads may expose which class was the default within the cutoff timestamp, even though historical connections are read-only.
245. The default-class marker should be visible in class metadata as a simple boolean.
246. Q0 will eventually include class-focused actions, including an action for changing the tenant default class.
247. Changing the tenant default class is a versioned class change.
248. Q0 will eventually include an action for renaming a class.
249. Renaming a class must not upset the internal structure or identity of existing classes.
250. Renaming a class updates descendant visible class paths while preserving underlying class identities.
251. Records in renamed classes present the new class paths after the rename while keeping the same underlying class identities.
252. Historical reads before a rename show the old class names and class paths.
253. If a class was the tenant default, renaming that class preserves its default status through the same underlying class identity.
254. Renaming a class is prohibited when it would create a sibling-name collision under the same parent.
255. That collision uses the error `class-name-conflict`.
256. Class rename validation uses the same class-id naming rules as other class step names and performs name validation before collision checks.
257. Classes will become first-class objects in Mikobase rather than a separate parallel structure.
258. The class object class id is `mikobase.com/class`.
259. This decision implies significant refactoring in both the SQLite and PostgreSQL engines.
260. Classes may be marked deleted.
261. A class cannot be deleted while any records still belong to that class or to any descendant class.
262. That delete rule is cascade-fail rather than cascade-delete.
263. Normal present-time class queries do not return classes whose latest visible version is a delete tombstone.
264. Historical reads at a cutoff timestamp may still return classes that were active at that cutoff, even if they were deleted later.
265. Class tombstones clear class business fields and keep only identity, tenant identity, `active = false`, and engine-managed metadata.
266. Assigning a record to a class whose latest visible version is deleted uses `class-deleted`.
267. Renaming a class whose latest visible version is deleted uses `class-deleted`.
268. Class delete supports an optional `if-exists` flag.
269. With `if-exists: true`, deleting an already deleted class or a class path that never existed returns success with `deleted: false`.
270. Classes will eventually be able to define how their data is presented as HTML for user-facing interfaces.
271. That presentation metadata may describe how specific fields should render, such as text inputs, textareas, checkboxes, or select-style boolean controls.
272. This feature is intended to simplify porting Mikobase data into user-facing interfaces.
273. Nested objects inside a record bucket may carry their own classes through `custom_classes`.
274. Those nested object classes may carry their own constraints.
275. HTML generation should be able to follow `custom_classes` on nested objects automatically.
276. When both a parent class field rule and a nested object's own class metadata apply, the nested object's own class metadata controls the inner widget behavior.
277. The parent class may still add container-level hints such as label, ordering, grouping, or visibility around the nested object.
278. A nested object without a `custom_classes` entry falls back to parent field rules and generic type-based HTML generation.
279. HTML metadata may hide fields from generated output without affecting stored record data.
280. There will be a record-class base called `mikobase.com/join` for directional many-to-many relationship records.
281. Developers may subclass `mikobase.com/join`.
282. A `mikobase.com/join` subclass must define one left field and one right field.
283. Those fields are marked directly in the field definitions rather than repeated in separate metadata.
284. Marking a field as left or right implies and requires that it use the field object class `mikobase.com/reference`.
285. Left and right must be distinct fields.
286. A join subclass must constrain which record class each side may reference.
287. In the first version, each join side points to exactly one allowed record class path.
288. Those left/right target constraints respect record-class inheritance.
289. Join uniqueness is enforced on the ordered `(left, right)` pair only.
290. The pair is directional; `(A, B)` is distinct from `(B, A)`.
291. Additional join payload fields remain editable, but left and right are immutable once the join record is created.
292. If a join record is deleted, a later active join with the same `(left, right)` pair is allowed.
293. Q0 and the future class-definition system should support JSON-Schema export, but JSON Schema is not intended to be the native class-definition model.

Initial scope:

1. Define the exact Q0 request shapes for `create`, `update`, and `delete`.
2. Keep the design engine-agnostic so PostgreSQL and SQLite can implement the same behavior.
3. Preserve append-only history semantics for record identity rows and record version rows.
4. Define validation and failure behavior for invalid writes.
5. Define how write actions interact with `bucket`, class membership, tenant isolation, and `active`.
6. Add tests for both engines.

Open design questions for this issue:

1. Define the exact public request examples for `create`, `update`, and `delete`, including `if-exists`, `misc`, and `enterprise`.
2. Confirm the exact success response shape for `delete`, including `deleted: true` and `deleted: false`.
3. Define the engine-agnostic tombstone field requirements for PostgreSQL and SQLite.
4. Confirm how request validation should interact with future Q0 actions beyond `select`, `create`, `update`, and `delete`.

## Product Open Questions

1. Define the formal public API for creating, versioning, and querying classes and records outside direct SQL inserts.
2. Define the required fields in `records_history` beyond `tenant_pk`, `record_pk`, `class_pk`, and `bucket`.
3. Confirm how the latest version is determined when timestamps and insertion order disagree.
4. Clarify whether deletes are forbidden everywhere, or only updates to append-only tables.
5. Define uniqueness rules for class identifiers within a tenant.
6. Define validation rules for record payloads against a class definition.
7. Define query requirements for reading current state versus historical state.
8. Clarify which remaining requirements belong in engine-agnostic code and which belong in engine implementations.
