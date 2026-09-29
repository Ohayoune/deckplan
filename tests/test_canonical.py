"""The hash and canonical JSON (docs/CANONICAL_JSON.md).

`hash_parts` and `dumps` are the only hash and JSON encoding the Core
uses anywhere (the "Determinism" rule). This file checks every literal
example in docs/CANONICAL_JSON.md and the M2 build brief, plus focused cases for the number
and string rules the brief pins so a Swift port can match them byte for
byte.
"""

import unittest

from tools.core import canonical as J


class CanonicalTests(unittest.TestCase):

    def test_D11_hash_and_canonical_json(self):
        # hash_parts: the three literal values (docs/CANONICAL_JSON.md).
        self.assertEqual(13436514500253700074, J.hash_parts("abc"))  # 0xba7816bf8f01cfea
        self.assertEqual(7132184755009805105,
                          J.hash_parts(12345, 0, "1.front-glide", "puffin-rocket-ride"))
        self.assertEqual(13095845880559124262, J.hash_parts("L5"))  # D9: seed = hash(lesson.id)

        # an unsigned 64-bit integer, including above the signed 64-bit max.
        self.assertGreater(J.hash_parts("L5"), 2 ** 63 - 1)
        self.assertLess(J.hash_parts("L5"), 2 ** 64)

        # canonical JSON: the brief's literal dumps() example.
        self.assertEqual('{"a":[7,1.5,"é/x"],"b":1}',
                          J.dumps({"b": 1, "a": [7.0, 1.5, "é/x"]}))

    def test_integral_floats_become_integers(self):
        self.assertEqual("7", J.dumps(7.0))
        self.assertEqual("-7", J.dumps(-7.0))
        self.assertEqual("0", J.dumps(0.0))
        self.assertEqual("0", J.dumps(-0.0))
        self.assertEqual("123456789", J.dumps(123456789.0))
        self.assertEqual("1", J.dumps(1))  # a plain int is never treated as a float

    def test_non_integral_floats_keep_shortest_round_trip_form(self):
        for value in (5.75, 0.1, 1e-7, 0.25, 1.0000000000000002, -5.75, 3.14159):
            rendered = J.dumps(value)
            self.assertEqual(value, float(rendered), "%r -> %s" % (value, rendered))
        # the exact strings (repr's shortest round-trip form)
        self.assertEqual("5.75", J.dumps(5.75))
        self.assertEqual("0.1", J.dumps(0.1))
        self.assertEqual("1e-07", J.dumps(1e-7))

    def test_bool_is_never_written_as_a_number(self):
        self.assertEqual("true", J.dumps(True))
        self.assertEqual("false", J.dumps(False))
        # bool next to real 1/0 ints keeps its own literal, not 1/0
        self.assertEqual("[true,1,false,0]", J.dumps([True, 1, False, 0]))

    def test_none_is_null(self):
        self.assertEqual("null", J.dumps(None))
        self.assertEqual('{"a":null}', J.dumps({"a": None}))

    def test_nan_and_infinity_raise_value_error(self):
        with self.assertRaises(ValueError):
            J.dumps(float("nan"))
        with self.assertRaises(ValueError):
            J.dumps(float("inf"))
        with self.assertRaises(ValueError):
            J.dumps(float("-inf"))
        with self.assertRaises(ValueError):
            J.dumps({"x": [1, float("nan")]})  # nested, not just top-level

    def test_control_characters_escape_as_the_brief_says(self):
        # \b \f \n \r \t keep their short forms
        self.assertEqual('"\\b\\f\\n\\r\\t"', J.dumps("\b\f\n\r\t"))
        # every other control character (U+0000-U+001F) is lower-case \u00xx
        self.assertEqual('"\\u0000\\u0001\\u001f"', J.dumps("\x00\x01\x1f"))
        # quote and backslash escape too, distinct from the control-char case
        self.assertEqual('"\\"\\\\"', J.dumps('"\\'))

    def test_slash_and_non_ascii_stay_unescaped(self):
        self.assertEqual('"a/b"', J.dumps("a/b"))
        self.assertEqual('"é"', J.dumps("é"))
        self.assertEqual('"日本語"', J.dumps("日本語"))

    def test_keys_sorted_by_code_point(self):
        # "Z" (U+005A) < "a" (U+0061) < "z" (U+007A) < "é" (U+00E9)
        self.assertEqual('{"Z":2,"a":3,"z":1,"é":4}',
                          J.dumps({"z": 1, "Z": 2, "a": 3, "é": 4}))

    def test_nested_structures(self):
        value = {"x": {"y": [1, 2, {"z": None, "w": [True, False]}]}, "a": []}
        self.assertEqual('{"a":[],"x":{"y":[1,2,{"w":[true,false],"z":null}]}}', J.dumps(value))

    def test_lists_keep_their_given_order(self):
        self.assertEqual("[3,1,2]", J.dumps([3, 1, 2]))  # never re-sorted

    def test_no_insignificant_whitespace(self):
        rendered = J.dumps({"a": 1, "b": [1, 2], "c": "x y"})
        self.assertNotIn(" ", rendered.replace('"x y"', ""))  # only the string's own space survives
        self.assertNotIn("\n", rendered)
        self.assertNotIn("\t", rendered)

    def test_non_string_dict_key_is_a_type_error(self):
        with self.assertRaises(TypeError):
            J.dumps({1: "a"})

    def test_hash_parts_rejects_non_str_non_int_parts(self):
        with self.assertRaises(TypeError):
            J.hash_parts(True)  # bool, not a documented part kind
        with self.assertRaises(TypeError):
            J.hash_parts(1.5)
        with self.assertRaises(TypeError):
            J.hash_parts(None)

    def test_hash_parts_matches_first_8_bytes_of_its_own_sha256(self):
        # cross-check the two functions' shared rule: hash_parts("abc") is
        # exactly the first 8 bytes of sha256_hex("abc"), as an unsigned
        # big-endian integer (docs/CANONICAL_JSON.md).
        self.assertEqual(J.hash_parts("abc"), int(J.sha256_hex("abc")[:16], 16))

    def test_sha256_hex_of_empty_string(self):
        self.assertEqual(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            J.sha256_hex(""))

    def test_loads_reads_back_dumps(self):
        value = {"a": [1, 2.5, None, True, "é/x"], "b": "y"}
        self.assertEqual(value, J.loads(J.dumps(value)))


if __name__ == "__main__":
    unittest.main()
