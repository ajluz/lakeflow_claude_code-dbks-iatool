# Implementation Plan: Medallion Schemas with Restricted Access

**Branch**: `001-medallion-schemas` | **Date**: 2026-10-10, revised 2026-10-11 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-medallion-schemas/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Create the `bronze`, `silver` and `gold` schemas in the `workspace` catalog of the
Databricks Free Edition workspace, owned by and accessible only to
`arthur.luz@dataslight.com.br`, with a setup that can be run again safely.

Technical approach, from [research.md](research.md): one idempotent SQL script written as
a SQL scripting compound statement. It checks its preconditions before changing anything,
creates each schema if missing, sets its description, grants full control to the owner,
and revokes any other direct grant it finds in the information schema. A second, read-only
script returns a pass/fail verification report on demand. Access inherited from the
catalog is reported and left unchanged.

**Revisions of 2026-10-11**: the plan follows the repository layout of constitution
v1.5.0. Code is split by purpose: `src/` for the deployed pipeline and `explorations/` for
auxiliary code, with setup scripts in `explorations/setup/`. The scripts were implemented
in a top-level `setup/` folder and then moved to `src/setup/` under v1.4.0; their location
is now `explorations/setup/`. Only the location changes. No behavior, contract or
requirement changes.

## Technical Context

**Language/Version**: Databricks SQL with SQL scripting (`BEGIN ... END`, `FOR`, `IF`,
`EXECUTE IMMEDIATE`, `SIGNAL`); observed working on DBSQL 2026.38

**Primary Dependencies**: Unity Catalog; a serverless SQL warehouse (auto-detected by the
CLI); Databricks CLI v1.11.0 to run the scripts

**Storage**: Unity Catalog metadata only: three schemas, their owner, description and
grants. No tables, volumes or files

**Testing**: the read-only verification script plus the manual scenarios in
[quickstart.md](quickstart.md). No test framework

**Target Platform**: Databricks Free Edition workspace `dbc-7e0f02e0-ff06`, catalog
`workspace`

**Project Type**: environment setup scripts for a data pipeline project

**Performance Goals**: setup and verification each finish in under 1 minute; the whole
path from missing schemas to a verified environment in under 5 minutes (SC-005)

**Constraints**: repeatable; never drops a schema or object; changes nothing outside the
three schemas; CLI profile always passed explicitly; runs only as the authorized principal

**Scale/Scope**: 3 schemas, 1 authorized identity, 2 SQL files, 1 documentation update

No item is marked NEEDS CLARIFICATION. Facts about the target environment were read from
it on 2026-10-10 and are recorded in [research.md](research.md).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v1.5.0.

| Principle / section | Applies | Result | Notes |
|---|---|---|---|
| I. Medallion Architecture | Yes | PASS | Creates exactly the three layer schemas the principle names, in `workspace`. No dataset is created, so the read-direction and `quality` property rules have nothing to check yet. |
| II. SQL-Only Declarative Pipelines | In spirit | PASS | The principle binds pipeline source. This is environment setup, not a pipeline dataset, but it is written in SQL only and adds no Python. |
| III. Data Quality Through Expectations | No | N/A | No dataset, no rows, no quality rule. |
| IV. Quarantine, Never Silently Discard | No | N/A | No data is processed. |
| V. Dataset Types and Flows | No | N/A | No dataset or flow. |
| VI. Record Source and Hash Keys in Silver | No | N/A | No silver table is created. |
| VII. Kimball Dimensional Modeling in Gold | No | N/A | No gold table is created. |
| Constraints: catalog and schemas | Yes | PASS | One catalog, `workspace`; schemas `bronze`, `silver`, `gold`; no other catalog referenced. |
| Constraints: landing zone | No | N/A | The `landing` volume is a later step. |
| Constraints: repository layout | Yes | PASS | Both scripts are auxiliary code (the pipeline does not need them deployed to run) and live in `explorations/setup/`, the folder the layout rule names for initial setup. Nothing is added under `src/`. |
| Constraints: naming | Yes | PASS | Schema names are lowercase; report columns and check names are Portuguese snake_case. |
| Constraints: data | Yes | PASS | No data is loaded. |
| Constraints: CLI | Yes | PASS | Every command takes `--profile`; no profile is stored in a script. |
| Workflow: consult `databricks-pipelines` skill | No | N/A | No pipeline code. `databricks-core` governs the CLI usage here. |
| Workflow: completion gates 1 to 5 | No | N/A | They concern pipeline updates, expectations, keys and facts. |
| Workflow: completion gate 6 (documentation) | Yes | PLANNED | `doc/getting-started.md` and `doc/README.md` are updated as part of this feature (FR-014). |
| Workflow: destructive actions need approval | Yes | PASS | The setup never drops anything. The quickstart's re-creation test drops one empty schema and is run by the owner. |

