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

import Combine
import Connect
import Dispatch
import os.log

private typealias ConverseRequest = Buf_Connect_Demo_Eliza_V1_ConverseRequest
private typealias ConverseResponse = Buf_Connect_Demo_Eliza_V1_ConverseResponse

private typealias SayRequest = Buf_Connect_Demo_Eliza_V1_SayRequest
private typealias SayResponse = Buf_Connect_Demo_Eliza_V1_SayResponse

/// View model that can be injected into a `MessagingView`.
protocol MessagingViewModel: ObservableObject {
    /// The current set of messages. Observable by storing the view model as an `@ObservedObject`.
    @MainActor var messages: [Message] { get }

    /// Send a message to the upstream service.
    /// This message and any responses will be appended to `messages`.
    ///
    /// - parameter message: The message to send.
    func send(_ message: String) async

    /// End the chat session (and close connections if needed).
    func endChat() async
}

/// View model that uses unary requests for messaging.
@MainActor
final class UnaryMessagingViewModel: MessagingViewModel {
    private let client: Buf_Connect_Demo_Eliza_V1_ElizaServiceClientInterface

    @Published private(set) var messages = [Message]()

    init(client: Buf_Connect_Demo_Eliza_V1_ElizaServiceClientInterface) {
        self.client = client
    }

    func send(_ sentence: String) async {
        let request = SayRequest.with { $0.sentence = sentence }
        self.addMessage(Message(message: sentence, author: .user))

        let response = await self.client.say(request: request, headers: [:])
        os_log(.debug, "Eliza unary response: %@", String(describing: response))
        self.addMessage(Message(
            message: response.message?.sentence ?? "No response", author: .eliza
        ))
     }

    func endChat() async {}

    private func addMessage(_ message: Message) {
        self.messages.append(message)
    }
}

/// View model that uses bidirectional streaming for messaging.
@MainActor
final class BidirectionalStreamingMessagingViewModel: MessagingViewModel {
    private let client: Buf_Connect_Demo_Eliza_V1_ElizaServiceClientInterface
    private lazy var elizaStream = self.client.converse(headers: [:])

    @Published private(set) var messages = [Message]()

    init(client: Buf_Connect_Demo_Eliza_V1_ElizaServiceClientInterface) {
        self.client = client
        self.observeResponses()
    }

    func send(_ sentence: String) async {
        do {
            let request = ConverseRequest.with { $0.sentence = sentence }
            self.addMessage(Message(message: sentence, author: .user))
            try self.elizaStream.send(request)
        } catch let error {
            os_log(
                .error, "Failed to write message to stream: %@", error.localizedDescription
            )
        }
    }

    func endChat() {
        self.elizaStream.close()
    }

    private func observeResponses() {
        Task {
            for await result in self.elizaStream.results() {
                switch result {
                case .headers(let headers):
                    os_log(.debug, "Eliza headers: %@", headers)

                case .message(let message):
                    os_log(.debug, "Eliza message: %@", String(describing: message))
                    self.addMessage(Message(message: message.sentence, author: .eliza))

                case .complete(_, let error, let trailers):
                    os_log(.debug, "Eliza completed with trailers: %@", trailers ?? [:])
                    let sentence: String
                    if let error = error {
                        os_log(.error, "Eliza error: %@", error.localizedDescription)
                        sentence = "[Error: \(error)]"
                    } else {
                        sentence = "[Conversation ended]"
                    }
                    self.addMessage(Message(message: sentence, author: .eliza))
                }
            }
        }
    }

    private func addMessage(_ message: Message) {
        self.messages.append(message)
        print(self.messages)
    }
}
