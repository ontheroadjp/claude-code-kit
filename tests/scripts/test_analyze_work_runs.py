from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


MODULE_PATH = Path(__file__).parents[2] / "scripts" / "analyze_work_runs.py"
SPEC = importlib.util.spec_from_file_location("analyze_work_runs", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def write_events(path: Path, events: list[dict[str, object]]) -> None:
    path.write_text(
        "".join(json.dumps(event) + "\n" for event in events), encoding="utf-8"
    )


def event(sequence: int, kind: str, **extra: object) -> dict[str, object]:
    return {
        "work_run_id": "run-1",
        "timestamp": f"2026-08-29T00:00:{sequence:02d}.000Z",
        "sequence": sequence,
        "event": kind,
        "agent_session_id": "session-parent",
        **extra,
    }


def test_summarize_success_and_session_correlation(tmp_path: Path) -> None:
    path = tmp_path / "run.jsonl"
    events = [
        event(1, "run_started", issue_number=401),
        {**event(2, "worker_registered", issue_number=401), "agent_session_id": "worker"},
        event(3, "approval_wait_started", issue_number=401, approval_kind="plan"),
        event(4, "approval_wait_finished", issue_number=401, approval_kind="plan"),
        event(5, "issue_state_changed", issue_number=401, state="implementing"),
        event(6, "pr_created", issue_number=401),
        event(7, "issue_state_changed", issue_number=401, state="delivering"),
        event(8, "delivery_result", issue_number=401),
        event(9, "cleanup_result", outcome="success"),
        event(10, "run_finished", outcome="success"),
    ]
    write_events(path, events)

    summary = MODULE.summarize(MODULE.parse_run(path))

    assert summary["status"] == "success"
    assert summary["issues"] == [401]
    assert summary["agent_session_ids"] == ["session-parent", "worker"]
    assert summary["elapsed_seconds"] == 9.0
    assert summary["approval_wait_seconds"] == 1.0
    assert summary["pr_preparation_seconds"] == 1.0
    assert summary["delivery_seconds"] == 1.0
    assert summary["parallel_worker_peak"] == 1


def test_infers_gate_stop_partial_failure_and_interruption(tmp_path: Path) -> None:
    gate = tmp_path / "gate.jsonl"
    partial = tmp_path / "partial.jsonl"
    interrupted = tmp_path / "interrupted.jsonl"
    write_events(gate, [event(1, "run_started"), event(2, "gate_result", outcome="stopped")])
    write_events(
        partial,
        [event(1, "run_started"), event(2, "issue_state_changed", state="failed")],
    )
    write_events(interrupted, [event(1, "run_started")])

    assert MODULE.summarize(MODULE.parse_run(gate))["status"] == "gate_stopped"
    assert MODULE.summarize(MODULE.parse_run(partial))["status"] == "partial_failure"
    assert MODULE.summarize(MODULE.parse_run(interrupted))["status"] == "interrupted"


def test_parse_error_prevents_clean_success(tmp_path: Path) -> None:
    path = tmp_path / "broken.jsonl"
    write_events(
        path,
        [event(1, "run_started"), event(2, "run_finished", outcome="success")],
    )
    path.write_text(path.read_text(encoding="utf-8") + "not-json\n", encoding="utf-8")

    summary = MODULE.summarize(MODULE.parse_run(path))

    assert summary["parse_error_count"] == 1
    assert summary["status"] == "incomplete"
