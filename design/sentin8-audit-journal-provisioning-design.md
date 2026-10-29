# sentin8 - Audit-Journal Provisioning Design (AUDJOUR)

> **Status**: Target state. This document defines how every shell-served
> service provisions its local audit journal - the `{leaf}.audit_journal`
> table the shell's boot-step-8c pusher drains to Sys's ingest API - and the
> authorization (`{leaf}-audit` m2m grants) that lets the push present its
> certificate to Sys.
>
> **Audience**: All agents and engineers adding or refreshing a service's
> audit-journal DDL. Per AGENTS.md this design precedes any implementation;
> code comments reference `design/sentin8-audit-journal-provisioning-design.md`
> §numbers.

---

## 1. Scope & Context

### 1.1 Problem

The audit pipeline (architecture-principles §6.8) is journal-first: each
service writes audit rows locally and a shell-spawned pusher drains them to
Sys `POST /v1/audit`. When the journal table is missing or stale, the
pusher's 5-second poll fails forever (5s poll + 2s backoff = one WARN every
~7s, unbounded), and - as the 2026-10-16 fleet investigation showed - this
is not a self-healing failure:

- **email8** never provisioned the table at all: every push fails
  `relation "audit_journal" does not exist` (42,163 WARNs in one service's
  log over 6 days). The leaf schemas (`mta`, `store`) carry the outbox only;
  `gate`/`access` have no leaf schema.
- **bill8** provisions a stale 9-column shape (`actor`/`subject_type`/
  `subject_id`/`detail`): every push fails `column "target_resource_type"
  does not exist` (19,016 WARNs/day across the six services).
  `CREATE TABLE IF NOT EXISTS` cannot converge an existing wrong-shaped
  table - the defect is permanent until the schema is recreated.
- **email8** additionally never declared its `{leaf}-audit` m2m grants, so
  `auth.m2m_scope_grants` holds no `mta-audit`/`store-audit`/`gate-audit`/
  `access-audit` rows - the pusher's `{leaf}-audit` certificate is minted
  but unenrollable (the no-grant class). Even with a table present, the
  push would 401 at Sys's scope gate.

### 1.2 The contract (why this is one design, not six fixes)

The single DDL contract lives in the SDK: `sentin8_audit::audit_journal_sql(
schema)` - 15 columns, a partial unpushed index, RLS enabled and forced, and
the `audit_journal_dml` policy. Every service mirrors this block into its own
`sql/` files (the WARN-class precedent: the SDK shape changed once, and every
mirrored init.sql had to be refreshed in the same change). The pusher resolves
the table UNQUALIFIED (`FROM audit_journal`) through the service role's
search_path, so **the journal must live in the schema that leads the role's
search_path** - the same leaf-schema layout the outbox uses.

## 2. Target State

### 2.1 Leaf-schema layout (email8)

```
email8 DB
├── email8 schema        - shared domain tables (unchanged)
├── mta schema           - mta.outbox (v3) + mta.audit_journal (v4, this design)
├── store schema         - store.outbox (v3) + store.audit_journal (v4, this design)
├── gate schema          - gate.audit_journal (v2, this design - first leaf object)
└── access schema        - access.audit_journal (v2, this design - first leaf object)
```

- Roles keep their existing search_paths (`mta, email8, public`,
  `store, email8, public`, `gate, email8, public`, `access, email8, public`)
  - the unqualified pusher SELECT/UPDATE resolves to `{leaf}.audit_journal`.
- gate/access `audit.sql` opens with `CREATE SCHEMA IF NOT EXISTS` because
  their leaf schemas hold nothing today.
- Grants mirror `outbox.sql`'s per-service block (`GRANT USAGE ON SCHEMA` +
  `GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA`), which covers the
  journal - the pusher reads/marks rows on the service's MAIN pool.

### 2.2 Shared-schema layout (bill8)

bill8 keeps its single-schema-per-service layout (`billing`, `ledger`,
`payments`, `reporting`, `risk`, `webhooks`); the six stale audit_journal
blocks are replaced with the canonical 15-column shape + RLS. The existing
grant block (`ALL TABLES IN SCHEMA`) covers the table. No migration code -
the stale live tables are dropped and recreated by `vertical init`
(greenfield; old audit rows are disposable dev data).

