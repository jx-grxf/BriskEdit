#!/usr/bin/env python3
"""Keep the newest signed enclosure on each supported Sparkle channel."""
import copy
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
ET.register_namespace("sparkle", SPARKLE[1:-1])


def build(item):
    value = item.findtext(SPARKLE + "version") or ""
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
        raise ValueError("Appcast contains an invalid build version")
    parts = [int(component) for component in value.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))


def merge(paths, output):
    tree = ET.parse(paths[0])
    channel = tree.getroot().find("channel")
    if channel is None:
        raise ValueError("Appcast has no channel")
    items = []
    for path in paths:
        if not Path(path).exists():
            continue
        source = ET.parse(path).getroot().find("channel")
        if source is None:
            raise ValueError("Appcast has no channel")
        for item in source.findall("item"):
            tag = item.findtext(SPARKLE + "channel") or ""
            if tag not in ("", "beta"):
                raise ValueError("Unsupported appcast channel")
            build(item)
            items.append(copy.deepcopy(item))
    for item in channel.findall("item"):
        channel.remove(item)
    newest = []
    for tag in ("", "beta"):
        candidates = [item for item in items if (item.findtext(SPARKLE + "channel") or "") == tag]
        if candidates:
            newest.append(max(candidates, key=build))
    for item in sorted(newest, key=build, reverse=True):
        channel.append(item)
    tree.write(output, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    if len(sys.argv) < 4:
        raise SystemExit("usage: merge_appcasts.py <current> <other-or-missing> [more-feeds...] <output>")
    merge(sys.argv[1:-1], sys.argv[-1])
