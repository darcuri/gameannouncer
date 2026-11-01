#!/bin/sh
# Applies the repository protections that GitHub's free plan only allows on public repos.
# Run it right after making the repo public. It's safe to re-run: rulesets that already
# exist (by name) are skipped, and the security settings are idempotent.
#
# Usage: scripts/configure-github.sh [owner/repo]
set -eu
REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
echo "Configuring $REPO"

existing="$(gh api "repos/$REPO/rulesets" -q '.[].name')"

ruleset() {
    name="$1"
    if printf '%s\n' "$existing" | grep -qxF "$name"; then
        echo "  ruleset exists: $name"
    else
        gh api -X POST "repos/$REPO/rulesets" --input - >/dev/null
        echo "  ruleset created: $name"
    fi
}

# Nobody, including admins, can force-push or delete main.
ruleset "main: no force-push or deletion" <<'EOF'
{
  "name": "main: no force-push or deletion",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [ { "type": "deletion" }, { "type": "non_fast_forward" } ],
  "bypass_actors": []
}
EOF

# Changes reach main only through a pull request with passing CI. Repository admins can
# bypass it, so the owner can still push directly.
ruleset "main: pull requests with passing CI" <<'EOF'
{
  "name": "main: pull requests with passing CI",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [ { "context": "build-and-test" } ]
      }
    }
  ],
  "bypass_actors": [ { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" } ]
}
EOF

# Published release tags can't be moved or deleted. To fix a bad tag, disable this ruleset.
ruleset "release tags are immutable" <<'EOF'
{
  "name": "release tags are immutable",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "rules": [ { "type": "deletion" }, { "type": "update" }, { "type": "non_fast_forward" } ],
  "bypass_actors": []
}
EOF

# CI on pull requests from forks waits for approval, so outside code never runs unreviewed.
gh api -X PUT "repos/$REPO/actions/permissions/fork-pr-contributor-approval" \
    -f approval_policy=all_external_contributors >/dev/null
echo "  fork pull request CI: needs approval for all outside contributors"

# Secret scanning blocks pushes that contain credentials; free on public repos.
gh api -X PATCH "repos/$REPO" --input - >/dev/null <<'EOF'
{ "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" } } }
EOF
echo "  secret scanning and push protection: on"

# Lets people report security problems privately (see SECURITY.md).
gh api -X PUT "repos/$REPO/private-vulnerability-reporting" >/dev/null
echo "  private vulnerability reporting: on"

gh api -X PUT "repos/$REPO/vulnerability-alerts" >/dev/null
echo "  Dependabot alerts: on"
