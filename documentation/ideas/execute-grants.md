# Execute grants down the chain

*Strategy for passing **limited** execution permissions to non-user roles. In V1, `.execute` is user-only — non-user roles can't invoke external programs at all. This design space explores how to controllably grant `.execute` to a callee while keeping the security posture sane. Possible directions: an allowlist of specific programs, argv-shape constraints, chroot-strengthened execution (see [chroot-dirjails](chroot-dirjails)), or something else. Post-V1.*

~~~vibecode
{"vibecode": {
	"doc": "idea_execute_grants",
	"role": "brainstorm for a future mechanism to grant limited .execute permissions to non-user roles. In V1, .execute is strictly user-only — non-user code can never invoke external programs. This design space would open a controlled path: allowlist specific programs, constrain argv shape, require chroot-strength containment, or some combination. Related: idea_chroot_dirjails (OS-level containment as one possible strategy), idea_linux_utils (the general .execute model and the user-only rule this would relax).",
	"status": "brainstorm — flagged during dirjail-safety design; deferred post-V1"
}}
~~~

## Directions worth exploring when we come back

- **Program allowlist.** User grants callee the ability to `.execute` only specific programs by name (`tar` yes, `curl` no). Callee-side attempt to run anything else raises.
- **Argv-shape constraints.** User grants callee execute on `tar` but only with specific arg patterns (e.g. extract-only, no `-C` outside a given prefix). Requires a mini-DSL or predicate for describing allowed argv.
- **Chroot-strengthened.** Combine with [chroot-dirjails](chroot-dirjails) so callee's `.execute` runs inside an actual OS-level jail. Real containment; higher complexity.
- **Composite.** Any two of the above (e.g. allowlisted programs + chroot).
