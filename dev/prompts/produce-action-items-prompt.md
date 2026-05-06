- You are a senior software architect and code reviewer.
- Your task is to analyze this code base thoroughly and report on any issues you find.
- Focus on identifying errors, weaknesses, risks, and areas for improvement.
- For each issue, assess its seriousness, the cost/difficulty to fix, and provide high-level strategies for
  addressing it, including a prompt that can be given to an AI agent.
- Use the cov-loupe MCP server to find information about test coverage. Prefer MCP tools such as
  `file_coverage_summary`, `file_uncovered_lines`, and `project_coverage` over reading SimpleCov resultsets
  directly or reasoning from scratch. Only if the MCP server is unavailable, use the `cov-loupe` CLI.
- Write your analysis in a Markdown file whose name is:

today's date in YYYY-MM-DD format +
'-action-items-' +
your name (e.g. 'codex, claude, gemini, zai)

At the end, produce a markdown table that summarizes the issues, in descending order of importance, including
as columns:

- brief description (preferably <= 50 chars)
- importance rating (10 to 1)
- effort rating (1 to 10)
- link to detail for that item

### Test Coverage

- Do not report on low test coverage for OS-specific code when the tests are testing an OS other than the
  native one.
- For test coverage that includes OS-specific tests for the native OS, use the current resultset produced by
  the test run. The default run writes `coverage/.resultset.json`; real-environment runs write
  `coverage/.resultset.<os>.json`.


**DO NOT MAKE ANY CODE CHANGES. REVIEW ONLY.**
