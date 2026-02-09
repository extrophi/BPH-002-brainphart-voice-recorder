# GitHub CLI Reference (Fetched: 2026-02-08)

**Research Date**: February 8, 2026
**Sources**: cli.github.com, docs.github.com, github.com/pricing

---

## 1. gh auth login — Authentication Flow

### Command Syntax
```bash
gh auth login [flags]
```

### Description
Authenticates with a GitHub host using a web-based browser flow by default, storing credentials securely in the system credential store.

### Flags

| Flag | Short | Argument | Description |
|------|-------|----------|-------------|
| `--web` | `-w` | none | Open browser to authenticate (default behavior) |
| `--clipboard` | `-c` | none | Copy one-time OAuth device code to clipboard instead of printing |
| `--with-token` | none | none | Read token from standard input (for headless/automated use) |
| `--git-protocol` | `-p` | `ssh` or `https` | Git protocol for operations (defaults to HTTPS) |
| `--hostname` | `-h` | `hostname` | GitHub instance hostname (defaults to github.com) |
| `--scopes` | `-s` | `comma-separated list` | Additional authentication scopes to request beyond defaults |
| `--skip-ssh-key` | none | none | Skip SSH key generation/upload prompt |
| `--insecure-storage` | none | none | Save credentials as plain text instead of using system credential store |

### Token Types & Scopes

**Default minimum scopes requested:**
- `repo` — Full access to private repositories
- `read:org` — Read organization data
- `gist` — Create gists

**Common additional scopes:**
- `admin:org` — Full org control (includes repo, read:org)
- `admin:public_key` — Manage SSH keys
- `admin:repo_hook` — Manage webhooks
- `delete_repo` — Delete repos
- `workflow` — Manage GitHub Actions workflows

### Usage Examples

**Interactive browser-based setup (default):**
```bash
gh auth login
```
This opens your browser, generates a device code, and waits for browser confirmation.

**Clipboard-friendly for remote machines:**
```bash
gh auth login --web --clipboard
```
Copies the device code to clipboard so you don't have to type it.

**Enterprise instance with SSH:**
```bash
gh auth login --hostname enterprise.internal --git-protocol ssh
```

**Headless/automated with token file:**
```bash
gh auth login --with-token < /path/to/token.txt
```

**Specific scopes for workflow automation:**
```bash
gh auth login --scopes repo,admin:org,workflow
```

### Key Details
- **Environment variable**: `GH_TOKEN` can bypass login if set
- **Credential storage**: Uses system keychain (macOS Keychain, Windows Credential Manager, etc.)
- **Multiple accounts**: Can authenticate to multiple GitHub instances; use `gh auth switch` to change
- **Token persistence**: Tokens persist until manually logged out with `gh auth logout`

---

## 2. gh auth setup-git — Credential Helper Configuration

### Command Syntax
```bash
gh auth setup-git [flags]
```

### Flags

| Flag | Short | Argument | Description |
|------|-------|----------|-------------|
| `--hostname` | `-h` | `hostname` | Configure credential helper for specific host only |
| `--force` | `-f` | none | Force setup even if host is not yet authenticated (requires `--hostname`) |

### Description
Configures Git to use GitHub CLI as the credential helper for authenticated hosts. After running this command, `git push`, `git pull`, and other Git operations automatically use your `gh` authentication.

### How It Works Under the Hood

**What it modifies in `~/.gitconfig`:**
```ini
[credential "https://github.com"]
    helper = !/usr/bin/gh auth git-credential

[credential "https://gist.github.com"]
    helper = !/usr/bin/gh auth git-credential
```

When Git needs credentials, it calls `gh auth git-credential`, which returns the authenticated token from `gh`'s credential store.

### Usage Examples

**Setup for all authenticated hosts:**
```bash
gh auth setup-git
```
Automatically discovers all hosts you've authenticated with via `gh auth login` and configures them.

**Setup for a specific enterprise instance:**
```bash
gh auth setup-git --hostname enterprise.internal
```

**Force setup for unauthenticated host (rare):**
```bash
gh auth setup-git --hostname custom.github.com --force
```

### Relationship with gh auth git-credential

**`gh auth git-credential` is NOT a direct command.** It's an internal function called by Git's credential helper system:

