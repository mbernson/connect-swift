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

import ConnectPluginGeneratedExtensions
import ConnectPluginUtilities
import Foundation
import SwiftProtobuf
import SwiftProtobufPluginLibrary

private struct VanguardError: Swift.Error {
    let message: String
}

/// Class used to resolve additional Vanguard annotations added to RPC methods.
final class VanguardResolver {
    private let descriptor: MethodDescriptor
    private let inputVariableName: String
    private let namer: SwiftProtobufNamer

    struct Output {
        let httpMethod: String
        let httpPath: String
    }

    init(descriptor: MethodDescriptor, namer: SwiftProtobufNamer, inputVariableName: String) {
        self.descriptor = descriptor
        self.inputVariableName = inputVariableName
        self.namer = namer
    }

    func methodInfo() throws -> Output {
        let extensions = self.descriptor.proto.options.getExtensionValue(ext: Buf_Vanguard_Extensions_http)
//        var options = try Buf_Vanguard_HttpOptions(
//            serializedData: self.descriptor.proto.options.unknownFields.data
//        )
//        options.unknownFields = .init()


        guard let method = extensions?.method else {
            return Output(
                httpMethod: "POST",
                httpPath: "\(self.descriptor.service.servicePath)/\(self.descriptor.name)"
            )
        }

        FileHandle.standardError.write(
            ("\(self.descriptor.name) - \(method)" + "\n").data(using: .utf8)!
        )

        if self.descriptor.clientStreaming || self.descriptor.serverStreaming {
            throw VanguardError(message: "Vanguard options may not be used with streaming RPCs.")
        }

        switch method {
        case .get(let path):
            return Output(
                httpMethod: "GET", httpPath: try self.resolvedVanguardPath(fromPath: path)
            )
        case .put(let path):
            return Output(
                httpMethod: "PUT", httpPath: try self.resolvedVanguardPath(fromPath: path)
            )
        case .post(let path):
            return Output(
                httpMethod: "POST", httpPath: try self.resolvedVanguardPath(fromPath: path)
            )
        case .delete(let path):
            return Output(
                httpMethod: "DELETE", httpPath: try self.resolvedVanguardPath(fromPath: path)
            )
        case .patch(let path):
            return Output(
                httpMethod: "PATCH", httpPath: try self.resolvedVanguardPath(fromPath: path)
            )
        case .customMethod(let customMethod):
            if customMethod.kind.isEmpty || customMethod.path.isEmpty {
                throw VanguardError(
                    message: "Vanguard custom methods must include a kind and path."
                )
            }

            return Output(
                httpMethod: customMethod.kind,
                httpPath: try self.resolvedVanguardPath(fromPath: customMethod.path)
            )
        }
    }

    private func resolvedVanguardPath(fromPath path: String) throws -> String {
        // TODO: Replace this with regex literals when we no longer want to support building
        // with < macOS 13.
        let regex = try NSRegularExpression(pattern: "\\{(.+)\\}")
        let pathRange = NSRange(path.startIndex..<path.endIndex, in: path)
        var finalPath = path
        for match in regex.matches(in: path, range: pathRange) {
            guard match.numberOfRanges == 2 else { // Match + capture group
                throw VanguardError(message: "Unable to resolve Vanguard path from '\(path)'.")
            }

            let pathFieldName = String(path[Range(match.range(at: 1), in: path)!])
            let swiftFieldName = try self.swiftFieldName(forFieldName: pathFieldName)
            finalPath = finalPath.replacingOccurrences(
                of: "{\(pathFieldName)}",
                with: "\\(\(self.inputVariableName).`\(swiftFieldName))`"
            )
        }
        return finalPath
    }

    private func swiftFieldName(forFieldName fieldName: String) throws -> String {
        guard let field = self.descriptor.inputType.fields.first(where: { field in
            return field.name == fieldName
        }) else {
            throw VanguardError(
                message: "Field '\(fieldName)' referenced in path does not exist in input message."
            )
        }

        if !Google_Protobuf_FieldDescriptorProto.TypeEnum.validPathFieldTypes.contains(field.type) {
            throw VanguardError(
                message: "The field type for path field '\(fieldName)' is of an unsupported type."
            )
        }

        return self.namer.messagePropertyNames(
            field: field, prefixed: "", includeHasAndClear: false
        ).name
    }
}

private extension Google_Protobuf_FieldDescriptorProto.TypeEnum {
    static let validPathFieldTypes: Set<Self> = [
        .double,
        .float,
        .int64,
        .uint64,
        .int32,
        .fixed64,
        .fixed32,
        .bool,
        .string,
        .uint32,
        .sfixed32,
        .sfixed64,
        .sint32,
        .sint64,
    ]
}
