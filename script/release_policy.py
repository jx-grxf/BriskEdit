#!/usr/bin/env python3
"""Reject releases that would replace published artifacts or regress a channel."""
import json
import re
import sys


def version_key(tag):
    match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?", tag)
    if not match:
        raise ValueError(f"Unsupported release tag: {tag}")
    major, minor, patch, beta = match.groups()
    return int(major), int(minor), int(patch), 0 if beta else 1, int(beta or 0)


def validate(candidate, releases):
    current = version_key(candidate)
    beta = "-beta." in candidate
    for release in releases:
        if release.get("draft") or release.get("tag_name") == "beta":
            continue
        tag = release.get("tag_name", "")
        if tag.removeprefix("v") == candidate.removeprefix("v"):
            raise ValueError("This version is already published. Bump the version instead of replacing its artifacts.")
        if not re.fullmatch(r"v?\d+\.\d+\.\d+(?:-beta\.\d+)?", tag):
            continue
        # A beta may precede the next stable, but never an already published
        # equal/newer stable or beta. Stable maintenance releases must not move
        # the latest stable download backwards; newer betas do not block them.
        if (beta or not release.get("prerelease")) and current <= version_key(tag):
            raise ValueError(f"Release {candidate} would regress the channel behind {tag}.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: release_policy.py <version> <releases.json>")
    try:
        with open(sys.argv[2], encoding="utf-8") as source:
            validate(sys.argv[1], json.load(source))
    except (ValueError, OSError) as error:
        raise SystemExit(str(error)) from error
