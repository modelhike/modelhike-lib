//
//  DebugHTTPServer.swift
//  DevTester
//

import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import ModelHike

actor DebugHTTPServer {
    private let router: DebugRouter
    private let wsManager: WebSocketClientManager
    private let stepper: LiveDebugStepper?
    private let port: UInt16
    private var serverChannel: (any Channel)?
    private var eventLoopGroup: (any EventLoopGroup)?

    init(
        session: DebugSession,
        recorder: DefaultDebugRecorder? = nil,
        pipeline: Pipeline? = nil,
        renderedOutputs: [RenderedOutputRecord] = [],
        port: UInt16 = 4800,
        devAssetsPath: String? = nil,
        serverMode: DebugServerMode = .postMortem,
        wsManager: WebSocketClientManager = WebSocketClientManager(),
        stepper: LiveDebugStepper? = nil
    ) {
        self.wsManager = wsManager
        self.stepper = stepper
        self.port = port
        self.router = DebugRouter(
            session: session,
            renderedOutputs: renderedOutputs,
            recorder: recorder,
            pipeline: pipeline,
            devAssetsPath: devAssetsPath,
            serverMode: serverMode,
            stepper: stepper
        )
    }

    func start() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        eventLoopGroup = group

        let router = self.router
        let wsManager = self.wsManager
        let stepper = self.stepper

        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { channel, head in
                guard head.uri.hasPrefix("/ws") else {
                    return channel.eventLoop.makeSucceededFuture(nil)
                }
                return channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { channel, _ in
                channel.pipeline.addHandler(
                    WebSocketHandler(wsManager: wsManager, stepper: stepper)
                )
            }
        )

        let channel = try await ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { ch in
                let httpHandler = HTTPChannelHandler(router: router)
                return ch.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (upgraders: [upgrader], completionHandler: { ctx in
                        // Remove our HTTP handler when WebSocket upgrade completes
                        ctx.pipeline.removeHandler(httpHandler, promise: nil)
                    })
                ).flatMap {
                    ch.pipeline.addHandler(httpHandler)
                }
            }
            .bind(host: "127.0.0.1", port: Int(self.port))
            .get()

        serverChannel = channel
        print("🔍 Debug console: http://localhost:\(port)")
    }

    /// Call this in --debug-stepping mode after the pipeline completes so that
    /// subsequent REST requests see the full session instead of the empty placeholder.
    func updateSession(_ session: DebugSession, renderedOutputs: [RenderedOutputRecord]) async {
        await router.updateSession(session, renderedOutputs: renderedOutputs)
    }

    func stop() async {
        try? await serverChannel?.close()
        try? await eventLoopGroup?.shutdownGracefully()
        serverChannel = nil
        eventLoopGroup = nil
    }
}
