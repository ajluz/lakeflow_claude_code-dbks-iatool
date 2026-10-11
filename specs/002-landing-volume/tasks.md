---

description: "Task list for feature 002-landing-volume"
---

# Tasks: Landing Volume in Bronze

**Input**: Design documents from `/specs/002-landing-volume/`

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

- **Constants**: catalog `workspace`; schema `bronze`; volume `landing`; authorized
  principal `arthur.luz@dataslight.com.br`; volume description
  `Landing zone: arquivos de origem como chegaram, uma pasta por origem.`
- **Model files**: `explorations/setup/01_schemas.sql` and
  `explorations/setup/01_schemas_verify.sql` (feature 001). Follow their structure, naming,
  Portuguese comment style and header layout. Do not modify them.
- **One statement per file**: the setup script is a single SQL scripting compound statement
  (`BEGIN ... END`) with constants declared at the top; the verify script is a single
  `WITH ... SELECT` query with constants in a CTE named `constantes`.
- **String literals**: in dynamic statements, wrap embedded text in double-quoted literals
  around the single quotes (`" IS '"`, `"'"`); `''` is not an escaped quote in this dialect.
- **Never destructive**: neither file may contain `DROP`, `CREATE OR REPLACE`, `LOCATION`,
  or any statement that lists or removes files.
- **Running against the workspace**: tasks marked "run" execute
  `databricks experimental aitools tools query <file-or-sql> --profile <profile>`. Ask the
  owner which profile to use before the first run and pass it explicitly every time.
- **Report shape**: columns `ordem` INT, `verificacao` STRING, `objeto` STRING, `resultado`
  STRING (`PASS`, `FAIL` or `INFO`), `detalhe` STRING, ordered by `ordem`, `objeto`,
  `detalhe`. This step uses `ordem` 110 to 190.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: create the two script files

- [X] T001 Create `explorations/setup/02_landing_volume_verify.sql` with a header comment in Portuguese (purpose: read-only verification report for feature 002; that it changes nothing and can run in any state; the run command `databricks experimental aitools tools query explorations/setup/02_landing_volume_verify.sql --profile <profile>`; that a clean environment shows 6 `PASS` rows; that the query is repeated at the end of `explorations/setup/02_landing_volume.sql` and the two copies must stay identical) followed by a `WITH constantes AS (...)` CTE holding `catalogo = 'workspace'`, `schema_nome = 'bronze'`, `volume_nome = 'landing'`, `dono = 'arthur.luz@dataslight.com.br'` and `descricao_esperada` with the volume description
- [X] T002 [P] Create `explorations/setup/02_landing_volume.sql` with a header comment in Portuguese (purpose: creates the managed volume `workspace.bronze.landing` and applies the access rule for feature 002; that it never removes or replaces the volume or its files and can be run again; the run command; the five preconditions P1 to P5 in one line each; that the result is the verification report plus the `revogado` rows) followed by `BEGIN ... END` declaring `v_catalogo`, `v_schema`, `v_volume`, `v_dono`, `v_descricao`, `v_qtd INT`, `v_msg STRING`, `v_descricao_atual STRING` and `v_revogados ARRAY<STRUCT<objeto STRING, detalhe STRING>>` defaulting to an empty array cast to that type

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the report skeleton and the guard rails every story relies on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 In `explorations/setup/02_landing_volume_verify.sql`, build the report as a `relatorio` CTE made of `UNION ALL` branches and a final `SELECT ordem, verificacao, objeto, resultado, detalhe FROM relatorio ORDER BY ordem, objeto, detalhe`; add the row `ordem = 110`, `verificacao = 'alvo'`, `objeto = 'workspace.bronze'`, `resultado = 'INFO'`, `detalhe` = current user, current catalog and current metastore with labels, as in the step 1 verify file
- [X] T004 In `explorations/setup/02_landing_volume_verify.sql`, add the row `ordem = 120`, `verificacao = 'pre_requisito'`, `objeto = 'workspace.bronze'` from a `LEFT JOIN` to `workspace.information_schema.schemata`: `PASS` when the schema exists and `schema_owner` equals the owner constant; `FAIL` with `detalhe = 'schema não existe; execute antes explorations/setup/01_schemas.sql'` when missing; `FAIL` with the observed and expected owner when owned by someone else
- [X] T005 In `explorations/setup/02_landing_volume.sql`, add precondition P1: if no row for `bronze` exists in `workspace.information_schema.schemata`, raise `SIGNAL SQLSTATE '45000'` with a message containing `schema workspace.bronze not found` and `run explorations/setup/01_schemas.sql first`
- [X] T006 In `explorations/setup/02_landing_volume.sql`, add precondition P2 after P1 (if `current_user()` differs from `v_dono`, raise with a message containing `must be run as arthur.luz@dataslight.com.br` and the actual user) and precondition P3 after P2 (if the `schema_owner` of `bronze` differs from `v_dono`, raise with a message containing `schema bronze is owned by <owner>`)
- [X] T007 Run `explorations/setup/02_landing_volume_verify.sql` against the workspace and confirm exit code 0, one `alvo` row showing `arthur.luz@dataslight.com.br`, and one `pre_requisito` row with `PASS`

