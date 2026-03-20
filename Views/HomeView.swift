import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: ScanViewModel
    @EnvironmentObject var recoveryStore: RecoveryStore
    @State private var pulse = false
    @State private var ringScale: [CGFloat] = [1, 1, 1]
    @State private var particleOpacity: [Double] = Array(repeating: 0, count: 12)
    @State private var scanLineOffset: CGFloat = -1
    @State private var glowIntensity: Double = 0.3

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let isSmall = h < 700

            ZStack {
                // Base background
                Color(hex: "#0A0000").ignoresSafeArea()

                // Animated gradient mesh
                ZStack {
                    RadialGradient(
                        colors: [Color(hex: "#5C0000").opacity(glowIntensity), Color.clear],
                        center: .init(x: 0.5, y: 0.35),
                        startRadius: 0, endRadius: w * 0.7
                    )
                    RadialGradient(
                        colors: [Color(hex: "#3D0010").opacity(0.25), Color.clear],
                        center: .init(x: 0.1, y: 0.8),
                        startRadius: 0, endRadius: w * 0.5
                    )
                    RadialGradient(
                        colors: [Color(hex: "#200030").opacity(0.2), Color.clear],
                        center: .init(x: 0.9, y: 0.6),
                        startRadius: 0, endRadius: w * 0.4
                    )
                }
                .ignoresSafeArea()
                .onAppear {
                    withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                        glowIntensity = 0.55
                    }
                }

                // Scan line sweep
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.clear, Color(hex: "#FF2020").opacity(0.06), Color.clear],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(height: 80)
                    .offset(y: scanLineOffset * h / 2)
                    .ignoresSafeArea()
                    .onAppear {
                        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                            scanLineOffset = 1.2
                        }
                    }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // ── Header ──
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    // Red dot indicator
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: "#FF2020").opacity(0.3))
                                            .frame(width: 14, height: 14)
                                            .scaleEffect(pulse ? 1.8 : 1.0)
                                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                                        Circle()
                                            .fill(Color(hex: "#FF2020"))
                                            .frame(width: 7, height: 7)
                                    }
                                    Text("FileSalvage")
                                        .font(.system(size: isSmall ? 26 : 30, weight: .black, design: .rounded))
                                        .foregroundStyle(LinearGradient(
                                            colors: [Color(hex: "#FF4444"), Color(hex: "#FF8080")],
                                            startPoint: .leading, endPoint: .trailing
                                        ))
                                }
                                Text("APFS Data Recovery")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(hex: "#FF4444").opacity(0.7))
                                    .tracking(2)
                            }
                            Spacer()
                            // Status pill
                            HStack(spacing: 5) {
                                Circle().fill(Color(hex: "#FF2020")).frame(width: 5, height: 5)
                                Text("READY")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(hex: "#FF4444"))
                                    .tracking(1.5)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color(hex: "#FF2020").opacity(0.1))
                                .overlay(Capsule().strokeBorder(Color(hex: "#FF2020").opacity(0.3), lineWidth: 0.5)))
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, isSmall ? 50 : geo.safeAreaInsets.top + 20)

                        Spacer().frame(height: isSmall ? 28 : 40)

                        // ── Main Scan Button ──
                        ZStack {
                            // Outer pulsing rings
                            ForEach(0..<3) { i in
                                Circle()
                                    .strokeBorder(Color(hex: "#FF2020").opacity(0.08 - Double(i) * 0.02), lineWidth: 1)
                                    .frame(
                                        width: (isSmall ? 150 : 180) + CGFloat(i * 44),
                                        height: (isSmall ? 150 : 180) + CGFloat(i * 44)
                                    )
                                    .scaleEffect(ringScale[i])
                                    .onAppear {
                                        withAnimation(
                                            .easeInOut(duration: 2.4 + Double(i) * 0.4)
                                            .repeatForever(autoreverses: true)
                                            .delay(Double(i) * 0.3)
                                        ) { ringScale[i] = 1.06 + CGFloat(i) * 0.01 }
                                    }
                            }

                            // Particles around button
                            ForEach(0..<12) { i in
                                let angle = Double(i) / 12.0 * 360.0
                                let radius: CGFloat = isSmall ? 105 : 125
                                Circle()
                                    .fill(Color(hex: "#FF2020"))
                                    .frame(width: i % 3 == 0 ? 4 : 2.5, height: i % 3 == 0 ? 4 : 2.5)
                                    .shadow(color: Color(hex: "#FF2020").opacity(0.8), radius: 3)
                                    .opacity(particleOpacity[i])
                                    .offset(
                                        x: CGFloat(cos(angle * .pi / 180)) * radius,
                                        y: CGFloat(sin(angle * .pi / 180)) * radius
                                    )
                                    .onAppear {
                                        withAnimation(
                                            .easeInOut(duration: 1.5 + Double(i) * 0.15)
                                            .repeatForever(autoreverses: true)
                                            .delay(Double(i) * 0.12)
                                        ) { particleOpacity[i] = 1.0 }
                                    }
                            }

                            // Main button
                            Button(action: viewModel.startScan) {
                                ZStack {
                                    // Button base
                                    Circle()
                                        .fill(Color(hex: "#1A0000"))
                                        .frame(width: isSmall ? 150 : 180, height: isSmall ? 150 : 180)

                                    // Red gradient ring
                                    Circle()
                                        .strokeBorder(
                                            AngularGradient(
                                                colors: [
                                                    Color(hex: "#FF2020"),
                                                    Color(hex: "#FF6060"),
                                                    Color(hex: "#8B0000"),
                                                    Color(hex: "#FF2020")
                                                ],
                                                center: .center
                                            ),
                                            lineWidth: 2
                                        )
                                        .frame(width: isSmall ? 150 : 180, height: isSmall ? 150 : 180)
                                        .shadow(color: Color(hex: "#FF2020").opacity(0.6), radius: 12)

                                    // Inner glow disc
                                    Circle()
                                        .fill(RadialGradient(
                                            colors: [Color(hex: "#4A0000").opacity(0.8), Color.clear],
                                            center: .center, startRadius: 0, endRadius: isSmall ? 60 : 75
                                        ))
                                        .frame(width: isSmall ? 130 : 156, height: isSmall ? 130 : 156)

                                    VStack(spacing: 8) {
                                        // Radar icon
                                        ZStack {
                                            ForEach(0..<3) { i in
                                                Circle()
                                                    .strokeBorder(Color(hex: "#FF2020").opacity(0.4 - Double(i) * 0.1), lineWidth: 0.5)
                                                    .frame(width: CGFloat(24 + i * 14), height: CGFloat(24 + i * 14))
                                            }
                                            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                                                .font(.system(size: isSmall ? 28 : 34))
                                                .foregroundColor(Color(hex: "#FF4444"))
                                                .shadow(color: Color(hex: "#FF2020").opacity(0.8), radius: 8)
                                        }

                                        Text("SCAN NOW")
                                            .font(.system(size: isSmall ? 10 : 12, weight: .black))
                                            .foregroundColor(Color(hex: "#FF6060"))
                                            .tracking(2)
                                    }
                                }
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }

                        Spacer().frame(height: isSmall ? 20 : 28)

                        // Tagline
                        Text("Recover deleted photos, videos & documents")
                            .font(.system(size: isSmall ? 13 : 15, weight: .medium))
                            .foregroundColor(Color(hex: "#FF4444").opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Spacer().frame(height: isSmall ? 24 : 36)

                        // ── Scan Depth ──
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("SCAN DEPTH")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(Color(hex: "#FF2020").opacity(0.6))
                                    .tracking(2)
                                Spacer()
                            }
                            .padding(.horizontal, 24)

                            HStack(spacing: 10) {
                                ForEach(ScanDepth.allCases, id: \.self) { depth in
                                    RedDepthButton(
                                        depth: depth,
                                        isSelected: viewModel.selectedDepth == depth,
                                        isSmall: isSmall
                                    ) { viewModel.selectedDepth = depth }
                                }
                            }
                            .padding(.horizontal, 24)
                        }

                        Spacer().frame(height: isSmall ? 24 : 32)

                        // ── File Types Grid ──
                        VStack(alignment: .leading, spacing: 10) {
                            Text("RECOVERABLE TYPES")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(Color(hex: "#FF2020").opacity(0.6))
                                .tracking(2)
                                .padding(.horizontal, 24)

                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
                                spacing: 10
                            ) {
                                ForEach(FileType.allCases.filter { $0 != .unknown }, id: \.self) { type in
                                    RedFileTypeTile(fileType: type, isSmall: isSmall)
                                }
                            }
                            .padding(.horizontal, 24)
                        }

                        // ── Recent Sessions ──
                        if !recoveryStore.sessions.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("RECENT SESSIONS")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(Color(hex: "#FF2020").opacity(0.6))
                                    .tracking(2)
                                    .padding(.horizontal, 24)
                                ForEach(recoveryStore.sessions.prefix(2)) { session in
                                    RedSessionRow(session: session).padding(.horizontal, 24)
                                }
                            }
                            .padding(.top, 24)
                        }

                        Spacer().frame(height: 50)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            pulse = true
            recoveryStore.loadSessions()
        }
    }
}

