import SwiftUI

struct PassRoute: Hashable {
    let id: String
}

/// All tickets as passes: valid now first, then upcoming, without dates and just expired;
/// older ones in the archive.
/// Expects a NavigationStack around it and a PassStore in the environment.
struct PassWalletView: View {
    @Environment(PassStore.self) private var store
    @State private var importing = false
    var now: Date = .now

    var body: some View {
        Group {
            if store.passes.isEmpty {
                empty
            } else {
                list
            }
        }
        .liveBarPadding()
        .background(Color.ground)
        .navigationTitle(L10n.t("Tickets"))
        .screenTrail("Tickets")
        .withSettingsButton()
        .navigationDestination(for: PassRoute.self) { PassDetailView(passId: $0.id) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { importing = true } label: { Label(L10n.t("Add ticket"), systemImage: "plus") }
                    .accessibilityIdentifier("addPass")
            }
        }
        .sheet(isPresented: $importing) { PassImportView() }
    }

    private var list: some View {
        let groups = store.grouped(at: now)
        let archived = store.archived(at: now).count
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if groups.isEmpty {
                    Text("No current tickets").font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
                }
                ForEach(groups, id: \.group) { section in
                    Text(verbatim: section.group.title).font(.headline).padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                    PassCards(passes: section.passes, now: now)
                }
                if archived > 0 {
                    NavigationLink {
                        PassArchiveView(now: now)
                    } label: {
                        HStack {
                            Label(L10n.t("Archive"), systemImage: "archivebox")
                            Spacer()
                            Text(verbatim: "\(archived)").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(14)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .accessibilityIdentifier("passArchive")
                }
            }
            .padding()
        }
    }

    private var empty: some View {
        EmptyState(title: L10n.t("No tickets yet"), systemImage: "ticket",
                   message: L10n.t("Add a ticket from a PDF, a photo or a screenshot. Publit reads the details on your iPhone and keeps the code ready for the gate.")) {
            Button { importing = true } label: { Text("Add ticket") }
                .buttonStyle(.ink)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Compact cards that open the pass; long press to move a ticket to the archive or back.
struct PassCards: View {
    @Environment(PassStore.self) private var store
    let passes: [TicketPass]
    var now: Date = .now

    var body: some View {
        ForEach(passes) { pass in
            NavigationLink(value: PassRoute(id: pass.id)) {
                PassCardView(pass: pass, compact: true, now: now, logo: PassLogoCache.image(pass, store: store))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pass.accessibilitySummary)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("passCard")
            .contextMenu { PassArchiveButton(pass: pass, now: now) }
            .accessibilityActions { PassArchiveButton(pass: pass, now: now) }
        }
    }
}

struct PassArchiveButton: View {
    @Environment(PassStore.self) private var store
    let pass: TicketPass
    var now: Date = .now

    var body: some View {
        if pass.isArchived(at: now) {
            Button { withAnimation { store.unarchive(pass.id) } } label: {
                Label(L10n.t("Move back to tickets"), systemImage: "tray.and.arrow.up")
            }
        } else {
            Button { withAnimation { store.archive(pass.id) } } label: {
                Label(L10n.t("Move to archive"), systemImage: "archivebox")
            }
        }
    }
}