**Checkpoint**: both files run; the report shape and the first guard rails exist

---

## Phase 3: User Story 1 - Create the landing volume (Priority: P1) 🎯 MVP

**Goal**: the managed volume `workspace.bronze.landing` exists, empty, with its description, and a file can be written to it and read back.

**Independent Test**: quickstart.md Scenario 1. Before the setup the report shows `volume_existe` as `FAIL`; after it, `databricks volumes list workspace bronze` shows `landing` as `MANAGED` with its description, and a file copied to the volume comes back identical.

### Implementation for User Story 1

- [X] T008 [US1] In `explorations/setup/02_landing_volume_verify.sql`, add a CTE reading the volume from `workspace.information_schema.volumes` (`volume_catalog`, `volume_schema`, `volume_name`, `volume_type`, `volume_owner`, `comment`) with a `LEFT JOIN` from the constants so a missing volume yields one row of nulls, and add the row `ordem = 130`, `verificacao = 'volume_existe'`, `objeto = 'workspace.bronze.landing'`: `PASS` with `detalhe = 'volume existe'`, otherwise `FAIL` with `detalhe = 'volume não existe'`; a missing volume or schema must produce a `FAIL` row and never an error
- [X] T009 [US1] In `explorations/setup/02_landing_volume_verify.sql`, add the row `ordem = 150`, `verificacao = 'armazenamento'`: `PASS` when `volume_type = 'MANAGED'` with the type in `detalhe`; `FAIL` with the observed type and `esperado: MANAGED` otherwise; `FAIL` with `volume não existe` when missing. Add the row `ordem = 160`, `verificacao = 'descricao'`: `PASS` when `comment` equals the expected description using the null-safe comparison `<=>`; otherwise `FAIL` with the observed and expected text
- [X] T010 [US1] In `explorations/setup/02_landing_volume.sql`, add precondition P4 after P3 (if a row named `landing` exists in `workspace.information_schema.tables` for schema `bronze`, raise with a message containing `an object named landing already exists in workspace.bronze` and its `table_type`) and precondition P5 after P4 (if a volume named `landing` exists in `workspace.information_schema.volumes` for schema `bronze` with `volume_owner` different from `v_dono`, raise with a message containing `volume landing is owned by <owner>`); all five preconditions must come before the first statement that changes anything
- [X] T011 [US1] In `explorations/setup/02_landing_volume.sql`, after the preconditions, run `CREATE VOLUME IF NOT EXISTS workspace.bronze.landing` through `EXECUTE IMMEDIATE` with no `LOCATION` clause, then read the current `comment` of the volume into `v_descricao_atual` and run `COMMENT ON VOLUME workspace.bronze.landing IS '<description>'` only when it differs (`NOT (v_descricao_atual <=> v_descricao)`)
- [X] T012 [US1] In `explorations/setup/02_landing_volume.sql`, make the last statement return the verification report by repeating the report query of `explorations/setup/02_landing_volume_verify.sql` verbatim, indented inside the block, and add a comment in both files stating that the two copies must be kept identical
- [X] T013 [US1] Run quickstart.md Scenario 1: run the verify script (expect `pre_requisito` `PASS` and `volume_existe` `FAIL`, no error); run the setup script (expect exit code 0); run `databricks volumes list workspace bronze --profile <profile>` and confirm one volume `landing` of type `MANAGED` with its description; then copy a one-line local file to `dbfs:/Volumes/workspace/bronze/landing/zz_teste_landing.txt` with `databricks fs cp`, copy it back, and confirm with `diff` that the content is identical; leave the file in the volume for Phase 5