### 2.3 The canonical DDL (from `sentin8_audit::audit_journal_sql`)

```sql
CREATE TABLE IF NOT EXISTS {leaf}.audit_journal (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    env_id          UUID NOT NULL,
    action          TEXT NOT NULL,
    target_resource_type TEXT,
    target_resource_id    TEXT,
    actor_user_id   TEXT,
    actor_subject_type TEXT,
    severity        TEXT NOT NULL DEFAULT 'info',
    correlation_id  TEXT,
    before_state    JSONB,
    after_state     JSONB,
    details         JSONB,
    pushed          BOOLEAN NOT NULL DEFAULT false,
    pushed_at       TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_{leaf}_audit_journal_unpushed
    ON {leaf}.audit_journal (created_at) WHERE pushed = false;
ALTER TABLE {leaf}.audit_journal ENABLE ROW LEVEL SECURITY;
ALTER TABLE {leaf}.audit_journal FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS audit_journal_dml ON {leaf}.audit_journal;
CREATE POLICY audit_journal_dml ON {leaf}.audit_journal
    USING (sentin8_context_initialized() AND env_id = sentin8_current_env_id())
    WITH CHECK (sentin8_context_initialized() AND env_id = sentin8_current_env_id());
```

`env_id` is NOT NULL (the-era nullable shape is retired everywhere -
RLS requires the env comparison).

### 2.4 Authorization (the `{leaf}-audit` m2m grant)

Each service's registration declares:

```rust
M2mGrant {
    workload: "{leaf}-audit",
    scopes: &["sentin8:sys:audit:write"],
},
```

`vertical enroll` provisions the `auth.m2m_scope_grants` row from the
self-declaration (§4.14 registration-driven - the platform never hardcodes a
vertical's workloads). hotel8 (`pms-audit`) and bill8 (`billing-audit`) already
declare this row; email8's four services gain it in this change.

### 2.5 Migration versioning

| Service | Existing migrations | New migration |
|---|---|---|
| email8-mta | v1 init, v3 outbox | **v4 audit** (`sql/audit.sql`) |
| email8-store | v1 init, v3 outbox | **v4 audit** (`sql/audit.sql`) |
| email8-gate | (none - `sql_migrations: vec![]`) | **v2 audit** (`sql/audit.sql` + registration gains `sql_migrations`) |
| email8-access | v1 init | **v2 audit** (`sql/audit.sql`) |

The version numbers keep the never-reuse invariant (a version that ever
applied on a live DB must never apply different SQL).

## 3. Convergence (greenfield - no migration code)

Per AGENTS.md ("No migration code - this is a new platform"):

1. Drop the stale bill8 `audit_journal` tables on the live dev DBs.
2. `make build` the email8 + bill8 groups (the registrations carry the new
   migrations).
3. `sentin8-cli vertical init <group>` - the migration table tracks v4/v2;
   `CREATE TABLE IF NOT EXISTS` creates what is missing.
4. `sentin8-cli vertical enroll <group>` - provisions the four new
   `*-audit` scope rows.
5. Fleet restart; the pusher's first pass succeeds; the 7s WARN loop ends.

## 4. Failure Modes & Recovery

- **Pusher failure posture is unchanged**: a Sys outage only delays the push
  (rows stay in the journal; the pusher retries). What this design removes is
  the *permanent* failure classes (missing table, wrong shape, unenrollable
  workload).
- **Schema drift detection**: if a future SDK DDL change adds a column, the
  pusher fails with `column "…" does not exist` - the fix is always the
  greenfield re-init (§3), never ALTER-code. The WARN message names the
  column, so drift is diagnosable from the log alone.
- **RLS**: the journal is FORCE RLS with the env-pinned policy; the pusher
  sets tenant context before SELECT/UPDATE (the shell pusher already runs
  through the shared pool's context-setting path).

## 5. Open Questions

None for the provisioning scope. The pusher's 7s WARN cadence during a
permanent failure is noisy-but-visible (by design - fail loud); a
log-frequency cap belongs to the log-rotation work (item 4), not
to the audit plane.