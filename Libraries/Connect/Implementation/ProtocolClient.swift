// Copyright 2022-2023 Buf Technologies, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import os.log
import SwiftProtobuf

/// Concrete implementation of the `ProtocolClientInterface`.
public final class ProtocolClient {
    private let config: ProtocolClientConfig
    private let httpClient: HTTPClientInterface

    /// Designated initializer.
    ///
    /// - parameter httpClient: The HTTP client to use for sending requests and starting streams.
    /// - parameter config: The configuration to use for requests and streams.
    public init(
        httpClient: HTTPClientInterface = URLSessionHTTPClient(),
        config: ProtocolClientConfig
    ) {
        self.httpClient = httpClient
        self.config = config
    }
}

extension ProtocolClient: ProtocolClientInterface {
    // MARK: - Callbacks

    @discardableResult
    public func unary<
        Input: SwiftProtobuf.Message, Output: SwiftProtobuf.Message
    >(
        path: String,
        method: String,
        request: Input,
        headers: Headers,
        completion: @escaping (ResponseMessage<Output>) -> Void
    ) -> Cancelable {
        let codec = self.config.codec
        let data: Data
        do {
            data = try codec.serialize(message: request)
        } catch let error {
            completion(ResponseMessage(
                code: .unknown,
                result: .failure(ConnectError(
                    code: .unknown, message: "request serialization failed", exception: error,
                    details: [], metadata: [:]
                ))
            ))
            return Cancelable(cancel: {})
        }

        #warning("todo - handle vanilla http")
        let chain = self.config.createInterceptorChain().unaryFunction()
        let url = URL(string: path, relativeTo: URL(string: self.config.host))!
        let request = chain.requestFunction(HTTPRequest(
            url: url,
            contentType: "application/\(codec.name())",
            headers: headers,
            message: data
        ))
        return self.httpClient.unary(request: request) { response in
            let response = chain.responseFunction(response)
            let responseMessage: ResponseMessage<Output>
            if response.code != .ok {
                let error = (response.error as? ConnectError)
                    ?? ConnectError.from(
                        code: response.code, headers: response.headers, source: response.message
                    )
                responseMessage = ResponseMessage(
                    code: response.code,
                    headers: response.headers,
                    result: .failure(error),
                    trailers: response.trailers
                )
            } else if let message = response.message {
                do {
                    responseMessage = ResponseMessage(
                        code: response.code,
                        headers: response.headers,
                        result: .success(try codec.deserialize(source: message)),
                        trailers: response.trailers
                    )
                } catch let error {
                    responseMessage = ResponseMessage(
                        code: response.code,
                        headers: response.headers,
                        result: .failure(ConnectError(
                            code: response.code, message: nil, exception: error,
                            details: [], metadata: response.headers
                        )),
                        trailers: response.trailers
                    )
                }
            } else {
                responseMessage = ResponseMessage(
                    code: response.code,
                    headers: response.headers,
                    result: .success(.init()),
                    trailers: response.trailers
                )
            }
            completion(responseMessage)
        }
    }

    public func bidirectionalStream<
        Input: SwiftProtobuf.Message, Output: SwiftProtobuf.Message
    >(
        path: String,
        headers: Headers,
        onResult: @escaping (StreamResult<Output>) -> Void
    ) -> any BidirectionalStreamInterface<Input> {
        return BidirectionalStream(
            requestCallbacks: self.createRequestCallbacks(
                path: path, headers: headers, onResult: onResult
            ),
            codec: self.config.codec
        )
    }

    public func clientOnlyStream<
        Input: SwiftProtobuf.Message, Output: SwiftProtobuf.Message
    >(
        path: String,
        headers: Headers,
        onResult: @escaping (StreamResult<Output>) -> Void
    ) -> any ClientOnlyStreamInterface<Input> {
        return BidirectionalStream(
            requestCallbacks: self.createRequestCallbacks(
                path: path, headers: headers, onResult: onResult
            ),
            codec: self.config.codec
        )
    }

    public func serverOnlyStream<
        Input: SwiftProtobuf.Message, Output: SwiftProtobuf.Message
    >(
        path: String,
        headers: Headers,
        onResult: @escaping (StreamResult<Output>) -> Void
    ) -> any ServerOnlyStreamInterface<Input> {
        return ServerOnlyStream(bidirectionalStream: BidirectionalStream(
            requestCallbacks: self.createRequestCallbacks(
                path: path, headers: headers, onResult: onResult
            ),
            codec: self.config.codec
        ))
    }

    // MARK: - Async/await

    public func unary<
        Input: SwiftProtobuf.Message, Output: SwiftProtobuf.Message
    >(
        path: String,
        method: String,
        request: Input,
        headers: Headers
    ) async -> ResponseMessage<Output> {
        return await UnaryAsyncWrapper { completion in
            self.unary(
                path: path, method: method, request: request,
                headers: headers, completion: completion
            )
        }.send()
    }

