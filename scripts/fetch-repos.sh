#!/usr/bin/env bash
# Clone or refresh every eligible repository into the workspace and put it
# on the optimization branch. Writes workspace/_manifest.json as the work list.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config
require_gh
require_cmd jq

DRY_RUN=""
ONLY=""
LIMIT=""
REFRESH=""

usage() {
    cat <<'USAGE'
Usage: fetch-repos.sh [options]

  --dry-run       List what would be fetched; clone nothing.
  --only <repo>   Process a single repository by name.
  --limit <n>     Process at most n repositories.
  --refresh       Reset an existing clone to the remote default branch first.
  -v, --verbose   Verbose output.
  -h, --help      Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=1; shift ;;
        --only)     ONLY="${2:?--only needs a repository name}"; shift 2 ;;
        --limit)    LIMIT="${2:?--limit needs a number}"; shift 2 ;;
        --refresh)  REFRESH=1; shift ;;
        -v|--verbose) VERBOSE=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *)          die "Unknown option: $1 (try --help)" ;;
    esac
done

# --- 1. fetch the repository list -------------------------------------------

log_info "Listing repositories for '$GH_OWNER' ..."
raw_json="$(gh repo list "$GH_OWNER" \
    --limit "${REPO_LIST_LIMIT:-300}" \
    --json name,isFork,isArchived,isPrivate,description,url,defaultBranchRef,repositoryTopics)"

total_count="$(jq 'length' <<<"$raw_json")"
log_info "Found $total_count repositories."

# --- 2. apply skip rules -----------------------------------------------------

eligible_json="$(jq \
    --argjson skipForks "$([[ "${SKIP_FORKS:-true}" == "true" ]] && echo true || echo false)" \
    --argjson skipArchived "$([[ "${SKIP_ARCHIVED:-true}" == "true" ]] && echo true || echo false)" \
    '[ .[]
       | select(($skipForks    and .isFork)     | not)
       | select(($skipArchived and .isArchived) | not)
       | {name,
          isPrivate,
          url,
          description: (.description // ""),
          defaultBranch: (.defaultBranchRef.name // "main"),
          topics: [.repositoryTopics[]?.name]}
     ] | sort_by(.name)' <<<"$raw_json")"

# Filter the skiplist in bash so glob patterns behave identically everywhere.
kept=()
while IFS= read -r name; do
    if is_skipped "$name"; then
        log_debug "skiplist excludes $name"
        continue
    fi
    if [[ -n "$ONLY" && "$name" != "$ONLY" ]]; then
        continue
    fi
    kept+=("$name")
done < <(jq -r '.[].name' <<<"$eligible_json")

if [[ -n "$ONLY" && ${#kept[@]} -eq 0 ]]; then
    die "Repository '$ONLY' not found, or excluded by the skip rules."
fi

if [[ -n "$LIMIT" ]]; then
    kept=("${kept[@]:0:$LIMIT}")
fi

if [[ ${#kept[@]} -eq 0 ]]; then
    log_warn "No repositories left after filtering. Nothing to do."
    exit 0
fi

log_info "${#kept[@]} repositories eligible after filtering."

# Narrow the manifest to the kept names.
names_json="$(printf '%s\n' "${kept[@]}" | jq -R . | jq -sc .)"
manifest_json="$(jq --argjson keep "$names_json" \
    '[ .[] | select(.name as $n | $keep | index($n)) ]' <<<"$eligible_json")"

# --- 3. dry run stops here ---------------------------------------------------

if [[ -n "$DRY_RUN" ]]; then
    log_info "Dry run - the following repositories would be fetched:"
    jq -r '.[] | "  \(.name)  [\(if .isPrivate then "private" else "public" end), default: \(.defaultBranch)]\(if .description == "" then "  (no description)" else "" end)"' \
        <<<"$manifest_json"
    exit 0
fi

# --- 4. clone / refresh ------------------------------------------------------

mkdir -p "$WORKSPACE_DIR"
results='[]'

for name in "${kept[@]}"; do
    entry="$(jq -c --arg n "$name" '.[] | select(.name == $n)' <<<"$manifest_json")"
    default_branch="$(jq -r '.defaultBranch' <<<"$entry")"
    url="$(jq -r '.url' <<<"$entry")"
    dest="$WORKSPACE_DIR/$name"
    status="ready"
    note=""

    if [[ -d "$dest/.git" ]]; then
        # Never clobber work in progress.
        if [[ -n "$(git -C "$dest" status --porcelain)" ]]; then
            log_warn "$name: uncommitted changes in workspace - skipping refresh."
            status="dirty"
            note="uncommitted changes preserved"
            results="$(jq -c --argjson e "$entry" --arg s "$status" --arg no "$note" \
                '. + [$e + {status:$s, note:$no, path:"'"$dest"'"}]' <<<"$results")"
            log_state "$name" "fetch-skipped" "$note"
            continue
        fi
        log_info "$name: refreshing existing clone."
        git -C "$dest" fetch --quiet origin
        if [[ -n "$REFRESH" ]]; then
            git -C "$dest" checkout --quiet "$default_branch"
            git -C "$dest" reset --hard --quiet "origin/$default_branch"
        fi
    else
        log_info "$name: cloning."
        # gh repo clone carries the gh credentials; plain `git clone` cannot
        # authenticate against private repositories here.
        if ! gh repo clone "$GH_OWNER/$name" "$dest" -- --quiet; then
            log_error "$name: clone failed."
            log_state "$name" "fetch-failed" "git clone failed"
            results="$(jq -c --argjson e "$entry" \
                '. + [$e + {status:"error", note:"clone failed", path:null}]' <<<"$results")"
            continue
        fi
    fi

    # Put the repository on the optimization branch.
    if git -C "$dest" show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
        git -C "$dest" checkout --quiet "$BRANCH_NAME"
        note="existing branch reused"
    else
        git -C "$dest" checkout --quiet -b "$BRANCH_NAME" "$default_branch"
        note="branch created"
    fi

    log_ok "$name: on $BRANCH_NAME ($note)"
    log_state "$name" "fetched" "$note"
    results="$(jq -c --argjson e "$entry" --arg no "$note" \
        '. + [$e + {status:"ready", note:$no, path:"'"$dest"'"}]' <<<"$results")"
done

# --- 5. write the manifest ---------------------------------------------------

jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   --arg branch "$BRANCH_NAME" \
   --arg owner "$GH_OWNER" \
   '{generatedAt:$ts, owner:$owner, branch:$branch, repositories:.}' \
   <<<"$results" > "$MANIFEST_FILE"

ready="$(jq '[.repositories[] | select(.status == "ready")] | length' "$MANIFEST_FILE")"
log_ok "Manifest written: $MANIFEST_FILE ($ready ready)"
