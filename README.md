# 🌐 GitHub Actions Download Manager with YouTube Support

A powerful, secure download manager that turns your GitHub repository into a remote download cache – now with full **YouTube / yt‑dlp** support, interactive mode, and automatic file splitting to stay within GitHub limits.

[![Trigger Download](https://github.com/tabrizkeratin/test-gh/actions/workflows/download-url.yml/badge.svg)](https://github.com/tabrizkeratin/test-gh/actions/workflows/download-url.yml)

## ✨ Features

- 📦 **Download any file** (direct links) or **YouTube videos/audio** using `yt‑dlp`
- 🧠 **Parallel downloads** – each URL runs in its own GitHub Actions job
- 🗜️ **Automatic splitting** of large files into chunks (< 100 MB) for GitHub
- 🎛️ **Flexible quality selection** – presets (`best`, `1080p`, `720p`, `audio`) or raw format IDs (`135+251`)
- 🍪 **Cookie support** – pass YouTube cookies as a secret to access private/age‑restricted content
- 🖥️ **Interactive CLI** – simple prompts for URLs & quality; advanced mode for subtitles, thumbnails, remux
- 🔒 **Token protection** – only users who know the secret token can trigger downloads
- 📂 **Versioned downloads** – all files are committed to your repository (optional `downloads/` branch)

## 🚀 Quick Start

### 1. Fork or clone this repository

```bash
git clone https://github.com/tabrizkeratin/test-gh.git
cd test-gh
```

### 2. Set up the download token

Create a `.env` file (or export the variable):

```bash
DOWNLOAD_TOKEN=your-secret-token   # any strong password
```

Add the **same token** as a GitHub secret in your repository:  
`Settings → Secrets and variables → Actions → New repository secret`  
Name: `DOWNLOAD_TOKEN` – Value: `your-secret-token`

### 3. (Optional) Add YouTube cookies

If you need to download private, age‑restricted, or member‑only videos, export your browser cookies (use an extension like "Get cookies.txt") and save the whole content as a GitHub secret:

Name: `YT_COOKIES` – Value: *paste the entire cookies.txt content*

### 4. Run the script

```bash
./scripts/download.sh
```

Follow the interactive prompts – enter one or more URLs, choose quality, and confirm.

Or use command‑line mode:

```bash
# Download a YouTube video in 1080p with English subtitles
./scripts/download.sh --yt-quality 1080p --yt-subs en https://youtu.be/...

# Extract audio as MP3
./scripts/download.sh --yt-extract-audio --yt-audio-format mp3 https://youtu.be/...

# Download multiple direct links (will be zipped automatically)
./scripts/download.sh https://example.com/file1.zip https://example.com/file2.pdf

# Use raw yt‑dlp format IDs
./scripts/download.sh --yt-quality "135+251" https://youtu.be/...
```

The workflow will run on GitHub and push the downloaded files into the `downloads/` folder of your repository.

## 📖 Detailed Usage

### Interactive modes

| Command | Description |
|---------|-------------|
| `./scripts/download.sh` | **Simple interactive** – asks for URLs and quality only. |
| `./scripts/download.sh --advanced` | **Full interactive** – also prompts for split size, subtitles, embed thumbnail, remux, commit message. |
| `./scripts/download.sh --help` | Show all command‑line options. |

### Quality / format specifiers

| Value | Effect |
|-------|--------|
| `best` | Best video + audio (default) |
| `1080p` | Best video ≤1080p + best audio |
| `720p` | Best video ≤720p + best audio |
| `480p` | Best video ≤480p + best audio |
| `audio` | Best audio only |
| `135+251` | Raw yt‑dlp format IDs (e.g., video 135 + audio 251) |
| `bestvideo[height<=1440][fps<=60]+bestaudio` | Any valid yt‑dlp format filter |

> 💡 Run `yt-dlp -F <YouTube-URL>` locally to see available format IDs.

### Command‑line options (non‑interactive)

```
--mode <auto|download|download-zip>      default: auto
--split-size <MB>                        split files larger than this, 0=never (default 90)
--commit-msg <msg>                       custom commit message
--yt-quality <best|1080p|720p|480p|audio|height|formatID>
--yt-fps <30|60>                         limit frame rate
--yt-extract-audio                       extract audio only
--yt-audio-format <mp3|m4a|opus>         default mp3
--yt-subs <lang1,lang2>                  download subtitles (e.g. en,fr)
--yt-embed-subs                          embed subtitles into file
--yt-embed-thumbnail                     embed thumbnail
--yt-remux                               remux video for better compatibility
--advanced                               full interactive mode
--help
```

All options can also be set via `.env` file (see `.env.example`).

## 🔧 How it works

1. **Local script** collects URLs, quality settings, and your secret token.
2. **Workflow dispatch** triggers a GitHub Actions workflow with all inputs.
3. **Matrix jobs** run in parallel: each URL is processed independently.
   - YouTube URLs → `yt-dlp` with Bun runtime + optional cookies, subs, remux.
   - Direct links → `aria2c` for fast multi‑connection downloads.
4. **Artifacts** from all jobs are merged into the `downloads/` folder.
5. **Splitting & zipping** logic:
   - Files larger than `split_size_mb` are split into `.part.aa`, `.part.ab`, …
   - If `mode` is `download-zip` **and** no split parts exist **and** total size < 100 MB → a single `all-files.zip` is created.
   - Otherwise individual files are committed (safe for GitHub’s 100 MB limit).
6. **Commit & push** – all files are committed to the repository (default branch, folder `downloads/`).

## 🔐 Security

- **Download token** (`DOWNLOAD_TOKEN`) is required – only people who know it can start downloads.
- **Cookie secret** (`YT_COOKIES`) is never exposed in logs or commits; it is written temporarily on the runner.
- **Domain allowlist** (optional, set `ALLOWED_DOMAINS` in `.env`) restricts which domains can be downloaded.
- The runner is ephemeral – everything is destroyed after the workflow finishes.

## 🧪 Testing

Run offline tests that do not contact the network:

```bash
./scripts/test_download.sh
./scripts/test_domain_validation.sh
```

## 🧹 Cleaning up

To remove all downloaded files from the repository history (including old commits):

```bash
./scripts/clean.sh --confirm
```

This rewrites history using `git-filter-repo`. Use with caution – coordinate with all collaborators.

## 📁 Repository structure after download

```
your-repo/
├── downloads/
│   ├── video.mp4.part.aa
│   ├── video.mp4.part.ab
│   ├── all-files.zip   (only if small & zip mode)
│   └── ...
└── ... (other files)
```

## ❓ Troubleshooting

| Problem | Solution |
|---------|----------|
| `Requested format is not available` | Try `--allow-unplayable-formats` (already included) or use a specific format ID from `-F`. |
| `n challenge solving failed` | The workflow includes Bun runtime – ensure your yt‑dlp version is up‑to‑date. Check `YT_COOKIES` if the video is age‑restricted. |
| Push rejected (file >100 MB) | The splitting logic should prevent this. If it still happens, set a lower `split_size_mb` (e.g., 80). |
| `zip` step fails with exit code 1 | The fixed `finalize` job now skips zipping when split parts exist or total size >100 MB. |
| Cookies not working | Export fresh cookies.txt while logged into YouTube. Make sure the secret is named exactly `YT_COOKIES`. |

## 📜 License

MIT – use freely, modify as needed.

## 🙏 Acknowledgements

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) – the amazing YouTube downloader
- [Bun](https://bun.sh) – fast JavaScript runtime for solving JS challenges
- [aria2](https://aria2.github.io/) – high‑speed download utility
- GitHub Actions – the backbone of this entire system
