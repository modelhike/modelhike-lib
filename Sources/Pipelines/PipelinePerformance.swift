//
//  PipelinePerformance.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

public protocol PipelinePerformanceRecorder: Actor, Sendable {
    func recordPipelineStarted() async
    func recordPipelineCompleted(durationMs: Double, success: Bool, errorMessage: String?) async
    func recordPhaseStarted(name: String) async
    func recordPhaseCompleted(name: String, durationMs: Double, success: Bool, errorMessage: String?) async
    func recordPassCompleted(phaseName: String, passName: String, durationMs: Double, success: Bool, errorMessage: String?) async
    func report() async -> PipelinePerformanceReport?
    func textReport() async -> String
}

public struct PipelinePerformancePassRecord: Sendable {
    public let phaseName: String
    public let passName: String
    public let durationMs: Double
    public let success: Bool
    public let errorMessage: String?

    public init(phaseName: String, passName: String, durationMs: Double, success: Bool, errorMessage: String?) {
        self.phaseName = phaseName
        self.passName = passName
        self.durationMs = durationMs
        self.success = success
        self.errorMessage = errorMessage
    }
}

public struct PipelinePerformancePhaseRecord: Sendable {
    public let name: String
    public let durationMs: Double?
    public let success: Bool?
    public let errorMessage: String?
    public let passes: [PipelinePerformancePassRecord]

    public init(name: String, durationMs: Double?, success: Bool?, errorMessage: String?, passes: [PipelinePerformancePassRecord]) {
        self.name = name
        self.durationMs = durationMs
        self.success = success
        self.errorMessage = errorMessage
        self.passes = passes
    }
}

public struct PipelinePerformanceReport: Sendable {
    public let startedAt: Date
    public let completedAt: Date?
    public let totalDurationMs: Double?
    public let success: Bool?
    public let errorMessage: String?
    public let phases: [PipelinePerformancePhaseRecord]

    public init(
        startedAt: Date,
        completedAt: Date?,
        totalDurationMs: Double?,
        success: Bool?,
        errorMessage: String?,
        phases: [PipelinePerformancePhaseRecord]
    ) {
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.totalDurationMs = totalDurationMs
        self.success = success
        self.errorMessage = errorMessage
        self.phases = phases
    }
}

public actor DefaultPipelinePerformanceRecorder: PipelinePerformanceRecorder {
    private struct MutablePhaseRecord: Sendable {
        let name: String
        var durationMs: Double?
        var success: Bool?
        var errorMessage: String?
        var passes: [PipelinePerformancePassRecord]
    }

    private var startedAt: Date?
    private var completedAt: Date?
    private var totalDurationMs: Double?
    private var success: Bool?
    private var errorMessage: String?
    private var phaseRecords: [MutablePhaseRecord] = []

    public init() {}

    public func recordPipelineStarted() async {
        startedAt = Date()
        completedAt = nil
        totalDurationMs = nil
        success = nil
        errorMessage = nil
        phaseRecords = []
    }

    public func recordPipelineCompleted(durationMs: Double, success: Bool, errorMessage: String?) async {
        completedAt = Date()
        totalDurationMs = durationMs
        self.success = success
        self.errorMessage = errorMessage
    }

    public func recordPhaseStarted(name: String) async {
        for phase in phaseRecords where phase.name == name {
            return
        }
        phaseRecords.append(MutablePhaseRecord(name: name, durationMs: nil, success: nil, errorMessage: nil, passes: []))
    }

    public func recordPhaseCompleted(name: String, durationMs: Double, success: Bool, errorMessage: String?) async {
        upsertPhase(named: name) { phase in
            phase.durationMs = durationMs
            phase.success = success
            phase.errorMessage = errorMessage
        }
    }

    public func recordPassCompleted(
        phaseName: String, passName: String, durationMs: Double, success: Bool, errorMessage: String?
    ) async {
        upsertPhase(named: phaseName) { phase in
            phase.passes.append(
                PipelinePerformancePassRecord(
                    phaseName: phaseName,
                    passName: passName,
                    durationMs: durationMs,
                    success: success,
                    errorMessage: errorMessage
                )
            )
        }
    }

    public func report() async -> PipelinePerformanceReport? {
        guard let startedAt else { return nil }
        return PipelinePerformanceReport(
            startedAt: startedAt,
            completedAt: completedAt,
            totalDurationMs: totalDurationMs,
            success: success,
            errorMessage: errorMessage,
            phases: phaseRecords.map {
                PipelinePerformancePhaseRecord(
                    name: $0.name,
                    durationMs: $0.durationMs,
                    success: $0.success,
                    errorMessage: $0.errorMessage,
                    passes: $0.passes
                )
            }
        )
    }

    public func textReport() async -> String {
        guard let report = await report() else {
            return "No pipeline performance data recorded."
        }

        var lines: [String] = []
        lines.append("Pipeline total: \(Self.format(report.totalDurationMs))")

        for phase in report.phases {
            lines.append("Phase \(phase.name): \(Self.format(phase.durationMs))")
            for pass in phase.passes {
                lines.append("  Pass \(pass.passName): \(Self.format(pass.durationMs))")
            }
        }

        return lines.joined(separator: String.newLine)
    }

    private func upsertPhase(named name: String, update: (inout MutablePhaseRecord) -> Void) {
        if let index = phaseRecords.firstIndex(where: { $0.name == name }) {
            update(&phaseRecords[index])
        } else {
            var record = MutablePhaseRecord(name: name, durationMs: nil, success: nil, errorMessage: nil, passes: [])
            update(&record)
            phaseRecords.append(record)
        }
    }

    private static func format(_ durationMs: Double?) -> String {
        guard let durationMs else { return "n/a" }
        return String(format: "%.3f ms", durationMs)
    }
}

enum PipelinePerformanceTime {
    static func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        return (Double(components.seconds) * 1000.0) + (Double(components.attoseconds) / 1_000_000_000_000_000.0)
    }
}
