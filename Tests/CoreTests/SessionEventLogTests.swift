import Foundation
import Testing
import Core

struct SessionEventLogTests {
    @Test func eventLogAssignsReplayableCursorsAndStreams() async {
        let log = SessionEventLog()
        let sessionID = UUID()
        var stream = await log.stream(sessionID: sessionID).makeAsyncIterator()

        let first = await log.append(SessionEvent(sessionID: sessionID, kind: .created))
        let second = await log.append(SessionEvent(sessionID: sessionID, kind: .promptAdmitted))

        #expect(first.sequence == 1)
        #expect(second.sequence == 2)
        #expect(await stream.next() == first)
        #expect(await stream.next() == second)
        #expect(await log.replay(sessionID: sessionID, after: first.cursor).map(\.kind) == [.promptAdmitted])

        let cursor = await log.durableCursor(sessionID: sessionID)
        let replay = await log.replay(sessionID: sessionID, after: DurableEventCursor(sessionID: sessionID, cursor: first.cursor), limit: 10)
        #expect(cursor.streamID == DurableEventCursor.sessionStreamID(sessionID))
        #expect(cursor.sequence == 2)
        #expect(replay.events.map(\.kind) == [.promptAdmitted])
        #expect(replay.summary.replayedCount == 1)
    }
}
