# sentin8.new — Repository-Split Workspace

This directory holds the **target state** of the platform after the
repository split defined in `design/sentin8-repository-split-design.md`.

The original monorepo (`../sentin8/`) is the read-only **source of truth**
during migration — nothing in it is modified.

## Layout — seven group folders (RS §4.4)

```
sentin8.new/
├── sentin8/          # platform group — OWNS the docker infra (§2.2.1)
│   ├── docker-compose.yml   # THE tree-wide dev PG 18 + Valkey
│   ├── Makefile · README.md · DESIGN.md · BUSINESS.md
│   ├── sentin8-sdk/         # the shared workspace (tag sdk-v0.1.0)
│   ├── sentin8-cli/ · sentin8-captain/        # starters
│   ├── sentin8-{svc} × 17                    # platform services
│   └── sentin8-flutter/ · apps · e2e · packaging
├── bank8/    Makefile · README · DESIGN · BUSINESS · bank8-sdk · 6 services · 4 apps
├── hotel8/   … 6 services · 6 apps
├── trade8/   … 6 services · 1 app
├── bill8/    … 8 services · 4 apps
├── email8/   … 4 services · 1 app
├── exchange8/ … 14 services · 1 app
├── design/           # the split's design of record
└── Makefile · backlog.md   # aggregation + split backlog
```

Group folders are **plain directories** — every child is an independent
git repository named `{vertical}-{service}`. Vertical groups carry no
compose files; they consume the platform's infra over localhost.

## Dev quickstart

```bash
make infra-up       # PG 18 + Valkey (delegates to sentin8/)
make build          # the whole tree, DAG order
# or group-scoped:
cd sentin8 && make build
cd bank8 && make build
# or a single repo (no group, no siblings needed):
cd sentin8/sentin8-auth && cargo build
```

## Single-repo dev story

Clone any one repo; `cargo build` fetches the SDK git tags
(`sentin8-sdk` + the vertical's `{v}-sdk`) and builds — no sibling
checkouts, no platform tree, no live DB (committed `.sqlx` caches).

---

**Architecture & Design:** sentin8.new and its underlying concepts were designed by [Hamid Jahanzad](https://www.linkedin.com/in/hamidjahanzad/).
