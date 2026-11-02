#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="$(cd "$TEST_DIR/.." && pwd)"
KIT="$HARNESS/kit/fable-team/bin"
processes="$(ps -u "$(id -u)" -o pid= | wc -l | tr -d ' ')"
hard_limit="$(ulimit -Hu)"
test_limit=$((processes + 64))
if [[ "$hard_limit" != unlimited && "$test_limit" -gt "$hard_limit" ]]; then test_limit="$hard_limit"; fi
ulimit -Su "$test_limit"

PYTHONPATH="$KIT" timeout 70 python3 - <<'PY'
import os
import subprocess
import types
import unittest
from unittest.mock import patch

import ft_team_lib as lib

clock = [0.0]
durations = []
timeouts = []


class FakeGit:
    pid = 99999999

    def __init__(self, result, duration):
        self.returncode, self.stdout, self.stderr = result
        self.duration = duration

    def communicate(self, timeout):
        timeouts.append(timeout)
        clock[0] += self.duration
        return self.stdout, self.stderr


def fake_popen(*_args, **_kwargs):
    return FakeGit(durations.pop(0), durations.pop(0))


def queue_git(*results_and_durations):
    durations[:] = list(results_and_durations)


def mutant_module(replacements):
    from pathlib import Path

    source = Path(lib.__file__).read_text(encoding="utf-8")
    for original, changed in replacements:
        if original not in source:
            raise AssertionError(f"mutation anchor missing: {original}")
        source = source.replace(original, changed, 1)
    mutant = types.ModuleType("ft_team_lib_mutant")
    exec(compile(source, "ft_team_lib_mutant.py", "exec"), mutant.__dict__)
    return mutant


def baseline_module():
    return mutant_module([
        ("_REF_SPENT = 0.0\n", "_REF_SPENT = 0.0\n_REF_T0: float | None = None\n"),
        ("    try:\n        budget = float(os.environ.get(\"FT_REF_BUDGET_SEC\") or REF_BUDGET_S)",
         "    global _REF_T0\n    if _REF_T0 is None:\n        _REF_T0 = time.monotonic()\n    try:\n        budget = float(os.environ.get(\"FT_REF_BUDGET_SEC\") or REF_BUDGET_S)"),
        ("return budget - _REF_SPENT", "return _REF_T0 + budget - time.monotonic()"),
    ])


