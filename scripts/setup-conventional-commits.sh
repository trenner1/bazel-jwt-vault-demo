#!/bin/bash
# Setup script for conventional commits workflow

echo "Setting up Conventional Commits workflow..."

# Set Git commit message template
echo "Configuring Git commit message template..."
git config commit.template .gitmessage
git config commit.verbose true

# Install commit message validation hook
echo "Installing commit message validation hook..."
if [ -d ".git/hooks" ]; then
    cp hooks/commit-msg .git/hooks/commit-msg
    chmod +x .git/hooks/commit-msg
    echo "Commit message validation hook installed"
else
    echo "Not in a Git repository or .git/hooks directory not found"
    echo "   Run this script from the project root after git init"
fi

# Configure helpful Git aliases
echo "Setting up helpful Git aliases..."
git config alias.cm 'commit -m'
git config alias.cma 'commit -am'
git config alias.feat 'commit -m "feat: "'
git config alias.fix 'commit -m "fix: "'
git config alias.docs 'commit -m "docs: "'
git config alias.style 'commit -m "style: "'
git config alias.refactor 'commit -m "refactor: "'
git config alias.test 'commit -m "test: "'
git config alias.chore 'commit -m "chore: "'

echo ""
echo "Conventional Commits setup complete!"
echo ""
echo "Quick reference:"
echo "   git feat 'add new authentication feature'    # feat: add new authentication feature"
echo "   git fix 'resolve token creation error'       # fix: resolve token creation error"  
echo "   git docs 'update installation guide'         # docs: update installation guide"
echo "   git test 'add security validation tests'     # test: add security validation tests"
echo ""
echo "For detailed guidelines, see: docs/COMMIT_STRATEGY.md"
echo ""
echo "Test the setup:"
echo "   git cm 'test: validate commit message format'"