"""The files that go public carry no toolkit text (DECISIONS_LOG 2026-09-15).

Every toolkit PDF prints "Copyright © 2016 by YMCA of the USA. All rights reserved.", so
nothing transcribed from it may sit in a tracked file that `tools/dev/export_public.py`
would copy: not a sample, not a fixture, not a doc example. This test holds that, by
looking for a run of seven words shared with the extracted text in
`reference/ymca-v6/text/`. It runs on the owner's machine, where that text is; anywhere
else there is nothing to compare against and it skips.

The owner's own notes (the agent instructions, the decisions log, docs/v1/, inputs/) are not exported
and are not checked — they quote the toolkit freely.
"""

import unittest

from tools.dev import export_public


class PublicFilesTests(unittest.TestCase):

    def test_no_toolkit_text_in_the_files_that_go_public(self):
        files = [path for path in export_public.tracked() if not export_public.is_private(path)]
        self.assertIn("README.md", files)
        found = export_public.toolkit_runs(files)
        if found is None:
            self.skipTest("no reference/ymca-v6/text/ to compare against (not the owner's machine)")
        report = "\n".join("%s: %s" % (path, runs[0]) for path, runs in sorted(found.items()))
        self.assertEqual({}, found, "toolkit text in files bound for the public copy:\n" + report)

    def test_the_owners_own_notes_stay_behind(self):
        for path in ("CLAUDE.md", "AGENTS.md", "docs/DECISIONS_LOG.md", "docs/BUILD_STATUS.md",
                     "docs/IDEAS.md", "docs/v1/SPEC.md", "inputs/README.md"):
            self.assertTrue(export_public.is_private(path), path)
        for path in ("README.md", "LICENSE", "docs/CURRICULUM_FORMAT.md", "docs/TEST_CASES.md",
                     "examples/curriculum.stage1.sample.json", "tools/core/curriculum.py"):
            self.assertFalse(export_public.is_private(path), path)

    def test_the_copyright_notice_itself_is_not_a_hit(self):
        self.assertTrue(export_public.is_attribution("is copyright 2016 by ymca of the usa"))
        self.assertFalse(export_public.is_attribution("swimmers take one breath and blow bubbles"))
        # (an example here must itself be made up: this file is exported too)


if __name__ == "__main__":
    unittest.main()
