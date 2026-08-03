#!/usr/bin/env python3
"""Parse logs/auto-approve/*.log and print an aggregated JSON summary.

Log format is produced by hooks/auto-approve-readonly.sh `log_decision()`:
one line per PreToolUse decision, e.g.
"[2026-08-03 22:34:07] agent=claude session=<id> result=approved  tool=Bash    <detail>"
"""

from __future__ import annotations

import re
import sys
from collections.abc import Iterable
from pathlib import Path
from typing import TypedDict

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib.analyze_common import (  # noqa: E402
    build_arg_parser,
    emit_json,
    log_files_for_months,
    resolve_target_months,
)

TOP_N = 10
RECENT_N = 15

LINE_RE = re.compile(
    r"^\[(?P<timestamp>[^\]]+)\]\s+"
    r"agent=(?P<agent>\S+)\s+"
    r"session=(?P<session>\S+)\s+"
    r"result=(?P<result>\S+)\s+"
    r"tool=(?P<tool>\S+)\s*"
    r"(?P<detail>.*)$"
)


class Decision(TypedDict):
    timestamp: str
    agent: str
    session: str
    result: str
    tool: str
    detail: str


def parse_line(line: str) -> Decision | None:
    match = LINE_RE.match(line)
    if match is None:
        return None
    return {
        "timestamp": match.group("timestamp"),
        "agent": match.group("agent"),
        "session": match.group("session"),
        "result": match.group("result"),
        "tool": match.group("tool"),
        "detail": match.group("detail"),
    }


def load_decisions(months: list[str]) -> list[Decision]:
    decisions: list[Decision] = []
    for path in log_files_for_months("auto-approve", months):
        if not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            decision = parse_line(line)
            if decision is not None:
                decisions.append(decision)
    return decisions


def count_values(values: Iterable[str]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for value in values:
        counts[value] = counts.get(value, 0) + 1
    return counts


def ratio(counts: dict[str, int], total: int) -> dict[str, float]:
    if total == 0:
        return {key: 0.0 for key in counts}
    return {key: round(count * 100.0 / total, 2) for key, count in counts.items()}


def top_sessions(decisions: list[Decision], n: int) -> list[dict[str, object]]:
    counts = count_values(d["session"] for d in decisions)
    ranked = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)[:n]
    return [{"session": session, "count": count} for session, count in ranked]


def top_detail_patterns(decisions: list[Decision], result: str, n: int) -> list[dict[str, object]]:
    counts: dict[tuple[str, str], int] = {}
    for decision in decisions:
        if decision["result"] != result:
            continue
        key = (decision["tool"], decision["detail"])
        counts[key] = counts.get(key, 0) + 1
    ranked = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)[:n]
    return [{"tool": tool, "detail": detail, "count": count} for (tool, detail), count in ranked]


def recent_samples(decisions: list[Decision], result: str, n: int) -> list[dict[str, str]]:
    matching = [d for d in decisions if d["result"] == result]
    return [
        {
            "timestamp": d["timestamp"],
            "agent": d["agent"],
            "tool": d["tool"],
            "detail": d["detail"],
        }
        for d in matching[-n:]
    ]


def aggregate(months: list[str], decisions: list[Decision]) -> dict[str, object]:
    total = len(decisions)
    result_counts = count_values(d["result"] for d in decisions)

    return {
        "log_type": "auto-approve",
        "months": months,
        "total_decisions": total,
        "result_counts": result_counts,
        "result_ratio_pct": ratio(result_counts, total),
        "tool_counts": count_values(d["tool"] for d in decisions),
        "agent_counts": count_values(d["agent"] for d in decisions),
        "top_sessions": top_sessions(decisions, TOP_N),
        "top_blocked_patterns": top_detail_patterns(decisions, "blocked", TOP_N),
        "top_user_prompt_patterns": top_detail_patterns(decisions, "user_prompt", TOP_N),
        "recent_blocked_samples": recent_samples(decisions, "blocked", RECENT_N),
        "recent_user_prompt_samples": recent_samples(decisions, "user_prompt", RECENT_N),
    }


def main() -> None:
    parser = build_arg_parser("Analyze logs/auto-approve/*.log")
    args = parser.parse_args()
    months = resolve_target_months("auto-approve", args.month, args.all)
    decisions = load_decisions(months)
    emit_json(aggregate(months, decisions))


if __name__ == "__main__":
    main()