**Checkpoint**: User Story 1 is functional; the volume exists and accepts files

---

## Phase 4: User Story 2 - Keep the volume restricted to the project owner (Priority: P2)

**Goal**: `arthur.luz@dataslight.com.br` owns the volume and is the only identity with access granted on it; inherited access is reported.

**Independent Test**: quickstart.md Scenario 2. The report shows `dono` and `acesso_direto` as `PASS` naming only the owner, and any `acesso_herdado` row is `INFO`.

### Implementation for User Story 2

- [X] T014 [US2] In `explorations/setup/02_landing_volume_verify.sql`, add the row `ordem = 140`, `verificacao = 'dono'`: `PASS` when `volume_owner` equals the owner constant, otherwise `FAIL` with the observed and expected owner; `FAIL` with `volume não existe` when missing
- [X] T015 [US2] In `explorations/setup/02_landing_volume_verify.sql`, add CTEs over `workspace.information_schema.volume_privileges` filtered to `volume_catalog = 'workspace'`, `volume_schema = 'bronze'`, `volume_name = 'landing'`, following the `privilegios`, `diretos_por_grantee` and `diretos` CTEs of the step 1 verify file, and add the row `ordem = 170`, `verificacao = 'acesso_direto'`: `PASS` when, among rows with `inherited_from = 'NONE'`, the authorized principal is a grantee and no other grantee exists; otherwise `FAIL`; `detalhe` lists each grantee with its privileges in brackets and, for `FAIL`, ends with `esperado: apenas arthur.luz@dataslight.com.br`
- [X] T016 [US2] In `explorations/setup/02_landing_volume_verify.sql`, add rows `ordem = 180`, `verificacao = 'acesso_herdado'`, one per grantee and privilege where `inherited_from <> 'NONE'` and the grantee is not the authorized principal: `INFO` when the privilege, upper-cased with spaces replaced by underscores, is `USE_CATALOG`, `USE_SCHEMA` or `BROWSE`; `FAIL` for any other privilege; `detalhe` = `<grantee>: <privilege> (herdado de <inherited_from>)`
- [X] T017 [US2] In `explorations/setup/02_landing_volume.sql`, after the description step, run `GRANT ALL PRIVILEGES ON VOLUME workspace.bronze.landing TO` the authorized principal quoted with backticks, through `EXECUTE IMMEDIATE`, so that data-model.md rule R2 holds ("exactly one direct grant set: `ALL PRIVILEGES` to the authorized principal"); the script must contain no `GRANT` or `REVOKE` on a schema or on the catalog
- [X] T018 [US2] In `explorations/setup/02_landing_volume.sql`, update the final report copy to match `explorations/setup/02_landing_volume_verify.sql` after T014 to T016
- [X] T019 [US2] Run quickstart.md Scenario 2: run the setup script and confirm the report has 6 `PASS` rows and no `FAIL` row, with `dono` and `acesso_direto` naming only `arthur.luz@dataslight.com.br`; record in the Implementation notes of this file whether the owner's schema-level `ALL PRIVILEGES` appears in `volume_privileges` as an inherited row and which privilege names the view returns for the direct grant

**Checkpoint**: User Stories 1 and 2 both work; access is explicit and verifiable

---

## Phase 5: User Story 3 - Run the setup again safely (Priority: P3)

**Goal**: a second run succeeds, keeps every file in the volume, removes access granted to anyone else, and recreates the volume when it is missing.

**Independent Test**: quickstart.md Scenario 3. A second run reports 6 `PASS` rows with no `revogado` row and the test file is still identical; a stray grant to `account users` is flagged by the verify script and removed by the next setup run.

### Implementation for User Story 3

