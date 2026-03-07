# Geolocate3D: Frontend Implementation Plan

**Status**: Implementation-ready blueprint
**Target**: iOS 17+, iPhone 15 Pro Max, Swift 5.9+
**Last updated**: 2026-03-07

---

## 1. Aesthetic Direction: "Volumetric Observatory"

The design language draws from spatial computing interfaces — not flat mobile UI. Every element exists at a perceived depth. The app feels like peering into a luminous spatial instrument.

### 1.1 Color System

```swift
// DesignSystem/Colors.swift
import SwiftUI

extension Color {
    // Backgrounds — true black for OLED + depth layers
    static let spaceBlack       = Color(red: 0.00, green: 0.00, blue: 0.00) // #000000
    static let obsidian         = Color(red: 0.04, green: 0.04, blue: 0.06) // #0A0A0F
    static let voidGray         = Color(red: 0.08, green: 0.08, blue: 0.12) // #14141F

    // Spatial Accents — luminous, high-contrast on black
    static let spatialCyan      = Color(red: 0.00, green: 0.96, blue: 1.00) // #00F5FF
    static let signalMagenta    = Color(red: 1.00, green: 0.00, blue: 0.80) // #FF00CC
    static let confirmGreen     = Color(red: 0.22, green: 1.00, blue: 0.08) // #39FF14
    static let warningAmber     = Color(red: 1.00, green: 0.75, blue: 0.00) // #FFBF00
    static let inferenceViolet  = Color(red: 0.55, green: 0.20, blue: 1.00) // #8C33FF

    // Surface materials — translucent layers
    static let glassWhite       = Color.white.opacity(0.06)
    static let glassEdge        = Color.white.opacity(0.12)
    static let dimLabel         = Color.white.opacity(0.5)
}
```

### 1.2 Typography

```swift
// DesignSystem/Typography.swift
import SwiftUI

enum SpatialFont {
    // Display — SF Pro Rounded for spatial warmth
    static let largeTitle  = Font.system(size: 34, weight: .bold, design: .rounded)
    static let title       = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let title2      = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let headline    = Font.system(size: 17, weight: .semibold, design: .rounded)

    // Body — SF Pro default for readability
    static let body        = Font.system(size: 17, weight: .regular)
    static let callout     = Font.system(size: 16, weight: .regular)
    static let subheadline = Font.system(size: 15, weight: .regular)
    static let caption     = Font.system(size: 13, weight: .regular)

    // Data — monospaced digits for coordinates, measurements, confidence
    static let dataLarge   = Font.system(size: 20, weight: .medium, design: .monospaced)
    static let dataMedium  = Font.system(size: 15, weight: .medium, design: .monospaced)
    static let dataSmall   = Font.system(size: 12, weight: .medium, design: .monospaced)
}
```

### 1.3 Visual Identity Rules

| Element | Treatment |
|-|-|
| Card backgrounds | `.ultraThinMaterial` over black, never solid gray |
| Card borders | 0.5pt `LinearGradient` stroke (white 50% -> white 5% -> white 20%) |
| Active/selected state | Animated `spatialGlow` modifier (pulsing cyan border + blur) |
| Shadows | Deep black shadows (radius: 30, y: 15) for floating elements |
| Corner radii | 32pt for cards, 24pt for buttons, 16pt for chips, Capsule for pills |
| Transitions | Spring(response: 0.35, dampingFraction: 0.8) — never linear |
| Icons | SF Symbols with hierarchical rendering, never flat |

### 1.4 Confidence Visual Language

| Confidence Class | Color | Shape | Animation |
|-|-|-|-|
| `confirmed-high` | `spatialCyan` | Solid ring + filled center dot | Static glow |
| `confirmed-medium` | `spatialCyan` at 70% | Solid ring, no center | Static |
| `last-seen` | `warningAmber` | Dashed ring | Pulsing scale 0.85-1.15 |
| `signal-estimated` | `signalMagenta` | Radar sweep arc | Rotating 360 loop |
| `likelihood-ranked` | `inferenceViolet` | Gradient blob | Breathing scale |
| `no-result` | `dimLabel` | Empty circle | None |

---

## 2. App Architecture

### 2.1 Pattern: Observable-Coordinator

```
@Observable AppCoordinator (navigation state, modal state, routing)
    -> injected via .environment(coordinator)
    -> owns NavigationPath per tab
    -> owns modal presentation state (fullScreenCover, sheet)

@Observable SpatialSessionManager (ARSession singleton)
    -> injected via .environment(sessionManager)
    -> manages ARSession lifecycle across view transitions
    -> feeds frames to detection pipeline

@Observable RoomStore (SwiftData wrapper)
    -> injected via .environment(roomStore)
    -> CRUD for rooms, observations, hypotheses

Feature ViewModels (@Observable, per-screen)
    -> @State private var viewModel = ScanViewModel()
    -> screen-specific logic, no navigation concerns
```

### 2.2 Navigation Strategy

**Root**: `TabView` with 2 tabs (Spaces, Settings).
**Hierarchical push** (NavigationStack): For inspecting saved data — Home -> Room Twin -> Hidden Search.
**Full-screen cover**: For immersive AR flows — Scan Room, Live Search. AR views MUST render on a pristine layer without tab bar interference.
**Sheet**: For contextual overlays — Query Console (half-sheet), Scan Results Summary, Object Detail.

```swift
// Models/Navigation/AppRoutes.swift

/// Hierarchical push destinations
enum NavigationRoute: Hashable {
    case roomTwin(roomID: UUID)
    case hiddenSearch(roomID: UUID)
    case objectDetail(observationID: UUID)
}

/// Immersive full-screen AR destinations
enum FullScreenRoute: Identifiable {
    case scanRoom
    case liveSearch(roomID: UUID?)
    case companionTarget

    var id: String { String(describing: self) }
}

/// Contextual sheet destinations
enum SheetRoute: Identifiable {
    case queryConsole(roomID: UUID?)
    case scanResults(roomID: UUID)
    case objectDetail(observationID: UUID)

    var id: String { String(describing: self) }
}
```

### 2.3 AppCoordinator

