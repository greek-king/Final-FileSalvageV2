// FileRecoveryApp.swift
// Main entry point for the File Recovery iOS Application

import SwiftUI

@main
struct FileRecoveryApp: App {
    @StateObject private var scanViewModel = ScanViewModel()
    @StateObject private var recoveryStore = RecoveryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scanViewModel)
                .environmentObject(recoveryStore)
                .preferredColorScheme(.dark)
        }
    }
}
