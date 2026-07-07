# Review and Revise Documentation as Necessary

**Purpose:** Keep WifiWand's Markdown documentation accurate, clear, complete, and internally consistent.

## Preconditions

Before you begin:

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding so they can
   choose to start a new session in the project root.
2. Inspect the project guidance first: `AGENTS.md`, `README.md`, `Gemfile`,
   `wifi-wand.gemspec`, `.rubocop.yml`, and `.rspec` when present.

---

## Scope

Examine all Markdown files in:

- `*.md`
- `docs/**/*.md`
- `dev/docs/**/*.md`
- `dev/prompts/**/*.md`
- `AGENTS.md`

## What to Look For

### Accuracy

- Claims that no longer match the code (CLI flags, method names, output formats, file paths).
- Code examples that produce different output than documented, or that refer to removed features.
- Version numbers, dependency names, or configuration keys that have changed.
- References to the gem, executable, and library names:
  - gem name: `wifi-wand`
  - primary executable: `wifiwand`
  - setup executable: `wifiwand-macos-setup`
  - Ruby require path: `wifi_wand`
- Platform claims for macOS and Ubuntu support, including OS-specific command
  dependencies such as `networksetup`, `system_profiler`, `ifconfig`, `nmcli`,
  `iw`, and `ip`.
- macOS helper-app guidance for macOS 14+ Location Services access and
  redacted network names.
- CLI semantics that changed in version 3, including explicit boolean option
  values, exact command names/aliases, the `shell` command, and the
  `internet_connectivity_state` API.

### Clarity

- Sections that assume prior knowledge not provided in the doc or a clearly-linked prerequisite.
- Ambiguous pronouns or unexplained jargon; if the meaning is unclear on first read, rewrite it.
- Paragraphs that mix distinct topics; split or reorganise them.
- Over-long explanations where a concise rewrite would preserve meaning with less noise.
- Instructions that blur CLI mode, interactive shell mode, and Ruby library usage.

### Completeness

- Missing prerequisites: if a command requires setup, the setup must be described or linked.
- Gaps between what a feature does and what the docs say it does.
- New CLI subcommands, aliases, options, output formats, environment variables,
  setup scripts, or helper-app behavior not yet documented.
- Safety notes for commands that can reveal WiFi passwords or modify real
  network state.
- Platform-specific setup requirements, especially Ubuntu NetworkManager tools,
  optional `qrencode`, and macOS helper installation.

### Link Integrity

Check internal links (relative Markdown paths) and anchor links (`#heading-id`):

- Verify that the target file exists at the referenced path.
- Verify that named anchors (`#section-name`) match an actual heading in the target document.
- Check that bidirectional navigation links exist where expected (e.g., a top-level README links
  to a specialist doc, and that doc links back with text like `Back to main README`).

### Duplication

- If the same point is explained in multiple documents, decide which is the canonical location
  and replace the others with a brief note and a link to it.
- Do not duplicate content that is already maintained elsewhere; link instead.
- Treat generated CLI help as the canonical command reference. Documentation
  should summarize or point to help output rather than maintaining large,
  duplicated command tables unless there is a clear reason.

### Code Examples

- Confirm that shell/CLI examples use current flag names and produce valid output.
- Prefer `bundle exec exe/wifiwand ...` for development-check examples and
  `wifiwand ...` for installed-user examples.
- Do not run examples that intentionally connect, disconnect, cycle WiFi,
  change DNS, alter saved networks, or otherwise mutate the current network
  environment unless the user explicitly approves that manual validation.
- When examples use bracketed Rake task arguments such as
  `test:real[spec/foo_spec.rb]`, quote them for shell portability.
- For coverage-related documentation, use cov-loupe MCP tools or the
  `cov-loupe` CLI rather than reading `.resultset.json` directly.

## Actions to Take

1. **Fix in place** - edit the doc file directly; no separate report is needed
   unless the scope of changes warrants a summary.
2. **Prefer linking over duplicating** - when the same information belongs in
   two places, keep the authoritative copy and add a short cross-reference
   elsewhere.
3. **Match existing tone** - keep edits consistent with the surrounding prose style.
4. **Do not rewrite for rewriting's sake** - only change what is inaccurate, unclear, or missing.
5. **Preserve migration history** - migration and release documents must
   describe the project as it existed for that version. Do not retroactively
   update old migration docs with APIs or names introduced later.

## Constraints

- Do not alter code files unless a documented example is genuinely broken and a
  code fix is clearly correct; prefer updating the docs to match current
  behaviour.
- Do not run real-environment read-write commands unless the user explicitly
  approves them for the current machine and network.
- Do not run `git commit`. Stage only the documentation files you changed, and
  propose a concise commit message describing what was corrected and why.
