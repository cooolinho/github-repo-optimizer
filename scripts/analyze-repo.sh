#!/usr/bin/env bash
# Analyze one cloned repository and emit a JSON fact sheet on stdout.
# This is the evidence base for the README - the skill must not guess.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
require_cmd jq

usage() { echo "Usage: analyze-repo.sh <repo-name | path-to-clone>"; }

[[ $# -ge 1 ]] || { usage; exit 1; }
[[ "$1" == "-h" || "$1" == "--help" ]] && { usage; exit 0; }

target="$1"
if [[ -d "$target" ]]; then
    repo_path="$(cd "$target" && pwd)"
else
    repo_path="$WORKSPACE_DIR/$target"
fi
[[ -d "$repo_path" ]] || die "Not a directory: $repo_path"
repo_name="$(basename "$repo_path")"

j() { jq -r "$1" "$2" 2>/dev/null || true; }
has() { [[ -e "$repo_path/$1" ]]; }

# Score a manifest by how much it looks like *the application* rather than a
# tooling stub. A repository root can carry a composer.json that only pulls in
# something like laravel/homestead while the real app lives in a subdirectory -
# picking the root there reports the wrong stack entirely.
score_manifest() {
    local file="$1" filename="$2" score=0 deps=0

    if [[ "$filename" == "composer.json" ]]; then
        # A declared framework is the strongest signal.
        if jq -e '.require // {} | keys[] | select(test("^(laravel/framework|symfony/framework-bundle|contao/core-bundle|cakephp/cakephp|yiisoft/yii2|slim/slim)$"))' \
            "$file" >/dev/null 2>&1; then
            score=$((score + 100))
        fi
        # An application declares the PHP version it needs; a tooling stub rarely does.
        jq -e '.require.php // empty' "$file" >/dev/null 2>&1 && score=$((score + 20))
        # Own source code, rather than just pulled-in tools.
        jq -e '.autoload."psr-4" // empty' "$file" >/dev/null 2>&1 && score=$((score + 20))
        deps="$(jq '((.require // {}) + (."require-dev" // {})) | length' "$file" 2>/dev/null || echo 0)"
    else
        if jq -e '((.dependencies // {}) + (.devDependencies // {})) | keys[] | select(test("^(vue|react|next|nuxt|svelte|@angular/core|vite|webpack|laravel-vite-plugin|@symfony/webpack-encore)$"))' \
            "$file" >/dev/null 2>&1; then
            score=$((score + 100))
        fi
        jq -e '.scripts // empty | keys | length > 0' "$file" >/dev/null 2>&1 && score=$((score + 20))
        deps="$(jq '((.dependencies // {}) + (.devDependencies // {})) | length' "$file" 2>/dev/null || echo 0)"
    fi

    # More declared dependencies breaks ties, capped so it cannot outweigh a
    # framework match.
    [[ "$deps" -gt 30 ]] && deps=30
    score=$((score + deps))
    printf '%s' "$score"
}

# Locate the manifest that best represents the application. Candidates are the
# repository root plus anything up to three levels down; the root wins ties so
# ordinary single-project repositories behave exactly as before.
find_manifest() {
    local filename="$1"
    local best_file="" best_score=-1
    local candidate score

    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        score="$(score_manifest "$candidate" "$filename")"
        # The root gets a nudge so it wins an otherwise equal comparison.
        [[ "$candidate" == "$repo_path/$filename" ]] && score=$((score + 1))
        if [[ "$score" -gt "$best_score" ]]; then
            best_score="$score"
            best_file="$candidate"
        fi
    done < <(
        [[ -f "$repo_path/$filename" ]] && printf '%s\n' "$repo_path/$filename"
        find "$repo_path" -mindepth 2 -maxdepth 3 -name "$filename" \
            -not -path '*/vendor/*' -not -path '*/node_modules/*' \
            -not -path '*/.git/*' -print 2>/dev/null | sort
    )

    printf '%s' "$best_file"
}

COMPOSER_JSON="$(find_manifest composer.json)"
COMPOSER_LOCK=""
[[ -n "$COMPOSER_JSON" && -f "${COMPOSER_JSON%.json}.lock" ]] && COMPOSER_LOCK="${COMPOSER_JSON%.json}.lock"
PACKAGE_JSON="$(find_manifest package.json)"

# Directory the manifests live in, relative to the repo root ("." at root).
manifest_dir="."
if [[ -n "$COMPOSER_JSON" ]]; then
    manifest_dir="$(realpath --relative-to="$repo_path" "$(dirname "$COMPOSER_JSON")")"
elif [[ -n "$PACKAGE_JSON" ]]; then
    manifest_dir="$(realpath --relative-to="$repo_path" "$(dirname "$PACKAGE_JSON")")"
fi

# --- composer ----------------------------------------------------------------

composer_require='{}'
composer_require_dev='{}'
composer_desc=""
php_constraint=""
if [[ -n "$COMPOSER_JSON" ]]; then
    composer_require="$(jq -c '.require // {}'           "$COMPOSER_JSON" 2>/dev/null || echo '{}')"
    composer_require_dev="$(jq -c '."require-dev" // {}' "$COMPOSER_JSON" 2>/dev/null || echo '{}')"
    composer_desc="$(j '.description // ""' "$COMPOSER_JSON")"
    php_constraint="$(jq -r '.require.php // ""'         "$COMPOSER_JSON" 2>/dev/null || echo "")"
fi

# Resolved versions from composer.lock beat the constraint from composer.json.
composer_locked='{}'
if [[ -n "$COMPOSER_LOCK" ]]; then
    composer_locked="$(jq -c '[(.packages // [])[], (."packages-dev" // [])[]]
        | map({key: .name, value: .version}) | from_entries' \
        "$COMPOSER_LOCK" 2>/dev/null || echo '{}')"
fi

# --- npm ---------------------------------------------------------------------

npm_deps='{}'
npm_dev_deps='{}'
npm_scripts='{}'
npm_desc=""
package_manager=""
if [[ -n "$PACKAGE_JSON" ]]; then
    npm_deps="$(jq -c '.dependencies // {}'        "$PACKAGE_JSON" 2>/dev/null || echo '{}')"
    npm_dev_deps="$(jq -c '.devDependencies // {}' "$PACKAGE_JSON" 2>/dev/null || echo '{}')"
    npm_scripts="$(jq -c '.scripts // {}'          "$PACKAGE_JSON" 2>/dev/null || echo '{}')"
    npm_desc="$(j '.description // ""' "$PACKAGE_JSON")"
    package_manager="$(j '.packageManager // ""' "$PACKAGE_JSON")"
fi
# Infer the package manager from the lockfile if not declared.
if [[ -z "$package_manager" && -n "$PACKAGE_JSON" ]]; then
    pkg_dir="$(dirname "$PACKAGE_JSON")"
    [[ -f "$pkg_dir/package-lock.json" ]] && package_manager="npm"
    [[ -f "$pkg_dir/yarn.lock" ]]         && package_manager="yarn"
    [[ -f "$pkg_dir/pnpm-lock.yaml" ]]    && package_manager="pnpm"
fi

# --- python ------------------------------------------------------------------

python_deps='[]'
if has requirements.txt; then
    python_deps="$(grep -vE '^\s*(#|-|$)' "$repo_path/requirements.txt" 2>/dev/null \
        | sed 's/[[:space:]]*$//' | jq -R . | jq -sc . || echo '[]')"
elif has pyproject.toml; then
    python_deps="$(sed -n '/^\[project\]/,/^\[/p' "$repo_path/pyproject.toml" 2>/dev/null \
        | sed -n '/dependencies/,/]/p' | grep -oE '"[^"]+"' | tr -d '"' \
        | jq -R . | jq -sc . || echo '[]')"
fi

# --- files, CI, tests --------------------------------------------------------

file_flags="$(jq -nc \
    --argjson composer   "$([[ -n "$COMPOSER_JSON" ]] && echo true || echo false)" \
    --argjson package    "$([[ -n "$PACKAGE_JSON" ]]  && echo true || echo false)" \
    --argjson dockerfile "$(has Dockerfile        && echo true || echo false)" \
    --argjson compose    "$( { has docker-compose.yml || has docker-compose.yaml || has compose.yml || has compose.yaml; } && echo true || echo false)" \
    --argjson envExample "$(has .env.example      && echo true || echo false)" \
    --argjson license    "$( { has LICENSE || has LICENSE.md || has LICENSE.txt; } && echo true || echo false)" \
    --argjson makefile   "$(has Makefile          && echo true || echo false)" \
    --argjson artisan    "$( [[ -f "$repo_path/$manifest_dir/artisan" ]] && echo true || echo false)" \
    --argjson docsDir    "$(has docs              && echo true || echo false)" \
    '{composerJson:$composer, packageJson:$package, dockerfile:$dockerfile,
      compose:$compose, envExample:$envExample, license:$license,
      makefile:$makefile, artisan:$artisan, docsDir:$docsDir}')"

workflows='[]'
if [[ -d "$repo_path/.github/workflows" ]]; then
    workflows="$(find "$repo_path/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) \
        -printf '%f\n' 2>/dev/null | jq -R . | jq -sc . || echo '[]')"
