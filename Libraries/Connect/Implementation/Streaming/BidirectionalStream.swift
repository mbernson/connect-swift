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

import SwiftProtobuf

/// Concrete implementation of `BidirectionalStreamInterface`.
final class BidirectionalStream<Message: SwiftProtobuf.Message> {
    private let requestCallbacks: RequestCallbacks
    private let codec: Codec

    init(requestCallbacks: RequestCallbacks, codec: Codec) {
        self.requestCallbacks = requestCallbacks
        self.codec = codec
    }
}

extension BidirectionalStream: BidirectionalStreamInterface {
    typealias Input = Message

    @discardableResult
    func send(_ input: Input) throws -> Self {
        self.requestCallbacks.sendData(try self.codec.serialize(message: input))
        return self
    }

    func close() {
        self.requestCallbacks.sendClose()
    }
}

// Conforms to the client-only interface since it matches exactly and the implementation is internal
extension BidirectionalStream: ClientOnlyStreamInterface {}
