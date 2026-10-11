---

description: "Task list for feature 001-medallion-schemas"
---

# Tasks: Medallion Schemas with Restricted Access

**Input**: Design documents from `/specs/001-medallion-schemas/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/setup-and-verify.md, quickstart.md

**Tests**: no automated tests were requested. Each story ends with a validation task that
runs the matching scenario of quickstart.md against the workspace.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Setup scripts: `explorations/setup/`, the folder the constitution's repository layout (v1.5.0) names for auxiliary setup code
- Documentation: `doc/` at repository root
- All paths below are relative to the repository root

## Conventions for every task

- **Constants**: catalog `workspace`; schemas `bronze`, `silver`, `gold`; authorized
  principal `arthur.luz@dataslight.com.br`.
- **One statement per file**: each `.sql` file is a single SQL scripting compound statement
  (`BEGIN ... END`) with the constants declared at the top.
- **Running against the workspace**: tasks marked "run" execute
  `databricks experimental aitools tools query <file-or-sql> --profile <profile>`. Ask the
  owner which profile to use before the first run and pass it explicitly every time. Never
  pick a profile on the owner's behalf.
- **Report shape**: both scripts return columns `ordem` INT, `verificacao` STRING, `objeto`
  STRING, `resultado` STRING (`PASS`, `FAIL` or `INFO`), `detalhe` STRING, ordered by
  `ordem`, as defined in contracts/setup-and-verify.md.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: create the folder and the two script files

- [X] T001 Create the folder `explorations/setup/` and the file `explorations/setup/01_schemas_verify.sql` containing a header comment (purpose: read-only verification report for feature 001; how to run it; that it changes nothing) and an empty compound statement that declares the constants `v_catalogo = 'workspace'` and `v_dono = 'arthur.luz@dataslight.com.br'`
- [X] T002 [P] Create the file `explorations/setup/01_schemas.sql` containing a header comment (purpose: creates the bronze, silver and gold schemas and applies the access rule for feature 001; how to run it; that it never drops anything and can be run again) and an empty compound statement that declares the same constants `v_catalogo` and `v_dono`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the report skeleton and the pre-flight checks that every story relies on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 In `explorations/setup/01_schemas_verify.sql`, build the report as one final `SELECT` over a `UNION ALL` of check rows with the columns `ordem`, `verificacao`, `objeto`, `resultado`, `detalhe`, ordered by `ordem`; add the first row `verificacao = 'alvo'`, `objeto = 'workspace'`, `resultado = 'INFO'`, `detalhe` = `current_user()`, `current_catalog()` and `current_metastore()` concatenated with labels
- [X] T004 In `explorations/setup/01_schemas.sql`, add precondition P1: if `SELECT count(*) FROM system.information_schema.catalogs WHERE catalog_name = 'workspace'` is 0, raise `SIGNAL SQLSTATE '45000'` with a message containing `catalog workspace not found`
- [X] T005 In `explorations/setup/01_schemas.sql`, add precondition P2 after P1: if `current_user()` differs from `v_dono`, raise `SIGNAL SQLSTATE '45000'` with a message containing `must be run as arthur.luz@dataslight.com.br` followed by the actual `current_user()`
- [X] T006 Run `explorations/setup/01_schemas_verify.sql` against the workspace and confirm it returns one `alvo` row showing `arthur.luz@dataslight.com.br`, catalog `workspace` and a metastore id, with exit code 0

**Checkpoint**: both scripts run; the report shape and the guard rails exist

---

## Phase 3: User Story 1 - Create the three layer schemas (Priority: P1) 🎯 MVP

**Goal**: `bronze`, `silver` and `gold` exist in `workspace`, each with its layer description, and nothing else in the catalog changes.

**Independent Test**: quickstart.md Scenario 1. Before the setup the report shows three `schema_existe` rows with `FAIL`; after it, `databricks schemas list workspace` shows the three schemas with their descriptions and the `schema_existe` and `descricao` rows are `PASS`.

### Implementation for User Story 1

- [X] T007 [US1] In `explorations/setup/01_schemas_verify.sql`, add three `schema_existe` rows, one per schema, with `objeto = 'workspace.<schema>'`: `PASS` when the schema appears in `workspace.information_schema.schemata`, otherwise `FAIL` with `detalhe = 'schema não existe'`; a missing schema must produce a `FAIL` row and never an error
- [X] T008 [US1] In `explorations/setup/01_schemas_verify.sql`, add three `descricao` rows comparing `schemata.comment` with the expected text: bronze = `Camada bronze: dados brutos, exatamente como chegaram da origem.`; silver = `Camada silver: dados validados, tipados e conformados.`; gold = `Camada gold: modelo analítico (dimensões, fatos e tabelas desnormalizadas).`; `PASS` on an exact match, otherwise `FAIL` with the observed comment and the expected one in `detalhe`
- [X] T009 [US1] In `explorations/setup/01_schemas.sql`, add precondition P3 after P2 and before any change: for each of the three schemas that already exists in `workspace.information_schema.schemata` with `schema_owner` different from `v_dono`, collect `schema <name> is owned by <owner>`; if any was collected, raise `SIGNAL SQLSTATE '45000'` with all collected messages; all three schemas must be checked before the first `CREATE`
- [X] T010 [US1] In `explorations/setup/01_schemas.sql`, after the preconditions and in the order bronze, silver, gold, run `CREATE SCHEMA IF NOT EXISTS workspace.<schema>` followed by `COMMENT ON SCHEMA workspace.<schema> IS '<text>'` with the three descriptions quoted in T008, so the description is re-applied on every run; the script must contain no `DROP` statement and must reference no schema other than these three
- [X] T011 [US1] In `explorations/setup/01_schemas.sql`, make the last step return the verification report by repeating the report query of `explorations/setup/01_schemas_verify.sql` verbatim (rows `alvo`, `schema_existe`, `descricao`), and add a comment in both files stating that the two copies must be kept identical
- [X] T012 [US1] Run quickstart.md Scenario 1: run `explorations/setup/01_schemas_verify.sql` (expect three `schema_existe` rows with `FAIL` and no error), run `explorations/setup/01_schemas.sql` (expect exit code 0), then run `databricks schemas list workspace --profile <profile>` and confirm `bronze`, `silver`, `gold` exist with their descriptions and that `default` and `information_schema` are unchanged

**Checkpoint**: User Story 1 is functional; the three schemas exist and are described

---

## Phase 4: User Story 2 - Restrict access to the project owner (Priority: P2)

**Goal**: `arthur.luz@dataslight.com.br` owns the three schemas and is the only identity with access granted on them; inherited access is reported.

**Independent Test**: quickstart.md Scenario 2. The report shows `dono` and `acesso_direto` as `PASS` for all three schemas naming only the owner, `acesso_herdado` rows are `INFO`, and a throwaway table can be created and dropped in each schema.

### Implementation for User Story 2

- [X] T013 [US2] In `explorations/setup/01_schemas_verify.sql`, add three `dono` rows: `PASS` when `schemata.schema_owner` equals `v_dono`, otherwise `FAIL` with the observed owner in `detalhe`; when the schema does not exist the row is `FAIL` with `detalhe = 'schema não existe'`
- [X] T014 [US2] In `explorations/setup/01_schemas_verify.sql`, add three `acesso_direto` rows from `workspace.information_schema.schema_privileges` filtered to `inherited_from = 'NONE'`: `PASS` when the distinct grantees of the schema are exactly `v_dono`, otherwise `FAIL`; `detalhe` lists each grantee with its privileges, and for `FAIL` states that only `arthur.luz@dataslight.com.br` is expected
- [X] T015 [US2] In `explorations/setup/01_schemas_verify.sql`, add `acesso_herdado` rows, one per grantee and privilege, from `workspace.information_schema.schema_privileges` where `inherited_from <> 'NONE'` for the three schemas, plus one per row of `workspace.information_schema.catalog_privileges`; exclude rows whose grantee is `v_dono`; `resultado` is `INFO` when the privilege is `USE_CATALOG` or `BROWSE` (no access to schema contents) and `FAIL` for any other privilege; `detalhe` names the grantee, the privilege and where it is inherited from
- [X] T016 [US2] In `explorations/setup/01_schemas_verify.sql`, add one `dono_catalogo` row with `resultado = 'INFO'`, `objeto = 'workspace'` and `detalhe` giving the catalog owner from `system.information_schema.catalogs` and the sentence that members of this owner can manage the schemas by platform design
- [X] T017 [US2] In `explorations/setup/01_schemas.sql`, after the `COMMENT` of each schema, run `GRANT ALL PRIVILEGES ON SCHEMA workspace.<schema> TO` the authorized principal quoted with backticks, so that "exactly one direct grant set: `ALL PRIVILEGES` to the authorized principal" (data-model.md rule R2) holds; the script must contain no `GRANT` or `REVOKE` on the catalog
- [X] T018 [US2] In `explorations/setup/01_schemas.sql`, update the final report copy to match `explorations/setup/01_schemas_verify.sql` after T013 to T016 (rows `dono`, `acesso_direto`, `acesso_herdado`, `dono_catalogo`)
- [X] T019 [US2] Run quickstart.md Scenario 2: run `explorations/setup/01_schemas.sql`, confirm the report has 12 `PASS` rows (4 checks × 3 schemas) and no `FAIL` row, confirm `acesso_herdado` shows `USE_CATALOG` for the workspace users group as `INFO`, then create and drop the table `zz_teste_acesso (id INT)` in each of the three schemas and confirm every statement succeeds

**Checkpoint**: User Stories 1 and 2 both work; access is restricted and verifiable

---

## Phase 5: User Story 3 - Run the setup again safely (Priority: P3)

**Goal**: a second run succeeds, keeps every object and its data, recreates only what is missing, and removes access granted to anyone else.

**Independent Test**: quickstart.md Scenario 3. A second run reports the same 12 `PASS` rows with no `revogado` row; a table created between runs still has its row; an extra grant on `gold` is reported as `FAIL` by the verify script and removed by the next setup run.

### Implementation for User Story 3

- [X] T020 [US3] In `explorations/setup/01_schemas.sql`, after the `GRANT` of each schema, loop with `FOR ... DO` over the rows of `workspace.information_schema.schema_privileges` for that schema where `inherited_from = 'NONE'` and `grantee <> v_dono`, and for each run `EXECUTE IMMEDIATE` of `REVOKE <privilege> ON SCHEMA workspace.<schema> FROM` the grantee quoted with backticks, converting the `privilege_type` value to its SQL keyword form (underscores to spaces); record each revoked schema, grantee and privilege in a variable or temporary structure for the report
- [X] T021 [US3] In `explorations/setup/01_schemas.sql`, add `revogado` rows to the final report, one per privilege revoked in this run, with `resultado = 'INFO'`, `objeto = 'workspace.<schema>'` and `detalhe` naming the grantee and the privilege; a run that revokes nothing adds no such row
- [X] T022 [US3] Grant `USE SCHEMA ON SCHEMA workspace.gold` to the group `account users`, run `explorations/setup/01_schemas.sql`, and check whether the `acesso_direto` row for `workspace.gold` in the script's own final report is `PASS`; if it still shows the revoked grant, change `explorations/setup/01_schemas.sql` so the `acesso_direto` rows exclude the grants revoked in this run, and record the finding as a comment at the top of the file
- [X] T023 [US3] Run quickstart.md Scenario 3 in full: second run changes nothing (12 `PASS`, no `revogado`); create `workspace.bronze.zz_teste_reexecucao` with one row, run the setup, confirm the row count is 1, then drop the test table; with the owner's approval drop the empty schema `workspace.silver`, run the setup, and confirm 12 `PASS` rows; grant `USE SCHEMA` on `workspace.gold` to `account users`, confirm `explorations/setup/01_schemas_verify.sql` reports `FAIL` naming `account users`, run the setup, and confirm one `revogado` row and 12 `PASS` rows
- [X] T024 [US3] Review `explorations/setup/01_schemas.sql` against the refusal cases of quickstart.md Scenario 4 that cannot be provoked with a single user: confirm by reading the script that P2 raises before any change when `current_user()` is another identity, and that P3 raises naming schema and owner before any change when a schema has a different owner

**Checkpoint**: all three user stories work; the setup is repeatable

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: documentation required by FR-014 and the final validation

- [X] T025 [P] In `doc/getting-started.md`, replace the Prerequisites paragraph that says the repository has no script and the `CREATE SCHEMA` lines of its SQL block with instructions to run `explorations/setup/01_schemas.sql` and then `explorations/setup/01_schemas_verify.sql` with an explicit `--profile`, stating that the report must contain no `FAIL` row; keep the `CREATE VOLUME IF NOT EXISTS workspace.bronze.landing` statement as a separate manual step, since the volume is out of scope for this feature
- [X] T026 [P] In `doc/README.md`, add `explorations/setup/` to the repository layout tree with the two files and a one-line description of each (`01_schemas.sql`: creates the schemas and applies the access rule; `01_schemas_verify.sql`: read-only verification report)
- [X] T027 Review `explorations/setup/01_schemas.sql` and `explorations/setup/01_schemas_verify.sql` against contracts/setup-and-verify.md: guarantees G1 to G7 and V1 to V3 hold, the two report queries are identical apart from the `revogado` rows, and neither file contains a profile name, a `DROP`, or a reference to a catalog other than `workspace` and `system`
- [X] T028 Run `explorations/setup/01_schemas_verify.sql` one last time and confirm the report has 12 `PASS` rows and no `FAIL` row, and that no test object (`zz_teste_acesso`, `zz_teste_reexecucao`) remains in any of the three schemas

---

## Phase 7: Relocation to `src/` (constitution v1.4.0, superseded)

**Purpose**: bring what is already built into line with the amended repository layout.
Phases 1 to 6 were implemented on 2026-10-10 in a top-level `setup/` folder, which
constitution v1.3.0 allowed as a recorded deviation. Version 1.4.0 requires all code under
`src/`. Content and behavior do not change; nothing changes in the workspace.

- [X] T029 Move `setup/01_schemas.sql` to `src/setup/01_schemas.sql` and `setup/01_schemas_verify.sql` to `src/setup/01_schemas_verify.sql` with `git mv`, content unchanged, and confirm the top-level `setup/` folder no longer exists
- [X] T030 [P] In `src/setup/01_schemas.sql`, update the three comment lines that name a script path (the run command in the header, the header line naming the verify script, and the comment above the report query) from `setup/` to `src/setup/`; change no SQL
- [X] T031 [P] In `src/setup/01_schemas_verify.sql`, update the two comment lines that name a script path (the run command and the note about the copy in the setup script) from `setup/` to `src/setup/`; change no SQL
- [X] T032 [P] In `doc/getting-started.md`, change the two commands under "Create the schemas" to `src/setup/01_schemas.sql` and `src/setup/01_schemas_verify.sql`
- [X] T033 [P] In `doc/README.md`, change the repository layout tree so that the two scripts appear under `src/setup/` instead of a top-level `setup/`
- [X] T034 Confirm no file outside `specs/` and `.specify/` still references the top-level path (search for `setup/01_schemas` not preceded by `src/`), then run `src/setup/01_schemas_verify.sql` against the workspace with the owner's profile and confirm 12 `PASS` rows and no `FAIL` row

**Checkpoint**: reached on 2026-10-11 under v1.4.0. Superseded the same day by v1.5.0; see Phase 8

---

## Phase 8: Relocation to `explorations/setup/` (constitution v1.5.0)

**Purpose**: constitution v1.5.0 reserves `src/` for the deployed pipeline and puts all
auxiliary code, the initial setup included, in `explorations/`. The two scripts are in
`src/setup/` after Phase 7 and move to `explorations/setup/`. Content and behavior do not
change; nothing changes in the workspace.

- [X] T035 Move `src/setup/01_schemas.sql` to `explorations/setup/01_schemas.sql` and `src/setup/01_schemas_verify.sql` to `explorations/setup/01_schemas_verify.sql` with `git mv`, content unchanged; then remove the empty folder `src/setup/`, and remove `src/` as well if it contains nothing else
- [X] T036 [P] In `explorations/setup/01_schemas.sql`, update the three comment lines that name a script path (the run command in the header, the header line naming the verify script, and the comment above the report query) from `src/setup/` to `explorations/setup/`; change no SQL
- [X] T037 [P] In `explorations/setup/01_schemas_verify.sql`, update the two comment lines that name a script path (the run command and the note about the copy in the setup script) from `src/setup/` to `explorations/setup/`; change no SQL
- [X] T038 [P] In `doc/getting-started.md`, change the two commands under "Create the schemas" to `explorations/setup/01_schemas.sql` and `explorations/setup/01_schemas_verify.sql`
- [X] T039 [P] In `doc/README.md`, change the repository layout tree so that `setup/` with its two scripts appears under `explorations/`, and remove the `src/` entry that was added for `src/setup/`
- [X] T040 Confirm no file outside `specs/` and `.specify/` still references `src/setup`, confirm `git diff` shows only comment lines changed in the two scripts, then run `explorations/setup/01_schemas_verify.sql` against the workspace with the profile chosen by the owner and confirm 12 `PASS` rows and no `FAIL` row

**Checkpoint**: the feature's code lives in `explorations/setup/`; nothing from this feature is under `src/`; the constitution check of plan.md passes with no deviations

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup; blocks all user stories
- **User Story 1 (Phase 3)**: depends on Foundational
- **User Story 2 (Phase 4)**: depends on User Story 1, because grants need the schemas to exist and both stories edit the same two files
- **User Story 3 (Phase 5)**: depends on User Story 2, because revoking and re-running build on the grant logic
- **Polish (Phase 6)**: depends on all three stories
- **Relocation (Phase 7)**: depends on Phases 1 to 6 being complete; T029 first, then T030 to T033 in parallel, then T034
- **Relocation (Phase 8)**: depends on Phase 7; T035 first, then T036 to T039 in parallel, then T040

### User Story Dependencies

The stories are sequential, not parallel. This is a deliberate exception to the usual
independence: the feature is two files, and each story adds statements to both.

- **US1 (P1)**: independent; delivers usable schemas on its own
- **US2 (P2)**: needs US1's schemas
- **US3 (P3)**: needs US2's grants; its "second run changes nothing" check is only
  meaningful once US1 and US2 are complete

### Within Each User Story

- Verification rows first (`explorations/setup/01_schemas_verify.sql`), then the change
  (`explorations/setup/01_schemas.sql`), then the report copy, then the validation run
- Tasks that edit the same file run in order; do not parallelize them

### Parallel Opportunities

- T001 and T002 (different files)
- T025 and T026 (different documentation files)
- T030, T031, T032 and T033 (four different files, all after T029)
- T036, T037, T038 and T039 (four different files, all after T035)
- Within a story, a verify-script task and a setup-script task touch different files, but
  the setup's report copy depends on the verify rows, so run them in the listed order

---

## Parallel Example: Polish

```bash
# The two documentation updates touch different files and can run together:
Task: "Update prerequisites in doc/getting-started.md to point to setup/"
Task: "Add setup/ to the repository layout in doc/README.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: run quickstart.md Scenario 1
5. The schemas exist and the next project step could start, with creator-only access by
   platform default