// MARK: - Red Depth Button
struct RedDepthButton: View {
    let depth: ScanDepth
    let isSelected: Bool
    var isSmall: Bool = false
    let action: () -> Void

    var icon: String {
        switch depth { case .quick: return "bolt.fill"; case .deep: return "magnifyingglass"; case .full: return "scope" }
    }
    var label: String {
        switch depth { case .quick: return "QUICK"; case .deep: return "DEEP"; case .full: return "FULL" }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: isSmall ? 16 : 20))
                    .foregroundColor(isSelected ? Color(hex: "#FF2020") : Color(hex: "#FF2020").opacity(0.3))
                    .shadow(color: isSelected ? Color(hex: "#FF2020").opacity(0.8) : .clear, radius: 6)
                Text(label)
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(isSelected ? Color(hex: "#FF4040") : Color(hex: "#FF2020").opacity(0.3))
                    .tracking(1.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isSmall ? 12 : 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color(hex: "#FF2020").opacity(0.1) : Color(hex: "#0F0000"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isSelected ? Color(hex: "#FF2020").opacity(0.5) : Color(hex: "#FF2020").opacity(0.08),
                                lineWidth: isSelected ? 1 : 0.5
                            )
                    )
                    .shadow(color: isSelected ? Color(hex: "#FF2020").opacity(0.15) : .clear, radius: 8)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Red File Type Tile
