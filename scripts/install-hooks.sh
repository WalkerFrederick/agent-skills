#!/usr/bin/env bash
# Installs the gitleaks pre-commit hook into .git/hooks (hooks aren't versioned).
set -euo pipefail
cd "$(dirname "$0")/.."

cp scripts/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
echo "✓ pre-commit hook installed (gitleaks)"
