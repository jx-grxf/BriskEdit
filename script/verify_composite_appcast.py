#!/usr/bin/env python3
"""Validate channel feed structure and extract each item for archive verification."""
import base64
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
ET.register_namespace("sparkle", SPARKLE[1:-1])


def validate(path, expected_build, repository, output):
    channel = ET.parse(path).getroot().find("channel")
    items = [] if channel is None else channel.findall("item")
    if not 1 <= len(items) <= 2:
        raise ValueError("The combined feed must contain one or two items")
    channels = set()
    builds = set()
    output.mkdir(parents=True, exist_ok=True)
    for index, item in enumerate(items):
        name = item.findtext(SPARKLE + "channel") or "stable"
        build = item.findtext(SPARKLE + "version") or ""
        version = item.findtext(SPARKLE + "shortVersionString") or ""
        enclosure = item.find("enclosure")
        if name not in ("stable", "beta") or name in channels:
            raise ValueError("Duplicate or unsupported channel")
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", build) or build in builds:
            raise ValueError("Invalid or duplicate build")
        if not re.fullmatch(r"\d+\.\d+\.\d+(?:-beta\.\d+)?", version):
            raise ValueError("Invalid visible version")
        if (name == "beta") != ("-beta." in version):
            raise ValueError("Version does not match its channel")
        url = f"https://github.com/{repository}/releases/download/v{version}/BriskEdit-{version}.zip"
        if enclosure is None or enclosure.get("url") != url:
            raise ValueError("Enclosure must reference this repository's versioned release")
        if not re.fullmatch(r"[1-9][0-9]*", enclosure.get("length", "")):
            raise ValueError("Invalid archive length")
        signature = base64.b64decode(enclosure.get(SPARKLE + "edSignature", ""), validate=True)
        if len(signature) != 64:
            raise ValueError("Invalid Ed25519 signature")
        channels.add(name)
        builds.add(build)
        rss = ET.Element("rss", version="2.0")
        ET.SubElement(rss, "channel").append(item)
        item_path = output / f"item-{index}.xml"
        ET.ElementTree(rss).write(item_path, encoding="utf-8", xml_declaration=True)
        print(f"{index}\t{url}\t{name}\t{version}\t{build}")
    if expected_build not in builds:
        raise ValueError("The new release is missing from the combined feed")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit("usage: verify_composite_appcast.py <feed> <expected-build> <owner/repo> <output-directory>")
    try:
        validate(sys.argv[1], sys.argv[2], sys.argv[3], Path(sys.argv[4]))
    except (ValueError, OSError, ET.ParseError) as error:
        raise SystemExit(str(error)) from error
