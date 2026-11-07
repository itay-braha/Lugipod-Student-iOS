import Daily
import SwiftUI

/// Which way the app may rotate. The lesson is always held sideways (the teacher's shared screen is landscape); everything else stays upright on an
/// iPhone and free on an iPad.
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait

    @MainActor static func landscape() { set(.landscape) }

    @MainActor static func restore() { set(UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait) }

    @MainActor private static func set(_ m: UIInterfaceOrientationMask) {
        mask = m
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: m)) { _ in }
    }
}

/// The lesson, natively and full screen, held sideways: the teacher's shared screen and everyone's faces fill the display, with the mic, the
/// camera and the way out on top of it. The lesson's website page (timer, files, leave, feedback) stays loaded and slides in from the side
/// when asked for. The app's native client is the student's ONLY participant in the room; the page does not join the video call.
struct LessonCallScreen: View {
    let path: String
    @EnvironmentObject private var call: CallManager
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var celebration: CelebrationCenter
    /// Set when the lesson is over for this student (they left, or the teacher ended it): the app asks how it was.
    @State private var left: (leftEarly: Bool, teacherName: String?)?
    @State private var showPanel = false

    /// `/meeting/lesson/<id>` → ("lesson", id)
    private var meeting: (kind: String, ref: String)? {
        let parts = path.split(separator: "/").map(String.init)
        return parts.count >= 3 && parts[0] == "meeting" ? (parts[1], parts[2]) : nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: 0x0B1020).ignoresSafeArea()
                CallVideoPanel(call: call, onClose: close, onDetails: { withAnimation(.easeOut(duration: 0.25)) { showPanel.toggle() } }, insets: geo.safeAreaInsets)
                    .ignoresSafeArea()
                // The page is ALWAYS loaded (it keeps the lesson's clock, presence and the files), only slid out of view.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        HStack {
                            Text("פרטי השיעור").font(.heebo(15, 900)).foregroundStyle(.white)
                            Spacer()
                            Button { withAnimation(.easeOut(duration: 0.25)) { showPanel = false } } label: {
                                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 32, height: 32).background(Color.white.opacity(0.16), in: Circle())
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color(hex: 0x0B1020))
                        controls
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(width: min(430, max(300, geo.size.width * 0.5)))
                    .padding(.top, geo.safeAreaInsets.top).padding(.trailing, geo.safeAreaInsets.trailing)
                    .background(Color(hex: 0x0B1020))
                    .offset(x: showPanel ? 0 : min(430, max(300, geo.size.width * 0.5)) + geo.safeAreaInsets.trailing + 20)
                    .shadow(color: .black.opacity(showPanel ? 0.35 : 0), radius: 14)
                }
                .environment(\.layoutDirection, .leftToRight)
                .opacity(showPanel ? 1 : 0)          // stays loaded, but never peeks in at an edge (e.g. while the screen is still turning)
                .allowsHitTesting(showPanel)
            }
            .clipped()
        }
        .overlay {
            if let left, let meeting {
                PostLessonFlow(kind: meeting.kind, ref: meeting.ref, leftEarly: left.leftEarly, teacherName: left.teacherName) { close() }
                    .transition(.opacity)
            }
        }
        .overlay { CelebrationHost(center: celebration) }
        .animation(.easeOut(duration: 0.25), value: left == nil)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { OrientationLock.landscape() }
        .onDisappear { call.stop(); OrientationLock.restore() }
    }

    private var controls: some View {
        WebScreen(path: path, showsClose: false) { message in
            switch message {
            case .startCall(let kind, let ref): Task { await call.start(kind: kind, ref: ref) }
            case .endCall: call.stop()
            case .lessonLeft(let early, let teacher): call.stop(); left = (early, teacher); showPanel = false
            case .closeRoom: close()
            }
        }
    }

    private func close() {
        call.stop()
        router.web = nil
    }
}

/// The room as the student sees it: the teacher's shared screen (or the teacher's face) large, everyone else in a strip, the student's
/// own camera small, and the mic and camera switches.
struct CallVideoPanel: View {
    @ObservedObject var call: CallManager
    var onClose: () -> Void
    var onDetails: (() -> Void)? = nil
    var insets: EdgeInsets = EdgeInsets()

