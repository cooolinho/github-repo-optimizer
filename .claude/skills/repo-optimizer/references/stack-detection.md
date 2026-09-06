# Stack detection

Which manifest entry proves which technology. The rule throughout: **a technology
belongs in the README only if a direct dependency proves it.**

## Direct vs. transitive

`analyze-repo.sh` reports two things per PHP project:

- `php.require` / `php.requireDev` — what the project **declares**. Only these
  justify a badge.
- `php.locked` — resolved versions from `composer.lock`, including transitive
  packages. Use this **only to look up the version** of something already proven
  direct.

Same for Node: `node.dependencies` / `node.devDependencies` prove; nothing else does.

Concretely: `symfony/dom-crawler` in `require` does **not** make it a Symfony
project — every Laravel app pulls Symfony components. Only `symfony/framework-bundle`
or a `bin/console` + `config/bundles.php` layout does.

## Version display

Take the version from `php.locked[package]` (e.g. `"v13.26.1"`), strip the leading
`v`, and show the major series: `13.x`. Exact patch versions go stale within days.

If a package is absent from `locked` (no lockfile committed), fall back to the
constraint from `require` and show it as-is (`^8.5`).

## PHP — composer

| Composer package (in `require`) | Technology |
|---|---|
| `laravel/framework` | Laravel |
| `filament/filament` | Filament |
| `livewire/livewire` | Livewire — but see note below |
| `laravel/horizon` | Laravel Horizon (queue dashboard) |
| `laravel/octane` | Laravel Octane |
| `laravel/sanctum`, `laravel/passport` | API authentication |
| `symfony/framework-bundle` | Symfony |
| `contao/core-bundle` | Contao |
| `spatie/*` | Name the specific package in the table, not "Spatie" |
| `guzzlehttp/guzzle` | Infrastructure — do **not** badge it |
| `php` | PHP, version from the constraint |

**Livewire note:** Filament depends on Livewire. Badge Livewire separately only if
`livewire/livewire` is in `require` *and* the repo has its own components under
`app/Livewire/` or `app/Http/Livewire/`. Otherwise it is an implementation detail
of Filament and belongs in neither the badge row nor the table.

Test runners: `phpunit/phpunit` → PHPUnit, `pestphp/pest` → Pest.
Prefer Pest when both are present — Pest runs on PHPUnit.

## JavaScript — package.json

| Package | Technology |
|---|---|
| `vue` | Vue.js |
| `react` + `react-dom` | React |
| `alpinejs` | Alpine.js |
| `tailwindcss` | Tailwind CSS |
| `bootstrap` | Bootstrap |
| `sass`, `sass-embedded` | Sass |
| `jquery` | jQuery |
| `vite` | Vite |
| `typescript` | TypeScript |
| `vitest`, `jest` | Test runner |
| `laravel-vite-plugin`, `autoprefixer`, `postcss` | Build plumbing — no badge |

Package manager from `node.packageManager` (`yarn@4.18.0` → Yarn) or the lockfile.
The install command must match: `yarn install`, `pnpm install`, `npm ci`.

## Python

`python.dependencies` holds raw requirement lines (`opencv-python>=4.8.0`).
Strip the version specifier for the name.

| Requirement | Technology |
|---|---|
| `opencv-python` | OpenCV |
| `django` | Django |
| `flask` | Flask |
| `fastapi` | FastAPI |
| `selenium` | Selenium |
| `requests`, `pillow`, `numpy` | Library — table only, no badge |

## Infrastructure — from `files` and `workflows`

| Signal | Technology |
|---|---|
| `files.dockerfile` or `files.compose` | Docker |
| `workflows` non-empty | GitHub Actions |
| `mysql`/`mariadb`/`postgres`/`redis` service in the compose file | that database |
| `files.artisan` | confirms Laravel even without a lockfile |

For databases, read the compose file — the service image is the evidence, not a guess.

## Monorepos

### How the manifest is chosen

A repository can contain several `composer.json` files, and the one at the root is
not always the application. `symfony-template` is the cautionary case: its root
manifest declares only `laravel/homestead` — a VM tool — while the actual Symfony
6.3 application, with 39 dependencies, sits in `symfony/`.

So `analyze-repo.sh` scores every candidate instead of taking the root blindly:

| Signal | Points |
|--------|--------|
| Declares a framework (`laravel/framework`, `symfony/framework-bundle`, …) | +100 |
| Declares a `php` version constraint | +20 |
| Has `autoload.psr-4` — own source code, not just tools | +20 |
| Number of declared dependencies | +1 each, capped at 30 |
| Is the repository root | +1 (tiebreaker only) |

The highest score wins. For an ordinary single-project repository the root is the
only candidate and nothing changes; the scoring only matters when a subdirectory
manifest is a better description of the project.

If the reported `manifestDir` still looks wrong, read the manifests yourself and
trust what you see — the score is a heuristic, not an oracle.

### Working with the result

`manifestDir` names the directory holding the manifests. When it is not `.`:

- Install commands need `cd {manifestDir}` first
- The README gets a **Project Structure** section explaining the layout
- Docker Compose usually still runs from the repo root — check the compose file's
  `build.context` before writing the command

## Nothing detected

No `composer.json`, no `package.json`, no `requirements.txt`, no Dockerfile:

- Read the source directly. A repo of shell scripts is still a Bash project.
- Shell scripts → Bash badge; `.ahk` files → AutoHotkey; `.ino` → Arduino.
- If there is genuinely no content and no stack, **skip the repository** and report
  it. Do not write a README for an empty repo.
