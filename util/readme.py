#!/usr/bin/env python3
"""Update README usage and check or update its introductory example."""

import argparse
import difflib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def code_block(text, section, language):
    heading = re.search(rf"^## {re.escape(section)}\s*$", text, re.MULTILINE)
    if not heading:
        raise ValueError(f"Missing README section: {section}")
    end = re.search(r"^## ", text[heading.end() :], re.MULTILINE)
    limit = heading.end() + end.start() if end else len(text)
    block = re.search(
        rf"^```{language}\n(.*?)^```[ \t]*$",
        text[heading.end() : limit],
        re.MULTILINE | re.DOTALL,
    )
    if not block:
        raise ValueError(f"Missing {language or 'plain'} code block in {section}")
    return heading.end() + block.start(1), heading.end() + block.end(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["update-usage", "check-example", "update-example"])
    parser.add_argument("--readme", type=Path, default=ROOT / "README.md")
    args = parser.parse_args()
    text = args.readme.read_text()
    section, language = (
        ("Usage", "") if args.command == "update-usage" else ("Example", "bash")
    )
    start, end = code_block(text, section, language)
    if args.command != "update-usage":
        example = (ROOT / "examples/readme/example.sh").read_text()
        if args.command == "check-example":
            if text[start:end] != example:
                diff = difflib.unified_diff(
                    text[start:end].splitlines(keepends=True),
                    example.splitlines(keepends=True),
                    fromfile=str(args.readme),
                    tofile="examples/readme/example.sh",
                )
                parser.exit(
                    1,
                    "".join(diff)
                    + "Run python3 util/readme.py update-example to sync the README.\n",
                )
            return
        updated = text[:start] + example + text[end:]
        if updated != text:
            args.readme.write_text(updated)
            print(f"Updated {args.readme.name}")
        return
    output = subprocess.check_output([str(ROOT / "extra-container"), "--help"], text=True)
    usage = re.search(r"\A.*?Usage:\s*(.*)", output, re.DOTALL)
    if not usage:
        raise ValueError("extra-container help has no Usage header")
    updated = text[:start] + usage[1].rstrip("\n") + "\n" + text[end:]
    if updated != text:
        args.readme.write_text(updated)
        print(f"Updated {args.readme.name}")


if __name__ == "__main__":
    main()
