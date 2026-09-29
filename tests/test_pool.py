"""P1–P6: the pool profile, the one filter and the profile items (TEST_CASES.md group P)."""

import copy
import unittest
from pathlib import Path

from tools.core import activities as ACT
from tools.core import curriculum as C
from tools.core import day_plan, finder
from tools.core import ids

from tests.v2support import ROOT, fixture_class, fixture_pool, manifest_case, sample

PROFILE_SAMPLE = ["pool-noodle", "kickboard", "hoop", "small-toys", "ball"]
PROFILE_LIBRARY = ["pool-noodle", "kickboard", "hoop", "small-toys", "pull-buoy"]


class PoolProfileTests(unittest.TestCase):
    def setUp(self):
        self.curriculum = sample()

    def test_P1_default_profile_has_everything_on_and_one_key_per_profile_item(self):
        pool = ACT.default_pool(self.curriculum)
        self.assertEqual({"shallow": True, "medium": True, "deep": True}, pool["depths"])
        self.assertTrue(pool["diving"])
        self.assertTrue(pool["totDock"])
        self.assertEqual(PROFILE_SAMPLE, list(pool["equipment"]))
        self.assertNotIn("flotation-device", pool["equipment"])
        self.assertNotIn("goggles", pool["equipment"])  # a prop
        self.assertTrue(all(pool["equipment"].values()))

    def test_P1_missing_keys_read_as_off_and_prop_and_unknown_keys_are_dropped(self):
        pool = ACT.normalize_pool({"equipment": {"kickboard": 1, "jetpack": True, "goggles": False},
                                   "depths": {"shallow": True}}, self.curriculum)
        self.assertEqual({"shallow": True, "medium": False, "deep": False}, pool["depths"])
        self.assertFalse(pool["diving"])
        self.assertFalse(pool["totDock"])
        self.assertIs(True, pool["equipment"]["kickboard"])
        self.assertIs(False, pool["equipment"]["pool-noodle"])
        self.assertNotIn("jetpack", pool["equipment"])
        self.assertNotIn("goggles", pool["equipment"])
        self.assertEqual(PROFILE_SAMPLE, list(pool["equipment"]))
        self.assertEqual(ACT.normalize_pool(None, self.curriculum), ACT.normalize_pool({}, self.curriculum))
        # the fixture pool is already in shape
        self.assertEqual(fixture_pool(), ACT.normalize_pool(fixture_pool(), self.curriculum))

    def test_P6_profile_items_are_the_five_most_required_in_catalog_order(self):
        self.assertEqual(PROFILE_SAMPLE, ACT.profile_items(self.curriculum))
        self.assertEqual(manifest_case("P6.profile")["expected"]["profileItems"], PROFILE_SAMPLE)
        counts = ACT.requirement_counts(self.curriculum.activities, self.curriculum.equipment)
        self.assertEqual(counts["ball"], counts["float-belt"])  # ball wins its tie by catalog order
        catalog = ACT.catalog_items(self.curriculum.equipment)
        self.assertLess(catalog.index("ball"), catalog.index("float-belt"))
        fifth = min(counts[item] for item in PROFILE_SAMPLE)
        for item in catalog:
            if item not in PROFILE_SAMPLE:
                self.assertLessEqual(counts.get(item, 0), fifth, item)
        self.assertTrue(ACT.is_prop(self.curriculum, "goggles"))
        self.assertTrue(ACT.is_prop(self.curriculum, "life-jacket"))
        self.assertFalse(ACT.is_prop(self.curriculum, "kickboard"))
        self.assertFalse(ACT.is_prop(self.curriculum, "flotation-device"))  # a group, not an item
        self.assertFalse(ACT.is_prop(self.curriculum, "no-such-thing"))
        # a group requirement counts toward each of its anyOf members, once per activity
        needs_group = next(a for a in self.curriculum.activities if ["flotation-device"] in (a.get("equipment") or []))
        group = self.curriculum.equipment_entry("flotation-device")
        only = ACT.requirement_counts([needs_group], self.curriculum.equipment)
        for item in group["anyOf"]:
            self.assertEqual(1, only[item], item)
        twice = ACT.requirement_counts([{"equipment": [["kickboard"], ["kickboard"], ["kickboard", "hoop"]]}],
                                       self.curriculum.equipment)
        self.assertEqual({"kickboard": 1}, twice)

    def test_P6_the_full_library(self):
        library = ROOT / "curriculum"
        if not (library / "equipment.json").exists():
            self.skipTest("curriculum/ is not checked out (copyright, v1 D20)")
        curriculum, problems = C.check(library)
        self.assertFalse(C.errors(problems))
        self.assertEqual(PROFILE_LIBRARY, ACT.profile_items(curriculum))


