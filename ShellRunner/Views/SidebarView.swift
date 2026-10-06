import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SavedCommand?
    @Binding var showingAddSheet: Bool

    @Query(sort: \SavedCommand.name) private var commands: [SavedCommand]
    @Environment(\.modelContext) private var modelContext

    private var groupedByFolder: [(folder: String, commands: [SavedCommand])] {
        let groups = Dictionary(grouping: commands) { $0.folder ?? "Uncategorized" }
        return groups
            .map { (folder: $0.key, commands: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.folder < $1.folder }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(groupedByFolder, id: \.folder) { group in
                    Section(group.folder) {
                        ForEach(group.commands) { cmd in
                            row(for: cmd).tag(cmd)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                showingAddSheet = true
            } label: {
                Label("Add Command", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .navigationTitle("Commands")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Command", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private func row(for cmd: SavedCommand) -> some View {
        HStack {
            Image(systemName: "terminal.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(cmd.name)
                Text(cmd.command)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                cmd.isFavorite.toggle()
            } label: {
                Image(systemName: cmd.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(cmd.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                if selection == cmd { selection = nil }
                HotkeyBindingCoordinator.shared.unregister(cmd)
                RunnerStore.shared.forget(cmd)
                modelContext.delete(cmd)
            }
        }
    }
}
