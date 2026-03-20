import SwiftUI

// MARK: - Destination Sheet
struct RecoveryDestinationSheet: View {
    @EnvironmentObject var viewModel: ScanViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: "#0A0000").ignoresSafeArea()
                RadialGradient(
                    colors: [Color(hex: "#3D0000").opacity(0.4), Color.clear],
                    center: .top, startRadius: 0, endRadius: 400
                ).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Handle
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#FF2020").opacity(0.2))
                        .frame(width: 36, height: 4)
                        .padding(.top, 14)

                    Text("RECOVERY DESTINATION")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(Color(hex: "#FF4444"))
                        .tracking(2)
                        .padding(.top, 20)

                    Text("Choose where to save recovered files")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#FF4444").opacity(0.4))
                        .padding(.top, 6).padding(.bottom, 28)

                    VStack(spacing: 12) {
                        RedDestinationOption(icon: "photo.on.rectangle.angled", title: "Camera Roll",
                                             subtitle: "Saves directly to Photos app", color: "#FF2020") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                viewModel.recoverSelected(to: .cameraRoll)
                            }
                        }
                        RedDestinationOption(icon: "folder.fill", title: "Files App",
                                             subtitle: "Saved in Files → FileSalvage → Recovered Files", color: "#FF4040") {
                            let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd_HHmmss"
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                viewModel.recoverSelected(to: .files(folderName: "Recovery_\(fmt.string(from: Date()))"))
                            }
                        }
                        RedDestinationOption(icon: "icloud.and.arrow.up", title: "iCloud Drive",
                                             subtitle: "Saved in Files → iCloud Drive", color: "#FF6060") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                viewModel.recoverSelected(to: .iCloud)
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(hex: "#FF4444").opacity(0.5))
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 8)
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct RedDestinationOption: View {
    let icon: String; let title: String; let subtitle: String; let color: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: color).opacity(0.12))
                        .frame(width: 50, height: 50)
                    Image(systemName: icon).font(.system(size: 20)).foregroundColor(Color(hex: color))
                        .shadow(color: Color(hex: color).opacity(0.5), radius: 4)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Text(subtitle).font(.system(size: 12)).foregroundColor(Color(hex: "#FF4444").opacity(0.4))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#FF2020").opacity(0.3))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#0F0000"))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(hex: "#FF2020").opacity(0.12), lineWidth: 0.5)))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Recovering View
struct RecoveringView: View {
    @EnvironmentObject var viewModel: ScanViewModel
    @State private var rotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0

    var progress: Double { viewModel.recoveryProgress?.percentage ?? 0 }

    var body: some View {
        GeometryReader { geo in
            let isSmall = geo.size.height < 700
            let orbSize: CGFloat = isSmall ? 180 : 220

            ZStack {
                Color(hex: "#0A0000").ignoresSafeArea()
                RadialGradient(
                    colors: [Color(hex: "#3D0000").opacity(CGFloat(0.3 + progress * 0.3)), Color.clear],
                    center: .center, startRadius: 0, endRadius: geo.size.height * 0.5
                ).ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Orb
                    ZStack {
                        // Pulsing outer ring
                        Circle()
                            .strokeBorder(Color(hex: "#FF2020").opacity(0.15), lineWidth: 1)
                            .frame(width: orbSize + 60, height: orbSize + 60)
                            .scaleEffect(pulseScale)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                                    pulseScale = 1.06
                                }
                            }

                        // Rotating border
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(
                                AngularGradient(
                                    colors: [Color(hex: "#FF2020"), Color(hex: "#8B0000"), Color.clear],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                            )
                            .frame(width: orbSize + 8, height: orbSize + 8)
                            .rotationEffect(.degrees(rotation))
                            .shadow(color: Color(hex: "#FF2020").opacity(0.4), radius: 6)
                            .onAppear {
                                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                    rotation = 360
                                }
                            }

                        // Fill circle
                        ZStack {
                            Circle().fill(Color(hex: "#0F0000")).frame(width: orbSize, height: orbSize)

                            // Fill progress (red liquid)
                            let innerSize: CGFloat = orbSize - 4
                            let fillH: CGFloat = innerSize * CGFloat(progress)
                            let offsetY: CGFloat = innerSize / 2 - fillH / 2

                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color(hex: "#FF2020").opacity(0.5), Color(hex: "#8B0000").opacity(0.3)],
                                    startPoint: .bottom, endPoint: .top
                                ))
                                .frame(width: innerSize, height: fillH)
                                .offset(y: offsetY)
                                .clipShape(Circle())
                                .animation(.easeInOut(duration: 0.5), value: progress)

