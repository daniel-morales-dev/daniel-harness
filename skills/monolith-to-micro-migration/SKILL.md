---
name: monolith-to-micro-migration
description: >-
  Migrate fragments of alegra-app (PHP) to api-alegra-bills-backend (TypeScript).
  Activate only when: user pastes PHP code, mentions Bill.php, any .php file,
  bills-migration, or requests monolith↔micro parity in this repo.
  DO NOT activate for pure TS refactors or performance.
---

# Monolith → micro migration (bills backend)

Use this skill when you need to **translate monolith behavior** into the microservice code **without copying whole files**: only the agreed fragment.

## Mandatory link with `/senior-engineer` and quality with `/code-reviewer`

- This skill **does not replace** the user's **main / senior-engineer** protocol (invokable as **`/senior-engineer`** or `senior-engineer` subagent in Cursor): it **complements** it.
- The goal is **not** to mimic the monolith **100%** in structure, names, or bad practices. The PHP fragment is the **source of truth for business rules and observable contract** (API, amounts, branches, order), not an architecture textbook. Smells like `N+1`, anemic models, endless `if`s, or logic mixed with transport in the monolith are **not** reasons to replicate them in the micro: **improve** with DRY, layer boundaries, performance (avoid queries in loops, batching, request-scoped cache where applicable), and repo rules.
- After or alongside implementation, apply **`/code-reviewer`** criteria: security, complexity, DRY, regression risk, and **verdict** (approve / changes / block). If acceptance criteria demand strict parity with an ugly monolith detail, **document the trade-off** in **PR**, **Linear**, or a **short note to the user in the delivery** (not a long narrative in source code) instead of "silently improving" and breaking the agreement.
- **Suggested application order:** (1) **senior-engineer** — scoped plan, minimal changes, verification, trade-offs; (2) rules from **this skill** — **behavior** parity and contract, no invented fallbacks, honest TODOs; (3) **code-reviewer** — quality, checklist, verdict.
- If the user only types **`/senior-engineer`** for a migration, the agent should still **activate** `monolith-to-micro-migration` when the task is monolith→micro (or when the user pastes a PHP fragment / mentions `alegra-app`).
- If the user says **`/senior-engineer` + migration** (or "migrate this block from Bill.php"), apply **both** layers without contradiction: parity of **business rules and output**; **internal design** better than PHP where it does not break the contract.

## Agent role

Act as a **principal engineer** (aligned with `/senior-engineer`): autonomous, minimal changes, mandatory tests if the repo requires them for the touched area. **Linear:** see §7b — if there is a linked issue and the work is done, closing comment + Done state via MCP; if the user asks not to update Linear, skip.

## Inputs (adaptive)

What the user may provide (all optional except the goal):

| Input               | Use                                                                            |
| ------------------- | ------------------------------------------------------------------------------ |
| **Goal**            | What the TS equivalent must do (one sentence).                                 |
| **Source fragment** | PHP, legacy TS, or diff; delimit lines or file.                                |
| **Linear task**     | ID (e.g. `ACEXPEN-1876`): acceptance criteria and scope; link TODOs to the ID. |
| **Target file**     | If already clear; otherwise the agent proposes it after inspecting the repo.   |

If technical context is missing, **infer from code** (semantic search, grep, reading file neighbors). **Do not** invent behavior not supported by the monolith fragment or consulted PHP code.

## No fallbacks or assumptions (mandatory)

- **Do not add fallbacks** (`?? value`, `|| defaultValue`, "just in case" branches) if **equivalents do not exist** in the monolith for that case. Parity is with the reference PHP, not with agent heuristics.
- **Do not assume** what should happen when a branch is missing from the fragment: expand the fragment by reading the full method in `alegra-app`, or **state explicitly** that information is missing.
- If after inspecting monolith and micro **doubt remains** (ambiguity, opaque call, data not available in the micro): **ask the user** with **file and line** (PHP or TS) of what blocks you; do not silence uncertainty with invented code.
- If a PHP helper is unknown or the TS equivalent **does not exist or is not findable**: **do not fake** the logic; leave `// TODO: <optional ISSUE-ID> — what is missing` and, in the user response, the same gap described for a follow-up.
- The only acceptable "default values" are those the **monolith already encodes** (e.g. read order in `general.json`, explicit feature flag in PHP). Everything else goes to TODO, injected option, or a question.

