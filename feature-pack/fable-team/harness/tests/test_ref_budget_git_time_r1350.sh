#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; HARNESS="$(cd "$TEST_DIR/.." && pwd)"; KIT="$HARNESS/kit/fable-team/bin"; REPO="$(git -C "$HARNESS" rev-parse --show-toplevel)"
processes="$(ps -u "$(id -u)" -o pid= | wc -l | tr -d ' ')"; hard_limit="$(ulimit -Hu)"; test_limit=$((processes + 64))
[[ "$hard_limit" == unlimited || "$test_limit" -le "$hard_limit" ]] || test_limit="$hard_limit"
ulimit -Su "$test_limit"
FT_REPO_ROOT="$REPO" PYTHONPATH="$KIT" timeout 70 python3 - <<'PY'
import os, subprocess, sys, types, unittest
from pathlib import Path
from unittest.mock import patch
import ft_team_lib as lib

clock = [0.0]
queued = []
timeouts = []
class FakeGit:
    pid = 99999999
    def __init__(self, result, duration):
        self.returncode, self.stdout, self.stderr = result
        self.duration = duration
        self.calls = 0
    def communicate(self, timeout):
        timeouts.append(timeout)
        self.calls += 1
        clock[0] += timeout if self.duration == "timeout" else self.duration
        if self.duration == "timeout":
            raise subprocess.TimeoutExpired("git", timeout)
        return self.stdout, self.stderr
    def wait(self, timeout):
        clock[0] += timeout
        return 0
def fake_popen(*_args, **_kwargs):
    result, duration = queued.pop(0)
    return FakeGit(result, duration)
def run(module, steps, callback):
    queued[:] = steps
    timeouts.clear()
    clock[0] = 0.0
    module._clock = lambda: clock[0]
    with patch.object(module.time, "monotonic", side_effect=lambda: clock[0]), patch.object(
        module.subprocess, "Popen", side_effect=fake_popen
    ), patch.object(module.os, "killpg"):
        return callback(), list(timeouts)
def good(duration, body=b"body"):
    return ((0, body, b""), duration)
def mutant_module(replacements):
    source = Path(lib.__file__).read_text(encoding="utf-8")
    for original, changed in replacements:
        if original not in source:
            raise AssertionError(f"mutation anchor missing: {original}")
        source = source.replace(original, changed, 1)
    mutant = types.ModuleType("ft_team_lib_mutant")
    exec(compile(source, "ft_team_lib_mutant.py", "exec"), mutant.__dict__)
    return mutant
def baseline_module():
    source = subprocess.check_output(
        ["git", "-C", os.environ["FT_REPO_ROOT"], "show",
         "8c532ae1:feature-pack/fable-team/harness/kit/fable-team/bin/ft_team_lib.py"],
        text=True,
    )
    baseline = types.ModuleType("ft_team_lib_main_8c532ae1")
    exec(compile(source, "ft_team_lib_main_8c532ae1.py", "exec"), baseline.__dict__)
    return baseline

