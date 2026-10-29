# OBVERT - OpenFin8: the open-finance vertical split

> Status: **PROPOSED** (OBVERT-1) - the design for extracting the
> open-banking (open finance) services from the bank8 vertical into
> their own vertical, **OpenFin8** (GitHub org:
> [OpenFin8](https://github.com/OpenFin8)). Companion to the OBARCH
> design set ( ..5, in the open-core/us/ca/uk repositories).
> Reading order: this document, then the per-country adapter designs.

## 1. Motivation: why a separate vertical

**The standards shifted from open banking to open finance.** Every
jurisdiction this platform serves has moved (or is moving) past
banking-only data sharing:

| Jurisdiction | Evidence | Consequence |
|---|---|---|
| US | FDX 6.0 added payroll data structures; the 2026 initiative targets open finance + agentic AI data sharing | The US data holder increasingly serves **non-banking** data (payroll) |
| UK | OBL's successor ("Future Entity") is chartered for Open Finance/Smart Data | UK layer will outgrow ASPSP-only semantics |
| BR | Open Finance phases 4-5 (investments, insurance, pensions) are live | A Brazilian adapter's data sources extend beyond `bank8:Ledger` on day one |
| EU | The Berlin Group's successor IS the "openFinance API Framework" | The standard itself is named for the umbrella |
| AU | CDR is sector-agnostic by legislation (energy, telco, non-bank lending) | The consent regime was never banking-shaped |

**The architectural consequence**: the open-finance layer's *data
sources* are becoming cross-sector, and banking is merely its first
sector. A layer whose provider adapters increasingly reach beyond
`bank8:Ledger` does not belong inside the `bank8` vertical group -
otherwise every new data domain (payroll, investments, insurance)
either lands as an awkward cross-vertical dependency or bloats bank8's
boundaries. Splitting makes bank8 the *first customer* of OpenFin8
rather than its container.

**The strategic consequence**: the recipient plane becomes
independently sellable. Today a recipient-only fintech (no bank, no
ledger) must enroll the bank8 vertical to get the connection registry;
after the split, OpenFin8 stands alone - and bank8 (or health8, or
any vertical) composes it when its institution plays the provider
role.

**Why now is the right time:**

1. **The institution-agnostic contract already exists** (fdx DESIGN
 §1, preserved in open-core): "either institution may run Sentin8
 or any other technology - nothing in the consent contract may
 assume both sides share a platform." The adapters consume
 Ledger/Payments via **public APIs only** - no intra-vertical
 shortcut exists to unwind. The split is registry/catalog/database
 work, not a code rewrite.
2. **The Profile refactor collapsed the rename cost** :
 every identity string derives from one `Profile` struct per
 adapter. The fdx→open rename was a 218-string sweep; a vertical
 rename is a Profile field change + registration scope sets +
 catalog + app `serviceName`s. The playbook is rehearsed.
3. **bank8-open-uk is still a skeleton** (unbuilt). Splitting
 before the UK adapter's implementation means the largest remaining
 build lands directly in its final home and is never renamed.

## 2. Naming and Identity

| Layer | bank8 (today) | OpenFin8 (after) |
|---|---|---|
| Vertical name | (nested in bank8) | **openfin8** (`{domain}8` convention) |
| GitHub org | Bank8-dev | **OpenFin8** (exists; created 2026-10-28) |
| Kernel lib repo | `Bank8-dev/bank8-open-core` | `OpenFin8/openfin8-core` |
| Adapter repos | `Bank8-dev/bank8-open-{ca,us,uk}` | `OpenFin8/openfin8-{ca,us,uk}` |
| Service types | `bank8:open-ca` etc. | **`openfin8:ca`** etc. |
| Shell identity | `Sentin8Shell::new("bank8:open-ca", "BANK8_OPEN_CA")` | `("openfin8:ca", "OPENFIN8_CA")` |
| Env prefix | `BANK8_OPEN_CA_*` | **`OPENFIN8_CA_*`** |
| Database (DBX §6.6 database-per-vertical) | `bank8` (schema `open_ca`) | **database `openfin8`** (schema-per-service: `openfin8_ca`, `openfin8_us`, `openfin8_uk`) |
| Event families | `bank8:open-ca:*` | **`openfin8:ca:*`** (vertical:resource:operation) |
| OAuth scopes | `bank8:open-ca:consents:read` | **`openfin8:ca:consents:read`** |
| Stream family / workload | `open-ca` | `openfin8-ca` |
| Admin UI flag | `open-ca` | `openfin8-ca` |
| Pin tag (lib) | `bank8-v*` | **`openfin8-v*`** |

**Naming rationale**: "open banking" is open finance's banking
subset; the vertical owns the umbrella so the BR (investments) and
AU (energy/telco) families need no second rename. The `Profile`
struct in `openfin8-core` gains the new values once; the adapters'
`Profile::canada` / `::united_states` constructors are the only
code that changes.

## 3. What moves vs. what stays

| Artifact | Disposition |
|---|---|
| `bank8-open-core` (kernel library) | **moves** → `openfin8-core` (repo transfer to OpenFin8 org; crate rename `bank8_open_core` → `openfin8_core`) |
| `bank8-open-ca`, `bank8-open-us`, `bank8-open-uk` | **move** → `openfin8-{ca,us,uk}`; binaries/service-types per §2 |
| SQL (15 kernel tables + producers) | **moves** to the `openfin8` database, schema-per-service (`openfin8_ca` etc.) - fresh `vertical init` |
| `bank8:fdx` PG role grants in the bank8 DB | retired with the bank8 schema drop |
| The bank8 `catalog.json` open-* entries | **removed**; new `openfin8/catalog.json` (group root) |
| ebank/efintech `serviceName: 'bank8-open-ca'` | → `'openfin8-ca'` (BFF route); ebank consent dashboard stays a bank8 app |
| **efintech app repository** | **phase-2 candidate**: the recipient app naturally belongs to OpenFin8 (a fintech app, not a bank app) - deferred one release to bound the blast radius (it is the only change that touches an app's git origin) |
| Ledger/Payments | **stay in bank8** - the provider adapters already consume them via public APIs over mTLS workloads (`openfin8-ca-ledger`, `openfin8-ca-payments` workload grants re-register under the new identity) |
| Auth integration (PAR/DPoP/grant-seed) | **unchanged** - Auth is platform-level; consent providers re-enroll under the new service types |
| `sys.services` enablement | **unchanged mechanism** - per-env enablement of `openfin8:*` rows; the `sentin8:sys:service:updated` consumer pattern persists |
| Sentin8:Bus consumer groups | renamed (`openfin8:ca:envinit` etc.) - the neutral `open-banking:*` consts in the kernel become `openfin8:{xx}:*` per-adapter data |

**What does NOT change conceptually**: the two-ledger model, the
consent middleware chokepoint, CSDF minimization, the Profile
parameterization, the spec-publication policy, and every
design invariant in the OBARCH set. The split is a **re-homing**,
not a redesign.

## 4. The Migration Inventory (OBVERT-2)

The rehearsed playbook, in order:

1. **Kernel rename + transfer**: `bank8-open-core` → `openfin8-core`
 (crate, repo, org transfer; pin tag `openfin8-v0.1.0`). Profile
 struct field values updated; `bank8` facade dep remains (the
 kernel calls Ledger/Payments contracts through `bank8::ledger`/
 `bank8::payments` clients - a cross-vertical SDK dependency,
 the same pattern every vertical uses for cross-vertical reads).
2. **Adapter renames**: `bank8-open-{ca,us,uk}` → `openfin8-{ca,us,uk}`
 - repo transfers + Profile constructors + registration scope sets
 (`bank8:open-ca:*` → `openfin8:ca:*`) + service types + `main.rs`
 shell identities + Makefile `SERVICE_TYPES`/`BOOT_PIN` + CI pin
 bumps to `openfin8-v*` tags.
3. **Vertical bootstrap**: `openfin8/` group root (catalog.json,
 root Makefile/README/BUSINESS/DESIGN per the house per-vertical
 template), `vertical init` (new `openfin8` database), `vertical
 enroll` per adapter.
4. **bank8 cleanup**: remove open-* entries from `bank8/catalog.json`;
 drop the `open_ca`/`open_us` schemas from the bank8 database
 (migration window: back up `fdx`/`open_ca` rows if any deployment
 carries live consents); bank8 BUSINESS.md capability block 3
 becomes "Open banking - delivered by the OpenFin8 vertical
 (composed provider role)".
5. **App retargets**: ebank/efintech/admin `serviceName` strings +
 scope whitelists (`bank8:open-ca:*` → `openfin8:ca:*`); e2e
 fixtures/global-setup service names; efintech repo transfer
 deferred to phase 2.
6. **Docs/site/org**: bank8-site products/reference sections for the
 open services move to an OpenFin8 site (or the site engine learns
 a second vertical - decided at implementation); bank8.github org
 profile table drops the OpenCore/OpenCA/OpenUS/OpenUK rows; the
 OpenFin8 org gains its own `.github` profile. **The site's
 open-ca spec/doc pages must be regenerated from the
 renamed repos** (harvest pipeline - see the site-engine notes).
7. **Tags/CI**: `Bank8-dev/bank8-open-*` repos archived after
 transfer (GitHub redirects preserved); sentin8-ci sync run for
 the new repos; dependabot on the new org.

**Sequencing note**: (the UK adapter implementation) starts
AFTER the split - it lands as `openfin8-uk` and is never renamed.

## 5. Cross-Vertical Composition Contract

The one new *architectural* artifact the split creates: the
provider-role composition. bank8 (or any vertical) composes OpenFin8
by:

1. Enabling the provider adapter (`openfin8:ca`) in the bank's env
 (`sys.services` row, `enabled=true`).
2. The adapter's workload grants (`openfin8-ca-ledger`,
 `openfin8-ca-payments`) hold scopes **owned by bank8 services**
 (`bank8:ledger:accounts:read`) - the scope-mirror policy sets
 enroll per-adapter; the platform's scope registry has no
 vertical-boundary concept, which is exactly what makes this work.
3. The bank's customer-facing surfaces (ebank consent dashboard)
 reach the adapter through BFF `serviceName` - same mechanism as
 any service call.

**Invariant to add (OBVERT invariant)**: OpenFin8 services must
never import bank8's *database* or internal schemas - only the
public API + SDK-contract surface. (Already true; the invariant
makes the boundary auditable.) Conversely, bank8 never imports
openfin8 internals: the ebank app calls by service name only.

## 6. Costs, Risks, Deferrals

- **One more identity rename** (~a day of mechanical sweeps; the
 218-string fdx→open sweep is the rehearsal). The alternative -
 keeping `bank8:*` service types inside a non-bank vertical group -
 is a naming lie we avoid.
- **Database migration** for any deployment with live consents
 (bank8 DB `open_ca` schema → openfin8 DB). Pre-production: near
 zero. Otherwise: one bounded migration window with row backup.
- **GitHub repo transfers** preserve redirects; old `Bank8-dev`
 pins in *unmigrated* clones break until `cargo update` - the
 normal tag-bump discipline.
- **Deferred**: efintech repo transfer (phase 2); OpenFin8's own
 website (bank8-site carries the pages until then); BR/EU/AU
 adapters (unchanged roadmap - they now land in the final home
 directly).

## 7. Open Questions

- **Site strategy**: does bank8-site grow a second vertical's
 sections (site.json `units` already carry per-unit org/repo), or
 does OpenFin8 get `openfin8-site` (reusing the sentin8 site
 engine)? Leaning: keep one site per vertical group (matches the
 org-per-vertical repo layout), i.e. a new `openfin8-site` seeded by
 `new-site.mjs` - but the harvest resolution order (sibling repo
 first) means the tree layout gains an `openfin8/` group root
 either way.
- **Vertical-registry admin scopes**: `openfin8:admin` scope
 vocabulary registered via the OpenFin8 group's registry file -
 confirm the CLI's `vertical init` accepts an already-running
 platform (it does per AGENTS.md §"vertical init per-vertical
 database + SQL" - the split is a normal second vertical).
- **Tag namespace**: `openfin8-v*` for the kernel; adapters do not
 pin the kernel by org-relative path (git tag pins are
 org-qualified URLs, so the transfer is transparent to Cargo).

---

**Architecture & Design:** the OpenFin8 vertical split (OBVERT) was
designed by [Hamid Jahanzad](https://www.linkedin.com/in/hamidjahanzad/).