                            Circle()
                                .strokeBorder(Color(hex: "#FF2020").opacity(0.3), lineWidth: 1)
                                .frame(width: orbSize, height: orbSize)

                            VStack(spacing: 4) {
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: isSmall ? 38 : 46, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                    .shadow(color: Color(hex: "#FF2020").opacity(0.4), radius: 8)
                                Text("RECOVERING")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(Color(hex: "#FF4444").opacity(0.6))
                                    .tracking(2)
                            }
                        }
                        .frame(width: orbSize, height: orbSize)
                    }

                    Spacer().frame(height: isSmall ? 36 : 50)

                    // Info
                    if let prog = viewModel.recoveryProgress {
                        VStack(spacing: 10) {
                            Text(prog.currentFile)
                                .font(.system(size: isSmall ? 14 : 16, weight: .semibold))
                                .foregroundColor(.white).lineLimit(1).padding(.horizontal, 40)
                            Text("\(prog.completedCount) of \(prog.totalCount) files")
                                .font(.system(size: 12)).foregroundColor(Color(hex: "#FF4444").opacity(0.5))

                            // Mini progress bar
                            GeometryReader { bg in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#1A0000")).frame(height: 4)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(LinearGradient(
                                            colors: [Color(hex: "#8B0000"), Color(hex: "#FF2020")],
                                            startPoint: .leading, endPoint: .trailing
                                        ))
                                        .frame(width: max(4, bg.size.width * CGFloat(prog.percentage)), height: 4)
                                        .shadow(color: Color(hex: "#FF2020").opacity(0.5), radius: 3)
                                        .animation(.easeInOut(duration: 0.4), value: prog.percentage)
                                }
                            }
                            .frame(height: 4).padding(.horizontal, 50)
                        }
                    }

                    Spacer()

                    Text("Keep app open during recovery")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#FF4444").opacity(0.3))
                        .padding(.bottom, geo.safeAreaInsets.bottom + 24)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Recovery Complete
struct RecoveryCompleteView: View {
    @EnvironmentObject var viewModel: ScanViewModel
    @EnvironmentObject var recoveryStore: RecoveryStore
    @State private var checkScale: CGFloat = 0
    @State private var ringsExpand = false
    @State private var shineOffset: CGFloat = -300

    var result: RecoveryOperationResult? { viewModel.recoveryResult }