```swift
// Services/AppCoordinator.swift
import SwiftUI

@Observable
@MainActor
final class AppCoordinator {
    var selectedTab: Int = 0
    var homeNavPath = NavigationPath()

    // Modal state
    var activeFullScreen: FullScreenRoute?
    var activeSheet: SheetRoute?

    // MARK: - Navigation intents

    func push(_ route: NavigationRoute) {
        homeNavPath.append(route)
    }

    func presentImmersive(_ route: FullScreenRoute) {
        activeFullScreen = route
    }

    func presentSheet(_ route: SheetRoute) {
        activeSheet = route
    }

    func dismissModals() {
        activeFullScreen = nil
        activeSheet = nil
    }

    /// Complex transition: dismiss AR fullscreen -> push twin viewer
    func finishScanAndShowTwin(roomID: UUID) {
        dismissModals()
        // Delay push until fullScreenCover dismiss animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.selectedTab = 0
            self.push(.roomTwin(roomID: roomID))
        }
    }
}
```

### 2.4 ARSession Singleton

```swift
// Services/AR/SpatialSessionManager.swift
import ARKit
import Combine

@Observable
@MainActor
final class SpatialSessionManager: NSObject, ARSessionDelegate {
    let session = ARSession()
    var trackingState: ARCamera.TrackingState = .notAvailable
    var isRunning = false
    var worldMappingStatus: ARFrame.WorldMappingStatus = .notAvailable

    override init() {
        super.init()
        session.delegate = self
    }

    // MARK: - Session configurations

    func startWorldTracking(initialWorldMap: ARWorldMap? = nil) {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        if let map = initialWorldMap {
            config.initialWorldMap = map
        }
        session.run(config, options: initialWorldMap == nil
            ? [.resetTracking, .removeExistingAnchors]
            : [])
        isRunning = true
    }

    func pause() {
        session.pause()
        isRunning = false
    }

    func getCurrentWorldMap() async throws -> ARWorldMap {
        try await withCheckedThrowingContinuation { continuation in
            session.getCurrentWorldMap { map, error in
                if let map { continuation.resume(returning: map) }
                else { continuation.resume(throwing: error ?? ARError(.sessionFailed)) }
            }
        }
    }

    // MARK: - ARSessionDelegate

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            trackingState = frame.camera.trackingState
            worldMappingStatus = frame.worldMappingStatus
        }
    }
}
```

---

## 3. Project File Structure

```
Geolocate3D/
├── App/
│   ├── Geolocate3DApp.swift              # @main, DI setup
│   └── RootTabView.swift                 # TabView + fullScreenCover + sheet routing
│
├── DesignSystem/
│   ├── Colors.swift                      # Color palette
│   ├── Typography.swift                  # SpatialFont enum
│   ├── Components/
│   │   ├── GlassCard.swift               # Glass-morphism card container
│   │   ├── SpatialGlow.swift             # Animated glow view modifier
│   │   ├── FloatingQueryBar.swift        # Pill-shaped query input
│   │   ├── ConfidenceIndicator.swift     # Per-class visual treatment
│   │   ├── AnimatedWaveform.swift        # Voice input waveform
│   │   ├── StatusChip.swift              # Reconstruction status pill
│   │   └── SpatialButton.swift           # Primary action button
│   └── Modifiers/
│       ├── GlassBackground.swift         # .glassBackground() modifier
│       └── FadeIn.swift                  # .fadeIn(delay:) modifier
│
├── Features/
│   ├── Home/
│   │   ├── HomeView.swift                # Room grid + FAB
│   │   ├── HomeViewModel.swift           # Room list state
│   │   └── RoomPreviewCard.swift         # Individual room card
│   │
│   ├── Scan/
│   │   ├── ScanRoomView.swift            # RoomCaptureView host + overlays
│   │   ├── ScanViewModel.swift           # Scan state machine
│   │   ├── ScanOverlayView.swift         # Progress ring, object count, status
│   │   └── ScanCompletionSheet.swift     # Post-scan summary + name input
│   │
│   ├── Search/
│   │   ├── LiveSearchView.swift          # AR camera + detection overlays
│   │   ├── LiveSearchViewModel.swift     # Detection pipeline state
│   │   ├── ARObjectOverlay.swift         # RealityView attachment for detected objects
│   │   └── SearchResultCard.swift        # Result card with confidence
│   │
│   ├── Viewer/
│   │   ├── RoomTwinView.swift            # 3D model viewer with orbit controls
│   │   ├── RoomTwinViewModel.swift       # Viewer state, layer toggles
│   │   ├── AnnotationPin.swift           # 3D annotation pin entity
│   │   └── LayerToggleBar.swift          # Toggle: scaffold/objects/heatmap/dense
│   │
│   ├── Query/
│   │   ├── QueryConsoleView.swift        # Expanded query sheet
│   │   ├── QueryViewModel.swift          # Intent parsing, executor dispatch
│   │   ├── QueryResultView.swift         # Rendered response
│   │   └── QueryHistoryRow.swift         # Past query row
│   │
│   ├── HiddenSearch/
│   │   ├── HiddenSearchView.swift        # Heatmap overlay + ranked hypotheses
│   │   ├── HiddenSearchViewModel.swift   # Hypothesis state
│   │   ├── HeatmapOverlay.swift          # Custom Metal material for mesh coloring
│   │   └── HypothesisCard.swift          # Ranked result with explanation
│   │
│   └── Settings/
│       └── SettingsView.swift            # Backend config, object prototypes
│
├── Services/
│   ├── AppCoordinator.swift              # Navigation + modal state
│   ├── AR/
│   │   ├── SpatialSessionManager.swift   # ARSession singleton
│   │   ├── WorldMapStore.swift           # ARWorldMap archive/unarchive
│   │   └── RelocalizationMonitor.swift   # Relocalization state machine
│   ├── Room/
│   │   ├── RoomCaptureManager.swift      # RoomPlan session + RoomBuilder
│   │   ├── RoomPersistenceService.swift  # Save/load room assets
│   │   └── FrameBundleCollector.swift    # Keyframe + pose + depth collector
│   ├── Detection/
│   │   ├── OnDeviceDetector.swift        # Core ML closed-set detector
│   │   ├── DetectionLocalizer.swift      # 2D bbox -> 3D world position
│   │   └── ObservationTracker.swift      # Multi-frame fusion + tracking
│   ├── Query/
│   │   ├── IntentParser.swift            # NL -> structured query
│   │   ├── SearchPlanner.swift           # Route query to executor
│   │   └── Executors/
│   │       ├── LocalObservationExecutor.swift
│   │       ├── SceneGraphExecutor.swift
│   │       └── HiddenInferenceExecutor.swift
│   ├── Speech/
│   │   └── SpeechRecognitionService.swift # Speech framework wrapper
│   ├── Backend/
│   │   ├── BackendClient.swift           # FastAPI HTTP client
│   │   ├── FrameUploader.swift           # Background frame bundle upload
│   │   └── ReconstructionPoller.swift    # Poll reconstruction status
│   └── Persistence/
│       └── RoomStore.swift               # SwiftData CRUD wrapper
│
├── Models/
│   ├── Room/
│   │   ├── RoomRecord.swift              # @Model — room metadata
│   │   └── ReconstructionStatus.swift    # Enum: pending/processing/complete/failed
│   ├── Observation/
│   │   ├── ObjectObservation.swift       # @Model — detected object
│   │   ├── ObjectPrototype.swift         # @Model — known object template
│   │   └── ObservationSource.swift       # Enum: closedSet/openVocab/signal/manual
│   ├── SceneGraph/
│   │   ├── SceneNode.swift               # @Model — scene graph node
│   │   └── SceneEdge.swift               # @Model — spatial relationship
│   ├── Query/
│   │   ├── SearchQuery.swift             # Parsed query DSL
│   │   ├── SearchResult.swift            # Result with confidence + evidence
│   │   └── SearchClass.swift             # Enum: visible/lastSeen/signal/hidden
│   └── HiddenSearch/
│       ├── ObjectHypothesis.swift        # @Model — probabilistic location
│       └── HypothesisType.swift          # Enum: cooperative/tagged/inferred
│
├── Utilities/
│   ├── SIMDExtensions.swift              # simd_float4x4 <-> Data encoding
│   └── ThermalMonitor.swift              # ProcessInfo thermal state observer
│
└── Resources/
    ├── ML/
    │   └── PersonalObjectDetector.mlmodel
    └── Assets.xcassets/
```

