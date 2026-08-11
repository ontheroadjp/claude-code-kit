import json
import sys
import textwrap
from pathlib import Path

import pytest

import analyze_access
from lib import analyze_common

SESSION_1 = textwrap.dedent(
    """\
    [日時]
    2026.08.01 18.49

    [ユーザーからの指示内容]
    Do something

    [アクセスサマリ]
    総アクセス数: 3
    重複アクセス:
      - /path/a (2回) [work:2]

    [フェーズ別アクセス順序]
    [work] 3件
      #1  Read  /path/a
      #2  Read  /path/a
      #3  Bash  ls

    [修正したファイル]
      - /path/a

    [トークン使用量]
      input:       100
      output:      200
      cache_read:  50  (cache_ratio: 33.3%)
      total:       300
      cost_usd:    1.2345
    """
)

SESSION_2 = textwrap.dedent(
    """\
    [日時]
    2026.08.02 09.00

    [ユーザーからの指示内容]
    Investigate only

    [アクセスサマリ]
    総アクセス数: 2
    重複アクセス: なし

    [フェーズ別アクセス順序]
    [work] 2件
      #1  Read  /path/b
      #2  Read  /path/c

    [修正したファイル]
    """
)

SESSION_3 = textwrap.dedent(
    """\
    [日時]
    2026.08.03 10.00

    [ユーザーからの指示内容]
    Reread the same file too many times

    [アクセスサマリ]
    総アクセス数: 5
    重複アクセス:
      - /path/d (3回) [work:3]
      - /path/a (2回) [work:2]

    [フェーズ別アクセス順序]
    [work] 5件
      #1  Read  /path/d
      #2  Read  /path/d
      #3  Read  /path/d
      #4  Read  /path/a
      #5  Read  /path/a

    [修正したファイル]

    [Hook処理時間]
    45,120,NA
    """
)

SESSION_4 = textwrap.dedent(
    """\
    [日時]
    2026.08.04 11.00

    [ユーザーからの指示内容]
    Re-read the same hook across two different commands in one session

    [アクセスサマリ]
    総アクセス数: 3
    重複アクセス:
      - hooks/auto-approve-readonly.sh (3回) [work:2, task:1]

    [フェーズ別アクセス順序]
    [work] 2件
      #1  Read  hooks/auto-approve-readonly.sh
      #2  Read  hooks/auto-approve-readonly.sh
    [task] 1件
      #3  Read  hooks/auto-approve-readonly.sh

    [修正したファイル]
    """
)

LOG_CONTENT = (
    "\n---\n\n" + SESSION_1 + "\n---\n\n" + SESSION_2 + "\n---\n\n" + SESSION_3 + "\n---\n\n" + SESSION_4
)


def write_log(tmp_path: Path, month: str, content: str) -> None:
    access_dir = tmp_path / "logs" / "access"
    access_dir.mkdir(parents=True, exist_ok=True)
    (access_dir / f"{month}.log").write_text(content, encoding="utf-8")


def test_split_blocks_returns_one_block_per_session() -> None:
    blocks = analyze_access.split_blocks(LOG_CONTENT)
    assert len(blocks) == 4


def test_parse_session_extracts_summary_and_token_usage() -> None:
    block = analyze_access.split_blocks(LOG_CONTENT)[0]
    session = analyze_access.parse_session(analyze_access.split_sections(block))
    assert session is not None
    assert session["total_accesses"] == 3
    assert session["duplicates"] == [{"path": "/path/a", "count": 2, "by_phase": {"work": 2}}]
    assert session["modified_files"] == ["/path/a"]
    assert session["token_usage"] == {
        "input": 100,
        "output": 200,
        "cache_read": 50,
        "cache_ratio": 33.3,
        "total": 300,
        "cost_usd": 1.2345,
    }


def test_parse_phase_breakdown_parses_multiple_phases() -> None:
    assert analyze_access.parse_phase_breakdown("work:2, task:1") == {"work": 2, "task": 1}


def test_parse_phase_breakdown_returns_empty_for_missing_suffix() -> None:
    assert analyze_access.parse_phase_breakdown("") == {}


def test_parse_summary_backward_compatible_with_pre_308_format() -> None:
    """Log lines flushed before issue #308 lack the `[phase:count, ...]` suffix."""
    text = "総アクセス数: 2\n重複アクセス:\n  - /path/x (2回)\n"
    total, duplicates = analyze_access.parse_summary(text)
    assert total == 2
    assert duplicates == [{"path": "/path/x", "count": 2, "by_phase": {}}]


