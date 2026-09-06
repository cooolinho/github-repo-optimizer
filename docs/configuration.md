# Configuration

[← Documentation index](INDEX.md)

## config/settings.env

Sourced by every script. **Environment variables win over the file**, so a one-off
override needs no edit:

```bash
BATCH_SIZE=1 ./scripts/fetch-repos.sh
```

For permanent local changes that should not be committed, create
`config/settings.local.env` — it is gitignored and sourced after `settings.env`.

| Variable | Default | Description |
|----------|---------|-------------|
| `GH_OWNER` | `cooolinho` | GitHub account whose repositories are processed |
| `BRANCH_NAME` | `chore/readme-optimization` | Feature branch created in every repository |
| `WORKSPACE_DIR` | `workspace` | Clone target, relative to the project root |
| `BATCH_SIZE` | `5` | Repositories processed before asking for approval |
| `SKIP_FORKS` | `true` | Exclude forked repositories |
| `SKIP_ARCHIVED` | `true` | Exclude archived repositories |
| `DOCS_SPLIT_THRESHOLD_LINES` | `250` | README length that triggers a `docs/` split |
| `REPO_LIST_LIMIT` | `300` | Upper bound for `gh repo list` |
| `COMMIT_MESSAGE` | `docs: standardize README …` | Commit message used when publishing |
| `PR_TITLE` | `docs: standardize README` | Pull request title |

## config/token.env

Holds the GitHub token for this project. Created from `token.env.example`,
gitignored, and never sourced — only the `GH_TOKEN` line is parsed out.

```
GH_TOKEN=ghp_your_token_here
```

| Variable | Description |
|----------|-------------|
| `GH_TOKEN` | The token used for every `gh` and `git` operation in this project |

An inherited `GH_TOKEN` from the environment takes precedence over the file, which
is what makes CI work without one. See [Setup](setup.md#authentication) for the
full resolution order and the reasoning behind not using `gh auth login`.

| Related variable | Default | Description |
|------------------|---------|-------------|
| `ALLOW_GLOBAL_GH_AUTH` | `false` | Set to `true` to fall back to the global `gh auth login` identity when no project token is configured |

## config/skiplist.txt

One repository name per line. `#` starts a comment. Glob patterns are supported.

```
# Work in progress — leave alone
experimental-thing

# Everything starting with test-
test-*

# Anything ending in -archive
*-archive
```

Matching happens in Bash, so the patterns behave exactly like shell globs.

### Skip list vs. skip flags

`SKIP_FORKS` and `SKIP_ARCHIVED` filter by repository metadata from the GitHub API.
The skip list filters by name. They are independent — a fork listed by name is
excluded either way.

## What is excluded by default

Of 104 repositories on the reference account, 98 are eligible: the 6 forks are
excluded by `SKIP_FORKS=true`. Repositories with no detectable stack **and** no
meaningful content are skipped by the skill at authoring time, not by the scripts —
they still get cloned so their content can be assessed.
