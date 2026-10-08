import Foundation

// MARK: - Media Track

/// A selectable audio or subtitle track, normalised across playback engines.
///
/// `id` carries whatever the owning engine needs to make the selection: a libVLC
/// track ID for VOD, or an index into the cached `AVMediaSelectionOption` list for
/// live HLS. Callers hand the id straight back to the view model, so the two
/// numbering schemes never have to be told apart by the UI.
struct MediaTrack: Identifiable, Hashable {
    let id: Int
    let name: String

    /// Sentinel for "no track", shown as "Off" in subtitle menus. Matches
    /// libVLC's own convention and AVFoundation's "deselect the group" case.
    static let offID = -1
}
