---
name: repo-optimizer
description: Standardizes READMEs across all GitHub repositories of an account. Clones via gh, extracts the tech stack from composer.json/package.json/requirements.txt, writes README.md plus a German README.de.md following one canonical template with shields.io badges, splits long READMEs into docs/, and delivers everything as a draft pull request. Use when asked to optimize repos, unify READMEs, add tech stack badges, or clean up repository documentation.
---

# Repo Optimizer

Brings every repository to the same README standard, delivered as a **draft PR** so
the user reviews before anything reaches the default branch.

## Non-negotiable rules

1. **Documentation only.** Only `README.md`, `README.de.md`, `docs/` and `LICENSE`
   may change. `publish-repo.sh` enforces this and aborts on any other path — never
   work around that guard.
2. **Never commit or push to the default branch.** All work happens on the branch
   from `BRANCH_NAME` (`chore/readme-optimization`).
3. **Never invent content.** Every feature, command and version in a README must be
   backed by something `analyze-repo.sh` reported or by a file you actually read.
   Where you cannot verify a fact, write `<!-- TODO: verify -->` instead of guessing.
   A wrong install command is worse than a missing one.
4. **Preserve substance.** Existing README content gets restructured into the
   template, not deleted. Repo-specific knowledge (quirks, deploy notes, credentials
   hints) is the most valuable part of the old README — carry it over.
5. **Skip empty repos.** No detectable stack and no meaningful content → log it as
   skipped and move on. A badge row on an empty repo helps nobody.

## Prerequisites

The project uses its own token from `config/token.env`, not the global
`gh auth login`. If a script aborts with "No project token configured", tell the
user to set it up — do **not** work around it with `ALLOW_GLOBAL_GH_AUTH=true`
unless they explicitly ask:

```bash
cp config/token.env.example config/token.env
chmod 600 config/token.env
```

Never print the token value, and never read `config/token.env` into the
conversation. The scripts handle it; you do not need to see it.

## Workflow

### 1. Fetch

```bash
./scripts/fetch-repos.sh --dry-run          # review the list first
./scripts/fetch-repos.sh                    # clone + create branches
```

Reads `workspace/_manifest.json` afterwards — that is the work list. It carries per
repo: `name`, `isPrivate`, `defaultBranch`, `description`, `topics`, `status`, `path`.

Repos with `status: "dirty"` had uncommitted local work and were left untouched;
report them to the user rather than forcing them.

### 2. Process in batches

Work through `BATCH_SIZE` repositories (default 5), then stop and report before
continuing. Do not run all 98 repositories unattended.

Per repository:

```bash
./scripts/analyze-repo.sh <repo> > /tmp/analysis.json
```

Then:

1. Read the analysis. Note `manifestDir` — monorepos keep their manifests in a
   subdirectory (e.g. `laravel/`) and install commands must account for that.
2. Read the existing README in full, plus enough source to describe the project
   honestly (entry point, routes, main classes — whatever settles what it *does*).
3. Map dependencies to badges using `references/stack-detection.md` and
   `references/stack-badges.md`.
4. Write `README.md` following `references/readme-template.md`.
5. Write `README.de.md` — a real translation of the same structure, not a stub.
6. If `readme.needsDocsSplit` is true, apply `references/docs-split.md`.
7. Review the diff:

```bash
./scripts/publish-repo.sh <repo> --dry-run
```

### 3. Report and wait

After each batch, show the user a compact table: repo, detected stack, README lines
before → after, docs split yes/no, proposed description and topics. Then **wait for
approval**.

### 4. Publish

```bash
./scripts/publish-repo.sh <repo> \
  --meta \
  --description "One-line description" \
  --topics "laravel,filament,docker"
```

`--meta` also sets the GitHub description and topics. Most of these repositories
have an empty description, so propose one for every repo — derived from what the
code actually does, in English, under 120 characters, no trailing period.

Topics: 3–6 lowercase, hyphenated terms. Prefer the stack (`laravel`, `filament`,
`docker`) plus one domain term (`invoicing`, `timelapse`).

## Rollback

```bash
gh pr close --repo <owner>/<repo> <number> --delete-branch
```

## Configuration

`config/settings.env` (branch name, batch size, split threshold) and
`config/skiplist.txt` (one repo name per line, `#` comments, `*` globs).
Forks and archived repos are already excluded via `SKIP_FORKS` / `SKIP_ARCHIVED`.

## References

- `references/readme-template.md` — the canonical section structure (EN + DE)
- `references/stack-detection.md` — which manifest entry proves which technology
- `references/stack-badges.md` — technology → shields.io badge markdown
- `references/docs-split.md` — when and how to split a long README
