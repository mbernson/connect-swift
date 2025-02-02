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

import Connect
import Foundation
import XCTest

private let kTimeout = TimeInterval(10.0)

private typealias TestServiceClient = Grpc_Testing_TestServiceClient
private typealias UnimplementedServiceClient = Grpc_Testing_UnimplementedServiceClient

/// This test suite runs against multiple protocols and serialization formats.
/// Tests are based on https://github.com/bufbuild/connect-crosstest
///
/// Tests are written using async/await APIs.
@available(iOS 13, *)
final class AsyncAwaitCrosstests: XCTestCase {
    private func executeTestWithClients(
        function: Selector = #function,
        timeout: TimeInterval = 60,
        runTestsWithClient: (TestServiceClient) async throws -> Void
    ) async rethrows {
        let configurations = CrosstestConfiguration.all(timeout: timeout)
        for configuration in configurations {
            try await runTestsWithClient(TestServiceClient(client: configuration.protocolClient))
            print("Ran \(function) with \(configuration.description)")
        }
    }

    private func executeTestWithUnimplementedClients(
        function: Selector = #function,
        runTestsWithClient: (UnimplementedServiceClient) async throws -> Void
    ) async rethrows {
        let configurations = CrosstestConfiguration.all(timeout: 60)
        for configuration in configurations {
            try await runTestsWithClient(
                UnimplementedServiceClient(client: configuration.protocolClient)
            )
            print("Ran \(function) with \(configuration.description)")
        }
    }

    // MARK: - Crosstest cases

    func testEmptyUnary() async {
        await self.executeTestWithClients { client in
            let response = await client.emptyCall(request: Grpc_Testing_Empty())
            XCTAssertEqual(response.message, Grpc_Testing_Empty())
        }
    }

    func testLargeUnary() async {
        await self.executeTestWithClients { client in
            let size = 314_159
            let message = Grpc_Testing_SimpleRequest.with { proto in
                proto.responseSize = Int32(size)
                proto.payload = .with { $0.body = Data(repeating: 0, count: size) }
            }
            let response = await client.unaryCall(request: message)
            XCTAssertNil(response.error)
            XCTAssertEqual(response.message?.payload.body.count, size)
        }
    }

