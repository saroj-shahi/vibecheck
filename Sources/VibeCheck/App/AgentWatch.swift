import Foundation

/// Agent runs seen from local logs: whether an agent is working (keep-awake trigger) and when a long run
/// has finished (opt-in notification). Pure logic; fed the agent summaries from `AgentUsageStore`.
struct AgentWatch {
    /// An agent counts as working while it wrote usage this recently. Longer than `AgentSummary.isWorking`
    /// (2 min) so a long tool call (a test run, a build) doesn't end the run halfway.
    static let quietGap: TimeInterval = 3 * 60
    /// Only runs at least this long get a "finished" notification.
    static let longRun: TimeInterval = 10 * 60

    static func isWorking(_ agent: AgentSummary, now: Date) -> Bool {
        agent.lastActive.map { now.timeIntervalSince($0) < quietGap } ?? false
    }

    static func anyWorking(_ agents: [AgentSummary], now: Date) -> Bool {
        agents.contains { isWorking($0, now: now) }
    }

    struct Finished: Equatable {
        var agent: AgentKind
        var duration: TimeInterval
    }

    /// When each running agent's current run started (its first write after a quiet gap).
    private var runStart: [AgentKind: Date] = [:]
    /// The last write seen per agent, to tell a new run from the same one.
    private var lastSeen: [AgentKind: Date] = [:]

    /// Call on every tick. Returns the long runs that just finished.
    mutating func update(_ agents: [AgentSummary], now: Date) -> [Finished] {
        var finished: [Finished] = []
        for agent in agents {
            let kind = agent.agent
            // No usage today (e.g. just after midnight): drop any open run without notifying.
            guard let last = agent.lastActive else { runStart[kind] = nil; lastSeen[kind] = nil; continue }
            if Self.isWorking(agent, now: now) {
                // A write after a quiet gap starts a new run; the first write we ever see starts one too.
                if runStart[kind] == nil || (lastSeen[kind].map { last.timeIntervalSince($0) >= Self.quietGap } ?? false) {
                    runStart[kind] = last
                }
                lastSeen[kind] = last
            } else if let start = runStart.removeValue(forKey: kind) {
                let duration = last.timeIntervalSince(start)
                if duration >= Self.longRun { finished.append(Finished(agent: kind, duration: duration)) }
            }
        }
        return finished
    }

    /// "Claude Code is done" / "It worked for 24 min."
    static func message(_ run: Finished) -> (title: String, body: String) {
        let minutes = Int((run.duration / 60).rounded())
        let length = minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
        return ("\(run.agent.title) is done", "It worked for \(length).")
    }
}