---

## 4. Screen-by-Screen Implementation

### 4.1 App Entry Point

```swift
// App/Geolocate3DApp.swift
import SwiftUI
import SwiftData

@main
struct Geolocate3DApp: App {
    @State private var coordinator = AppCoordinator()
    @State private var sessionManager = SpatialSessionManager()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(coordinator)
                .environment(sessionManager)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [
            RoomRecord.self,
            ObjectObservation.self,
            ObjectPrototype.self,
            SceneNode.self,
            ObjectHypothesis.self
        ])
    }
}
```

```swift
// App/RootTabView.swift
import SwiftUI

struct RootTabView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var nav = coordinator

        TabView(selection: $nav.selectedTab) {
            HomeStack()
                .tabItem { Label("Spaces", systemImage: "square.grid.2x2.fill") }
                .tag(0)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(1)
        }
        .tint(.spatialCyan)
        .fullScreenCover(item: $nav.activeFullScreen) { route in
            switch route {
            case .scanRoom:
                ScanRoomView()
            case .liveSearch(let roomID):
                LiveSearchView(roomID: roomID)
            case .companionTarget:
                CompanionTargetView()
            }
        }
        .sheet(item: $nav.activeSheet) { route in
            switch route {
            case .queryConsole(let roomID):
                QueryConsoleView(roomID: roomID)
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(32)
                    .presentationBackground(.ultraThinMaterial)
            case .scanResults(let roomID):
                ScanCompletionSheet(roomID: roomID)
                    .presentationDetents([.height(400)])
                    .presentationCornerRadius(32)
            case .objectDetail(let id):
                ObjectDetailSheet(observationID: id)
                    .presentationDetents([.medium])
            }
        }
    }
}

struct HomeStack: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var nav = coordinator

        NavigationStack(path: $nav.homeNavPath) {
            HomeView()
                .navigationDestination(for: NavigationRoute.self) { route in
                    switch route {
                    case .roomTwin(let id):
                        RoomTwinView(roomID: id)
                    case .hiddenSearch(let id):
                        HiddenSearchView(roomID: id)
                    case .objectDetail(let id):
                        ObjectDetailView(observationID: id)
                    }
                }
        }
    }
}
```

### 4.2 HomeView — Room Grid

```swift
// Features/Home/HomeView.swift
import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Query(sort: \RoomRecord.updatedAt, order: .reverse) private var rooms: [RoomRecord]
    @Namespace private var heroNamespace

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                if rooms.isEmpty {
                    EmptyStateView()
                } else {
                    LazyVGrid(columns: [GridItem(.flexible())], spacing: 20) {
                        ForEach(rooms) { room in
                            RoomPreviewCard(room: room)
                                .onTapGesture {
                                    coordinator.push(.roomTwin(roomID: room.id))
                                }
                                .contextMenu {
                                    Button("Live Search", systemImage: "arkit") {
                                        coordinator.presentImmersive(.liveSearch(roomID: room.id))
                                    }
                                    Button("Query", systemImage: "text.magnifyingglass") {
                                        coordinator.presentSheet(.queryConsole(roomID: room.id))
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) { }
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .background(Color.spaceBlack)
            .navigationTitle("Spaces")

            // Floating scan button
            Button {
                coordinator.presentImmersive(.scanRoom)
            } label: {
                Image(systemName: "plus.viewfinder")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 64)
                    .background(Color.spatialCyan)
                    .clipShape(Circle())
                    .shadow(color: .spatialCyan.opacity(0.4), radius: 20, y: 8)
            }
            .padding(.trailing, 24)
            .padding(.bottom, 24)
        }
    }
}
```

### 4.3 RoomPreviewCard — Glass-morphism

```swift
// Features/Home/RoomPreviewCard.swift
import SwiftUI

struct RoomPreviewCard: View {
    let room: RoomRecord

    var body: some View {
        ZStack(alignment: .bottom) {
            // Room preview thumbnail
            if let image = room.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [.indigo.opacity(0.3), .spaceBlack],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Glass info overlay
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(room.name)
                        .font(SpatialFont.title2)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(room.observationCount) objects")
                        .font(SpatialFont.caption)
                        .foregroundStyle(.dimLabel)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.1), in: Capsule())
                }

                HStack {
                    Text(room.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(SpatialFont.caption)
                        .foregroundStyle(.dimLabel)
                    Spacer()
                    StatusChip(status: room.reconstructionStatus)
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                // Luminous specular edge
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.4), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.05), .white.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.4), radius: 30, y: 15)
    }
}
```

