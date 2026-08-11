# `commands/analyze-hazard-scan.md` specification

`/analyze-hazard-scan` analyzes both auto-approve and access logs. It derives auto-approve candidates from `routine_ops.patterns_needing_approval` and validates them with a cold-session `--explain` run; it derives access candidates from the three most duplicated paths and their aggregate waste evidence. Only evidence-backed `no-known-hazard` candidates are filed after one explicit batch approval, using the `hazard-candidate` label.

The command never modifies hooks. Access candidates do not invoke `--explain`, because access logs record file access rather than command-approval decisions. Existing candidate issues are deduplicated by source plus candidate command/path.

`/triage-issues-for-hazard` is the required human-review path before a candidate can be implemented.

根拠: `commands/analyze-hazard-scan.md`
