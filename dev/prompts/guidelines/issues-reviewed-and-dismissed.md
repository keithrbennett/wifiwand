# Issues Reviewed And Dismissed

## Coverage artifacts can be stale or partial

1) Do not report coverage reliability as a code issue just because SimpleCov output only reflects files touched by the last run, some files are missing from the current resultset, or `cov-loupe` reports stale entries.

This repository keeps separate coverage resultsets for default and real-environment runs, and coverage data is only trustworthy for the exact test scope that generated it. If someone wants to rely on coverage data for prioritization or planning, it is the developer's responsibility to run a fresh full test suite first.

Raise this again only if docs or tooling start treating partial coverage as whole-repo authoritative, or if CI depends on stale coverage as if it were complete.
