import Foundation

guard CommandLine.arguments.count >= 4, CommandLine.arguments.count.isMultiple(of: 2) else {
    fputs("Usage: pack_icns.swift OUTPUT.icns TYPE PNG [TYPE PNG ...]\n", stderr)
    exit(2)
}

func bigEndianBytes(_ value: UInt32) -> Data {
    var bigEndian = value.bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}

var chunks = Data()
var index = 2
while index < CommandLine.arguments.count {
    let type = CommandLine.arguments[index]
    let path = CommandLine.arguments[index + 1]
    guard type.utf8.count == 4 else {
        fputs("ICNS chunk type must contain four ASCII characters\n", stderr)
        exit(2)
    }
    let imageData = try Data(contentsOf: URL(fileURLWithPath: path))
    chunks.append(contentsOf: type.utf8)
    chunks.append(bigEndianBytes(UInt32(imageData.count + 8)))
    chunks.append(imageData)
    index += 2
}

var result = Data("icns".utf8)
result.append(bigEndianBytes(UInt32(chunks.count + 8)))
result.append(chunks)
try result.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
