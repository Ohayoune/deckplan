"""C5: the N-lesson mapping kept from v1 (TEST_CASES.md C5; v1 B12)."""

import unittest

from tools.core import session_plan as SP

from tests.v2support import sample


class MappingTests(unittest.TestCase):
    def setUp(self):
        self.curriculum = sample()

    def test_C5_stage1_mappings(self):
        expected = {
            8: [1, 2, 3, 4, 5, 6, 7, 8],
            7: [1, 2, 3, 4, 5, 7, 8],
            6: [1, 2, 3, 4, 7, 8],
            5: [1, 2, 4, 7, 8],
            4: [1, 2, 4, 8],
            10: [1, 2, 3, 4, 5, 6, 7, None, None, 8],
        }
        for n, mapping in expected.items():
            with self.subTest(n=n):
                self.assertEqual(mapping, SP.guide_lesson_mapping(self.curriculum, "1", n))

    def test_C5_guide_lesson_for_day(self):
        self.assertEqual(7, SP.guide_lesson_for_day(self.curriculum, "1", 6, 5))
        self.assertIsNone(SP.guide_lesson_for_day(self.curriculum, "1", 10, 8))
        self.assertEqual(8, SP.guide_lesson_for_day(self.curriculum, "1", 10, 10))
        for bad in (0, 9, "5"):
            with self.assertRaises(ValueError):
                SP.guide_lesson_for_day(self.curriculum, "1", 8, bad)


if __name__ == "__main__":
    unittest.main()