    public func bidirectionalStream<
        Input: SwiftProtobuf.Message, Output: SwiftProtobuf.Message
    >(
        path: String,
        headers: Headers
    ) -> any BidirectionalAsyncStreamInterface<Input, Output> {
        let bidirectionalAsync = BidirectionalAsyncStream<Input, Output>(codec: self.config.codec)
        let callbacks = self.createRequestCallbacks(
            path: path, headers: headers, onResult: bidirectionalAsync.receive
        )
        return bidirectionalAsync.configureForSending(with: callbacks)
    }

    public func clientOnlyStream<
        Input: SwiftProtobuf.Message, Output: SwiftProtobuf.Message
    >(
        path: String,
        headers: Headers
    ) -> any ClientOnlyAsyncStreamInterface<Input, Output> {
        let bidirectionalAsync = BidirectionalAsyncStream<Input, Output>(codec: self.config.codec)
        let callbacks = self.createRequestCallbacks(
            path: path, headers: headers, onResult: bidirectionalAsync.receive
        )
        return bidirectionalAsync.configureForSending(with: callbacks)
    }

    public func serverOnlyStream<
        Input: SwiftProtobuf.Message, Output: SwiftProtobuf.Message
    >(
        path: String,
        headers: Headers
    ) -> any ServerOnlyAsyncStreamInterface<Input, Output> {
        let bidirectionalAsync = BidirectionalAsyncStream<Input, Output>(codec: self.config.codec)
        let callbacks = self.createRequestCallbacks(
            path: path, headers: headers, onResult: bidirectionalAsync.receive
        )
        return ServerOnlyAsyncStream(
            bidirectionalStream: bidirectionalAsync.configureForSending(with: callbacks)
        )
    }

    // MARK: - Private

    private func createRequestCallbacks<Output: SwiftProtobuf.Message>(
        path: String,
        headers: Headers,
        onResult: @escaping (StreamResult<Output>) -> Void
    ) -> RequestCallbacks {
        let codec = self.config.codec
        let chain = self.config.createInterceptorChain().streamFunction()
        let url = URL(string: path, relativeTo: URL(string: self.config.host))!
        let request = chain.requestFunction(HTTPRequest(
            url: url,
            contentType: "application/connect+\(codec.name())",
            headers: headers,
            message: nil
        ))

        let interceptAndHandleResult: (StreamResult<Data>) -> Void = { streamResult in
            do {
                let interceptedResult = chain.streamResultFunc(streamResult)
                onResult(try interceptedResult.toTypedResult(using: codec))
            } catch let error {
                // TODO: Should we terminate the stream here?
                os_log(
                    .error,
                    "Failed to deserialize stream result - dropping result: %@",
                    error.localizedDescription
                )
            }
        }
        var responseBuffer = Data()
        let responseCallbacks = ResponseCallbacks(
            receiveResponseHeaders: { interceptAndHandleResult(.headers($0)) },
            receiveResponseData: { responseChunk in
                // Repeating handles cases where multiple messages are received in a single chunk.
                responseBuffer += responseChunk
                while true {
                    let messageLength = Envelope.messageLength(forPackedData: responseBuffer)
                    if messageLength < 0 {
                        return
                    }

                    let prefixedMessageLength = Envelope.prefixLength + messageLength
                    guard responseBuffer.count >= prefixedMessageLength else {
                        return
                    }

                    interceptAndHandleResult(.message(responseBuffer.prefix(prefixedMessageLength)))
                    responseBuffer = Data(responseBuffer.suffix(from: prefixedMessageLength))
                }
            },
            receiveClose: { code, error in
                if code != .ok || error != nil {
                    // Only pass the result through as completion if there is an error.
                    // Examples of this codepath would be the client disconnecting mid-stream
                    // or receiving a non-2xx response.
                    // The happy path is usually determined by "end stream" flags in the
                    // response body.
                    interceptAndHandleResult(.complete(
                        code: code,
                        error: error,
                        trailers: nil
                    ))
                }
            }
        )
        let httpRequestCallbacks = self.httpClient.stream(
            request: request,
            responseCallbacks: responseCallbacks
        )

        // Wrap the request data callback to invoke the interceptor chain.
        return RequestCallbacks(
            sendData: { httpRequestCallbacks.sendData(chain.requestDataFunction($0)) },
            sendClose: httpRequestCallbacks.sendClose
        )
    }
}

private extension StreamResult<Data> {
    func toTypedResult<Output: SwiftProtobuf.Message>(using codec: Codec)
        throws -> StreamResult<Output>
    {
        switch self {
        case .complete(let code, let error, let trailers):
            return .complete(code: code, error: error, trailers: trailers)
        case .headers(let headers):
            return .headers(headers)
        case .message(let data):
            return .message(try codec.deserialize(source: data))
        }
    }
}
