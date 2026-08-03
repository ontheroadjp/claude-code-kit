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
    MONTH_PATTERN_LENGTH,
    build_arg_parser,
    emit_json,
    log_files_for_months,
    resolve_target_months,
)

TOP_N = 10
RECENT_N = 15

# Mirrors hooks/auto-approve-readonly.sh's check_session_approved() categories
# (tool:git_write / tool:gh_issue_write / tool:gh_pr_write) — the same Bash
# command shapes that only auto-approve once a session has an approved plan.
# Kept in the same match order as the hook so a pattern here maps 1:1 to the
# regex branch that would need updating to auto-approve it unconditionally.
ROUTINE_OP_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("git add", re.compile(r"^git\s+add(\s|$)")),
    ("git commit", re.compile(r"^git\s+commit(\s|$)")),
    ("git merge", re.compile(r"^git\s+merge(\s|$)")),
    ("git fetch", re.compile(r"^git\s+fetch(\s|$)")),
    ("git pull", re.compile(r"^git\s+pull(\s|$)")),
    ("git stash", re.compile(r"^git\s+stash(\s|$)")),
    ("git push", re.compile(r"^git\s+push(\s|$)")),
    ("git checkout/switch", re.compile(r"^git\s+(checkout|switch)(\s|$)")),
    ("git branch", re.compile(r"^git\s+branch(\s|$)")),
    ("gh issue create", re.compile(r"^gh\s+issue\s+create(\s|$)")),
    ("gh issue edit", re.compile(r"^gh\s+issue\s+edit(\s|$)")),
    ("gh issue close", re.compile(r"^gh\s+issue\s+close(\s|$)")),
    ("gh issue delete", re.compile(r"^gh\s+issue\s+delete(\s|$)")),
    ("gh issue comment", re.compile(r"^gh\s+issue\s+comment(\s|$)")),
    ("gh issue reopen", re.compile(r"^gh\s+issue\s+reopen(\s|$)")),
    ("gh pr create", re.compile(r"^gh\s+pr\s+create(\s|$)")),
    ("gh pr edit", re.compile(r"^gh\s+pr\s+edit(\s|$)")),
    ("gh pr close", re.compile(r"^gh\s+pr\s+close(\s|$)")),
    ("gh pr comment", re.compile(r"^gh\s+pr\s+comment(\s|$)")),
    ("gh pr reopen", re.compile(r"^gh\s+pr\s+reopen(\s|$)")),
    ("gh pr ready", re.compile(r"^gh\s+pr\s+ready(\s|$)")),
    ("gh pr review", re.compile(r"^gh\s+pr\s+review(\s|$)")),
    ("gh pr checkout", re.compile(r"^gh\s+pr\s+checkout(\s|$)")),
    ("gh pr merge", re.compile(r"^gh\s+pr\s+merge(\s|$)")),
]

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


def classify_routine_op(tool: str, detail: str) -> str | None:
    if tool != "Bash":
        return None
    stripped = detail.strip()
    for label, pattern in ROUTINE_OP_PATTERNS:
        if pattern.match(stripped):
            return label
    return None


def monthly_trend(decisions: list[Decision]) -> list[dict[str, object]]:
    grouped: dict[str, list[Decision]] = {}
    for decision in decisions:
        month = decision["timestamp"][:MONTH_PATTERN_LENGTH]
        grouped.setdefault(month, []).append(decision)

    trend = []
    for month, group in sorted(grouped.items()):
        counts = count_values(d["result"] for d in group)
        trend.append(
            {
                "month": month,
                "total_decisions": len(group),
                "result_counts": counts,
                "result_ratio_pct": ratio(counts, len(group)),
            }
        )
    return trend


def routine_ops_breakdown(decisions: list[Decision], n: int) -> dict[str, object]:
    routine: list[tuple[str, Decision]] = []
    for decision in decisions:
        label = classify_routine_op(decision["tool"], decision["detail"])
        if label is not None:
            routine.append((label, decision))

    total = len(routine)
    result_counts = count_values(d["result"] for _, d in routine)

    pattern_result_counts: dict[str, dict[str, int]] = {}
    for label, decision in routine:
        bucket = pattern_result_counts.setdefault(label, {})
        bucket[decision["result"]] = bucket.get(decision["result"], 0) + 1

    ranked_patterns = sorted(
        (
            (counts.get("user_prompt", 0), label, counts)
            for label, counts in pattern_result_counts.items()
            if counts.get("user_prompt", 0) > 0
        ),
        key=lambda item: item[0],
        reverse=True,
    )[:n]
    patterns_needing_approval = [
        {
            "pattern": label,
            "user_prompt_count": user_prompt_count,
            "approved_count": counts.get("approved", 0),
            "blocked_count": counts.get("blocked", 0),
        }
        for user_prompt_count, label, counts in ranked_patterns
    ]

    return {
        "total_routine_decisions": total,
        "result_counts": result_counts,
        "result_ratio_pct": ratio(result_counts, total),
        "patterns_needing_approval": patterns_needing_approval,
    }


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
        "monthly_trend": monthly_trend(decisions),
        "routine_ops": routine_ops_breakdown(decisions, TOP_N),
    }


def main() -> None:
    parser = build_arg_parser("Analyze logs/auto-approve/*.log")
    args = parser.parse_args()
    months = resolve_target_months("auto-approve", args.month, args.all)
    decisions = load_decisions(months)
    emit_json(aggregate(months, decisions))


if __name__ == "__main__":
    main()
