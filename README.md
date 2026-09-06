<h1 align="center">🔧 GitHub Repo Optimizer</h1>

<p align="center">
  <em>Bring every GitHub repository to the same README standard — analyzed, badged, translated, and delivered as a draft pull request.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/GitHub_CLI-181717?style=for-the-badge&logo=github&logoColor=white" alt="GitHub CLI">
  <img src="https://img.shields.io/badge/jq-1E8CBE?style=for-the-badge&logo=jquery&logoColor=white" alt="jq">
  <img src="https://img.shields.io/badge/Claude_Skill-D97757?style=for-the-badge&logo=anthropic&logoColor=white" alt="Claude Skill">
</p>

<p align="center">
  <a href="README.de.md">🇩🇪 Deutsche Version</a>
</p>

---

## 📖 About

Repositories accumulate. After a few dozen, some have a polished README, most have
three lines, and the GitHub description field is empty everywhere.

This project fixes that in bulk without touching a single line of source code. A
set of Bash scripts clones every repository, extracts the real tech stack from the
dependency manifests, and hands that evidence to a Claude skill that writes a
README following one canonical structure — in English and German, with shields.io
badges. Each result lands on a feature branch as a **draft pull request**, so
nothing reaches the default branch without review.

The scripts refuse to commit anything outside `README.md`, `README.de.md`, `docs/`
and `LICENSE`. That guard is enforced, not merely intended.

## 🛠️ Tech Stack

