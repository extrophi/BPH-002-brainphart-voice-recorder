# GitHub CLI Quick Reference (2026-02-08)

**Summary of Key Findings**

---

## Core Commands You'll Use

### 1. Authenticate Once
```bash
gh auth login
# Browser opens, you approve → credentials saved
```

### 2. Configure Git
```bash
gh auth setup-git
# Git now auto-uses your gh credentials for push/pull
```

### 3. Create Private Org Repo
```bash
gh repo create org/repo-name --private --add-readme --clone
```

### 4. List Org Repos (JSON)
```bash
gh repo list org-name --json name,url,isPrivate --limit 100
```

### 5. Clone from Org
```bash
gh repo clone org-name/repo-name
```

---

## Critical Findings

### Q1: Does gh org create exist?
**NO.** There is no `gh org create` command.

Organizations must be created via:
- **Web UI**: https://github.com/organizations/new
- **GitHub API**: `gh api /user/orgs` with POST (see reference doc for syntax)

### Q2: Can free accounts create orgs with private repos?
**YES.** Free GitHub accounts can:
- Create unlimited organizations
- Create unlimited private repos per org
- BUT limited to 3 external collaborators per private repo

### Q3: Private repo limits by plan?
**No limits.** All plans (Free, Pro, Team, Enterprise) support:
- Unlimited private repositories
- Unlimited collaborators (except free org: 3 external)

The cost difference is for **features** (security tools, compliance), not repo count.

### Q4: How does git auth work with gh?
```
gh auth login
    ↓ (stores token)
gh auth setup-git
    ↓ (adds to ~/.gitconfig)
git push/pull
    ↓ (calls gh auth git-credential)
credentials returned automatically
```

**You never run `gh auth git-credential` directly** — Git calls it internally.

### Q5: Creating org repos via CLI
```bash
# Simple way
gh repo create org/repo --private

# With all options
gh repo create org/repo --private \
  --description "..." \
  --gitignore Python \
  --license MIT \
  --add-readme \
  --clone
```

### Q6: Using gh api for advanced org work
```bash
# List org repos (REST)
gh api orgs/my-org/repos

# Get org details (GraphQL)
gh api graphql -F org='my-org' -f query='
  query($org: String!) {
    organization(login: $org) {
      name
      description
    }
  }
'

# Create repo via API
gh api orgs/my-org/repos \
  --method POST \
  -f name='new-repo' \
  -f private=true
```

---

## Token Types & Scopes

**Default scopes:** `repo`, `read:org`, `gist`

**For org administration:** Add `admin:org` scope
```bash
gh auth logout
gh auth login --scopes admin:org,repo
```

---

## Troubleshooting Quick Fixes

**"Not authenticated"**
```bash
gh auth logout && gh auth login
```

**Git still asking for password**
```bash
git config --global credential.helper
# Should show: !/usr/bin/gh auth git-credential
# If blank, run: gh auth setup-git
```

**"403 Forbidden" on org operations**
- You may need org admin role
- May need `admin:org` scope → re-login with new scopes

---

## Full Documentation

See `/docs/GITHUB_CLI_REFERENCE.md` for:
- All flags and options for every command
- Complete syntax tables
- Advanced usage examples
- Troubleshooting guide
- API endpoint reference

---

## Key URLs

- CLI Reference: https://cli.github.com/manual
- GitHub Docs: https://docs.github.com
- Pricing: https://github.com/pricing
- API: https://docs.github.com/en/rest
