# Conventional Commits Strategy

This project follows the [Conventional Commits](https://www.conventionalcommits.org/) specification for standardized commit messages.

## Commit Message Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

## Types

| Type | Description | Example |
|------|-------------|---------|
| **feat** | A new feature | `feat(auth): add OIDC authentication` |
| **fix** | A bug fix | `fix(vault): resolve token creation error` |
| **docs** | Documentation changes | `docs(readme): update setup instructions` |
| **style** | Code style changes (formatting, etc) | `style(broker): fix indentation` |
| **refactor** | Code refactoring | `refactor(cli): improve error handling` |
| **perf** | Performance improvements | `perf(auth): optimize token validation` |
| **test** | Test additions/modifications | `test(security): add team isolation tests` |
| **build** | Build system changes | `build(docker): update compose configuration` |
| **ci** | CI/CD changes | `ci(github): add security scanning workflow` |
| **chore** | Maintenance tasks | `chore(deps): update vault client version` |
| **revert** | Reverts a previous commit | `revert: feat(auth): add OIDC authentication` |

## Scopes

Use these standardized scopes to indicate the area of change:

| Scope | Description | Examples |
|-------|-------------|----------|
| **auth** | Authentication system | OIDC, JWT, session management |
| **vault** | HashiCorp Vault integration | Policies, roles, token management |
| **broker** | Python broker service | Flask app, endpoints, middleware |
| **cli** | Command-line tools | bazel-auth, bazel-auth-simple |
| **security** | Security features | Policies, access control, encryption |
| **config** | Configuration management | Environment variables, setup scripts |
| **docs** | Documentation | README, guides, API docs |
| **testing** | Test infrastructure | Test scripts, CI/CD testing |
| **docker** | Container configuration | Dockerfiles, compose files |
| **ui** | User interface | Web pages, forms, styling |

## Commit Message Guidelines

### Subject Line (First Line)
- Use imperative mood: "add feature" not "added feature"
- Keep under 50 characters
- Don't end with a period
- Capitalize the first letter after the colon

### Body (Optional)
- Wrap at 72 characters
- Explain **what** and **why**, not **how**
- Use bullet points for multiple changes
- Reference issues/PRs when relevant

### Footer (Optional)
- Reference breaking changes: `BREAKING CHANGE: <description>`
- Reference issues: `Closes #123`, `Fixes #456`
- Reference co-authors: `Co-authored-by: Name <email>`

## Examples

### Simple Feature Addition
```
feat(auth): add PKCE flow support for CLI authentication

Implements OAuth 2.0 PKCE (Proof Key for Code Exchange) flow for secure
CLI authentication without client secrets. Improves security for public
clients and mobile applications.

Closes #42
```

### Bug Fix
```
fix(vault): resolve token creation permission denied error

Team tokens were failing to create due to incorrect policy mapping.
Updated policy assignments to match team-specific token roles.

- Fix mobile team token policy assignment
- Update backend team role configuration  
- Add validation for token role permissions

Fixes #58
```

### Breaking Change
```
feat(broker)!: migrate session storage to Redis

BREAKING CHANGE: Session storage moved from in-memory to Redis.
Requires Redis service and updated environment configuration.

- Add Redis dependency to docker-compose
- Update session middleware for Redis backend
- Add Redis health checks

Migration guide: See docs/MIGRATION.md
```

### Documentation Update
```
docs(testing): add comprehensive security testing guide

- Add team token isolation test procedures
- Document OIDC authentication flow testing
- Include troubleshooting common test failures
- Add performance testing guidelines
```

### Multiple Scope Changes
```
feat(auth,vault): implement team-specific token creation

- Add token auth roles for each team
- Implement cross-team access restrictions
- Update vault policies for team isolation
- Add token creation endpoints to broker

Co-authored-by: Security Team <security@company.com>
```

## Setup Git Template

Configure Git to use the commit message template:

```bash
# Set the commit message template
git config commit.template .gitmessage

# Configure Git to open editor for commit messages
git config commit.verbose true
```

## Automated Validation

### Pre-commit Hook (Optional)

Create `.git/hooks/commit-msg`:

```bash
#!/bin/sh
# Validate commit message format

commit_regex='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?\!?:.{1,50}'

if ! grep -qE "$commit_regex" "$1"; then
    echo "❌ Invalid commit message format!"
    echo "Format: <type>[scope]: <description>"
    echo "Example: feat(auth): add OIDC authentication"
    exit 1
fi
```

### VS Code Extension

Install the "Conventional Commits" extension for VS Code to get autocomplete and validation.

## Release Management

### Semantic Versioning

Commit types automatically determine version bumps:

- `feat:` → Minor version bump (1.0.0 → 1.1.0)
- `fix:` → Patch version bump (1.0.0 → 1.0.1)  
- `BREAKING CHANGE:` → Major version bump (1.0.0 → 2.0.0)

### Changelog Generation

Use tools like `conventional-changelog` to auto-generate changelogs:

```bash
npm install -g conventional-changelog-cli
conventional-changelog -p angular -i CHANGELOG.md -s
```

## Branch Naming

Align branch names with commit types:

```
feature/auth-oidc-integration
bugfix/vault-token-creation
docs/security-testing-guide
hotfix/session-timeout-error
chore/update-dependencies
```

## Review Guidelines

### Pull Request Titles
Use the same format as commit messages:
```
feat(auth): add OIDC authentication with Okta integration
```

### Commit Squashing
- Squash related commits before merging
- Keep meaningful commits separate
- Ensure final commit message follows convention

## Examples from This Project

Here are examples of good commit messages for recent changes:

```
feat(auth): implement hybrid JWT + token roles authentication
fix(broker): resolve OKTA_DOMAIN extraction from auth URL  
test(security): add team token creation isolation validation
docs(architecture): update authentication flow diagrams
refactor(vault): improve team-specific policy structure
perf(cli): optimize PKCE flow parameter generation
build(docker): add broker health checks to compose
ci(github): add automated security testing workflow
```

This strategy ensures:
- ✅ **Consistent** commit history
- ✅ **Automated** release management  
- ✅ **Clear** change tracking
- ✅ **Efficient** code review process
- ✅ **Professional** project maintenance