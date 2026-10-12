#!/usr/bin/env bash
# Watch for Org releases newer than the one org.nvim is measured against
# (.github/workflows/org-release.yml runs it weekly; see "Watching for Org
# releases" in CONTRIBUTING.md).
#
#   release-watch.sh pinned                  the pinned Org version (ORG_VERSION
#                                            in .github/workflows/difftest.yml)
#   release-watch.sh latest                  the newest Org release: the highest
#                                            of GNU ELPA's org package and the
#                                            release_* tags of the org-mode git
#                                            repository
#   release-watch.sh newer OLD NEW           exit 0 when NEW is a later version
#   release-watch.sh inventory VER OUTDIR    fetch Org VER (GNU ELPA, else the
#                                            git tag) and run inventory.el of
#                                            docs/parity/ on it, into
#                                            OUTDIR/{commands,options}.tsv
#   release-watch.sh report OLDDIR NEWDIR OLD NEW
#                                            the Markdown report: what changed
#                                            between two inventories, and what
#                                            docs/parity/inventory.tsv lacks
#   release-watch.sh issue NEW PINNED REPORT open the issue for NEW (label
#                                            org-release) or update the open one;
#                                            never a second one. DRY_RUN=1 prints
#                                            what it would do instead
#
# ORG_EMACS (default emacs) runs the inventory; ELPA_URL and ORG_GIT_URL
# change where releases are looked up (for tests).
set -euo pipefail
# sort and join must agree on the order
export LC_ALL=C