- [X] T020 [US3] In `explorations/setup/02_landing_volume.sql`, after the `GRANT`, loop with `FOR ... DO` over the distinct `grantee`, `privilege_type` rows of `workspace.information_schema.volume_privileges` for this volume where `inherited_from = 'NONE'` and `grantee <> v_dono`, and for each run `EXECUTE IMMEDIATE` of `REVOKE <privilege> ON VOLUME workspace.bronze.landing FROM` the grantee quoted with backticks, converting `privilege_type` to its keyword form by replacing underscores with spaces; append to `v_revogados` a struct with `objeto = 'workspace.bronze.landing'` and `detalhe = '<grantee>: <privilege>'`
- [X] T021 [US3] In `explorations/setup/02_landing_volume.sql`, add to the final report a branch `ordem = 190`, `verificacao = 'revogado'`, `resultado = 'INFO'` reading `explode(v_revogados)`, marked with a comment saying it exists only in the setup script; a run that revokes nothing adds no such row
- [X] T022 [US3] Run the first two parts of quickstart.md Scenario 3: run the setup script again and confirm 6 `PASS` rows, no `revogado` row, and that `zz_teste_landing.txt` copied back from the volume is identical to the original; then grant `READ VOLUME ON VOLUME workspace.bronze.landing` to `account users`, confirm the verify script reports `acesso_direto` as `FAIL` naming `account users`, run the setup script, and confirm one `revogado` row naming `account users`, 6 `PASS` rows, and the test file still present
- [X] T023 [US3] With the owner's approval, run the last part of quickstart.md Scenario 3 together with the reproducible case of Scenario 4: remove `zz_teste_landing.txt` from the volume with `databricks fs rm` and run `DROP VOLUME workspace.bronze.landing`; while no volume exists, create the table `workspace.bronze.landing (id INT)`, run `explorations/setup/02_landing_volume.sql`, confirm it fails with a message containing `an object named landing already exists` and that no volume was created, then drop that table; run the setup script again and confirm 6 `PASS` rows; finally run `explorations/setup/01_schemas_verify.sql` and confirm it still shows 12 `PASS` rows
- [X] T024 [US3] Review `explorations/setup/02_landing_volume.sql` for the refusals of quickstart.md Scenario 4 that cannot be provoked with a single user: confirm by reading the script that P1, P2, P3 and P5 each raise before the first statement that changes anything, with the message text required by contracts/setup-and-verify.md

**Checkpoint**: all three user stories work; the setup is repeatable

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: the combined check of FR-014, the documentation of FR-015, and the final validation

- [X] T025 [P] In `doc/getting-started.md`, replace the section "Create the landing volume" (the sentence saying the volume is not part of the script and its `CREATE VOLUME` SQL block) with instructions to run `explorations/setup/02_landing_volume.sql` with an explicit `--profile` after the schemas step, stating that the report must contain no `FAIL` row and that a clean run shows 6 `PASS` rows; then add a short subsection "Check the whole environment" giving the single command that runs `explorations/setup/01_schemas_verify.sql` and `explorations/setup/02_landing_volume_verify.sql` with `--output json | jq -r '.[].rows[] | @tsv'`, stating that the environment is ready when no row says `FAIL` and that a clean environment shows 18 `PASS` rows
- [X] T026 [P] In `doc/README.md`, add `02_landing_volume.sql` (creates the landing volume and applies the access rule) and `02_landing_volume_verify.sql` (read-only verification report) to the `explorations/setup/` entry of the repository layout tree, and change the "Landing volume" row of the "At a glance" table only if it no longer matches `/Volumes/workspace/bronze/landing`
- [X] T027 Review `explorations/setup/02_landing_volume.sql` and `explorations/setup/02_landing_volume_verify.sql` against contracts/setup-and-verify.md: guarantees G1 to G8 and V1 to V3 hold; the two report queries are identical apart from the `revogado` branch; neither file contains a profile name, `DROP`, `CREATE OR REPLACE`, `LOCATION`, or a reference to a catalog other than `workspace`; and `git status` shows the two step 1 files unmodified
- [X] T028 Run quickstart.md Scenario 5 and the clean-up: run both verify files in one call with `--output json | jq -r '.[].rows[] | @tsv'` and confirm 18 `PASS` rows and no `FAIL` row; confirm with `databricks fs ls dbfs:/Volumes/workspace/bronze/landing --profile <profile>` that the volume is empty; remove the local `/tmp/zz_teste_landing*.txt` files

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies inside this feature; requires feature 001 to be in place in the workspace
- **Foundational (Phase 2)**: depends on Setup; blocks all user stories
- **User Story 1 (Phase 3)**: depends on Foundational
- **User Story 2 (Phase 4)**: depends on User Story 1, because grants need the volume to exist and both stories edit the same two files
- **User Story 3 (Phase 5)**: depends on User Story 2, because revoking and re-running build on the grant logic
- **Polish (Phase 6)**: depends on all three stories

