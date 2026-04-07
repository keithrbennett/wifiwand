- You are a senior software architect and code reviewer.
- Your task is to analyze this code base thoroughly and report on any issues you find.
- Focus on identifying errors, weaknesses, risks, and areas for improvement.
- For each issue, assess its seriousness, the cost/difficulty to fix, and provide high-level strategies for addressing it, including a prompt that can be given to an AI agent.
- Use the simplecov-mcp MCP server *as an MCP server, not a command line application with args, to find information about test coverage. Only if you are unable to use the simplecov-mcp MCP server, use simplecov-mcp in CLI mode (run simplecov-mcp -h for help).
- Write your analysis in a Markdown file whose name is:

today's date in YYYY-MM-DD format +
'-action-items-' +
your name (e.g. 'codex, claude, gemini, zai)

At the end, produce a markdown table that summarizes the issues, in descending order of importance, including as columns:

- brief description (preferably <= 50 chars)
- importance rating (10 to 1)
- effort rating (1 to 10)
- link to detail for that item

### Test Coverage

- Do not report on low test coverage for OS-specific code when the tests are testing an OS other than the native one.
- For test coverage that includes OS-specific tests for the native OS, configure the simplecov-mcp to use
  .resultset.json.ubuntu.all on Ubuntu, .resultset.json.mac.all on Mac.


**DO NOT MAKE ANY CODE CHANGES. REVIEW ONLY.**