## Mandatory flow (fixed order)

### 1. Scope the work

- From the fragment, extract which **business rules** belong to the **Bill / billing** domain in the micro vs **side effects** (inventory, other services, writes outside the aggregate).
- What **does not belong** to the micro domain: **do not migrate**; leave `// TODO: <ISSUE-ID> — short description` and note in Linear if the user requests it.

### 2. Monolith ↔ micro map

- Find in the TS backend the **insertion point** (application service, assembler, domain, DTO).
- Compare **method names and data** from the PHP model with TS entities (`Bill`, `BillCategory`, `BillTax`, etc.).
- Identify **feature flags**, **metadata**, **country / applicationVersion**, and existing constants (`FEATURE_TOGGLES`, `APPLICATION_VERSIONS`, `GENERAL_CALCULATION_SCALE`, etc.).

### 3. Migration design

- **Single path** when the monolith branches (avoid duplicate branches): extract helpers with business-meaningful names.
- **No magic strings**: dedicated constants file — for catalog keys / enums aligned to monolith (`retentionReferences.key`, tax references, etc.) use `shared/constants/` (`retentionReferenceKeys.ts`, `taxReferenceKey.ts`, …) with `as const` and named exports; do not repeat literals like `"ISR"`, `"IVA"` in helpers. Business rules may live in `domain/helpers/`, but **fixed string values** from the PHP/DB contract live in `shared/constants`.
- **Cognitive complexity** (ESLint): max **10** per function; if exceeded, split into pure functions with clear names.
- **Avoid** nested ternaries and deep `if`s: early return, helpers, policy object.
- **Typing**: public/API contracts and ports use explicit interfaces; avoid `unknown` except at a real untyped boundary. For logic centered on **`Bill`**, type the aggregate as **`Bill`** in domain services; use **`import type { Bill }`** only to avoid a runtime import cycle with `Bill.ts`. Do not invent parallel "minimal surface" interfaces just to avoid importing the entity. Auxiliary types/interfaces for the service go in **separate files**, not next to the main class.
- **Readable conditionals**: do not chain ternaries or long `&&` to normalize IDs, dates, or flags; extract **named helpers** and reuse (DRY). **Location (DDD / Clean):** rules or normalizations specific to the Bill aggregate go under `contexts/billing/bills/domain/helpers/` (or another agreed domain subfolder, e.g. `value-objects/`), not at the root of `domain/`; e.g. `domain/helpers/finiteLedgerCategoryId.util.ts`. Reserve `shared/util` for truly cross-cutting utilities (dates, money, retries). The `shared/database` layer may import helpers from **that** domain when the repository materializes columns that feed context entities (pattern already used with domain types from shared repos). If the same validation appears in repository and entity, **one helper**, not two copies with different shapes.
- **File names (new code):** team convention — **no hyphens** in the base name; use **camelCase** + suffix when applicable (e.g. `finiteLedgerCategoryId.util.ts`, not `finite-ledger-category-id.util.ts`). Legacy `kebab-case` files are not renamed by this rule unless another refactor touches them.
- **Method names and size**: avoid identifiers **longer than ~50–60 characters** that describe an entire process; if you need such a long name, the method likely **mixes steps** (load, transform, merge DTO). **Split** into shorter methods (`loadX`, `mergeY`, `applyZ`) instead of one inflated name.

#### MySQL repositories in `shared/database/repositories`