1. You run `gh auth setup-git` (one-time setup)
2. Git's config now calls `gh auth git-credential` when it needs credentials
3. `gh auth git-credential` retrieves the token from `gh`'s secure store
4. Git uses that token for authentication

This means you do NOT run `gh auth git-credential` directly; it's automatically invoked by Git through the credential helper protocol.

### Verifying the Setup

```bash
# Check what's configured
git config --global credential.helper
# Output: /usr/bin/gh auth git-credential

# Test it works
git ls-remote https://github.com/username/repo.git
# Should work without prompting for password
```

---

## 3. gh auth — All Subcommands

### Available Subcommands

| Subcommand | Purpose |
|------------|---------|
| `gh auth login` | Authenticate with GitHub (interactive or via token) |
| `gh auth logout` | Remove stored authentication credentials |
| `gh auth refresh` | Refresh authentication tokens |
| `gh auth setup-git` | Configure Git to use gh as credential helper |
| `gh auth status` | Display current authentication status |
| `gh auth switch` | Switch between authenticated accounts |
| `gh auth token` | Display the authentication token for the current account |

### Example: Check Current Auth Status

```bash
gh auth status
# Output:
# Logged in to github.com as username
# Git operations with https protocol will use /usr/bin/gh to authenticate
```

---

## 4. gh repo create — Creating Repos in Organizations

### Command Syntax
```bash
gh repo create [<name>] [flags]
```

### Key Flags for Organization Repos

| Flag | Short | Argument | Description |
|------|-------|----------|-------------|
| `--private` | none | none | Make the repository private |
| `--public` | none | none | Make the repository public (default if not specified) |
| `--internal` | none | none | Make the repository internal (GitHub Enterprise only) |
| `--description` | `-d` | `string` | Repository description |
| `--gitignore` | `-g` | `template` | Gitignore template (e.g., Python, Node, etc.) |
| `--license` | `-l` | `license` | Open Source License (e.g., MIT, Apache-2.0) |
| `--add-readme` | none | none | Add a README file |
| `--clone` | `-c` | none | Clone the repository locally after creation |
| `--push` | none | none | Push local commits to the new repository |
| `--remote` | `-r` | `name` | Name of the remote (default: `origin`) |
| `--source` | `-s` | `path` | Path to existing repository to push |
| `--team` | `-t` | `name` | Organization team to grant access to |

### Creating a Private Repo in an Organization

**Basic syntax:**
```bash
gh repo create org-name/repo-name --private
```

**With description and README:**
```bash
gh repo create org-name/repo-name --private \
  --description "Crisis intervention voice recorder" \
  --add-readme
```

**Full setup (create, clone, and initialize):**
```bash
gh repo create org-name/repo-name --private \
  --description "Project description" \
  --gitignore Python \
  --license MIT \
  --add-readme \
  --clone
```

**Push existing local repo to org:**
```bash
gh repo create org-name/new-repo --private \
  --source=. \
  --push
```

### Important Notes
- **Organization prefix required**: Must use `OWNER/NAME` format for org repos
- **Authentication required**: You must have permission to create repos in the org
- **Non-interactive**: Use flags to skip all prompts
- **Private by default for teams**: Teams can have default visibility settings

---

## 5. gh repo list — Listing Organization Repositories

### Command Syntax
```bash
gh repo list [<owner>] [flags]
```

### Key Flags

| Flag | Short | Argument | Description |
|------|-------|----------|-------------|
| `--json` | `-q` | `fields` | Output as JSON (machine-readable) |
| `--limit` | `-L` | `number` | Maximum repos to list (default: 30) |
| `--visibility` | none | `public/private/internal` | Filter by visibility |
| `--source` | none | `owned/forked/archived` | Filter by source type |
| `--language` | `-l` | `language` | Filter by programming language |
| `--jq` | none | `selector` | Filter JSON output with jq |

### JSON Output Fields

Available fields for `--json`:
- `name`, `nameWithOwner`, `description`, `url`
- `isPrivate`, `visibility`
- `createdAt`, `updatedAt`, `pushedAt`
- `forkCount`, `stargazerCount`
- `primaryLanguage`

### Usage Examples

**List all repos in organization (10 repos, non-interactive):**
```bash
gh repo list my-org --limit 100
```

