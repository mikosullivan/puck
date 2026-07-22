/*
 * sandbox/main.c — round-trip prototype for Caspian's sandbox mechanism.
 *
 * Demonstrates that a single Linux process can:
 *   1. Save its initial mount + user namespaces.
 *   2. Unshare into a new user + mount namespace.
 *   3. Hide /etc/passwd from itself inside the new namespace (proving OS
 *      enforcement — a subsequent open("/etc/passwd") returns nothing).
 *   4. setns() back into the saved namespaces.
 *   5. Read /etc/passwd again — access restored.
 *
 * If this program prints "PASS" the sandbox design is viable on the
 * running kernel. See ../../documentation/ideas/caspian/sandboxing-primitives.md
 * for the design this prototype backs.
 *
 * Build:  gcc -O2 -Wall -o sandbox main.c
 * Run:    ./sandbox        (needs no root, but does need
 *                           unprivileged user namespaces enabled)
 */

#define _GNU_SOURCE
#include <sched.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Bail with a useful message when a syscall fails. */
static void die(const char *what) {
	fprintf(stderr, "FAIL: %s: %s\n", what, strerror(errno));
	exit(1);
}

/* Write a short string to a /proc file, dying on any error. Used for
   the setgroups / uid_map / gid_map dance that unprivileged user
   namespaces require. */
static void write_proc(const char *path, const char *value) {
	int fd = open(path, O_WRONLY);
	if (fd < 0) die(path);
	ssize_t need = (ssize_t)strlen(value);
	if (write(fd, value, need) != need) die(path);
	close(fd);
}

/* Try to open /etc/passwd and print the outcome. Returns 1 on success,
   0 on failure. Used to verify the sandbox is actually enforced. */
static int try_passwd(const char *phase) {
	int fd = open("/etc/passwd", O_RDONLY);
	if (fd < 0) {
		printf("  %-32s /etc/passwd: NOT visible (%s)\n", phase, strerror(errno));
		return 0;
	}
	char buf[64];
	ssize_t n = read(fd, buf, sizeof buf - 1);
	close(fd);
	if (n <= 0) {
		printf("  %-32s /etc/passwd: opened but empty (n=%zd)\n", phase, n);
		return 0;
	}
	buf[n] = '\0';
	/* Strip trailing newline for tidier output. */
	char *nl = strchr(buf, '\n');
	if (nl) *nl = '\0';
	printf("  %-32s /etc/passwd: visible, starts \"%s\"\n", phase, buf);
	return 1;
}

int main(void) {
	printf("Sandbox namespace round-trip prototype\n\n");

	/* --- Step 1: save initial namespace fds. ---------------------- */
	printf("Step 1: save initial namespace fds\n");
	int saved_mnt = open("/proc/self/ns/mnt", O_RDONLY);
	if (saved_mnt < 0) die("open /proc/self/ns/mnt");
	int saved_user = open("/proc/self/ns/user", O_RDONLY);
	if (saved_user < 0) die("open /proc/self/ns/user");
	printf("  saved mnt fd=%d, user fd=%d\n\n", saved_mnt, saved_user);

	/* --- Step 2: baseline — /etc/passwd should be visible. -------- */
	printf("Step 2: baseline (before sandbox)\n");
	int baseline_ok = try_passwd("baseline:");
	printf("\n");

	/* --- Step 3: capture current uid/gid before we unshare. ------- */
	uid_t real_uid = getuid();
	gid_t real_gid = getgid();

	/* --- Step 4: enter a new user + mount namespace. -------------- */
	printf("Step 3: unshare(CLONE_NEWUSER | CLONE_NEWNS)\n");
	if (unshare(CLONE_NEWUSER | CLONE_NEWNS) != 0) {
		fprintf(stderr,
			"FAIL: unshare: %s\n"
			"      This kernel refused unprivileged user namespaces.\n"
			"      Check kernel.unprivileged_userns_clone or CONFIG_USER_NS.\n",
			strerror(errno));
		return 1;
	}
	printf("  now in a private user + mount namespace\n\n");

	/* --- Step 5: set up uid/gid maps in the new user ns. ---------- */
	/* The kernel requires setgroups to be denied before gid_map can be
	   written in an unprivileged user namespace. */
	printf("Step 4: set up UID/GID maps\n");
	write_proc("/proc/self/setgroups", "deny");
	char map_buf[64];
	snprintf(map_buf, sizeof map_buf, "0 %u 1", (unsigned)real_uid);
	write_proc("/proc/self/uid_map", map_buf);
	snprintf(map_buf, sizeof map_buf, "0 %u 1", (unsigned)real_gid);
	write_proc("/proc/self/gid_map", map_buf);
	printf("  uid %u -> 0, gid %u -> 0 (inside the namespace)\n\n",
		(unsigned)real_uid, (unsigned)real_gid);

	/* --- Step 6: mark / as private so our mount doesn't propagate
	       back to the parent namespace. Most modern distros mount /
	       as shared via systemd. ------------------------------------ */
	printf("Step 5: make / private (defense against systemd's shared mount)\n");
	if (mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL) != 0)
		die("mount / MS_PRIVATE");
	printf("  ok\n\n");

	/* --- Step 7: hide /etc by mounting an empty tmpfs over it. ---- */
	printf("Step 6: mount empty tmpfs over /etc — hides /etc/passwd\n");
	if (mount("tmpfs", "/etc", "tmpfs", 0, "size=64k") != 0)
		die("mount tmpfs over /etc");
	printf("  ok\n\n");

	/* --- Step 8: verify /etc/passwd is now unreachable. ----------- */
	printf("Step 7: verify sandbox is enforced\n");
	int sandbox_blocked = !try_passwd("inside sandbox:");
	printf("\n");

	/* --- Step 9: setns back to the saved namespaces. -------------- */
	printf("Step 8: setns back to saved namespaces\n");
	if (setns(saved_user, CLONE_NEWUSER) != 0) die("setns user");
	if (setns(saved_mnt,  CLONE_NEWNS)   != 0) die("setns mnt");
	printf("  restored\n\n");

	/* --- Step 10: verify /etc/passwd is visible again. ------------ */
	printf("Step 9: verify full filesystem view restored\n");
	int restored_ok = try_passwd("after sandbox:");
	printf("\n");

	/* --- Summary. ------------------------------------------------- */
	int all_ok = baseline_ok && sandbox_blocked && restored_ok;
	printf("---\n");
	printf("baseline:                   %s\n", baseline_ok    ? "ok" : "FAIL");
	printf("sandbox hides /etc/passwd:  %s\n", sandbox_blocked ? "ok" : "FAIL");
	printf("view restored after exit:   %s\n", restored_ok    ? "ok" : "FAIL");
	printf("%s\n", all_ok ? "PASS — sandbox design is viable on this kernel."
	                      : "FAIL — see above.");

	close(saved_mnt);
	close(saved_user);
	return all_ok ? 0 : 1;
}
