# README template

The canonical structure. Every repository gets these sections, in this order.

**Omit optional sections entirely rather than filling them with placeholders.**
A README with four honest sections beats one with ten hollow ones.

## Structure

```markdown
<h1 align="center">{emoji} {Project Name}</h1>

<p align="center">
  <em>{One-line description — what it does, for whom}</em>
</p>

<p align="center">
  {stack badges, see stack-badges.md}
</p>

<p align="center">
  <a href="README.de.md">🇩🇪 Deutsche Version</a>
</p>

---

## 📖 About

Two to four sentences: the problem it solves, who it is for, what makes it
different. No marketing language, no invented claims.

## 🛠️ Tech Stack

| Technology | Version | Purpose |
|------------|---------|---------|
| ![Laravel](badge-url) Laravel | 13.x | Application framework |
| ![Filament](badge-url) Filament | 5.x | Admin panel |

Versions come from the lockfile (`php.locked` in the analysis), not from the
constraint in `composer.json`. Only list what a developer needs to know about —
direct dependencies, never transitive ones.

## ✨ Features

- **Feature name** — one line on what it does

Only features you can point at in the code. Four real ones beat twelve guesses.

## 🚀 Getting Started

### Prerequisites

- PHP 8.5+
- Composer 2.x
- Docker & Docker Compose  *(only if the repo actually ships a compose file)*

### Installation

```bash
git clone https://github.com/{owner}/{repo}.git
cd {repo}
{install commands}
```

### Configuration

Only if `.env.example` exists. Name the variables that actually need a value,
not the whole file.

```bash
cp .env.example .env
```

| Variable | Description | Default |
|----------|-------------|---------|
| `APP_URL` | Base URL of the application | `http://localhost` |

## 📋 Usage

The commands to actually run the thing. Real commands, copy-pasteable.

## 🧪 Testing            (only if a test runner was detected)

```bash
{test command}
```

## 📁 Project Structure   (only when the layout is non-obvious — monorepos, unusual roots)

```
{repo}/
├── laravel/     # Application code
└── docker/      # Container configuration
```

## 📚 Documentation       (only when docs/ exists)

See [docs/INDEX.md](docs/INDEX.md) for the full documentation.

## 📄 License

Released under the [MIT License](LICENSE).
```

## Header emoji

One emoji matching the domain — `🚀` `📦` `🎬` `🤖` `🏋️` `📊` `🔧` `🌐` `📝` `🐳`.
Pick something specific to the project, not a generic box for everything.

## Install commands by stack

Derive from the analysis; prefix with `cd {manifestDir}` when it is not `.`.

| Stack | Commands |
|-------|----------|
| Laravel | `composer install`<br>`cp .env.example .env`<br>`php artisan key:generate`<br>`php artisan migrate`<br>`php artisan serve` |
| Laravel + Vite | above, plus `npm install` and `npm run dev` |
| Docker Compose | `cp .env.example .env`<br>`docker compose up -d` |
| Node | `npm ci` then the actual script from `node.scripts` |
| Python | `python -m venv .venv`<br>`source .venv/bin/activate`<br>`pip install -r requirements.txt` |

Use the real package manager from `node.packageManager` — `yarn install` for yarn,
`pnpm install` for pnpm. Never write `npm ci` for a yarn project.

## README.de.md

A full translation of the same structure — same sections, same order, same badges.

- Header link points back: `<a href="README.md">🇬🇧 English version</a>`
- Section headings translate: About → Über das Projekt, Tech Stack → Tech-Stack,
  Features → Funktionen, Getting Started → Erste Schritte, Usage → Verwendung,
  Testing → Tests, Project Structure → Projektstruktur,
  Documentation → Dokumentation, License → Lizenz
- Code blocks, commands and variable names stay untranslated
- Use "du" — these are personal projects, not enterprise docs
