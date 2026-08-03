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
      - /path/a (2回)

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

LOG_CONTENT = "\n---\n\n" + SESSION_1 + "\n---\n\n" + SESSION_2


def write_log(tmp_path: Path, month: str, content: str) -> None:
    access_dir = tmp_path / "logs" / "access"
    access_dir.mkdir(parents=True, exist_ok=True)
    (access_dir / f"{month}.log").write_text(content, encoding="utf-8")


def test_split_blocks_returns_one_block_per_session() -> None:
    blocks = analyze_access.split_blocks(LOG_CONTENT)
    assert len(blocks) == 2


def test_parse_session_extracts_summary_and_token_usage() -> None:
    block = analyze_access.split_blocks(LOG_CONTENT)[0]
    session = analyze_access.parse_session(analyze_access.split_sections(block))
    assert session is not None
    assert session["total_accesses"] == 3
    assert session["duplicates"] == [{"path": "/path/a", "count": 2}]
    assert session["modified_files"] == ["/path/a"]
    assert session["token_usage"] == {
        "input": 100,
        "output": 200,
        "cache_read": 50,
        "cache_ratio": 33.3,
        "total": 300,
        "cost_usd": 1.2345,
    }


def test_parse_session_handles_no_duplicates_and_no_token_usage() -> None:
    block = analyze_access.split_blocks(LOG_CONTENT)[1]
    session = analyze_access.parse_session(analyze_access.split_sections(block))
    assert session is not None
    assert session["duplicates"] == []
    assert session["modified_files"] == []
    assert session["token_usage"] is None


def test_aggregate_across_sessions(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", LOG_CONTENT)

    sessions = analyze_access.load_sessions(["2026-08"])
    result = analyze_access.aggregate(["2026-08"], sessions)

    assert result["session_count"] == 2
    assert result["total_accesses"] == 5
    assert result["zero_modified_sessions"] == 1
    assert result["zero_modified_ratio"] == 0.5
    assert result["top_duplicate_files"] == [{"path": "/path/a", "count": 2}]
    assert result["top_modified_files"] == [{"path": "/path/a", "count": 1}]
    assert result["phase_totals"] == {"work": 5}
    assert result["tool_totals"] == {"Read": 4, "Bash": 1}
    assert result["token_usage"]["sessions_with_data"] == 1
    assert result["token_usage"]["total_cost_usd"] == 1.2345


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
    assert output["session_count"] == 2
