"""F1–F6: the activity finder and browse (TEST_CASES.md group F)."""

import math
import unittest

from tools.core import activities as ACT
from tools.core import canonical
from tools.core import finder as F

from tests.v2support import fixture_pool, load_json, manifest_case, read_text, sample

FRONT_GLIDE_GUIDE_PAIRED = ["puffin-rocket-ride", "meteor-torpedo", "comet-rocket-ride", "jellybean-express"]


class FinderTests(unittest.TestCase):
    def setUp(self):
        self.curriculum = sample()
        self.pool = fixture_pool()
        self.expected = load_json("finder.stage1.expected.json")

    def query(self, query_id):
        return next(q for q in self.expected["queries"] if q["id"] == query_id)["pages"]

    def test_F1_stage_only_seeded_paged_and_wrapping(self):
        ordered, problems = F.candidates(self.curriculum, "1", self.pool)
        self.assertEqual([], problems)
        self.assertEqual(68, len(ordered))  # 71 in the sample; volcano-ladder (depth), sunflower-home-base and kangaroo-voyage (kickboard) hidden
        self.assertEqual(len(set(ordered)), len(ordered))
        self.assertNotIn("volcano-ladder", ordered)
        self.assertEqual(ordered, F.candidates(self.curriculum, "1", self.pool)[0])
        page1, _ = F.find(self.curriculum, "1", self.pool)
        page2, _ = F.find(self.curriculum, "1", self.pool, page_number=2)
        self.assertEqual(self.query("stage"), [page1, page2])
        self.assertEqual(ordered[:3], page1["activityIds"])
        self.assertEqual(ordered[3:6], page2["activityIds"])
        self.assertEqual((1, 3, 68, False), (page1["page"], page1["pageSize"], page1["total"], page1["wrapped"]))
        last = math.ceil(68 / 3)
        wrapped, _ = F.find(self.curriculum, "1", self.pool, page_number=last + 1)
        self.assertTrue(wrapped["wrapped"])
        self.assertEqual(page1["activityIds"], wrapped["activityIds"])  # page 1 again
        final, _ = F.find(self.curriculum, "1", self.pool, page_number=last)
        self.assertEqual((2, False), (len(final["activityIds"]), final["wrapped"]))  # 68 = 22 * 3 + 2
        self.assertEqual({"page": 1, "pageSize": 3, "total": 0, "activityIds": [], "wrapped": False}, F.page([], 1))
        self.assertEqual(["a", "b"], F.page(["a", "b"], 1)["activityIds"])
        self.assertEqual(["a", "b"], F.page(["a", "b"], 2)["activityIds"])
        self.assertTrue(F.page(["a", "b"], 2)["wrapped"])
        self.assertEqual(["d"], F.page(["a", "b", "c", "d"], 2)["activityIds"])
        self.assertEqual(["a", "b", "c"], F.page(["a", "b", "c", "d"], 3)["activityIds"])

    def test_F2_stage_and_skill(self):
        ordered, problems = F.candidates(self.curriculum, "1", self.pool, "1.front-glide")
        self.assertEqual([], problems)
        skill_ids = set(self.curriculum.skill("1.front-glide")["activityIds"])
        self.assertEqual(skill_ids, set(ordered))
        self.assertEqual(12, len(ordered))
        page1, _ = F.find(self.curriculum, "1", self.pool, "1.front-glide")
        page2, _ = F.find(self.curriculum, "1", self.pool, "1.front-glide", page_number=2)
        self.assertEqual(self.query("skill"), [page1, page2])
        self.assertNotEqual(ordered, F.candidates(self.curriculum, "1", self.pool)[0][:12])
        for skill_id, step, code in (("2.front-glide", None, "finder-skill"), ("1.front-glide", 9, "finder-step"),
                                     (None, 2, "finder-step")):
            _, problems = F.find(self.curriculum, "1", self.pool, skill_id, step)
            self.assertEqual([code], [p.code for p in problems])
        _, problems = F.find(self.curriculum, "9", self.pool)
        self.assertEqual(["finder-stage"], [p.code for p in problems])

    def test_F3_a_step_puts_the_guide_paired_activities_first(self):
        self.assertEqual(FRONT_GLIDE_GUIDE_PAIRED, F.guide_paired(self.curriculum, "1", "1.front-glide", 2))
        ordered, _ = F.candidates(self.curriculum, "1", self.pool, "1.front-glide", 2)
        self.assertEqual(FRONT_GLIDE_GUIDE_PAIRED, ordered[:4])
        self.assertEqual(12, len(ordered))
        self.assertEqual(set(self.curriculum.skill("1.front-glide")["activityIds"]), set(ordered))
        page1, _ = F.find(self.curriculum, "1", self.pool, "1.front-glide", 2)
        page2, _ = F.find(self.curriculum, "1", self.pool, "1.front-glide", 2, page_number=2)
        self.assertEqual(self.query("skill-step"), [page1, page2])
        self.assertEqual(manifest_case("F1.finder")["expected"]["frontGlideStep2FirstPage"], page1["activityIds"])
        # the remainder is seeded by the inputs, step included
        without_step, _ = F.candidates(self.curriculum, "1", self.pool, "1.front-glide")
        self.assertNotEqual(without_step, ordered)

    def test_F4_age_applies_only_from_a_class(self):
        all_ages, _ = F.candidates(self.curriculum, "1", self.pool)
        school_age, _ = F.candidates(self.curriculum, "1", self.pool, age_tag="S")
        self.assertIn("snowflake-hide-and-seek", all_ages)
        self.assertNotIn("snowflake-hide-and-seek", school_age)
        self.assertTrue(set(school_age) < set(all_ages))
        page1, _ = F.find(self.curriculum, "1", self.pool, "1.front-glide", age_tag="S")
        page2, _ = F.find(self.curriculum, "1", self.pool, "1.front-glide", age_tag="S", page_number=2)
        self.assertEqual(self.query("skill-age"), [page1, page2])
        self.assertEqual("S", page1["ageTag"])

    def test_F5_detail(self):
        self.curriculum.videos.append({"id": "vimeo:1", "skillIds": ["1.front-glide"], "stageIds": ["1"],
                                       "title": "Front glide", "url": "https://vimeo.com/1"})
        item = F.detail(self.curriculum, "comet-rocket-ride", "1.front-glide")
        self.assertEqual("Comet Rocket Ride", item["name"])
        self.assertTrue(item["description"])
        self.assertEqual(["pool noodle or rescue tube or rope"], item["equipment"])
        self.assertEqual([], item["equipmentOptional"])
        self.assertEqual(["P", "S", "A"], item["ages"])
        self.assertTrue(item["submerges"])
        self.assertEqual(["Front glide"], item["videos"])
        self.assertEqual(["Front glide"], F.detail(self.curriculum, "comet-rocket-ride")["videos"])
        self.assertEqual([], F.detail(self.curriculum, "comet-rocket-ride", "1.submerge")["videos"])
        straws = F.detail(self.curriculum, "submarine-peekaboo")
        self.assertEqual(["straws"], straws["equipment"])
        self.assertEqual(["ball", "whistle"], straws["equipmentOptional"])
        self.assertIsNone(F.detail(self.curriculum, "no-such"))

    def test_F6_browse(self):
        result, problems = F.browse(self.curriculum, "1", self.pool)
        self.assertEqual([], problems)
        self.assertEqual(self.expected["browse"], result)
        self.assertEqual("Greeting", result["groups"][0]["name"])
        self.assertIsNone(result["groups"][0]["skillId"])
        self.assertEqual([s["id"] for s in self.curriculum.skills_of("1")], [g["skillId"] for g in result["groups"][1:]])
        self.assertEqual(manifest_case("F1.finder")["expected"]["browseGroupSizes"], [len(g["activityIds"]) for g in result["groups"]])
        position = ACT.catalog_position(self.curriculum)
        for group in result["groups"]:
            positions = [position[a] for a in group["activityIds"]]
            self.assertEqual(sorted(positions), positions, group["name"])
        adults, _ = F.browse(self.curriculum, "1", self.pool, "A")
        back_float = next(g for g in adults["groups"] if g["skillId"] == "1.back-float")
        self.assertEqual([], back_float["activityIds"])  # its three activities are all P/S
        self.assertEqual(len(result["groups"]), len(adults["groups"]))

    def test_F7_search_by_name_case_and_diacritic_insensitive_grouped_by_skill(self):
        glide, problems = F.search(self.curriculum, "1", self.pool, "glide")
        self.assertEqual([], problems)
        self.assertEqual(self.expected["search"][0], glide)
        self.assertEqual(["1.front-glide", "1.back-glide"], [g["skillId"] for g in glide["groups"]])
        for group in glide["groups"]:
            self.assertTrue(group["activityIds"])
            for activity_id in group["activityIds"]:
                self.assertIn("glide", self.curriculum.activity(activity_id)["name"].lower())
        browsed, _ = F.browse(self.curriculum, "1", self.pool)
        for group in glide["groups"]:
            shown = next(g for g in browsed["groups"] if g["skillId"] == group["skillId"])["activityIds"]
            self.assertEqual([a for a in shown if "glide" in self.curriculum.activity(a)["name"].lower()], group["activityIds"])
        upper, _ = F.search(self.curriculum, "1", self.pool, "GLIDE")
        self.assertEqual(glide["groups"], upper["groups"])
        self.assertEqual(self.expected["search"][1], upper)
        accented, _ = F.search(self.curriculum, "1", self.pool, "glidé")
        self.assertEqual(glide["groups"], accented["groups"])
        padded, _ = F.search(self.curriculum, "1", self.pool, "  glide ")
        self.assertEqual(glide["groups"], padded["groups"])
        for text in ("zzz", "", "   "):
            result, problems = F.search(self.curriculum, "1", self.pool, text)
            self.assertEqual([], problems)
            self.assertEqual([], result["groups"], repr(text))
        self.assertEqual(self.expected["search"][2], F.search(self.curriculum, "1", self.pool, "zzz")[0])
        expected = manifest_case("F7.search")["expected"]["groups"]
        self.assertEqual(expected[0], [{"skillId": g["skillId"], "activityIds": g["activityIds"]} for g in glide["groups"]])
        self.assertEqual([], expected[2])
        # the age tag applies as in browse
        adults, _ = F.search(self.curriculum, "1", self.pool, "float", "A")
        self.assertNotIn("1.back-float", [g["skillId"] for g in adults["groups"]])  # its activities are all P/S
        self.assertEqual("flotte", F.fold("FLOTTÉ"))
        result, problems = F.search(self.curriculum, "9", self.pool, "glide")
        self.assertIsNone(result)
        self.assertEqual(["finder-stage"], [p.code for p in problems])

    def test_fixture_file_and_hash(self):
        text = canonical.dumps({"stageId": "1", "queries": self.expected["queries"], "browse": self.expected["browse"],
                                "search": self.expected["search"]}) + "\n"
        self.assertEqual(read_text("finder.stage1.expected.json"), text)
        self.assertEqual(manifest_case("F1.finder")["expected"]["sha256"], canonical.sha256_hex(text))


if __name__ == "__main__":
    unittest.main()
