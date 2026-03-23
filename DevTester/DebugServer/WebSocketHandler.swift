//
//  WebSocketHandler.swift
//  DevTester
//

import Foundation
import NIOCore
import NIOWebSocket
import ModelHike

/// Writes a WebSocket text frame to a channel.
/// Uses NIOLoopBound to safely capture the channel for async use.
private func writeWebSocketText(_ text: String, to channel: any Channel) {
    let eventLoop = channel.eventLoop
    eventLoop.execute {
        guard channel.isActive else { return }
        var buffer = channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        // Use the channel's write method which routes through the pipeline correctly
        _ = channel.writeAndFlush(frame)
    }
}

/// JSON shapes for messages sent from the browser to the server.
private struct BrowserCommand: Decodable {
    let type: String
    // addBreakpoint / removeBreakpoint
    let fileIdentifier: String?
    let lineNo: Int?
    // resume
    let mode: String?
}

/// `ChannelInboundHandler` installed after a successful WebSocket upgrade.
/// - Registers the channel with `WebSocketClientManager` so events can be broadcast.
/// - Decodes incoming text frames as JSON commands and dispatches them to `LiveDebugStepper`.
/// - Responds to ping frames with pong frames.
final class WebSocketHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let wsManager: WebSocketClientManager
    private let stepper: LiveDebugStepper?
    private var clientID: ObjectIdentifier?

    init(wsManager: WebSocketClientManager, stepper: LiveDebugStepper?) {
        self.wsManager = wsManager
        self.stepper = stepper
    }

    // MARK: - Channel lifecycle

    /// `handlerAdded` fires immediately when the handler is inserted into the pipeline,
    /// even if the channel is already active — which is always the case for WebSocket
    /// upgrade handlers added via `upgradePipelineHandler`. Using `channelActive` here
    /// would be unreliable because NIO does not re-fire `channelActive` for handlers
    /// added after the channel has already transitioned to the active state.
    func handlerAdded(context: ChannelHandlerContext) {
        let channel = context.channel
        let id = ObjectIdentifier(channel)
        clientID = id

        // Swift 6's implicit existential opening passes `any Channel` to the generic
        // writeWebSocketText helper, which holds a concrete `C: Channel` type and can
        // therefore call the non-deprecated Sendable-aware writeAndFlush overload.
        let sendClosure: @Sendable (String) -> Void = { text in
            writeWebSocketText(text, to: channel)
        }

        let client = WebSocketClient(id: id, send: sendClosure)
        let manager = wsManager
        Task {
            await manager.add(client)
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        guard let id = clientID else { return }
        let manager = wsManager
        Task {
            await manager.remove(id: id)
        }
    }

    // MARK: - Frame handling

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        switch frame.opcode {
        case .text:
            var payload = frame.unmaskedData
            guard let text = payload.readString(length: payload.readableBytes) else { return }
            handleTextMessage(text, context: context)

        case .ping:
            var pongData = context.channel.allocator.buffer(capacity: frame.data.readableBytes)
            pongData.writeImmutableBuffer(frame.data)
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: pongData)
            context.writeAndFlush(NIOAny(pong), promise: nil)

        case .connectionClose:
            let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: frame.data)
            let channel = context.channel
            context.writeAndFlush(NIOAny(closeFrame)).whenComplete { _ in
                channel.close(promise: nil)
            }

        default:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("[WebSocketHandler] error: \(error)")
        context.close(promise: nil)
    }

    // MARK: - Command dispatch

    private func handleTextMessage(_ text: String, context: ChannelHandlerContext) {
        print("[WebSocketHandler] received message: \(text)")
        guard let data = text.data(using: .utf8),
              let command = try? JSONDecoder().decode(BrowserCommand.self, from: data) else {
            print("[WebSocketHandler] could not decode message: \(text)")
            return
        }
        print("[WebSocketHandler] decoded command type: \(command.type)")

        switch command.type {
        case "addBreakpoint":
            guard let fileId = command.fileIdentifier, let line = command.lineNo else { return }
            let bp = BreakpointLocation(fileIdentifier: fileId, lineNo: line)
            guard let stepper else { return }
            Task { await stepper.addBreakpoint(bp) }

        case "removeBreakpoint":
            guard let fileId = command.fileIdentifier, let line = command.lineNo else { return }
            let bp = BreakpointLocation(fileIdentifier: fileId, lineNo: line)
            guard let stepper else { return }
            Task { await stepper.removeBreakpoint(bp) }

        case "resume":
            let modeStr = command.mode ?? "run"
            let stepMode = StepMode(rawValue: modeStr) ?? .run
            print("[WebSocketHandler] resume command, mode: \(stepMode), stepper: \(stepper != nil)")
            guard let stepper else { 
                print("[WebSocketHandler] ERROR: stepper is nil!")
                return 
            }
            Task { 
                print("[WebSocketHandler] calling stepper.resume()")
                await stepper.resume(mode: stepMode) 
                print("[WebSocketHandler] stepper.resume() completed")
            }

        default:
            print("[WebSocketHandler] unknown command type: \(command.type)")
        }
    }
}
