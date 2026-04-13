Most recent commit at review start: `178e826 Add .codex/ to .gitignore`

Review scope: git-tracked files only. The requested exclusion references `dev/prompts/guidelines/ai-code-evaluator-guidelines.md` and `docs/dev/arch-decisions` are not present in this repository, so there was nothing there to exempt from review.

---

## Issue 1: `log --file` Can Silently Drop All Events

### Description
`LogCommand` disables stdout when `--file` is used without `--stdout`, but `LogFileManager` suppresses file-open failures and leaves `@file_handle` as `nil` instead of failing fast. In that state, `EventLogger` continues running with no usable destination, so the user can start a long-running log session and get no event stream at all. The failure path is in [lib/wifi-wand/commands/log_command.rb](/home/kbennett/code/wifiwand/primary/lib/wifi-wand/commands/log_command.rb:46), [lib/wifi-wand/services/log_file_manager.rb](/home/kbennett/code/wifiwand/primary/lib/wifi-wand/services/log_file_manager.rb:60), and [lib/wifi-wand/services/event_logger.rb](/home/kbennett/code/wifiwand/primary/lib/wifi-wand/services/event_logger.rb:66).

### Assessment
- **Severity:** High
- **Effort to Fix:** Low
- **Impact if Unaddressed:** Users can believe logging is active while the process silently discards the very events they asked to capture.

### Strategy
Make file logging initialization explicit and non-ambiguous. If a requested file destination cannot be opened, either raise a configuration/runtime error before entering the polling loop or automatically fall back to stdout with an unmistakable warning. Add tests for nonexistent parent directories and runtime write failures.

### Actionable Prompt
```text
Fix the wifi-wand log command so file logging never fails silently.

Requirements:
1. In LogCommand/EventLogger/LogFileManager, treat `--file` as a required destination once requested.
2. If the file cannot be opened, fail fast with a user-facing error before the polling loop starts, unless stdout is also enabled and you intentionally choose an explicit fallback.
3. If a fallback is used, print a clear warning that file logging is disabled and stdout is the only remaining sink.
4. Add specs covering:
   - `--file` with a missing parent directory
   - `--file --stdout` when file setup fails
   - write failures after initialization
5. Keep the existing command-line UX for successful cases unchanged.
```

---

## Issue 2: Connectivity Checks Leave Overlapping Worker Threads Behind

### Description
`NetworkConnectivityTester#run_parallel_checks?` spawns one Ruby thread per endpoint/domain and returns as soon as it sees a success or timeout, but it never joins or cancels the remaining workers. That means repeated polling can leave multiple batches of socket/DNS threads alive until each one times out on its own. The core behavior is in [lib/wifi-wand/services/network_connectivity_tester.rb](/home/kbennett/code/wifiwand/primary/lib/wifi-wand/services/network_connectivity_tester.rb:138), and it is exercised repeatedly by status/log flows via [lib/wifi-wand/services/status_line_data_builder.rb](/home/kbennett/code/wifiwand/primary/lib/wifi-wand/services/status_line_data_builder.rb:79). A quick runtime probe confirmed this: thread count rose from 1 to 4 after the caller had already returned, then only dropped back after the sleeping workers finished.

### Assessment
- **Severity:** High
- **Effort to Fix:** Medium
- **Impact if Unaddressed:** Under degraded networks or short polling intervals, long-lived commands can accumulate extra blocked threads, increasing latency and resource use exactly when the tool is supposed to help diagnose outages.

### Strategy
Track worker thread objects, then ensure the caller either joins them before return or moves the checks to a cancellation-aware execution model. Add a regression spec that asserts no worker batch remains alive after a successful or timed-out call returns.

### Actionable Prompt
```text
Remove worker-thread leakage from NetworkConnectivityTester#run_parallel_checks?.

Requirements:
1. Refactor the method so it keeps explicit references to spawned worker threads.
2. When the method returns early on success or timeout, ensure the remaining workers are cleaned up deterministically instead of being left to finish in the background.
3. Preserve the current "return true as soon as any check succeeds" behavior.
4. Add regression tests that verify:
   - no extra worker threads remain after an early success
   - no extra worker threads remain after overall timeout
   - failures still return false
5. Keep the implementation compatible with the existing TCP and DNS call sites.
```

---

## Issue 3: `log` Polling Uses the Expensive Status Pipeline Instead of the Cheap Connectivity Path

### Description
The `EventLogger` class documentation says the logger polls `wifi_on?`, `connected_network_name`, and `fast_connectivity?`, but the implementation actually calls `model.status_line_data`, which performs TCP checks, DNS checks, and captive-portal detection. That path can trigger the captive-portal subprocess fan-out in [lib/wifi-wand/services/captive_portal_checker.rb](/home/kbennett/code/wifiwand/primary/lib/wifi-wand/services/captive_portal_checker.rb:74) on every poll. The mismatch is visible in [lib/wifi-wand/services/event_logger.rb](/home/kbennett/code/wifiwand/primary/lib/wifi-wand/services/event_logger.rb:17) versus [lib/wifi-wand/services/event_logger.rb](/home/kbennett/code/wifiwand/primary/lib/wifi-wand/services/event_logger.rb:120) and [lib/wifi-wand/services/status_line_data_builder.rb](/home/kbennett/code/wifiwand/primary/lib/wifi-wand/services/status_line_data_builder.rb:79).

