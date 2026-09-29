"""Shared loaders for the v2 tests: the Stage 1 sample, the fixture class and pool."""

import copy
import json
from pathlib import Path

from tools.core import curriculum as C

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / "examples"
SAMPLE = EXAMPLES / "curriculum.stage1.sample.json"


def load_json(name):
    with open(EXAMPLES / name, encoding="utf-8") as handle:
        return json.load(handle)


def read_text(name):
    return (EXAMPLES / name).read_text(encoding="utf-8")


def sample():
    curriculum = C.load(SAMPLE)
    assert not C.errors(C.validate(curriculum)), "the Stage 1 sample must validate"
    return curriculum


def fixture_class():
    return copy.deepcopy(load_json("class.stage1.json")["items"][0])


def fixture_pool():
    return copy.deepcopy(load_json("pool.shallow.json")["items"][0])


def manifest_case(case_id):
    for case in load_json("manifest.json")["cases"]:
        if case["id"] == case_id:
            return case
    raise KeyError(case_id)
