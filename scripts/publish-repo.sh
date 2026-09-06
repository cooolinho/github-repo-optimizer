#!/usr/bin/env bash
# Commit the README changes of one repository, push the branch and open a
# draft PR. Only documentation files are ever staged.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
require_gh
require_cmd jq

# The only paths this script is ever allowed to commit.
ALLOWED_PATHS=(README.md README.de.md docs LICENSE)

DRY_RUN=""
NO_PR=""
META=""
DESCRIPTION=""
TOPICS=""
REPO=""

usage() {
    cat <<'USAGE'
Usage: publish-repo.sh <repo-name> [options]

  --dry-run              Show the staged diff; commit nothing, push nothing.
  --no-pr                Commit and push, but do not open a pull request.
  --meta                 Also apply --description / --topics via `gh repo edit`.
  --description <text>   GitHub repository description (needs --meta).
  --topics <a,b,c>       Comma-separated GitHub topics (needs --meta).
  -v, --verbose          Verbose output.
  -h, --help             Show this help.

Only README.md, README.de.md, docs/ and LICENSE are ever staged.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)     DRY_RUN=1; shift ;;
        --no-pr)       NO_PR=1; shift ;;
        --meta)        META=1; shift ;;
        --description) DESCRIPTION="${2:?--description needs a value}"; shift 2 ;;
        --topics)      TOPICS="${2:?--topics needs a value}"; shift 2 ;;
        -v|--verbose)  VERBOSE=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        -*)            die "Unknown option: $1 (try --help)" ;;
        *)             REPO="$1"; shift ;;
    esac
done

[[ -n "$REPO" ]] || { usage; exit 1; }

repo_path="$WORKSPACE_DIR/$REPO"
[[ -d "$repo_path/.git" ]] || die "No clone found at $repo_path (run fetch-repos.sh first)."

# gh is not necessarily configured as a git credential helper, so supply it
# per invocation rather than mutating the user's global git config.
git_r() {
    git -C "$repo_path" -c 'credential.https://github.com.helper=' \
        -c 'credential.https://github.com.helper=!gh auth git-credential' "$@"
}

# --- guard: never touch the default branch ----------------------------------

current_branch="$(git_r rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" != "$BRANCH_NAME" ]]; then
    die "$REPO is on '$current_branch', expected '$BRANCH_NAME'. Refusing to publish."
fi

# --- guard: refuse to commit anything outside the whitelist ------------------

# Every path git reports as changed, ignoring untracked noise we never stage.
mapfile -t changed < <(git_r status --porcelain | sed 's/^...//' | sed 's/ -> .*//')

# A clean worktree still needs publishing if an earlier run committed but
# failed to push.
default_branch="$(git_r symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
default_branch="${default_branch:-main}"

# Compare against the remote branch once it exists, otherwise against the
# default branch - never against the empty set, which would count all history.
if git_r rev-parse --verify --quiet "refs/remotes/origin/$BRANCH_NAME" >/dev/null 2>&1; then
    compare_ref="origin/$BRANCH_NAME"
else
    compare_ref="origin/$default_branch"
fi
unpushed="$(git_r rev-list --count "$compare_ref..HEAD" 2>/dev/null || echo 0)"

