import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: ScanViewModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: "#0A0000").ignoresSafeArea()
                // Ambient red glow background
                RadialGradient(
                    colors: [Color(hex: "#3D0000").opacity(0.6), Color.clear],
                    center: .center, startRadius: 0, endRadius: geo.size.height * 0.6
                )
                .ignoresSafeArea()

                Group {
                    switch viewModel.appState {
                    case .home:
                        HomeView()
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    case .scanning:
                        ScanningView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity
                            ))
                    case .results:
                        ResultsView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    case .recovering:
                        RecoveringView()
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    case .complete:
                        RecoveryCompleteView()
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: viewModel.appState)
            }
        }
        .ignoresSafeArea()
        .alert("Access Required", isPresented: $viewModel.isShowingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please grant Photos access to scan for recoverable files.")
        }
        .onAppear { viewModel.requestPermissions() }
    }
}
