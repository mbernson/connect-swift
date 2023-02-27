// swift-tools-version:5.6

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

import PackageDescription

let package = Package(
    name: "Connect",
    platforms: [
        .iOS(.v14),
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "Connect",
            targets: ["Connect"]
        ),
        .library(
            name: "ConnectMocks",
            targets: ["ConnectMocks"]
        ),
        .executable(
            name: "protoc-gen-connect-swift",
            targets: ["ConnectSwiftPlugin"]
        ),
        .executable(
            name: "protoc-gen-connect-swift-mocks",
            targets: ["ConnectMocksPlugin"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-protobuf.git",
            from: "1.20.3"
        ),
    ],
    targets: [
        .target(
            name: "Connect",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Libraries/Connect",
            exclude: [
                "buf.gen.yaml",
                "buf.work.yaml",
                "proto",
            ]
        ),
        .testTarget(
            name: "ConnectLibraryTests",
            dependencies: [
                "Connect",
                "ConnectMocks",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Tests/ConnectLibraryTests",
            exclude: [
                "buf.gen.yaml",
                "buf.work.yaml",
                "proto",
            ],
            resources: [
                .copy("Resources"),
            ]
        ),
        .target(
            name: "ConnectMocks",
            dependencies: [
                .target(name: "Connect"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Libraries/ConnectMocks",
            exclude: [
                "README.md",
            ]
        ),
        .executableTarget(
            name: "ConnectMocksPlugin",
            dependencies: [
                "ConnectPluginUtilities",
                .product(name: "SwiftProtobufPluginLibrary", package: "swift-protobuf"),
            ],
            path: "Plugins/ConnectMocksPlugin"
        ),
        .target(
            name: "ConnectPluginGeneratedExtensions",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Plugins/ConnectPluginGeneratedExtensions"
        ),
        .target(
            name: "ConnectPluginUtilities",
            dependencies: [
                .product(name: "SwiftProtobufPluginLibrary", package: "swift-protobuf"),
            ],
            path: "Plugins/ConnectPluginUtilities"
        ),
        .testTarget(
            name: "ConnectPluginUtilitiesTests",
            dependencies: [
                "ConnectPluginUtilities",
            ],
            path: "Tests/ConnectPluginUtilitiesTests"
        ),
        .executableTarget(
            name: "ConnectSwiftPlugin",
            dependencies: [
                "ConnectPluginGeneratedExtensions",
                "ConnectPluginUtilities",
                .product(name: "SwiftProtobufPluginLibrary", package: "swift-protobuf"),
            ],
            path: "Plugins/ConnectSwiftPlugin"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
