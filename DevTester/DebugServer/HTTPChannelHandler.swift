//
//  HTTPChannelHandler.swift
//  DevTester
//

import Foundation
import NIOCore
import NIOHTTP1

/// Assembles a complete HTTP request from NIO's incremental `HTTPServerRequestPart`
/// delivery, then dispatches asynchronously to `DebugRouter` and writes the response
/// back onto the channel.
final class HTTPChannelHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let router: DebugRouter

    // Accumulated request state for the current request
    private var requestHead: HTTPRequestHead?
    private var requestBodyBuffer: ByteBuffer?

    init(router: DebugRouter) {
        self.router = router
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestHead = head
            requestBodyBuffer = context.channel.allocator.buffer(capacity: 0)

        case .body(let buffer):
            requestBodyBuffer?.writeImmutableBuffer(buffer)

        case .end:
            guard let head = requestHead else { return }
            let bodyData: Data?
            if let buf = requestBodyBuffer, buf.readableBytes > 0 {
                bodyData = Data(buf.readableBytesView)
            } else {
                bodyData = nil
            }

            var headers: [String: String] = [:]
            for (name, value) in head.headers {
                headers[name.lowercased()] = value
            }

            let request = InboundHTTPRequest(
                method: head.method.rawValue,
                path: head.uri,
                headers: headers,
                body: bodyData
            )

            requestHead = nil
            requestBodyBuffer = nil

            let router = self.router
            let channel = context.channel

            Task {
                let response = await router.handle(request)
                await Self.writeResponse(response, to: channel)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("[HTTPChannelHandler] error: \(error)")
        context.close(promise: nil)
    }

    // MARK: - Response writing (static so it can be called from Task)

    private static func writeResponse(_ response: HTTPRouteResponse, to channel: Channel) async {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: response.contentType)
        headers.add(name: "Content-Length", value: "\(response.body.count)")
        headers.add(name: "Connection", value: "close")
        headers.add(name: "Access-Control-Allow-Origin", value: "*")
        headers.add(name: "Access-Control-Allow-Methods", value: "GET, POST, OPTIONS")
        headers.add(name: "Access-Control-Allow-Headers", value: "Content-Type")
        headers.add(name: "Cache-Control", value: "no-store, no-cache, must-revalidate, max-age=0")
        headers.add(name: "Pragma", value: "no-cache")
        headers.add(name: "Expires", value: "0")

        let status = httpStatus(for: response.status)
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)

        var bodyBuffer = channel.allocator.buffer(capacity: response.body.count)
        bodyBuffer.writeBytes(response.body)

        let promise: EventLoopPromise<Void> = channel.eventLoop.makePromise()
        promise.futureResult.whenComplete { _ in
            channel.close(promise: nil)
        }
        channel.write(HTTPServerResponsePart.head(head), promise: nil)
        channel.write(HTTPServerResponsePart.body(.byteBuffer(bodyBuffer)), promise: nil)
        channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: promise)
    }

    private static func httpStatus(for code: UInt) -> HTTPResponseStatus {
        switch code {
        case 200: return .ok
        case 204: return .noContent
        case 404: return .notFound
        case 501: return .notImplemented
        default: return HTTPResponseStatus(statusCode: Int(code))
        }
    }
}