class RefBudgetTests(unittest.TestCase):
    def setUp(self):
        os.environ["FT_REF_BUDGET_SEC"] = "70"
        lib._REF_SPENT = 0.0
    def test_b1_unrelated_80_seconds_do_not_spend_budget(self):
        def check():
            self.assertEqual(lib.ref_read("/tmp/r", "show", "HEAD:a"), "one")
            clock[0] += 80.0
            self.assertEqual(lib.ref_read("/tmp/r", "show", "HEAD:b"), "two")
        _, limits = run(lib, [good(0.1, b"one"), good(0.1, b"two")], check)
        self.assertEqual(limits, [7.0, 7.0])
    def test_b2_nine_reads_then_4_5_second_tenth_attempt(self):
        def check():
            for _ in range(10):
                lib.ref_read("/tmp/r", "show", "HEAD:a")
            with self.assertRaisesRegex(lib.RefReadError, "예산 소진"):
                lib.ref_read("/tmp/r", "show", "HEAD:a")
        steps = [good(7.0)] * 9 + [good(4.5)]
        _, limits = run(lib, steps, check)
        self.assertEqual(limits, [7.0] * 9 + [4.5])
        self.assertAlmostEqual(lib._REF_SPENT, 67.5)
    def test_b3_three_seconds_left_caps_attempt_at_half_second(self):
        lib._REF_SPENT = 67.0
        _, limits = run(lib, [good(0.5)], lambda: lib.ref_read("/tmp/r", "show", "HEAD:a"))
        self.assertEqual(limits, [0.5])
    def test_b4_empty_retry_counts_both_attempts(self):
        os.environ["FT_REF_BUDGET_SEC"] = "10"
        def check():
            with self.assertRaisesRegex(lib.RefReadError, "빈 응답 2회"):
                lib.ref_read("/tmp/r", "show", "HEAD:a")
        run(lib, [((0, b"", b""), 0.4), ((0, b"", b""), 0.6)], check)
        self.assertAlmostEqual(lib._REF_SPENT, 1.0)
    def test_b5_nonzero_rc_spends_attempt_time(self):
        os.environ["FT_REF_BUDGET_SEC"] = "10"
        def check():
            with self.assertRaisesRegex(lib.RefReadError, "못 읽음"):
                lib.ref_read("/tmp/r", "show", "HEAD:a")
        run(lib, [((1, b"", b"fatal"), 1.2)], check)
        self.assertAlmostEqual(lib._REF_SPENT, 1.2)
    def test_b6_ref_present_ignores_other_work_gap(self):
        def check():
            lib.ref_read("/tmp/r", "show", "HEAD:a")
            clock[0] += 80.0
            self.assertTrue(lib._ref_present("/tmp/r", "HEAD:a"))
        run(lib, [good(0.1), ((0, b"", b""), 0.1)], check)
    def test_b6b_ref_present_spend_sets_next_attempt_to_2_4(self):
        os.environ["FT_REF_BUDGET_SEC"] = "10"
        def check():
            lib.ref_read("/tmp/r", "show", "HEAD:a")
            self.assertTrue(lib._ref_present("/tmp/r", "HEAD:a"))
            lib.ref_read("/tmp/r", "show", "HEAD:a")
        _, limits = run(lib, [good(0.1), ((0, b"", b""), 5.0), good(2.4)], check)
        self.assertEqual(limits[:2], [7.0, 7.0])
        self.assertAlmostEqual(limits[2], 2.4)
    def test_b7_invalid_budget_override_falls_back_to_70(self):
        os.environ["FT_REF_BUDGET_SEC"] = "not-a-number"
        self.assertEqual(lib._ref_remaining(), 70.0)
    def test_b8_reserve_exhaustion_makes_zero_git_attempts(self):
        lib._REF_SPENT = 69.8
        def check():
            with self.assertRaisesRegex(lib.RefReadError, "예산 소진"):
                lib.ref_read("/tmp/r", "show", "HEAD:a")
        _, limits = run(lib, [], check)
        self.assertEqual(limits, [])
    def test_b9_timeout_counts_attempt_limit_plus_cleanup_2_5(self):
        def check():
            self.assertEqual(lib._git_once("/tmp/r", ["show", "HEAD:a"], 7.0), (124, "", ""))
        run(lib, [((0, b"", b""), "timeout")], check)
        self.assertAlmostEqual(lib._REF_SPENT, 9.5)
    def test_baseline_main_8c532ae1_fails_b1_and_b6(self):
        baseline = baseline_module()
        baseline._REF_T0 = None
        def check_b1():
            baseline.ref_read("/tmp/r", "show", "HEAD:a")
            clock[0] += 80.0
            with self.assertRaises(baseline.RefReadError):
                baseline.ref_read("/tmp/r", "show", "HEAD:b")
        run(baseline, [good(0.1)], check_b1)
        baseline._REF_T0 = None
        def check_b6():
            baseline.ref_read("/tmp/r", "show", "HEAD:a")
            clock[0] += 80.0
            with self.assertRaises(baseline.RefReadError):
                baseline._ref_present("/tmp/r", "HEAD:a")
        run(baseline, [good(0.1)], check_b6)
    def test_mutation_1_wall_clock_is_caught(self):
        mutant = mutant_module([
            ("_REF_SPENT = 0.0\n", "_REF_SPENT = 0.0\n_REF_T0 = None\n"),
            ("    try:\n        budget = float(os.environ.get(\"FT_REF_BUDGET_SEC\") or REF_BUDGET_S)",
             "    global _REF_T0\n    if _REF_T0 is None: _REF_T0 = _clock()\n    try:\n        budget = float(os.environ.get(\"FT_REF_BUDGET_SEC\") or REF_BUDGET_S)"),
            ("return budget - _REF_SPENT", "return _REF_T0 + budget - _clock()"),
        ])
        def check():
            mutant._ref_remaining()
            clock[0] += 80.0
            self.assertEqual(mutant._ref_remaining(), 70.0)
        with self.assertRaises(AssertionError): run(mutant, [], check)
    def test_mutation_2_no_accumulation_is_caught(self):
        mutant = mutant_module([("_REF_SPENT += max(0.0, _clock() - started)", "_REF_SPENT += 0.0")])
        mutant._REF_SPENT = 0.0
        def check():
            mutant._git_once("/tmp/r", ["show", "HEAD:a"], 7.0)
            self.assertEqual(mutant._REF_SPENT, 2.0)
        with self.assertRaises(AssertionError): run(mutant, [good(2.0)], check)
    def test_mutation_3_fixed_seven_second_cap_is_caught(self):
        mutant = mutant_module([("return max(0.0, min(7.0, left - REF_CLEANUP_RESERVE_S))", "return 7.0")])
        with self.assertRaises(AssertionError): self.assertEqual(mutant._ref_attempt_limit(3.0), 0.5)
    def test_mutation_4_ref_present_unaccounted_is_caught(self):
        mutant = mutant_module([(
            "_REF_SPENT += max(0.0, _clock() - started)",
            "if not (args and args[0] == \"cat-file\"): _REF_SPENT += max(0.0, _clock() - started)",
        )])
        mutant._REF_SPENT = 0.0
        os.environ["FT_REF_BUDGET_SEC"] = "10"
        def check():
            mutant._ref_present("/tmp/r", "HEAD:a")
            self.assertAlmostEqual(mutant._REF_SPENT, 5.0)
        with self.assertRaises(AssertionError): run(mutant, [((0, b"", b""), 5.0)], check)
    def test_mutation_5_reserve_removal_is_caught(self):
        mutant = mutant_module([("return max(0.0, min(7.0, left - REF_CLEANUP_RESERVE_S))", "return min(7.0, left)")])
        with self.assertRaises(AssertionError): self.assertEqual(mutant._ref_attempt_limit(69.8), 0.0)
    def test_mutation_6_timeout_cleanup_unaccounted_is_caught(self):
        mutant = mutant_module([(
            "_REF_SPENT += max(0.0, _clock() - started)",
            "_REF_SPENT += min(lim, max(0.0, _clock() - started))",
        )])
        mutant._REF_SPENT = 0.0
        def check():
            mutant._git_once("/tmp/r", ["show", "HEAD:a"], 7.0)
            self.assertAlmostEqual(mutant._REF_SPENT, 9.5)
        with self.assertRaises(AssertionError): run(mutant, [((0, b"", b""), "timeout")], check)
if __name__ == "__main__":
    unittest.main(verbosity=2)
PY