def test_parse_session_handles_no_duplicates_and_no_token_usage() -> None:
    block = analyze_access.split_blocks(LOG_CONTENT)[1]
    session = analyze_access.parse_session(analyze_access.split_sections(block))
    assert session is not None
    assert session["duplicates"] == []
    assert session["modified_files"] == []
    assert session["token_usage"] is None
    assert session["hook_durations_ms"] == []


def test_parse_session_extracts_hook_durations() -> None:
    block = analyze_access.split_blocks(LOG_CONTENT)[2]
    session = analyze_access.parse_session(analyze_access.split_sections(block))
    assert session is not None
    assert session["hook_durations_ms"] == ["45", "120", "NA"]


def test_aggregate_across_sessions(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", LOG_CONTENT)

    sessions = analyze_access.load_sessions(["2026-08"])
    result = analyze_access.aggregate(["2026-08"], sessions)

    assert result["session_count"] == 4
    assert result["total_accesses"] == 13
    assert result["top_duplicate_files"] == [
        {"path": "/path/a", "count": 4, "by_phase": {"work": 4}},
        {"path": "/path/d", "count": 3, "by_phase": {"work": 3}},
        {
            "path": "hooks/auto-approve-readonly.sh",
            "count": 3,
            "by_phase": {"work": 2, "task": 1},
        },
    ]
    assert result["redundant_access_waste"] == {
        "sessions_with_data": 1,
        "estimated_wasted_tokens": 100,
        "estimated_wasted_cost_usd": 0.4115,
        "estimated_waste_ratio_pct": 33.33,
    }


def test_aggregate_tracks_redundant_reads_per_session(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", LOG_CONTENT)

    sessions = analyze_access.load_sessions(["2026-08"])
    result = analyze_access.aggregate(["2026-08"], sessions)

    assert result["redundant_accesses_total"] == 6
    assert result["sessions_with_duplicates"] == 3
    assert result["sessions_with_duplicates_ratio"] == 0.75

    top_redundant_sessions = result["top_redundant_sessions"]
    assert [entry["redundant_accesses"] for entry in top_redundant_sessions] == [3, 2, 1]
    assert top_redundant_sessions[0]["timestamp"] == "2026.08.03 10.00"
    assert top_redundant_sessions[0]["duplicate_files"] == [
        {"path": "/path/d", "count": 3, "by_phase": {"work": 3}},
        {"path": "/path/a", "count": 2, "by_phase": {"work": 2}},
    ]
    assert top_redundant_sessions[0]["modified"] is False
    assert top_redundant_sessions[1]["timestamp"] == "2026.08.04 11.00"
    assert top_redundant_sessions[1]["duplicate_files"] == [
        {
            "path": "hooks/auto-approve-readonly.sh",
            "count": 3,
            "by_phase": {"work": 2, "task": 1},
        },
    ]
    assert top_redundant_sessions[1]["modified"] is False
    assert top_redundant_sessions[2]["timestamp"] == "2026.08.01 18.49"
    assert top_redundant_sessions[2]["modified"] is True


def test_duration_ms_stats_pools_across_sessions_and_excludes_na(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", LOG_CONTENT)

    sessions = analyze_access.load_sessions(["2026-08"])
    result = analyze_access.aggregate(["2026-08"], sessions)

    stats = result["duration_ms_stats"]
    assert stats["sample_count"] == 2
    assert stats["excluded_count"] == 1
    assert stats["avg_ms"] == 82.5
    assert stats["median_ms"] == 82.5
    assert stats["max_ms"] == 120


def test_duration_ms_stats_all_missing_returns_zeroed_stats() -> None:
    result = analyze_access.duration_ms_stats([])
    assert result == {
        "sample_count": 0,
        "excluded_count": 0,
        "avg_ms": 0.0,
        "median_ms": 0.0,
        "p95_ms": 0.0,
        "max_ms": 0.0,
    }


def test_main_prints_valid_json(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", LOG_CONTENT)
    monkeypatch.setattr(sys, "argv", ["analyze_access.py", "--month", "2026-08"])

    analyze_access.main()

    output = json.loads(capsys.readouterr().out)
    assert output["log_type"] == "access"
    assert output["months"] == ["2026-08"]
    assert output["session_count"] == 4
