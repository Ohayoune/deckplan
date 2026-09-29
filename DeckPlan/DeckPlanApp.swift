//
//  DeckPlanApp.swift
//  DeckPlan
//
//  The app entry point (docs/REDESIGN.md): four tabs — Today, Finder, Classes,
//  Settings — over one `AppModel`. iPhone first, iOS 17.0+.
//

import SwiftUI

@main
struct DeckPlanApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

struct RootView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            NavigationStack {
                TodayView(model: model)
                    .appDestinations(model)
            }
            .tabItem { Label("Today", systemImage: "sun.max") }

            NavigationStack {
                FinderView(model: model, context: .standalone)
                    .appDestinations(model)
            }
            .tabItem { Label("Finder", systemImage: "magnifyingglass") }

            NavigationStack {
                ClassesView(model: model)
                    .appDestinations(model)
            }
            .tabItem { Label("Classes", systemImage: "person.3") }

            NavigationStack {
                SettingsView(model: model)
                    .appDestinations(model)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task {
            await model.openStore()
        }
        // A day saves itself (DECISIONS_LOG 2026-09-13): the days through today,
        // when the app comes back and when the date changes while it is open.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.saveDaysThroughToday() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await model.saveDaysThroughToday() }
        }
        .alert(Display.General.couldntSave, isPresented: saveErrorShown) {
            Button(Display.General.ok) { model.saveError = nil }
        } message: {
            Text(model.saveError ?? "")
        }
    }

    private var saveErrorShown: Binding<Bool> {
        Binding(get: { model.saveError != nil },
                set: { shown in if !shown { model.saveError = nil } })
    }
}
