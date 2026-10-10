#!/usr/bin/env python3
"""Add Nix paths and NIX_PATH to sudo's environment; emit only changes."""

import re
import sys


def make_sudoers(original, extra_paths):
    def extend_path(match):
        paths = dict.fromkeys((match[2] + ":" + extra_paths).split(":"))
        return match[1] + ":".join(paths) + match[3]

    updated, count = re.subn(
        r'(Defaults\s+secure_path\s*=\s*"?)([^"\s]+)([^\n]*)',
        extend_path,
        original,
        count=1,
    )
    additions = []
    if not count:
        additions.append(f'Defaults\tsecure_path = "{extra_paths}"')
    keep = "Defaults\tenv_keep += NIX_PATH"
    if keep not in original:
        additions.append(keep)
    if additions:
        separator = "\n" if updated and not updated.endswith("\n") else ""
        updated += separator + "\n".join(additions) + "\n"
    return updated if updated != original else ""


if __name__ == "__main__":
    sys.stdout.write(make_sudoers(sys.stdin.read(), sys.argv[1]))
