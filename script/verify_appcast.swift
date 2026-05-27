#!/usr/bin/env xcrun swift
// Verify a Sparkle appcast.xml:
//   - It is well-formed XML.
//   - The first <item>'s <enclosure url=...> matches the expected URL.
//   - The first <item> declares the expected sparkle:channel.
//
// Usage:
//   ./script/verify_appcast.swift dist/sparkle/appcast.xml https://.../BriskEdit-0.1.0.zip stable

import Foundation

@MainActor
final class AppcastDelegate: NSObject, XMLParserDelegate {
    var enclosureURL: String?
    var channel: String?
    private var currentElement = ""
    private var currentChannel = ""
    private var foundItem = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" { foundItem = true }
        if foundItem, elementName == "enclosure", enclosureURL == nil {
            enclosureURL = attributeDict["url"]
        }
        if elementName == "sparkle:channel" || qName == "sparkle:channel" {
            currentChannel = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "sparkle:channel" {
            currentChannel += string
            channel = currentChannel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write(Data("usage: verify_appcast.swift <path> <expected-url> <expected-channel>\n".utf8))
    exit(2)
}

let path = args[1]
let expectedURL = args[2]
let expectedChannel = args[3]

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
if let actualChannel = delegate.channel, actualChannel != expectedChannel {
    failures.append("channel mismatch: got \(actualChannel), expected \(expectedChannel)")
}

if failures.isEmpty {
    print("appcast ok: url=\(expectedURL) channel=\(expectedChannel)")
} else {
    for f in failures { FileHandle.standardError.write(Data((f + "\n").utf8)) }
    exit(1)
}