- In **this microservice** the monolith MySQL connection is **read-only** (`SELECT`). Operations that in PHP perform `UPDATE`/`INSERT`/`DELETE` must **not** run silently in the repository: leave **`// TODO: <ISSUE>`** (Spanish) with an alternative (monolith API, queue, another service with DB permissions, or policy change) and a linked Linear task.
- The **repository class file** must be limited to **SQL queries**, parameter binding, minimal validation (e.g. numeric ids), error logging, and **delegating** the result to a mapper. **Do not** mix there: driver row interfaces, JSON/`metadata` parsing, date normalization, or building the output DTO.
- That row → record/DTO transformation lives in **`shared/database/mappers/`** in a dedicated module (convention `*.mapper.ts`, exported function like `mapXxxMysqlRowToRecord`).
- **Interfaces** (raw MySQL row, record/DTO, repository port) go in **`shared/database/repositories/interfaces/`** as **`*.interface.ts`**. **Do not** declare contract interfaces in the same file as `XxxRepository.ts`.

##### Repository scope and table ownership (mandatory)

- **One concern per repository.** SQL that targets tables **outside** the primary aggregate of a repository must **not** live on that repository class.
  - Example: reads from **`metadataAdmin_companies`** joined with **`metadataAdmin`** belong in a dedicated **`MetadataAdminCompanyRepository`** (port `IMetadataAdminCompanyRepository`), not on **`CompanyRepository`**.
  - Example: reads from the **certificate** table (e.g. latest expiration for a company) belong in **`CertificateRepository`** (port `ICertificateRepository`), not on **`CompanyRepository`**.
- **Inject the right port** where the use case or validator needs that data (e.g. `CompanyStampValidator` depends on `(metadataAdminCompanyRepository, certificateRepository, …)`, not on `CompanyRepository` for those reads).
- **Rationale:** keeps boundaries clear, avoids a "god" company repo, and matches Clean Architecture: aggregate/root naming reflects **what table or bounded read** the class owns.

##### MySQL read errors vs "no row" (mandatory)

- **Empty query result** → return **`null`** (or an agreed empty shape) from the repository method. That is normal business state.
- **Driver / connection / SQL failure** (exception from `mysqlConnection.query`) → **`logger.error`** with structured context (`idCompany`, query intent, `error` message/stack) and **rethrow** the error (or wrap in a domain error if the project standard says so). **Do not** catch, log **`warn`**, and return **`null`** as if the row were missing — that hides outages and differs from patterns like `findByUuid` that surface failures.
- **Tests:** mock `query` to reject → expect the method to **throw**; mock `query` to resolve `[]` → expect **`null`**.

#### Clean code in migrations (DRY, KISS, YAGNI)

