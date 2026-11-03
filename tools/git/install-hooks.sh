#!/bin/sh
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"

echo "Configuring git hooks directory to tools/git..."
git config core.hooksPath tools/git
chmod +x "$DIR/pre-commit"

echo "✅ Git pre-commit hook installed successfully."