    var body: some View {
        GeometryReader { geo in
            let isSmall = geo.size.height < 700

            ZStack {
                Color(hex: "#0A0000").ignoresSafeArea()
                RadialGradient(
                    colors: [Color(hex: "#4A0000").opacity(0.5), Color.clear],
                    center: .center, startRadius: 0, endRadius: geo.size.height * 0.6
                ).ignoresSafeArea()

                // Shine sweep
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.clear, Color(hex: "#FF2020").opacity(0.04), Color.clear],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: 120)
                    .rotationEffect(.degrees(15))
                    .offset(x: shineOffset)
                    .ignoresSafeArea()
                    .onAppear {
                        withAnimation(.linear(duration: 2).delay(1.5)) { shineOffset = 600 }
                    }

                VStack(spacing: 0) {
                    Spacer()

                    // Check mark
                    ZStack {
                        ForEach(0..<3) { i in
                            Circle()
                                .strokeBorder(Color(hex: "#FF2020").opacity(ringsExpand ? 0 : 0.2 - Double(i) * 0.06), lineWidth: 1.5)
                                .frame(width: CGFloat(90 + i * 46), height: CGFloat(90 + i * 46))
                                .scaleEffect(ringsExpand ? CGFloat(2.5 + Double(i) * 0.3) : 1.0)
                                .animation(.easeOut(duration: 1.6).delay(Double(i) * 0.1), value: ringsExpand)
                        }
                        ZStack {
                            Circle()
                                .fill(RadialGradient(
                                    colors: [Color(hex: "#FF2020").opacity(0.2), Color(hex: "#0F0000")],
                                    center: .center, startRadius: 0, endRadius: 50
                                ))
                                .frame(width: 100, height: 100)
                            Circle()
                                .strokeBorder(
                                    AngularGradient(
                                        colors: [Color(hex: "#FF2020"), Color(hex: "#FF6060"), Color(hex: "#8B0000"), Color(hex: "#FF2020")],
                                        center: .center
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 100, height: 100)
                                .shadow(color: Color(hex: "#FF2020").opacity(0.5), radius: 10)
                            Image(systemName: "checkmark")
                                .font(.system(size: isSmall ? 36 : 44, weight: .bold))
                                .foregroundColor(Color(hex: "#FF4444"))
                                .shadow(color: Color(hex: "#FF2020").opacity(0.8), radius: 8)
                                .scaleEffect(checkScale)
                        }
                    }
                    .onAppear {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.2)) { checkScale = 1.0 }
                        withAnimation { ringsExpand = true }
                        saveSession()
                    }

                    Spacer().frame(height: isSmall ? 28 : 40)

                    VStack(spacing: 8) {
                        Text("Recovery Complete")
                            .font(.system(size: isSmall ? 26 : 32, weight: .black))
                            .foregroundStyle(LinearGradient(
                                colors: [Color(hex: "#FF4444"), Color(hex: "#FF8080")],
                                startPoint: .leading, endPoint: .trailing
                            ))
                        if let result = result {
                            Text("\(result.succeededFiles.count) files successfully recovered")
                                .font(.system(size: isSmall ? 14 : 16))
                                .foregroundColor(Color(hex: "#FF4444").opacity(0.5))
                        }
                    }

                    Spacer().frame(height: isSmall ? 28 : 36)

                    // Stat cards
                    if let result = result {
                        HStack(spacing: 10) {
                            RedResultStat(icon: "checkmark.circle.fill",
                                         value: "\(result.succeededFiles.count)", label: "RECOVERED", color: "#FF2020")
                            RedResultStat(icon: "xmark.circle.fill",
                                         value: "\(result.failedFiles.count)", label: "FAILED",
                                         color: result.failedFiles.isEmpty ? "#441010" : "#FF4040")
                            RedResultStat(icon: "externaldrive.fill",
                                         value: ByteCountFormatter.string(fromByteCount: result.totalRecovered, countStyle: .file),
                                         label: "TOTAL SIZE", color: "#FF6060")
                        }
                        .padding(.horizontal, 24)
                    }

                    Spacer()

                    // Buttons
                    VStack(spacing: 12) {
                        Button(action: viewModel.rescan) {
                            HStack(spacing: 10) {
                                Image(systemName: "sensor.tag.radiowaves.forward.fill").font(.system(size: 16))
                                Text("SCAN AGAIN").font(.system(size: 14, weight: .black)).tracking(1.5)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(LinearGradient(
                                        colors: [Color(hex: "#6B0000"), Color(hex: "#FF2020")],
                                        startPoint: .leading, endPoint: .trailing
                                    ))
                                    .shadow(color: Color(hex: "#FF2020").opacity(0.5), radius: 16)
                            )
                        }
                        .buttonStyle(ScaleButtonStyle()).padding(.horizontal, 24)

                        Button(action: viewModel.resetToHome) {
                            Text("Done")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(hex: "#FF4444").opacity(0.4))
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.bottom, geo.safeAreaInsets.bottom + 20)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func saveSession() {
        guard let result = result else { return }
        recoveryStore.addSession(RecoverySession(
            id: UUID(), date: Date(), recoveredFiles: result.succeededFiles,
            destinationPath: result.destinationURL?.path ?? "Device",
            status: result.failedFiles.isEmpty ? .completed : .partial
        ))
    }
}

struct RedResultStat: View {
    let icon: String; let value: String; let label: String; let color: String
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(Color(hex: color))
                .shadow(color: Color(hex: color).opacity(0.5), radius: 4)
            Text(value).font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(.white)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.system(size: 9, weight: .black)).foregroundColor(Color(hex: color).opacity(0.5)).tracking(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "#0F0000"))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: "#FF2020").opacity(0.1), lineWidth: 0.5)))
    }
}
