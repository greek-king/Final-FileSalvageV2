import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var viewModel: ScanViewModel
    @State private var showRecoverySheet = false
    @State private var searchText = ""
    @State private var headerAppeared = false

    var filteredAndSearched: [RecoverableFile] {
        var files = viewModel.filteredFiles
        if !searchText.isEmpty {
            files = files.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return files
    }

    var body: some View {
        GeometryReader { geo in
            let isSmall = geo.size.height < 700

            ZStack {
                Color(hex: "#0A0000").ignoresSafeArea()
                RadialGradient(
                    colors: [Color(hex: "#2A0000").opacity(0.4), Color.clear],
                    center: .top, startRadius: 0, endRadius: geo.size.height * 0.5
                ).ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Header ──
                    VStack(spacing: 0) {
                        HStack {
                            Button(action: viewModel.resetToHome) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                                    Text("New Scan").font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(Color(hex: "#FF4444").opacity(0.8))
                            }
                            Spacer()
                            Text("SCAN RESULTS")
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(Color(hex: "#FF4444"))
                                .tracking(2)
                            Spacer()
                            Menu {
                                Button("Select All") { viewModel.selectAll() }
                                Button("High Chance Only") { viewModel.selectHighChance() }
                                Button("Deselect All") { viewModel.deselectAll() }
                                Divider()
                                ForEach(ScanViewModel.SortOrder.allCases, id: \.self) { order in
                                    Button(order.rawValue) { viewModel.sortOrder = order }
                                }
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(hex: "#FF4444").opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, isSmall ? 50 : geo.safeAreaInsets.top + 16)
                        .padding(.bottom, 16)

                        // Summary cards
                        HStack(spacing: 10) {
                            RedSummaryCard(icon: "doc.text.magnifyingglass",
                                          label: "FOUND",
                                          value: "\(viewModel.scanResult?.scannedFiles.count ?? 0)",
                                          color: "#FF4444")
                            RedSummaryCard(icon: "clock.fill",
                                          label: "TIME",
                                          value: formatDuration(viewModel.scanResult?.duration ?? 0),
                                          color: "#FF6060")
                            RedSummaryCard(icon: "externaldrive.fill",
                                          label: "SIZE",
                                          value: ByteCountFormatter.string(
                                            fromByteCount: viewModel.scanResult?.totalRecoverableSize ?? 0,
                                            countStyle: .file),
                                          color: "#FF8080")
                        }
                        .padding(.horizontal, 24)

                        // Type filters
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                RedFilterChip(
                                    label: "All",
                                    count: viewModel.scanResult?.scannedFiles.count ?? 0,
                                    isSelected: viewModel.filterType == nil
                                ) { viewModel.filterType = nil }
                                ForEach(viewModel.typeBreakdown, id: \.0) { type, count in
                                    RedFilterChip(label: type.rawValue, count: count,
                                                 isSelected: viewModel.filterType == type) {
                                        viewModel.filterType = (viewModel.filterType == type) ? nil : type
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        .padding(.top, 12)

                        // Search
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13)).foregroundColor(Color(hex: "#FF4444").opacity(0.5))
                            TextField("Search files...", text: $searchText)
                                .font(.system(size: 14)).foregroundColor(.white)
                                .tint(Color(hex: "#FF4444"))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#0F0000"))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(hex: "#FF2020").opacity(0.15), lineWidth: 0.5)))
                        .padding(.horizontal, 24).padding(.top, 10)

                        // Count bar
                        HStack {
                            Text(viewModel.selectedCount > 0
                                 ? "\(viewModel.selectedCount) selected"
                                 : "\(filteredAndSearched.count) files found")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "#FF4444").opacity(0.5))
                            Spacer()
                            Menu {
                                ForEach(ScanViewModel.SortOrder.allCases, id: \.self) { order in
                                    Button(order.rawValue) { viewModel.sortOrder = order }
                                }
                            } label: {
                                Text("Sort ↕")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color(hex: "#FF4444").opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 8)
                    }
                    .background(Color(hex: "#0A0000").opacity(0.95))

                    // ── File List ──
                    if filteredAndSearched.isEmpty {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 44)).foregroundColor(Color(hex: "#FF2020").opacity(0.2))
                        Text("No files match filter").font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(hex: "#FF4444").opacity(0.3)).padding(.top, 8)
                        Spacer()
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredAndSearched) { file in
                                    RedFileRow(
                                        file: file,
                                        isSelected: viewModel.selectedFiles.contains(file.id),
                                        onTap: { viewModel.toggleSelection(file) }
                                    )
                                    .padding(.horizontal, 24)
                                }
                                Spacer().frame(height: viewModel.selectedCount > 0 ? 100 : 30)
                            }
                            .padding(.top, 8)
                        }
                    }

                    // ── Recovery Bar ──
                    if viewModel.selectedCount > 0 {
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [Color.clear, Color(hex: "#0A0000")],
                                startPoint: .top, endPoint: .bottom
                            ).frame(height: 20)

                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(viewModel.selectedCount) selected")
                                        .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                                    Text(ByteCountFormatter.string(fromByteCount: viewModel.selectedTotalSize, countStyle: .file))
                                        .font(.system(size: 11)).foregroundColor(Color(hex: "#FF4444").opacity(0.6))
                                }
                                Spacer()
                                Button(action: { showRecoverySheet = true }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 16))
                                        Text("RECOVER").font(.system(size: 13, weight: .black)).tracking(1)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 22).padding(.vertical, 13)
                                    .background(
                                        Capsule().fill(LinearGradient(
                                            colors: [Color(hex: "#8B0000"), Color(hex: "#FF2020")],
                                            startPoint: .leading, endPoint: .trailing
                                        ))
                                        .shadow(color: Color(hex: "#FF2020").opacity(0.5), radius: 12)
                                    )
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                            .padding(.horizontal, 24).padding(.vertical, 14)
                            .background(Color(hex: "#0A0000"))
                            .padding(.bottom, geo.safeAreaInsets.bottom)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showRecoverySheet) { RecoveryDestinationSheet() }
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let m = Int(s / 60); let sec = Int(s.truncatingRemainder(dividingBy: 60))
        return m > 0 ? "\(m)m\(sec)s" : "\(sec)s"
    }
}

