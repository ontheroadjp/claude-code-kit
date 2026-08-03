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
PHASE_HEADER_RE = re.compile(r"^\[(.+?)\]\s*(\d+)件\s*$")
ACCESS_ENTRY_RE = re.compile(r"^\s*#\d+\s+(\S+)\s+(.+)$")
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
    phase_counts: dict[str, int]
    tool_counts: dict[str, int]
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


def parse_phases(text: str) -> tuple[dict[str, int], dict[str, int]]:
    phase_counts: dict[str, int] = {}
    tool_counts: dict[str, int] = {}
    for line in text.splitlines():
        header_match = PHASE_HEADER_RE.match(line)
        if header_match:
            phase_counts[header_match.group(1)] = int(header_match.group(2))
            continue
        entry_match = ACCESS_ENTRY_RE.match(line)
        if entry_match:
            tool = entry_match.group(1)
            tool_counts[tool] = tool_counts.get(tool, 0) + 1
    return phase_counts, tool_counts


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
    phase_counts, tool_counts = parse_phases(sections.get("フェーズ別アクセス順序", ""))
    return {
        "timestamp": sections.get("日時", "").strip(),
        "user_instruction": sections.get("ユーザーからの指示内容", "").strip(),
        "total_accesses": total,
        "duplicates": duplicates,
        "phase_counts": phase_counts,
        "tool_counts": tool_counts,
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
        }
        for count, session in ranked
    ]


def aggregate(months: list[str], sessions: list[Session]) -> dict[str, object]:
    session_count = len(sessions)
    total_accesses = sum(s["total_accesses"] for s in sessions)

    duplicate_totals: dict[str, int] = {}
    modified_totals: dict[str, int] = {}
    phase_totals: dict[str, int] = {}
    tool_totals: dict[str, int] = {}
    zero_modified_sessions = 0
    sessions_with_duplicates = 0
    redundant_accesses_total = 0
    token_sessions: list[TokenUsage] = []

    for session in sessions:
        if session["duplicates"]:
            sessions_with_duplicates += 1
        for duplicate in session["duplicates"]:
            path = str(duplicate["path"])
            duplicate_totals[path] = duplicate_totals.get(path, 0) + int(duplicate["count"])
            redundant_accesses_total += int(duplicate["count"]) - 1
        for modified_file in session["modified_files"]:
            modified_totals[modified_file] = modified_totals.get(modified_file, 0) + 1
        if not session["modified_files"]:
            zero_modified_sessions += 1
        for phase, count in session["phase_counts"].items():
            phase_totals[phase] = phase_totals.get(phase, 0) + count
        for tool, count in session["tool_counts"].items():
            tool_totals[tool] = tool_totals.get(tool, 0) + count
        if session["token_usage"] is not None:
            token_sessions.append(session["token_usage"])

    total_cost = sum(t["cost_usd"] for t in token_sessions)

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
        "top_modified_files": top_n(modified_totals, TOP_N),
        "phase_totals": phase_totals,
        "tool_totals": tool_totals,
        "zero_modified_sessions": zero_modified_sessions,
        "zero_modified_ratio": round(zero_modified_sessions / session_count, 3) if session_count else 0,
        "token_usage": {
            "sessions_with_data": len(token_sessions),
            "total_cost_usd": round(total_cost, 4),
            "total_tokens": sum(t["total"] for t in token_sessions),
            "avg_cost_usd_per_session": round(total_cost / len(token_sessions), 4) if token_sessions else 0,
        },
    }


def main() -> None:
    parser = build_arg_parser("Analyze logs/access/*.log")
    args = parser.parse_args()
    months = resolve_target_months("access", args.month, args.all)
    sessions = load_sessions(months)
    emit_json(aggregate(months, sessions))


if __name__ == "__main__":
    main()