- **Comments in code**: prefer **clear helper/function names** plus **tests** that cover parity with PHP. **Do not** add JSDoc blocks that list monolith file/line equivalence (`Bill.php` ~NNN), long PHP↔TS matrices, or narration that duplicates readable code. **Do not** add module JSDoc above `shared/constants/` entries that only cite MySQL tables/columns, `Model_*`, or "aligned with …" — traceability belongs in **PR**, **Linear**, and **tests** (same line as **`code-standards.mdc`** _Comments and TODOs_). In-repo comments only when the code **cannot** make it obvious: `// TODO: <ISSUE-ID> — …`, **security/legal invariants**, or one line for a team-agreed hack. **Language:** follow project **`code-standards.mdc`** and team convention for TODO/comment language (this repo often uses Spanish for `// TODO` in migration work).
- **Readable names**: do not use opaque single-letter variables for domain values (`d`, `x`, `n` as "date" or "number" without context). Prefer names that say what they hold (`sourceDate`, `billDate`, `normalizedAmount`). Acceptable exceptions: short indices in very local loops or standard signatures (`i`, `k` in a one-line `map`/`reduce`) when scope is minimal.
- **`YYYY-MM-DD` from `Date`**: do not scatter `date.toISOString().split("T")[0]`; use **`toIsoDateStringUtc`** from `shared/util/date-format.util` (re-exported from `shared`) for one convention and less drift.
- **DRY**: if two micro files repeat the same numeric or tax/journal logic (e.g. item vs category), extract **one shared module** (helpers or `*Shared.ts`) in the application/domain layer that applies; do not duplicate IEPS `sort`, amount resolution, IVA/IEPS adjustment, merge into subtotals, etc.
- **KISS**: prefer small pure functions and one readable flow before new "just in case" hierarchies or layers.
- **Early returns in migrated logic**: when porting PHP branches, prefer **guards and early `return`** over accumulating a result in a mutable variable (`let subType` + many `if`s). Same observable semantics, less intermediate state and depth; aligns with §3 (_early return, helpers_). If a simplification removes intermediates but might differ from a PHP detail, validate against the source fragment or document the trade-off in PR/Linear.
- **YAGNI**: do not introduce generic abstractions beyond what is needed for **parity with the agreed PHP fragment**; if the monolith does not use a case, do not code it for completeness.
- **Parameters**: if a function exceeds **3 positional parameters**, refactor to a **typed arguments object** (`FooParams`, `AppendXArgs`, etc.) or group related context; improves readability and PR review.

### 4. Implementation

- Touch **only** files needed for the agreed fragment (no drive-by refactors).
- Keep **style** of the target file (imports, naming, Clean/DDD layers of the repo).
- Parity **by observable behavior** (amounts, branches, order, agreed API shape), **not** line-by-line style parity with the monolith. Improve structure and names and avoid PHP smells **while** keeping the contract; if a "quality fix" changes an amount or an output field, you need **explicit agreement** or an **issue**.
- Apply **No fallbacks or assumptions**: any behavior not present in the reference monolith is **out of scope** until TODO or clarification.

### 4b. Environment variables (`.env`) — mandatory checklist

If the work **adds** a new variable to `process.env`, **documents** a dependency in code that reads it directly, or **requires** it at runtime/CI for `getEnvironment()`:

| Step  | File                           | Action                                                                                                                                                                              |
| ----- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1** | `lib/interfaces/index.ts`      | Declare the key on **`ILambdaEnv`** (`?:` only if contract and `getEnvironment()` allow absence without breaking startup).                                                          |
| **2** | `lib/utils/index.ts`           | In **`getEnvironment()`**, read `process.env.<NAME>`, validate (e.g. `throw` if mandatory), include it in the returned object.                                                      |
| **3** | `.github/workflows/deploy.yml` | In the job that writes `.env` (`echo "…=…" >> .env`), add the same variable (typical: `echo "<NAME>=${{ secrets.<NAME> }}" >> .env`). Configure the **secret** in GitHub if needed. |
| **4** | `.github/workflows/test.yml`   | **Same line** as deploy so tests and CI get the value (deploy ↔ test parity).                                                                                                      |

Without these four steps, local may work with a manual `.env` but **deploy or CI fail** or miss the variable. Update **`docs/infrastructure-config.md`** if the repo documents env there (see **`AGENTS.md`**).

### 5. Inevitable gaps

- Configuration that only exists in the monolith (`general.json`, country rules): **inject via options/DTO/metadata** or TODO with issue id.
- Paths **Mexico rounding / roundTotals / deferred entries**: if full parity is another ticket, **placeholder + TODO** with reference `ACEXPEN-xxxx` or the current task.

### 6. Verification

