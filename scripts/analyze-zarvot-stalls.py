#!/usr/bin/env python3
"""Summarize the existing opt-in Vulkan STALL probe, without running the game.

Use --log for a saved host log and optionally --launch for its launch.json.
JSON on stdout contains no input paths, raw log lines, native addresses or guest
PCs. A launch request alone does not establish that the probe ran. When process
configuration was independently verified, --probe-state enabled records that
assertion separately from observed records.
"""

import argparse
import json
import math
import pathlib
import re
import sys


NUMBER = r"[0-9]+(?:\.[0-9]+)?"
SCOPES = ("gpu_idle", "draw", "sched_wait", "build_wait", "acquire", "present", "frame_wait")
COUNTED_SCOPES = ("draw", "build_wait")
MARKER = re.compile(r"\bSTALL\b")
PREFIX = re.compile(
    rf"^\[\s*(?P<timestamp>{NUMBER})\]\s+Render\.Vulkan\s+<Info>\s+"
    r"[^\r\n]*?:\s*(?P<message>STALL(?:\s.*)?)$")
MESSAGE = re.compile(
    rf"STALL present_interval=(?P<present_interval>{NUMBER})ms "
    r"completed_scope_totals\(overlap_possible\): "
    rf"gpu_idle=(?P<gpu_idle>{NUMBER})ms "
    rf"draw=(?P<draw>{NUMBER})ms\(n=(?P<draw_count>[0-9]+)\) "
    rf"sched_wait=(?P<sched_wait>{NUMBER})ms "
    rf"build_wait=(?P<build_wait>{NUMBER})ms\(n=(?P<build_wait_count>[0-9]+)\) "
    rf"acquire=(?P<acquire>{NUMBER})ms "
    rf"present=(?P<present>{NUMBER})ms "
    rf"frame_wait=(?P<frame_wait>{NUMBER})ms")

LIMITS = [
    "Only the existing probe's reported slow-presentation observations are summarized; this is not a complete frame trace.",
    "The source emits only presentation intervals above 100 ms; one-decimal rounding can display 100.0 ms.",
    "Scope values are process-wide completed CPU wall-time totals from multiple threads; scopes overlap and can straddle reports.",
    "Scope totals must not be added together, treated as frame-time percentages, or divided by counts to claim individual call latency.",
    "gpu_idle measures the GPU-emulation thread waiting for incoming work, not hardware GPU idleness or GPU execution time.",
    "draw covers direct-draw preparation/configuration and command recording, not all indirect draws or hardware draw execution.",
    "Counts tally completed probed scopes, not successful GPU draws or the number of pipelines compiled.",
    "Timestamps are relative host-log timestamps, not UTC or independently verified frame boundaries; file order is preserved.",
    "No records does not establish smooth gameplay: probe enablement, log filtering, first-present suppression and capture completeness matter.",
    "No CPU-bound or GPU-bound verdict, FPS percentiles, or causal performance improvement follows from this report.",
]


def numeric_summary(values, suffix):
    """Describe one series only; never combine the overlapping scope series."""
    ordered = sorted(values)
    middle = len(ordered) // 2
    median = None
    if ordered:
        median = ordered[middle]
        if len(ordered) % 2 == 0:
            # All values are nonnegative. Halving before addition avoids an
            # overflowing float sum even when both inputs are finite.
            median = ordered[middle - 1] / 2 + ordered[middle] / 2
    return {
        "samples": len(values),
        "nonzero_samples": sum(value != 0 for value in values),
        f"minimum_{suffix}": min(values) if values else None,
        f"median_{suffix}": median,
        f"maximum_{suffix}": max(values) if values else None,
    }