if [[ ${#changed[@]} -eq 0 ]]; then
    if [[ "$unpushed" -gt 0 ]]; then
        log_info "$REPO: worktree clean, $unpushed commit(s) not yet pushed."
        SKIP_COMMIT=1
    else
        log_warn "$REPO: no changes to publish."
        log_state "$REPO" "publish-skipped" "no changes"
        exit 0
    fi
fi

violations=()
for path in "${changed[@]}"; do
    allowed=""
    for prefix in "${ALLOWED_PATHS[@]}"; do
        if [[ "$path" == "$prefix" || "$path" == "$prefix/"* ]]; then
            allowed=1
            break
        fi
    done
    [[ -z "$allowed" ]] && violations+=("$path")
done

if [[ ${#violations[@]} -gt 0 ]]; then
    log_error "$REPO: changes outside the documentation whitelist:"
    printf '    %s\n' "${violations[@]}" >&2
    log_error "Revert those files, then publish again."
    log_state "$REPO" "publish-blocked" "non-doc changes: ${violations[*]}"
    exit 1
fi

# --- stage -------------------------------------------------------------------

if [[ -z "${SKIP_COMMIT:-}" ]]; then
for prefix in "${ALLOWED_PATHS[@]}"; do
    [[ -e "$repo_path/$prefix" ]] && git_r add -- "$prefix"
done

if git_r diff --cached --quiet; then
    log_warn "$REPO: nothing staged after filtering."
    log_state "$REPO" "publish-skipped" "nothing staged"
    exit 0
fi

log_info "$REPO: staged changes"
git_r diff --cached --stat >&2

if [[ -n "$DRY_RUN" ]]; then
    log_info "$REPO: dry run - nothing committed or pushed."
    { [[ "$unpushed" -gt 0 ]] && log_info "$REPO: $unpushed commit(s) would also be pushed."; } || true
    if [[ -n "$META" ]]; then
        log_info "  would set description: ${DESCRIPTION:-<unchanged>}"
        log_info "  would set topics:      ${TOPICS:-<unchanged>}"
    fi
    git_r reset --quiet
    exit 0
fi

# --- commit ------------------------------------------------------------------

git_r commit --quiet -m "$COMMIT_MESSAGE" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
log_ok "$REPO: committed."
fi  # SKIP_COMMIT

# Dry run for the "already committed, not yet pushed" path.
if [[ -n "$DRY_RUN" ]]; then
    log_info "$REPO: dry run - $unpushed commit(s) would be pushed, no PR opened."
    exit 0
fi

# --- push --------------------------------------------------------------------

git_r push --quiet -u origin "$BRANCH_NAME"
log_ok "$REPO: pushed $BRANCH_NAME."

# --- pull request ------------------------------------------------------------

pr_url=""
if [[ -z "$NO_PR" ]]; then
    existing="$(gh pr list --repo "$GH_OWNER/$REPO" --head "$BRANCH_NAME" \
        --state open --json url --jq '.[0].url' 2>/dev/null || true)"
    if [[ -n "$existing" && "$existing" != "null" ]]; then
        pr_url="$existing"
        log_info "$REPO: pull request already open - $pr_url"
    else
        pr_body="$(cat <<'BODY'
Standardizes the README across repositories.

- Unified section structure (About, Tech Stack, Getting Started, Usage, License)
- Tech stack badges derived from the actual dependency manifests
- German translation in `README.de.md`

Documentation only - no source code was changed.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
        pr_url="$(gh pr create --repo "$GH_OWNER/$REPO" \
            --draft \
            --base "$default_branch" \
            --head "$BRANCH_NAME" \
            --title "$PR_TITLE" \
            --body "$pr_body")"
        log_ok "$REPO: draft PR opened - $pr_url"
    fi
fi

# --- repository metadata -----------------------------------------------------

if [[ -n "$META" ]]; then
    edit_args=()
    [[ -n "$DESCRIPTION" ]] && edit_args+=(--description "$DESCRIPTION")
    if [[ -n "$TOPICS" ]]; then
        IFS=',' read -ra topic_list <<< "$TOPICS"
        for t in "${topic_list[@]}"; do
            t="$(printf '%s' "$t" | tr -d '[:space:]')"
            [[ -n "$t" ]] && edit_args+=(--add-topic "$t")
        done
    fi
    if [[ ${#edit_args[@]} -gt 0 ]]; then
        gh repo edit "$GH_OWNER/$REPO" "${edit_args[@]}" >/dev/null
        log_ok "$REPO: description/topics updated."
    else
        log_warn "$REPO: --meta given but no --description or --topics."
    fi
fi

log_state "$REPO" "published" "${pr_url:-pushed without PR}"
