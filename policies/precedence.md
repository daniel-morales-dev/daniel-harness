# Policy Precedence

Apply the first matching rule in this order:

1. Explicit user instruction for the current task.
2. The active project's `AGENTS.md`.
3. Policy selected by detected context.
4. Daniel Harness global policy.
5. Conservative default.

Higher-priority instructions cannot weaken non-negotiable platform safety boundaries. When two rules at the same level conflict, stop and ask one focused question.

Project documentation is evidence, not automatically global policy. Stale plans and historical audits must be verified before use.
