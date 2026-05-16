# Download Manager with GitHub Actions

A unified download tool that supports **direct URLs**, **YouTube** (via `yt-dlp`), **webpage archiving** (MHTML), and **Google Play APKs**. It dispatches a GitHub Actions workflow to download, split large files, zip when appropriate, and commit to the repository.

## Features

- **Three download types**:
  - **URL** – direct downloads (via `aria2`) or YouTube (via `yt-dlp`)
  - **MHTML** – archive webpages as `.mhtml` files (via `pyppeteer`)
  - **Google Play** – download APKs with architecture selection and split-APK merging
- Batch download multiple URLs (comma-separated or from a file)
- YouTube support with `yt-dlp` (quality presets, custom format spec, subtitles, thumbnails, remux, playlist controls)
- Automatic handling of cookies (via secret)
- Split large files into chunks (GitHub‑friendly)
- Automatically zip all files if total size < 100 MB and no splitting occurred
- Interactive or command‑line mode
- History cleanup tools (`clean.sh`, `clean-downloads.yml`)

## Prerequisites

- [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh auth login`)
- A GitHub repository with a valid `DOWNLOAD_TOKEN` secret (matching the token you provide)
- (Optional) `gum` for nicer interactive prompts – otherwise fallback to plain `read`
- (Optional) `git-filter-repo` for the `clean.sh` history cleanup tool

## Setup

1. Clone the repository.
2. Copy `.env.example` to `.env` and configure:

   ```bash
   cp .env.example .env
   ```

3. Set your token in `.env` (or pass via `--token` each time):

   ```bash
   DOWNLOAD_TOKEN=your_secret_token
   ```

4. (Optional) Add YouTube cookies to the secret `YT_COOKIES` (as a raw Netscape‑format cookies.txt content).

## Usage

### Command line (non‑interactive)

```bash
./scripts/download.sh [OPTIONS]
```

#### Basic options

| Option | Description |
|--------|-------------|
| `--type TYPE` | Download type: `url` (default), `mhtml`, `googleplay` |
| `-u, --urls "URL1,URL2"` | Comma‑separated URLs (for `url` and `mhtml` types) |
| `-f, --urls-file FILE` | File with one URL per line |
| `-q, --quality QUALITY` | Simple quality preset: `best`, `1080p`, `720p`, `480p`, `360p`, `240p`, `144p`, `audio` |
| `-m, --mode MODE` | `auto` (zip if fits), `download-full` (no zip), `download-zip` (force zip) |
| `-s, --split-size MB` | Split files larger than this MB (0 = never split). Default 90 |
| `-c, --cookies FILE` | Path to cookies.txt file (sent as plain text) |
| `-t, --token TOKEN` | Override `DOWNLOAD_TOKEN` from `.env` |
| `--check` | Test reachability of each URL before dispatch |
| `--dry-run` | Show the `gh workflow run` command without executing |
| `-h, --help` | Show help |

#### YouTube advanced options (only applied when at least one URL is from YouTube)

| Option | Description |
|--------|-------------|
| `--yt-format-spec SPEC` | Custom `yt-dlp` format spec (e.g., `"bestvideo[height<=720]+bestaudio"`). Overrides `--quality`. |
| `--yt-extract-audio` | Extract audio only (implies `--yt-audio-format`) |
| `--yt-audio-format FORMAT` | `mp3`, `m4a`, or `opus`. Default `mp3` |
| `--yt-subs LANGS` | Comma‑separated subtitle languages, e.g., `en,fr` |
| `--yt-embed-subs` | Embed subtitles into the output file (default: true when `--yt-subs` is set) |
| `--yt-embed-thumbnail` | Embed thumbnail as cover art |
| `--yt-remux` | Remux video using `ffmpeg -c copy` (improves compatibility) |
| `--yt-playlist-start N` | Start downloading playlist from item N |
| `--yt-playlist-end N` | End downloading playlist at item N |
| `--yt-max-playlist-size N` | Limit playlist to N items |

**Default behavior:** Subtitles are embedded by default when selected.

#### MHTML options (`--type mhtml`)

| Option | Description |
|--------|-------------|
| `-u, --urls URL` | Single URL to archive |
| `--title TITLE` | Optional filename (no spaces/special chars) |

#### Google Play options (`--type googleplay`)

| Option | Description |
|--------|-------------|
| `--package-name NAME` | Package name (e.g., `com.google.android.youtube`) |
| `--architecture ARCH` | `arm64` or `armv7` (default `arm64`) |
| `--merge-splits BOOL` | Merge split APKs into single installable (default `true`) |

**Examples:**

```bash
# Download a YouTube video in 720p with English subtitles (embedded by default)
./scripts/download.sh --urls "https://youtu.be/..." --quality 720p --yt-subs en

# Custom format: best video up to 1080p, audio only, mp3 output
./scripts/download.sh --urls "https://youtu.be/..." --yt-format-spec "bestvideo[height<=1080]+bestaudio" --yt-extract-audio --yt-audio-format mp3

# Multiple URLs (mixed YouTube and direct) with thumbnail embedding
./scripts/download.sh --urls "https://youtu.be/abc,https://example.com/file.zip" --yt-embed-thumbnail

# Disable subtitle embedding (download separate .vtt files instead)
./scripts/download.sh --urls "https://youtu.be/..." --yt-subs en --yt-embed-subs false

# Download a YouTube playlist (items 5-20)
./scripts/download.sh --urls "https://youtube.com/playlist?list=..." --quality 1080p --yt-playlist-start 5 --yt-playlist-end 20

# Archive a webpage as MHTML
./scripts/download.sh --type mhtml --urls "https://example.com" --title my_page

# Download a Google Play APK
./scripts/download.sh --type googleplay --package-name com.google.android.youtube --architecture arm64
```

### Interactive mode

Run without any arguments:

```bash
./scripts/download.sh
```

It will prompt for:

- Download type (URL, MHTML, or Google Play)
- URL input method (paste manually or from file)
- YouTube setup (simple quality preset **or** custom format spec)
- Subtitles, thumbnail embedding, remux options
- Playlist controls (start, end, max size) when YouTube URLs detected
- Type-specific options (title for MHTML, package name/architecture for Google Play)
- Confirmation before dispatching the workflow

## How it works

1. The script collects inputs based on the selected download type.
2. It validates the `DOWNLOAD_TOKEN` and determines the GitHub repository.
3. It builds a `gh workflow run` command to trigger `download-url.yml`.
4. The workflow:
   - Installs required tools (`yt-dlp`, `bun`, `ffmpeg`, `aria2`, `jq`, `pyppeteer`, etc.)
   - Based on `download_type`:
     - **url** → For each URL: YouTube uses `yt-dlp`, others use `aria2c`
     - **mhtml** → Uses `pyppeteer` to capture the page as MHTML
     - **googleplay** → Uses `gplay-apk-downloader` to fetch APKs
   - Uploads all downloaded files as a workflow artifact
   - The `finalize` job:
     - Downloads all artifacts into a timestamped `downloads/` subdirectory
     - Optionally splits large files (if `split_size_mb > 0`)
     - Zips all files if mode is `download-zip` **or** if mode is `auto`, total size < 100 MB, no splitting occurred, and more than one file exists
     - Commits the `downloads/` folder back to the repository (with `[skip ci]`)

## Important notes

- **Token security**: The token you pass must match the GitHub secret `DOWNLOAD_TOKEN`. It is transmitted as a workflow input – GitHub does not expose it in logs.
- **Cookies**: If you set the secret `YT_COOKIES`, the workflow automatically writes it to `cookies.txt`. You can also pass a local file with `--cookies` (the content is sent as a plain text field – use with caution).
- **Zip condition**: The workflow creates a zip only when:
  - `mode == 'download-zip'`, **or**
  - `mode == 'auto'` **and** the download job succeeded **and** total size < 100 MB **and** no split parts exist **and** there is more than one file.
- **Splitting**: If any file exceeds `split_size_mb`, it is split into `.part.*` files and committed individually (no zip). This avoids GitHub’s 100 MB file limit.
- **Cleanup tools**:
  - `scripts/clean.sh` – removes `downloads/` from git history locally (requires `git-filter-repo`)
  - `scripts/clean-runs.sh` – deletes completed workflow runs via `gh`
  - `.github/workflows/clean-downloads.yml` – remote history cleanup workflow

## Troubleshooting

| Error | Solution |
|-------|----------|
| `gh not authenticated` | Run `gh auth login` |
| `DOWNLOAD_TOKEN is not set` | Provide via `.env` or `--token` |
| `getopt: invalid option` | The script now uses manual parsing – works everywhere |
| `unrecognized option` | Use the exact flags shown in `--help`. The old `--yt-quality` etc. are **not** supported – use `--quality` or `--yt-format-spec` |

## 📜 License

MIT – use freely, modify as needed.

## 🙏 Acknowledgements

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) – the amazing YouTube downloader
- [Bun](https://bun.sh) – fast JavaScript runtime for solving JS challenges
- [aria2](https://aria2.github.io/) – high‑speed download utility
- GitHub Actions – the backbone of this entire system