### 4.4 ScanRoomView — RoomPlan Integration

```swift
// Features/Scan/ScanRoomView.swift
import SwiftUI
import RoomPlan

struct ScanRoomView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var viewModel = ScanViewModel()

    var body: some View {
        ZStack {
            // RoomCaptureView bridge
            RoomCaptureViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea()

            // Scan state overlay
            VStack {
                // Top bar: status + dismiss
                HStack {
                    Button(action: { coordinator.dismissModals() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    ScanStatusPill(state: viewModel.scanState)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                // Bottom: object count + save
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(viewModel.detectedObjectCount)")
                            .font(SpatialFont.dataLarge)
                            .foregroundStyle(.spatialCyan)
                        Text("objects detected")
                            .font(SpatialFont.caption)
                            .foregroundStyle(.dimLabel)
                    }
                    Spacer()
                    if viewModel.scanState == .ready {
                        Button("Save Room") {
                            Task { await viewModel.finalizeScan() }
                        }
                        .buttonStyle(SpatialButtonStyle())
                    }
                }
                .padding(24)
                .background(.ultraThinMaterial)
            }
        }
        .onChange(of: viewModel.savedRoomID) { _, roomID in
            if let roomID {
                coordinator.finishScanAndShowTwin(roomID: roomID)
            }
        }
    }
}

// UIViewRepresentable bridge for RoomCaptureView
struct RoomCaptureViewRepresentable: UIViewRepresentable {
    let viewModel: ScanViewModel

    func makeUIView(context: Context) -> RoomCaptureView {
        let captureView = RoomCaptureView(frame: .zero)
        captureView.captureSession.delegate = viewModel
        captureView.delegate = viewModel
        viewModel.startSession(captureView: captureView)
        return captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
```

```swift
// Features/Scan/ScanViewModel.swift
import Foundation
import RoomPlan
import ARKit

@Observable
@MainActor
final class ScanViewModel: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    var scanState: ScanState = .initializing
    var detectedObjectCount: Int = 0
    var savedRoomID: UUID?

    private var captureView: RoomCaptureView?
    private var capturedRoomData: CapturedRoomData?
    private var collectedFrames: [FrameRecord] = []

    enum ScanState {
        case initializing, scanning, processing, ready, saving, error(String)
    }

    func startSession(captureView: RoomCaptureView) {
        self.captureView = captureView
        let config = RoomCaptureSession.Configuration()
        captureView.captureSession.run(configuration: config)
        scanState = .scanning
    }

    // RoomCaptureSessionDelegate
    nonisolated func captureSession(_ session: RoomCaptureSession,
                                     didUpdate room: CapturedRoom) {
        Task { @MainActor in
            detectedObjectCount = room.objects.count + room.doors.count +
                                  room.windows.count + room.openings.count
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession,
                                     didEndWith data: CapturedRoomData,
                                     error: Error?) {
        Task { @MainActor in
            capturedRoomData = data
            scanState = .processing
        }
    }

    // RoomCaptureViewDelegate
    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                                  error: Error?) -> Bool {
        true
    }

    nonisolated func captureView(didPresent processedResult: CapturedRoom,
                                  error: Error?) {
        Task { @MainActor in
            scanState = .ready
        }
    }

    func finalizeScan() async {
        guard let data = capturedRoomData else { return }
        scanState = .saving

        do {
            let builder = RoomBuilder(options: [.beautifyObjects])
            let room = try await builder.capturedRoom(from: data)

            let roomID = UUID()
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let roomDir = docsDir.appendingPathComponent("rooms/\(roomID.uuidString)")
            try FileManager.default.createDirectory(at: roomDir, withIntermediateDirectories: true)

            // Export USDZ
            let usdzURL = roomDir.appendingPathComponent("room.usdz")
            try room.export(to: usdzURL, exportOptions: .mesh)

            // Export RoomPlan JSON
            let jsonURL = roomDir.appendingPathComponent("room.json")
            let jsonData = try JSONEncoder().encode(room)
            try jsonData.write(to: jsonURL)

            // TODO: Save ARWorldMap, frame bundle, create SwiftData record

            savedRoomID = roomID
        } catch {
            scanState = .error(error.localizedDescription)
        }
    }
}
```

### 4.5 LiveSearchView — AR Detection Overlays

```swift
// Features/Search/LiveSearchView.swift
import SwiftUI
import RealityKit
import ARKit

struct LiveSearchView: View {
    let roomID: UUID?
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(SpatialSessionManager.self) private var sessionManager
    @State private var viewModel = LiveSearchViewModel()

    var body: some View {
        ZStack {
            // AR scene with detection overlays
            RealityView { content, attachments in
                // Root anchor for detected objects
                let root = Entity()
                root.name = "detectionRoot"
                content.add(root)
            } update: { content, attachments in
                guard let root = content.entities.first(where: { $0.name == "detectionRoot" })
                else { return }

                // Sync detected object overlays
                for observation in viewModel.activeObservations {
                    let tag = observation.id.uuidString

                    if let existing = root.children.first(where: { $0.name == tag }) {
                        // Update position
                        existing.transform = Transform(matrix: observation.worldTransform)
                    } else if let attachment = attachments.entity(for: tag) {
                        // Create new pin + tooltip
                        let pin = ModelEntity(
                            mesh: .generateSphere(radius: 0.015),
                            materials: [SimpleMaterial(color: .cyan, isMetallic: true)]
                        )
                        pin.name = tag
                        pin.transform = Transform(matrix: observation.worldTransform)

                        attachment.components.set(BillboardComponent())
                        attachment.position = SIMD3(0, 0.06, 0)
                        pin.addChild(attachment)

                        root.addChild(pin)
                    }
                }
            } attachments: {
                ForEach(viewModel.activeObservations) { obs in
                    Attachment(id: obs.id.uuidString) {
                        ObjectTooltip(label: obs.label, confidence: obs.confidence)
                    }
                }
            }
            .ignoresSafeArea()

            // UI overlay
            VStack {
                // Top bar
                HStack {
                    Button { coordinator.dismissModals() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    TrackingStatusBadge(state: sessionManager.trackingState)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                // Floating query bar
                FloatingQueryBar(onSubmit: { query in
                    Task { await viewModel.executeSearch(query: query) }
                })
                .padding(.bottom, 16)
            }
        }
        .onAppear { sessionManager.startWorldTracking() }
        .onDisappear { sessionManager.pause() }
    }
}

// Tooltip attachment for detected objects
struct ObjectTooltip: View {
    let label: String
    let confidence: Double

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(SpatialFont.headline)
                .foregroundStyle(.white)
            Text("\(Int(confidence * 100))%")
                .font(SpatialFont.dataSmall)
                .foregroundStyle(.spatialCyan)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        }
    }
}
```