// MARK: - Red File Row
struct RedFileRow: View {
    let file: RecoverableFile; let isSelected: Bool; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Checkbox
                ZStack {
                    Circle().strokeBorder(
                        isSelected ? Color(hex: "#FF2020") : Color(hex: "#FF2020").opacity(0.2),
                        lineWidth: 1.5
                    ).frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Color(hex: "#FF2020")).frame(width: 22, height: 22)
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                    }
                }
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "#FF2020").opacity(0.08))
                        .frame(width: 38, height: 38)
                    Image(systemName: file.fileType.icon)
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "#FF4444"))
                }
                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name).font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(file.formattedSize).font(.system(size: 10)).foregroundColor(Color(hex: "#FF4444").opacity(0.5))
                        if file.deletedDate != nil {
                            Text("•").foregroundColor(Color(hex: "#FF2020").opacity(0.2))
                            Text(file.formattedDeletedDate).font(.system(size: 10)).foregroundColor(Color(hex: "#FF4444").opacity(0.5))
                        }
                        if file.fragmentCount > 1 {
                            Text("•").foregroundColor(Color(hex: "#FF2020").opacity(0.2))
                            Text("\(file.fragmentCount) fragments").font(.system(size: 10)).foregroundColor(Color(hex: "#FF6060").opacity(0.6))
                        }
                    }
                }
                Spacer()
                // Chance
                VStack(spacing: 2) {
                    Text("\(Int(file.recoveryChance * 100))%")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(chanceColor(file.recoveryChance))
                    Text(file.recoveryChanceLabel)
                        .font(.system(size: 9))
                        .foregroundColor(chanceColor(file.recoveryChance).opacity(0.6))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color(hex: "#FF2020").opacity(0.06) : Color(hex: "#0F0000"))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isSelected ? Color(hex: "#FF2020").opacity(0.4) : Color(hex: "#FF2020").opacity(0.08),
                            lineWidth: isSelected ? 1 : 0.5
                        ))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
    func chanceColor(_ c: Double) -> Color {
        switch c {
        case 0.8...1.0: return Color(hex: "#FF2020")
        case 0.5..<0.8: return Color(hex: "#FF6040")
        default:        return Color(hex: "#993020")
        }
    }
}

// MARK: - Red Summary Card
struct RedSummaryCard: View {
    let icon: String; let label: String; let value: String; let color: String
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(Color(hex: color))
                .shadow(color: Color(hex: color).opacity(0.5), radius: 4)
            Text(value).font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(.white)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.system(size: 9, weight: .black)).foregroundColor(Color(hex: color).opacity(0.5)).tracking(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#0F0000"))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: "#FF2020").opacity(0.1), lineWidth: 0.5)))
    }
}

// MARK: - Red Filter Chip
struct RedFilterChip: View {
    let label: String; let count: Int; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label).font(.system(size: 12, weight: .bold))
                Text("\(count)").font(.system(size: 10, weight: .black))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(isSelected ? Color.white.opacity(0.15) : Color(hex: "#FF2020").opacity(0.1)))
            }
            .foregroundColor(isSelected ? .white : Color(hex: "#FF4444").opacity(0.6))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? Color(hex: "#FF2020") : Color(hex: "#0F0000"))
                    .overlay(Capsule().strokeBorder(
                        isSelected ? Color.clear : Color(hex: "#FF2020").opacity(0.15), lineWidth: 0.5))
                    .shadow(color: isSelected ? Color(hex: "#FF2020").opacity(0.4) : .clear, radius: 6)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