**List as JSON for scripting:**
```bash
gh repo list my-org --json name,nameWithOwner,isPrivate --limit 100
```

**Filter by private visibility:**
```bash
gh repo list my-org --visibility private
```

**Get all private repos with jq filtering:**
```bash
gh repo list my-org --json name,isPrivate --jq '.[] | select(.isPrivate == true)'
```

---

## 6. gh repo clone — Cloning from Organization

### Command Syntax
```bash
gh repo clone <repository> [<directory>]
```

### Description
Clones a repository from any GitHub user or organization. Authentication is automatic if you've set up `gh auth login` and `gh auth setup-git`.

### Usage Examples

**Clone org repository:**
```bash
gh repo clone my-org/repo-name
```

**Clone to custom directory:**
```bash
gh repo clone my-org/repo-name ./custom-directory
```

**Clone with SSH protocol (if configured):**
```bash
gh repo clone my-org/repo-name
# Uses SSH if git protocol is set to ssh
```

### How It's Different from `git clone`

- **Automatic authentication**: Uses your gh credentials automatically
- **Protocol handling**: Respects your `--git-protocol` preference from `gh auth login`
- **Simpler syntax**: Can omit full URL; just use `owner/repo`

---

## 7. gh org create — Organization Creation

### DOES NOT EXIST

**Important**: There is no `gh org create` command in the GitHub CLI.

Organizations must be created through:
1. **Web UI**: https://github.com/organizations/new
2. **GitHub API**: `gh api` with POST to `/user/orgs` endpoint

### Creating Organization via gh api

**GraphQL method (recommended):**
```bash
gh api graphql -f query='
  mutation {
    createOrganization(input: {name: "org-name", profile_name: "Org Display Name"}) {
      organization {
        name
        url
      }
    }
  }
'
```

**REST API method:**
```bash
gh api /user/orgs \
  -f login='org-name' \
  -f profile_name='Org Display Name' \
  -f billing_email='billing@example.com'
```

### Note
Free GitHub accounts can create organizations with unlimited private repos, but with limited features. Upgrade to GitHub Team or Enterprise Cloud for full feature set on org private repos.

---

## 8. gh api — Making GitHub API Calls

### Command Syntax
```bash
gh api <endpoint> [flags]
```

### Description
Makes authenticated HTTP requests to the GitHub API (REST v3 or GraphQL v4) and prints the response. This is the programmatic way to interact with GitHub beyond built-in CLI commands.

### Key Flags

| Flag | Short | Argument | Description |
|------|-------|----------|-------------|
| `--method` | `-X` | `GET/POST/PATCH/DELETE/etc` | HTTP method (defaults to GET, or POST if fields added) |
| `--field` | `-F` | `key=value` | Typed parameter (auto-converts booleans, integers, nulls, file reads with `@`) |
| `--raw-field` | `-f` | `key=value` | Static string parameter |
| `--header` | `-H` | `key:value` | Custom HTTP header |
| `--input` | none | `file` | Request body from file (for complex payloads) |
| `--jq` | `-q` | `selector` | Filter response using jq syntax |
| `--paginate` | none | none | Fetch all result pages sequentially |
| `--slurp` | `-s` | none | Combine paginated results into single JSON array |
| `--preview` | `-p` | `header` | Opt into experimental API features |

### REST API Endpoint Handling

**Basic format:**
```bash
gh api repos/{owner}/{repo}/issues
# Auto-replaces {owner} and {repo} with current repo values
```

**Explicit placeholders:**
```bash
gh api repos/my-org/my-repo/releases
```

### GraphQL Queries

**Simple GraphQL:**
```bash
gh api graphql -F owner='my-org' -f query='
  query {
    organization(login: $owner) {
      repositories(first: 10) {
        nodes {
          name
          isPrivate
        }
      }
    }
  }
'
```

### Usage Examples

**List organization repositories with REST:**
```bash
gh api orgs/my-org/repos --limit 100
```

**Get org details with GraphQL:**
```bash
gh api graphql -F org='my-org' -f query='
  query($org: String!) {
    organization(login: $org) {
      name
      description
      createdAt
    }
  }
'
```

**Create a repository in an org (alternative to gh repo create):**
```bash
gh api orgs/my-org/repos \
  --method POST \
  -f name='new-repo' \
  -f private=true \
  -f description='Private repository'
```

