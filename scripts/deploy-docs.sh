#!/bin/bash
set -e

# Deployment script for TypeDoc documentation to GitHub Pages
# Usage: ./scripts/deploy-docs.sh <tag-name>
# Example: ./scripts/deploy-docs.sh v1.21.1

# Validate tag name argument
if [ -z "${1}" ]; then
  echo "Error: Tag name is required"
  echo "Usage: ${0} <tag-name>"
  echo "Example: ${0} v1.21.1"
  exit 1
fi

TAG_NAME="${1}"
DOCS_OUTPUT_DIR="./tmp/docs"

echo "Deploying documentation for tag: ${TAG_NAME}"

# Clean up any previous documentation
rm -rf "${DOCS_OUTPUT_DIR}"

# Generate TypeDoc documentation into temporary directory
echo "Generating TypeDoc documentation..."
npm exec typedoc

# Ensure docs were generated
if [ ! -d "${DOCS_OUTPUT_DIR}" ]; then
  echo "Error: Documentation was not generated at ${DOCS_OUTPUT_DIR}"
  exit 1
fi

# Store current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Check if gh-pages branch exists locally
if git show-ref --verify --quiet refs/heads/gh-pages; then
  echo "Checking out existing gh-pages branch..."
  git checkout gh-pages
elif git ls-remote --exit-code --heads origin gh-pages > /dev/null 2>&1; then
  echo "Checking out gh-pages branch from remote..."
  git checkout -b gh-pages origin/gh-pages
else
  echo "Creating new orphan gh-pages branch..."
  git checkout --orphan gh-pages
  # Remove all files from the index
  git rm -rf . > /dev/null 2>&1 || true
  # Create initial empty commit
  git commit --allow-empty -m "Initial gh-pages commit"
fi

# Create versioned directory
echo "Creating versioned directory: ${TAG_NAME}"
mkdir -p "${TAG_NAME}"

# Copy generated docs to versioned directory
echo "Copying documentation to ${TAG_NAME}/"
cp -r "${DOCS_OUTPUT_DIR}"/* "${TAG_NAME}/"

# Create/update latest redirect
echo "Creating latest redirect..."
mkdir -p latest
cat > latest/index.html << EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Redirecting to latest documentation...</title>
  <meta http-equiv="refresh" content="0; url=../${TAG_NAME}/">
  <link rel="canonical" href="../${TAG_NAME}/">
</head>
<body>
  <p>Redirecting to <a href="../${TAG_NAME}/">latest documentation</a>...</p>
  <script>
    window.location.href = "../${TAG_NAME}/";
  </script>
</body>
</html>
EOF

# Stage all changes
git add "${TAG_NAME}" latest/index.html

# Commit if there are changes
if git diff --staged --quiet; then
  echo "No changes to commit"
else
  echo "Committing documentation for ${TAG_NAME}..."
  git commit -m "Add ${TAG_NAME} docs"

  echo "Documentation committed to gh-pages branch!"
  echo "Ready to push to deploy docs to:"
  echo "  Version-specific: https://modelcontextprotocol.github.io/typescript-sdk/${TAG_NAME}/"
  echo "  Latest: https://modelcontextprotocol.github.io/typescript-sdk/latest/"
fi

# Return to original branch
echo "Returning to ${CURRENT_BRANCH} branch..."
git checkout "${CURRENT_BRANCH}"

echo "Done!"
