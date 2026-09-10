#!/usr/bin/env python3
"""Decide whether a nightly build should replace the published nightly feed.

Prints "publish" or "skip: <reason>". A malformed feed or an item outside the
nightly channel aborts, because publishing over it would hide the problem.
"""
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def published_build(path):
    if not Path(path).exists():
        return None
    channel = ET.parse(path).getroot().find("channel")
    if channel is None:
        raise ValueError("Nightly feed has no channel")
    builds = []
    for item in channel.findall("item"):
        if (item.findtext(SPARKLE + "channel") or "") != "nightly":
            raise ValueError("Nightly feed contains an item outside the nightly channel")
        value = item.findtext(SPARKLE + "version") or ""
        if not re.fullmatch(r"[1-9][0-9]{0,3}", value):
            raise ValueError("Nightly feed contains an invalid build")
        builds.append(int(value))
    return max(builds) if builds else None


def decide(feed, build, force=False):
    if not re.fullmatch(r"[1-9][0-9]{0,3}", build):
        raise ValueError("Nightly build must be a positive integer below 10000")
    current = published_build(feed)
    candidate = int(build)
    if current is None or candidate > current:
        return "publish"
    if candidate == current:
        return "publish" if force else f"skip: build {candidate} is already published"
    # An older CI run finished after a newer nightly was published.
    return f"skip: build {candidate} is older than published build {current}"


if __name__ == "__main__":
    args = [arg for arg in sys.argv[1:] if arg != "--force"]
    if len(args) != 2:
        raise SystemExit("usage: nightly_feed_decision.py <feed-or-missing-path> <build> [--force]")
    try:
        print(decide(args[0], args[1], force="--force" in sys.argv[1:]))
    except (ValueError, OSError, ET.ParseError) as error:
        raise SystemExit(str(error)) from error
