"""Shared helpers for the logs/ analysis scripts (scripts/analyze_*.py)."""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

MONTH_PATTERN_LENGTH = 7  # "YYYY-MM"


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def log_dir(log_type: str) -> Path:
    return repo_root() / "logs" / log_type


def available_months(log_type: str) -> list[str]:
    directory = log_dir(log_type)
    if not directory.is_dir():
        return []
    return sorted(p.stem for p in directory.glob("*.log"))


def build_arg_parser(description: str) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=description)
    target = parser.add_mutually_exclusive_group()
    target.add_argument(
        "--month",
        metavar="YYYY-MM",
        help="target month (default: latest available month)",
    )
    target.add_argument(
        "--all",
        action="store_true",
        help="aggregate across every available month",
    )
    return parser


def resolve_target_months(log_type: str, month: str | None, use_all: bool) -> list[str]:
    months = available_months(log_type)
    if not months:
        raise SystemExit(f"no log files found under logs/{log_type}/")

    if use_all:
        return months

    if month is not None:
        if len(month) != MONTH_PATTERN_LENGTH or month[4] != "-":
            raise SystemExit(f"invalid --month value: {month!r} (expected YYYY-MM)")
        if month not in months:
            raise SystemExit(f"no log file for {month} under logs/{log_type}/ (available: {', '.join(months)})")
        return [month]

    return [months[-1]]


def log_files_for_months(log_type: str, months: list[str]) -> list[Path]:
    directory = log_dir(log_type)
    return [directory / f"{month}.log" for month in months]


def emit_json(data: dict[str, object]) -> None:
    json.dump(data, sys.stdout, ensure_ascii=False, indent=2, sort_keys=False)
    sys.stdout.write("\n")


def percentile(sorted_values: list[int], pct: int) -> float:
    if len(sorted_values) == 1:
        return float(sorted_values[0])
    quantiles = statistics.quantiles(sorted_values, n=100, method="inclusive")
    return round(quantiles[pct - 1], 2)
