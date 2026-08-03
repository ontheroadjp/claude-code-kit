#!/usr/bin/env python3
"""Parse logs/token-usage/*.log and print an aggregated JSON summary.

Log format is produced by hooks/log-token-usage.sh: one line per Stop event,
carrying *cumulative* usage for the whole session as of that turn (the hook
recomputes totals from the full transcript on every Stop). Aggregation must
therefore keep only the last line per session_id before summing, otherwise
per-session totals get counted once per turn instead of once per session.
"""

from __future__ import annotations

import re
import sys
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
LOW_CACHE_MIN_TURNS = 2
LOW_CACHE_RATIO_PCT = 50.0
HIGH_DENSITY_TOKENS_PER_TURN = 20000
TIMESTAMP_DATE_LENGTH = 10  # "YYYY-MM-DD"

LINE_RE = re.compile(
    r"^\[(?P<timestamp>[^\]]+)\]\s+"
    r"session=(?P<session>\S+)\s+"
    r"name=(?P<name>.*?)\s+"
    r"model=(?P<model>\S+)\s+"
    r"turns=\s*(?P<turns>\d+)\s+"
    r"input=\s*(?P<input>\d+)\s+"
    r"output=\s*(?P<output>\d+)\s+"
    r"cache_read=\s*(?P<cache_read>\d+)\s+"
    r"cache_create=\s*(?P<cache_create>\d+)\s+"
    r"total=\s*(?P<total>\d+)\s+"
    r"cache_ratio=\s*(?P<cache_ratio>[\d.]+)\s+"
    r"cost_usd=\s*(?P<cost_usd>[\d.]+)\s+"
    r"branch=(?P<branch>.*?)\s+"
    r"cwd=(?P<cwd>\S+)\s*$"
)


class Record(TypedDict):
    timestamp: str
    session: str
    name: str
    model: str
    turns: int
    input: int
    output: int
    cache_read: int
    cache_create: int
    total: int
    cache_ratio: float
    cost_usd: float
    branch: str
    cwd: str


def parse_line(line: str) -> Record | None:
    match = LINE_RE.match(line)
    if match is None:
        return None
    return {
        "timestamp": match.group("timestamp"),
        "session": match.group("session"),
        "name": match.group("name"),
        "model": match.group("model"),
        "turns": int(match.group("turns")),
        "input": int(match.group("input")),
        "output": int(match.group("output")),
        "cache_read": int(match.group("cache_read")),
        "cache_create": int(match.group("cache_create")),
        "total": int(match.group("total")),
        "cache_ratio": float(match.group("cache_ratio")),
        "cost_usd": float(match.group("cost_usd")),
        "branch": match.group("branch"),
        "cwd": match.group("cwd"),
    }


def load_records(months: list[str]) -> list[Record]:
    records: list[Record] = []
    for path in log_files_for_months("token-usage", months):
        if not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            record = parse_line(line)
            if record is not None:
                records.append(record)
    return records


def dedupe_last_per_session(records: list[Record]) -> list[Record]:
    """Keep only the latest (highest-cumulative) row per session_id."""
    latest: dict[str, Record] = {}
    for record in records:
        latest[record["session"]] = record
    return list(latest.values())


def model_breakdown(sessions: list[Record]) -> list[dict[str, object]]:
    grouped: dict[str, list[Record]] = {}
    for session in sessions:
        grouped.setdefault(session["model"], []).append(session)
    ranked = sorted(grouped.items(), key=lambda kv: sum(s["cost_usd"] for s in kv[1]), reverse=True)
    return [
        {
            "model": model,
            "session_count": len(group),
            "total_cost_usd": round(sum(s["cost_usd"] for s in group), 4),
            "avg_cache_ratio": round(sum(s["cache_ratio"] for s in group) / len(group), 2),
        }
        for model, group in ranked
    ]


