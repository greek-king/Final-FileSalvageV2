import SwiftUI

struct ScanningView: View {
    @EnvironmentObject var viewModel: ScanViewModel
    @State private var rotation: Double = 0
    @State private var innerRotation: Double = 0
    @State private var blipOpacities: [Double] = Array(repeating: 0, count: 8)
    @State private var waveScale: [CGFloat] = [1, 1, 1, 1]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let isSmall = h < 700
            let radarR: CGFloat = isSmall ? 110 : 140

            ZStack {
                Color(hex: "#0A0000").ignoresSafeArea()

                // Background radial
                RadialGradient(
                    colors: [Color(hex: "#3D0000").opacity(0.5), Color.clear],
                    center: .init(x: 0.5, y: 0.38),
                    startRadius: 0, endRadius: w * 0.65
                ).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: viewModel.cancelScan) {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Cancel")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(Color(hex: "#FF4444").opacity(0.7))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Color(hex: "#FF2020").opacity(0.08))
                                .overlay(Capsule().strokeBorder(Color(hex: "#FF2020").opacity(0.2), lineWidth: 0.5)))
                        }
                        Spacer()
                        Text(viewModel.selectedDepth.rawValue.uppercased())
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(Color(hex: "#FF4444"))
                            .tracking(2)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color(hex: "#FF2020").opacity(0.1))
                                .overlay(Capsule().strokeBorder(Color(hex: "#FF2020").opacity(0.3), lineWidth: 0.5)))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, isSmall ? 50 : geo.safeAreaInsets.top + 20)

                    Spacer()

                    // ── Radar ──
                    ZStack {
                        // Expanding wave rings
                        ForEach(0..<4) { i in
                            Circle()
                                .strokeBorder(Color(hex: "#FF2020").opacity(0.06 + Double(i) * 0.03), lineWidth: 0.5)
                                .frame(width: radarR * 2 * (0.35 + CGFloat(i) * 0.22),
                                       height: radarR * 2 * (0.35 + CGFloat(i) * 0.22))
                                .scaleEffect(waveScale[i])
                                .onAppear {
                                    withAnimation(.easeInOut(duration: 2.2 + Double(i) * 0.3)
                                        .repeatForever(autoreverses: true).delay(Double(i) * 0.2)) {
                                        waveScale[i] = 1.04 + CGFloat(i) * 0.01
                                    }
                                }
                        }

                        // Outer sweep arc
                        Circle()
                            .trim(from: 0, to: 0.3)
                            .stroke(
                                AngularGradient(
                                    colors: [Color(hex: "#FF2020").opacity(0.7), Color.clear],
                                    center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(108)
                                ),
                                style: StrokeStyle(lineWidth: 1.5)
                            )
                            .frame(width: radarR * 2, height: radarR * 2)
                            .rotationEffect(.degrees(rotation))

                        // Inner counter-rotating ring
                        Circle()
                            .trim(from: 0, to: 0.15)
                            .stroke(Color(hex: "#FF6060").opacity(0.4), style: StrokeStyle(lineWidth: 1))
                            .frame(width: radarR * 1.4, height: radarR * 1.4)
                            .rotationEffect(.degrees(-innerRotation))

                        // Sweep line
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [Color(hex: "#FF2020").opacity(0.9), Color.clear],
                                startPoint: .center, endPoint: .trailing
                            ))
                            .frame(width: radarR, height: 1.5)
                            .offset(x: radarR / 2)
                            .rotationEffect(.degrees(rotation))
                            .shadow(color: Color(hex: "#FF2020").opacity(0.6), radius: 4)

                        // Blips
                        ForEach(0..<8) { i in
                            let angle = Double(i) * 45.0 + rotation.truncatingRemainder(dividingBy: 360)
                            let dist = radarR * (0.3 + CGFloat(i % 3) * 0.22)
                            Circle()
                                .fill(Color(hex: "#FF2020"))
                                .frame(width: i % 3 == 0 ? 5 : 3, height: i % 3 == 0 ? 5 : 3)
                                .shadow(color: Color(hex: "#FF2020").opacity(0.9), radius: 4)
                                .opacity(blipOpacities[i])
                                .offset(
                                    x: CGFloat(cos(angle * .pi / 180)) * dist,
                                    y: CGFloat(sin(angle * .pi / 180)) * dist
                                )
                                .onAppear {
                                    withAnimation(.easeInOut(duration: 0.9 + Double(i) * 0.18)
                                        .repeatForever(autoreverses: true).delay(Double(i) * 0.15)) {
                                        blipOpacities[i] = 1.0
                                    }
                                }
                        }

                        // Center core
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#1A0000"))
                                .frame(width: radarR * 0.5, height: radarR * 0.5)
                            Circle()
                                .strokeBorder(
                                    AngularGradient(
                                        colors: [Color(hex: "#FF2020"), Color(hex: "#8B0000"), Color(hex: "#FF2020")],
                                        center: .center
                                    ),
                                    lineWidth: 1.5
                                )
                                .frame(width: radarR * 0.5, height: radarR * 0.5)
                                .shadow(color: Color(hex: "#FF2020").opacity(0.5), radius: 6)
                            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                                .font(.system(size: isSmall ? 20 : 26))
                                .foregroundColor(Color(hex: "#FF4444"))
                                .shadow(color: Color(hex: "#FF2020").opacity(0.9), radius: 8)
                        }
                    }
                    .frame(width: radarR * 2.5, height: radarR * 2.5)
                    .onAppear {
                        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { rotation = 360 }
                        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) { innerRotation = 360 }
                    }

                    Spacer().frame(height: isSmall ? 32 : 44)

                    // Progress info
                    VStack(spacing: isSmall ? 14 : 18) {
                        // Step name with animated dots
                        HStack(spacing: 0) {
                            Text(viewModel.scanProgress.currentStep)
                                .font(.system(size: isSmall ? 15 : 17, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 24)

                        // Progress bar
                        GeometryReader { barGeo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(hex: "#1A0000"))
                                    .frame(height: 6)
                                    .overlay(RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color(hex: "#FF2020").opacity(0.15), lineWidth: 0.5))

                                RoundedRectangle(cornerRadius: 6)
                                    .fill(LinearGradient(
                                        colors: [Color(hex: "#8B0000"), Color(hex: "#FF2020"), Color(hex: "#FF6060")],
                                        startPoint: .leading, endPoint: .trailing
                                    ))
                                    .frame(
                                        width: max(8, barGeo.size.width * viewModel.scanProgress.percentage),
                                        height: 6
                                    )
                                    .shadow(color: Color(hex: "#FF2020").opacity(0.5), radius: 4)
                                    .animation(.easeInOut(duration: 0.4), value: viewModel.scanProgress.percentage)
                            }
                        }
                        .frame(height: 6)
                        .padding(.horizontal, 36)

                        // Stats
                        HStack(spacing: 50) {
                            RedStatItem(label: "FOUND", value: "\(viewModel.scanProgress.filesFound)", color: "#FF4444")
                            RedStatItem(label: "PROGRESS", value: "\(Int(viewModel.scanProgress.percentage * 100))%", color: "#FF8080")
                        }
                    }

                    Spacer()

                    // Tip
                    HStack(spacing: 8) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#FF2020").opacity(0.5))
                        Text("Keep app open for best recovery results")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#FF4444").opacity(0.4))
                    }
                    .padding(.bottom, isSmall ? 24 : geo.safeAreaInsets.bottom + 24)
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct RedStatItem: View {
    let label: String; let value: String; let color: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: color))
                .shadow(color: Color(hex: color).opacity(0.5), radius: 6)
            Text(label)
                .font(.system(size: 9, weight: .black))
                .foregroundColor(Color(hex: color).opacity(0.5))
                .tracking(2)
        }
    }
}
