#!/usr/bin/env python3
import asyncio
import sys
import os
from pyppeteer import launch


async def main():
    if len(sys.argv) < 2:
        print("Usage: save_mhtml.py <URL> [title]", file=sys.stderr)
        sys.exit(1)

    url = sys.argv[1]
    title = sys.argv[2] if len(sys.argv) > 2 else None

    browser = await launch(headless=True, args=["--no-sandbox"])
    page = await browser.newPage()
    await page.goto(url, {"waitUntil": "networkidle2"})
    cdp = await page.target.createCDPSession()
    data = await cdp.send("Page.captureSnapshot", {"format": "mhtml"})

    if title:
        filename = f"{title}.mhtml"
    else:
        # Create safe filename from URL
        filename = url.split("//")[-1].replace("/", "_").replace("?", "_") + ".mhtml"

    with open(filename, "w", encoding="utf-8") as f:
        f.write(data["data"])

    await browser.close()
    print(filename)  # Output filename for potential capturing


if __name__ == "__main__":
    asyncio.get_event_loop().run_until_complete(main())
