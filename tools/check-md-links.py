#!/usr/bin/env python3
"""Quick on-disk markdown link checker.

Walks a docs tree, reports any relative-path markdown link `[text](path)` whose
target doesn't exist on disk. External URLs (http/https/mailto/file) and pure
fragments (#anchor) are skipped. Fragment portions of links are not validated.

Usage:
    tools/check-md-links.py                            # check documentation/
    tools/check-md-links.py documentation/ideas        # check a subtree
    tools/check-md-links.py --fix                      # attempt auto-fixes for
                                                       # paths under documentation/
                                                       # that moved into a
                                                       # documentation/requirements/
                                                       # sibling tree.

Auto-fix candidates the script will try for each broken link, in order:
    - Insert 'requirements/' before the first moved-dir segment in the path
      (handles ../caspian/X → ../requirements/caspian/X).
    - As above with an additional '../' prefix (handles depth-confused links
      from ideas/SUBDIR/ that need to climb one more level).
    - Same with '../requirements/' as a fresh prefix.
    - As any of the above but treating a trailing '.md' as a directory whose
      index.md is the real target (handles old `blockchain.md` → new
      `blockchain/index.md` migrations).

Exit code:
    0  no broken links remain (after --fix if given).
    1  one or more broken links remain.
"""

import argparse
import os
import re
import sys
from urllib.parse import unquote

MOVED_DIRS = {'caspian', 'mikobase', 'puck', 'ecoverse', 'development'}
MD_LINK_RE = re.compile(r'(\[[^\]]*\]\()([^)]+)(\))')
SKIP_PREFIXES = ('http://', 'https://', 'mailto:', '#', 'file:')


def exists(file_dir, url):
    base = url.split('#', 1)[0]
    if not base:
        return True
    target = os.path.normpath(os.path.join(file_dir, unquote(base)))
    return os.path.exists(target)


def candidates(base):
    """Yield possible rewrites for a broken link's path portion (no fragment)."""
    parts = base.split('/')
    moved_idx = None
    for i, p in enumerate(parts):
        if p in MOVED_DIRS:
            moved_idx = i
            break
    if moved_idx is None:
        return
    bases = [
        parts[:moved_idx] + ['requirements'] + parts[moved_idx:],
        ['..'] + parts[:moved_idx] + ['requirements'] + parts[moved_idx:],
    ]
    if not parts[0].startswith('..'):
        bases.append(['..', 'requirements'] + parts[moved_idx:])
    for b in list(bases):
        joined = '/'.join(b)
        yield joined
        if joined.endswith('.md') and not joined.endswith('/index.md'):
            yield joined[:-3] + '/index.md'


def try_rewrite(file_dir, url):
    if url.startswith(SKIP_PREFIXES) or not url:
        return None
    frag = ''
    base = url
    if '#' in url:
        base, frag = url.split('#', 1)
        frag = '#' + frag
    if exists(file_dir, base):
        return None
    for cand in candidates(base):
        if exists(file_dir, cand):
            return cand + frag
    return None


def walk(root, do_fix):
    broken = []
    fixed = []
    for dirpath, _, files in os.walk(root):
        for f in files:
            if not f.endswith('.md'):
                continue
            path = os.path.join(dirpath, f)
            with open(path) as fp:
                txt = fp.read()
            new_txt = txt
            file_dir = os.path.dirname(path)
            for lineno, line in enumerate(txt.split('\n'), 1):
                for m in MD_LINK_RE.finditer(line):
                    url = m.group(2)
                    if url.startswith(SKIP_PREFIXES) or not url:
                        continue
                    if exists(file_dir, url):
                        continue
                    if do_fix:
                        new_url = try_rewrite(file_dir, url)
                        if new_url:
                            old_link = m.group(0)
                            new_link = m.group(1) + new_url + m.group(3)
                            new_txt = new_txt.replace(old_link, new_link)
                            fixed.append((path, url, new_url))
                            continue
                    broken.append((path, lineno, url))
            if do_fix and new_txt != txt:
                with open(path, 'w') as fp:
                    fp.write(new_txt)
    return broken, fixed


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('root', nargs='?', default='documentation',
                    help='Directory to walk (default: documentation)')
    ap.add_argument('--fix', action='store_true',
                    help='Attempt auto-fixes for paths that moved under requirements/')
    args = ap.parse_args()

    if not os.path.isdir(args.root):
        print(f"error: not a directory: {args.root}", file=sys.stderr)
        return 2

    broken, fixed = walk(args.root, args.fix)

    if args.fix and fixed:
        print(f"Auto-fixed {len(fixed)} link(s):")
        for path, old, new in fixed[:10]:
            print(f"  {path}: {old} -> {new}")
        if len(fixed) > 10:
            print(f"  ... and {len(fixed) - 10} more")
        print()

    if broken:
        print(f"Broken link(s) remaining: {len(broken)}")
        for path, lineno, url in broken:
            print(f"  {path}:{lineno}  {url}")
        return 1

    print("No broken links.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
