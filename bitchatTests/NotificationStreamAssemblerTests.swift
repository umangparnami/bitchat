import XCTest
@testable import bitchat

final class NotificationStreamAssemblerTests: XCTestCase {
    private func makePacket(timestamp: UInt64 = 0x0102030405) -> BitchatPacket {
        let sender = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77])
        return BitchatPacket(
            type: MessageType.message.rawValue,
            senderID: sender,
            recipientID: nil,
            timestamp: timestamp,
            payload: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            signature: nil,
            ttl: 3
        )
    }

    func testAssemblesSingleFrameAcrossChunks() {
        var assembler = NotificationStreamAssembler()
        let packet = makePacket()
        guard let frame = packet.toBinaryData(padding: false) else {
            return XCTFail("Failed to encode packet")
        }
        XCTAssertNotNil(BinaryProtocol.decode(frame))
        let payloadLen = (Int(frame[12]) << 8) | Int(frame[13])
        XCTAssertEqual(payloadLen, packet.payload.count)

        let splitIndex = min(20, max(1, frame.count / 2))
        let first = frame.prefix(splitIndex)
        let second = frame.suffix(from: splitIndex)
        XCTAssertEqual(first.count + second.count, frame.count)

        var result = assembler.append(first)
        XCTAssertTrue(result.frames.isEmpty)
        XCTAssertTrue(result.droppedPrefixes.isEmpty)
        XCTAssertFalse(result.reset)

        result = assembler.append(second)
        XCTAssertEqual(result.frames.count, 1)
        XCTAssertTrue(result.droppedPrefixes.isEmpty)
        XCTAssertFalse(result.reset)

        guard let frameData = result.frames.first else {
            return XCTFail("Missing frame data")
        }
        if frameData.count != frame.count {
            XCTFail("Frame size mismatch: expected \(frame.count) got \(frameData.count)\nframe=\(Array(frame))\nassembled=\(Array(frameData))")
            return
        }
        guard let decoded = BinaryProtocol.decode(frameData) else {
            return XCTFail("Failed to decode frame")
        }
        XCTAssertEqual(decoded.type, packet.type)
        XCTAssertEqual(decoded.payload, packet.payload)
        XCTAssertEqual(decoded.senderID, packet.senderID)
        XCTAssertEqual(decoded.timestamp, packet.timestamp)

        var directAssembler = NotificationStreamAssembler()
        let directResult = directAssembler.append(frame)
        XCTAssertEqual(directResult.frames.first?.count, frame.count)
    }

    func testAssemblesMultipleFramesSequentially() {
        var assembler = NotificationStreamAssembler()
        let packet1 = makePacket(timestamp: 0xABC)
        let packet2 = makePacket(timestamp: 0xDEF)

        guard let frame1 = packet1.toBinaryData(padding: false),
              let frame2 = packet2.toBinaryData(padding: false) else {
            return XCTFail("Failed to encode packets")
        }

        var combined = Data()
        combined.append(frame1)
        combined.append(frame2)
        let firstChunk = combined.prefix(20)
        let secondChunk = combined.suffix(from: 20)

        var result = assembler.append(firstChunk)
        XCTAssertTrue(result.frames.isEmpty)

        result = assembler.append(secondChunk)
        XCTAssertEqual(result.frames.count, 2)
        guard let decoded1 = BinaryProtocol.decode(result.frames[0]),
              let decoded2 = BinaryProtocol.decode(result.frames[1]) else {
            return XCTFail("Failed to decode frames")
        }
        XCTAssertEqual(decoded1.timestamp, packet1.timestamp)
        XCTAssertEqual(decoded2.timestamp, packet2.timestamp)
    }

    func testDropsInvalidPrefixByte() {
        var assembler = NotificationStreamAssembler()
        let packet = makePacket(timestamp: 0xF00)
        guard let frame = packet.toBinaryData(padding: false) else {
            return XCTFail("Failed to encode packet")
        }
        var noisyFrame = Data([0x00])
        noisyFrame.append(frame)

        let result = assembler.append(noisyFrame)
        XCTAssertEqual(result.droppedPrefixes, [0x00])
        XCTAssertEqual(result.frames.count, 1)
        XCTAssertFalse(result.reset)

        guard let decoded = BinaryProtocol.decode(result.frames[0]) else {
            return XCTFail("Failed to decode frame after drop")
        }
        XCTAssertEqual(decoded.timestamp, packet.timestamp)
    }
}