- **Prerequisite:** Read `.cursor/rules/testing-philosophy.mdc` before writing tests.
- Unit tests in the touched area (existing project pattern).
- Run **`npm test`** (or the repo standard) on **tests relevant to the change** until green — not only the edited file: include **direct consumers** (e.g. if you changed `assemblePrivateBillJournal` or journal lines, also run `PrivateApiJournalBuilder`, `BillToApiArrayPrivate`, etc. per imports in the repo).
- Run **`npm run lint`** when closing the change (repo ESLint).
- Run **`npm run type-check`** (`tsc --noEmit`): **ESLint does not replace TypeScript** — errors like `Property '…' does not exist on type 'PrivateBillResponse'` (TS2339) or `numberTemplate` vs `BillPublicNumberTemplate` only show up here. Fix by **aligning the DTO** (`PrivateBillResponse`, `PrivateBillApiContracts`) with what the monolith exposes for that country, or using the private type (`PrivateBillNumberTemplate`) instead of forcing the public shape — without `as any` or unnecessary complexity.
- If the linter fails (**complexity**, **max-depth**): refactor as in §3.

#### If a test fails after the change

Diagnose before blind fixes:

| Likely cause                         | What to check                                                                                                                                                 |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Implementation / monolith parity** | New behavior does not match expected amounts, branches, or order per reference PHP; fix code.                                                                 |
| **Stricter domain contract**         | Mocks missing methods (`getIdCostCenter`, `getTaxesArray`, `getCostCenterId`, country flags…); production calls them — update **test stubs**, not production. |
| **`try/catch` hiding errors**        | If `build()` returns `null`, check whether an exception occurred earlier (incomplete mocks); in tests prefer complete mocks over assuming `null` is valid.    |

Goal: separate **real regression** vs **outdated test** relative to the current `Bill` / journal contract.

### 6b. Mandatory post-feature closure (repo + Cursor)

After implementation is ready, **do not close** the task without what **`.cursor/rules/agent-workflow-and-caveman.mdc`** defines:

1. **`/test-engineer`** + **generate-tests** Cursor flow: broad suite, edge cases, green for touched code. **Prerequisite:** read `.cursor/rules/testing-philosophy.mdc`.
2. **`/senior-engineer`**: final pass (trade-offs, suggested commit).
3. **`/code-reviewer`**: review as **tech lead / PR** (skill format: severities, verdict).

Also: user responses in **`/caveman`** by default (same rule). Migration without this closure = incomplete.

### 7. Delivery to the user

- **Numbered list of files** changed and **what each change does**.
- **Risks** and **by country/flag** where behavior might differ from the monolith narrative.
- **Decisions** (one sentence each): why this extraction, why this injectable policy.
- **Commit message (output text only, do not run git):** at the end, include **one line** ready to copy/paste that satisfies **Conventional Commits** and repo **commitlint** (`type(scope): description`). **Types** stay in English (`feat`, `fix`, `refactor`, `test`, `docs`, `chore`, …); **scope** can be short (`bills`, `cursor`, …) per area; the **description after the colon** should be **in Spanish**, imperative or clear noun phrase (team convention). Full header line ≤ **120 characters**. **Forbidden:** run `git commit`, hooks, or change git state; only an explicit suggestion for the user.

### 7b. Linear closure (when an issue is linked)

If the migration is tied to a **Linear issue** (ID in the user message, task scope, or explicit TODOs `ACEXPEN-xxxx`) and work is **done and verified** (tests/linter green for scope):

