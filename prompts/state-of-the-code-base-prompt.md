# State of the Code Base Prompt

* You are a senior software architect and code reviewer.  
* Your task is to analyze this code base thoroughly and report on its state.  
* Focus on identifying weaknesses, risks, and areas for improvement.  
* For each issue, assess its seriousness, the cost/difficulty to fix, and provide high-level strategies for addressing it.
* If you are unable to use the simplecov-mcp MCP server, use `simplecov-mcp` in CLI mode (run `simplecov-mcp -h` for help).

Write your analysis in a Markdown file whose name is:
* today's date in YYYY-MM-DD format +
* '-state-of-the-code-base-' + 
* your name (e.g. 'codex, claude, gemini, zai)

The file should have the following structure:

---

### Executive Summary
- Provide a concise overview of the overall health of the code base.
- Identify the strongest areas and the weakest areas.
- Give a **one-line summary verdict** (e.g., *“Overall: Fair, with major risks in testing and infrastructure maintainability”*).
- **Overall Weighted Score (1–10):** Show the score at the end of this summary.

---

### Critical Blockers
List issues so severe that they must be resolved before meaningful progress can continue. For each blocker, include:
- **Description**
- **Impact**
- **Urgency**
- **Estimated Cost-to-Fix** (High/Medium/Low)

---

### Architecture & Design
- Summarize the overall architecture (monolith, microservices, layered, etc.).
- Identify strengths and weaknesses.
- Highlight areas where complexity, coupling, or technical debt are high.
- Assess maintainability, scalability, and clarity.
- **Score (1–10)**

---

### Code Quality
- Identify recurring issues (duplication, inconsistent style, long methods, deeply nested logic, etc.).
- Point out readability and maintainability concerns.
- **Score (1–10)**

---

### Infrastructure Code
- Evaluate Dockerfiles, CI/CD pipelines, and Infrastructure-as-Code (Terraform, Ansible, etc.).
- Highlight brittle or outdated configurations.
- Identify risks in automation, deployment, or scaling.
- **Score (1–10)**

---

### Dependencies & External Integrations
- List major dependencies (frameworks, libraries, services).
- Note outdated or risky dependencies and upgrade costs.
- Assess vendor lock-in and integration fragility.
- **Score (1–10)**

---

### Test Coverage
- Using the **simplecov-mcp MCP server**, analyze the test coverage:
    - Include a summary table of coverage by file/module.
    - Report coverage at a high and general level.
    - Rank risks of lacking coverage in **descending order of magnitude**.
- Highlight untested critical paths and potential consequences.
- **Score (1–10)**

---

### Security & Reliability
- Identify insecure coding practices, hardcoded secrets, or missing validations.
- Assess error handling, fault tolerance, and resilience.
- **Score (1–10)**

---

### Documentation & Onboarding
- Evaluate inline docs, README quality, and onboarding flow.
- Identify missing/outdated documentation.
- **Score (1–10)**

---

### Performance & Efficiency
- Highlight bottlenecks or inefficient patterns.
- Suggest whether optimizations are low-cost or high-cost.
- **Score (1–10)**

---

### Formatting & Style Conformance
- Report **bad or erroneous formatting** (inconsistent whitespace, broken Markdown).
- Note whether style is consistent enough for maintainability.
- **Score (1–10)**

---

### Best Practices & Conciseness
- Assess whether the code follows recognized best practices (naming, modularization, separation of concerns).
- Evaluate verbosity vs. clarity — is the code concise without being cryptic?
- **Score (1–10)**

---

### Prioritized Issue List
Provide a table of the top issues found, with the following columns:

| Issue | Severity | Cost-to-Fix | Impact if Unaddressed |
|-------|----------|-------------|------------------------|
| Example issue description | High | Medium | Major reliability risks |

The order should take both severity and cost-to-fix into account such that performing them in descending order would
result in the optimal value addition velocity.

---

### High-Level Recommendations
- Suggest general strategies for improvement (e.g., refactoring approach, improving test coverage, upgrading dependencies, modularization).
- Highlight where incremental vs. large-scale changes are most appropriate.

---

### Overall State of the Code Base
- Display the **weights used** for each dimension (decided by you, the AI).
- Show the **weights table** and the weighted score calculation.

### Suggested Prompts
Suggest prompts to a coding AI tool that would be helpful in addressing the major tasks.

#### Example Weights Table (AI decides actual values)
| Dimension                | Weight (%) |
|---------------------------|------------|
| Architecture & Design     | ?%         |
| Code Quality              | ?%         |
| Infrastructure Code       | ?%         |
| Dependencies              | ?%         |
| Test Coverage             | ?%         |
| Security & Reliability    | ?%         |
| Documentation             | ?%         |
| Performance & Efficiency  | ?%         |
| Formatting & Style        | ?%         |
| Best Practices & Conciseness | ?%      |

- **Weighted Score Calculation:** Multiply each section’s score by its chosen weight, then sum to compute the **Overall Weighted Score (1–10)**.
- Report the final **Overall Weighted Score** with justification.  

### Summarize suggested changes
