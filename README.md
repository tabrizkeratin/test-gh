# 💾 Download & Clean Workflows

This repository contains two GitHub Actions workflows for managing large binary files:

1. **Download from Commit & Save to Repo** – automatically downloads files from URLs in a commit message and stores them in the `downloads/` folder.
2. **Clean downloads from history** – completely purges the `downloads/` directory from the entire Git history and object storage, triggered by a special commit message.

---

## 📥 Download Workflow

### Trigger

Push **any commit** containing the keyword `download:` or `download-zip:` in the commit message.

### Commit message format

```
download: https://example.com/file1.bin https://example.com/file2.bin
```

or

```
download-zip: https://example.com/data.iso https://example.com/backup.tar
```

- Place the URLs on the same line as the keyword, or on subsequent non‑empty lines.
- `download-zip:` creates a single timestamped ZIP archive of all downloaded files.

### What happens

- The workflow fetches the files (only from allowed domains, configurable via repository variable `ALLOWED_DOMAINS`).
- Files are placed in the `downloads/` directory.
- If a file exceeds 90 MB, it is automatically split into 90 MB chunks (using `.zip` split format).
- A new commit with message `Add downloaded files from commit [skip ci]` is pushed to the same branch.
- The `[skip ci]` tag prevents the workflow from re‑running on its own commit.

### Skipping a run

Include `[skip ci]` anywhere in the commit message to prevent the workflow from starting.

### 🔹 URL list syntax

Separate URLs with **spaces**, **commas**, or **newlines**.  
You may also wrap URLs in **single or double quotes** (useful if a URL contains spaces).

Valid examples:

---

## 🧹 Clean Workflow

### Trigger

Push **any commit** containing `clean-downloads:` in the commit message.

### Commit message example

```
clean-downloads: remove all downloaded files
```

### What happens

1. The entire **commit history** is rewritten – every commit that ever touched the `downloads/` directory will have that directory completely removed.
2. The branch is force‑pushed with the cleaned history.
3. GitHub will eventually run garbage collection, freeing up the object storage space.

> ⚠️ **Warning:** This operation **rewrites history**. All existing commit SHAs change.  
> Every collaborator must **rebase their work** or **re‑clone** the repository after the cleanup.  
> Protected branches may block force‑pushing – you may need to disable branch protection temporarily or use a Personal Access Token.

### Safeguard (optional)

If you want an extra confirmation word to avoid accidental runs, change the workflow’s `if` condition to require both `clean-downloads:` and `confirm` in the commit message.

---

## 📊 Repository Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `ALLOWED_DOMAINS` | Regex to whitelist download hosts | `.*` (all domains) |

Set these under **Settings > Secrets and variables > Actions > Variables**.

---

## ⚡ Quick Examples

**Download a file**

```bash
git commit --allow-empty -m "download: https://releases.ubuntu.com/22.04/ubuntu-22.04.4-desktop-amd64.iso"
git push
```

**Download and zip multiple files**

```bash
git commit --allow-empty -m "download-zip: https://example.com/a.zip https://example.com/b.zip"
git push
```

**Clean all downloaded files from history**

```bash
git commit --allow-empty -m "clean-downloads: free up space"
git push
```

After the clean run, your repository will no longer contain the `downloads/` directory in any commit.

---

## ⚙️ Local Installation of `git-filter-repo`

The clean workflow uses `git-filter-repo` automatically. If you ever need to run the cleanup locally, install it first:

```bash
# Ubuntu / Debian
sudo apt install git-filter-repo

# macOS
brew install git-filter-repo
```

```

