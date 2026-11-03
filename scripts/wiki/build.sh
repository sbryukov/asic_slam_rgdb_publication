#!/usr/bin/env bash
# =============================================================================
#  Build the GitHub Wiki version of the paper.
#
#  Usage:  scripts/wiki/build.sh [out_dir] [pdf]
#          (defaults: build/wiki  build/main.pdf;  or simply `make wiki`)
#
#  Result (copied as is into the root of the <repo>.wiki.git repository):
#    <out_dir>/Home.md                    article text + PDF download link
#    <out_dir>/assets/<WIKI_PDF_NAME>     the PDF
#    <out_dir>/assets/figures/*.png       figures/algorithms rendered to PNG
#
#  Environment:
#    WIKI_BASE_URL  https://github.com/<owner>/<repo>/wiki  (derived from the
#                   `origin` remote if unset)
#    WIKI_PDF_NAME  file name of the PDF in the wiki (default: asic_slam.pdf)
#    PANDOC         pandoc binary, >= 3.1 (default: pandoc)
# =============================================================================
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
out=${1:-$root/build/wiki}
pdf=${2:-$root/build/main.pdf}
pdf_name=${WIKI_PDF_NAME:-asic_slam.pdf}
pandoc=${PANDOC:-pandoc}

[ -s "$pdf" ] || { echo "wiki: PDF not found: $pdf (run 'make pdf' first)" >&2; exit 1; }

if [ -z "${WIKI_BASE_URL:-}" ]; then
  remote=$(git -C "$root" remote get-url origin 2>/dev/null || true)
  slug=$(sed -E 's#^(https://[^/]+/|git@[^:]+:)##; s#\.git$##' <<<"$remote")
  WIKI_BASE_URL="https://github.com/${slug:-OWNER/REPO}/wiki"
fi

sha=${GITHUB_SHA:-$(git -C "$root" rev-parse --verify -q HEAD || echo unknown)}
ref=${GITHUB_REF_NAME:-$(git -C "$root" symbolic-ref --short -q HEAD || echo local)}
build_info="Version: ${ref} @ ${sha:0:7}, built $(date -u '+%Y-%m-%d %H:%M UTC')"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

rm -rf "$out"
mkdir -p "$out/assets"

# 1. flatten sources, render TikZ/algorithms/placeholders to PNG
python3 "$here/prepare.py" "$root/main.tex" "$work"
[ -d "$work/figures" ] && cp -r "$work/figures" "$out/assets/"

# 2. LaTeX -> GitHub-flavoured Markdown
( cd "$root" && "$pandoc" "$work/flat.tex" \
    --from latex --to gfm --wrap=none \
    --citeproc --bibliography references.bib \
    --lua-filter "$here/wiki.lua" \
    -M "pdf_url=$WIKI_BASE_URL/assets/$pdf_name" \
    -M "pdf_name=$pdf_name" \
    -M "build_info=$build_info" \
    -M "asset_base=$WIKI_BASE_URL/assets/" \
    -o "$out/Home.md" )

# 3. the PDF itself
cp "$pdf" "$out/assets/$pdf_name"

echo "wiki: $out/Home.md ($(wc -l <"$out/Home.md") lines), $(find "$out/assets" -type f | wc -l) assets"