### Assessment
- **Severity:** Medium
- **Effort to Fix:** Medium
- **Impact if Unaddressed:** The long-running `log` command does more work than its own design intends, making frequent polling slower, noisier, and more expensive during outage diagnosis.

### Strategy
Give logging its own lightweight snapshot path that matches the documented behavior: WiFi power, associated SSID, and fast internet reachability only. Reserve DNS and captive-portal work for one-shot status/info commands where the richer diagnosis is worth the cost.

### Actionable Prompt
```text
Refactor wifi-wand's log command so it uses a lightweight polling path instead of full status_line_data.

Requirements:
1. Replace EventLogger's use of `model.status_line_data` with a purpose-built snapshot that reads:
   - WiFi on/off
   - current SSID
   - fast connectivity state
2. Do not run DNS checks or captive-portal subprocesses on every log poll.
3. Keep emitted event semantics the same (`wifi_on/off`, `connected/disconnected`, `internet_on/off`).
4. Update the class documentation so it matches the implementation.
5. Add specs proving the log path calls `fast_connectivity?` and does not invoke the full status pipeline.
```

---

## Issue 4: Valid 64-Character WPA PSKs Are Rejected Up Front

### Description
`ConnectionManager` hard-limits passwords to 63 characters in all cases. That matches WPA passphrases, but it rejects the other valid input form: a 64-character hexadecimal pre-shared key. The hard limit is enforced in [lib/wifi-wand/services/connection_manager.rb](/home/kbennett/code/wifiwand/primary/lib/wifi-wand/services/connection_manager.rb:7) and [lib/wifi-wand/services/connection_manager.rb](/home/kbennett/code/wifiwand/primary/lib/wifi-wand/services/connection_manager.rb:80), and the current spec suite explicitly locks that behavior in.

### Assessment
- **Severity:** Medium
- **Effort to Fix:** Low
- **Impact if Unaddressed:** Users with networks configured via raw PSKs cannot connect through wifi-wand even though the underlying OS tools can.

### Strategy
Differentiate between passphrases and raw PSKs during validation. Continue rejecting oversized normal passwords, but allow exactly 64 hex characters and pass them through unchanged to the OS-specific connection commands.

### Actionable Prompt
```text
Update wifi-wand password validation to support raw 64-character WPA PSKs.

Requirements:
1. In ConnectionManager, keep support for normal WPA passphrases up to 63 characters.
2. Also allow exactly 64 hexadecimal characters as a valid raw PSK.
3. Preserve existing validation for blank values, control characters, and non-string input.
4. Update or replace the current specs that reject 64-character passwords so they distinguish:
   - valid 64-char hex PSKs
   - invalid 64-char non-hex strings
   - valid 63-char passphrases
5. Do not change the external CLI/API shape.
```

---

## Issue 5: Coverage Reporting Is Not Trustworthy Enough to Guide Fix Priorities

### Description
`CoverageConfig` starts SimpleCov but does not define tracked files, so coverage only reflects files touched by the last run. In the current repository state, `cov-loupe --format json list` reports 29 of 34 covered files as stale with `length_mismatch`, and several tracked Ruby entrypoints are missing entirely from the result set, including `lib/wifi-wand/services/captive_portal_probe_helper.rb`. The relevant setup is in [spec/support/coverage_config.rb](/home/kbennett/code/wifiwand/primary/spec/support/coverage_config.rb:9).

### Assessment
- **Severity:** Low
- **Effort to Fix:** Low
- **Impact if Unaddressed:** Coverage percentages will keep overstating confidence and under-reporting blind spots, which makes sprint planning and bug-fix prioritization less reliable.

### Strategy
Track the repo’s Ruby sources explicitly and add a cheap coverage sanity check that fails when tracked runtime files disappear from the result set or when stale coverage dominates the report.

### Actionable Prompt
```text
Make wifi-wand's coverage output reliable enough for prioritization work.

Requirements:
1. Update CoverageConfig to track the repository's runtime Ruby files explicitly instead of only whatever the last test run happened to load.
2. Ensure helper/entrypoint files such as `lib/wifi-wand/services/captive_portal_probe_helper.rb` are represented in coverage output.
3. Add a small verification step or spec helper check that catches stale or missing tracked files early.
4. Keep the existing separate resultset behavior for default vs real-environment runs.
5. Document the intended coverage workflow so `cov-loupe` output stays actionable.
```

---

## Summary Table

| Brief Description (<= 50 chars) | Severity (H/M/L) | Effort (H/M/L) | Impact if Unaddressed | Link to Detail |
| :--- | :---: | :---: | :--- | :--- |
| `log --file` can drop all events | H | L | Logging sessions can run with no effective output sink | [See below](#issue-1-log---file-can-silently-drop-all-events) |
| Connectivity checks leave live threads | H | M | Repeated polling can accumulate blocked workers during outages | [See below](#issue-2-connectivity-checks-leave-overlapping-worker-threads-behind) |
| `log` uses full status pipeline | M | M | Long-running logging does needless DNS and captive-portal work | [See below](#issue-3-log-polling-uses-the-expensive-status-pipeline-instead-of-the-cheap-connectivity-path) |
| 64-char WPA PSKs are rejected | M | L | Valid raw PSK networks cannot be connected through the tool | [See below](#issue-4-valid-64-character-wpa-psks-are-rejected-up-front) |
| Coverage data is stale/missing | L | L | Prioritization decisions rely on misleading coverage numbers | [See below](#issue-5-coverage-reporting-is-not-trustworthy-enough-to-guide-fix-priorities) |