fi

test_runners='[]'
runners=()
# Each check is guarded with `|| true` so a miss does not trip `set -e`.
md="$repo_path/$manifest_dir"
{ [[ -f "$md/phpunit.xml" || -f "$md/phpunit.xml.dist" ]]; } && runners+=("phpunit") || true
{ [[ -f "$md/tests/Pest.php" || -f "$md/pest.xml" ]]; } && runners+=("pest") || true
{ [[ -f "$repo_path/pytest.ini" || -f "$repo_path/tox.ini" ]] || [[ -d "$repo_path/tests" && "$python_deps" != "[]" ]]; } && runners+=("pytest") || true
[[ -n "$PACKAGE_JSON" ]] && grep -q '"vitest"' "$PACKAGE_JSON" 2>/dev/null && runners+=("vitest") || true
[[ -n "$PACKAGE_JSON" ]] && grep -q '"jest"'   "$PACKAGE_JSON" 2>/dev/null && runners+=("jest") || true
if [[ ${#runners[@]} -gt 0 ]]; then
    test_runners="$(printf '%s\n' "${runners[@]}" | sort -u | jq -R . | jq -sc .)"
fi

# --- existing README ---------------------------------------------------------

readme_file=""
readme_lines=0
readme_headings='[]'
readme_lang="unknown"
for candidate in README.md readme.md Readme.md README.markdown; do
    if [[ -f "$repo_path/$candidate" ]]; then
        readme_file="$candidate"
        break
    fi
done
if [[ -n "$readme_file" ]]; then
    readme_lines="$(wc -l < "$repo_path/$readme_file" | tr -d ' ')"
    readme_headings="$(grep -E '^#{1,3} ' "$repo_path/$readme_file" 2>/dev/null \
        | sed 's/[[:space:]]*$//' | jq -R . | jq -sc . || echo '[]')"
    # Crude but effective language sniff on German function words.
    # grep -c exits 1 on zero matches, so swallow the status rather than the count.
    de_hits="$(grep -ciE '\b(und|oder|nicht|werden|wird|eine|dieses|folgende|müssen|können)\b' \
        "$repo_path/$readme_file" 2>/dev/null | head -1 || true)"
    de_hits="${de_hits:-0}"
    if [[ "$de_hits" -ge 5 ]]; then readme_lang="de"; else readme_lang="en"; fi
fi

has_readme_de=false
[[ -f "$repo_path/README.de.md" ]] && has_readme_de=true

# --- git ---------------------------------------------------------------------

default_branch="$(git -C "$repo_path" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
current_branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
last_commit="$(git -C "$repo_path" log -1 --format=%cI 2>/dev/null || echo "")"

# --- top-level layout --------------------------------------------------------

top_level="$(find "$repo_path" -maxdepth 1 -mindepth 1 \
    -not -name '.git' -not -name 'node_modules' -not -name 'vendor' -not -name '.idea' \
    -printf '%f%y\n' 2>/dev/null | sed 's/d$/\//; s/f$//' | sort | jq -R . | jq -sc . || echo '[]')"

# --- emit --------------------------------------------------------------------

jq -n \
    --arg repo "$repo_name" \
    --arg path "$repo_path" \
    --arg currentBranch "$current_branch" \
    --arg defaultBranch "$default_branch" \
    --arg lastCommit "$last_commit" \
    --arg composerDesc "$composer_desc" \
    --arg npmDesc "$npm_desc" \
    --arg phpConstraint "$php_constraint" \
    --arg packageManager "$package_manager" \
    --arg manifestDir "$manifest_dir" \
    --arg readmeFile "$readme_file" \
    --argjson readmeLines "${readme_lines:-0}" \
    --argjson readmeHeadings "$readme_headings" \
    --arg readmeLang "$readme_lang" \
    --argjson hasReadmeDe "$has_readme_de" \
    --argjson composerRequire "$composer_require" \
    --argjson composerRequireDev "$composer_require_dev" \
    --argjson composerLocked "$composer_locked" \
    --argjson npmDeps "$npm_deps" \
    --argjson npmDevDeps "$npm_dev_deps" \
    --argjson npmScripts "$npm_scripts" \
    --argjson pythonDeps "$python_deps" \
    --argjson files "$file_flags" \
    --argjson workflows "$workflows" \
    --argjson testRunners "$test_runners" \
    --argjson topLevel "$top_level" \
    --argjson splitThreshold "${DOCS_SPLIT_THRESHOLD_LINES:-250}" \
    '{
      repo: $repo,
      path: $path,
      manifestDir: $manifestDir,
      git: {currentBranch:$currentBranch, defaultBranch:$defaultBranch, lastCommit:$lastCommit},
      descriptions: {composer:$composerDesc, npm:$npmDesc},
      readme: {
        file: $readmeFile,
        lines: $readmeLines,
        language: $readmeLang,
        headings: $readmeHeadings,
        hasGermanVersion: $hasReadmeDe,
        needsDocsSplit: ($readmeLines > $splitThreshold)
      },
      php: {constraint:$phpConstraint, require:$composerRequire, requireDev:$composerRequireDev, locked:$composerLocked},
      node: {packageManager:$packageManager, dependencies:$npmDeps, devDependencies:$npmDevDeps, scripts:$npmScripts},
      python: {dependencies:$pythonDeps},
      files: $files,
      workflows: $workflows,
      testRunners: $testRunners,
      topLevel: $topLevel
    }'
