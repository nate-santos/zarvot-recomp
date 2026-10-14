"""Synthetic log tests for the opt-in CPU wall-time stall diagnostic parser."""

import contextlib
import importlib.util
import io
import json
import pathlib
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    "analyze_zarvot_stalls", pathlib.Path(__file__).resolve().parents[1] / "scripts/analyze-zarvot-stalls.py")
STALLS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STALLS)
FIXTURE_ROOT = pathlib.Path(__file__).resolve().parents[1] / "build/stall-parser-tests"


def record(timestamp=1.5, interval="120.5", *, draw="4.2", draws="3", build="2.0", builds="1",
           idle="117.0", frame_wait="0.0", newline="\n"):
    return (f"[ {timestamp}] Render.Vulkan <Info> video_core\\renderer_vulkan\\vk_stall_probe.h:72:ReportFrame: "
            f"STALL present_interval={interval}ms completed_scope_totals(overlap_possible): "
            f"gpu_idle={idle}ms draw={draw}ms(n={draws}) sched_wait=0.1ms "
            f"build_wait={build}ms(n={builds}) acquire=0.2ms present=0.3ms frame_wait={frame_wait}ms{newline}")


class StallTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        FIXTURE_ROOT.mkdir(parents=True, exist_ok=True)

    def test_exact_format_units_counts_and_summary(self):
        result = STALLS.parse_log(["ordinary startup\n", record(), record(2.5, "200.0", draw="8.4", draws="5", builds="0")])
        self.assertEqual(result["analysis_state"], "complete")
        self.assertEqual(result["valid_record_count"], 2)
        self.assertEqual(result["present_intervals"], dict(samples=2, nonzero_samples=2,
                                                          minimum_ms=120.5, median_ms=160.25, maximum_ms=200.0))
        self.assertAlmostEqual(result["completed_scope_observations"]["draw"]["median_ms"], 6.3)
        self.assertEqual(result["completed_scope_counts"]["draw"]["total_reported_count"], 8)
        self.assertEqual(result["completed_scope_counts"]["build_wait"]["nonzero_samples"], 1)
        self.assertEqual(result["records"][0]["line_number"], 2)
        self.assertEqual(result["records"][0]["completed_scope_counts"], dict(draw=3, build_wait=1))
        self.assertEqual(result["probe"]["enablement_evidence"], "valid_stall_records")

    def test_chronology_preserves_file_order_and_marks_regressions(self):
        result = STALLS.parse_log([record("3.000001"), record(4), record(1), record(1), record(2)])
        self.assertEqual([row["log_seconds"] for row in result["records"]], [3.000001, 4, 1, 1, 2])
        self.assertEqual([row["timestamp_segment"] for row in result["records"]], [1, 1, 2, 2, 2])
        self.assertEqual(result["chronology"]["timestamp_regression_count"], 1)
        self.assertEqual(result["chronology"]["timestamp_segments"], 2)
        self.assertEqual(result["chronology"]["first_log_seconds"], 3.000001)
        self.assertEqual(result["chronology"]["last_log_seconds"], 2)
        self.assertEqual(result["chronology"]["minimum_log_seconds"], 1)
        self.assertEqual(result["chronology"]["maximum_log_seconds"], 4)

    def test_malformed_truncated_or_wrong_units_are_not_silent(self):
        bad = [record().replace("frame_wait=0.0ms", "frame_wait="),
               record().replace("draw=4.2ms", "draw=4.2s"),
               record().replace("(n=3)", "(n=-1)"),
               record().replace("[ 1.5]", "[ missing]"),
               record().replace("frame_wait=0.0ms", "frame_wait=NaNms"),
               record().replace("acquire=0.2ms ", ""),
               record().replace("[ 1.5]", "[ -1.5]"),
               "STALL\n"]
        result = STALLS.parse_log([*bad, record(3, newline="")])
        self.assertEqual(result["analysis_state"], "partial")
        self.assertEqual(result["valid_record_count"], 1)
        self.assertEqual(result["malformed_record_count"], len(bad))
        self.assertEqual([row["line_number"] for row in result["malformed_records"]], list(range(1, len(bad) + 1)))
        self.assertEqual(result["records"][0]["line_number"], len(bad) + 1)

    def test_out_of_range_values_and_maximum_u64_count(self):
        result = STALLS.parse_log([record(draws=str((1 << 64) - 1)), record(draws=str(1 << 64)),
                                  record(interval="9" * 400)])
        self.assertEqual(result["valid_record_count"], 1)
        self.assertEqual(result["completed_scope_counts"]["draw"]["total_reported_count"], (1 << 64) - 1)
        self.assertEqual(result["malformed_record_count"], 2)
        self.assertTrue(all(row["reason"] == "numeric_value_out_of_range" for row in result["malformed_records"]))

    def test_empty_old_and_enablement_states_stay_distinct(self):
        old = ["[ 1.0] Frontend <Info> startup.cpp:1:main: Started\n"]
        self.assertEqual(STALLS.parse_log([])["observation_state"], "empty_log")
        self.assertEqual(STALLS.parse_log([" \n"])["observation_state"], "empty_log")
        self.assertEqual(STALLS.parse_log(old)["observation_state"], "no_stall_records_not_known_enabled")
        self.assertEqual(STALLS.parse_log(old, probe_state="enabled")["observation_state"], "no_stall_records_enabled_asserted")
        self.assertEqual(STALLS.parse_log(old, launch_requested=True)["observation_state"], "no_stall_records_requested_unconfirmed")
        self.assertEqual(STALLS.parse_log(old, launch_requested=False)["observation_state"], "no_stall_records_not_requested")
        self.assertEqual(STALLS.parse_log(old, probe_state="disabled")["observation_state"], "no_stall_records_disabled_asserted")
        malformed = STALLS.parse_log(["STALL\n"], probe_state="enabled")
        self.assertEqual(malformed["observation_state"], "malformed_stall_records_only")
        self.assertEqual(malformed["present_intervals"]["samples"], 0)
        self.assertIsNone(malformed["present_intervals"]["median_ms"])
        self.assertEqual(malformed["chronology"]["timestamp_segments"], 0)

    def test_conflicting_metadata_does_not_hide_observed_records(self):
        result = STALLS.parse_log([record()], launch_requested=False, probe_state="disabled")
        self.assertTrue(result["probe"]["configuration_conflict"])
        self.assertTrue(result["probe"]["valid_records_observed"])
        self.assertEqual(result["probe"]["enablement_evidence"], "valid_stall_records")
        self.assertTrue(STALLS.parse_log(["other\n"], launch_requested=False,
                                        probe_state="enabled")["probe"]["configuration_conflict"])

    def test_overlap_and_long_scope_durations_remain_independent_observations(self):
        # Draw contains a pipeline wait, and completed waits can span reports.
        result = STALLS.parse_log([record(interval="120.0", draw="250.0", build="200.0", idle="300.0")])
        self.assertEqual(result["valid_record_count"], 1)
        self.assertEqual(result["completed_scope_observations"]["draw"]["maximum_ms"], 250)
        self.assertEqual(result["completed_scope_observations"]["build_wait"]["maximum_ms"], 200)
        for summary in result["completed_scope_observations"].values():
            self.assertEqual(set(summary), {"samples", "nonzero_samples", "minimum_ms", "median_ms", "maximum_ms"})
        self.assertNotIn("total_scopes_ms", result)
        self.assertNotIn("gpu_bound", result)
        self.assertTrue(any("not hardware GPU" in limit for limit in result["limits"]))

    def test_rounded_threshold_zero_counts_and_final_line(self):
        result = STALLS.parse_log([record(interval="100.0", draw="0.0", draws="0", build="0.0", builds="0", newline="")])
        self.assertEqual(result["valid_record_count"], 1)
        self.assertEqual(result["records_below_nominal_threshold"], 0)
        self.assertEqual(result["completed_scope_counts"]["draw"]["total_reported_count"], 0)
        unexpected = STALLS.parse_log([record(interval="99.9")])
        self.assertEqual(unexpected["records_below_nominal_threshold"], 1)

    def test_cli_sanitizes_paths_and_raw_lines_and_reads_request(self):
        with tempfile.TemporaryDirectory(dir=FIXTURE_ROOT) as temporary:
            root = pathlib.Path(temporary)
            log, launch = root / "private-log.txt", root / "launch.json"
            private = r"C:\Users\example\secret\game.bin guest=0x1234"
            log.write_text(private + "\n" + record() + "STALL " + private + "\n", encoding="utf-8")
            launch.write_text(json.dumps(dict(stall_probe_requested=True, run_root=private)), encoding="utf-8")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = STALLS.main(["--log", str(log), "--launch", str(launch)])
            result = json.loads(output.getvalue())
            self.assertEqual(code, 1)
            self.assertTrue(result["probe"]["launcher_requested"])
            self.assertEqual(result["valid_record_count"], 1)
            self.assertNotIn(str(root), output.getvalue())
            self.assertNotIn("secret", output.getvalue())
            self.assertNotIn("0x1234", output.getvalue())

    def test_cli_input_errors_and_old_launch_schema_are_explicit(self):
        with tempfile.TemporaryDirectory(dir=FIXTURE_ROOT) as temporary:
            root = pathlib.Path(temporary)
            log, launch = root / "log.txt", root / "launch.json"
            log.write_text("ordinary startup\n", encoding="utf-8")
            for value, expected_code, expected_error in [
                    ("{private invalid json", 2, "cannot_read_launch_metadata"),
                    ("[]", 2, "invalid_launch_metadata"),
                    ('{"stall_probe_requested":"true"}', 2, "invalid_launch_probe_state"),
                    ("{}", 0, None)]:
                launch.write_text(value, encoding="utf-8")
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    code = STALLS.main(["--log", str(log), "--launch", str(launch)])
                result = json.loads(output.getvalue())
                self.assertEqual(code, expected_code)
                self.assertEqual(result.get("error"), expected_error)
                self.assertNotIn("private", output.getvalue())
                if expected_code == 0:
                    self.assertIsNone(result["probe"]["launcher_requested"])
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = STALLS.main(["--log", str(root / "missing-private-file.txt")])
            self.assertEqual(code, 2)
            self.assertEqual(json.loads(output.getvalue())["error"], "cannot_read_log")
            self.assertNotIn(str(root), output.getvalue())


if __name__ == "__main__":
    unittest.main(verbosity=2)
