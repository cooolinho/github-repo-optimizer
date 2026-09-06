# Setup

[← Documentation index](INDEX.md)

## Prerequisites

| Tool | Purpose | Check |
|------|---------|-------|
| [`gh`](https://cli.github.com/) | Repository listing, cloning, PRs | `gh --version` |
| `git` | Version control | `git --version` |
| [`jq`](https://jqlang.github.io/jq/) | JSON parsing | `jq --version` |
| Bash 4+ | Scripts use arrays and `mapfile` | `bash --version` |

Install on Debian/Ubuntu:

```bash
sudo apt update && sudo apt install gh git jq
```

## Authentication

This project deliberately avoids `gh auth login`.

`gh auth login` stores credentials in `~/.config/gh/hosts.yml`. That is a
**machine-wide** identity: every `gh` command you run afterwards, in any project,
uses it. A tool that rewrites 98 repositories should not be running under the same
broad token you use for everyday work.

Instead, the token is configured per project and injected as an environment
variable for the lifetime of one script run.

### Why GH_TOKEN

`gh` resolves credentials in this order:

1. `GH_TOKEN` / `GITHUB_TOKEN` from the environment
2. `~/.config/gh/hosts.yml` (what `gh auth login` writes)

Because the environment wins, exporting `GH_TOKEN` inside a script overrides the
stored login **without reading or modifying it**. You can hold a broad personal
token globally and a narrow one for this project simultaneously; neither affects
the other.

You can see which one is in play:

```bash
gh auth status
# ✓ Logged in to github.com account cooolinho (GH_TOKEN)
# ✓ Logged in to github.com account cooolinho (/home/you/.config/gh/hosts.yml)
```

The source is named in parentheses.

### Setting up the project token

```bash

cp config/token.env.example config/token.env
cp config/settings.env config/settings.local.env
cp config/skiplist.txt.example config/skiplist.txt

chmod 600 config/token.env
chmod 600 config/settings.local.env
chmod 600 config/skiplist.txt

```

Edit `config/token.env`:

```
GH_TOKEN=ghp_your_token_here
```

Edit `config/settings.local.env`:

```
GH_OWNER=your_github_username
```

That file is gitignored and must never be committed.

### How the file is read

`load_token()` in `scripts/lib/common.sh` **greps** the `GH_TOKEN` line rather
than sourcing the file:

```bash
grep -E '^[[:space:]]*GH_TOKEN[[:space:]]*=' "$token_file" | tail -1 | sed 's/^[^=]*=//'
```

Sourcing would execute anything in the file. Since this file holds a credential and
may be edited in a hurry, parsing is the safer contract — a stray line cannot turn
into a command.

The file mode is checked too. Anything other than `600`-style permissions produces:

```
[warn]  config/token.env is readable by others (mode 644).
[warn]  Fix with: chmod 600 config/token.env
```

### Resolution order

| Priority | Source | Use case |
|----------|--------|----------|
| 1 | `GH_TOKEN` already in the environment | CI, or a one-off override |
| 2 | `config/token.env` | Normal local use |
| 3 | Global `gh auth login` | Only with `ALLOW_GLOBAL_GH_AUTH=true` |

A one-off run with a different token needs no file edit:

```bash
GH_TOKEN=ghp_other_token ./scripts/fetch-repos.sh --dry-run
```

In CI, set `GH_TOKEN` as a secret and skip the file entirely:

```yaml
env:
  GH_TOKEN: ${{ secrets.REPO_OPTIMIZER_TOKEN }}
```

### What happens on every run

`require_gh()` validates before any repository is touched:

1. `gh` and `git` are installed
2. A token was found — otherwise the run **aborts** with setup instructions
3. The token is accepted by GitHub — `gh api user` must succeed
4. The account is reported, along with where the token came from
5. The token owner matches `GH_OWNER` — a mismatch warns, because private
   repositories of another account would silently be invisible
6. Scopes are checked (see below)

```
[info]  Authenticated as 'cooolinho' via config/token.env.
[warn]  Token carries scopes this project never uses: delete_repo admin:org
```

A rejected token fails immediately and unambiguously:

```
[error] The token from config/token.env was rejected by GitHub (bad credentials or expired).
```

### Falling back to the global login

Not recommended, but available:

```bash
ALLOW_GLOBAL_GH_AUTH=true ./scripts/fetch-repos.sh
```

This warns that actions run under your personal gh identity. Without it, a missing
token is a hard error — the failure mode should be "nothing happened", not
"something happened as the wrong user".

## Token permissions

### What the tool actually does

The permission question is easy to answer because the surface is small. Every
GitHub operation in the scripts, exhaustively:

| Operation | Command | Where |
|-----------|---------|-------|
| Verify authentication | `gh auth status` | `lib/common.sh` |
| List repositories | `gh repo list` | `fetch-repos.sh` |
| Clone a repository | `gh repo clone` | `fetch-repos.sh` |
| Push a branch | `git push` (via `gh auth git-credential`) | `publish-repo.sh` |
| Check for an existing PR | `gh pr list` | `publish-repo.sh` |
| Open a draft PR | `gh pr create` | `publish-repo.sh` |
| Set description and topics | `gh repo edit` — **only with `--meta`** | `publish-repo.sh` |

There is no delete, no settings change beyond description and topics, no workflow
modification, no organization access. Verify it yourself:

```bash
grep -nE '\bgh (auth|repo|pr|api)' scripts/*.sh scripts/lib/*.sh
```

### Classic personal access token

Create one at [github.com/settings/tokens](https://github.com/settings/tokens).

| Scope | Required | Purpose |
|-------|----------|---------|
| `repo` | **Yes** | Read private repositories, clone, push branches, open pull requests, set description and topics |
| `public_repo` | Alternative | Sufficient **only** when optimizing public repositories exclusively. Narrower than `repo` — prefer it when it fits |

One scope. Nothing else on that page is needed.

### Scopes to avoid

Everything below is unnecessary for this tool, and each one widens the blast radius
if the token leaks.

| Scope | Risk |
|-------|------|
| `delete_repo` | Permanently deletes repositories, no recovery through the API. This tool never deletes anything |
| `admin:org` | Full control over organizations: members, teams, settings. Unrelated to READMEs |
| `admin:public_key` | Adds and removes SSH keys — an attacker could add their own and keep access after the token is revoked |
| `admin:gpg_key` | Manages signing keys, enabling forged signed commits |
| `admin:repo_hook` | Creates webhooks — a quiet, persistent data exfiltration channel |
| `workflow` | Modifies GitHub Actions workflows. See the note below |
| `write:packages` | Publishes packages under your name |
| `gist` | Reads and writes your gists, including secret ones |
| `user` | Changes profile and email settings |
| `notifications` | Reads your notification stream |

#### `workflow` is worth omitting deliberately

Without the `workflow` scope, GitHub **rejects any push that touches
`.github/workflows/`** — at the server, regardless of what the client tries.

This tool only ever commits `README.md`, `README.de.md`, `docs/` and `LICENSE`, so
it never needs to push a workflow file. Leaving the scope off turns that intent
into a second enforced guarantee, independent of the whitelist check in
`publish-repo.sh`. Two independent guards beat one.

### Fine-grained personal access token

The narrower alternative. Restrict it to the repositories you actually intend to
optimize rather than "all repositories".

| Permission | Level | Purpose |
|------------|-------|---------|
| Metadata | Read | Mandatory for every fine-grained token |
| Contents | Read and write | Clone the repository, push the branch |
| Pull requests | Read and write | Open the draft pull request |
| Administration | Read and write | **Only for `--meta`** — GitHub gates `PATCH /repos/{owner}/{repo}` (description) and `PUT /repos/{owner}/{repo}/topics` behind this permission |

Leave every other permission at "No access".

#### The Administration trade-off

Administration write also covers repository settings — visibility, branch
protection, collaborators. That is a lot of authority to grant so a description
field gets filled in.

If you would rather not: omit the permission and run without `--meta`. READMEs are
published exactly the same way; you set descriptions and topics yourself in the
GitHub UI. The skill still proposes both, so it is copy-paste rather than
invention.

> **Note on `gh repo list`:** it queries the GraphQL API rather than
> `GET /user/repos`, and reports repositories the token can see. With a
> fine-grained token restricted to a subset, only that subset is listed — which is
> the desired behavior, but worth knowing before you wonder where the rest went.

### Auditing what you have

```bash
gh auth status
```

The output includes a `Token scopes:` line. Anything beyond `repo` (or
`public_repo`) is unused by this tool and can be dropped.

To narrow the token this project uses, regenerate it at
[github.com/settings/tokens](https://github.com/settings/tokens) with fewer scopes
and replace the value in `config/token.env`. No `gh auth login` involved — your
global login is a separate credential and stays as it is.

To inspect the project token specifically:

```bash
GH_TOKEN="$(grep -E '^GH_TOKEN=' config/token.env | cut -d= -f2-)" gh auth status
```

Old tokens tend to accumulate scopes from whatever needed them once. Checking is
worth the thirty seconds.

> **Why `gh repo clone` and not `git clone`?**
> Plain `git clone` over HTTPS cannot authenticate against private repositories
> without a credential helper. `gh repo clone` carries the gh credentials, so
> private repos work out of the box.

## First run

```bash
git clone https://github.com/cooolinho/github-repo-optimizer.git
cd github-repo-optimizer

# 1. Configure the project token
cp config/token.env.example config/token.env
chmod 600 config/token.env
$EDITOR config/token.env

# 2. See what would happen — clones nothing
./scripts/fetch-repos.sh --dry-run

# 3. Try a single repository end to end
./scripts/fetch-repos.sh --only some-repo
./scripts/analyze-repo.sh some-repo | jq
```

Step 2 doubles as the token check: it prints the authenticated account and any
excessive scopes before touching anything.

## Directory layout

```
github-repo-optimizer/
├── .claude/skills/repo-optimizer/   # The Claude skill
│   ├── SKILL.md
│   └── references/                  # Template, badges, detection, split rules
├── scripts/
│   ├── lib/common.sh                # Logging, config, guards, state log
│   ├── fetch-repos.sh               # Clone + branch
│   ├── analyze-repo.sh              # Stack detection → JSON
│   └── publish-repo.sh              # Commit + push + draft PR
├── config/
│   ├── settings.env                 # Central configuration
│   ├── token.env.example            # Token template (committed)
│   ├── token.env                    # Your token (gitignored)
│   └── skiplist.txt                 # Exclusions
├── workspace/                       # Clones (gitignored)
├── state/optimization-log.jsonl     # Audit trail (gitignored)
└── docs/                            # This documentation
```

`workspace/`, `state/` and `config/token.env` are gitignored — clones, run history
and your credential never end up in this repository.
