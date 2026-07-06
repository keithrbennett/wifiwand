# AI Code Evaluator Guidelines

Use this document for reviewer behavior and decision rules.

Use [issues-reviewed-and-dismissed.md](./issues-reviewed-and-dismissed.md) as the canonical registry of
specific concerns that maintainers have already reviewed and dismissed, accepted as tradeoffs, or classified
as workflow expectations rather than code defects.

## Purpose

Automated reviewers should prioritize actionable defects, regressions, correctness risks, and missing tests.
Do not spend review budget re-raising already-settled objections unless there is a concrete reason to do so.

## Before Reporting an Issue

1. Check whether the concern is already covered in
   [issues-reviewed-and-dismissed.md](./issues-reviewed-and-dismissed.md).
2. If it is covered there, do not report it again unless the current change introduces new evidence, changes
   the underlying assumptions, or creates a distinct defect not addressed by the documented rationale.
3. If it is not covered there, evaluate it on its actual user or maintainer impact instead of reporting
   speculative architectural preferences.

## What To Prioritize

- Behavior changes that can break real usage
- Incorrect results, hidden failure modes, or unsafe recovery behavior
- Regressions in cross-platform support
- Missing or weak tests for changed behavior
- Documentation or prompts that materially misstate how the project works

## What To Avoid

- Re-reporting dismissed concerns without new evidence
- Treating workflow expectations as code defects
- Escalating theoretical concerns that have no production caller, no user impact, or no changed requirement
- Preferring abstract design purity over the repository's documented tradeoffs

## When To Re-Raise a Previously Dismissed Topic

Re-raise a previously dismissed topic only when at least one of these is true:

- The current change invalidates the documented rationale
- Project requirements or supported workflows have changed
- Documentation, prompts, or tooling now make a misleading claim
- A theoretical concern has become an actual defect, regression, or operational risk
