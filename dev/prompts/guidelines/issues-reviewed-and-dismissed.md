# Issues Reviewed And Dismissed

## Coverage artifacts can be stale or partial

1) Do not report coverage reliability as a code issue just because SimpleCov output only reflects files
   touched by the last run or `cov-loupe` reports stale entries for an old or filtered resultset.

This repository keeps separate coverage resultsets for default and real-environment runs, and coverage data is
only trustworthy for the exact test scope that generated it. If someone wants to rely on coverage data for
prioritization or planning, it is the developer's responsibility to run a fresh full test suite first and then
check tracked runtime files with cov-loupe.

Raise this again only if docs or tooling start treating partial coverage as whole-repo authoritative, or if CI
depends on stale coverage as if it were complete. It is also valid to raise concrete gaps where a fresh
whole-codebase coverage review omits or misclassifies tracked runtime files.

## Verbose output can include plaintext WiFi passwords

1) Do not report plaintext password visibility in verbose troubleshooting output as an immediate code defect
   by default.

This utility is primarily intended for individual use, and verbose output is part of the troubleshooting
experience. Showing the actual password can help diagnose bad credentials, malformed PSKs, and other
connection problems. Hiding or redacting passwords in all output paths would reduce usability for the
maintainer's current workflow.

This topic may be revisited in a future version if the product's audience changes, if persistent logging of
password-bearing output becomes a documented workflow, or if maintainers decide to distinguish between
interactive troubleshooting output and durable retained logs. Until then, do not raise this as a current
action item merely because passwords may appear in verbose output.


## `try_os_command_until` retry throttling is intentionally minimal

1) Do not report the fixed 1 ms sleep between failed `try_os_command_until` attempts as an
   excessive delay by default.

The loop now includes a minimal throttle to prevent tight process-spawn loops when callers pass
trivially fast commands. The delay is deliberately small because WiFi management commands (`nmcli`,
`networksetup`, `iw`, etc.) are already I/O-bound and typically dominate retry timing.

Raise this again only if a production caller needs a configurable retry interval or if the fixed
delay demonstrably harms a real workflow.


## WPA minimum-length validation should stay OS-driven

1) Do not raise lack of SSID-specific WPA minimum-length validation as a current
   code issue by default.

wifi-wand should reject malformed raw PSKs and impossible byte lengths, but it
should not duplicate OS-specific security-type inference just to enforce WPA's
8-character minimum locally. That approach increases cross-platform complexity
and has already shown regression risk around idempotent reconnects and macOS
scan-list interpretation.

Raise this again only if the project gains a stable, low-complexity,
platform-agnostic source of target security type, or if maintainers explicitly
want wifi-wand to become authoritative for per-protocol credential validation.
