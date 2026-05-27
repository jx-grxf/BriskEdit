import SwiftUI

struct FileTreeView: View {
    let root: URL
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        List(selection: $workspace.selectedSidebarURL) {
            FileTreeBranch(node: FileNode(url: root, isDirectory: true))
                .environment(workspace)
        }
        .listStyle(.sidebar)
    }
}

private struct FileTreeBranch: View {
    let node: FileNode
    @Environment(WorkspaceModel.self) private var workspace
    @State private var isExpanded: Bool = true
    @State private var children: [FileNode] = []
    @State private var didLoad: Bool = false

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(children) { child in
                    FileTreeBranch(node: child)
                        .environment(workspace)
                }
            } label: {
                Label(node.name, systemImage: "folder")
            }
            .task(id: node.id) {
                guard !didLoad else { return }
                let loaded = await Task.detached { FileNode.children(of: node.url) }.value
                children = loaded
                didLoad = true
            }
        } else {
            Label(node.name, systemImage: iconName(for: node.url))
                .tag(node.url)
                .onTapGesture(count: 2) {
                    Task { await workspace.openFile(at: node.url) }
                }
        }
    }

    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "swift": "swift"
        case "md", "markdown": "doc.richtext"
        case "json", "yaml", "yml", "toml": "curlybraces"
        case "py", "rb", "go", "rs", "ts", "tsx", "js", "jsx", "c", "h", "cpp", "hpp", "m", "mm":
            "chevron.left.forwardslash.chevron.right"
        case "png", "jpg", "jpeg", "gif", "heic", "webp": "photo"
        default: "doc.text"
        }
    }
}
