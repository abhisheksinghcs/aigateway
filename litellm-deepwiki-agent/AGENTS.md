# Project Constitution

These rules govern every human- or AI-authored change in this project. A
change is not complete until it satisfies this constitution.

## Code Explainability Is Required

The source code must teach a reader how the agent works without requiring
them to study the external documentation first.

For every Python change:

1. **Every file must have a module docstring** that explains its purpose, its
   place in the request flow, and any security boundary it owns.
2. **Every class and protocol must have a docstring** that explains its
   responsibility, important collaborators, and lifecycle or trust assumptions.
3. **Every function and method must have a docstring** that explains why it
   exists, its inputs, its return value, expected errors, and credential
   handling where relevant. This includes test helpers and test functions.
4. **Multi-stage and security-sensitive logic must have short inline stage
   comments** so a customer can follow the flow in the source file. Explain
   intent and rationale, not obvious Python syntax.
5. **Annotations must stay synchronized with behavior.** Update comments and
   docstrings in the same change whenever code behavior or trust boundaries
   change.
6. **Never use comments as a substitute for clear names and structure.** The
   implementation must remain typed, testable, and straightforward.

Before declaring a task complete, inspect every Python file added or changed
and confirm that its file, classes, functions, and non-obvious security stages
are explained at the appropriate level.

## Security Boundaries

- Never log or return the delegated user token, LiteLLM virtual key, or any
  middleware credential.
- The caller may provide only question text. The LiteLLM URL, MCP tool,
  DeepWiki repository, and virtual key must remain deployment- or code-fixed.
- The middleware OBO client secret belongs only to the AKS middleware and must
  never be added to this hosted-agent project.
- Configuration and upstream failures must fail closed with credential-safe
  errors.

## Validation

Run the smallest relevant unit tests, Ruff lint and formatting checks, Python
compilation, and type analysis before considering a code change complete.

# Coding Agent Instructions

This project is a **Microsoft Foundry hosted agent** — a containerized AI agent that runs in [Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents). The platform handles containerization, hosting, security, scaling, and observability so you can focus on agent logic.

## Key files

- `Dockerfile` — container definition

## Development workflow

The **Azure Developer CLI (`azd`)** manages the full lifecycle:

```bash
azd ai agent run                           # Run locally on http://localhost:8088
azd ai agent invoke --local "your message" # Test the local agent
azd deploy                                 # Deploy to Foundry
azd ai agent invoke "your message"         # Invoke the deployed agent
```

## Microsoft Foundry Skill

Install the **Microsoft Foundry Skill** for guided deployment, evaluation, and troubleshooting workflows.

Direct install (preferred, works with any coding agent):

```bash
npx skills add https://github.com/microsoft/azure-skills --skill microsoft-foundry
```

Or install the Azure Skills Plugin:

- **Copilot CLI**: `/plugin marketplace add microsoft/azure-skills` then `/plugin install azure@azure-skills`
- **Claude Code**: `/plugin install azure@claude-plugins-official`

Then ask naturally, e.g. `Use the Microsoft Foundry Skill to deploy this agent.`

## References

- [Hosted agents overview](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents)
- [Microsoft Foundry Skill](https://learn.microsoft.com/en-us/azure/foundry/how-to/develop/use-microsoft-foundry-skill)