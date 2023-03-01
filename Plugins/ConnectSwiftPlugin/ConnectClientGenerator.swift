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

import ConnectPluginUtilities
import Foundation
import SwiftProtobufPluginLibrary

/// Responsible for generating services and RPCs that are compatible with the Connect library.
final class ConnectClientGenerator: Generator {
    private let visibility: String

    required init(_ descriptor: FileDescriptor, options: GeneratorOptions) throws {
        switch options.visibility {
        case .internal:
            self.visibility = "internal"
        case .public:
            self.visibility = "public"
        }
        try super.init(descriptor, options: options)
        try self.printContent()
    }

    private func printContent() throws {
        self.printFilePreamble()

        self.printModuleImports()

        for service in self.descriptor.services {
            self.printLine()
            try self.printService(service)
        }
    }

    private func printService(_ service: ServiceDescriptor) throws {
        self.printCommentsIfNeeded(for: service)

        let protocolName = service.protocolName(using: self.namer)
        self.printLine("\(self.visibility) protocol \(protocolName) {")
        self.indent {
            for method in service.methods {
                if self.options.generateCallbackMethods {
                    self.printCallbackMethodInterface(for: method)
                }
                if self.options.generateAsyncMethods {
                    self.printAsyncAwaitMethodInterface(for: method)
                }
            }
        }
        self.printLine("}")

        self.printLine()

        let className = service.implementationName(using: self.namer)
        self.printLine("/// Concrete implementation of `\(protocolName)`.")
        self.printLine("\(self.visibility) final class \(className): \(protocolName) {")
        try self.indent {
            self.printLine("private let client: Connect.ProtocolClientInterface")
            self.printLine()
            self.printLine("\(self.visibility) init(client: Connect.ProtocolClientInterface) {")
            self.indent {
                self.printLine("self.client = client")
            }
            self.printLine("}")

            for method in service.methods {
                let vanguardResolver = VanguardResolver(
                    descriptor: method, namer: self.namer, inputVariableName: "request"
                )
                if self.options.generateCallbackMethods {
                    try self.printCallbackMethodImplementation(
                        for: method, vanguardResolver: vanguardResolver
                    )
                }
                if self.options.generateAsyncMethods {
                    try self.printAsyncAwaitMethodImplementation(
                        for: method, vanguardResolver: vanguardResolver
                    )
                }
            }

            if self.options.generateServiceMetadata {
                self.printSpecs(for: service)
            }
        }
        self.printLine("}")
    }

    private func printSpecs(for service: ServiceDescriptor) {
        self.printLine()
        self.printLine("\(self.visibility) enum Metadata {")
        self.indent {
            self.printLine("\(self.visibility) enum Methods {")
            self.indent {
                for method in service.methods {
                    self.printLine(
                        """
                        \(self.visibility) static let \(method.name(using: self.options)) = \
                        Connect.MethodSpec(\
                        name: "\(method.name)", \
                        service: "\(method.service.servicePath)", \
                        type: \(method.specStreamType())\
                        )
                        """
                    )
                }
            }
            self.printLine("}")
        }
        self.printLine("}")
    }

    private func printCallbackMethodInterface(for method: MethodDescriptor) {
        self.printLine()
        self.printCommentsIfNeeded(for: method)
        if !method.serverStreaming && !method.clientStreaming {
            self.printLine("@discardableResult")
        }

        self.printLine(
            method.callbackSignature(
                using: self.namer, includeDefaults: false, options: self.options
            )
        )
    }

    private func printAsyncAwaitMethodInterface(for method: MethodDescriptor) {
        self.printLine()
        self.printCommentsIfNeeded(for: method)
        self.printLine(
            method.asyncAwaitSignature(
                using: self.namer, includeDefaults: false, options: self.options
            )
        )
    }

    private func printCallbackMethodImplementation(
        for method: MethodDescriptor, vanguardResolver: VanguardResolver
    ) throws {
        self.printLine()
        if !method.serverStreaming && !method.clientStreaming {
            self.printLine("@discardableResult")
        }

        self.printLine(
            "\(self.visibility) "
            + method.callbackSignature(
                using: self.namer, includeDefaults: true, options: self.options
            )
            + " {"
        )
        try self.indent {
            try self.printLine("return \(method.callbackReturnValue(using: vanguardResolver))")
        }
        self.printLine("}")
    }

    private func printAsyncAwaitMethodImplementation(
        for method: MethodDescriptor, vanguardResolver: VanguardResolver
    ) throws {
        self.printLine()
        self.printLine(
            "\(self.visibility) "
            + method.asyncAwaitSignature(
                using: self.namer, includeDefaults: true, options: self.options
            )
            + " {"
        )
        try self.indent {
            try self.printLine("return \(method.asyncAwaitReturnValue(using: vanguardResolver))")
        }
        self.printLine("}")
    }
}

private extension MethodDescriptor {
     func specStreamType() -> String {
        if self.clientStreaming && self.serverStreaming {
            return ".bidirectionalStream"
        } else if self.serverStreaming {
            return ".serverStream"
        } else if self.clientStreaming {
            return ".clientStream"
        } else {
            return ".unary"
        }
    }

    func callbackReturnValue(using vanguardResolver: VanguardResolver) throws -> String {
        let methodInfo = try vanguardResolver.methodInfo()
        if self.clientStreaming && self.serverStreaming {
            return """
            self.client.bidirectionalStream(\
            path: "\(methodInfo.httpPath)", headers: headers, onResult: onResult)
            """
        } else if self.serverStreaming {
            return """
            self.client.serverOnlyStream(\
            path: "\(methodInfo.httpPath)", headers: headers, onResult: onResult)
            """
        } else if self.clientStreaming {
            return """
            self.client.clientOnlyStream(\
            path: "\(methodInfo.httpPath)", headers: headers, onResult: onResult)
            """
        } else {
            return """
            self.client.unary(\
            path: "\(methodInfo.httpPath)", request: request, \
            method: "\(methodInfo.httpMethod)", headers: headers, completion: completion)
            """
        }
    }

    func asyncAwaitReturnValue(using vanguardResolver: VanguardResolver) throws -> String {
        let methodInfo = try vanguardResolver.methodInfo()
        if self.clientStreaming && self.serverStreaming {
            return """
            self.client.bidirectionalStream(path: "\(methodInfo.httpPath)", headers: headers)
            """
        } else if self.serverStreaming {
            return """
            self.client.serverOnlyStream(path: "\(methodInfo.httpPath)", headers: headers)
            """
        } else if self.clientStreaming {
            return """
            self.client.clientOnlyStream(path: "\(methodInfo.httpPath)", headers: headers)
            """
        } else {
            return """
            await self.client.unary(\
            path: "\(methodInfo.httpPath)", request: request, \
            method: "\(methodInfo.httpMethod)", headers: headers)
            """
        }
    }
}
