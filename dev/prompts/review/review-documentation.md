# Review Documentation

**Purpose:** Review WifiWand's Markdown documentation for accuracy, clarity,
completeness, and consistency without making changes.

## When to Use This

- Before documentation cleanup work.
- Before a release or README refresh.
- When you want a prioritized documentation issue list, not direct edits.
- When checking whether docs still match the current CLI, Ruby API, platform
  behavior, and packaging.

For a prompt that fixes documentation in place, use
`dev/prompts/update-documentation.md` instead.

---

## Preconditions

Before you begin:

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding so they can
   choose to start a new session in the project root.
2. Always open the report by citing the most recent git commit at the time you
   begin writing.
3. Limit the review strictly to git-tracked files unless the user explicitly
   asks you to include untracked files.
4. If `git status` shows uncommitted changes, inform me, ask for confirmation
   to proceed, and-if I consent-include those `git status` details immediately
   after the commit citation.
5. Inspect the project guidance first: `AGENTS.md`, `README.md`, `Gemfile`,
   `wifi-wand.gemspec`, `.rubocop.yml`, and `.rspec` when present.

---

## Scope

Review Markdown documentation in:

- `*.md`
- `docs/**/*.md`
- `dev/docs/**/*.md`
- `dev/prompts/**/*.md`
- `AGENTS.md`

## What to Review

### Accuracy

- Claims that no longer match the code, generated help, CLI flags, method names,
  command aliases, output formats, file paths, or packaging.
- Code examples that produce different output than documented, rely on removed
  behavior, or use obsolete names.
- Version numbers, dependency names, environment variables, setup commands, or
  configuration keys that have changed.
- References to WifiWand naming:
  - gem name: `wifi-wand`
  - primary executable: `wifiwand`
  - setup executable: `wifiwand-macos-setup`
  - Ruby require path: `wifi_wand`
- Platform claims for macOS and Ubuntu support, including `networksetup`,
  `system_profiler`, `ifconfig`, `nmcli`, `iw`, `ip`, optional `qrencode`, and
  macOS helper-app behavior.
- Version 3 semantics such as explicit boolean values, exact command names,
  `shell`, `internet_connectivity_state`, and removed partial abbreviations.

### Clarity

- Sections that assume prior knowledge without a prerequisite or link.
- Ambiguous wording, unexplained jargon, or prose that mixes CLI mode,
  interactive shell mode, and Ruby library usage.
- Over-long explanations where a concise rewrite would preserve meaning.
- Safety-sensitive language around WiFi passwords, verbose output, process
  listings, terminal history, QR code files, and real network mutation.

### Completeness

- Missing prerequisites for commands or platform-specific features.
- Gaps between the feature behavior and what docs say it does.
- New CLI commands, aliases, options, output formats, environment variables,
  setup scripts, helper-app behavior, or platform requirements not documented.
- Missing warnings for examples that can connect, disconnect, cycle WiFi, change
  DNS, alter saved networks, or expose passwords.

### Link Integrity

Check internal links and anchors:

- Verify that each relative Markdown target exists.
- Verify that each `#heading-id` matches an actual heading in the target file.
- Note missing reciprocal navigation where it would help readers move between
  the README, docs index, setup guides, command guides, and security notes.

### Duplication

- Identify duplicated explanations and recommend a canonical location.
- Prefer linking over maintaining the same detail in several files.
- Treat generated CLI help as the canonical command reference unless a document
  has a clear reason to include command details inline.

### Examples

- Review whether shell examples use current flags and executable names.
- Prefer development examples using `bundle exec exe/wifiwand ...` and installed
  user examples using `wifiwand ...`.
- Do not run real-environment read-write examples unless the user explicitly
  approves that validation.
- Quote bracketed Rake task arguments such as `test:real[spec/foo_spec.rb]` for
  shell portability.

## Report Structure

Write a Markdown report with these sections:

1. **Commit and Scope:** cite the commit reviewed and any uncommitted changes
   included.
2. **Executive Summary:** concise assessment of documentation health.
3. **Findings:** prioritized documentation issues. For each finding include:
   - File path and line number when practical.
   - Severity: High/Medium/Low.
   - Description.
   - Recommended change.
4. **Link and Example Checks:** summarize broken links, suspicious anchors, and
   examples that need manual validation.
5. **Prioritized Fix List:** table ordered by expected value.
6. **Suggested Prompts:** copy-paste-ready prompts for an AI coding agent to
   address the highest-value documentation fixes.

## Output File

Write the report in `untracked/` (mkdir if necessary). Name it:

- today's date in UTC `%Y-%m-%d-%H-%M` format +
- `-documentation-review-` +
- your name (for example, `codex`, `claude`, `gemini`, `zai`) +
- `.md`

Example: `2026-01-08-19-45-documentation-review-codex.md`

## Constraints

- **DO NOT MAKE ANY CODE OR DOCUMENTATION CHANGES. REVIEW ONLY.**
- Do not run `git commit`.
- Do not run real-environment read-write WiFi commands without explicit user
  approval.
- Migration and release documents must describe the project as it existed for
  that version. Do not flag older migration docs merely because they preserve
  historically accurate old names or APIs.
