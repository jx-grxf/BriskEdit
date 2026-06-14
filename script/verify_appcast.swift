#!/usr/bin/env xcrun swift
// Verify a Sparkle appcast.xml:
//   - It is well-formed XML.
//   - The first <item>'s <enclosure url=...> matches the expected URL.
//   - The first <item> declares the expected sparkle:channel.
//
// Usage:
//   ./script/verify_appcast.swift appcast.xml https://.../BriskEdit-0.1.0.zip stable [version] [build] [archive]

import Foundation

final class AppcastDelegate: NSObject, XMLParserDelegate {
    var enclosureURL: String?
    var enclosureLength: String?
    var enclosureSignature: String?
    var channel: String?
    var shortVersion: String?
    var build: String?
    private var currentElement = ""
    private var currentText = ""
    private var currentChannel = ""
    private var foundItem = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "item" { foundItem = true }
        if foundItem, elementName == "enclosure", enclosureURL == nil {
            enclosureURL = attributeDict["url"]
            enclosureLength = attributeDict["length"]
            enclosureSignature = attributeDict["sparkle:edSignature"] ?? attributeDict["edSignature"]
        }
        if elementName == "sparkle:channel" || qName == "sparkle:channel" {
            currentChannel = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
        if currentElement == "sparkle:channel" {
            currentChannel += string
            channel = currentChannel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "sparkle:shortVersionString" || qName == "sparkle:shortVersionString" {
            shortVersion = value
        } else if elementName == "sparkle:version" || qName == "sparkle:version" {
            build = value
        }
        currentElement = ""
        currentText = ""
    }
}

let args = CommandLine.arguments
guard (4...7).contains(args.count) else {
    FileHandle.standardError.write(Data("usage: verify_appcast.swift <path> <expected-url> <expected-channel> [expected-version] [expected-build] [archive]\n".utf8))
    exit(2)
}

let path = args[1]
let expectedURL = args[2]
let expectedChannel = args[3]
let expectedVersion = args.count > 4 ? args[4] : nil
let expectedBuild = args.count > 5 ? args[5] : nil
let archivePath = args.count > 6 ? args[6] : nil

guard let data = FileManager.default.contents(atPath: path) else {
    FileHandle.standardError.write(Data("appcast not found at \(path)\n".utf8))
    exit(1)
}

let parser = XMLParser(data: data)
let delegate = AppcastDelegate()
parser.delegate = delegate

guard parser.parse() else {
    FileHandle.standardError.write(Data("appcast did not parse: \(parser.parserError?.localizedDescription ?? "unknown")\n".utf8))
    exit(1)
}

var failures: [String] = []
if delegate.enclosureURL != expectedURL {
    failures.append("enclosure url mismatch: got \(delegate.enclosureURL ?? "nil"), expected \(expectedURL)")
}
if delegate.enclosureSignature?.isEmpty != false {
    failures.append("enclosure is missing sparkle:edSignature")
}
if let expectedVersion, delegate.shortVersion != expectedVersion {
    failures.append("version mismatch: got \(delegate.shortVersion ?? "nil"), expected \(expectedVersion)")
}
if let expectedBuild, delegate.build != expectedBuild {
    failures.append("build mismatch: got \(delegate.build ?? "nil"), expected \(expectedBuild)")
}
if let archivePath {
    do {
        let attributes = try FileManager.default.attributesOfItem(atPath: archivePath)
        let size = (attributes[.size] as? NSNumber)?.stringValue
        if delegate.enclosureLength != size {
            failures.append("enclosure length mismatch: got \(delegate.enclosureLength ?? "nil"), expected \(size ?? "nil")")
        }
    } catch {
        failures.append("could not inspect archive at \(archivePath): \(error.localizedDescription)")
    }
}
// Stable releases ride the default channel: they carry NO <sparkle:channel> tag
// so every client (including beta opt-ins) sees them. Only pre-release builds are
// tagged. So when "stable" (or empty) is expected, assert there is no channel.
let expectsNoChannel = expectedChannel.isEmpty || expectedChannel == "stable" || expectedChannel == "default"
if expectsNoChannel {
    if let channel = delegate.channel, !channel.isEmpty {
        failures.append("expected no channel tag for a stable release, got \(channel)")
    }
} else if delegate.channel != expectedChannel {
    failures.append("channel mismatch: got \(delegate.channel ?? "nil"), expected \(expectedChannel)")
}

if failures.isEmpty {
    print("appcast ok: url=\(expectedURL) channel=\(expectedChannel)")
} else {
    for f in failures { FileHandle.standardError.write(Data((f + "\n").utf8)) }
    exit(1)
}
