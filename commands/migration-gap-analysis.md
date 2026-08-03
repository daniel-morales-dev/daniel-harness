---
description: Analyze monolith vs microservice parity gaps for a Linear task. Preview only; use --apply to create subtasks with confirmation.
agent: migration-parity-reviewer
subtask: true
argument-hint: "<linear-issue-key> [--apply]"
---

# Migration Gap Analysis

Analizar gaps de paridad entre monolito y microservicio para: $ARGUMENTS

## Process

### Step 1: Parse Arguments

- First token = Linear issue key (required, e.g. ACEXPEN-392)
- `--apply` = create subtasks after preview (requires confirmation)

### Step 2: Read the Linear Task

Use `linear_get_issue` to read title, description, status, existing subtasks
(check `blocks` + `blockedBy` + `linear_list_issues` with parent filter).

### Step 3: Understand the Monolith Feature

Search the monolith codebase for the relevant PHP files. Use grep/glob to find
the feature's main files. Read key methods: `save()`, `update()`, `delete()`, etc.
Identify ALL distinct logical blocks: validations, pre-save, persistence, post-save,
events, rollback.

### Step 4: Understand the Microservice

Search the microservice: use case file, repository implementation, orchestrator,
validation services. Identify what's already implemented and what has TODO comments.

### Step 5: Gap Analysis

Create comparison table:

| Monolith Step | File:Line | Microservice Coverage | Status |
|---|---|---|---|

Status: ✅ Covered, 🔲 Covered by subtask (mention which), ❌ Gap, ⚠️ Partial

### Step 6: Report (preview mode — default)

Return markdown summary:
1. **Comparison table**
2. **Already covered** (with references)
3. **Gaps found**
4. **Open questions**

Do NOT create subtasks in preview mode.

### Step 7: Apply (--apply mode)

Only if `--apply` flag was provided AND user confirms:

For each ❌ Gap:
1. Show the proposed subtask (title, description, estimate)
2. Wait for user confirmation
3. Only create subtasks that were explicitly approved

Use `linear_save_issue` with `parentId` to create subtasks. Set labels, priority,
and estimate per user input.

## Notas

- Monolith and microservice paths are resolved from the current workspace context
  (`dh context`) and project registry. Do NOT hardcode paths.
- Default assignee: current authenticated Linear user.
- This command analyzes and reports. Mutations (subtask creation) only happen
  with `--apply` + user confirmation.
