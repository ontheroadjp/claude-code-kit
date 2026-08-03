import json
import sys
import textwrap
from pathlib import Path

import pytest

import analyze_token_usage
from lib import analyze_common

# session s1 appears twice (cumulative rows); only the second (higher) row
# should count toward aggregates. session s2 appears once.
LOG_CONTENT = textwrap.dedent(
    """\
    [2026-08-01 10:00:00] session=s1  name=                 model=claude-sonnet-5  turns=  1  input=   100  output=   200  cache_read=    500  cache_create=   100  total=    300  cache_ratio= 80.0  cost_usd=  1.0000  branch=main  cwd=repo-a
    [2026-08-01 10:05:00] session=s1  name=                 model=claude-sonnet-5  turns=  3  input=   150  output=   600  cache_read=   1500  cache_create=   100  total=    850  cache_ratio= 90.0  cost_usd=  3.0000  branch=main  cwd=repo-a
    [2026-08-02 09:00:00] session=s2  name=demo             model=claude-opus-5    turns=  5  input=   200  output=  9000  cache_read=    100  cache_create=   100  total=  9300  cache_ratio= 10.0  cost_usd=  9.5000  branch=feat/x  cwd=repo-b
    [2026-08-02 09:10:00] session=s3  name=big               model=claude-opus-5    turns=  1  input=   500  output= 30000  cache_read=      0  cache_create=     0  total= 30500  cache_ratio= 95.0  cost_usd=  2.5000  branch=main  cwd=repo-b
    """
)


def write_log(tmp_path: Path, month: str, content: str) -> None:
    log_dir = tmp_path / "logs" / "token-usage"
    log_dir.mkdir(parents=True, exist_ok=True)
    (log_dir / f"{month}.log").write_text(content, encoding="utf-8")


def test_parse_line_extracts_all_fields() -> None:
    line = (
        "[2026-08-01 10:00:00] session=s1  name=                 model=claude-sonnet-5  turns=  1  "
        "input=   100  output=   200  cache_read=    500  cache_create=   100  total=    300  "
        "cache_ratio= 80.0  cost_usd=  1.0000  branch=main  cwd=repo-a"
    )
    record = analyze_token_usage.parse_line(line)
    assert record is not None
    assert record["session"] == "s1"
    assert record["model"] == "claude-sonnet-5"
    assert record["turns"] == 1
    assert record["cost_usd"] == 1.0
    assert record["branch"] == "main"
    assert record["cwd"] == "repo-a"


def test_dedupe_keeps_last_row_per_session() -> None:
    records = [analyze_token_usage.parse_line(line) for line in LOG_CONTENT.splitlines()]
    sessions = analyze_token_usage.dedupe_last_per_session([r for r in records if r is not None])
    assert len(sessions) == 3
    s1 = next(s for s in sessions if s["session"] == "s1")
    assert s1["cost_usd"] == 3.0
    assert s1["turns"] == 3


def test_aggregate_uses_deduped_totals(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", LOG_CONTENT)

    records = analyze_token_usage.load_records(["2026-08"])
    result = analyze_token_usage.aggregate(["2026-08"], records)

    assert result["raw_line_count"] == 4
    assert result["session_count"] == 3
    assert result["total_cost_usd"] == 15.0  # 3.0 (s1 final) + 9.5 (s2) + 2.5 (s3), not 1.0+3.0+9.5+2.5
    assert result["low_cache_sessions"] == [
        {"session": "s2", "model": "claude-opus-5", "turns": 5, "cache_ratio": 10.0}
    ]
    assert result["high_density_sessions"] == [
        {"session": "s3", "model": "claude-opus-5", "turns": 1, "tokens_per_turn": 30500}
    ]


def test_main_prints_valid_json(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(analyze_common, "repo_root", lambda: tmp_path)
    write_log(tmp_path, "2026-08", LOG_CONTENT)
    monkeypatch.setattr(sys, "argv", ["analyze_token_usage.py", "--month", "2026-08"])

    analyze_token_usage.main()

    output = json.loads(capsys.readouterr().out)
    assert output["log_type"] == "token-usage"
    assert output["session_count"] == 3