1. **Closing comment** on the issue (Linear MCP `save_comment`): short Spanish summary — what was implemented, main files, trade-offs or known gaps (TODO + id if any). Do not dump the whole chat.
2. **Done state** (`save_issue` with `state: Done` or the team's completed state name), unless the user said **not** to update Linear.

If there is no issue or the user asked not to touch Linear, skip (do not invent ids).

## Combined checklist `/senior-engineer` + this skill + `/code-reviewer`

Keep **visible** the senior-engineer frame, monolith rules, and quality review in every migration response:

| Layer                             | What it covers                                                                                                                                                                                                                                                                                                                                                                                              |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`/senior-engineer`**            | Plan → touched files and why → minimal implementation → tests/commands run → trade-offs and risks → **suggested commit message in Spanish** (Conv. Commits, ≤120 chars), without running git.                                                                                                                                                                                                               |
| **`monolith-to-micro-migration`** | PHP↔TS map by **behavior/contract**, no non-monolith fallbacks, Bill domain boundaries, TODO with issue, question with **file:line** if doubt remains; DRY/KISS/YAGNI and max 3 params (typed objects); **§7b** comment + Done on Linear if issue; dedicated repos for metadata-admin / certificate reads; **error + rethrow** on DB failures; same commit message rule at close (description in Spanish). |
| **`/code-reviewer`**              | Whether the migration introduces smells (complexity, N+1, layer leaks), whether it improves on PHP without breaking contract, and **verdict** per the skill (severities).                                                                                                                                                                                                                                   |

- Do not improvise scope or **fallbacks**: if ambiguity remains after searching the code, **ask** with **file:line**; if waiting is not possible, **TODO** in code describing the gap.
- **Better design yes, surprise no:** if the micro does something cleaner than the monolith, it must be **transparent** in PR/delivery (what changed internally vs what stayed the same for the API client).

## Anti-patterns

- **Error messages that may reach the client** (`Error.message`, public HTTP body, API payloads): **forbidden** to include internal details — DB tables/columns, internal field names (`metadata`, code paths), monolith/micro comparisons, XML/CFDI/FechaTimbrado, PHP methods, service names, or implementation narrative. Use a **short neutral** text in the product language (e.g. generic Spanish **without** exposing architecture). Technical trace, correlation, and PHP parity go in **`logger`** with structured context, **PR/Linear**, or **tests**. A stable **`code`** on the error class is allowed so handlers map to HTTP without exposing internals in `message`.
- **Blind copy of the monolith**: replicating huge branches, unnecessary item/category duplication, or patterns that **hurt performance** in the micro when TS already has a better approach (shared helpers, single pass, batch). The reference is the **outcome**, not the **PHP code**.
- Migrating calls that **persist other bounded contexts** from Bill without an explicit decision.
- Duplicating huge logic inline instead of extracting a stable **assembler / policy / helper**.
- **Fat repository**: defining local interfaces, `mapRow`, JSON parsing, or column normalization in the same file as SQL — belongs in **`interfaces/`** + **`mappers/*.mapper.ts`** (see § MySQL repositories above).
- **Wrong repository ownership**: attaching **metadata-admin**, **certificate**, or other satellite-table queries to **`CompanyRepository`** (or any aggregate repo that does not own those tables) instead of **`MetadataAdminCompanyRepository`**, **`CertificateRepository`**, or another dedicated port (see § Repository scope and table ownership).
- **Swallowing DB failures**: catching query exceptions, logging **`warn`**, and returning **`null`** as if no row existed — use **`logger.error`** + **rethrow** unless the monolith contract explicitly maps that failure to a business outcome (document if so).
- **Noisy migration comments**: "migrated from line X", `Bill.php` line lists, or JSDoc that repeats branches already visible in code; monolith↔micro equivalence goes to PR/Linear/tests (see § "Comments in code" above).
- **Invented defaults and fallbacks** (catch-all, `?? 0`, "if country missing assume X") that **do not appear** in the monolith for that flow.
- **Hiding ignorance**: prefer TODO + honest delivery over a guessed implementation.
- **Running `git commit`** or preparing commits on the user's behalf: forbidden unless explicitly requested; here we only **propose** the message text.

## Example triggers (non-exhaustive)

- **`/senior-engineer`** + "migrate…" / PHP fragment / monolith parity.
- "Migrate this block from `Bill.php` to…"
- "Parity private journal / categories / IEPS…"
- "What's missing vs PHP in…"
- Pasted Linear task + fragment.

---

**Note:** This skill is **adaptive**: the concrete domain (journal, taxes, metadata, country) changes each migration; the **process** stays the same (business aligned to PHP, implementation aligned to micro standards, review like **code-reviewer**).
