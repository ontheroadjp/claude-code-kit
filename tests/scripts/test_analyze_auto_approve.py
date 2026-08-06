import json
import sys
import textwrap
from pathlib import Path

import pytest

import analyze_auto_approve
from lib import analyze_common

LOG_CONTENT = textwrap.dedent(
    """\
    [2026-08-01 10:00:00] agent=claude session=s1       result=approved     tool=Read       /repo/a.py
    [2026-08-01 10:00:05] agent=claude session=s1       result=blocked      tool=Bash       rm -rf /
    [2026-08-01 10:00:10] agent=claude session=s1       result=user_prompt  tool=Bash       curl example.com
    [2026-08-01 10:00:15] agent=codex  session=s2       result=approved     tool=Edit       /repo/b.py
    [2026-08-01 10:00:20] agent=claude session=s1       result=blocked      tool=Bash       rm -rf /
    [2026-08-01 10:00:25] agent=claude session=s1       result=user_prompt  tool=Bash       git commit -m "wip"
    [2026-08-01 10:00:30] agent=claude session=s1       result=approved     tool=Bash       git commit -m "wip" (session)
    [2026-09-01 09:00:00] agent=claude session=s3       result=user_prompt  tool=Bash       git commit -m "later"
    """
)

LONG_COMMAND_DETAIL = 'git commit -m "' + "x" * 110 + '"'

TRUNCATION_LOG_CONTENT = textwrap.dedent(
    f"""\
    [2026-08-01 10:00:00] agent=claude session=s1 result=user_prompt tool=Bash git push origin feature-a
    [2026-08-01 10:00:05] agent=claude session=s2 result=user_prompt tool=Bash git push origin feature-a
    [2026-08-01 10:00:10] agent=claude session=s2 result=user_prompt tool=Bash git push origin feature-b
    [2026-08-01 10:00:15] agent=claude session=s1 result=user_prompt tool=Bash {LONG_COMMAND_DETAIL}
    [2026-08-01 10:00:20] agent=claude session=s1 result=approved     tool=Bash git push (session)
    """
)

DURATION_LOG_CONTENT = textwrap.dedent(
    """\
    [2026-08-01 10:00:00] agent=claude session=s1       result=approved     tool=Bash       duration_ms=10     git commit -m "a"
    [2026-08-01 10:00:05] agent=claude session=s1       result=approved     tool=Bash       duration_ms=20     git commit -m "a"
    [2026-08-01 10:00:10] agent=claude session=s1       result=approved     tool=Bash       duration_ms=30     git commit -m "a"
    [2026-08-01 10:00:15] agent=claude session=s1       result=approved     tool=Bash       duration_ms=200    git push
    [2026-08-01 10:00:20] agent=claude session=s1       result=approved     tool=Bash       duration_ms=NA     git fetch
    [2026-08-01 10:00:25] agent=claude session=s1       result=approved     tool=Read       /repo/a.py
    """
)


def write_log(tmp_path: Path, month: str, content: str) -> None:
    log_dir = tmp_path / "logs" / "auto-approve"
    log_dir.mkdir(parents=True, exist_ok=True)
    (log_dir / f"{month}.log").write_text(content, encoding="utf-8")


def test_parse_line_extracts_all_fields() -> None:
    line = "[2026-08-01 10:00:00] agent=claude session=s1       result=approved     tool=Read       /repo/a.py"
    decision = analyze_auto_approve.parse_line(line)
    assert decision == {
        "timestamp": "2026-08-01 10:00:00",
        "agent": "claude",
        "session": "s1",
        "result": "approved",
        "tool": "Read",
        "duration_ms": None,
        "detail": "/repo/a.py",
    }


def test_parse_line_handles_empty_detail() -> None:
    line = "[2026-08-01 10:00:00] agent=claude session=s1       result=approved     tool=update_plan"
    decision = analyze_auto_approve.parse_line(line)
    assert decision is not None
    assert decision["detail"] == ""


def test_parse_line_extracts_duration_ms_without_corrupting_detail() -> None:
    line = (
        "[2026-08-01 10:00:00] agent=claude session=s1       result=approved     "
        'tool=Bash       duration_ms=12     git commit -m "wip"'
    )
    decision = analyze_auto_approve.parse_line(line)
    assert decision is not None
    assert decision["duration_ms"] == "12"
    assert decision["detail"] == 'git commit -m "wip"'
    assert analyze_auto_approve.classify_routine_op(decision["tool"], decision["detail"]) == "git commit"


def test_parse_line_handles_na_duration_ms() -> None:
    line = "[2026-08-01 10:00:00] agent=claude session=s1       result=approved     tool=Read       duration_ms=NA     /repo/a.py"
    decision = analyze_auto_approve.parse_line(line)
    assert decision is not None
    assert decision["duration_ms"] == "NA"
    assert decision["detail"] == "/repo/a.py"


