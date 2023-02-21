// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: annotations.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

// Copyright 2015 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

// MARK: - Extension support defined in annotations.proto.

// MARK: - Extension Properties

// Swift Extensions on the exteneded Messages to add easy access to the declared
// extension fields. The names are based on the extension field name from the proto
// declaration. To avoid naming collisions, the names are prefixed with the name of
// the scope where the extend directive occurs.

extension SwiftProtobuf.Google_Protobuf_MethodOptions {

  /// See `HttpRule`.
  var Google_Api_http: Google_Api_HttpRule {
    get {return getExtensionValue(ext: Google_Api_Extensions_http) ?? Google_Api_HttpRule()}
    set {setExtensionValue(ext: Google_Api_Extensions_http, value: newValue)}
  }
  /// Returns true if extension `Google_Api_Extensions_http`
  /// has been explicitly set.
  var hasGoogle_Api_http: Bool {
    return hasExtensionValue(ext: Google_Api_Extensions_http)
  }
  /// Clears the value of extension `Google_Api_Extensions_http`.
  /// Subsequent reads from it will return its default value.
  mutating func clearGoogle_Api_http() {
    clearExtensionValue(ext: Google_Api_Extensions_http)
  }

}

// MARK: - File's ExtensionMap: Google_Api_Annotations_Extensions

/// A `SwiftProtobuf.SimpleExtensionMap` that includes all of the extensions defined by
/// this .proto file. It can be used any place an `SwiftProtobuf.ExtensionMap` is needed
/// in parsing, or it can be combined with other `SwiftProtobuf.SimpleExtensionMap`s to create
/// a larger `SwiftProtobuf.SimpleExtensionMap`.
let Google_Api_Annotations_Extensions: SwiftProtobuf.SimpleExtensionMap = [
  Google_Api_Extensions_http
]

// Extension Objects - The only reason these might be needed is when manually
// constructing a `SimpleExtensionMap`, otherwise, use the above _Extension Properties_
// accessors for the extension fields on the messages directly.

/// See `HttpRule`.
let Google_Api_Extensions_http = SwiftProtobuf.MessageExtension<SwiftProtobuf.OptionalMessageExtensionField<Google_Api_HttpRule>, SwiftProtobuf.Google_Protobuf_MethodOptions>(
  _protobuf_fieldNumber: 72295728,
  fieldName: "google.api.http"
)
