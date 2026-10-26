# State of the Code Base Prompt

You are a senior software architect and code reviewer. Analyze this code base thoroughly and report on its
state, focusing on weaknesses, risks, and areas for improvement. For each issue, assess its seriousness and
cost to fix, and give a high-level strategy for addressing it.

**DO NOT MAKE ANY CODE CHANGES. REVIEW ONLY.**

## Ground Rules

- Read [AGENTS.md](../../../AGENTS.md) first; it describes the architecture, test strategy, and conventions.
- Back every finding with evidence: cite `path/to/file.rb:line` (or a command and its output). Label anything
  you could not verify as an inference.
- Do not invent issues to fill sections. If a section has nothing significant, say so briefly.
- Only run commands that do not change the host. `bundle exec rake test:safe` and `bundle exec rubocop` are
  fine. **Never run real-env tests** (`test:read_only`, `test:all`, `test:real[...]`); they touch, and may
  change, the host's network state.
- Use the cov-loupe MCP server for coverage data (`project_coverage`, `file_coverage_summary`,
  `file_uncovered_lines`). Prefer it over reading SimpleCov resultsets directly or reasoning from scratch; fall
  back to the `cov-loupe` CLI only if the MCP server is unavailable.
- If earlier reports of this kind exist in `untracked/`, compare with the most recent one and note what has
  improved or regressed.

## Output

Write the report to `untracked/` (create it if needed), named
`YYYY-MM-DD-state-of-the-code-base-<agent>.md`, where the date is today's date and `<agent>` is your
lowercase tool or model family name (e.g. `claude`, `codex`, `gemini`, `zai`).

## Scoring

Score each dimension from 1 to 10:

- **9–10:** Exemplary; nothing significant to fix.
- **7–8:** Solid; minor issues only.
- **5–6:** Adequate; notable issues that slow work or add risk.
- **3–4:** Weak; issues that regularly cause defects or friction.
- **1–2:** Failing; needs immediate attention.

Choose weights suited to this project (a cross-platform Ruby CLI and library that shells out to OS tools).
The weights must sum to 100%.

## Report Structure

### Executive Summary

- A concise overview of the code base's overall health.
- The strongest and weakest areas.
- A **one-line verdict** (e.g., *"Overall: Good, with risks in platform-specific test coverage"*).
- The **Overall Weighted Score (1–10)** from the final section.

### Critical Blockers

Issues so severe that they must be resolved before meaningful progress can continue, or "None". For each,
give the **Description**, **Impact**, **Urgency**, and **Cost to Fix** (High/Medium/Low).

### Architecture & Design

- Summarize the architecture: layering, the platform abstraction (macOS/Ubuntu models), and how the CLI,
  commands, services, and models fit together.
- Identify strengths and weaknesses, and areas of high complexity, coupling, or technical debt.
- Assess maintainability, extensibility (e.g., cost of adding a platform or command), and clarity.
- **Score (1–10)**

### Code Quality

- Identify recurring issues: duplication, long methods, deep nesting, unclear naming.
- Point out readability and maintainability concerns.
- **Score (1–10)**

### Build, CI & Release

- Evaluate the GitHub Actions workflows, Rakefile tasks, gemspec, git hooks, `bin/` scripts, the macOS helper
  build/release process, and the docs build.
- Highlight brittle, outdated, or redundant configuration, and gaps in the CI matrix.
- **Score (1–10)**

### Dependencies & External Integrations

- List major runtime and development dependencies, and the OS commands the code relies on (e.g.,
  `networksetup`, `nmcli`).
- Note outdated or risky dependencies and their upgrade cost.
- Assess fragility against OS version changes and differences in command output.
- **Score (1–10)**

### Test Coverage

- Include a summary table of coverage by component (Core, Services, Platforms, Shared Models) and list the
  least-covered files.
- For whole-codebase claims, call `project_coverage` with the intended runtime file set (`lib/**/*.rb`) and
  report files missing from the SimpleCov resultset. Do not rely only on the aggregate percentage.
- State which resultset you used and whether it is current. The default run writes
  `coverage/.resultset.json`; real-env runs write `coverage/.resultset.<os>.json`.
- Do not count low coverage of OS-specific code against the score when that code targets a different OS from
  the one the tests ran on.
- Rank coverage gaps by risk, highest first, and name the untested critical paths and their consequences.
- **Score (1–10)**

### Security & Reliability

- Check how shell commands are built (injection risk from SSIDs, passwords, and other user input), whether
  secrets leak through logs or verbose output, and whether input is validated.
- Assess error handling, timeouts, retries, and behavior when OS commands fail or return unexpected output.
- **Score (1–10)**

### Documentation & Onboarding

- Evaluate the README, the `docs/` site, inline docs, and contributor guidance (AGENTS.md, CONTRIBUTING.md).
- Identify missing, outdated, or inconsistent documentation, including docs that contradict the code.
- **Score (1–10)**

### Performance & Efficiency

- Highlight bottlenecks: CLI startup time, redundant OS command calls, polling and sleep intervals.
- State whether each optimization is low-cost or high-cost.
- **Score (1–10)**

### Formatting & Style Conformance

- Report the RuboCop results and any significant patterns behind them.
- Report formatting problems outside Ruby (broken Markdown, inconsistent YAML, and the like).
- **Score (1–10)**

### Best Practices & Conciseness

- Assess adherence to Ruby idioms and conventions, modularization, and separation of concerns.
- Evaluate verbosity against clarity: is the code concise without being cryptic?
- **Score (1–10)**

### Prioritized Issue List

A table of the top issues, ordered so that working through them top to bottom delivers the most value
soonest (weigh severity against cost to fix; cheap, high-impact fixes come first).

| ID | Issue | Location | Severity | Cost to Fix | Impact if Unaddressed |
|----|-------|----------|----------|-------------|-----------------------|
| 1 | Example issue description | `lib/wifi_wand/foo.rb:42` | High | Low | Silent failures on Ubuntu |

### High-Level Recommendations

- General strategies for improvement (refactoring, coverage, dependency upgrades, modularization).
- Where incremental change is enough and where larger changes are justified.

### Suggested Prompts

For each major issue, a self-contained prompt for a coding AI tool that would address it. Reference the
issue's ID.

### Overall Weighted Score

Show the weights table and the calculation (score × weight for each dimension, summed). Then give the
**Overall Weighted Score (1–10)** with a brief justification.

| Dimension                    | Score | Weight | Weighted |
|------------------------------|-------|--------|----------|
| Architecture & Design        | ?     | ?%     | ?        |
| Code Quality                 | ?     | ?%     | ?        |
| Build, CI & Release          | ?     | ?%     | ?        |
| Dependencies                 | ?     | ?%     | ?        |
| Test Coverage                | ?     | ?%     | ?        |
| Security & Reliability       | ?     | ?%     | ?        |
| Documentation                | ?     | ?%     | ?        |
| Performance & Efficiency     | ?     | ?%     | ?        |
| Formatting & Style           | ?     | ?%     | ?        |
| Best Practices & Conciseness | ?     | ?%     | ?        |
| **Total**                    |       | 100%   | **?**    |