def cwd_breakdown(sessions: list[Record], n: int) -> list[dict[str, object]]:
    grouped: dict[str, list[Record]] = {}
    for session in sessions:
        grouped.setdefault(session["cwd"], []).append(session)
    ranked = sorted(grouped.items(), key=lambda kv: sum(s["cost_usd"] for s in kv[1]), reverse=True)[:n]
    return [
        {
            "cwd": cwd,
            "session_count": len(group),
            "total_cost_usd": round(sum(s["cost_usd"] for s in group), 4),
        }
        for cwd, group in ranked
    ]


def daily_cost_trend(sessions: list[Record]) -> list[dict[str, object]]:
    grouped: dict[str, list[Record]] = {}
    for session in sessions:
        date = session["timestamp"][:TIMESTAMP_DATE_LENGTH]
        grouped.setdefault(date, []).append(session)
    return [
        {
            "date": date,
            "session_count": len(group),
            "total_cost_usd": round(sum(s["cost_usd"] for s in group), 4),
        }
        for date, group in sorted(grouped.items())
    ]


def top_expensive_sessions(sessions: list[Record], n: int) -> list[dict[str, object]]:
    ranked = sorted(sessions, key=lambda s: s["cost_usd"], reverse=True)[:n]
    return [
        {
            "session": s["session"],
            "name": s["name"],
            "model": s["model"],
            "turns": s["turns"],
            "total_tokens": s["total"],
            "cost_usd": s["cost_usd"],
            "cache_ratio": s["cache_ratio"],
            "branch": s["branch"],
            "cwd": s["cwd"],
        }
        for s in ranked
    ]


def low_cache_sessions(sessions: list[Record]) -> list[dict[str, object]]:
    flagged = [
        s
        for s in sessions
        if s["turns"] > LOW_CACHE_MIN_TURNS and s["cache_ratio"] < LOW_CACHE_RATIO_PCT
    ]
    return [
        {"session": s["session"], "model": s["model"], "turns": s["turns"], "cache_ratio": s["cache_ratio"]}
        for s in flagged
    ]


def high_density_sessions(sessions: list[Record]) -> list[dict[str, object]]:
    flagged = []
    for s in sessions:
        if s["turns"] == 0:
            continue
        tokens_per_turn = s["total"] / s["turns"]
        if tokens_per_turn > HIGH_DENSITY_TOKENS_PER_TURN:
            flagged.append(
                {
                    "session": s["session"],
                    "model": s["model"],
                    "turns": s["turns"],
                    "tokens_per_turn": round(tokens_per_turn),
                }
            )
    return flagged


def aggregate(months: list[str], records: list[Record]) -> dict[str, object]:
    sessions = dedupe_last_per_session(records)
    session_count = len(sessions)
    total_cost = sum(s["cost_usd"] for s in sessions)
    total_tokens = sum(s["total"] for s in sessions)
    total_turns = sum(s["turns"] for s in sessions)

    return {
        "log_type": "token-usage",
        "months": months,
        "raw_line_count": len(records),
        "session_count": session_count,
        "total_cost_usd": round(total_cost, 4),
        "total_tokens": total_tokens,
        "total_turns": total_turns,
        "avg_cost_usd_per_session": round(total_cost / session_count, 4) if session_count else 0,
        "avg_turns_per_session": round(total_turns / session_count, 2) if session_count else 0,
        "model_breakdown": model_breakdown(sessions),
        "cwd_breakdown": cwd_breakdown(sessions, TOP_N),
        "daily_cost_trend": daily_cost_trend(sessions),
        "top_expensive_sessions": top_expensive_sessions(sessions, TOP_N),
        "low_cache_sessions": low_cache_sessions(sessions),
        "high_density_sessions": high_density_sessions(sessions),
    }


def main() -> None:
    parser = build_arg_parser("Analyze logs/token-usage/*.log")
    args = parser.parse_args()
    months = resolve_target_months("token-usage", args.month, args.all)
    records = load_records(months)
    emit_json(aggregate(months, records))


if __name__ == "__main__":
    main()
