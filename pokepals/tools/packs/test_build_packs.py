"""Tests for the pure parts of build_packs.py. Run:  python3 -m unittest discover -s pokepals/tools/packs"""
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_packs as bp  # noqa: E402

CONFIG = {"base_worlds": ["vale", "home"], "kit_max_worlds": 3}


def art(*names):
    return {f"res://assets/sprites/{n}.png" for n in names}


class PlanTests(unittest.TestCase):
    def plan(self, seen, pins=()):
        return bp.plan(seen, CONFIG, list(pins))

    def test_what_only_one_other_world_loads_becomes_its_pack(self):
        packs, worlds = self.plan({"vale": art("grass"), "noct": art("grass", "glow", "moss")})
        self.assertEqual(sorted(packs), ["noct"])
        self.assertEqual(sorted(packs["noct"]["files"]), sorted(art("glow", "moss")))
        self.assertEqual(worlds, {"noct": ["noct"]})

    def test_what_the_base_worlds_load_stays_in_the_base(self):
        packs, _ = self.plan({"vale": art("a"), "home": art("b"), "x": art("a", "b")})
        self.assertEqual(packs, {})

    def test_pinned_files_stay_in_the_base_whatever_the_audit_saw(self):
        packs, _ = self.plan({"vale": art("a"), "x": art("player", "portal_ring", "own")},
                             pins=["res://assets/sprites/player.png", "res://assets/sprites/portal_*"])
        self.assertEqual(packs["x"]["files"], sorted(art("own")))

    def test_art_shared_by_a_few_worlds_becomes_one_kit_they_all_need(self):
        packs, worlds = self.plan({"vale": art("a"), "x": art("kit", "x1"), "y": art("kit", "y1")})
        self.assertEqual(sorted(packs), ["kit-x-y", "x", "y"])
        self.assertEqual(packs["kit-x-y"]["files"], sorted(art("kit")))
        self.assertEqual(worlds["x"], ["kit-x-y", "x"])
        self.assertEqual(worlds["y"], ["kit-x-y", "y"])

    def test_art_loaded_by_many_worlds_is_general_purpose_and_joins_the_base(self):
        seen = {"vale": art("a")}
        for w in "wxyz":
            seen[w] = art("common", f"own_{w}")
        packs, _ = self.plan(seen)
        self.assertNotIn("res://assets/sprites/common.png", [f for p in packs.values() for f in p["files"]])
        self.assertEqual(sorted(packs), ["w", "x", "y", "z"])

    def test_a_world_with_nothing_of_its_own_gets_no_pack(self):
        packs, worlds = self.plan({"vale": art("a", "b"), "plain": art("a", "b")})
        self.assertEqual((packs, worlds), ({}, {}))


class PresetTests(unittest.TestCase):
    CFG = (
        '[preset.0]\n\nname="iOS"\nexclude_filter=""\n\n[preset.0.options]\n\nx=1\n\n'
        '[preset.1]\n\nname="Web"\nexclude_filter="*.md"\n\n[preset.1.options]\n\nhtml/export_icon=true\n'
    )

    def test_only_the_web_preset_is_kept_and_the_packed_files_are_excluded(self):
        with tempfile.TemporaryDirectory() as d:
            work = Path(d)
            (work / "export_presets.cfg").write_text(self.CFG)
            bp.write_presets(work, ["assets/b.png", "assets/a.png"])
            out = (work / "export_presets.cfg").read_text()
        self.assertEqual(re.findall(r'(?m)^name="(.*)"$', out), ["Web"])
        self.assertIn("[preset.0]", out)
        self.assertIn("[preset.0.options]", out)
        self.assertNotIn("iOS", out)
        self.assertIn('exclude_filter="*.md,assets/a.png,assets/b.png"', out)  # existing filters are kept


class LogParsingTests(unittest.TestCase):
    def test_only_source_assets_are_read_from_the_verbose_log(self):
        log = ("Loading resource: res://assets/sprites/a.png\n"
               "Loading resource: res://.godot/imported/a.png-123.ctex\n"
               "Loading resource: res://scripts/x.gd\n"
               "Loading resource: res://assets/pals/fox_0.png\n")
        self.assertEqual(bp.loaded_assets(log), {"res://assets/sprites/a.png", "res://assets/pals/fox_0.png"})


if __name__ == "__main__":
    unittest.main()
