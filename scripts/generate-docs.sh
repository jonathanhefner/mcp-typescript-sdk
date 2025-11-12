#!/bin/bash
set -e

# Generates versioned API documentation and commits to gh-pages branch
#
# PURPOSE:
#   This script generates API documentation in the gh-pages branch for a
#   specific version tag while preserving existing versioned documentation.
#   This script is invoked by the publish-docs job in the GitHub Actions
#   workflow (.github/workflows/main.yml) when a release is published.
#
# HOW IT WORKS:
#   - Creates isolated git worktrees for the specified tag and gh-pages branch
#   - Generates documentation into gh-pages in a directory based on the tag name (e.g., v1.2.3/)
#   - Copies custom documentation from docs/ into gh-pages root
#   - Updates the "latest" redirect to point to the most recent version
#   - If missing, generates a landing page with links to all versions
#   - Commits changes to gh-pages (does not push automatically)
#
# WORKFLOW:
#   1. Run this script with a tag name: `./scripts/generate-docs.sh v1.2.3`
#   2. Script generates docs and commits to local gh-pages branch
#   3. Push gh-pages branch to deploy: `git push origin gh-pages`

# Validate tag name argument
if [ -z "${1}" ]; then
  echo "Error: Tag name is required"
  echo "Usage: ${0} <tag-name>"
  echo "Example: ${0} v1.2.3"
  exit 1
fi

TAG_NAME="${1}"
REPO_ROOT="$(git rev-parse --show-toplevel)"

echo "Generating documentation for tag: ${TAG_NAME}"

# Create temporary directories for both worktrees
WORKTREE_DIR=$(mktemp -d)
GHPAGES_WORKTREE_DIR=$(mktemp -d)

# Set up trap to clean up both worktrees on exit
trap 'git worktree remove --force "${WORKTREE_DIR}" 2>/dev/null || true; \
      git worktree remove --force "${GHPAGES_WORKTREE_DIR}" 2>/dev/null || true' EXIT

echo "Creating worktree for ${TAG_NAME}..."
git worktree add --quiet "${WORKTREE_DIR}" "${TAG_NAME}"

# Check if gh-pages branch exists
if git show-ref --verify --quiet refs/heads/gh-pages; then
  echo "Creating worktree for existing gh-pages branch..."
  git worktree add --quiet "${GHPAGES_WORKTREE_DIR}" gh-pages
elif git ls-remote --exit-code --heads origin gh-pages > /dev/null 2>&1; then
  echo "Creating worktree for gh-pages branch from remote..."
  git worktree add --quiet "${GHPAGES_WORKTREE_DIR}" -b gh-pages origin/gh-pages
else
  echo "Creating worktree for new orphan gh-pages branch..."
  git worktree add --quiet --detach "${GHPAGES_WORKTREE_DIR}"
  cd "${GHPAGES_WORKTREE_DIR}"
  git checkout --orphan gh-pages
  git rm -rf . > /dev/null 2>&1 || true

  # Configure Jekyll for generated docs
  cat > _config.yml << 'EOF'
# Include generated files and directories which may start with underscores
include:
  - "_*"
EOF

  git add _config.yml
  git commit -m "Initial gh-pages commit"
  cd "${REPO_ROOT}"
fi

# Create target directory for docs
echo "Creating versioned directory: ${TAG_NAME}"
mkdir -p "${GHPAGES_WORKTREE_DIR}/${TAG_NAME}"

# Generate TypeDoc documentation into gh-pages worktree
cd "${WORKTREE_DIR}"
echo "Installing dependencies..."
npm ci --ignore-scripts
echo "Generating TypeDoc documentation..."
npx typedoc src --entryPointStrategy expand --out "${GHPAGES_WORKTREE_DIR}/${TAG_NAME}"
cd "${REPO_ROOT}"

# Ensure docs were generated
if [ -z "$(ls -A "${GHPAGES_WORKTREE_DIR}/${TAG_NAME}")" ]; then
  echo "Error: Documentation was not generated at ${GHPAGES_WORKTREE_DIR}/${TAG_NAME}"
  exit 1
fi

# Change to gh-pages worktree
cd "${GHPAGES_WORKTREE_DIR}"

# Determine if this tag is the latest version
echo "Determining if ${TAG_NAME} is the latest version..."

# Get the latest version from all version directories (excluding 'latest')
LATEST_VERSION=$(printf '%s\n' */ | grep -v '^latest/' | sed 's:/$::' | sort -V | tail -n 1)

if [ "${TAG_NAME}" = "${LATEST_VERSION}" ]; then
  echo "${TAG_NAME} is the latest version"
else
  echo "${TAG_NAME} is not the latest version (latest is ${LATEST_VERSION})"
fi

# Update custom documentation for latest version
if [ "${TAG_NAME}" = "${LATEST_VERSION}" ]; then
  echo "Updating custom documentation..."

  # Clean up old custom docs from gh-pages root (keep only version directories and Jekyll config)
  echo "Cleaning gh-pages root..."
  git ls-tree --name-only HEAD | grep -v '^v[0-9]' | grep -v '^_config\.yml$' | xargs -r git rm -rf

  # Copy custom docs if they exist
  if [ -d "${WORKTREE_DIR}/docs" ]; then
    echo "Copying custom docs from ${WORKTREE_DIR}/docs/..."
    cp -r "${WORKTREE_DIR}/docs/." "${GHPAGES_WORKTREE_DIR}/"
  fi

  # Generate landing page if none exists
  if [ ! -f index.html ] && [ ! -f index.md ]; then
    echo "Generating landing page..."
    cat > index.md << EOF
# MCP TypeScript SDK API Documentation

$(printf '%s\n' */ | grep '^v[0-9]' | sed 's:/$::' | sort -Vr | xargs -I {} printf -- '- [%s](%s/)\n' {} {})
EOF
  fi
fi

# Create/update latest redirect
echo "Creating latest redirect to ${LATEST_VERSION}..."
mkdir -p latest
cat > latest/index.html << EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Redirecting to latest documentation...</title>
  <meta http-equiv="refresh" content="0; url=../${LATEST_VERSION}/">
  <link rel="canonical" href="../${LATEST_VERSION}/">
</head>
<body>
  <p>Redirecting to <a href="../${LATEST_VERSION}/">latest documentation</a>...</p>
  <script>
    window.location.href = "../${LATEST_VERSION}/";
  </script>
</body>
</html>
EOF

# Stage all changes
git add .

# Commit if there are changes
if git diff --staged --quiet; then
  echo "No changes to commit"
else
  echo "Committing documentation for ${TAG_NAME}..."
  git commit -m "Add ${TAG_NAME} docs"

  echo "Documentation committed to gh-pages branch!"
  echo "Push to remote to deploy to GitHub Pages"
fi

echo "Done!"
