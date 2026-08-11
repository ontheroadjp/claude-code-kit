# `commands/triage-issues-for-hazard.md` specification

`/triage-issues-for-hazard` lists open `hazard-candidate` issues, discloses their source-specific analysis verbatim, and asks for a yes/no decision per issue. A yes swaps `hazard-candidate` for `triage-approved` and directs the user to run `/work #N`; it never starts `/work` itself.

Only label swaps and creation of the `triage-approved` label are permitted writes. Session grants are scoped to issue numbers listed during the run.

根拠: `commands/triage-issues-for-hazard.md`