### 4.6 RoomTwinView — 3D Model Viewer

```swift
// Features/Viewer/RoomTwinView.swift
import SwiftUI
import RealityKit

struct RoomTwinView: View {
    let roomID: UUID
    @Environment(AppCoordinator.self) private var coordinator
    @State private var viewModel: RoomTwinViewModel
    @State private var showLayers = false

    init(roomID: UUID) {
        self.roomID = roomID
        _viewModel = State(initialValue: RoomTwinViewModel(roomID: roomID))
    }

    var body: some View {
        ZStack {
            // 3D Room Model
            RealityView { content, attachments in
                if let roomEntity = try? await Entity(named: viewModel.usdzPath) {
                    content.add(roomEntity)

                    // Camera orbit entity
                    let camera = PerspectiveCamera()
                    camera.position = SIMD3(0, 2, 3)
                    camera.look(at: .zero, from: camera.position, relativeTo: nil)
                    content.add(camera)
                }

                // Add observation pins
                for obs in viewModel.observations {
                    if let pin = attachments.entity(for: obs.id.uuidString) {
                        pin.components.set(BillboardComponent())
                        pin.transform = Transform(matrix: obs.worldTransform)
                        content.add(pin)
                    }
                }
            } attachments: {
                ForEach(viewModel.observations) { obs in
                    Attachment(id: obs.id.uuidString) {
                        AnnotationPin(observation: obs)
                            .onTapGesture {
                                coordinator.presentSheet(.objectDetail(observationID: obs.id))
                            }
                    }
                }
            }
            .ignoresSafeArea()
            .gesture(
                MagnifyGesture()
                    .onChanged { value in viewModel.zoom = value.magnification }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in viewModel.orbit(by: value.translation) }
            )

            // Layer toggle overlay
            VStack {
                Spacer()
                LayerToggleBar(
                    showScaffold: $viewModel.showScaffold,
                    showObjects: $viewModel.showObjects,
                    showHeatmap: $viewModel.showHeatmap,
                    showDense: $viewModel.showDense
                )
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(viewModel.roomName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Live Search", systemImage: "arkit") {
                        coordinator.presentImmersive(.liveSearch(roomID: roomID))
                    }
                    Button("Query", systemImage: "text.magnifyingglass") {
                        coordinator.presentSheet(.queryConsole(roomID: roomID))
                    }
                    Button("Hidden Search", systemImage: "eye.slash") {
                        coordinator.push(.hiddenSearch(roomID: roomID))
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}
```

### 4.7 QueryConsoleView — NLP Input

```swift
// Features/Query/QueryConsoleView.swift
import SwiftUI

struct QueryConsoleView: View {
    let roomID: UUID?
    @State private var viewModel = QueryViewModel()
    @State private var queryText = ""
    @FocusState private var isTextFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Query input area
                HStack(spacing: 12) {
                    // Mic button
                    Button {
                        viewModel.toggleVoiceInput()
                    } label: {
                        Image(systemName: viewModel.isListening ? "mic.fill" : "mic")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(viewModel.isListening ? .black : .white)
                            .frame(width: 44, height: 44)
                            .background(viewModel.isListening ? Color.spatialCyan : .glassWhite)
                            .clipShape(Circle())
                    }

                    if viewModel.isListening {
                        AnimatedWaveform()
                            .frame(height: 24)
                    } else {
                        TextField("Where are my keys?", text: $queryText)
                            .font(SpatialFont.body)
                            .foregroundStyle(.white)
                            .tint(.spatialCyan)
                            .focused($isTextFocused)
                            .onSubmit {
                                Task {
                                    await viewModel.execute(
                                        query: queryText,
                                        roomID: roomID
                                    )
                                    queryText = ""
                                }
                            }
                    }

                    Spacer(minLength: 0)

                    if !queryText.isEmpty {
                        Button {
                            Task {
                                await viewModel.execute(query: queryText, roomID: roomID)
                                queryText = ""
                            }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.spatialCyan)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().overlay(Color.glassEdge)

                // Results / History
                ScrollView {
                    if let result = viewModel.currentResult {
                        QueryResultView(result: result)
                            .padding(16)
                    }

                    // Suggestions
                    if viewModel.currentResult == nil && queryText.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Suggestions")
                                .font(SpatialFont.caption)
                                .foregroundStyle(.dimLabel)
                                .padding(.horizontal, 16)

                            ForEach(viewModel.suggestions, id: \.self) { suggestion in
                                Button {
                                    queryText = suggestion
                                } label: {
                                    Text(suggestion)
                                        .font(SpatialFont.subheadline)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(.glassWhite, in: Capsule())
                                }
                            }
                        }
                        .padding(.top, 16)
                    }

                    // Query history
                    if !viewModel.history.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent")
                                .font(SpatialFont.caption)
                                .foregroundStyle(.dimLabel)
                                .padding(.horizontal, 16)
                            ForEach(viewModel.history) { entry in
                                QueryHistoryRow(entry: entry)
                            }
                        }
                        .padding(.top, 24)
                    }
                }
            }
            .background(Color.obsidian)
            .navigationTitle("Query")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
```

### 4.8 HiddenSearchView — Probabilistic Heatmap

