// SPDX-License-Identifier: MIT
// Copyright 2021 Stephen Larew

import ArgumentParser
import Compression
import Foundation

enum Err: String, Error, CustomStringConvertible {
  case tty = "Refusing to write to TTY."
  case compression = "Compression framework error."
  var description: String { self.rawValue }
}

enum Operation: EnumerableFlag {
  case encode, decode

  static func name(for value: Operation) -> NameSpecification {
    switch value {
    case .encode:
      return [.customShort("e"), .customLong("encode")]
    case .decode:
      return [.customShort("d"), .customLong("decode")]
    }
  }

  func run(out outFileHandle: FileHandle, in inFileHandle: FileHandle) throws {

    let bufferSize = 1 << 20

    let dstPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer {
      dstPtr.deallocate()
    }

    var stream = compression_stream(
      dst_ptr: dstPtr, dst_size: 0, src_ptr: dstPtr, src_size: 0, state: nil)
    var status = compression_stream_init(
      &stream, self == .encode ? COMPRESSION_STREAM_ENCODE : COMPRESSION_STREAM_DECODE,
      COMPRESSION_LZFSE)
    guard status == COMPRESSION_STATUS_OK else {
      throw Err.compression
    }
    defer {
      compression_stream_destroy(&stream)
    }

    stream.src_size = 0
    stream.dst_ptr = dstPtr
    stream.dst_size = bufferSize

    var srcData: Data?

    repeat {
      var flags = Int32(0)

      if stream.src_size == 0 {
        srcData = inFileHandle.readData(ofLength: bufferSize)

        stream.src_size = srcData!.count
        if srcData!.count < bufferSize {
          flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
        }
      }

      if let srcData = srcData {
        let count = srcData.count

        srcData.withUnsafeBytes {
          stream.src_ptr = $0.bindMemory(to: UInt8.self).baseAddress!
            .advanced(by: count - stream.src_size)
          status = compression_stream_process(&stream, flags)
        }
      }

      switch status {
      case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
        outFileHandle.write(
          Data(
            bytesNoCopy: dstPtr,
            count: bufferSize - stream.dst_size,
            deallocator: .none))
        stream.dst_ptr = dstPtr
        stream.dst_size = bufferSize

      case COMPRESSION_STATUS_ERROR:
        throw Err.compression

      default:
        fatalError("Unhandled Compression status code \(status)")
      }
    } while status == COMPRESSION_STATUS_OK
  }
}

struct lzfse: ParsableCommand {
  static var configuration = CommandConfiguration(
    abstract: "Encode or decode Apple LZFSE compression format.")

  @Flag(help: .hidden)
  var printLicense = false

  @Flag(help: "Operation to perform on input.")
  var operation = Operation.encode

  @Option(
    name: [.short, .customLong("input")],
    help: ArgumentHelp(
      "Path of input file.", discussion: "Reads from standard input if not provided.",
      valueName: "path"))
  var inputPath: String?

  @Option(
    name: [.short, .customLong("output")],
    help: ArgumentHelp(
      "Path of output file.", discussion: "Writes to standard output if not provided.",
      valueName: "path"))
  var outputPath: String?

  func run() throws {
    if printLicense {
      print(license)
      return
    }

    let inFileHandle: FileHandle
    let outFileHandle: FileHandle

    if let inputPath = inputPath {
      inFileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: inputPath))
    } else {
      inFileHandle = FileHandle.standardInput
    }
    defer {
      inFileHandle.closeFile()
    }

    if let outputPath = outputPath {
      outFileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: outputPath))
    } else {
      outFileHandle = FileHandle.standardOutput
    }
    defer {
      outFileHandle.closeFile()
    }

    guard isatty(outFileHandle.fileDescriptor) == 0 else {
      throw Err.tty
    }

    try self.operation.run(out: outFileHandle, in: inFileHandle)
  }
}

let license = """
  MIT License

  Copyright (c) 2021 Stephen Larew

  Permission is hereby granted, free of charge, to any person obtaining a copy \
  of this software and associated documentation files (the "Software"), to deal \
  in the Software without restriction, including without limitation the rights \
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
  copies of the Software, and to permit persons to whom the Software is \
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all \
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
  SOFTWARE.
  """

lzfse.main()
