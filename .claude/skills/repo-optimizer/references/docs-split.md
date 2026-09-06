# Splitting long READMEs

Applies when `readme.needsDocsSplit` is true — the existing README exceeds
`DOCS_SPLIT_THRESHOLD_LINES` (default 250).

The goal is a README a visitor reads in one minute, with depth one click away.
Splitting is not about hitting a line count; it is about what belongs on the
landing page.

## Never move out of the README

These are why someone opens the repository at all:

- Title, badges, one-line description
- **About** — what it is
- **Tech Stack** — what it is built with
- **Getting Started** — a path from clone to running, even if abbreviated
- **License**

If Getting Started is very long, keep a short **Quick Start** in the README and
move the detailed variants (production setup, manual install, platform-specific
notes) to `docs/installation.md`.

## Move to docs/

| Content | File |
|---|---|
| Detailed / alternative install paths | `docs/installation.md` |
| Configuration reference, env variable tables | `docs/configuration.md` |
| Deployment, server setup, CI/CD | `docs/deployment.md` |
| Architecture, data model, design decisions | `docs/architecture.md` |
| API / endpoint reference | `docs/api.md` |
| Known issues, FAQ | `docs/troubleshooting.md` |
| Version history | `docs/changelog.md` (or `CHANGELOG.md` at root, if that is the convention already) |
| Contribution rules | `docs/contributing.md` |

Only create a file when there is real content for it. Four solid documents beat
eight thin ones.

## docs/INDEX.md

```markdown
# 📚 Documentation

Full documentation for **{Project Name}**.
Back to the [README](../README.md).

## Contents

| Document | Description |
|----------|-------------|
| [Installation](installation.md) | Detailed setup for local and production |
| [Configuration](configuration.md) | All environment variables and options |
| [Deployment](deployment.md) | Server setup and release process |
```

## Rules

1. **Move, do not rewrite.** Keep the original wording; adjust only headings and
   links so the document stands on its own.
2. **Every doc links back**: a `Back to the [README](../README.md).` line under the
   title, and `[← Documentation index](INDEX.md)` at the top.
3. **Fix relative links.** Content moving from the root into `docs/` needs its
   relative paths adjusted — `./src/foo` becomes `../src/foo`. Check every link
   you moved.
4. **Point at the index from the README:**

   ```markdown
   ## 📚 Documentation

   See [docs/INDEX.md](docs/INDEX.md) for detailed documentation.
   ```
5. **An existing `docs/` is not yours to reorganize.** If the repo already has one,
   add `INDEX.md` if it is missing and file new documents alongside the existing
   ones. Do not restructure what is already there.
6. **Target: under 150 lines** for the resulting README. If it is still longer,
   the About or Features section is probably doing too much.

## German version

`README.de.md` gets the same split and links to the same `docs/` files. Do not
translate the `docs/` content — one set of documents in English, referenced from
both READMEs. Note this in the German README:

```markdown
## 📚 Dokumentation

Die ausführliche Dokumentation findest du in [docs/INDEX.md](docs/INDEX.md)
(auf Englisch).
```