### Incremental Delivery

1. Setup + Foundational → both scripts run and report their target
2. User Story 1 → schemas exist and are described (MVP)
3. User Story 2 → access is explicit, restricted and reported
4. User Story 3 → drift is corrected and re-runs are proven safe
5. Polish → documentation points to the scripts

---

## Notes

- Tasks T006, T012, T019, T022, T023 and T028 run against the live workspace. T012 and
  later create the schemas. T022 and T023 temporarily add a grant, and T023 drops the
  empty `silver` schema; ask the owner before those two steps.
- The owner is the only user in the workspace, so refusal for other identities (SC-003) is
  shown by the absence of grants, not by an attempt. See research.md, Decision 5.
- The scripts have had three locations as the layout rule was settled: `setup/` (v1.3.0,
  Phases 1 to 6), `src/setup/` (v1.4.0, Phase 7) and `explorations/setup/` (v1.5.0,
  Phase 8). Paths in Phases 1 to 6 name the final location; Phase 7 is kept as history.
- T040 runs a read-only query against the workspace. Ask the owner which profile to use.
- `doc/` still describes `code_tips/`, which is no longer in the repository. That does not
  belong to this feature.
- Commit after each phase checkpoint.

## Implementation notes (2026-10-10)

Tasks T001 to T028 were completed on this date, in a top-level `setup/` folder.
Deviations from the task text, with the reason:

- **T001**: `explorations/setup/01_schemas_verify.sql` is a single `WITH ... SELECT` query, not a
  compound statement. Its constants live in a `constantes` CTE. A plain query cannot
  change anything, which makes guarantee V1 (read-only) hold by construction, and the
  same text is reused as the last statement of the setup script.
- **T010**: the description is re-applied only when it differs from the expected text,
  so that a second run changes nothing (SC-004). `CREATE`, `COMMENT`, `GRANT` and
  `REVOKE` run through `EXECUTE IMMEDIATE` inside a loop over the three schemas.
- **T022, T023**: the stray grant was given to `account users`. The workspace-local group
  `users` is not a Unity Catalog principal, and the system group
  `_workspace_users_workspace_...` cannot receive schema grants. quickstart.md was
  corrected accordingly.
- **T022 finding**: the information schema reflects a `REVOKE` within the same compound
  statement, so no change to the `acesso_direto` rows was needed.
- **T024**: preconditions P2 and P3 were verified by reading the script only. The
  workspace has a single user, so neither can be provoked.

## Implementation notes (2026-10-11)

Tasks T029 to T034 are complete. Both scripts were moved to `src/setup/` with `git mv`;
only five comment lines changed, no SQL. The verification script, run from its new path,
returned 12 `PASS` rows and no `FAIL` row. The workspace was not modified.

Tasks T035 to T040 are complete (same day, after constitution v1.5.0). Both scripts were
moved from `src/setup/` to `explorations/setup/` with `git mv`, and the empty `src/` folder
was removed. Compared with the committed version, only five comment lines differ and no
SQL. The verification script, run from its new path, returned 12 `PASS` rows and no `FAIL`
row. The workspace was not modified.
