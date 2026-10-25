#!/usr/bin/env bash
# Regenerate the public skills/ from the private source of truth, scrubbed and leak-gated.
#
# The private workspace is authoritative. This copies only the PUBLIC allow-list below,
# runs the full scrub (brand -> neutral, internal paths -> placeholders, memory links
# stripped), then runs the leak gate. If the gate finds ANY private reference the sync
# ABORTS and nothing is written to skills/ — fix the source skill (or drop it from the
# allow-list) and re-run.
#
#   scripts/sync-from-private.sh [path-to-private-repo]
#   or set PRIVATE_SKILLS_REPO; default: ../skills-private
#
# Optional: point AGENT_SKILLS_BLOCKLIST at a newline-separated file of client/people
# proper nouns to also gate on (kept out of this public repo). Defaults to
# <private-repo>/.blocklist when that file exists.
#
# After it runs clean: review `git diff`, then branch + PR.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRIV="${1:-${PRIVATE_SKILLS_REPO:-$ROOT/../skills-private}}"
SRC="$PRIV/skills"
[ -d "$SRC" ] || { echo "private skills dir not found: $SRC" >&2; exit 1; }
[ -z "${AGENT_SKILLS_BLOCKLIST:-}" ] && [ -f "$PRIV/.blocklist" ] && export AGENT_SKILLS_BLOCKLIST="$PRIV/.blocklist"
# Neutralize the containing workspace folder name during scrub (derived, not hardcoded).
[ -z "${AGENT_SKILLS_WORKSPACE:-}" ] && export AGENT_SKILLS_WORKSPACE="$(basename "$(dirname "$PRIV")")"

# PUBLIC allow-list — the only skills that may be published. Held skills (saturated with
# client/infra detail that cannot be auto-scrubbed) are intentionally absent.
ALLOW="backend-architecture build-review-loop capability-intake competitor-market-analysis \
context-audit data-analysis-insights data-privacy-security dev-agents dev-patterns \
frontend-system-design idea-validator intellectual-property-licensing international-legal-research \
legal-document-drafter llm-council make-slides password-authentication-security \
privacy-data-protection-law project-estimation-planning project-start rea-research \
requirements-business-analyst secrets-credential-manager seo-tech-stack setup-project-context \
shopify-ui-audit site-incident sop-process-builder task-dispatch tech-research-intelligence \
technical-feasibility update-md"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/skills"
n=0
for s in $ALLOW; do
  if [ -d "$SRC/$s" ]; then cp -R "$SRC/$s" "$TMP/skills/"; n=$((n+1)); else echo "WARN missing in private: $s" >&2; fi
done
echo "copied $n skills from private"

python3 "$ROOT/scripts/scrub_gate.py" scrub "$TMP"      # scrub + gate; nonzero aborts (set -e)

# Gate passed — swap into place.
rm -rf "$ROOT/skills"; mkdir -p "$ROOT/skills"
cp -R "$TMP/skills/." "$ROOT/skills/"
python3 "$ROOT/scripts/build-readme.py"
echo "sync OK: skills/ regenerated and README rebuilt. Review git diff, then PR."
