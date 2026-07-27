from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "check_doc_paths.py"
SPEC = importlib.util.spec_from_file_location("check_doc_paths", MODULE_PATH)
assert SPEC is not None
assert SPEC.loader is not None
check_doc_paths = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = check_doc_paths
SPEC.loader.exec_module(check_doc_paths)


class FakeRepository(check_doc_paths.Repository):
    def __init__(
        self,
        tracked_files: set[str],
        ignored_files: set[str] | None = None,
    ) -> None:
        super().__init__(Path("."), tracked_files)
        self.ignored_files = ignored_files or set()

    def _is_ignored(self, reference: str) -> bool:
        return reference in self.ignored_files


class DocumentationPathCheckerTest(unittest.TestCase):
    def test_finds_missing_backtick_repo_path(self) -> None:
        repository = FakeRepository({"docs/guide.md"})

        findings = check_doc_paths.check_markdown_file(
            repository,
            "docs/guide.md",
            "See `lib/missing/service.dart`.",
        )

        self.assertEqual(
            findings,
            [
                check_doc_paths.Finding(
                    "docs/guide.md",
                    1,
                    "lib/missing/service.dart",
                )
            ],
        )

    def test_accepts_tracked_files_and_directories(self) -> None:
        repository = FakeRepository(
            {
                "docs/guide.md",
                "lib/domain/task.dart",
                "test/unit/task_test.dart",
            }
        )

        findings = check_doc_paths.check_markdown_file(
            repository,
            "docs/guide.md",
            "Use `lib/domain/task.dart`, then run tests under `test/unit/`.",
        )

        self.assertEqual(findings, [])

    def test_resolves_relative_markdown_links_from_source_file(self) -> None:
        repository = FakeRepository(
            {
                "docs/guide.md",
                "docs/adr/ADR-001.md",
                "README.md",
            }
        )

        findings = check_doc_paths.check_markdown_file(
            repository,
            "docs/guide.md",
            "Read [the ADR](adr/ADR-001.md) and [README](../README.md).",
        )

        self.assertEqual(findings, [])

    def test_finds_missing_relative_markdown_link(self) -> None:
        repository = FakeRepository({"docs/guide.md"})

        findings = check_doc_paths.check_markdown_file(
            repository,
            "docs/guide.md",
            "Read [the missing guide](missing.md).",
        )

        self.assertEqual(
            findings,
            [
                check_doc_paths.Finding(
                    "docs/guide.md",
                    1,
                    "docs/missing.md",
                )
            ],
        )

    def test_skips_external_anchor_and_wildcard_references(self) -> None:
        repository = FakeRepository({"docs/guide.md"})
        content = "\n".join(
            [
                "[web](https://example.com/docs/missing.md)",
                "[anchor](#local-section)",
                "Source: `https://github.com/android/health-samples`.",
                "Run `test/*.dart`.",
            ]
        )

        findings = check_doc_paths.check_markdown_file(
            repository,
            "docs/guide.md",
            content,
        )

        self.assertEqual(findings, [])

    def test_accepts_missing_generated_or_ignored_file(self) -> None:
        repository = FakeRepository(
            {"docs/guide.md"},
            ignored_files={"lib/data/database.g.dart"},
        )

        findings = check_doc_paths.check_markdown_file(
            repository,
            "docs/guide.md",
            "Generate `lib/data/database.g.dart` before analysis.",
        )

        self.assertEqual(findings, [])

    def test_ignore_marker_applies_to_same_or_next_line_only(self) -> None:
        repository = FakeRepository({"docs/guide.md"})
        content = "\n".join(
            [
                "<!-- doc-path-check: ignore -->",
                "Historical: `lib/former/location.dart`.",
                "Proposed: `lib/future/location.dart`. "
                "<!-- doc-path-check: ignore -->",
                "Valid: `docs/guide.md`.",
                "Broken: `lib/actually/missing.dart`.",
            ]
        )

        findings = check_doc_paths.check_markdown_file(
            repository,
            "docs/guide.md",
            content,
        )

        self.assertEqual(
            findings,
            [
                check_doc_paths.Finding(
                    "docs/guide.md",
                    5,
                    "lib/actually/missing.dart",
                )
            ],
        )

    def test_archive_markdown_is_not_in_scan_inventory(self) -> None:
        repository = FakeRepository(
            {
                "README.md",
                "docs/guide.md",
                "docs/archive/old.md",
            }
        )

        self.assertEqual(
            repository.markdown_files(),
            ["README.md", "docs/guide.md"],
        )

    def test_repo_hygiene_workflow_invokes_checker(self) -> None:
        repository_root = Path(__file__).parents[2]
        workflow = (
            repository_root / ".github/workflows/repo-hygiene.yml"
        ).read_text(encoding="utf-8")

        self.assertIn(
            "      - name: Documentation paths resolve\n"
            "        run: python3 scripts/check_doc_paths.py\n",
            workflow.replace("\r\n", "\n"),
        )


if __name__ == "__main__":
    unittest.main()
