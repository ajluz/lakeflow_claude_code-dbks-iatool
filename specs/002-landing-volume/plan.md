# Implementation Plan: Landing Volume in Bronze

**Branch**: `002-landing-volume` | **Date**: 2026-10-11 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-landing-volume/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Create the managed volume `landing` in `workspace.bronze`, owned by and accessible only to
`arthur.luz@dataslight.com.br`, with a setup that can be run again without losing the files
in the volume.

Technical approach, from [research.md](research.md): one idempotent SQL script in the same
form as the schemas script of feature 001. It checks five preconditions before changing
anything, creates the volume if missing, sets its description, grants full control to the
owner, and revokes any other direct grant it finds in the information schema. A second,
read-only script returns a pass/fail report with the same columns as step 1, so that one
CLI call can run both verifications and show the state of the whole environment.

## Technical Context

**Language/Version**: Databricks SQL with SQL scripting, the same constructs validated in
feature 001 on DBSQL 2026.38

**Primary Dependencies**: Unity Catalog volumes; a serverless SQL warehouse (auto-detected
by the CLI); Databricks CLI v1.11.0; `jq` for the combined check only

**Storage**: one Unity Catalog managed volume, at `/Volumes/workspace/bronze/landing`. The
feature writes no files to it

**Testing**: the read-only verification script plus the manual scenarios in
[quickstart.md](quickstart.md), including a file round trip with `databricks fs cp`. No
test framework

**Target Platform**: Databricks Free Edition workspace `dbc-7e0f02e0-ff06`, catalog
`workspace`, schema `bronze`

**Project Type**: environment setup scripts (auxiliary code) for a data pipeline project

**Performance Goals**: setup and verification each finish in under 1 minute; from "schemas
only" to a verified volume in under 2 minutes (SC-006)

**Constraints**: repeatable; never drops or replaces the volume and never touches its
files; changes no schema, table or other volume; CLI profile always passed explicitly;
runs only as the authorized principal and only after step 1

**Scale/Scope**: 1 volume, 1 authorized identity, 2 SQL files, 2 documentation updates

No item is marked NEEDS CLARIFICATION. Facts about the target environment were read from
it on 2026-10-11 and are recorded in [research.md](research.md).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v1.5.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | The volume sits in `bronze`, the layer that holds source data as it arrived. No dataset is created, so the read-direction and `quality` property rules have nothing to check yet. |
| II. SQL-Only Declarative Pipelines | In spirit | PASS | The principle binds pipeline source. This is auxiliary setup, written in SQL only; it adds no Python. |
| III. Data Quality Through Expectations | No | N/A | No dataset, no rows, no quality rule. |
| IV. Quarantine, Never Silently Discard | No | N/A | No data is processed. |
| V. Dataset Types and Flows | No | N/A | No dataset or flow. |
| VI. Record Source and Hash Keys in Silver | No | N/A | No silver table. |
| VII. Kimball Dimensional Modeling in Gold | No | N/A | No gold table. |
| Constraints: catalog and schemas | Yes | PASS | Only `workspace.bronze` is referenced; no other catalog. |
| Constraints: landing zone | Yes | PASS | Creates exactly the volume the constraint names, `workspace.bronze.landing`, for source files with one folder per source. The setup writes no files to it, and no pipeline code is involved. |
| Constraints: repository layout | Yes | PASS | Both scripts are auxiliary code and live in `explorations/setup/`, numbered `02_`. Nothing is added under `src/`. |
| Constraints: naming | Yes | PASS | The volume name is lowercase; report columns and check names are Portuguese snake_case. |
| Constraints: data | Yes | PASS | No data is loaded. The quickstart's test file holds one line of text and is removed. |
| Constraints: CLI | Yes | PASS | Every command takes `--profile`; no profile is stored in a script. |
| Workflow: consult `databricks-pipelines` skill | No | N/A | No pipeline code. `databricks-core` governs the CLI usage here. |
| Workflow: completion gates 1 to 5 | No | N/A | They concern pipeline updates, expectations, keys and facts. |
| Workflow: completion gate 6 (documentation) | Yes | PLANNED | `doc/getting-started.md` and `doc/README.md` are updated as part of this feature (FR-015). |
| Workflow: destructive actions need approval | Yes | PASS | The setup never drops anything. The quickstart's recreation test drops the volume after emptying it and is run only with the owner's approval. |

**Gate result (pre-research)**: PASS, no deviations.

**Gate result (post-design)**: PASS, no deviations. The design in
[data-model.md](data-model.md) and
[contracts/setup-and-verify.md](contracts/setup-and-verify.md) stays SQL-only, touches only
the one volume, leaves schema and catalog grants alone, and places its code in
`explorations/setup/`.

## Project Structure

### Documentation (this feature)

```text
specs/002-landing-volume/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── setup-and-verify.md   # Phase 1 output (/speckit-plan command)
├── checklists/
│   └── requirements.md  # Created by /speckit-specify
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
explorations/                        # auxiliary code
└── setup/                           # initial environment setup, run by hand, in step order
    ├── 01_schemas.sql               # unchanged (feature 001)
    ├── 01_schemas_verify.sql        # unchanged (feature 001)
    ├── 02_landing_volume.sql        # NEW: creates the volume and applies the access rule
    └── 02_landing_volume_verify.sql # NEW: read-only verification report

doc/
├── getting-started.md               # CHANGED: the manual CREATE VOLUME is replaced by the
│                                    #   script, and the combined check is added
└── README.md                        # CHANGED: repository layout lists the two new files
```

**Structure Decision**: the two scripts are auxiliary code and go in
`explorations/setup/` with the prefix `02_`, after the schemas step, as the constitution's
repository layout prescribes. The files of feature 001 are not modified.

## Design Notes for Implementation

These carry the decisions of [research.md](research.md) into the task phase.

- **Same form as step 1.** The setup script is one compound statement with its constants
  declared at the top; the verify script is one `WITH ... SELECT` query with its constants
  in a CTE. Use `explorations/setup/01_schemas.sql` and its verify file as the model for
  structure, naming and comment style.
- **Check, then change.** All five preconditions of the contract are evaluated before the
  `CREATE VOLUME`.
- **Never replace.** Only `CREATE VOLUME IF NOT EXISTS`, with no `LOCATION`. The script
  contains no `DROP`, no `CREATE OR REPLACE`, and no statement that lists or removes files.
- **Grants are read, not assumed.** Grants to revoke come from
  `workspace.information_schema.volume_privileges` filtered to this volume,
  `inherited_from = 'NONE'`, and grantees other than the authorized principal. Grantee
  names are quoted with backticks in `REVOKE`.
- **Shared report logic.** The verification query is the last step of the setup script and
  the whole of the verify script; the setup adds only the `revogado` rows. Keep the two
  copies identical.
- **Non-overlapping order values.** This step uses `ordem` 110 to 190 so that its rows
  follow those of step 1 (10 to 80) when both reports are printed together.
- **String literals.** Dynamic statements that embed text use double-quoted literals
  around the single quotes; `''` is not an escaped quote in this dialect.
- **To confirm while implementing.** How the owner's schema-level `ALL PRIVILEGES` shows
  up in `volume_privileges` for the new volume, and the privilege names that view returns
  after `GRANT ALL PRIVILEGES ON VOLUME`. The `acesso_direto` check counts grantees, not
  privilege names, so it holds either way; adjust only the `detalhe` text if needed.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations.
