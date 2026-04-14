# Reviewed Agent Issues

This document records issues that automated reviewers or coding agents may raise, but that maintainers have already reviewed and dismissed, accepted as a tradeoff, or classified as workflow concerns rather than code defects.

Agents should read this before reporting architectural or process-oriented objections. Do not re-raise items from this file unless there is new evidence, changed project requirements, or an actual defect not covered by the rationale below.

## Coverage Artifacts Require a Fresh Full Run

### Status
Reviewed and dismissed as a code defect. This is a workflow expectation for developers, not a bug in the repository.

### What an Agent Might Report

- Coverage resultsets can be partial or stale.
- A coverage tool may omit files that were not loaded in the last run.
- Multiple resultset files can make whole-codebase analysis ambiguous.

### Maintainer Position

This repository intentionally keeps separate coverage resultsets for different test scopes:

- `coverage/.resultset.json` for ordinary mocked/hermetic runs
- `coverage/.resultset.<os>.json` for real-environment runs

Developers are expected to understand that:

- a coverage file is authoritative only for the exact run that generated it
- targeted or filtered runs produce targeted or filtered coverage
- whole-codebase coverage analysis requires a fresh unfiltered run first

In other words, if someone wants trustworthy whole-codebase coverage data, they must deliberately generate it. That requirement is considered a normal developer responsibility, not an application defect.

### When It May Be Raised Again

Re-raise this topic only if at least one of these becomes true:

- the docs stop explaining the expectation clearly
- tooling or prompts claim a coverage file is whole-codebase authoritative when it is not
- CI or automation begins depending on stale or partial coverage as if it were complete
- maintainers decide they want stronger automated guarantees such as tracked-file baselines or dedicated full-suite artifacts