```swift
// Features/HiddenSearch/HiddenSearchView.swift
import SwiftUI

struct HiddenSearchView: View {
    let roomID: UUID
    @State private var viewModel: HiddenSearchViewModel
    @State private var selectedHypothesis: ObjectHypothesis?

    init(roomID: UUID) {
        self.roomID = roomID
        _viewModel = State(initialValue: HiddenSearchViewModel(roomID: roomID))
    }

    var body: some View {
        ZStack {
            // 3D room with heatmap overlay
            // Uses CustomMaterial with Metal shader for mesh coloring
            RoomHeatmapView(
                roomID: roomID,
                hypotheses: viewModel.hypotheses,
                selectedID: selectedHypothesis?.id
            )
            .ignoresSafeArea()

            // Results panel
            VStack {
                Spacer()

                // Ranked hypothesis cards
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.hypotheses) { hypothesis in
                            HypothesisCard(
                                hypothesis: hypothesis,
                                isSelected: hypothesis.id == selectedHypothesis?.id
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35)) {
                                    selectedHypothesis = hypothesis
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: 160)
                .padding(.bottom, 24)
            }

            // Disclaimer overlay
            if viewModel.hypotheses.contains(where: { $0.hypothesisType == .inferred }) {
                VStack {
                    HStack {
                        Spacer()
                        Label("Estimated locations", systemImage: "exclamationmark.triangle")
                            .font(SpatialFont.caption)
                            .foregroundStyle(.warningAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    Spacer()
                }
            }
        }
        .navigationTitle("Hidden Search")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HypothesisCard: View {
    let hypothesis: ObjectHypothesis
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ConfidenceIndicator(level: hypothesis.confidenceClass)
                    .frame(width: 32, height: 32)
                Spacer()
                Text("#\(hypothesis.rank)")
                    .font(SpatialFont.dataSmall)
                    .foregroundStyle(.dimLabel)
            }

            Text(hypothesis.queryLabel)
                .font(SpatialFont.headline)
                .foregroundStyle(.white)

            Text(hypothesis.reasonCodes.first ?? "")
                .font(SpatialFont.caption)
                .foregroundStyle(.dimLabel)
                .lineLimit(2)

            HStack {
                Text("\(Int(hypothesis.confidence * 100))%")
                    .font(SpatialFont.dataMedium)
                    .foregroundStyle(.inferenceViolet)
                Spacer()
                Text(hypothesis.hypothesisType.label)
                    .font(SpatialFont.caption)
                    .foregroundStyle(.dimLabel)
            }
        }
        .padding(16)
        .frame(width: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isSelected ? Color.inferenceViolet.opacity(0.8) : .white.opacity(0.1),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        }
        .if(isSelected) { view in
            view.spatialGlow(color: .inferenceViolet, cornerRadius: 24, intensity: 0.6)
        }
    }
}
```

---

## 5. Key Design System Components

### 5.1 SpatialGlow Modifier

```swift
// DesignSystem/Modifiers/SpatialGlow.swift
import SwiftUI

struct SpatialGlow: ViewModifier {
    var color: Color = .spatialCyan
    var cornerRadius: CGFloat = 24
    var intensity: CGFloat = 1.0

    func body(content: Content) -> some View {
        TimelineView(.animation) { timeline in
            let phase = (sin(timeline.date.timeIntervalSinceReferenceDate * .pi) + 1) / 2

            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(color.opacity(0.1 + (phase * 0.15 * intensity)))
                        .blur(radius: 12 + (phase * 8))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            color.opacity(0.4 + (phase * 0.4 * intensity)),
                            lineWidth: 1 + (phase * 1.5)
                        )
                        .blendMode(.plusLighter)
                }
        }
    }
}

extension View {
    func spatialGlow(color: Color = .spatialCyan, cornerRadius: CGFloat = 24,
                     intensity: CGFloat = 1.0) -> some View {
        modifier(SpatialGlow(color: color, cornerRadius: cornerRadius, intensity: intensity))
    }

    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool,
                                transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}
```

### 5.2 FloatingQueryBar

```swift
// DesignSystem/Components/FloatingQueryBar.swift
import SwiftUI

struct FloatingQueryBar: View {
    var onSubmit: (String) -> Void
    @State private var query = ""
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isRecording.toggle()
                }
            } label: {
                Image(systemName: isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isRecording ? .black : .white)
                    .frame(width: 44, height: 44)
                    .background(isRecording ? Color.spatialCyan : .white.opacity(0.1))
                    .clipShape(Circle())
            }

            if isRecording {
                AnimatedWaveform()
                    .frame(height: 24)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                TextField("Find objects...", text: $query)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .tint(.spatialCyan)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .onSubmit {
                        onSubmit(query)
                        query = ""
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
        .padding(.horizontal, 24)
    }
}

struct AnimatedWaveform: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 3
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(Color.spatialCyan)
                        .frame(width: 4, height: 10 + CGFloat(sin(phase + Double(i))) * 8)
                }
            }
        }
    }
}
```

### 5.3 ConfidenceIndicator

```swift
// DesignSystem/Components/ConfidenceIndicator.swift
import SwiftUI

struct ConfidenceIndicator: View {
    let level: DetectionConfidenceClass
    @State private var pulse = false

    var body: some View {
        ZStack {
            switch level {
            case .confirmedHigh:
                Circle()
                    .stroke(Color.spatialCyan, lineWidth: 3)
                    .shadow(color: .spatialCyan.opacity(0.6), radius: 8)
                    .overlay { Circle().fill(.spatialCyan.opacity(0.3)).scaleEffect(0.3) }

            case .confirmedMedium:
                Circle()
                    .stroke(Color.spatialCyan.opacity(0.7), lineWidth: 2)

            case .lastSeen:
                Circle()
                    .stroke(Color.warningAmber, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .scaleEffect(pulse ? 1.15 : 0.85)
                    .opacity(pulse ? 0.4 : 1.0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }

            case .signalEstimated:
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.signalMagenta, lineWidth: 2)
                    .rotationEffect(.degrees(pulse ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            pulse = true
                        }
                    }

            case .likelihoodRanked:
                ZStack {
                    AngularGradient(
                        colors: [.inferenceViolet, .spatialCyan.opacity(0.5), .inferenceViolet],
                        center: .center
                    )
                    .blur(radius: 12)
                    RadialGradient(
                        colors: [.white.opacity(0.6), .clear],
                        center: .center, startRadius: 0, endRadius: 12
                    )
                    .blendMode(.plusLighter)
                }
                .clipShape(Circle())
                .scaleEffect(pulse ? 1.05 : 0.95)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }

            case .noResult:
                Circle()
                    .stroke(Color.dimLabel, lineWidth: 1)
            }
        }
    }
}
```

