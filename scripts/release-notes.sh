#!/usr/bin/env bash
#
# release-notes.sh VERSION [CHANGELOG]
#
# Prints the GitHub release notes for VERSION (e.g. 1.42.0): what changed,
# taken from that version's section of CHANGELOG.md, then installation and
# requirements. Used by .github/workflows/release.yml; run it locally to
# preview, or with `gh release edit vX.Y.Z --notes-file -` to backfill.
#
# A version with no CHANGELOG section still gets notes — with a pointer to
# the changelog — and a warning on stderr, so a release never fails over it.

set -euo pipefail

VERSION="${1:?usage: release-notes.sh VERSION [CHANGELOG]}"
CHANGELOG="${2:-CHANGELOG.md}"
REPO_URL="https://github.com/mkrkmz/RELL"

# Lines after "## [VERSION]" up to the next "## [" heading; leading and
# trailing blank lines dropped.
changes="$(awk -v version="$VERSION" '
    /^## \[/ {
        if (inside) exit
        if (index($0, "## [" version "]") == 1) { inside = 1; next }
    }
    inside { print }
' "$CHANGELOG" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"

echo "## What's new in RELL ${VERSION}"
echo
if [[ -n "$changes" ]]; then
    echo "$changes"
else
    echo "::warning::CHANGELOG.md has no section for ${VERSION}" >&2
    echo "See the [changelog](${REPO_URL}/blob/main/CHANGELOG.md) for what changed."
fi

cat <<EOF

---

## Installation

1. Download \`RELL-${VERSION}-macOS.dmg\` below, open it, and drag **Reader for Language Learner** to Applications.
2. The app is not signed with an Apple Developer certificate, so macOS blocks the first launch. To allow it, do **one** of:

   **macOS 15 (Sequoia) or later:** double-click the app once (you'll see "could not be verified" → click **Done**), then open **System Settings → Privacy & Security**, scroll to the message about the app, and click **Open Anyway** → confirm with your password. It opens normally from then on.

   **Any macOS — Terminal (one line):**
   \`\`\`
   xattr -dr com.apple.quarantine "/Applications/Reader for Language Learner.app"
   \`\`\`
   Then open the app normally. This removes the download-quarantine flag; the app is safe — it simply lacks Apple's notarization stamp.

> The older "right-click → Open" trick no longer works on macOS 15 for un-notarized apps — use one of the methods above.

## Requirements

- macOS 15 (Sequoia) or later
- For the AI features: on a Mac with Apple Intelligence (macOS 26+), many work with no setup, offline. Otherwise — and for the rest — LM Studio or Ollama on your Mac, or an OpenAI/Anthropic API key.
EOF
