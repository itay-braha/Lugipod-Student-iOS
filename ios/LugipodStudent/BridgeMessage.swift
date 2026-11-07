import Foundation

/// What the Lugipod lesson page (MeetingRoom.tsx) tells the app, via `webkit.messageHandlers.lugipod.postMessage(...)`.
enum BridgeMessage: Equatable {
    case startCall(kind: String, ref: String)
    case endCall
    /// The student left and filled in the feedback: close the lesson screen.
    case closeRoom

    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "startCall":
            guard let kind = dict["kind"] as? String, ["lesson", "sos"].contains(kind),
                  let ref = dict["ref"] as? String, !ref.isEmpty else { return nil }
            self = .startCall(kind: kind, ref: ref)
        case "endCall": self = .endCall
        case "closeRoom": self = .closeRoom
        default: return nil
        }
    }
}
