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
    assert routine_ops["patterns_needing_approval"] == [
        {"pattern": "git commit", "user_prompt_count": 2, "approved_count": 1, "blocked_count": 0}
    ]


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
