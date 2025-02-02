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

/// Request/response headers.
/// All keys are expected to be lowercased.
/// Comma-separated values are split into individual items in the array. For example:
/// On the wire: `accept-encoding: gzip,brotli` or `accept-encoding: gzip, brotli`
/// Yields: `["accept-encoding": ["gzip", "brotli"]]`
public typealias Headers = [String: [String]]
