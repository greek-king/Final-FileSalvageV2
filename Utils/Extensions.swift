// Utils/Extensions.swift
// Shared utilities, extensions, and custom UI components

import SwiftUI
import Photos
import UIKit

// MARK: - Color from Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Haptic Feedback
class HapticManager {
    static let shared = HapticManager()

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}

// MARK: - Privacy Permission Helper
struct PermissionHelper {
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    static var photosAuthorizationStatus: String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized:    return "Authorized"
        case .denied:        return "Denied"
        case .limited:       return "Limited"
        case .notDetermined: return "Not Determined"
        case .restricted:    return "Restricted"
        @unknown default:    return "Unknown"
        }
    }
}

// MARK: - Gradient View
struct AnimatedGradientBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Color(hex: "#0A0E1A")

            RadialGradient(
                colors: [Color(hex: "#0D3040").opacity(0.5), Color.clear],
                center: animate ? .topLeading : .bottomTrailing,
                startRadius: 0,
                endRadius: 400
            )
            .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: animate)
            .onAppear { animate = true }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Shimmer Effect
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.15), .clear],
                    startPoint: UnitPoint(x: phase, y: 0.5),
                    endPoint: UnitPoint(x: phase + 0.5, y: 0.5)
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: phase)
                .onAppear { phase = 1.5 }
            }
        )
        .mask(content)
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Loading Skeleton
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: "#2A3352"))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "#2A3352"))
                    .frame(width: 180, height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "#1A2240"))
                    .frame(width: 120, height: 10)
            }

            Spacer()

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: "#2A3352"))
                .frame(width: 40, height: 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .shimmer()
    }
}
