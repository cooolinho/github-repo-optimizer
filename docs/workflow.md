# Workflow

[← Documentation index](INDEX.md)

How one repository moves from clone to merged pull request.

## Overview

```
fetch-repos.sh          analyze-repo.sh         (Claude skill)         publish-repo.sh
     │                        │                        │                      │
 clone repo              read manifests           write README            commit (whitelisted)
 create branch      →    emit JSON facts    →     write README.de.md  →   push branch
 write manifest          detect monorepo          split docs/ if long     open draft PR
                                                                          set description/topics
```

## 1. Fetch

```bash
./scripts/fetch-repos.sh --dry-run   # review the list first
./scripts/fetch-repos.sh
```

For every eligible repository:

1. Clone into `workspace/<name>` (via `gh repo clone`, so private repos work), or
   refresh an existing clone
2. Check out `BRANCH_NAME`, creating it from the default branch if needed
3. Record the result in `workspace/_manifest.json`

**Repositories with uncommitted changes are never touched.** They are recorded with
`status: "dirty"` and skipped — local work is not at risk.

### Flags

| Flag | Effect |
|------|--------|
| `--dry-run` | List what would be fetched; clone nothing |
| `--only <repo>` | Process a single repository |
| `--limit <n>` | Process at most n repositories |
| `--refresh` | Hard-reset an existing clone to the remote default branch |

## 2. Analyze

```bash
./scripts/analyze-repo.sh my-repo | jq
```

Emits a JSON fact sheet: manifests, dependencies with resolved versions, test
runners, CI workflows, existing README length and language, top-level layout.

This is the evidence base. The skill is required to derive the README from it
rather than guessing.

**Monorepos:** `manifestDir` names the directory holding `composer.json` /
`package.json`. Several repositories keep theirs in `laravel/`; install commands
are adjusted accordingly.

## 3. Author

The skill writes `README.md` and `README.de.md` following
`.claude/skills/repo-optimizer/references/readme-template.md`, and splits into
`docs/` when the original exceeds the threshold.

## 4. Review

```bash
./scripts/publish-repo.sh my-repo --dry-run
```

Shows the staged diff and stops. Nothing is committed or pushed.

## 5. Publish

```bash
./scripts/publish-repo.sh my-repo --meta \
  --description "Short project description" \
  --topics "laravel,filament,docker"
```

1. Verifies the repository is on `BRANCH_NAME` — refuses to run on the default branch
2. Verifies every changed path is in the whitelist (`README.md`, `README.de.md`,
   `docs/`, `LICENSE`) — **aborts with exit code 1 otherwise**
3. Commits, pushes, opens a draft PR (or reuses an open one)
4. With `--meta`, sets the GitHub description and topics via `gh repo edit`

## Safety guarantees

| Guarantee | Enforced by |
|-----------|-------------|
| Source code is never committed | Path whitelist in `publish-repo.sh` |
| The default branch is never modified | Branch check before staging |
| Local work is never overwritten | Dirty-worktree check in `fetch-repos.sh` |
| Nothing merges without review | Pull requests are opened as drafts |
| Every action is recorded | `state/optimization-log.jsonl` |

## Rollback

A single repository:

```bash
gh pr close --repo cooolinho/my-repo <number> --delete-branch
```

Everything published so far:

```bash
gh pr list --author "@me" --search "docs: standardize README" --json number,url
```

Locally, the branch is just a branch — `git checkout main && git branch -D chore/readme-optimization`
inside `workspace/<repo>` discards it.

## Audit trail

`state/optimization-log.jsonl` holds one JSON object per action:

```json
{"timestamp":"2026-09-06T03:14:02Z","repo":"my-repo","status":"fetched","details":"branch created"}
```

Statuses: `fetched`, `fetch-skipped`, `fetch-failed`, `publish-skipped`,
`publish-blocked`, `published`.

```bash
# Everything published so far
jq -r 'select(.status=="published") | "\(.repo)  \(.details)"' state/optimization-log.jsonl

# Anything blocked by the whitelist
jq -r 'select(.status=="publish-blocked")' state/optimization-log.jsonl
```
