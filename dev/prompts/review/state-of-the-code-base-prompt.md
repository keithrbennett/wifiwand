# State of the Code Base Prompt

You are a senior software architect and code reviewer. Analyze this code base thoroughly and report on its
state, focusing on weaknesses, risks, and areas for improvement. For each issue, assess its seriousness and
cost to fix, and give a high-level strategy for addressing it.

**DO NOT MAKE ANY CODE CHANGES. REVIEW ONLY.**

## Ground Rules

- First read the project's agent and contributor guidance (e.g., AGENTS.md, CLAUDE.md, CONTRIBUTING.md) and
  the README.
- Back every finding with evidence: cite `path/to/file.rb:line` (or a command and its output). Label anything
  you could not verify as an inference.
- Do not invent issues to fill sections. If a section has nothing significant, say so briefly.
- Only run commands that do not change the host or external systems (e.g., the default test suite, linters).
  Do not run anything that deploys, publishes, migrates real data, or calls paid or production services.
- Follow the Project-Specific Instructions at the end; they override these general rules where they conflict.
- If earlier reports of this kind exist in the output directory, compare with the most recent one and note
  what has improved or regressed.

## Output

Write the report to `untracked/` (create it if needed) unless the Project-Specific Instructions name another
directory. Name it
`YYYY-MM-DD-state-of-the-code-base-<agent>.md`, where the date is today's date and `<agent>` is your
lowercase tool or model family name (e.g. `claude`, `codex`, `gemini`, `zai`).

## Scoring

Score each dimension from 1 to 10:

- **9–10:** Exemplary; nothing significant to fix.
- **7–8:** Solid; minor issues only.
- **5–6:** Adequate; notable issues that slow work or add risk.
- **3–4:** Weak; issues that regularly cause defects or friction.
- **1–2:** Failing; needs immediate attention.

Choose weights suited to this project's nature (e.g., a library, CLI, web service, or data pipeline), and
explain the choice briefly. The weights must sum to 100%.

## Report Structure

### Executive Summary

- A concise overview of the code base's overall health.
- The strongest and weakest areas.
- A **one-line verdict** (e.g., *"Overall: Fair, with major risks in testing and error handling"*).
- The **Overall Weighted Score (1–10)** from the final section.

### Critical Blockers

Issues so severe that they must be resolved before meaningful progress can continue, or "None". For each,
give the **Description**, **Impact**, **Urgency**, and **Cost to Fix** (High/Medium/Low).

### Architecture & Design

- Summarize the architecture (layering, main components and how they interact, key abstractions).
- Identify strengths and weaknesses, and areas of high complexity, coupling, or technical debt.
- Assess maintainability, extensibility (the cost of adding a typical new feature), and clarity.
- **Score (1–10)**

### Code Quality

- Identify recurring issues: duplication, long methods, deep nesting, unclear naming.
- Point out readability and maintainability concerns.
- **Score (1–10)**

### Build, CI & Release

- Evaluate CI/CD pipelines, build scripts and task runners, packaging and release processes, git hooks,
  containers, and infrastructure-as-code, as present.
- Highlight brittle, outdated, or redundant configuration, and gaps in what CI verifies (platforms, runtime
  versions, checks).
- **Score (1–10)**

### Dependencies & External Integrations

- List major runtime and development dependencies, and external services, APIs, or system tools the code
  relies on.
- Note outdated, unmaintained, or risky dependencies and their upgrade cost.
- Assess vendor lock-in and fragility against changes in external integrations.
- **Score (1–10)**

### Test Coverage

- Use the project's coverage data. For Ruby projects with SimpleCov, use the cov-loupe MCP server
  (`project_coverage`, `file_coverage_summary`, `file_uncovered_lines`) rather than reading resultsets
  directly or reasoning from scratch; fall back to the `cov-loupe` CLI only if the MCP server is unavailable.
  If no coverage data exists, say so and assess tests qualitatively.
- Include a summary table of coverage by component and list the least-covered files.
- Measure whole-codebase coverage against all production source files, and report files missing from the
  coverage data. Do not rely only on the aggregate percentage.
- State which coverage data you used and whether it is current.
- Rank coverage gaps by risk, highest first, and name the untested critical paths and their consequences.
- **Score (1–10)**

### Security & Reliability

- Identify insecure practices: injection risks (shell, SQL, etc.), hardcoded secrets, secrets leaking into
  logs or output, and missing input validation.
- Assess error handling, timeouts, retries, and behavior when external calls fail or return unexpected
  results.
- **Score (1–10)**

### Documentation & Onboarding

- Evaluate the README, user documentation, inline docs, and contributor/agent guidance.
- Identify missing, outdated, or inconsistent documentation, including docs that contradict the code.
- **Score (1–10)**

### Performance & Efficiency

- Highlight bottlenecks and inefficient patterns (e.g., startup time, redundant I/O or external calls, N+1
  queries, unnecessary polling).
- State whether each optimization is low-cost or high-cost.
- **Score (1–10)**

### Formatting & Style Conformance

- Report the configured linters' and formatters' results and any significant patterns behind them.
- Report formatting problems in other files (broken Markdown, inconsistent YAML, and the like).
- **Score (1–10)**

### Best Practices & Conciseness

- Assess adherence to the language's idioms and conventions, modularization, and separation of concerns.
- Evaluate verbosity against clarity: is the code concise without being cryptic?
- **Score (1–10)**

### Prioritized Issue List

A table of the top issues, ordered so that working through them top to bottom delivers the most value
soonest (weigh severity against cost to fix; cheap, high-impact fixes come first).

| ID | Issue | Location | Severity | Cost to Fix | Impact if Unaddressed |
|----|-------|----------|----------|-------------|-----------------------|
| 1 | Example issue description | `src/foo.rb:42` | High | Low | Silent data loss on retry |

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

## Project-Specific Instructions

Replace or delete this section when reusing this prompt in another project.

- Read [AGENTS.md](../../../AGENTS.md) first.
- wifiwand is a cross-platform (macOS/Ubuntu) Ruby CLI and library that shells out to OS networking tools
  (e.g., `networksetup`, `nmcli`). Weight dimensions accordingly.
- `bundle exec rake test:safe` and `bundle exec rubocop` are safe to run. **Never run real-env tests**
  (`test:read_only`, `test:all`, `test:real[...]`); they touch, and may change, the host's network state.
- Coverage: use `lib/**/*.rb` as the intended runtime file set. The default run writes
  `coverage/.resultset.json`; real-env runs write `coverage/.resultset.<os>.json`. Do not count low coverage
  of OS-specific code against the score when that code targets a different OS from the one the tests ran on.
- Architecture: assess the platform abstraction (macOS/Ubuntu models) and the cost of adding a platform or
  command.
- Build & release: include the macOS helper build/release process and the docs build.
- Security: check how shell commands are built from SSIDs, passwords, and other user input, and whether
  secrets leak through verbose output. Assess behavior when OS commands fail or their output changes across
  OS versions.
- Performance: consider CLI startup time, redundant OS command calls, and polling/sleep intervals.
