@testable import KSPlayer
import XCTest

/// Embedded subtitle cues must share the playback clock's time base.
///
/// Fixture `subtitle_font_attachment.mkv` (6s, generated with ffmpeg):
/// - one ASS cue at 2.5s,
/// - a font attachment labelled `font/ttf` (the MIME current mkvmerge
///   writes). FFmpeg doesn't map that MIME to a codec, so
///   `avformat_find_stream_info` never finishes early and reads ~5s ahead.
///   While doing that it sees the cue and pins the subtitle stream's own
///   `start_time` to 2.5s,
/// - a container `start_time` of -0.021s (AAC priming).
///
/// The playback clock is rebased on the container start. If cues were rebased
/// on the subtitle stream's start (2.5s), every cue would render 2.5s early.
class SubtitleStartTimeTest: XCTestCase {
    private final class OpenWaiter: MEPlayerDelegate {
        let opened: XCTestExpectation
        init(_ opened: XCTestExpectation) { self.opened = opened }
        func sourceDidChange(loadingState _: LoadingState) {}
        func sourceDidOpened() { opened.fulfill() }
        func sourceDidFailed(error: NSError?) { XCTFail("open failed: \(String(describing: error))") }
        func sourceDidFinished() {}
        func sourceDidChange(oldBitRate _: Int64, newBitrate _: Int64) {}
    }

    func testSubtitleTrackUsesContainerStartTime() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "subtitle_font_attachment", withExtension: "mkv"))
        let item = MEPlayerItem(url: url, options: KSOptions())
        let waiter = OpenWaiter(expectation(description: "source opened"))
        item.delegate = waiter
        item.prepareToPlay()
        wait(for: [waiter.opened], timeout: 10)
        defer { item.shutdown() }

        let subtitle = try XCTUnwrap(item.assetTracks.first { $0.mediaType == .subtitle })
        XCTAssertEqual(subtitle.startTime.seconds, -0.021, accuracy: 0.001)

        // The decoded cue must land on the clock's time base too. Media time
        // 2.5s is playback time 2.521s (2.5 minus the -0.021s container start).
        // Rebased on the stream's own start it would sit at 0.021s instead, so
        // look in both places to make a regression report where it landed.
        let deadline = Date().addingTimeInterval(10)
        var parts = [SubtitlePart]()
        while parts.isEmpty, Date() < deadline {
            parts = subtitle.search(for: 3.0) + subtitle.search(for: 0.5)
            if parts.isEmpty { Thread.sleep(forTimeInterval: 0.05) }
        }
        let cue = try XCTUnwrap(parts.first, "cue was never decoded")
        XCTAssertEqual(cue.start, 2.521, accuracy: 0.001)
        XCTAssertEqual(cue.end, 4.021, accuracy: 0.001)
        XCTAssertTrue(subtitle.search(for: 1.0).isEmpty, "cue must not show before it is spoken")
    }
}
