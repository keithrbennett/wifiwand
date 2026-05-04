# WIFI_WAND Environment Variables Report Prompt

You are a senior Ruby engineer auditing this repository for configuration surface area and maintainability.

Prepare a comprehensive Markdown report of every environment variable used by this code base whose name starts
with `WIFI_WAND`.

Include the main application and every supporting area of the repository, including scripts, Rake tasks, test
helpers, specs, executable files, release tooling, documentation examples, and any development utilities.

## Required Scope

- Search the full repository, not just `lib/`.
- Include exact variable names and every file where each variable is referenced.
- Identify how each variable is read or set, such as `ENV.fetch`, `ENV[]`, shell assignment, Rake task usage,
  test stubbing, documentation-only mention, or generated command example.
- Distinguish runtime behavior from test-only, script-only, documentation-only, and development-only usage.
- Note default values, fallback behavior, expected value formats, and whether the variable is treated as a
  boolean, string, path, list, or other data type.
- Identify any aliases, backwards-compatibility names, or similar variables that could be confused with each
  other.
- Include variables that are constructed dynamically if their final names can be inferred.
- If a variable appears in documentation but not executable code, call that out explicitly.

## Suggested Search Strategy

Use repository tools instead of relying on memory. Start with searches such as:

```bash
rg 'WIFI_WAND'
rg "ENV\\[['\"]WIFI_WAND|ENV\\.fetch\\(['\"]WIFI_WAND"
rg 'WIFI_WAND' lib exe bin spec test Rakefile rakelib tasks scripts dev docs README* *.gemspec Gemfile
```

Broaden the search if this repository uses other directories for scripts, Rake tasks, generated files, or
documentation.

## Report Structure

Write the report to a Markdown file in `dev/reports/`. Name it with today's date, HH::MM time in UTC,
the topic, and your model or agent name, for example:

```text
YYYY-MM-DD-HH-MM-wifi-wand-env-vars-codex.md
```

Use this structure:

### Executive Summary

- Include the generation date and your model or agent name.
- State how many `WIFI_WAND*` variables were found.
- Summarize the main categories of use.
- Highlight any surprising or risky findings.

### Inventory

Provide a summary table with these columns:

| Variable | Type | Scope | Files | Purpose | Default / Fallback |
|----------|------|-------|-------|---------|--------------------|

For `Scope`, use values such as `runtime`, `test`, `script`, `rake`, `documentation`, or `development`.

### Detailed Findings

For each variable, include:

- Variable name.
- Purpose and behavior.
- All referencing files.
- Whether it is user-facing or internal.
- Allowed or expected values.
- Default and fallback behavior.
- Relevant commands, Rake tasks, or code paths that depend on it.
- Any tests or documentation that cover it.

### Cross-References and Patterns

- Group related variables.
- Note repeated parsing patterns, boolean conventions, naming conventions, and inconsistencies.
- Identify places where behavior depends on combinations of variables.

### Documentation Gaps

- List variables that are used in code but missing from user-facing documentation.
- List variables documented but not used in executable code.
- Recommend where each gap should be documented or cleaned up.

### Variables That Could Be Eliminated

At the bottom of the report, add a separate section for variables you believe could be removed, merged, or
replaced for simplicity.

For each candidate, include:

- Variable name.
- Why it may be unnecessary.
- What would replace it.
- Risk or migration concern.
- Whether removal is low, medium, or high effort.

If you do not find any good elimination candidates, state that explicitly and explain why.

## Accuracy Requirements

- Cite concrete file paths for every claim.
- Do not infer behavior from names alone; verify behavior from code, scripts, tasks, or docs.
- If something is ambiguous, mark it as ambiguous and explain what would need to be checked.
- Keep the report concise enough to be useful, but complete enough that a maintainer can thoroughly understand
  each variable's use.
