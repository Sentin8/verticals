# sentin8 - History Wipe Design (HIST): single-commit repos before going public

> Operations design of record for removing all commit history from every
> repository in the tree. Scope: ALL 100 git repositories on disk (root
> aggregation, 8 group folders' children, platform, verticals, health8)
> plus the fresh `sentin8-ci` repo. Executed by
> `sentin8/sentin8-ci/scripts/wipe-history.py`; the operator runs it once,
> before the repositories go public.

## 1. Problem & goal

The repositories are about to become public. Their existing histories
(2 - 16 commits each, ~40 MiB total) contain internal ticket references,
operator notes, and iteration noise that must not ship with the public
repos. The published state must look like a single fresh import:

- every repo has EXACTLY ONE commit on `main`,
- the commit message is verbatim:
  `Sync from SVN and remove client/project-related code.`,
- the commit content is the repo's current working tree (uncommitted
  WIP - fdx docs, auth DESIGN.md, e2e fixtures, the generated CI callers
  - folds into the snapshot, per the owner's decision),
- the tag graph the Cargo pins resolve through stays functional.

## 2. Constraints discovered (drive the design)

1. **Cargo pins resolve through tags, and `Cargo.lock` bakes the tag's
   commit rev** (`git+…?tag=sdk-v0.6.3#d9ad360c…`). Wiping history moves
   every tag target; a lockfile left with the old rev breaks
   `--locked` builds the moment the new tags are fetched.
2. **18 tags are pinned** across 13 SDK repos (`sdk-v0.6.3`, the
   `{svc}-sdk-v*` mini-facade pins - including ai's stale `*-sdk-v0.2.0`
   set - and the six `{vertical}-v0.5.3` facades). 95 further tags are
   unpinned history and are dropped with it.
3. **Stale pins jump content by design decision**: re-creating a pinned
   tag on the snapshot means e.g. ai's `cron-sdk-v0.2.0` now resolves to
   the same content as `cron-sdk-v0.6.2` - the versions converge on the
   single commit; accepted by the owner (the pins were stale drift
   anyway).
4. **Lock rewrite must precede the snapshot commit** (the lock IS part
   of the commit), and the snapshot SHA is final only after commit - so
   repos are wiped in **DAG order**: a repo's locks may only reference
   the new revs of upstream SDK repos already snapshotted
   (sdk → cross-pinned facades → vertical SDKs → services).
5. **Force-push keeps old commits reachable on GitHub** (PRs, caches,
   ~30-day GC) - accepted by the owner; full purge would require
   deleting + re-creating each repo (out of scope; the local backup
   outside the tree is the safety net).

## 3. The wipe (per repo)

```mermaid
flowchart TD
    A[pre-flight assertions<br/>tracked-ignored = none,<br/>node_modules ignored,<br/>push auth OK] -> B{repo has pins?}
    B - yes -> C[assert every pinned SDK<br/>already snapshotted]
    B - no -> D
    C -> D[rewrite Cargo.lock git-source revs<br/>old → new via the map]
    D -> E[checkout -orphan + clear index<br/>+ add -A → index == worktree]
    E -> F[commit 'Sync from SVN and remove<br/>client/project-related code.']
    F -> G[delete old main, rename orphan → main]
    G -> H[delete ALL tags,<br/>re-create this repo's pinned tags]
    H -> I[reflog expire + gc -prune=now]
    I -> J[record new SHA + tags in the map]
    J -> K[push: -force main,<br/>new tags, delete stale remote tags]
    K -> L[verify: 1 commit, message,<br/>tags, lock revs, remote refs]
```

- The index is cleared before `add -A`, so the snapshot is exactly the
  worktree minus gitignored paths (`target/`, `build/`, `node_modules/`,
  `.run/`, `.tmp/`); the assertion pass guarantees no tracked-but-ignored
  file silently disappears.
- `sentin8-ci` (never git-initialized) gets `git init -b main` + the
  same first commit; `health8` (outside the new-tree plan but present
  on disk) gets the same wipe.

## 4. Ordering & recovery

- Order: backup tarball (all `.git` dirs, outside the tree) → pilot
  (`sentin8-sdk` alone) → full DAG sweep → push sweep → verify sweep.
- Every step appends to a run log under `.tmp/`; any repo whose
  assertions fail aborts the run BEFORE any mutation (the script is
  idempotent per repo: re-running after a partial failure resumes).
- Recovery = restore the repo's `.git` from the tarball and re-run.

## 5. Post-conditions

1. Every repo: `git rev-list -count main` = 1; message exact; worktree
   clean.
2. Tag set per repo = its pinned tags, all pointing at the snapshot.
3. Every `Cargo.lock` git-source rev matches the pushed tags; spot
   `cargo update` + build on a consumer resolves cleanly from the
   remotes.
4. Remote `main` + tags on GitHub match the local snapshot state.

## 6. Out of scope

- GitHub-side purge of unreachable old commits (delete-and-recreate the
  repos, or GitHub Support) - the owner chose force-push.
- Any content changes: the wipe folds the tree as-is; the lint-debt and
  stale-pin normalization stories stay in the backlog.