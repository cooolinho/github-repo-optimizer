# Script reference

[← Documentation index](INDEX.md)

## scripts/lib/common.sh

Sourced by the other scripts; not executable on its own.

| Function | Purpose |
|----------|---------|
| `log_info` / `log_ok` / `log_warn` / `log_error` | Colored logging to stderr |
| `die <msg>` | Log an error and exit 1 |
| `load_config` | Source `settings.env` and `settings.local.env`; environment wins |
| `require_cmd <cmd>…` | Abort unless every command exists |
| `load_token` | Parse `GH_TOKEN` out of `config/token.env` and export it for this process |
| `gh_token_scopes` | Read the token's OAuth scopes from the API response header |
| `check_token_scopes` | Warn about missing `repo` and about scopes the project never uses |
| `require_gh` | Abort unless `gh` and `git` exist, a token is configured, and GitHub accepts it |
| `is_skipped <repo>` | Match against `skiplist.txt`, glob-aware |
| `log_state <repo> <status> [details]` | Append a line to the audit log |

All logging goes to **stderr**, so `analyze-repo.sh` output can be piped into `jq`
without interference.

## scripts/fetch-repos.sh

Clones eligible repositories and puts them on the optimization branch.

```bash
./scripts/fetch-repos.sh [--dry-run] [--only <repo>] [--limit <n>] [--refresh] [-v]
```

Writes `workspace/_manifest.json`:

```json
{
  "generatedAt": "2026-09-06T03:14:02Z",
  "owner": "cooolinho",
  "branch": "chore/readme-optimization",
  "repositories": [
    {
      "name": "my-repo",
      "isPrivate": true,
      "url": "https://github.com/cooolinho/my-repo",
      "description": "",
      "defaultBranch": "main",
      "topics": [],
      "status": "ready",
      "note": "branch created",
      "path": "/…/workspace/my-repo"
    }
  ]
}
```

`status` is `ready`, `dirty` (uncommitted local changes, left untouched) or `error`.

## scripts/analyze-repo.sh

```bash
./scripts/analyze-repo.sh <repo-name | path>
```

Prints a JSON fact sheet to stdout.

| Field | Contents |
|-------|----------|
| `manifestDir` | Directory holding the manifests (`.` at root, `laravel` in a monorepo). Chosen by score, not by position — see below |
| `git` | Current branch, default branch, last commit date |
| `descriptions` | `description` from composer.json / package.json |
| `readme` | File, line count, detected language, headings, `needsDocsSplit` |
| `php` | PHP constraint, `require`, `require-dev`, resolved versions from `composer.lock` |
| `node` | Package manager, dependencies, devDependencies, scripts |
| `python` | Requirement lines from `requirements.txt` or `pyproject.toml` |
| `files` | Presence flags: Dockerfile, compose, `.env.example`, LICENSE, artisan, docs/ |
| `workflows` | GitHub Actions workflow filenames |
| `testRunners` | `phpunit`, `pest`, `pytest`, `vitest`, `jest` |
| `topLevel` | Top-level entries, directories marked with a trailing `/` |

Distinguish `php.require` (declared — justifies a badge) from `php.locked`
(resolved, includes transitive packages — use only for version lookup).

#### Manifest selection

A repository may hold several manifests, and the root one is not always the
application — `symfony-template` has a root `composer.json` declaring only
`laravel/homestead` while the real Symfony app lives in `symfony/`. Candidates
(root plus up to three levels down, excluding `vendor/` and `node_modules/`) are
therefore scored: a declared framework is worth +100, a `php` constraint +20, an
`autoload.psr-4` section +20, and each declared dependency +1 up to 30. The root
gets +1 as a tiebreaker, so single-project repositories are unaffected.

## scripts/publish-repo.sh

```bash
./scripts/publish-repo.sh <repo> [--dry-run] [--no-pr] [--meta]
                                 [--description <text>] [--topics <a,b,c>]
```

| Flag | Effect |
|------|--------|
| `--dry-run` | Show the staged diff, then unstage. Nothing is committed or pushed |
| `--no-pr` | Commit and push, but open no pull request |
| `--meta` | Apply `--description` / `--topics` via `gh repo edit` |

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Published, or nothing to do |
| `1` | Non-documentation changes present, wrong branch, or a missing prerequisite |

The whitelist check runs **before** anything is staged. If it fails, revert the
offending files and run again — do not bypass the guard.