**Update organization settings:**
```bash
gh api orgs/my-org \
  --method PATCH \
  -f description='New org description' \
  -f blog='https://example.com'
```

**Post to issue with complex data:**
```bash
gh api repos/{owner}/{repo}/issues/123/comments \
  -f body='This is a **bold** comment'
```

**Filter response with jq:**
```bash
gh api repos/my-org/repo/issues \
  --jq '.[] | select(.state == "open") | .number'
```

---

## 9. GitHub Private Repository Limits by Plan (2026)

### Private Repository Counts

**All plans**: **Unlimited private repositories**

There are no limits on the total number of private repos you can create across any GitHub plan.

### Collaborator Limits

| Plan | External Collaborators (per private repo) | Cost |
|------|-------------------------------------------|------|
| **GitHub Free (Personal)** | Unlimited | Free |
| **GitHub Free (Organization)** | 3 | Free |
| **GitHub Pro** | Unlimited | $4/month |
| **GitHub Team** | Unlimited | $4/user/month |
| **GitHub Enterprise Cloud** | Unlimited | $21/user/month |

### Feature Differences (Not Repo Count)

What differs between plans:
- Advanced security features (SAST, dependency scanning)
- Code owners and branch protection rules
- Enterprise support and SLA
- Compliance certifications

What does NOT differ:
- Number of private repos allowed
- Storage limits
- Actions minutes (Teams: 3,000; Enterprise: custom)

### Free Accounts & Organizations

**Important finding**: Free GitHub accounts CAN create organizations with unlimited private repositories.

Organizations on GitHub Free plan have:
- Unlimited private repos
- Limited to 3 external collaborators per private repo
- Limited discussion features
- Limited project automation

To upgrade org features: GitHub Team ($4/user/month) or GitHub Enterprise Cloud ($21/user/month).

---

## Common Workflows

### Authenticating for CI/CD

```bash
# Store token securely
export GH_TOKEN=$(cat /secure/path/token.txt)

# Use gh commands without interactive login
gh repo list my-org
gh api repos/{owner}/{repo}/issues
```

### Creating Private Org Repo & Cloning

```bash
# 1. Create private repo
gh repo create my-org/private-proj --private --add-readme --clone

# 2. Already cloned! Then:
cd private-proj
echo "# Notes" > README.md
git add README.md
git commit -m "Initial commit"
git push origin main
```

### Listing All Private Org Repos (JSON)

```bash
gh repo list my-org \
  --json name,url,isPrivate \
  --visibility private \
  --limit 999 | jq '.[] | select(.isPrivate == true)'
```

### Batch Create Repositories

```bash
for repo in repo1 repo2 repo3; do
  gh repo create my-org/$repo --private --add-readme
done
```

---

## Troubleshooting

### "Not authenticated" error
```bash
# Check current auth status
gh auth status

# Re-authenticate
gh auth logout
gh auth login
```

### Git still asking for password after setup-git
```bash
# Verify git credential helper is configured
git config --global credential.helper
# Should output: !/usr/bin/gh auth git-credential

# If not, run setup again
gh auth setup-git

# Clear git's credential cache
git credential reject host=github.com
```

### "403 Forbidden" on org operations
```bash
# You may need org admin permission
# Check scopes
gh auth status

# Re-authenticate with required scopes
gh auth logout
gh auth login --scopes admin:org,repo
```

---

## Sources

- [GitHub CLI Manual - gh auth login](https://cli.github.com/manual/gh_auth_login)
- [GitHub CLI Manual - gh auth setup-git](https://cli.github.com/manual/gh_auth_setup-git)
- [GitHub CLI Manual - gh auth](https://cli.github.com/manual/gh_auth)
- [GitHub CLI Manual - gh repo create](https://cli.github.com/manual/gh_repo_create)
- [GitHub CLI Manual - gh api](https://cli.github.com/manual/gh_api)
- [GitHub Docs - Types of GitHub Accounts](https://docs.github.com/en/get-started/learning-about-github/types-of-github-accounts)
- [GitHub Pricing](https://github.com/pricing)
- [About Authentication to GitHub](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github)
- [REST API - Organizations](https://docs.github.com/en/rest/orgs/orgs)