---

## 6. SwiftData Models

### 6.1 SIMD Encoding Extension

```swift
// Utilities/SIMDExtensions.swift
import simd
import Foundation

extension simd_float4x4 {
    func toData() -> Data {
        var matrix = self
        return withUnsafeBytes(of: &matrix) { Data($0) }
    }

    static func fromData(_ data: Data) -> simd_float4x4? {
        guard data.count == MemoryLayout<simd_float4x4>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: simd_float4x4.self) }
    }
}
```

### 6.2 Core Models

```swift
// Models/Room/RoomRecord.swift
import SwiftData
import Foundation

@Model
final class RoomRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var previewImagePath: String?
    var capturedRoomJSONPath: String?
    var roomUSDZPath: String?
    @Attribute(.externalStorage) var worldMapData: Data?
    var frameBundlePath: String?
    var denseAssetPath: String?
    var sceneGraphVersion: Int
    var reconstructionStatusRaw: String

    @Relationship(deleteRule: .cascade, inverse: \ObjectObservation.room)
    var observations: [ObjectObservation] = []

    @Relationship(deleteRule: .cascade, inverse: \SceneNode.room)
    var sceneNodes: [SceneNode] = []

    @Relationship(deleteRule: .cascade, inverse: \ObjectHypothesis.room)
    var hypotheses: [ObjectHypothesis] = []

    var reconstructionStatus: ReconstructionStatus {
        get { ReconstructionStatus(rawValue: reconstructionStatusRaw) ?? .pending }
        set { reconstructionStatusRaw = newValue.rawValue }
    }

    @Transient var observationCount: Int { observations.count }

    @Transient var previewImage: UIImage? {
        guard let path = previewImagePath else { return nil }
        return UIImage(contentsOfFile: path)
    }

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sceneGraphVersion = 0
        self.reconstructionStatusRaw = ReconstructionStatus.pending.rawValue
    }
}
```

```swift
// Models/Observation/ObjectObservation.swift
import SwiftData
import Foundation

@Model
final class ObjectObservation {
    @Attribute(.unique) var id: UUID
    var label: String
    var sourceRaw: String
    var confidence: Double
    var transformData: Data   // simd_float4x4 encoded
    var observedAt: Date
    var boundingBoxX: Float?
    var boundingBoxY: Float?
    var boundingBoxW: Float?
    var boundingBoxH: Float?
    var maskPath: String?
    var snapshotPath: String?
    var visibilityStateRaw: String

    var room: RoomRecord?
    var prototype: ObjectPrototype?

    @Transient var worldTransform: simd_float4x4 {
        simd_float4x4.fromData(transformData) ?? matrix_identity_float4x4
    }

    @Transient var source: ObservationSource {
        ObservationSource(rawValue: sourceRaw) ?? .closedSet
    }

    @Transient var confidenceClass: DetectionConfidenceClass {
        switch (source, confidence) {
        case (.signal, _): return .signalEstimated
        case (_, 0.8...): return .confirmedHigh
        case (_, 0.5..<0.8): return .confirmedMedium
        default: return .lastSeen
        }
    }

    init(label: String, source: ObservationSource, confidence: Double,
         transform: simd_float4x4) {
        self.id = UUID()
        self.label = label
        self.sourceRaw = source.rawValue
        self.confidence = confidence
        self.transformData = transform.toData()
        self.observedAt = Date()
        self.visibilityStateRaw = "visible"
    }
}
```

```swift
// Models/HiddenSearch/ObjectHypothesis.swift
import SwiftData
import Foundation

@Model
final class ObjectHypothesis {
    @Attribute(.unique) var id: UUID
    var queryLabel: String
    var hypothesisTypeRaw: String
    var rank: Int
    var confidence: Double
    var transformData: Data?
    var reasonCodes: [String]
    var generatedAt: Date

    var room: RoomRecord?

    @Transient var hypothesisType: HypothesisType {
        HypothesisType(rawValue: hypothesisTypeRaw) ?? .inferred
    }

    @Transient var confidenceClass: DetectionConfidenceClass {
        switch hypothesisType {
        case .cooperative: return .signalEstimated
        case .tagged: return .signalEstimated
        case .inferred: return .likelihoodRanked
        }
    }

    init(queryLabel: String, type: HypothesisType, rank: Int,
         confidence: Double, reasons: [String]) {
        self.id = UUID()
        self.queryLabel = queryLabel
        self.hypothesisTypeRaw = type.rawValue
        self.rank = rank
        self.confidence = confidence
        self.reasonCodes = reasons
        self.generatedAt = Date()
    }
}
```

### 6.3 Enums

```swift
// Models/Room/ReconstructionStatus.swift
enum ReconstructionStatus: String, Codable {
    case pending, uploading, processing, complete, failed
}

// Models/Observation/ObservationSource.swift
enum ObservationSource: String, Codable {
    case closedSet, openVocabulary, signal, manual
}

// Models/Query/SearchClass.swift
enum DetectionConfidenceClass: String, Codable {
    case confirmedHigh, confirmedMedium, lastSeen
    case signalEstimated, likelihoodRanked, noResult
}

// Models/HiddenSearch/HypothesisType.swift
enum HypothesisType: String, Codable {
    case cooperative, tagged, inferred

    var label: String {
        switch self {
        case .cooperative: return "Cooperative"
        case .tagged: return "Tagged"
        case .inferred: return "Likely here"
        }
    }
}

// Models/SceneGraph/SceneNodeType.swift
enum SceneNodeType: String, Codable {
    case room, section, surface, furniture, container
    case personalObject, occluder, hypothesis
}

// Models/SceneGraph/SceneEdgeType.swift
enum SceneEdgeType: String, Codable {
    case contains, supports, inside, near
    case leftOf, rightOf, inFrontOf, behind, under, occludes
}
```

---

## 7. AR Integration Patterns

### 7.1 RoomPlan Capture Flow

