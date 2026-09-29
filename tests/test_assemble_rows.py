"""Tracker-row text in the assembled curriculum (A7, A8)."""

import unittest

from tools.core.assemble import row_text


class TrackerRowTextTests(unittest.TestCase):
    def test_A7_row_text_drops_the_printed_preschool_note(self):
        self.assertEqual("Front glide on your own, farther, 10 feet", row_text({"text": "Front glide on your own, farther, 10 feet (5 ft. preschool)"}))
        self.assertEqual("Tread water with a helper close by, 60 seconds",
                         row_text({"text": "Tread water with a helper close by, 60 seconds (30 secs. preschool)"}))

    def test_A7_row_text_without_a_note_is_unchanged(self):
        self.assertEqual("Swim and rest on your own, 5 yards", row_text({"text": " Swim and rest on your own, 5 yards "}))


if __name__ == "__main__":
    unittest.main()
