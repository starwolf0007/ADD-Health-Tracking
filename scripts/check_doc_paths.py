#!/usr/bin/env python3
"""Validate checkable repository paths in tracked Markdown files."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from urllib.parse import unquote


KNOWN_ROOTS = ("android", "docs", "lib", "scripts", "test", "wear")
ARCHIVE_PREFIX = PurePosixPath("docs/archive")
IGNORE_MARKER = "doc-path-check: ignore"
IGNORE_COMMENT = f"<!-- {IGNORE_MARKER} -->"

CODE_SPAN_RE = re.compile(r"`([^`\n]+)`")
MARKDOWN_LINK_RE = re.compile(r"!?\[[^\]\n]*\]\(([^)\n]+)\)")
REPO_PATH_RE = re.compile(
    rf"(?<![A-Za-z0-9_.-])(?:{'|'.join(KNOWN_ROOTS)})/"
    r"[A-Za-z0-9._/-]+"
)
WILDCARD_RE = re.compile(r"[*?[\]{}]")
URI_SCHEME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


@dataclass(frozen=True)
class Finding:
    markdown_file: str
    line: int
    reference: str

    def render(self) -> str:
        return (
            f"{self.markdown_file}:{self.line}: missing documentation path "
            f"`{self.reference}`"
        )


class Repository:
    def __init__(self, root: Path, tracked_files: set[str]) -> None:
        self.root = root
        self.tracked_files = tracked_files
        self.tracked_directories = {
            parent.as_posix()
            for filename in tracked_files
            for parent in PurePosixPath(filename).parents
            if parent != PurePosixPath(".")
        }

    @classmethod
    def from_git(cls, root: Path) -> "Repository":
        result = subprocess.run(
            ["git", "ls-files", "-z"],
            cwd=root,
            check=True,
            capture_output=True,
        )
        tracked_files = {
            path.decode("utf-8")
            for path in result.stdout.split(b"\0")
            if path
        }
        return cls(root, tracked_files)

    def markdown_files(self) -> list[str]:
        return sorted(
            filename
            for filename in self.tracked_files
            if filename.lower().endswith(".md")
            and not _is_under_archive(filename)
        )

    def reference_exists(self, reference: str) -> bool:
        normalized = _normalize_repo_path(reference)
        if normalized in self.tracked_files:
            return True
        if normalized.rstrip("/") in self.tracked_directories:
            return True
        return self._is_ignored(normalized)

    def _is_ignored(self, reference: str) -> bool:
        result = subprocess.run(
            ["git", "check-ignore", "--quiet", "--", reference],
            cwd=self.root,
            check=False,
        )
        if result.returncode not in (0, 1):
            raise RuntimeError(
                f"git check-ignore failed for {reference!r} "
                f"with exit code {result.returncode}"
            )
        return result.returncode == 0


def _is_under_archive(filename: str) -> bool:
    path = PurePosixPath(filename)
    return path == ARCHIVE_PREFIX or ARCHIVE_PREFIX in path.parents


def _normalize_repo_path(reference: str) -> str:
    normalized = PurePosixPath(reference.replace("\\", "/"))
    parts: list[str] = []
    for part in normalized.parts:
        if part in ("", "."):
            continue
        if part == "..":
            if parts:
                parts.pop()
            continue
        parts.append(part)
    return "/".join(parts)


def _is_wildcard(reference: str) -> bool:
    return WILDCARD_RE.search(reference) is not None


def _is_external_or_anchor(reference: str) -> bool:
    return (
        not reference
        or reference.startswith(("#", "//", "/"))
        or URI_SCHEME_RE.match(reference) is not None
    )


def _clean_link_destination(raw_destination: str) -> str:
    destination = raw_destination.strip()
    if destination.startswith("<") and destination.endswith(">"):
        destination = destination[1:-1]
    else:
        destination = destination.split(maxsplit=1)[0]
    destination = destination.split("#", maxsplit=1)[0]
    destination = destination.split("?", maxsplit=1)[0]
    return unquote(destination)


def _line_is_ignored(lines: list[str], index: int) -> bool:
    if IGNORE_MARKER in lines[index]:
        return True
    return index > 0 and lines[index - 1].strip() == IGNORE_COMMENT


def _code_path_references(line: str) -> set[str]:
    references: set[str] = set()
    for span in CODE_SPAN_RE.findall(line):
        if URI_SCHEME_RE.match(span):
            continue
        references.update(match.group(0) for match in REPO_PATH_RE.finditer(span))
    return references


def _link_references(markdown_file: str, line: str) -> set[str]:
    references: set[str] = set()
    source_parent = PurePosixPath(markdown_file).parent
    for raw_destination in MARKDOWN_LINK_RE.findall(line):
        destination = _clean_link_destination(raw_destination)
        if _is_external_or_anchor(destination) or _is_wildcard(destination):
            continue
        references.add((source_parent / destination).as_posix())
    return references


def check_markdown_file(
    repository: Repository, markdown_file: str, content: str
) -> list[Finding]:
    findings: list[Finding] = []
    lines = content.splitlines()
    for index, line in enumerate(lines):
        if _line_is_ignored(lines, index):
            continue
        references = _code_path_references(line)
        references.update(_link_references(markdown_file, line))
        for reference in sorted(references):
            if _is_wildcard(reference):
                continue
            if not repository.reference_exists(reference):
                findings.append(Finding(markdown_file, index + 1, reference))
    return findings


def check_repository(repository: Repository) -> list[Finding]:
    findings: list[Finding] = []
    for markdown_file in repository.markdown_files():
        content = (repository.root / markdown_file).read_text(encoding="utf-8")
        findings.extend(
            check_markdown_file(repository, markdown_file, content)
        )
    return findings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path.cwd(),
        help="repository root (defaults to the current directory)",
    )
    args = parser.parse_args(argv)
    root = args.root.resolve()

    try:
        repository = Repository.from_git(root)
        findings = check_repository(repository)
    except (OSError, UnicodeError, subprocess.CalledProcessError, RuntimeError) as error:
        print(f"Documentation path validation failed to run: {error}", file=sys.stderr)
        return 2

    if findings:
        print("Documentation path validation found missing paths:", file=sys.stderr)
        for finding in findings:
            print(f"  {finding.render()}", file=sys.stderr)
        print(
            f"{len(findings)} missing documentation path(s) found.",
            file=sys.stderr,
        )
        return 1

    print(
        f"Documentation path validation passed "
        f"({len(repository.markdown_files())} tracked Markdown files checked)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