def parse_log(lines, *, probe_state="unknown", launch_requested=None):
    """Parse exact current probe records, retaining malformed markers explicitly.

    Input is an iterable of log lines. Raw contents never enter the result.
    --probe-state is a caller assertion; launch_requested is merely metadata.
    """
    if probe_state not in ("unknown", "enabled", "disabled"):
        raise ValueError("invalid_probe_state")
    if launch_requested is not None and type(launch_requested) is not bool:
        raise ValueError("invalid_launch_probe_state")

    records = []
    malformed = []
    line_count = nonempty_lines = 0
    regressions = 0
    segment = 1
    previous_timestamp = None
    for line_count, raw in enumerate(lines, 1):
        line = raw.rstrip("\r\n")
        nonempty_lines += bool(line.strip())
        if not MARKER.search(line):
            continue
        prefix = PREFIX.fullmatch(line)
        if not prefix:
            malformed.append({"line_number": line_count, "reason": "invalid_log_prefix_or_timestamp"})
            continue
        message = MESSAGE.fullmatch(prefix["message"])
        if not message:
            malformed.append({"line_number": line_count, "reason": "invalid_or_truncated_stall_message"})
            continue
        try:
            timestamp = float(prefix["timestamp"])
            interval = float(message["present_interval"])
            scopes = {name: float(message[name]) for name in SCOPES}
            counts = {name: int(message[f"{name}_count"]) for name in COUNTED_SCOPES}
            if not all(math.isfinite(value) for value in (timestamp, interval, *scopes.values())):
                raise ValueError("nonfinite")
            if any(value > (1 << 64) - 1 for value in counts.values()):
                raise ValueError("count_overflow")
        except (ValueError, OverflowError):
            malformed.append({"line_number": line_count, "reason": "numeric_value_out_of_range"})
            continue
        if previous_timestamp is not None and timestamp < previous_timestamp:
            regressions += 1
            segment += 1
        records.append({
            "line_number": line_count,
            "timestamp_segment": segment,
            "log_seconds": timestamp,
            "present_interval_ms": interval,
            "completed_scopes_ms": scopes,
            "completed_scope_counts": counts,
        })
        previous_timestamp = timestamp

    observed = bool(records)
    conflict = ((observed and (probe_state == "disabled" or launch_requested is False))
                or (probe_state == "enabled" and launch_requested is False)
                or (probe_state == "disabled" and launch_requested is True))
    if observed:
        evidence = "valid_stall_records"
        observation_state = "stall_records"
    elif malformed:
        evidence = "no_valid_records"
        observation_state = "malformed_stall_records_only"
    elif not nonempty_lines:
        evidence = "no_valid_records"
        observation_state = "empty_log"
    elif probe_state == "enabled":
        evidence = "caller_asserted_enabled"
        observation_state = "no_stall_records_enabled_asserted"
    elif probe_state == "disabled":
        evidence = "caller_asserted_disabled"
        observation_state = "no_stall_records_disabled_asserted"
    elif launch_requested is True:
        evidence = "launcher_request_unconfirmed"
        observation_state = "no_stall_records_requested_unconfirmed"
    elif launch_requested is False:
        evidence = "launcher_did_not_request"
        observation_state = "no_stall_records_not_requested"
    else:
        evidence = "unknown"
        observation_state = "no_stall_records_not_known_enabled"

    times = [record["log_seconds"] for record in records]
    count_summaries = {}
    for name in COUNTED_SCOPES:
        values = [record["completed_scope_counts"][name] for record in records]
        count_summaries[name] = numeric_summary(values, "count")
        count_summaries[name]["total_reported_count"] = sum(values)
    return {
        "format_version": 1,
        "analysis_state": "partial" if malformed else "complete",
        "observation_state": observation_state,
        "probe": {
            "caller_asserted_state": probe_state,
            "launcher_requested": launch_requested,
            "valid_records_observed": observed,
            "enablement_evidence": evidence,
            "configuration_conflict": conflict,
        },
        "log_line_count": line_count,
        "nonempty_log_line_count": nonempty_lines,
        "valid_record_count": len(records),
        "malformed_record_count": len(malformed),
        "malformed_records": malformed,
        "chronology": {
            "file_order_preserved": True,
            "timestamp_regression_count": regressions,
            "timestamp_segments": segment if records else 0,
            "first_log_seconds": times[0] if times else None,
            "last_log_seconds": times[-1] if times else None,
            "minimum_log_seconds": min(times) if times else None,
            "maximum_log_seconds": max(times) if times else None,
        },
        "present_intervals": numeric_summary([record["present_interval_ms"] for record in records], "ms"),
        "records_below_nominal_threshold": sum(record["present_interval_ms"] < 100 for record in records),
        "completed_scope_observations": {
            name: numeric_summary([record["completed_scopes_ms"][name] for record in records], "ms")
            for name in SCOPES
        },
        "completed_scope_counts": count_summaries,
        "records": records,
        "limits": LIMITS,
    }


def launch_probe_request(path):
    try:
        launch = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        raise ValueError("cannot_read_launch_metadata") from None
    if not isinstance(launch, dict):
        raise ValueError("invalid_launch_metadata")
    requested = launch.get("stall_probe_requested")
    if requested is not None and type(requested) is not bool:
        raise ValueError("invalid_launch_probe_state")
    return requested


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True, type=pathlib.Path, help="Saved host log; no game is launched")
    parser.add_argument("--launch", type=pathlib.Path, help="Optional matching launch.json; only stall_probe_requested is read")
    parser.add_argument("--probe-state", choices=("unknown", "enabled", "disabled"), default="unknown",
                        help="Independently verified process configuration; a caller assertion, not inferred from an empty log")
    args = parser.parse_args(argv)
    try:
        requested = launch_probe_request(args.launch) if args.launch else None
        try:
            with args.log.open(encoding="utf-8-sig", errors="replace") as stream:
                result = parse_log(stream, probe_state=args.probe_state, launch_requested=requested)
        except OSError:
            raise ValueError("cannot_read_log") from None
    except ValueError as error:
        # Only fixed error codes reach stdout; exception messages from the OS
        # and JSON decoder can contain private paths or original log contents.
        print(json.dumps({"format_version": 1, "analysis_state": "input_error", "error": str(error)}))
        return 2
    print(json.dumps(result, indent=2, allow_nan=False))
    # Partial output retains valid observations, but automation must notice that
    # a format mismatch/truncation prevents claiming a complete parse.
    return 1 if result["malformed_record_count"] else 0


if __name__ == "__main__":
    sys.exit(main())