class FilterTests(unittest.TestCase):
    def setUp(self):
        self.curriculum = sample()
        self.pool = fixture_pool()

    def activity(self, activity_id):
        return self.curriculum.activity(activity_id)

    def test_P2_a_required_group_with_nothing_on_hides_optional_never_does(self):
        everything = ACT.default_pool(self.curriculum)
        nap = self.activity("kangaroo-voyage")  # [["kickboard"]]
        chest = self.activity("sunflower-home-base")  # [["small-toys"], ["kickboard"]]
        self.assertIsNone(ACT.hidden_reason(nap, everything, self.curriculum))
        off = dict(everything, equipment=dict(everything["equipment"], kickboard=False))
        self.assertEqual({"kind": "equipment", "missing": [["kickboard"]]}, ACT.hidden_reason(nap, off, self.curriculum))
        self.assertEqual("equipment", ACT.hidden_reason(chest, off, self.curriculum)["kind"])
        self.assertEqual("equipment", ACT.hidden_reason(nap, self.pool, self.curriculum)["kind"])  # the fixture pool
        # optional equipment never hides
        superhero = self.activity("dragon-launch")  # optional kickboard, no requirement
        self.assertEqual([], superhero.get("equipment") or [])
        self.assertIsNone(ACT.hidden_reason(superhero, off, self.curriculum))

    def test_P2_a_prop_never_hides(self):
        everything = ACT.default_pool(self.curriculum)
        straws = self.activity("submarine-peekaboo")  # [["straws"]], a prop
        self.assertIsNone(ACT.hidden_reason(straws, everything, self.curriculum))
        props_off = dict(everything, equipment=dict(everything["equipment"], straws=False, goggles=False))
        self.assertIsNone(ACT.hidden_reason(straws, props_off, self.curriculum))
        self.assertTrue(ACT.is_on(props_off, "straws", self.curriculum))
        self.assertTrue(ACT.is_on({}, "goggles", self.curriculum))
        self.assertFalse(ACT.is_on({}, "kickboard", self.curriculum))  # a missing profile key is off
        # with nothing on, an activity is hidden for equipment exactly when a group offers no prop at all
        profile = set(ACT.profile_items(self.curriculum))

        def profile_only(group):
            for item in group:
                entry = self.curriculum.equipment_entry(item)
                if entry is None:
                    continue
                if entry["kind"] == "item" and item not in profile:
                    return False
                if entry["kind"] == "group" and any(member not in profile for member in entry["anyOf"]):
                    return False
            return True

        hidden_for_equipment = 0
        for activity in self.curriculum.activities:
            reason = ACT.hidden_reason(activity, {}, self.curriculum)
            expected = any(profile_only(group) for group in activity.get("equipment") or [])
            self.assertEqual(expected, reason is not None and reason["kind"] == "equipment", activity["id"])
            hidden_for_equipment += expected
        self.assertTrue(0 < hidden_for_equipment < len(self.curriculum.activities))

    def test_P2_a_group_entry_is_on_when_any_of_its_items_is(self):
        everything = ACT.default_pool(self.curriculum)
        group = self.curriculum.equipment_entry("flotation-device")
        needs_group = [a for a in self.curriculum.activities if ["flotation-device"] in (a.get("equipment") or [])]
        self.assertTrue(needs_group, "the sample has an activity that needs a flotation device")
        activity = needs_group[0]
        profile_members = [item for item in group["anyOf"] if item in everything["equipment"]]
        prop_members = [item for item in group["anyOf"] if item not in everything["equipment"]]
        self.assertTrue(profile_members and prop_members, "the group mixes profile items and props")
        none_on = dict(everything, equipment={k: (k not in group["anyOf"]) for k in everything["equipment"]})
        # a prop member (float belt, life jacket) is always on, so the group is on and nothing hides
        self.assertTrue(ACT.is_on(none_on, "flotation-device", self.curriculum))
        self.assertIsNone(ACT.hidden_reason(activity, none_on, self.curriculum))
        self.assertFalse(ACT.is_on(none_on, "no-such-thing", self.curriculum))
        # a group of profile items only
        only_kickboard = [["kickboard", "pool-noodle"]]
        both_off = dict(none_on, equipment=dict(none_on["equipment"], kickboard=False))
        self.assertEqual({"kind": "equipment", "missing": only_kickboard},
                         ACT.hidden_reason({"id": "x", "equipment": only_kickboard}, both_off, self.curriculum))
        self.assertIsNone(ACT.hidden_reason({"id": "x", "equipment": only_kickboard},
                                            dict(both_off, equipment=dict(both_off["equipment"], kickboard=True)),
                                            self.curriculum))

    def test_P3_depth_and_diving(self):
        hoop_jump = self.activity("volcano-ladder")  # depths medium, deep
        shark = self.activity("iceberg-climb")  # depths shallow
        plain = self.activity("heron-roll-call")  # no depths
        self.assertEqual({"kind": "depth", "depths": ["medium", "deep"]}, ACT.hidden_reason(hoop_jump, self.pool, self.curriculum))
        self.assertIsNone(ACT.hidden_reason(shark, self.pool, self.curriculum))
        all_depths_off = dict(self.pool, depths={"shallow": False, "medium": False, "deep": False})
        self.assertIsNone(ACT.hidden_reason(plain, all_depths_off, self.curriculum))
        deep_on = dict(self.pool, depths={"shallow": True, "medium": False, "deep": True})
        self.assertIsNone(ACT.hidden_reason(hoop_jump, deep_on, self.curriculum))
        dive = {"id": "x-dive", "name": "Dive", "ages": [], "depths": ["deep"], "headfirst": True}
        self.assertEqual({"kind": "diving"}, ACT.hidden_reason(dive, deep_on, self.curriculum))
        self.assertEqual("depth", ACT.hidden_reason(dive, self.pool, self.curriculum)["kind"])
        self.assertIsNone(ACT.hidden_reason(dive, dict(deep_on, diving=True), self.curriculum))

    def test_P4_plan_shuffle_finder_search_and_browse_produce_nothing_the_filter_rejects(self):
        class_ = fixture_class()
        age = ACT.age_tag(class_["ageGroup"])
        everything = ACT.default_pool(self.curriculum)
        props_off = copy.deepcopy(everything)
        props_off["equipment"].update({"goggles": False, "life-jacket": False, "straws": False})
        pools = [self.pool, ACT.normalize_pool({}, self.curriculum), everything, props_off]
        for pool in pools:
            with self.subTest(pool=sorted(k for k, v in pool["equipment"].items() if not v) or pool["depths"]):
                shown = {a["id"] for a in ACT.pool_filter(self.curriculum.activities, pool, self.curriculum, age)}
                plan, problems = day_plan.plan_day(self.curriculum, class_, pool, 5)
                self.assertEqual([], problems)
                for block in plan["blocks"]:
                    self.assertTrue(set(block["activityIds"]) <= shown, block["kind"])
                updated, _ = day_plan.pick_skill(self.curriculum, class_, pool, 5, "introduce", "1.roll")
                updated, result, problems = day_plan.shuffle(self.curriculum, updated, pool, 5, "warmUp")
                if result is not None:
                    self.assertTrue(set(result["activityIds"]) <= shown)
                found, _ = finder.find(self.curriculum, "1", pool, age_tag=age)
                self.assertTrue(set(found["activityIds"]) <= shown)
                browsed, _ = finder.browse(self.curriculum, "1", pool, age)
                for group in browsed["groups"]:
                    self.assertTrue(set(group["activityIds"]) <= shown, group["name"])
                searched, _ = finder.search(self.curriculum, "1", pool, "a", age)
                for group in searched["groups"]:
                    self.assertTrue(set(group["activityIds"]) <= shown, group["name"])
        # a prop's toggle changes nothing anywhere
        with_props = {a["id"] for a in ACT.pool_filter(self.curriculum.activities, everything, self.curriculum, age)}
        without = {a["id"] for a in ACT.pool_filter(self.curriculum.activities, props_off, self.curriculum, age)}
        self.assertEqual(with_props, without)
        self.assertEqual(finder.browse(self.curriculum, "1", everything, age), finder.browse(self.curriculum, "1", props_off, age))
        self.assertEqual(day_plan.plan_day(self.curriculum, class_, everything, 5), day_plan.plan_day(self.curriculum, class_, props_off, 5))

    def test_P5_age(self):
        self.assertEqual("P", ACT.age_tag("preschool"))
        self.assertEqual("S", ACT.age_tag("schoolAge"))
        self.assertEqual("A", ACT.age_tag("teen"))
        self.assertEqual("A", ACT.age_tag("adult"))
        self.assertIsNone(ACT.age_tag("infantToddler"))
        self.assertIsNone(ACT.age_tag(None))
        magic_soap = self.activity("snowflake-hide-and-seek")  # ["P"]
        everything = ACT.default_pool(self.curriculum)
        self.assertEqual({"kind": "age", "ages": ["P"]}, ACT.hidden_reason(magic_soap, everything, self.curriculum, "S"))
        self.assertIsNone(ACT.hidden_reason(magic_soap, everything, self.curriculum, "P"))
        self.assertIsNone(ACT.hidden_reason(magic_soap, everything, self.curriculum, None))
        no_ages = self.activity("tugboat-hello")
        self.assertEqual([], no_ages["ages"])
        for tag in ids.AGE_TAGS:
            self.assertIsNone(ACT.hidden_reason(no_ages, everything, self.curriculum, tag))


if __name__ == "__main__":
    unittest.main()
