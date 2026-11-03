#!/usr/bin/env python3
"""Measure how many declared source sites answer HTTP at all.

The directory lists 2,365 sources across 1,452 bundles. "Many sources do not
work" has two very different causes and they need different answers:

* the site is gone, blocked or behind a challenge -> nothing the app can do
  beyond reporting it honestly, and
* the app fails on a site that answers -> a bug worth fixing.

This separates the two by asking each source's own `homeUrl` for a page. It
measures the site, not the extension: a source can be reachable and still fail
inside the extension, and a 403 can be a Cloudflare page rather than a dead
site, so a non-2xx answer is reported as "not confirmed reachable", never as
"the source is broken".

Usage:
    python3 tool/source_reachability.py --index index.json --out report.json
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import random
import urllib.error
import urllib.request
from collections import Counter

UA = (
    "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"
)
TIMEOUT = 15


def probe(url: str) -> tuple[int, str]:
    if not url.startswith(("http://", "https://")):
        return 0, "no-url"
    request = urllib.request.Request(
        url, headers={"User-Agent": UA, "Accept": "text/html,*/*"}
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            # Read a little so a truncated TLS/stream failure is not counted ok.
            response.read(2048)
            return response.status, "ok"
    except urllib.error.HTTPError as error:
        # A Cloudflare/anti-bot answer still proves the host is alive.
        return error.code, "http"
    except Exception as error:  # noqa: BLE001 - the reason is the result
        return 0, type(error).__name__


def collect_sources(index) -> list[dict]:
    """Flatten either index shape into one row per source."""
    # Mihon's index wraps the list; Aniyomi's is the list.
    entries = (
        index["extensionList"]["extensions"] if isinstance(index, dict) else index
    )
    sources = []
    for bundle in entries:
        for source in bundle["sources"]:
            sources.append(
                {
                    "bundle": bundle.get("packageName") or bundle.get("pkg") or "",
                    "name": source["name"],
                    "language": source.get("language") or source.get("lang") or "",
                    # Mihon's index calls it `homeUrl`, Aniyomi's calls it
                    # `baseUrl`; both mean "the site this source reads".
                    "url": source.get("homeUrl") or source.get("baseUrl") or "",
                }
            )
    return sources


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--index", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--sample", type=int, default=250)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--workers", type=int, default=16)
    args = parser.parse_args()

    index = json.loads(open(args.index, encoding="utf-8").read())
    sources = collect_sources(index)

    arabic = [item for item in sources if item["language"] == "ar"]
    rest = [item for item in sources if item["language"] != "ar"]
    random.Random(args.seed).shuffle(rest)
    chosen = arabic + rest[: max(0, args.sample - len(arabic))]

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(probe, item["url"]): item for item in chosen}
        for future in concurrent.futures.as_completed(futures):
            item = futures[future]
            status, reason = future.result()
            results.append({**item, "status": status, "reason": reason})

    results.sort(key=lambda row: (row["language"], row["name"]))
    reachable = [row for row in results if 200 <= row["status"] < 400]
    challenged = [row for row in results if row["status"] in (401, 403, 429, 503)]
    dead = [row for row in results if row["status"] == 0]

    report = {
        "checked": len(results),
        "reachable": len(reachable),
        "challenged": len(challenged),
        "unreachable": len(dead),
        "arabic": {
            "checked": sum(1 for row in results if row["language"] == "ar"),
            "reachable": sum(
                1
                for row in results
                if row["language"] == "ar" and 200 <= row["status"] < 400
            ),
        },
        "results": results,
    }
    open(args.out, "w", encoding="utf-8").write(
        json.dumps(report, ensure_ascii=False, indent=2)
    )

    total = len(results)
    print(f"checked {total} sources")
    print(f"  reachable        {len(reachable):4}  {len(reachable) * 100 // max(total, 1)}%")
    print(f"  challenged       {len(challenged):4}  (anti-bot / auth page)")
    print(f"  unreachable      {len(dead):4}")
    print(f"  arabic           {report['arabic']['reachable']}/{report['arabic']['checked']} reachable")
    print("\nunreachable by reason:")
    for reason, count in Counter(row["reason"] for row in dead).most_common():
        print(f"  {reason:28} {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
