---
description: Analyze monolith vs microservice gaps for a Linear task, create subtasks with detailed descriptions and estimations
allowed-tools:
  Read: true
  Write: false
  Edit: false
  Bash: true
argument-hint: "<linear-issue-key> [--assignee email] [--estimate points]"
---

# Migration Gap Analysis

Analizar gaps entre monolito y microservicio para: $ARGUMENTS

## Process

Follow these steps IN ORDER. Do NOT skip any step.

### Step 1: Parse Arguments

Parse `$ARGUMENTS`:
- First token = Linear issue key (required, e.g. ACEXPEN-392)
- `--assignee` = email for subtask assignment (optional, default: current user)
- `--estimate` = default points for subtasks (optional, default: 8)

Report what was parsed before proceeding.

### Step 2: Read the Linear Task

Use `linear_get_issue` with the issue key to understand:
- Title and description
- Current status
- Existing subtasks (check `blocks` + `blockedBy` relations, and also search for children via `linear_list_issues` with the parent filter using the project and state)
- Attachments (PR links etc.)

Read each existing subtask's description to understand what's already covered.

### Step 3: Understand the Monolith Feature

Search the monolith codebase at `/home/dmorales/Documents/Alegra/alegra-app/` for the relevant PHP files:
- Use `grep` and `glob` to find the feature's main files
- Read the key methods (look for `save()`, `update()`, `delete()`, etc.)
- Identify ALL distinct logical blocks: validations, pre-save, persistence, post-save, events, rollback

### Step 4: Understand the Microservice

Search the microservice at `/home/dmorales/Documents/Alegra/bills-migration/api-alegra-bills-backend/`:
- Read the use case file (e.g. `*CreateUseCase.ts`, `*UpdateUseCase.ts`)
- Read the repository implementation (e.g. `DynamoDB*Repository.ts`)
- Read any orchestrator files (e.g. `*Orchestrator.ts`)
- Read any validation services
- Identify what's already implemented and what has TODO comments

### Step 5: Gap Analysis

Create a comparison table matching each monolith block to microservice coverage:

| Monolith Step | File:Line | Microservice Coverage | Status |
|---|---|---|---|

Status values:
- ✅ **Covered** — clearly implemented
- 🔲 **Covered by subtask** — has an existing Linear subtask (mention which)
- ❌ **Gap** — not implemented, no subtask
- ⚠️ **Partial** — partially implemented

### Step 6: Create Subtasks

For each ❌ **Gap**:
1. Create a subtask under the parent Linear issue using `linear_save_issue`
2. Title must be clear in Spanish with the gap code if applicable (e.g. `[postSave] ...`)
3. Description must include:
   - **Contexto**: What the monolith does (with file:line references)
   - **Código de referencia**: Code snippets from the monolith
   - **Objetivo**: What needs to be implemented
   - **Consideraciones de arquitectura**: Architectural decisions, dependencies
   - **Criterios de aceptación**: Numbered checklist
   - **Archivos relevantes**: Both monolith and microservice file paths
   - **Relaciones**: Dependencies on other subtasks
4. Assign to the specified user
5. Set estimate (default: 8 points, use judgment: 1-3 small, 5 medium, 8 large, 13 xlarge)
6. Set priority: 1=Urgent, 2=High, 3=Medium, 4=Low (default: 2)
7. Add labels: `["New Feature", "XL"]` (use `S`, `M`, `L`, `XL` based on estimate)

For each ⚠️ **Partial**:
- Create a subtask only if the uncovered part is significant enough
- Document what's missing explicitly

For each 🔲 **Covered by subtask**:
- Do NOT create a new subtask
- Mention the existing subtask in the summary

### Step 7: Summary Report

Return a markdown summary with:
1. **Subtasks created**: List with IDs, titles, estimates
2. **Already covered**: List with references
3. **Comparison table**: Full gap analysis table
4. **Open questions**: Any ambiguities found

## Configuration

- The monolith root is resolved from the current workspace.
- The microservice path should be provided via Linear task description or attachment.
- Default assignee is the current authenticated Linear user.
