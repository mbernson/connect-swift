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
import ConnectNIO
import Foundation
import NIOSSL

/// HTTP client backed by NIO and used by crosstests in order to handle SSL challenges
/// with the crosstest server.
final class CrosstestNIOHTTPClient: ConnectNIO.NIOHTTPClient {
    init(host: String, port: Int, timeout: TimeInterval) {
        super.init(host: host, port: port, timeout: timeout)
    }

    override func createTLSConfiguration(forHost host: String) -> NIOSSL.TLSConfiguration {
        var configuration = super.createTLSConfiguration(forHost: host)
        configuration.certificateVerification = .none
        return configuration
    }
}
