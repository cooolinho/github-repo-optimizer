<h1 align="center">🔧 GitHub Repo Optimizer</h1>

<p align="center">
  <em>Bringt jedes GitHub-Repository auf denselben README-Standard — analysiert, mit Badges versehen, übersetzt und als Draft-Pull-Request ausgeliefert.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/GitHub_CLI-181717?style=for-the-badge&logo=github&logoColor=white" alt="GitHub CLI">
  <img src="https://img.shields.io/badge/jq-1E8CBE?style=for-the-badge&logo=jquery&logoColor=white" alt="jq">
  <img src="https://img.shields.io/badge/Claude_Skill-D97757?style=for-the-badge&logo=anthropic&logoColor=white" alt="Claude Skill">
</p>

<p align="center">
  <a href="README.md">🇬🇧 English version</a>
</p>

---

## 📖 Über das Projekt

Repositories sammeln sich an. Nach ein paar Dutzend hat eines eine gepflegte README,
die meisten haben drei Zeilen, und das GitHub-Beschreibungsfeld ist überall leer.

Dieses Projekt behebt das in großem Umfang, ohne eine einzige Zeile Quellcode
anzufassen. Bash-Skripte klonen jedes Repository, extrahieren den tatsächlichen
Tech-Stack aus den Dependency-Manifesten und übergeben diese Faktenbasis an einen
Claude-Skill, der eine README nach einer festen Struktur schreibt — auf Englisch
und Deutsch, mit shields.io-Badges. Jedes Ergebnis landet auf einem Feature-Branch
als **Draft-Pull-Request**, sodass nichts ungeprüft in den Default-Branch kommt.

Die Skripte weigern sich, etwas außerhalb von `README.md`, `README.de.md`, `docs/`
und `LICENSE` zu committen. Diese Sperre ist erzwungen, nicht nur vorgesehen.

## 🛠️ Tech-Stack