```
User taps "Scan" FAB
  -> coordinator.presentImmersive(.scanRoom)
  -> ScanRoomView presented as fullScreenCover
  -> RoomCaptureViewRepresentable creates UIKit bridge
  -> ScanViewModel manages:
       1. RoomCaptureSession configuration and start
       2. Delegate callbacks for real-time room updates
       3. FrameBundleCollector captures keyframes + poses + depth
       4. Object count updates during scan
  -> User taps "Save Room"
  -> ScanViewModel.finalizeScan():
       1. RoomBuilder processes CapturedRoomData (async, ~3-10s)
       2. Export USDZ to rooms/{uuid}/room.usdz
       3. Export CapturedRoom JSON
       4. Archive ARWorldMap via NSKeyedArchiver
       5. Save FrameBundle (keyframes + poses + intrinsics)
       6. Create RoomRecord in SwiftData
       7. Set savedRoomID -> triggers navigation
  -> coordinator.finishScanAndShowTwin(roomID:)
       1. Dismiss fullScreenCover
       2. After 0.45s delay, push RoomTwinView
```

### 7.2 Relocalization Flow

```
User opens saved room for Live Search
  -> coordinator.presentImmersive(.liveSearch(roomID: uuid))
  -> LiveSearchView.onAppear:
       1. Load ARWorldMap from rooms/{uuid}/worldmap.dat
       2. sessionManager.startWorldTracking(initialWorldMap: map)
       3. Show "Look around to relocalize" coaching overlay
  -> SpatialSessionManager monitors trackingState:
       - .notAvailable / .limited(.relocalizing) -> show coaching
       - .normal -> relocalization complete, enable overlays
  -> If relocalization fails after 30s:
       - Offer live-only mode (no prior anchors)
       - Saved room viewer and backend query remain available
```

### 7.3 Detection Overlay Pipeline

```
Every ~100-500ms (thermal-adaptive):
  -> ARSession.currentFrame.capturedImage
  -> Downscale to detection resolution
  -> OnDeviceDetector (Core ML):
       - Input: CVPixelBuffer
       - Output: [(label, confidence, bbox)]
  -> DetectionLocalizer per detection:
       1. Get center point of bbox in image space
       2. ARFrame.sceneDepth at center point (or raycast fallback)
       3. Unproject to 3D camera coordinates
       4. Transform to world coordinates via frame.camera.transform
  -> ObservationTracker:
       - Merge same-label within 0.4m and 2s
       - Smooth display transform via exponential moving average
       - Promote stable tracks to ObjectObservation (SwiftData)
  -> RealityView update closure:
       - Sync Entity children with active observations
       - Position SwiftUI Attachment tooltips via BillboardComponent
```

### 7.4 Thermal Management

```swift
// Utilities/ThermalMonitor.swift
import Foundation

@Observable
@MainActor
final class ThermalMonitor {
    var thermalState: ProcessInfo.ThermalState = .nominal
    var detectionFPS: Double = 10.0

    init() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateThermalState()
        }
    }

    private func updateThermalState() {
        thermalState = ProcessInfo.processInfo.thermalState
        switch thermalState {
        case .nominal:   detectionFPS = 10.0
        case .fair:      detectionFPS = 5.0
        case .serious:   detectionFPS = 2.0
        case .critical:  detectionFPS = 0.0  // Pause detection
        @unknown default: detectionFPS = 5.0
        }
    }
}
```

---

## 8. Build Order (Frontend)

| Phase | Deliverable | Depends On |
|-|-|-|
| **F1** | Xcode project, DesignSystem/, Colors, Typography, GlassCard, SpatialGlow | Nothing |
| **F2** | SwiftData models, SIMDExtensions, RoomStore, enums | F1 |
| **F3** | AppCoordinator, RootTabView, routing enums, navigation skeleton | F1 |
| **F4** | HomeView, RoomPreviewCard, empty state | F2, F3 |
| **F5** | ScanRoomView, ScanViewModel, RoomCaptureView bridge, room persistence | F4 |
| **F6** | SpatialSessionManager, WorldMapStore, relocalization monitor | F5 |
| **F7** | LiveSearchView, FloatingQueryBar, ObjectTooltip, RealityView setup | F6 |
| **F8** | OnDeviceDetector, DetectionLocalizer, ObservationTracker | F7 |
| **F9** | RoomTwinView, orbit controls, annotation pins, layer toggles | F5 |
| **F10** | QueryConsoleView, IntentParser, SearchPlanner, local executors | F8, F9 |
| **F11** | SpeechRecognitionService, voice input integration | F10 |
| **F12** | HiddenSearchView, HypothesisCard, ConfidenceIndicator, heatmap stub | F9, F10 |
| **F13** | BackendClient, FrameUploader, ReconstructionPoller | F5 |
| **F14** | Open-vocabulary search integration, backend query executor | F13 |
| **F15** | Hidden inference executor, heatmap Metal shader | F12, F14 |
| **F16** | Cooperative UWB (NearbyInteraction), CompanionTargetView | F7 |
| **F17** | ThermalMonitor, adaptive detection FPS, performance tuning | F8 |

---

## 9. Performance Targets

| Metric | Target | Enforcement |
|-|-|-|
| Relocalization | < 10s | Coaching overlay timeout at 30s |
| On-device detector | 2-10 fps adaptive | ThermalMonitor gates framerate |
| Query parse | < 300ms | Local NaturalLanguage + regex |
| AR overlay update | < 100ms after detection | Direct Entity position update |
| RoomBuilder processing | 3-10s | Async Task, never main thread |
| USDZ export | < 2s | Background thread |
| Backend open-vocab query | 3-10s | Loading indicator + cancel |
| App launch to Home | < 1s | Lazy SwiftData queries |

---

## 10. Testing Strategy

| Layer | Tool | What |
|-|-|-|
| SwiftData models | XCTest | CRUD, encoding/decoding transforms |
| ViewModels | XCTest | State transitions, mock data |
| Detection pipeline | XCTest | Mock frames -> observations |
| Query parser | XCTest | Intent classification accuracy |
| UI snapshots | Swift Snapshot Testing | Key screens in light/dark |
| AR integration | Physical device | Scan/relocalize/detect in real rooms |
| End-to-end | Physical device | Full scan -> search -> find flow |