struct RedFileTypeTile: View {
    let fileType: FileType
    var isSmall: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "#FF2020").opacity(0.1))
                    .frame(width: isSmall ? 40 : 46, height: isSmall ? 40 : 46)
                Image(systemName: fileType.icon)
                    .font(.system(size: isSmall ? 18 : 22))
                    .foregroundColor(Color(hex: "#FF4444"))
                    .shadow(color: Color(hex: "#FF2020").opacity(0.6), radius: 4)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(fileType.rawValue)
                    .font(.system(size: isSmall ? 13 : 14, weight: .bold))
                    .foregroundColor(.white)
                Text(typeSubtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#FF4444").opacity(0.5))
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#FF2020").opacity(0.4))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "#0F0000"))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(hex: "#FF2020").opacity(0.1), lineWidth: 0.5))
        )
    }

    var typeSubtitle: String {
        switch fileType {
        case .photo:    return "JPG, PNG, HEIC, RAW"
        case .video:    return "MP4, MOV, AVI, MKV"
        case .audio:    return "MP3, M4A, WAV, AAC"
        case .document: return "PDF, DOC, ZIP, XLS"
        default:        return "All formats"
        }
    }
}

// MARK: - Red Session Row
struct RedSessionRow: View {
    let session: RecoverySession
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color(hex: "#FF2020").opacity(0.1)).frame(width: 40, height: 40)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "#FF4444"))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(session.recoveredFiles.count) files recovered")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                Text(session.formattedDate)
                    .font(.system(size: 11)).foregroundColor(Color(hex: "#FF4444").opacity(0.5))
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: session.totalSize, countStyle: .file))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: "#FF4444"))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "#0F0000"))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(hex: "#FF2020").opacity(0.15), lineWidth: 0.5))
        )
    }
}