    func testServerStreaming() async throws {
        try await self.executeTestWithClients { client in
            let sizes = [31_415, 9, 2_653, 58_979]
            let stream = client.streamingOutputCall()
            try stream.send(Grpc_Testing_StreamingOutputCallRequest.with { proto in
                proto.responseParameters = sizes.enumerated().map { index, size in
                    return .with { parameters in
                        parameters.size = Int32(size)
                        parameters.intervalUs = Int32(index * 10)
                    }
                }
            })

            let expectation = self.expectation(description: "Stream completes")
            var responseCount = 0
            for await result in stream.results() {
                switch result {
                case .headers:
                    continue

                case .message(let output):
                    XCTAssertEqual(output.payload.body.count, sizes[responseCount])
                    responseCount += 1

                case .complete(let code, let error, _):
                    XCTAssertEqual(code, .ok)
                    XCTAssertNil(error)
                    expectation.fulfill()
                }
            }

            XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: kTimeout), .completed)
            XCTAssertEqual(responseCount, 4)
        }
    }

    func testEmptyStream() async throws {
        try await self.executeTestWithClients { client in
            let closeExpectation = self.expectation(description: "Stream completes")
            let stream = client.streamingOutputCall()
            try stream.send(Grpc_Testing_StreamingOutputCallRequest.with { proto in
                proto.responseParameters = []
            })
            for await result in stream.results() {
                switch result {
                case .headers:
                    continue

                case .message:
                    XCTFail("Unexpectedly received message")

                case .complete(let code, let error, _):
                    XCTAssertEqual(code, .ok)
                    XCTAssertNil(error)
                    closeExpectation.fulfill()
                }
            }

            XCTAssertEqual(XCTWaiter().wait(for: [closeExpectation], timeout: kTimeout), .completed)
        }
    }

    func testCustomMetadata() async {
        await self.executeTestWithClients { client in
            let size = 314_159
            let leadingKey = "x-grpc-test-echo-initial"
            let leadingValue = "test_initial_metadata_value"
            let trailingKey = "x-grpc-test-echo-trailing-bin"
            let trailingValue = Data([0xab, 0xab, 0xab])
            let headers: Headers = [
                leadingKey: [leadingValue],
                trailingKey: [trailingValue.base64EncodedString()],
            ]
            let message = Grpc_Testing_SimpleRequest.with { proto in
                proto.responseSize = Int32(size)
                proto.payload = .with { $0.body = Data(repeating: 0, count: size) }
            }

            let response = await client.unaryCall(request: message, headers: headers)
            XCTAssertEqual(response.code, .ok)
            XCTAssertNil(response.error)
            XCTAssertEqual(response.headers[leadingKey], [leadingValue])
            XCTAssertEqual(
                response.trailers[trailingKey], [trailingValue.base64EncodedString()]
            )
            XCTAssertEqual(response.message?.payload.body.count, size)
        }
    }

    func testCustomMetadataServerStreaming() async throws {
        let size = 314_159
        let leadingKey = "x-grpc-test-echo-initial"
        let leadingValue = "test_initial_metadata_value"
        let trailingKey = "x-grpc-test-echo-trailing-bin"
        let trailingValue = Data([0xab, 0xab, 0xab])
        let headers: Headers = [
            leadingKey: [leadingValue],
            trailingKey: [trailingValue.base64EncodedString()],
        ]

        try await self.executeTestWithClients { client in
            let headersExpectation = self.expectation(description: "Receives headers")
            let messageExpectation = self.expectation(description: "Receives message")
            let trailersExpectation = self.expectation(description: "Receives trailers")
            let stream = client.streamingOutputCall(headers: headers)
            try stream.send(Grpc_Testing_StreamingOutputCallRequest.with { proto in
                proto.responseParameters = [.with { $0.size = Int32(size) }]
            })
            for await result in stream.results() {
                switch result {
                case .headers(let headers):
                    XCTAssertEqual(headers[leadingKey], [leadingValue])
                    headersExpectation.fulfill()

                case .message(let message):
                    XCTAssertEqual(message.payload.body.count, size)
                    messageExpectation.fulfill()

                case .complete(let code, let error, let trailers):
                    XCTAssertEqual(code, .ok)
                    XCTAssertEqual(trailers?[trailingKey], [trailingValue.base64EncodedString()])
                    XCTAssertNil(error)
                    trailersExpectation.fulfill()
                }
            }

            XCTAssertEqual(XCTWaiter().wait(for: [
                headersExpectation, messageExpectation, trailersExpectation,
            ], timeout: kTimeout, enforceOrder: true), .completed)
        }
    }

    func testStatusCodeAndMessage() async {
        let message = Grpc_Testing_SimpleRequest.with { proto in
            proto.responseStatus = .with { status in
                status.code = Int32(Code.unknown.rawValue)
                status.message = "test status message"
            }
        }

        await self.executeTestWithClients { client in
            let response = await client.unaryCall(request: message)
            XCTAssertEqual(response.error?.code, .unknown)
            XCTAssertEqual(response.error?.message, "test status message")
        }
    }

    func testSpecialStatus() async {
        let statusMessage =
        "\\t\\ntest with whitespace\\r\\nand Unicode BMP ☺ and non-BMP \\uD83D\\uDE08\\t\\n"
        let message = Grpc_Testing_SimpleRequest.with { proto in
            proto.responseStatus = .with { status in
                status.code = 2
                status.message = statusMessage
            }
        }

        await self.executeTestWithClients { client in
            let response = await client.unaryCall(request: message)
            XCTAssertEqual(response.error?.code, .unknown)
            XCTAssertEqual(response.error?.message, statusMessage)
        }
    }

    func testTimeoutOnSleepingServer() async throws {
        try await self.executeTestWithClients(timeout: 0.01) { client in
            let expectation = self.expectation(description: "Stream times out")
            let message = Grpc_Testing_StreamingOutputCallRequest.with { proto in
                proto.payload = .with { $0.body = Data(count: 271_828) }
                proto.responseParameters = [
                    .with { parameters in
                        parameters.size = 31_415
                        parameters.intervalUs = 50_000
                    },
                ]
            }
            let stream = client.streamingOutputCall()
            try stream.send(message)
            for await result in stream.results() {
                switch result {
                case .headers:
                    continue

                case .message:
                    continue

                case .complete(let code, let error, _):
                    XCTAssertEqual(code, .deadlineExceeded)
                    XCTAssertNotNil(error)
                    expectation.fulfill()
                }
            }

            XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: kTimeout), .completed)
        }
    }

    func testUnimplementedMethod() async {
        await self.executeTestWithClients { client in
            let response = await client.unimplementedCall(request: Grpc_Testing_Empty())
            XCTAssertEqual(response.code, .unimplemented)
            XCTAssertEqual(
                response.error?.message,
                "grpc.testing.TestService.UnimplementedCall is not implemented"
            )
        }
    }

    func testUnimplementedServerStreamingMethod() async throws {
        try await self.executeTestWithClients { client in
            let expectation = self.expectation(description: "Stream completes")
            let stream = client.unimplementedStreamingOutputCall()
            try stream.send(Grpc_Testing_Empty())
            for await result in stream.results() {
                switch result {
                case .headers, .message:
                    continue

                case .complete(let code, let error, _):
                    XCTAssertEqual(code, .unimplemented)
                    XCTAssertEqual(
                        (error as? ConnectError)?.message,
                        """
                        grpc.testing.TestService.UnimplementedStreamingOutputCall is not implemented
                        """
                    )
                    expectation.fulfill()
                }
            }

            XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: kTimeout), .completed)
        }
    }

    func testUnimplementedService() async {
        await self.executeTestWithUnimplementedClients { client in
            let response = await client.unimplementedCall(request: Grpc_Testing_Empty())
            XCTAssertEqual(response.code, .unimplemented)
            XCTAssertNotNil(response.error)
        }
    }

    func testUnimplementedServerStreamingService() async throws {
        try await self.executeTestWithUnimplementedClients { client in
            let expectation = self.expectation(description: "Stream completes")
            let stream = client.unimplementedStreamingOutputCall()
            try stream.send(Grpc_Testing_Empty())
            for await result in stream.results() {
                switch result {
                case .headers:
                    continue

                case .message:
                    XCTFail("Unexpectedly received message")

                case .complete(let code, _, _):
                    XCTAssertEqual(code, .unimplemented)
                    expectation.fulfill()
                }
            }

            XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: kTimeout), .completed)
        }
    }

    func testFailUnary() async {
        await self.executeTestWithClients { client in
            let expectedErrorDetail = Grpc_Testing_ErrorDetail.with { proto in
                proto.reason = "soirée 🎉"
                proto.domain = "connect-crosstest"
            }
            let response = await client.failUnaryCall(request: Grpc_Testing_SimpleRequest())
            XCTAssertEqual(response.error?.code, .resourceExhausted)
            XCTAssertEqual(response.error?.message, "soirée 🎉")
            XCTAssertEqual(response.error?.unpackedDetails(), [expectedErrorDetail])
        }
    }

    func testFailServerStreaming() async throws {
        try await self.executeTestWithClients { client in
            let expectedErrorDetail = Grpc_Testing_ErrorDetail.with { proto in
                proto.reason = "soirée 🎉"
                proto.domain = "connect-crosstest"
            }
            let expectation = self.expectation(description: "Stream completes")
            let stream = client.failStreamingOutputCall()
            try stream.send(Grpc_Testing_StreamingOutputCallRequest.with { proto in
                proto.responseParameters = [31_415, 9, 2_653, 58_979]
                    .enumerated()
                    .map { index, value in
                        return Grpc_Testing_ResponseParameters.with { parameters in
                            parameters.size = Int32(value)
                            parameters.intervalUs = Int32(index * 10)
                        }
                    }
            })
            for await result in stream.results() {
                switch result {
                case .headers:
                    continue

                case .message:
                    XCTFail("Unexpectedly received message")

                case .complete(_, let error, _):
                    guard let connectError = error as? ConnectError else {
                        XCTFail("Expected ConnectError")
                        return
                    }

                    XCTAssertEqual(connectError.code, .resourceExhausted)
                    XCTAssertEqual(connectError.message, "soirée 🎉")
                    XCTAssertEqual(connectError.unpackedDetails(), [expectedErrorDetail])
                    expectation.fulfill()
                }
            }

            XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: kTimeout), .completed)
        }
    }
}
