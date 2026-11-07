import Daily
import Foundation
import UIKit

/// One person in the room, as the lesson screen draws them.
struct CallTile: Identifiable, Equatable {
    let id: String
    let name: String
    let camera: VideoTrack?
    let screen: VideoTrack?
    let micMuted: Bool
    let isTeacher: Bool
}

/// The student's native call client, and the student's ONLY participant in the lesson room (the lesson page inside the app does not join
/// the video call, so the room counts the student once). Native video and audio are why this exists: no web view camera quirks, and the
/// voice keeps working with the screen locked or another app in front. The web page below is the control surface (timer, files, leave,
/// feedback). This object also keeps the presence heartbeat going, because a backgrounded web view stops running timers.
final class CallManager: NSObject, ObservableObject {
    enum Phase: Equatable { case idle, joining, live, failed(String) }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var micOn = true
    @Published private(set) var cameraOn = false
    /// Everyone else in the room.
    @Published private(set) var tiles: [CallTile] = []
    /// The student's own camera, for the small self-view.
    @Published private(set) var myCamera: VideoTrack?

    private var client: CallClient?
    private var session: (kind: String, ref: String)?
    private var heartbeat: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    // MARK: - Lifecycle

    @MainActor
    func start(kind: String, ref: String) async {
        guard phase == .idle || isFailed else { return }
        phase = .joining
        session = (kind, ref)
        do {
            let data = try await API.request("POST", "/api/meeting/native-join", json: ["kind": kind, "ref": ref], timeout: 30)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urlStr = obj["roomUrl"] as? String, let url = URL(string: urlStr),
                  let token = obj["token"] as? String else { throw APIError.badURL }

            let call = CallClient()
            call.delegate = self
            client = call
            // Voice on, camera off to begin with: the student chooses to show their face.
            call.setInputsEnabled([.camera: false, .microphone: true], completion: nil)
            micOn = true
            cameraOn = false
            call.join(url: url, token: MeetingToken(stringValue: token)) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.phase = .live
                        self?.refreshParticipants()
                        self?.startHeartbeat()
                    case .failure(let e):
                        self?.fail("לא הצלחנו להתחבר לשיעור (\(e))")
                    }
                }
            }
        } catch APIError.server(_, let message) where !message.isEmpty {
            fail(message)
        } catch {
            fail("לא הצלחנו לפתוח את השיעור. בדקו חיבור ונסו שוב.")
        }
    }

    @MainActor
    func stop() {
        heartbeat?.cancel()
        heartbeat = nil
        removeObservers()
        client?.leave(completion: nil)
        client = nil
        session = nil
        micOn = true
        cameraOn = false
        tiles = []
        myCamera = nil
        phase = .idle
    }

    #if DEBUG
    /// Sample room for the CI screenshots (preview mode "call"): no network, no video tracks.
    @MainActor
    func loadPreview() {
        phase = .live
        micOn = true
        tiles = [
            CallTile(id: "t", name: "איתי", camera: nil, screen: nil, micMuted: false, isTeacher: true),
            CallTile(id: "s1", name: "דנה", camera: nil, screen: nil, micMuted: true, isTeacher: false),
            CallTile(id: "s2", name: "יואב", camera: nil, screen: nil, micMuted: false, isTeacher: false),
        ]
    }
    #endif

    /// Tries the same lesson again after a failed join.
    @MainActor
    func retry() async {
        guard let session else { return }
        await start(kind: session.kind, ref: session.ref)
    }

    @MainActor
    func setCamera(_ on: Bool) {
        cameraOn = on
        client?.setInputEnabled(.camera, on, completion: nil)
        refreshParticipants()
    }

    @MainActor
    func setMic(_ on: Bool) {
        micOn = on
        client?.setInputEnabled(.microphone, on, completion: nil)
    }

    /// Rebuilds the tiles from Daily's participant list.
    @MainActor
    func refreshParticipants() {
        guard let client else { tiles = []; myCamera = nil; return }
        myCamera = cameraOn ? client.participants.local.media?.camera.track : nil
        tiles = client.participants.remote.values
            .map { p -> CallTile in
                let muted: Bool
                switch p.media?.microphone.state {
                case .some(.off): muted = true
                default: muted = false
                }
                return CallTile(id: p.id.uuidString,
                                name: p.info.username ?? "משתתף/ת",
                                camera: p.media?.camera.track,
                                screen: p.media?.screenVideo.track,
                                micMuted: muted,
                                isTeacher: p.info.isOwner)
            }
            .sorted { ($0.isTeacher ? 0 : 1, $0.name) < ($1.isTeacher ? 0 : 1, $1.name) }
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    @MainActor
    private func fail(_ message: String) {
        client?.leave(completion: nil)
        client = nil
        heartbeat?.cancel()
        heartbeat = nil
        removeObservers()
        phase = .failed(message)
    }

    // MARK: - Presence

    /// One presence beat. It also tells the teacher what the student is watching on (phone or tablet) and whether the lesson is in front of
    /// them: `active` is false while the app is in the background or covered (the teacher sees a dimmed "not watching" sign).
    private func beat() async {
        guard let session else { return }
        let (device, active) = await MainActor.run {
            (UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone", UIApplication.shared.applicationState == .active)
        }
        _ = try? await API.post("/api/meeting/state", json: [
            "kind": session.kind, "ref": session.ref, "intent": "heartbeat",
            "client": ["device": device, "active": active],
        ])
    }

    @MainActor
    private func startHeartbeat() {
        guard session != nil else { return }
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                await self?.beat()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        // Say so straight away when the app goes to the background or comes back, not at the next 5 s beat.
        for name in [UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { await self?.beat() }
            })
        }
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
    }
}

extension CallManager: CallClientDelegate {
    func callClient(_ callClient: CallClient, participantJoined participant: Participant) {
        Task { @MainActor in self.refreshParticipants() }
    }

    func callClient(_ callClient: CallClient, participantUpdated participant: Participant) {
        Task { @MainActor in self.refreshParticipants() }
    }

    func callClient(_ callClient: CallClient, participantLeft participant: Participant, withReason reason: ParticipantLeftReason) {
        Task { @MainActor in self.refreshParticipants() }
    }
}