### User Story Dependencies

The stories are sequential, as in feature 001: the feature is two files and each story adds
statements to both.

- **US1 (P1)**: independent; delivers a usable volume on its own
- **US2 (P2)**: needs US1's volume
- **US3 (P3)**: needs US2's grant; uses the test file left by US1

### Within Each User Story

- Verification rows first (`02_landing_volume_verify.sql`), then the change
  (`02_landing_volume.sql`), then the report copy, then the validation run
- Tasks that edit the same file run in order

### Parallel Opportunities

- T001 and T002 (different files)
- T025 and T026 (different documentation files)

---

## Parallel Example: Polish

```bash
# The two documentation updates touch different files and can run together:
Task: "Replace the manual CREATE VOLUME in doc/getting-started.md and add the combined check"
Task: "Add the two new scripts to the repository layout in doc/README.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: run quickstart.md Scenario 1
5. The volume exists and the data generators could start writing to it, with access
   limited by the `bronze` schema's rule

### Incremental Delivery

1. Setup + Foundational → both scripts run and report target and prerequisite
2. User Story 1 → the volume exists and accepts files (MVP)
3. User Story 2 → access is explicit, restricted and reported
4. User Story 3 → drift is corrected and re-runs are proven safe
5. Polish → one command checks the whole environment; documentation points to the scripts

---

## Notes

- Tasks T007, T013, T019, T022, T023 and T028 run against the live workspace. T013 creates
  the volume and writes one small test file. T022 temporarily adds a grant. T023 deletes
  the test file, drops the volume to prove it is recreated, and briefly creates an empty
  table named `landing` to prove the collision is refused; ask the owner before T022 and
  T023.
- The workspace has a single user, so refusal for other identities (SC-003) is shown by
  the absence of grants. Preconditions P2, P3 and P5 cannot be provoked and are verified by
  review (T024).
- The source folders inside the volume are out of scope; the data generators create them.
- Commit after each phase checkpoint.

## Implementation notes (2026-10-11)

All 28 tasks are complete, run against the `databricks-free` profile chosen by the owner.
Both scripts worked on the first run; no fix was needed.

Findings recorded for T019:

- The owner's schema-level grant does appear on the volume: `volume_privileges` returns two
  rows for `arthur.luz@dataslight.com.br`, both `ALL_PRIVILEGES`, one with
  `inherited_from = 'NONE'` (the direct grant made by the script) and one with
  `inherited_from = 'SCHEMA'`. The `acesso_direto` check reads only the direct row, and the
  `acesso_herdado` check ignores rows of the owner, so the report is unaffected.
- `GRANT ALL PRIVILEGES ON VOLUME` is stored as the single privilege `ALL_PRIVILEGES`.
- A stray `READ VOLUME` grant is returned as `READ_VOLUME`; replacing underscores with
  spaces gives a valid `REVOKE`.

Deviations from the task text, with the reason:

- **T001, T003**: the constants CTE also holds `objeto_schema` and `objeto_volume`, the two
  display names used in the report, so they are written once.
- **T015**: the `diretos` CTE aggregates without `GROUP BY`, so it returns one row even when
  the volume has no grants; step 1 needed a `LEFT JOIN` per schema instead.
- **T013, T022**: the test file was written from the session's scratch folder, not `/tmp`.
- **T024**: preconditions P1, P2, P3 and P5 were verified by reading the script only. P4 was
  provoked in T023 and refused the run with
  `an object named landing already exists in workspace.bronze (MANAGED)`, creating nothing.

Final state of the workspace: the volume `workspace.bronze.landing` exists, managed, empty,
owned by and granted only to the owner. No test file, table or grant remains. The combined
check of both steps shows 18 `PASS` rows and no `FAIL` row.