| Technology | Purpose |
|------------|---------|
| Bash | Fetch, analysis and publish scripts |
| [GitHub CLI](https://cli.github.com/) (`gh`) | Repository listing, cloning, pull requests |
| [jq](https://jqlang.github.io/jq/) | Manifest parsing and JSON output |
| Claude Code skill | README authoring from the analysis |

## ✨ Features

- **Bulk analysis** — detects Laravel, Filament, Symfony, Vue, React, Python and more from `composer.json`, `package.json` and `requirements.txt`
- **Monorepo aware** — finds manifests in subdirectories and adjusts install commands
- **Direct dependencies only** — transitive packages never end up in the badge row
- **Bilingual** — `README.md` plus a full German `README.de.md`
- **Automatic docs split** — long READMEs move into `docs/` with a generated `INDEX.md`
- **Draft PRs** — every change is reviewable, and revertible with one command
- **Whitelist guard** — publishing aborts if any non-documentation file changed
- **Skip list** — exclude repositories by name or glob; forks and archived repos are excluded by default

## 🚀 Getting Started

### Prerequisites

- `gh` — [GitHub CLI](https://cli.github.com/) (no global login required, see below)
- `git`
- `jq`
- Bash 4+

### Installation

```bash
git clone https://github.com/cooolinho/github-repo-optimizer.git
cd github-repo-optimizer

cp config/token.env.example config/token.env
cp config/skiplist.txt.example config/skiplist.txt

chmod 600 config/token.env
chmod 600 config/skiplist.txt

# add your token to config/token.env, then:
./scripts/fetch-repos.sh --dry-run
```

### 🔑 Project token

This project does **not** use `gh auth login`. That command writes to
`~/.config/gh/hosts.yml` and changes your identity for every `gh` invocation on
the machine.

Instead, the token lives in `config/token.env` and is exported as `GH_TOKEN` for
the duration of a single script run. `gh` prefers `GH_TOKEN` over the stored
login, so your global setup is never read and never modified — you can hold a
broad personal token for daily work and a narrow one for this project at the same
time.

```bash
cp config/token.env.example config/token.env
chmod 600 config/token.env
```

Then set the token in that file:

```
GH_TOKEN=ghp_your_token_here
```

`config/token.env` is gitignored. The scripts parse only the `GH_TOKEN` line
rather than sourcing the file, so a stray command in it cannot execute.

On every run the scripts verify the token, print which account it belongs to and
where it came from, and warn if it carries scopes this project never uses:

```
[info]  Authenticated as 'cooolinho' via config/token.env.
[warn]  Token carries scopes this project never uses: delete_repo admin:org
```

Without a configured token the scripts refuse to run. To deliberately fall back to
your global login:

```bash
ALLOW_GLOBAL_GH_AUTH=true ./scripts/fetch-repos.sh
```

In CI, set `GH_TOKEN` as a secret — an inherited environment variable takes
precedence and no file is needed.

### 🔑 Token permissions

This tool performs exactly six GitHub operations: list repositories, clone them,
push a branch, list pull requests, open a draft pull request, and — only with
`--meta` — set the description and topics. Nothing else. Grant accordingly.

**Personal access token (classic) — the minimum:**

| Scope | Needed | Why |
|-------|--------|-----|
| `repo` | **Yes** | Covers everything: reading private repos, cloning, pushing the branch, opening PRs, setting description and topics |
| `public_repo` | Alternative | Enough **only** if you optimize public repositories exclusively — narrower than `repo`, prefer it when it fits |

That is the complete list. One scope.

**Never enable these:**

| Scope | Why not |
|-------|---------|
| `delete_repo` | Permanently deletes repositories. This tool never deletes anything — the scope adds only risk |
| `admin:org` | Full control over your organizations, including member removal. Entirely unrelated to READMEs |
| `admin:public_key`, `admin:gpg_key` | Manages your SSH and signing keys. An account-takeover path |
| `workflow` | Allows modifying GitHub Actions workflows. Without it, a push touching `.github/workflows/` is **rejected by GitHub** — a useful extra guard, since this tool only writes documentation |
| `write:packages`, `admin:repo_hook`, `gist`, `user` | Not used. Anything unused is attack surface |

> ⚠️ **Check what you already have:**
> ```bash
> gh auth status
> ```
> If the token scopes line shows more than `repo`, issue a narrower token at
> [github.com/settings/tokens](https://github.com/settings/tokens) and re-run
> `gh auth login`. Leftover broad scopes from an older setup are common.

**Fine-grained token — the alternative:**

| Permission | Level | Why |
|------------|-------|-----|
| Metadata | Read | Mandatory for every fine-grained token |
| Contents | Read and write | Clone the repository, push the branch |
| Pull requests | Read and write | Open the draft PR |
| Administration | Read and write | **Only for `--meta`** — GitHub gates description and topics behind this |

Administration is broad — it also covers repository settings. If that is more than
you want to hand out, omit it and skip `--meta`: READMEs still get published, and
you set descriptions and topics yourself in the GitHub UI.

Restrict the token to the repositories you actually intend to optimize rather than
"all repositories".

### Configuration

Edit [`config/settings.env`](config/settings.env):

| Variable | Description | Default |
|----------|-------------|---------|
| `GH_OWNER` | GitHub account to process | `cooolinho` |
| `BRANCH_NAME` | Feature branch created in every repo | `chore/readme-optimization` |
| `BATCH_SIZE` | Repositories per approval batch | `5` |
| `SKIP_FORKS` | Exclude forks | `true` |
| `SKIP_ARCHIVED` | Exclude archived repositories | `true` |
| `DOCS_SPLIT_THRESHOLD_LINES` | README length that triggers a `docs/` split | `250` |

Add exclusions to [`config/skiplist.txt`](config/skiplist.txt) — one name per line,
`#` for comments, `*` globs supported.

## 📋 Usage

The intended entry point is the Claude skill. In Claude Code:

```
Optimize my repositories
```

The skill runs the scripts, writes the READMEs and stops after each batch for approval.

To drive the scripts directly:

```bash
# See which repositories would be processed
./scripts/fetch-repos.sh --dry-run

# Clone them and create the feature branch
./scripts/fetch-repos.sh

# Inspect the detected stack of one repository
./scripts/analyze-repo.sh my-repo | jq

# Review the staged diff without pushing
./scripts/publish-repo.sh my-repo --dry-run

# Publish: commit, push, open a draft PR, set description and topics
./scripts/publish-repo.sh my-repo --meta \
  --description "Short project description" \
  --topics "laravel,filament,docker"
```

### Rollback

```bash
gh pr close --repo cooolinho/my-repo <number> --delete-branch
```

## 📚 Documentation

See [docs/INDEX.md](docs/INDEX.md) for setup, configuration and workflow details.

## 📄 License

Released under the [MIT License](LICENSE).
