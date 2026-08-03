---
description: Analyze monolith vs microservice parity gaps for a Linear task. Read-only preview that reports gaps but does NOT mutate Linear.
agent: migration-parity-reviewer
subtask: true
argument-hint: "<linear-issue-key>"
---

# Migration Gap Analysis

Analizar gaps de paridad entre monolito y microservicio para: $ARGUMENTS

## Process

### Step 1: Read the Linear Task

Use `linear_get_issue` to read title, description, status, existing subtasks
(check `blocks` + `blockedBy` + `linear_list_issues` with parent filter).

### Step 2: Understand the Monolith Feature

Search the monolith codebase for the relevant PHP files. Use grep/glob to find
the feature's main files. Read key methods: `save()`, `update()`, `delete()`, etc.
Identify ALL distinct logical blocks: validations, pre-save, persistence, post-save,
events, rollback.

### Step 3: Understand the Microservice

Search the microservice: use case file, repository implementation, orchestrator,
validation services. Identify what's already implemented and what has TODO comments.

### Step 4: Gap Analysis

Create comparison table:

| Monolith Step | File:Line | Microservice Coverage | Status |
|---|---|---|---|

Status: ✅ Covered, 🔲 Planned subtask, ❌ Gap, ⚠️ Partial

### Step 5: Report

Return markdown summary:
1. **Comparison table**
2. **Already covered** (with references)
3. **Gaps found**
4. **Open questions**

Do NOT create subtasks. This is a read-only command.

## Notas

- Monolith and microservice paths are resolved from the current workspace context
  (`dh context`) and project registry. Do NOT hardcode paths.
- This command is read-only. It does NOT mutate Linear.
