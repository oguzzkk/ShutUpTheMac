import ShutUpCore
import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var model: ShutUpModel
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()

            if model.needsAudioPermission {
                permissionBanner
                Divider()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    section(title: model.playingGroups.isEmpty ? nil : L.t("nowPlaying"),
                            groups: model.playingGroups)

                    if !model.quietGroups.isEmpty {
                        section(title: L.t("quietApps"), groups: model.quietGroups)
                    }

                    if model.visibleGroups.isEmpty {
                        Text(model.searchText.isEmpty ? L.t("noAudioApps") : L.t("noMatch"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }

                    offlineSection
                }
                .padding(8)
            }
            .frame(maxHeight: 420)

            Divider()
            footer
        }
        .frame(width: 360)
    }

    // MARK: Parçalar

    /// Susturma izin istemez; yalnızca seviye kısma sistem sesini okumayı gerektirir.
    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("permissionTitle"))
                    .font(.system(size: 12, weight: .semibold))
                Text(L.t("permissionBody"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button(L.t("grantPermission")) { model.requestAudioPermission() }
                    Button(L.t("openSettings")) { model.openPrivacySettings() }
                }
                .font(.system(size: 11))
                .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
            TextField(L.t("search"), text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func section(title: String?, groups: [AppGroup]) -> some View {
        if !groups.isEmpty {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }
            ForEach(groups) { group in
                GroupRow(group: group,
                         isExpanded: expanded.contains(group.bundleID),
                         toggleExpand: { toggleExpansion(group.bundleID) })
                if expanded.contains(group.bundleID) {
                    ForEach(group.members) { member in
                        MemberRow(member: member)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var offlineSection: some View {
        if !model.offlineMuted.isEmpty {
            Text(L.t("offlineMuted"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.top, 10)
            ForEach(model.offlineMuted, id: \.self) { bundleID in
                HStack {
                    Image(systemName: "moon.zzz").foregroundStyle(.secondary).frame(width: 18)
                    Text(bundleID.split(separator: ".").last.map(String.init) ?? bundleID)
                        .font(.system(size: 13))
                    Spacer()
                    Button(L.t("unmuteShort")) { model.setMuted(false, bundleID: bundleID) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                model.toggleMuteAll()
            } label: {
                if model.bulkActive {
                    Label(L.t("undo"), systemImage: "arrow.uturn.backward")
                        .foregroundStyle(.orange)
                } else {
                    Text(L.t("muteAll"))
                }
            }
            .help(model.bulkActive ? L.t("undo") : L.t("muteAll"))

            Button(L.t("exceptFront")) { model.soloFrontmost() }
            if model.mutedCount > 0 {
                Button(L.t("unmuteAll")) { model.unmuteAll() }
            }
            Spacer()
            Button {
                model.showOptionsMenu()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12))
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toggleExpansion(_ bundleID: String) {
        if expanded.contains(bundleID) { expanded.remove(bundleID) } else { expanded.insert(bundleID) }
    }
}

/// Bir uygulamanın satırı. Tıklayınca tüm alt süreçleriyle susar, panel açık kalır.
private struct GroupRow: View {
    @EnvironmentObject private var model: ShutUpModel
    let group: AppGroup
    let isExpanded: Bool
    let toggleExpand: () -> Void

    @State private var hovering = false

    private var isMuted: Bool { model.isMuted(group.bundleID) }
    private var volume: Float { model.volume(group.bundleID) }
    private var isSoloed: Bool { model.isSoloed(group) }

    /// Kaydırıcı sürekli durmaz: ya üstüne geliyorsun ya da ses zaten kısık.
    /// Böylece liste sakin kalır ama ayar bir hareket uzakta olur.
    private var showsSlider: Bool { hovering || (volume > 0 && volume < 1) }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(model.volume(group.bundleID)) },
            set: { model.setVolume(Float($0), bundleID: group.bundleID, live: true) }
        )
    }

    private var subtitle: String? {
        if volume > 0 && volume < 1 {
            return "%\(Int(volume * 100))" + (group.members.count > 1 ? " · " + L.t("processCount", group.members.count) : "")
        }
        guard group.members.count > 1 else { return nil }
        return group.isPlaying
            ? L.t("playingOfCount", group.playingCount, group.members.count)
            : L.t("processCount", group.members.count)
    }

    var body: some View {
        HStack(spacing: 8) {
            icon

            VStack(alignment: .leading, spacing: 1) {
                Text(group.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isMuted ? .secondary : .primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            // Sıralama önemli: kaydırıcı en solda ve yalnızca gerektiğinde yer kaplıyor,
            // böylece belirip kaybolduğunda sağındaki düğmeleri itmiyor. Diğerleri sabit
            // genişlikte sütunlar; görünmedikleri durumda da yerlerini koruyorlar, yoksa
            // her satırda farklı hizaya düşüyorlardı.

            if showsSlider {
                Slider(value: volumeBinding, in: 0...1) { editing in
                    if !editing { model.setVolume(model.volume(group.bundleID), bundleID: group.bundleID) }
                }
                .controlSize(.mini)
                .frame(width: 58)
                .tint(.secondary)
                .help(L.t("volumeTooltip"))
            }

            Image(systemName: "waveform")
                .font(.system(size: 11))
                .foregroundStyle(.green)
                .frame(width: 13)
                .opacity(group.isPlaying ? 1 : 0)
                .help("Şu an ses çalıyor")

            Button { model.solo(group) } label: {
                Image(systemName: isSoloed ? "s.square.fill" : "s.square")
                    .font(.system(size: 13))
                    .foregroundStyle(isSoloed ? AnyShapeStyle(.orange) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            }
            .buttonStyle(.plain)
            .frame(width: 16)
            .opacity(hovering || isSoloed ? 1 : 0)
            .allowsHitTesting(hovering || isSoloed)
            .help(isSoloed ? "Solo'dan çık, önceki duruma dön" : "Bu hariç hepsini sustur")

            Button(action: toggleExpand) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 12)
            .opacity(group.members.count > 1 ? 1 : 0)
            .allowsHitTesting(group.members.count > 1)
            .help(L.t("showSubprocesses"))

            Button { model.toggle(group) } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : speakerSymbol)
                    .font(.system(size: 12))
                    .foregroundStyle(isMuted ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 16)
            .help(isMuted ? L.t("unmute") : L.t("mute"))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.primary.opacity(0.08) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.toggle(group) }
    }

    private var speakerSymbol: String {
        switch volume {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = group.icon {
            Image(nsImage: image).resizable().frame(width: 18, height: 18)
        } else {
            Image(systemName: "app.dashed").foregroundStyle(.secondary).frame(width: 18)
        }
    }
}

/// Alt süreç satırı — hangi helper'ın ses çaldığını gösterir ve tek tek susturmaya izin verir.
///
/// Uygulamanın tamamı susturulmuşsa tek tek ayar anlamsızdır; o durumda satır pasifleşir.
private struct MemberRow: View {
    @EnvironmentObject private var model: ShutUpModel
    let member: AudioProcess
    @State private var hovering = false

    private var groupMuted: Bool { model.isMuted(member.owner.bundleID) }
    private var isMuted: Bool { model.isMuted(process: member) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: member.isPlaying ? "waveform" : "circle.dotted")
                .font(.system(size: 9))
                .foregroundStyle(member.isPlaying ? .green : .secondary)
                .frame(width: 14)

            Text(member.name)
                .font(.system(size: 11))
                .foregroundStyle(isMuted ? .tertiary : .secondary)

            Spacer()

            Text("pid \(member.pid)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.1.fill")
                .font(.system(size: 10))
                .foregroundStyle(isMuted ? AnyShapeStyle(.red)
                                         : AnyShapeStyle(hovering ? HierarchicalShapeStyle.secondary
                                                                  : HierarchicalShapeStyle.tertiary))
                .frame(width: 16)
                .opacity(groupMuted ? 0.35 : 1)
        }
        .padding(.leading, 30)
        .padding(.trailing, 10)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(hovering && !groupMuted ? Color.primary.opacity(0.06) : .clear)
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if !groupMuted { model.toggleProcess(member) } }
        .help(groupMuted ? L.t("wholeAppMuted") : L.t("muteThisProcessOnly"))
    }
}
