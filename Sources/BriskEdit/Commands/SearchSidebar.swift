import SwiftUI

/// Project-wide "Find in Files" pane: a query/replace header with case, word and
/// regex toggles, and a results list grouped by file. Clicking a match opens the
/// file at that line. Mirrors VS Code's search sidebar.
struct SearchSidebarView: View {
    @Bindable var workspace: WorkspaceModel
    @FocusState private var queryFocused: Bool
    @State private var debounce: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            results
        }
        .onChange(of: workspace.focusSearchToken) { _, _ in queryFocused = true }
        .onAppear { if workspace.searchResults.isEmpty { queryFocused = true } }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                TextField("Search", text: $workspace.searchQuery.text)
                    .textFieldStyle(.roundedBorder)
                    .focused($queryFocused)
                    .onSubmit { workspace.runProjectSearch() }
                    .onChange(of: workspace.searchQuery.text) { _, _ in scheduleSearch() }
                toggle("Aa", help: "Match case", isOn: $workspace.searchQuery.caseSensitive)
                toggle("W", help: "Whole word", isOn: $workspace.searchQuery.wholeWord)
                toggle(".*", help: "Use regular expression", isOn: $workspace.searchQuery.isRegex)
            }
            HStack(spacing: 4) {
                TextField("Replace", text: $workspace.searchReplacement)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { workspace.replaceAllInProject() }
                Button("Replace All", systemImage: "arrow.2.squarepath") {
                    workspace.replaceAllInProject()
                }
                .labelStyle(.iconOnly)
                .help("Replace all")
                .disabled(workspace.searchResults.isEmpty)
            }
            HStack {
                if workspace.isSearching {
                    ProgressView().controlSize(.small)
                    Text("Searching…").font(.caption).foregroundStyle(.secondary)
                } else if !workspace.searchQuery.text.isEmpty {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(8)
        .onChange(of: workspace.searchQuery.caseSensitive) { _, _ in workspace.runProjectSearch() }
        .onChange(of: workspace.searchQuery.wholeWord) { _, _ in workspace.runProjectSearch() }
        .onChange(of: workspace.searchQuery.isRegex) { _, _ in workspace.runProjectSearch() }
    }

    private var summary: String {
        let files = workspace.searchResults.count
        let matches = workspace.searchTotalMatches
        guard matches > 0 else { return "No results" }
        return "\(matches) result\(matches == 1 ? "" : "s") in \(files) file\(files == 1 ? "" : "s")"
    }

    private func toggle(_ label: String, help: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 22, height: 20)
        }
        .buttonStyle(.plain)
        .background(isOn.wrappedValue ? Color.accentColor.opacity(0.3) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    private var results: some View {
        List {
            ForEach(workspace.searchResults) { file in
                Section {
                    ForEach(file.matches) { match in
                        Button {
                            Task { await workspace.openFile(at: file.url, line: match.line, column: match.column, length: match.length) }
                        } label: {
                            HStack(spacing: 6) {
                                Text("\(match.line)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 26, alignment: .trailing)
                                Text(highlighted(match.lineText))
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack(spacing: 6) {
                        FileTypeIcon(url: file.url, isDirectory: false, language: SourceLanguage(url: file.url, displayName: file.url.lastPathComponent), size: 13)
                        Text(file.url.lastPathComponent).font(.caption.bold()).lineLimit(1)
                        Text("\(file.matches.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// Bolds the query occurrences inside the displayed line for quick scanning.
    private func highlighted(_ line: String) -> AttributedString {
        let display = String(line.drop(while: { $0 == " " || $0 == "\t" }))
        var attributed = AttributedString(display)
        let needle = workspace.searchQuery.text
        guard !needle.isEmpty, !workspace.searchQuery.isRegex else { return attributed }
        var searchRange = display.startIndex..<display.endIndex
        let options: String.CompareOptions = workspace.searchQuery.caseSensitive ? [] : [.caseInsensitive]
        while let found = display.range(of: needle, options: options, range: searchRange) {
            if let lower = AttributedString.Index(found.lowerBound, within: attributed),
               let upper = AttributedString.Index(found.upperBound, within: attributed) {
                attributed[lower..<upper].foregroundColor = .accentColor
                attributed[lower..<upper].font = .caption.monospaced().bold()
            }
            searchRange = found.upperBound..<display.endIndex
        }
        return attributed
    }

    private func scheduleSearch() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            workspace.runProjectSearch()
        }
    }
}