class RefReadBudgetTests(unittest.TestCase):
    def setUp(self):
        os.environ["FT_REF_BUDGET_SEC"] = "10"
        lib._REF_SPENT = 0.0
        clock[0] = 0.0
        durations.clear()
        timeouts.clear()

    def run_git(self, *items):
        queue_git(*items)
        with patch.object(lib.subprocess, "Popen", side_effect=fake_popen), patch.object(
            lib.time, "monotonic", side_effect=lambda: clock[0]
        ):
            return lib._git_once("/tmp/repo", ["show", "HEAD:file"], 7.0)

    def test_b1_idle_time_does_not_spend_budget(self):
        with patch.object(lib.time, "monotonic", side_effect=lambda: clock[0]):
            self.assertEqual(lib._ref_remaining(), 10.0)
            clock[0] = 9999.0
            self.assertEqual(lib._ref_remaining(), 10.0)

    def test_b2_one_git_duration_is_charged(self):
        self.run_git((0, b"x", b""), 2.5)
        self.assertEqual(lib._ref_remaining(), 7.5)

    def test_b3_multiple_git_durations_are_summed(self):
        self.run_git((0, b"x", b""), 2.5)
        self.run_git((0, b"x", b""), 3.0)
        self.assertEqual(lib._ref_remaining(), 4.5)

    def test_b4_ref_read_keeps_seven_second_attempt_cap(self):
        queue_git((0, b"body", b""), 7.8)
        with patch.object(lib.subprocess, "Popen", side_effect=fake_popen), patch.object(
            lib.time, "monotonic", side_effect=lambda: clock[0]
        ):
            self.assertEqual(lib.ref_read("/tmp/repo", "show", "HEAD:file"), "body")
        self.assertEqual(timeouts, [7.0])
        self.assertAlmostEqual(lib._ref_remaining(), 2.2)

    def test_b5_ref_present_time_reduces_next_attempt_limit(self):
        queue_git((0, b"", b""), 7.6, (0, b"body", b""), 2.0)
        with patch.object(lib.subprocess, "Popen", side_effect=fake_popen), patch.object(
            lib.time, "monotonic", side_effect=lambda: clock[0]
        ):
            self.assertTrue(lib._ref_present("/tmp/repo", "HEAD:file"))
            self.assertEqual(lib.ref_read("/tmp/repo", "show", "HEAD:file"), "body")
        self.assertEqual(timeouts[0], 7.0)
        self.assertAlmostEqual(timeouts[1], 2.4)

    def test_b6_failed_git_attempt_still_spends_time(self):
        self.assertEqual(lib._ref_remaining(), 10.0)
        self.assertEqual(self.run_git((1, b"", b"fatal"), 2.0), (1, "", "fatal"))
        clock[0] = 1000.0
        queue_git((0, b"body", b""), 0.1)
        with patch.object(lib.subprocess, "Popen", side_effect=fake_popen), patch.object(
            lib.time, "monotonic", side_effect=lambda: clock[0]
        ):
            self.assertEqual(lib.ref_read("/tmp/repo", "show", "HEAD:file"), "body")
        self.assertAlmostEqual(lib._ref_remaining(), 7.9)

    def test_b7_empty_retry_spends_both_git_attempts(self):
        os.environ["FT_REF_BUDGET_SEC"] = "5.2"
        queue_git((0, b"", b""), 3.0, (0, b"", b""), 2.2)
        with patch.object(lib.subprocess, "Popen", side_effect=fake_popen), patch.object(
            lib.time, "monotonic", side_effect=lambda: clock[0]
        ), self.assertRaisesRegex(lib.RefReadError, "빈 응답 2회"):
            lib.ref_read("/tmp/repo", "show", "HEAD:file")
        self.assertEqual(len(timeouts), 2)
        self.assertAlmostEqual(lib._ref_remaining(), 0.0)

    def test_baseline_b1_and_b6_fail_after_unrelated_elapsed_time(self):
        baseline = baseline_module()
        with patch.object(baseline.time, "monotonic", side_effect=lambda: clock[0]):
            clock[0] = 0.0
            self.assertEqual(baseline._ref_remaining(), 10.0)
            clock[0] = 9999.0
            self.assertNotEqual(baseline._ref_remaining(), 10.0)
            baseline._REF_T0 = 0.0
            clock[0] = 2.0
            baseline._REF_SPENT = 2.0
            clock[0] = 1000.0
            with self.assertRaises(baseline.RefReadError):
                baseline.ref_read("/tmp/repo", "show", "HEAD:file")

    def test_mutation_1_wall_clock_budget_is_caught(self):
        mutant = mutant_module([("return budget - _REF_SPENT", "return budget - _REF_SPENT - time.monotonic()")])
        with patch.object(mutant.time, "monotonic", return_value=9999.0):
            with self.assertRaises(AssertionError):
                self.assertEqual(mutant._ref_remaining(), 10.0)

    def test_mutation_2_unaccounted_git_time_is_caught(self):
        mutant = mutant_module([("_REF_SPENT += max(0.0, time.monotonic() - started)", "_REF_SPENT += 0.0")])
        self.run_git((0, b"x", b""), 2.5)
        queue_git((0, b"x", b""), 2.5)
        with patch.object(mutant.subprocess, "Popen", side_effect=fake_popen), patch.object(
            mutant.time, "monotonic", side_effect=lambda: clock[0]
        ):
            mutant._git_once("/tmp/repo", ["show", "HEAD:file"], 7.0)
        with self.assertRaises(AssertionError):
            self.assertEqual(mutant._ref_remaining(), 7.5)

    def test_mutation_3_ignored_ref_present_time_is_caught(self):
        mutant = mutant_module([(
            "_REF_SPENT += max(0.0, time.monotonic() - started)",
            "if not (args and args[0] == \"cat-file\"): _REF_SPENT += max(0.0, time.monotonic() - started)",
        )])
        queue_git((0, b"", b""), 7.6)
        with patch.object(mutant.subprocess, "Popen", side_effect=fake_popen), patch.object(
            mutant.time, "monotonic", side_effect=lambda: clock[0]
        ):
            mutant._ref_present("/tmp/repo", "HEAD:file")
        with self.assertRaises(AssertionError):
            self.assertAlmostEqual(mutant._ref_remaining(), 2.4)


if __name__ == "__main__":
    unittest.main(verbosity=2)
PY