    var body: some View {
        ZStack {
            Color(hex: 0x0B1020)
            content
            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 38, height: 38).background(Color.white.opacity(0.18), in: Circle())
                    }
                    .accessibilityLabel("יציאה מהחדר")
                    Spacer()
                    if let onDetails {
                        Button(action: onDetails) {
                            Label("פרטים", systemImage: "list.bullet.rectangle.portrait").font(.heebo(13, 800)).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 9).background(Color.white.opacity(0.18), in: Capsule())
                        }
                        .accessibilityLabel("פרטי השיעור: זמן, קבצים ויציאה")
                    }
                }
                Spacer()
                controls
            }
            .padding(.top, max(10, insets.top)).padding(.bottom, max(10, insets.bottom))
            .padding(.leading, max(14, insets.leading)).padding(.trailing, max(14, insets.trailing))
        }
        .clipped()
    }

    // The big stage: someone's shared screen if there is one, otherwise the teacher, otherwise whoever is there.
    private var stage: (tile: CallTile, screen: Bool)? {
        if let s = call.tiles.first(where: { $0.screen != nil }) { return (s, true) }
        if let t = call.tiles.first(where: \.isTeacher) { return (t, false) }
        if let f = call.tiles.first { return (f, false) }
        return nil
    }

    @ViewBuilder private var content: some View {
        switch call.phase {
        case .live:
            if let stage {
                HStack(spacing: 8) {
                    CallTileView(tile: stage.tile, screen: stage.screen).frame(maxWidth: .infinity, maxHeight: .infinity)
                    // everyone else, as a column down the side (landscape has the height for it)
                    let others = call.tiles.filter { $0.id != stage.tile.id || stage.screen }
                    if !others.isEmpty || call.myCamera != nil {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 8) {
                                if let mine = call.myCamera {
                                    DailyVideoTile(track: mine, fill: true)
                                        .frame(width: 128, height: 84)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.brand400, lineWidth: 2))
                                }
                                ForEach(others) { t in CallTileView(tile: t, screen: false).frame(width: 128, height: 84) }
                            }
                        }
                        .frame(width: 128)
                    }
                }
                .padding(.horizontal, max(8, insets.leading)).padding(.top, max(54, insets.top + 44)).padding(.bottom, max(64, insets.bottom + 52))
            } else {
                status(icon: "person.2.fill", text: "ממתינים שהמורה יצטרף…")
            }
        case .joining:
            VStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("מתחברים לשיעור…").font(.heebo(15, 700)).foregroundStyle(Color(hex: 0xC7D2FE))
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 28)).foregroundStyle(Theme.amber400)
                Text(message).font(.heebo(14, 700)).foregroundStyle(.white).multilineTextAlignment(.center)
                Button("ניסיון נוסף") { Task { await call.retry() } }.buttonStyle(SoftButtonStyle())
            }
            .padding(20)
        case .idle:
            // The page asks the app to start the call as soon as it has loaded; this is the second or two before that.
            VStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("פותחים את החדר…").font(.heebo(15, 700)).foregroundStyle(Color(hex: 0xC7D2FE))
            }
        }
    }

    private func status(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Color(hex: 0xA5B4FC))
            Text(text).font(.heebo(15, 700)).foregroundStyle(Color(hex: 0xC7D2FE))
        }
    }

    @ViewBuilder private var controls: some View {
        if call.phase == .live {
            HStack(spacing: 14) {
                roundButton(on: call.micOn, onIcon: "mic.fill", offIcon: "mic.slash.fill", label: call.micOn ? "השתקה" : "ביטול השתקה") { call.setMic(!call.micOn) }
                roundButton(on: call.cameraOn, onIcon: "video.fill", offIcon: "video.slash.fill", label: call.cameraOn ? "כיבוי מצלמה" : "הפעלת מצלמה") { call.setCamera(!call.cameraOn) }
            }
        }
    }

    private func roundButton(on: Bool, onIcon: String, offIcon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: on ? onIcon : offIcon).font(.system(size: 18, weight: .bold))
                .foregroundStyle(on ? Theme.brand700 : .white)
                .frame(width: 48, height: 48)
                .background(on ? Color.white : Theme.rose500, in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        }
        .accessibilityLabel(label)
    }
}

struct CallTileView: View {
    let tile: CallTile
    let screen: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1E2542))
            if let track = screen ? tile.screen : tile.camera {
                DailyVideoTile(track: track, fill: !screen)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Text(String(tile.name.trimmingCharacters(in: .whitespaces).prefix(1)))
                    .font(.heebo(36, 800)).foregroundStyle(Color(hex: 0xA5B4FC))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 5) {
                if !screen && tile.micMuted {
                    Image(systemName: "mic.slash.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.rose500)
                }
                Text(screen ? "המסך של \(tile.name)" : tile.name)
                    .font(.heebo(11, 700)).foregroundStyle(.white).lineLimit(1)
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Color.black.opacity(0.45), in: Capsule())
            .padding(5)
        }
    }
}

/// Daily's video view inside SwiftUI.
struct DailyVideoTile: UIViewRepresentable {
    let track: VideoTrack?
    var fill: Bool = true

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.videoScaleMode = fill ? .fill : .fit
        view.track = track
        return view
    }

    func updateUIView(_ view: VideoView, context: Context) {
        if view.track != track { view.track = track }
        view.videoScaleMode = fill ? .fill : .fit
    }
}
