// Copyright (c) 2021 Spotify AB.
//
// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import Foundation

enum ShellError: Error {
    case statusError(String, Int32)
}

extension ShellError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .statusError(let string, _): return string
        }
    }
}

protocol PipeLike {}
extension FileHandle: PipeLike {}
extension Pipe: PipeLike {}

typealias ShellOutFunction = (String, [String], String?, [String: String]?) throws -> String
typealias ShellCallFunction = (String, [String], String?, [String: String]?) throws -> Void

func shellExec(_ cmd: String, args: [String] = [], inDir dir: String? = nil, environment: [String: String]? = nil) throws {
    try shellInternal(cmd, args: args, stdout: nil, stderr: nil, inDir: dir, environment: environment)
}

func shellCall(_ cmd: String, args: [String] = [], inDir dir: String? = nil, environment: [String: String]? = nil) throws {
    try shellInternal(
        cmd,
        args: args,
        stdout: FileHandle.standardOutput,
        stderr: FileHandle.standardError,
        inDir: dir,
        environment: environment
    )
}

func shellGetStdout(_ cmd: String, args: [String] = [], inDir dir: String? = nil, environment: [String: String]? = nil) throws -> String {
    let pipe = Pipe()
    try shellInternal(cmd, args: args, stdout: pipe, stderr: nil, inDir: dir, environment: environment)

    let handle = pipe.fileHandleForReading
    let data = handle.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trim() ?? ""
}

private func which(_ cmd: String) throws -> String {
    return try shellGetStdout("/usr/bin/which", args: [cmd])
}

func shellInternal(_ cmd: String, args: [String] = [], stdout: PipeLike?, stderr: PipeLike?, inDir dir: String? = nil, environment: [String: String]? = nil) throws {
    let absCmd = try cmd.starts(with: "/") ? cmd : which(cmd)

    let errorHandle = Pipe()
    let task = Process()
    if let env = environment {
        task.environment = env
    }

    task.launchPath = absCmd
    task.arguments = args
    task.standardOutput = stdout ?? FileHandle.nullDevice
    task.standardError = stderr ?? errorHandle
    if let dir = dir {
        task.currentDirectoryPath = dir
    }
    task.launch()
    let errorData = (stderr == nil) ? nil : errorHandle.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    if task.terminationStatus != 0 {
        guard let errorData = errorData else {
            // Error stream was captured so cannot inspect its content
            throw ShellError.statusError("Failed command", task.terminationStatus)
        }
        let errorString = String(data: errorData, encoding: .utf8)?.trim() ?? "No error returned from the process."
        throw ShellError.statusError(
            "status \(task.terminationStatus): \(errorString)", task.terminationStatus
        )
    }
}

public extension String {
    func trim() -> String {
        func trim(_ separator: String) -> String {
            var E = endIndex
            while String(self[startIndex..<E]).hasSuffix(separator) && E > startIndex {
                E = index(before: E)
            }
            return String(self[startIndex..<E])
        }

        if hasSuffix("\r\n") {
            return trim("\r\n")
        } else if hasSuffix("\n") {
            return trim("\n")
        } else {
            return self
        }
    }
}