| Technologie | Zweck |
|-------------|-------|
| Bash | Skripte für Fetch, Analyse und Publish |
| [GitHub CLI](https://cli.github.com/) (`gh`) | Repository-Liste, Klonen, Pull Requests |
| [jq](https://jqlang.github.io/jq/) | Manifest-Parsing und JSON-Ausgabe |
| Claude-Code-Skill | README-Erstellung auf Basis der Analyse |

## ✨ Funktionen

- **Massen-Analyse** — erkennt Laravel, Filament, Symfony, Vue, React, Python u.a. aus `composer.json`, `package.json` und `requirements.txt`
- **Monorepo-fähig** — findet Manifeste in Unterverzeichnissen und passt die Installationsbefehle an
- **Nur direkte Abhängigkeiten** — transitive Pakete landen nie in der Badge-Reihe
- **Zweisprachig** — `README.md` plus eine vollständige deutsche `README.de.md`
- **Automatischer Docs-Split** — lange READMEs wandern nach `docs/` inklusive generierter `INDEX.md`
- **Draft-PRs** — jede Änderung ist prüfbar und mit einem Befehl zurücknehmbar
- **Whitelist-Sperre** — das Publish bricht ab, sobald eine Nicht-Doku-Datei geändert wurde
- **Skip-Liste** — Repositories per Name oder Glob ausschließen; Forks und archivierte Repos sind standardmäßig ausgeschlossen

## 🚀 Erste Schritte

### Voraussetzungen

- `gh` — [GitHub CLI](https://cli.github.com/) (kein globaler Login nötig, siehe unten)
- `git`
- `jq`
- Bash 4+

### Installation

```bash
git clone https://github.com/cooolinho/github-repo-optimizer.git
cd github-repo-optimizer

cp config/token.env.example config/token.env
chmod 600 config/token.env
# Token in config/token.env eintragen, dann:
./scripts/fetch-repos.sh --dry-run
```

### 🔑 Projekt-Token

Dieses Projekt nutzt **kein** `gh auth login`. Dieser Befehl schreibt nach
`~/.config/gh/hosts.yml` und ändert deine Identität für jeden `gh`-Aufruf auf dem
Rechner.

Stattdessen liegt der Token in `config/token.env` und wird für die Dauer eines
einzelnen Skriptlaufs als `GH_TOKEN` exportiert. `gh` bevorzugt `GH_TOKEN`
gegenüber dem gespeicherten Login, dein globales Setup wird also weder gelesen noch
verändert — du kannst parallel einen breiten persönlichen Token für den Alltag und
einen engen für dieses Projekt haben.

```bash
cp config/token.env.example config/token.env
chmod 600 config/token.env
```

Danach den Token in dieser Datei eintragen:

```
GH_TOKEN=ghp_dein_token_hier
```

`config/token.env` ist gitignored. Die Skripte lesen ausschließlich die
`GH_TOKEN`-Zeile heraus, statt die Datei zu sourcen — ein versehentlich darin
gelandeter Befehl kann also nicht ausgeführt werden.

Bei jedem Lauf prüfen die Skripte den Token, zeigen zu welchem Konto er gehört und
woher er stammt, und warnen bei Scopes, die dieses Projekt nie nutzt:

```
[info]  Authenticated as 'cooolinho' via config/token.env.
[warn]  Token carries scopes this project never uses: delete_repo admin:org
```

Ohne konfigurierten Token verweigern die Skripte den Start. Um bewusst auf deinen
globalen Login zurückzufallen:

```bash
ALLOW_GLOBAL_GH_AUTH=true ./scripts/fetch-repos.sh
```

In CI setzt du `GH_TOKEN` als Secret — eine geerbte Umgebungsvariable hat Vorrang,
eine Datei ist dann nicht nötig.

### 🔑 Token-Berechtigungen

Das Tool führt genau sechs GitHub-Operationen aus: Repositories auflisten, klonen,
einen Branch pushen, Pull Requests auflisten, einen Draft-PR öffnen und — nur mit
`--meta` — Beschreibung und Topics setzen. Sonst nichts. Vergib die Rechte
entsprechend.

**Personal Access Token (classic) — das Minimum:**

| Scope | Nötig | Wofür |
|-------|-------|-------|
| `repo` | **Ja** | Deckt alles ab: private Repos lesen, klonen, Branch pushen, PRs öffnen, Beschreibung und Topics setzen |
| `public_repo` | Alternative | Reicht **nur**, wenn du ausschließlich öffentliche Repositories optimierst — enger gefasst als `repo`, also vorzuziehen, wenn es passt |

Das ist die vollständige Liste. Ein einziger Scope.

**Diese Scopes solltest du niemals aktivieren:**

| Scope | Warum nicht |
|-------|-------------|
| `delete_repo` | Löscht Repositories unwiderruflich. Das Tool löscht nie etwas — der Scope bringt nur Risiko |
| `admin:org` | Volle Kontrolle über deine Organisationen, inklusive Entfernen von Mitgliedern. Hat mit READMEs nichts zu tun |
| `admin:public_key`, `admin:gpg_key` | Verwaltet deine SSH- und Signierschlüssel. Ein Weg zur Kontoübernahme |
| `workflow` | Erlaubt das Ändern von GitHub-Actions-Workflows. Ohne ihn **lehnt GitHub** einen Push ab, der `.github/workflows/` berührt — eine nützliche zusätzliche Sperre, da dieses Tool ausschließlich Dokumentation schreibt |
| `write:packages`, `admin:repo_hook`, `gist`, `user` | Werden nicht genutzt. Alles Ungenutzte ist Angriffsfläche |

> ⚠️ **Prüfe, was dein Token aktuell hat:**
> ```bash
> gh auth status
> ```
> Zeigt die Zeile mit den Token-Scopes mehr als `repo`, erstelle unter
> [github.com/settings/tokens](https://github.com/settings/tokens) einen enger
> gefassten Token und führe `gh auth login` erneut aus. Übrig gebliebene breite
> Scopes aus einem früheren Setup sind der Normalfall, nicht die Ausnahme.

**Fine-grained Token — die Alternative:**

| Berechtigung | Stufe | Wofür |
|--------------|-------|-------|
| Metadata | Read | Für jeden Fine-grained-Token verpflichtend |
| Contents | Read and write | Repository klonen, Branch pushen |
| Pull requests | Read and write | Draft-PR öffnen |
| Administration | Read and write | **Nur für `--meta`** — GitHub verlangt das für Beschreibung und Topics |

Administration ist weitreichend und umfasst auch die Repository-Einstellungen. Wenn
dir das zu viel ist, lass die Berechtigung weg und verzichte auf `--meta`: Die
READMEs werden trotzdem veröffentlicht, Beschreibung und Topics setzt du dann
selbst in der GitHub-Oberfläche.

Beschränke den Token auf die Repositories, die du tatsächlich optimieren willst,
statt auf „all repositories".

### Konfiguration

Bearbeite [`config/settings.env`](config/settings.env):

| Variable | Beschreibung | Standard |
|----------|--------------|----------|
| `GH_OWNER` | GitHub-Konto, das verarbeitet wird | `cooolinho` |
| `BRANCH_NAME` | Feature-Branch, der in jedem Repo angelegt wird | `chore/readme-optimization` |
| `BATCH_SIZE` | Repositories pro Freigabe-Batch | `5` |
| `SKIP_FORKS` | Forks ausschließen | `true` |
| `SKIP_ARCHIVED` | Archivierte Repositories ausschließen | `true` |
| `DOCS_SPLIT_THRESHOLD_LINES` | README-Länge, ab der nach `docs/` aufgeteilt wird | `250` |

Ausschlüsse trägst du in [`config/skiplist.txt`](config/skiplist.txt) ein — ein Name
pro Zeile, `#` für Kommentare, `*`-Globs werden unterstützt.

## 📋 Verwendung

Der vorgesehene Einstieg ist der Claude-Skill. In Claude Code:

```
Optimiere meine Repositories
```

Der Skill führt die Skripte aus, schreibt die READMEs und stoppt nach jedem Batch
zur Freigabe.

Die Skripte direkt aufrufen:

```bash
# Anzeigen, welche Repositories verarbeitet würden
./scripts/fetch-repos.sh --dry-run

# Klonen und Feature-Branch anlegen
./scripts/fetch-repos.sh

# Erkannten Stack eines Repositories prüfen
./scripts/analyze-repo.sh mein-repo | jq

# Diff prüfen, ohne zu pushen
./scripts/publish-repo.sh mein-repo --dry-run

# Veröffentlichen: committen, pushen, Draft-PR öffnen, Beschreibung und Topics setzen
./scripts/publish-repo.sh mein-repo --meta \
  --description "Kurze Projektbeschreibung" \
  --topics "laravel,filament,docker"
```

### Rückgängig machen

```bash
gh pr close --repo cooolinho/mein-repo <nummer> --delete-branch
```

## 📚 Dokumentation

Details zu Setup, Konfiguration und Workflow findest du in
[docs/INDEX.md](docs/INDEX.md) (auf Englisch).

## 📄 Lizenz

Veröffentlicht unter der [MIT-Lizenz](LICENSE).
