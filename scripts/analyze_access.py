#!/usr/bin/env python3
"""Parse logs/access/*.log and print an aggregated JSON summary.

Log format is produced by hooks/log-access-stop.sh: one block per turn,
delimited by a line containing only "---", with fixed [section] headers.
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

SECTION_HEADERS = [
    "日時",
    "ユーザーからの指示内容",
    "アクセスサマリ",
    "フェーズ別アクセス順序",
    "修正したファイル",
    "トークン使用量",
]
BLOCK_SPLIT_RE = re.compile(r"^---$", re.MULTILINE)
SECTION_RE = re.compile(
    r"^\[(" + "|".join(re.escape(h) for h in SECTION_HEADERS) + r")\]\n",
    re.MULTILINE,
)
DUPLICATE_RE = re.compile(r"^\s*-\s*(.+?)\s*\((\d+)回\)\s*$", re.MULTILINE)
TOTAL_ACCESSES_RE = re.compile(r"総アクセス数:\s*(\d+)")
MODIFIED_FILE_RE = re.compile(r"^\s*-\s*(.+)$", re.MULTILINE)
TOKEN_FIELD_RE = {
    "input": re.compile(r"input:\s*(\d+)"),
    "output": re.compile(r"output:\s*(\d+)"),
    "cache_read": re.compile(r"cache_read:\s*(\d+)"),
    "cache_ratio": re.compile(r"cache_ratio:\s*([\d.]+)%"),
    "total": re.compile(r"total:\s*(\d+)"),
    "cost_usd": re.compile(r"cost_usd:\s*([\d.]+)"),
}


class TokenUsage(TypedDict):
    input: int
    output: int
    cache_read: int
    cache_ratio: float
    total: int
    cost_usd: float


class Session(TypedDict):
    timestamp: str
    user_instruction: str
    total_accesses: int
    duplicates: list[dict[str, object]]
    modified_files: list[str]
    token_usage: TokenUsage | None


def split_blocks(text: str) -> list[str]:
    return [block.strip() for block in BLOCK_SPLIT_RE.split(text) if block.strip()]


def split_sections(block: str) -> dict[str, str]:
    matches = list(SECTION_RE.finditer(block))
    sections: dict[str, str] = {}
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(block)
        sections[match.group(1)] = block[start:end].strip("\n")
    return sections


def parse_summary(text: str) -> tuple[int, list[dict[str, object]]]:
    total_match = TOTAL_ACCESSES_RE.search(text)
    total = int(total_match.group(1)) if total_match else 0
    duplicates = [{"path": path, "count": int(count)} for path, count in DUPLICATE_RE.findall(text)]
    return total, duplicates


def parse_modified_files(text: str) -> list[str]:
    return MODIFIED_FILE_RE.findall(text) if text.strip() else []


def parse_token_usage(text: str) -> TokenUsage | None:
    if not text.strip():
        return None
    input_match = TOKEN_FIELD_RE["input"].search(text)
    if input_match is None:
        return None

    def find(field: str) -> str | None:
        match = TOKEN_FIELD_RE[field].search(text)
        return match.group(1) if match else None

    return {
        "input": int(input_match.group(1)),
        "output": int(find("output") or 0),
        "cache_read": int(find("cache_read") or 0),
        "cache_ratio": float(find("cache_ratio") or 0.0),
        "total": int(find("total") or 0),
        "cost_usd": float(find("cost_usd") or 0.0),
    }


def parse_session(sections: dict[str, str]) -> Session | None:
    if "日時" not in sections:
        return None
    total, duplicates = parse_summary(sections.get("アクセスサマリ", ""))
    return {
        "timestamp": sections.get("日時", "").strip(),
        "user_instruction": sections.get("ユーザーからの指示内容", "").strip(),
        "total_accesses": total,
        "duplicates": duplicates,
        "modified_files": parse_modified_files(sections.get("修正したファイル", "")),
        "token_usage": parse_token_usage(sections.get("トークン使用量", "")),
    }


def load_sessions(months: list[str]) -> list[Session]:
    sessions: list[Session] = []
    for path in log_files_for_months("access", months):
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for block in split_blocks(text):
            session = parse_session(split_sections(block))
            if session is not None:
                sessions.append(session)
    return sessions


def top_n(counts: dict[str, int], n: int) -> list[dict[str, object]]:
    ranked = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)[:n]
    return [{"path": path, "count": count} for path, count in ranked]


def top_redundant_sessions(sessions: list[Session], n: int) -> list[dict[str, object]]:
    redundant: list[tuple[int, Session]] = [
        (sum(int(d["count"]) - 1 for d in session["duplicates"]), session)
        for session in sessions
        if session["duplicates"]
    ]
    ranked = sorted(redundant, key=lambda item: item[0], reverse=True)[:n]
    return [
        {
            "timestamp": session["timestamp"],
            "user_instruction": session["user_instruction"],
            "redundant_accesses": count,
            "duplicate_files": session["duplicates"],
            "modified": bool(session["modified_files"]),
        }
        for count, session in ranked
    ]


def redundant_access_waste(sessions: list[Session]) -> dict[str, object]:
    """Estimate the tokens/cost spent on re-reading a file already read this session.

    Approximates each session's per-access cost as its total tokens/cost divided by
    its total accesses, then multiplies that by the session's redundant (count - 1)
    reads. This is the only place that ties `duplicates` directly to a loss figure —
    every other Fact in this module only reports frequency, not impact.
    """
    wasted_tokens = 0.0
    wasted_cost = 0.0
    total_tokens_with_data = 0
    sessions_with_data = 0

    for session in sessions:
        token_usage = session["token_usage"]
        if not session["duplicates"] or token_usage is None or session["total_accesses"] <= 0:
            continue
        redundant_count = sum(int(d["count"]) - 1 for d in session["duplicates"])
        per_access_tokens = token_usage["total"] / session["total_accesses"]
        per_access_cost = token_usage["cost_usd"] / session["total_accesses"]
        wasted_tokens += redundant_count * per_access_tokens
        wasted_cost += redundant_count * per_access_cost
        total_tokens_with_data += token_usage["total"]
        sessions_with_data += 1

    return {
        "sessions_with_data": sessions_with_data,
        "estimated_wasted_tokens": round(wasted_tokens),
        "estimated_wasted_cost_usd": round(wasted_cost, 4),
        "estimated_waste_ratio_pct": (
            round(wasted_tokens / total_tokens_with_data * 100, 2) if total_tokens_with_data else 0
        ),
    }


def aggregate(months: list[str], sessions: list[Session]) -> dict[str, object]:
    session_count = len(sessions)
    total_accesses = sum(s["total_accesses"] for s in sessions)

    duplicate_totals: dict[str, int] = {}
    sessions_with_duplicates = 0
    redundant_accesses_total = 0

    for session in sessions:
        if session["duplicates"]:
            sessions_with_duplicates += 1
        for duplicate in session["duplicates"]:
            path = str(duplicate["path"])
            duplicate_totals[path] = duplicate_totals.get(path, 0) + int(duplicate["count"])
            redundant_accesses_total += int(duplicate["count"]) - 1

    return {
        "log_type": "access",
        "months": months,
        "session_count": session_count,
        "total_accesses": total_accesses,
        "avg_accesses_per_session": round(total_accesses / session_count, 2) if session_count else 0,
        "top_duplicate_files": top_n(duplicate_totals, TOP_N),
        "redundant_accesses_total": redundant_accesses_total,
        "sessions_with_duplicates": sessions_with_duplicates,
        "sessions_with_duplicates_ratio": round(sessions_with_duplicates / session_count, 3) if session_count else 0,
        "top_redundant_sessions": top_redundant_sessions(sessions, TOP_N),
        "redundant_access_waste": redundant_access_waste(sessions),
    }


def main() -> None:
    parser = build_arg_parser("Analyze logs/access/*.log")
    args = parser.parse_args()
    months = resolve_target_months("access", args.month, args.all)
    sessions = load_sessions(months)
    emit_json(aggregate(months, sessions))


if __name__ == "__main__":
    main()
