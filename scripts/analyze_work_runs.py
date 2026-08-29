#!/usr/bin/env python3
"""Aggregate privacy-preserving per-/work JSONL lifecycle events."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import TypedDict, cast


class Event(TypedDict, total=False):
    work_run_id: str
    timestamp: str
    sequence: int
    event: str
    agent_session_id: str
    issue_number: int
    outcome: str


class RunSummary(TypedDict):
    work_run_id: str
    status: str
    started_at: str
    finished_at: str | None
    elapsed_seconds: float | None
    event_count: int
    issues: list[int]
    agent_session_ids: list[str]
    event_counts: dict[str, int]
    approval_wait_seconds: float
    pr_preparation_seconds: float
    delivery_seconds: float
    parallel_worker_peak: int
    parse_error_count: int


@dataclass(frozen=True)
class ParsedRun:
    events: list[Event]
    parse_error_count: int


def parse_timestamp(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def parse_run(path: Path) -> ParsedRun:
    events: list[Event] = []
    errors = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            raw = json.loads(line)
        except json.JSONDecodeError:
            errors += 1
            continue
        if not isinstance(raw, dict):
            errors += 1
            continue
        event = cast(Event, raw)
        required = ("work_run_id", "timestamp", "sequence", "event", "agent_session_id")
        if not all(key in event for key in required):
            errors += 1
            continue
        events.append(event)
    events.sort(key=lambda item: int(item["sequence"]))
    return ParsedRun(events=events, parse_error_count=errors)


def infer_status(events: list[Event], parse_error_count: int) -> str:
    if not events:
        return "invalid"
    finishes = [event for event in events if event.get("event") == "run_finished"]
    if finishes:
        outcome = str(finishes[-1].get("outcome", "incomplete"))
        if outcome == "success" and parse_error_count > 0:
            return "incomplete"
        if outcome == "success":
            cleanups = [event for event in events if event.get("event") == "cleanup_result"]
            if cleanups and cleanups[-1].get("outcome") != "success":
                return "cleanup_incomplete"
        return outcome
    gate_stops = [
        event
        for event in events
        if event.get("event") == "gate_result" and event.get("outcome") == "stopped"
    ]
    if gate_stops:
        return "gate_stopped"
    failed_issues = [
        event
        for event in events
        if event.get("event") == "issue_state_changed" and event.get("state") == "failed"
    ]
    if failed_issues:
        return "partial_failure"
    return "interrupted"


def summarize(parsed: ParsedRun) -> RunSummary:
    events = parsed.events
    run_id = str(events[0]["work_run_id"]) if events else "unknown"
    started = str(events[0]["timestamp"]) if events else ""
    finished_events = [event for event in events if event.get("event") == "run_finished"]
    finished = str(finished_events[-1]["timestamp"]) if finished_events else None
    elapsed: float | None = None
    if started and finished:
        elapsed = round((parse_timestamp(finished) - parse_timestamp(started)).total_seconds(), 3)
    issues = sorted(
        {int(event["issue_number"]) for event in events if "issue_number" in event}
    )
    sessions = sorted(
        {str(event["agent_session_id"]) for event in events if event.get("agent_session_id")}
    )
    counts = Counter(str(event["event"]) for event in events)
    approval_wait_seconds = paired_duration(
        events, "approval_wait_started", "approval_wait_finished", ("issue_number", "approval_kind")
    )
    pr_preparation_seconds = paired_duration(
        events, "issue_state_changed", "pr_created", ("issue_number",), start_state="implementing"
    )
    delivery_seconds = paired_duration(
        events, "issue_state_changed", "delivery_result", ("issue_number",), start_state="delivering"
    )
    return {
        "work_run_id": run_id,
        "status": infer_status(events, parsed.parse_error_count),
        "started_at": started,
        "finished_at": finished,
        "elapsed_seconds": elapsed,
        "event_count": len(events),
        "issues": issues,
        "agent_session_ids": sessions,
        "event_counts": dict(sorted(counts.items())),
        "approval_wait_seconds": approval_wait_seconds,
        "pr_preparation_seconds": pr_preparation_seconds,
        "delivery_seconds": delivery_seconds,
        "parallel_worker_peak": parallel_worker_peak(events),
        "parse_error_count": parsed.parse_error_count,
    }


def event_key(event: Event, keys: tuple[str, ...]) -> tuple[object, ...] | None:
    if not all(key in event for key in keys):
        return None
    return tuple(event[key] for key in keys)


def paired_duration(
    events: list[Event],
    start_event: str,
    finish_event: str,
    keys: tuple[str, ...],
    *,
    start_state: str | None = None,
) -> float:
    starts: dict[tuple[object, ...], datetime] = {}
    total = 0.0
    for event in events:
        key = event_key(event, keys)
        if key is None:
            continue
        if event.get("event") == start_event and (
            start_state is None or event.get("state") == start_state
        ):
            starts[key] = parse_timestamp(str(event["timestamp"]))
        elif event.get("event") == finish_event and key in starts:
            total += (parse_timestamp(str(event["timestamp"])) - starts.pop(key)).total_seconds()
    return round(total, 3)


def parallel_worker_peak(events: list[Event]) -> int:
    active: set[int] = set()
    peak = 0
    for event in events:
        if "issue_number" not in event:
            continue
        issue_number = int(event["issue_number"])
        if event.get("event") == "worker_registered":
            active.add(issue_number)
            peak = max(peak, len(active))
        elif event.get("event") == "issue_state_changed" and event.get("state") in {
            "completed",
            "failed",
        }:
            active.discard(issue_number)
    return peak


def discover(paths: list[Path]) -> list[Path]:
    discovered: set[Path] = set()
    for path in paths:
        if path.is_dir():
            discovered.update(path.glob("**/*.jsonl"))
        elif path.is_file():
            discovered.add(path)
    return sorted(discovered)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()
    summaries = [summarize(parse_run(path)) for path in discover(args.paths)]
    status_counts = Counter(summary["status"] for summary in summaries)
    result = {
        "run_count": len(summaries),
        "status_counts": dict(sorted(status_counts.items())),
        "runs": summaries,
    }
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
