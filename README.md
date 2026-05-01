# test-gh

Download files from the web directly into your repository using a single command,
with domain allowlisting, token protection, automatic splitting of large files,
and optional bundling into a ZIP archive.

## Features

- 🚀 **Dispatch via CLI** – no more editing commit messages. Run `./scripts/download.sh`
- 🔒 **Token protection** – only requests containing the correct `DOWNLOAD_TOKEN` succeed
- 🌍 **Domain allowlisting** – restrict which domains can be downloaded (or use `*` for all)
- 📦 **Auto ZIP** – multiple URLs are automatically bundled into `all-files.zip`
- ✂️ **Large file splitting** – files exceeding a size threshold are split into parts
- 🔁 **Retry logic** – network hiccups are handled gracefully
- 🧹 **History cleaner** – remove all `downloads/` from Git history when needed
- ⚙️ **Configurable** – all settings via `.env` file or command-line flags

## Quick Start

1. **Clone the repo**

   ```bash
   git clone https://github.com/tabrizkeratin/test-gh.git
   cd test-gh
   ```

2. **Set up environment**

   ```bash
   cp .env.example .env
   # Edit .env with your preferences (especially DOWNLOAD_TOKEN and ALLOWED_DOMAINS)
   ```

3. **Add the GitHub secret**
   - Go to **Settings > Secrets and variables > Actions**
   - Add a secret named `DOWNLOAD_TOKEN` with the same value as in your `.env`

4. **Make scripts executable**

   ```bash
   chmod +x scripts/*.sh
   ```

5. **Download something**

   ```bash
   ./scripts/download.sh https://example.com/file.bin
   ```

## Usage

### Downloading files

```bash
# Single file
./scripts/download.sh https://cdn.example.com/archive.tar.gz

# Multiple files (auto ZIP)
./scripts/download.sh https://cdn.example.com/a.bin https://cdn.example.com/b.bin

# All input styles supported
./scripts/download.sh "https://example.com/1, https://example.com/2"
./scripts/download.sh https://example.com/1,https://example.com/2
```

**Options:**

| Flag | Description | Default |
|------|-------------|---------|
| `--mode download|download-zip` | Override auto‑detected mode | `download` (single) / `download-zip` (multiple) |
| `--split-size-mb N` | Split files larger than N MB | `90` |
| `--allowed-domains d1,d2` | Allowed domains (overrides `.env`) | from `.env` |
| `--commit-message "msg"` | Custom commit message | `chore: download files` |
| `--token TOKEN` | Provide download token (overrides `.env`) | from `.env` |

### Cleaning download history

Remove all traces of `downloads/` from the repository history.

```bash
# Dry run – see what would be deleted
./scripts/clean.sh --dry-run

# Actually clean remote history (requires confirmation)
./scripts/clean.sh --confirm

# After remote clean, reset your local repo
./scripts/clean.sh --local-only
```

## Configuration

All persistent settings are stored in a `.env` file. Copy `.env.example` to `.env` and adjust:

```env
# Required
ALLOWED_DOMAINS=example.com,cdn.example.org   # or * for all
DOWNLOAD_TOKEN=your-secret-token-here

# Optional
SPLIT_SIZE=90
COMMIT_MSG=chore: download files
MODE=download   # leave empty for auto‑detect
```

The script loads `.env` from:  

1. The same directory as `download.sh`  
2. The current working directory

Command‑line flags always override `.env` values.

## How It Works

1. `scripts/download.sh` parses your URLs and dispatches a GitHub Actions workflow.
2. The workflow **validates** your token against the repository secret.
3. Each URL is downloaded **in parallel** using `aria2c`.
4. Downloaded files are uploaded as artifacts, then **combined** in a final job.
5. If you chose `download-zip`, all files are packed into `all-files.zip`.
6. Files larger than `SPLIT_SIZE` are automatically split into `.part_*` chunks.
7. Everything is committed and pushed to the `downloads/` directory.

## Security

- The `DOWNLOAD_TOKEN` ensures only those with the secret can trigger downloads.
- Domain allowlisting prevents accidental downloads from untrusted hosts.
- Use `ALLOWED_DOMAINS=*` only if you accept all domains.

## Requirements

- [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh auth login`)
- The repository has Actions enabled
- A `DOWNLOAD_TOKEN` secret set in repository settings

## Testing

Run the URL parser test (no network calls):

```bash
./scripts/test_download.sh
```

## Contributing

Pull requests are welcome. Please keep the scripts POSIX‑compatible where possible,
and ensure all workflows remain idempotent.

## License

MIT – use it, share it, modify it.