root=$(cd "$(dirname "$0")/../.." && pwd)
ELPA_URL=${ELPA_URL:-https://elpa.gnu.org/packages}
ORG_GIT_URL=${ORG_GIT_URL:-https://git.savannah.gnu.org/git/emacs/org-mode.git}
LABEL=org-release

die() {
  echo "release-watch: $*" >&2
  exit 2
}

# the highest of the versions on stdin (one per line)
highest() {
  grep -E '^[0-9]+(\.[0-9]+)*$' | sort -V | tail -n 1
}

pinned() {
  local v
  v=$(sed -n 's/^ *ORG_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\} *$/\1/p' "$root/.github/workflows/difftest.yml" | head -n 1)
  [ -n "$v" ] || die "no ORG_VERSION in .github/workflows/difftest.yml"
  echo "$v"
}

# the versions GNU ELPA has a tarball of
elpa_versions() {
  curl -fsSL --retry 3 "$ELPA_URL/org.html" 2>/dev/null |
    grep -oE 'org-[0-9]+(\.[0-9]+)+\.tar' | sed 's/^org-//; s/\.tar$//' || true
}

# the release_* tags of the org-mode repository, as versions
git_versions() {
  git ls-remote --tags --refs "$ORG_GIT_URL" 'release_*' 2>/dev/null | sed -n 's#.*refs/tags/release_##p' || true
}

# A release is tagged in git before GNU ELPA publishes its tarball, so the
# latest is the highest of either.
latest() {
  local v
  v=$({
    elpa_versions
    git_versions
  } | highest || true)
  [ -n "$v" ] || die "could not find the latest Org release (GNU ELPA and $ORG_GIT_URL)"
  echo "$v"
}

newer() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$2" ]
}

# Print the Lisp directory of Org VER, fetched under TMP: GNU ELPA's
# tarball, else the release_VER tag of the git repository with the
# autoloads and org-version.el generated (as the tarball has them).
fetch_org() {
  local tmp=$1 ver=$2
  if curl -fsSL --retry 3 "$ELPA_URL/org-$ver.tar" -o "$tmp/org.tar" 2>/dev/null; then
    tar -x -C "$tmp" -f "$tmp/org.tar"
    [ -d "$tmp/org-$ver" ] || die "org-$ver.tar has no org-$ver/ directory"
    echo "Org $ver: GNU ELPA's org-$ver.tar" >&2
    echo "$tmp/org-$ver"
  else
    git clone -q --depth 1 --branch "release_$ver" "$ORG_GIT_URL" "$tmp/org-mode" >&2 ||
      die "Org $ver is neither on GNU ELPA nor tagged release_$ver"
    make -s -C "$tmp/org-mode" EMACS="${ORG_EMACS:-emacs}" autoloads >&2
    echo "Org $ver: the release_$ver git tag" >&2
    echo "$tmp/org-mode/lisp"
  fi
}

inventory() {
  local ver=$1 out=$2 tmp dir
  mkdir -p "$out"
  tmp=$(mktemp -d)
  dir=$(fetch_org "$tmp" "$ver")
  "${ORG_EMACS:-emacs}" -Q --batch -l "$root/docs/parity/inventory.el" \
    --eval "(org-parity-inventory \"$dir/\" \"$out/\")"
  rm -rf "$tmp"
  [ -s "$out/commands.tsv" ] && [ -s "$out/options.tsv" ] || die "the inventory of Org $ver is empty"
}

# LIBRARY<TAB>SYMBOL lines of FILE as "SYMBOL<TAB>LIBRARY", sorted by symbol
by_symbol() {
  awk -F'\t' 'NF >= 2 { print $2 "\t" $1 }' "$1" | sort -t "$(printf '\t')" -k1,1
}

# a Markdown list of SYMBOL<TAB>LIBRARY lines on stdin, at most 300 of them
md_list() {
  awk -F'\t' '
    NR <= 300 { print "- `" $1 "` (" $2 ")" }
    END { if (NR > 300) print "- ... and " NR - 300 " more"; if (NR == 0) print "None." }'
}

report() {
  local old=$1 new=$2 oldv=$3 newv=$4 kind tmp
  tmp=$(mktemp -d)
  cut -f1,2 "$root/docs/parity/inventory.tsv" | awk -F'\t' '{ print $2 }' | sort -u >"$tmp/tracked"
  echo "Org $newv is out. org.nvim is measured against Org $oldv (the parity"
  echo "inventory, the parity fixtures and the nightly difftest)."
  echo
  echo "Run by \`scripts/emacs-parity/release-watch.sh\`: \`docs/parity/inventory.el\`"
  echo "listed the interactive commands and user options of both releases."
  echo
  echo "| | Org $oldv | Org $newv | Added | Removed | Moved |"
  echo "| --- | --- | --- | --- | --- | --- |"
  for kind in commands options; do
    by_symbol "$old/$kind.tsv" >"$tmp/old-$kind"
    by_symbol "$new/$kind.tsv" >"$tmp/new-$kind"
    join -t "$(printf '\t')" -v 2 "$tmp/old-$kind" "$tmp/new-$kind" >"$tmp/added-$kind"
    join -t "$(printf '\t')" -v 1 "$tmp/old-$kind" "$tmp/new-$kind" >"$tmp/removed-$kind"
    join -t "$(printf '\t')" "$tmp/old-$kind" "$tmp/new-$kind" |
      awk -F'\t' '$2 != $3 { print $1 "\t" $2 " → " $3 }' >"$tmp/moved-$kind"
    printf '| %s | %d | %d | %d | %d | %d |\n' "$kind" \
      "$(wc -l <"$tmp/old-$kind")" "$(wc -l <"$tmp/new-$kind")" "$(wc -l <"$tmp/added-$kind")" \
      "$(wc -l <"$tmp/removed-$kind")" "$(wc -l <"$tmp/moved-$kind")"
  done
  for kind in commands options; do
    echo
    echo "### Added $kind"
    echo
    md_list <"$tmp/added-$kind"
    echo
    echo "### Removed $kind"
    echo
    md_list <"$tmp/removed-$kind"
    if [ -s "$tmp/moved-$kind" ]; then
      echo
      echo "### Moved $kind (another library)"
      echo
      md_list <"$tmp/moved-$kind"
    fi
  done
  # what docs/parity/inventory.tsv doesn't list yet: a status to decide
  cat "$tmp/new-commands" "$tmp/new-options" | sort -t "$(printf '\t')" -k1,1 >"$tmp/new-all"
  join -t "$(printf '\t')" -v 1 "$tmp/new-all" "$tmp/tracked" >"$tmp/untracked"
  echo
  echo "### Not in \`docs/parity/inventory.tsv\` yet"
  echo
  md_list <"$tmp/untracked"
  echo
  echo "To move to Org $newv: bump \`ORG_VERSION\` in \`.github/workflows/difftest.yml\`"
  echo "and the version checks in \`scripts/emacs-parity/\`, regenerate the fixtures"
  echo "(\`make parity-fixtures\`), give every new command and option a status in"
  echo "\`docs/parity/inventory.tsv\`, and run \`make difftest\` against it (\"Watching for"
  echo "Org releases\" in CONTRIBUTING.md)."
  rm -rf "$tmp"
}

run() {
  if [ -n "${DRY_RUN:-}" ]; then
    printf 'would run:'
    printf ' %q' "$@"
    echo
  else
    "$@"
  fi
}

issue() {
  local newv=$1 pinned=$2 body=$3 title num closed
  title="Org $newv released (org.nvim is measured against $pinned)"
  head -c 60000 "$body" >"$body.issue"
  printf '\n\n<!-- org-release-watch: %s -->\n' "$newv" >>"$body.issue"
  # handled already: an issue for this release that was closed
  closed=$(gh issue list --label "$LABEL" --state closed --limit 100 --json number,title \
    --jq "map(select(.title | startswith(\"Org $newv released\"))) | .[0].number // empty")
  num=$(gh issue list --label "$LABEL" --state open --limit 1 --json number --jq '.[0].number // empty')
  if [ -n "$num" ]; then
    echo "Updating issue #$num for Org $newv"
    run gh issue edit "$num" --title "$title" --body-file "$body.issue"
  elif [ -n "$closed" ]; then
    echo "Issue #$closed for Org $newv was closed: not opening another one"
  else
    run gh label create "$LABEL" --color 0E8A16 --description "A new Emacs Org release to measure against" 2>/dev/null || true
    echo "Opening an issue for Org $newv"
    run gh issue create --title "$title" --label "$LABEL" --body-file "$body.issue"
  fi
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case "$cmd" in
  pinned) pinned ;;
  latest) latest ;;
  newer) [ $# -eq 2 ] || die "usage: newer OLD NEW"; newer "$1" "$2" ;;
  inventory) [ $# -eq 2 ] || die "usage: inventory VERSION OUTDIR"; inventory "$1" "$2" ;;
  report) [ $# -eq 4 ] || die "usage: report OLDDIR NEWDIR OLD NEW"; report "$1" "$2" "$3" "$4" ;;
  issue) [ $# -eq 3 ] || die "usage: issue NEW PINNED REPORT"; issue "$1" "$2" "$3" ;;
  *) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
