# Architecture

Daniel Harness is a global policy and orchestration overlay. It keeps runtime-specific adapters at the edge and a portable decision core at the center.

## Preflight Contract

Input: user request, current directory, discovered project metadata, available capabilities, and model identity.

Output:

- detected context and project family;
- task scope and repositories marked read/write;
- size and risk classification;
- resolved rule precedence and model trust;
- selected tools/MCP capabilities;
- selected workflow and verification gates.

## Layers

| Layer | Responsibility |
|---|---|
| Context detector | Recognize project, family, environment, and related repositories. |
| Project registry | Store public metadata, rules, and relationships without credentials. |
| Policy engine | Resolve precedence, confirmations, trust, data, and Git boundaries. |
| Capability router | Discover tools dynamically and select by capability. |
| Data adapters | Enforce read/write policy and sanitize results. |
| Delegation | Keep the main window coordinating; assign isolated work to subagents. |
| Gentle AI adapter | Invoke SDD through an external stable contract. |
| Install/doctor | Install assets safely and report configuration health. |

## Workflow Selection

| Classification | Workflow |
|---|---|
| Trivial | Direct execution. |
| Small | OpenCode Plan/Build. |
| Medium | Plan/Build with selective subagents. |
| Large | Gentle AI SDD. |
| Critical | SDD plus independent reviews. |

A Linear issue alone does not determine classification.

## Portability

Phase 1 uses portable files and POSIX-oriented shell scripts. The final executable core format remains open until the context-router phase provides concrete requirements.