def test_aggregate_counts_results_and_patterns(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", LOG_CONTENT)

    decisions = analyze_auto_approve.load_decisions(["2026-08"])
    result = analyze_auto_approve.aggregate(["2026-08"], decisions)

    assert result["total_decisions"] == 8
    assert result["result_counts"] == {"approved": 3, "blocked": 2, "user_prompt": 3}
    assert result["result_ratio_pct"]["blocked"] == 25.0
    assert result["tool_counts"] == {"Read": 1, "Bash": 6, "Edit": 1}
    assert result["agent_counts"] == {"claude": 7, "codex": 1}
    assert {"session": "s1", "count": 6} in result["top_sessions"]
    assert result["top_blocked_patterns"][0] == {"tool": "Bash", "detail": "rm -rf /", "count": 2}
    assert result["top_user_prompt_patterns"][0] == {"tool": "Bash", "detail": "curl example.com", "count": 1}
    assert len(result["recent_blocked_samples"]) == 2


def test_monthly_trend_groups_by_timestamp_month(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", LOG_CONTENT)

    decisions = analyze_auto_approve.load_decisions(["2026-08"])
    result = analyze_auto_approve.aggregate(["2026-08"], decisions)

    trend = result["monthly_trend"]
    assert [entry["month"] for entry in trend] == ["2026-08", "2026-09"]
    assert trend[0]["total_decisions"] == 7
    assert trend[0]["result_counts"] == {"approved": 3, "blocked": 2, "user_prompt": 2}
    assert trend[1]["total_decisions"] == 1
    assert trend[1]["result_counts"] == {"user_prompt": 1}


def test_routine_ops_breakdown_classifies_git_gh_write_commands(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", LOG_CONTENT)

    decisions = analyze_auto_approve.load_decisions(["2026-08"])
    result = analyze_auto_approve.aggregate(["2026-08"], decisions)

    routine_ops = result["routine_ops"]
    assert routine_ops["total_routine_decisions"] == 3
    assert routine_ops["result_counts"] == {"user_prompt": 2, "approved": 1}
    assert routine_ops["truncated_detail_count"] == 0
    assert routine_ops["patterns_needing_approval"] == [
        {
            "pattern": "git commit",
            "user_prompt_count": 2,
            "approved_count": 1,
            "blocked_count": 0,
            "sample_commands": [
                {"command": 'git commit -m "later"', "count": 1, "possibly_truncated": False},
                {"command": 'git commit -m "wip"', "count": 1, "possibly_truncated": False},
            ],
        }
    ]


def test_pattern_command_samples_orders_by_frequency_then_alphabetically(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", TRUNCATION_LOG_CONTENT)

    decisions = analyze_auto_approve.load_decisions(["2026-08"])
    result = analyze_auto_approve.aggregate(["2026-08"], decisions)

    patterns = {p["pattern"]: p for p in result["routine_ops"]["patterns_needing_approval"]}
    assert patterns["git push"]["sample_commands"] == [
        {"command": "git push origin feature-a", "count": 2, "possibly_truncated": False},
        {"command": "git push origin feature-b", "count": 1, "possibly_truncated": False},
    ]


def test_pattern_command_samples_flags_possibly_truncated_detail(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", TRUNCATION_LOG_CONTENT)

    decisions = analyze_auto_approve.load_decisions(["2026-08"])
    result = analyze_auto_approve.aggregate(["2026-08"], decisions)

    patterns = {p["pattern"]: p for p in result["routine_ops"]["patterns_needing_approval"]}
    assert patterns["git commit"]["sample_commands"] == [
        {"command": LONG_COMMAND_DETAIL, "count": 1, "possibly_truncated": True}
    ]
    assert result["routine_ops"]["truncated_detail_count"] == 1


def test_duration_ms_stats_excludes_na_and_missing_from_numeric_aggregation(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", DURATION_LOG_CONTENT)

    decisions = analyze_auto_approve.load_decisions(["2026-08"])
    result = analyze_auto_approve.aggregate(["2026-08"], decisions)

    stats = result["duration_ms_stats"]
    assert stats["sample_count"] == 4
    assert stats["excluded_count"] == 2
    assert stats["avg_ms"] == 65.0
    assert stats["median_ms"] == 25.0
    assert stats["p95_ms"] == 174.5
    assert stats["max_ms"] == 200
    assert stats["top_slow_patterns"] == [
        {"tool": "Bash", "detail": "git push", "count": 1, "avg_ms": 200.0, "max_ms": 200},
        {"tool": "Bash", "detail": 'git commit -m "a"', "count": 3, "avg_ms": 20.0, "max_ms": 30},
    ]


def test_duration_ms_stats_all_na_or_missing_returns_zeroed_stats(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", LOG_CONTENT)

    decisions = analyze_auto_approve.load_decisions(["2026-08"])
    result = analyze_auto_approve.aggregate(["2026-08"], decisions)

    stats = result["duration_ms_stats"]
    assert stats["sample_count"] == 0
    assert stats["excluded_count"] == 8
    assert stats["avg_ms"] == 0.0
    assert stats["median_ms"] == 0.0
    assert stats["p95_ms"] == 0.0
    assert stats["max_ms"] == 0.0
    assert stats["top_slow_patterns"] == []


def test_main_prints_valid_json(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", LOG_CONTENT)
    monkeypatch.setattr(sys, "argv", ["analyze_auto_approve.py", "--month", "2026-08"])

    analyze_auto_approve.main()

    output = json.loads(capsys.readouterr().out)
    assert output["log_type"] == "auto-approve"
    assert output["total_decisions"] == 8