**Gate result (pre-research)**: PASS, no deviations.

**Gate result (post-design)**: PASS, no deviations. The design in
[data-model.md](data-model.md) and
[contracts/setup-and-verify.md](contracts/setup-and-verify.md) stays SQL-only, touches only
the three schemas, leaves catalog grants alone, and places its code in `explorations/setup/`.

## Project Structure

### Documentation (this feature)

```text
specs/001-medallion-schemas/
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
explorations/                   # auxiliary code
├── setup/                      # initial environment setup, run by hand, in step order
│   ├── 01_schemas.sql          # creates the schemas and applies the access rule
│   └── 01_schemas_verify.sql   # read-only verification report
├── functions.py                # unchanged
├── user_case.ipynb             # unchanged
└── clean_up_env.ipynb          # unchanged

src/                            # project code (the pipeline); nothing from this feature

doc/
├── getting-started.md          # prerequisites point to explorations/setup/
└── README.md                   # repository layout lists explorations/setup/

databricks.yml                  # unchanged
```

**Structure Decision**: the schema scripts are auxiliary code and live in
`explorations/setup/`, numbered by project step, as the constitution's repository layout
prescribes. `src/` is reserved for the deployed pipeline, so this feature adds nothing
there. Later setup steps (landing volume, calendar table) can be added as `02_`, `03_`.

**Relocation of what is already built**: the two scripts are today in `src/setup/`.
Bringing the feature into compliance means:

1. move `src/setup/01_schemas.sql` and `src/setup/01_schemas_verify.sql` to
   `explorations/setup/` with `git mv`, content unchanged, and remove the empty
   `src/setup/` folder (and `src/`, if nothing else is in it);
2. update the run commands in the header comments of both scripts;
3. update the paths in `doc/getting-started.md` and `doc/README.md`;
4. run the verification script from its new path and confirm 12 `PASS` rows.

Nothing changes in the workspace: the schemas already exist and are compliant.

**Out of scope**: `doc/` still describes `code_tips/`, which is no longer in the
repository. That does not belong to this feature.

## Design Notes for Implementation

These carry the decisions of [research.md](research.md) into the task phase.

- **One statement per file.** The setup script is a single compound statement and the
  verify script is a single `WITH ... SELECT` query, so each runs the same way from the
  CLI and the SQL editor. A plain query cannot change anything, which makes the verify
  script read-only by construction.
- **Constants first.** The catalog, the three schema names with their descriptions, and
  the authorized principal are declared once at the top of each script.
- **Check, then change.** All three preconditions of the contract are evaluated for all
  three schemas before the first `CREATE`.
- **Grants are read, not assumed.** Grants to revoke come from
  `workspace.information_schema.schema_privileges` filtered to `inherited_from = 'NONE'`
  and to grantees other than the authorized principal. Grantee names are quoted with
  backticks when used in `REVOKE`, since group names contain spaces and punctuation.
- **Shared report logic.** The verification query is the last step of the setup script and
  the whole of the verify script. Keep the two copies identical; the setup adds only the
  `revogado` rows.
- **Confirmed in implementation.** The information schema reflects a `REVOKE` within the
  same compound statement, so the setup's final report shows the state after revoking.
- **String literals.** Spark SQL does not treat `''` as an escaped quote; dynamic
  statements that embed text use double-quoted literals around the single quotes.
- **Test principal.** A stray grant for testing goes to `account users`. The
  workspace-local `users` group is not a Unity Catalog principal and the system
  workspace-users group cannot receive schema grants.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations. The deviation recorded in the first version of this plan (a top-level
`setup/` folder not listed in the repository layout) no longer applies: constitution
v1.5.0 names `explorations/setup/` for these scripts.
