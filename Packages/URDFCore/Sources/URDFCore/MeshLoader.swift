import Foundation
import simd

public struct MeshLoader: MeshLoading, Sendable {
    public init() {}

    public func load(url: URL) throws -> MeshBuffer {
        let ext = url.pathExtension.lowercased()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MeshLoadError.decodeFailed("파일을 읽을 수 없습니다: \(url.lastPathComponent)")
        }

        switch ext {
        case "stl":
            return try loadSTL(data: data, name: url.lastPathComponent)
        case "obj":
            return try loadOBJ(data: data, name: url.lastPathComponent)
        case "dae":
            throw MeshLoadError.unsupported
        default:
            throw MeshLoadError.unsupported
        }
    }

    // MARK: STL

    private func loadSTL(data: Data, name: String) throws -> MeshBuffer {
        if isASCIISTL(data) {
            return try loadASCIISTL(data: data, name: name)
        }
        return try loadBinarySTL(data: data, name: name)
    }

    private func isASCIISTL(_ data: Data) -> Bool {
        // Binary STL has 80-byte header + UInt32 triangle count.
        // ASCII typically starts with "solid" and contains "facet".
        guard data.count >= 5 else { return false }
        if data.count < 84 { return true }
        let prefix = String(data: data.prefix(80), encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if prefix.hasPrefix("solid"),
           String(data: data, encoding: .ascii)?.lowercased().contains("facet") == true {
            return true
        }
        return false
    }

    private func loadASCIISTL(data: Data, name: String) throws -> MeshBuffer {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii) else {
            throw MeshLoadError.decodeFailed("ASCII STL 디코딩 실패: \(name)")
        }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var currentNormal = SIMD3<Float>(0, 0, 1)
        var faceVerts: [SIMD3<Float>] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if line.hasPrefix("facet normal") {
                let parts = line.split(separator: " ")
                if parts.count >= 5,
                   let x = Float(parts[2]), let y = Float(parts[3]), let z = Float(parts[4]) {
                    currentNormal = SIMD3(x, y, z)
                }
                faceVerts = []
            } else if line.hasPrefix("vertex") {
                let parts = line.split(separator: " ")
                if parts.count >= 4,
                   let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) {
                    faceVerts.append(SIMD3(x, y, z))
                }
            } else if line.hasPrefix("endfacet") {
                guard faceVerts.count >= 3 else { continue }
                // fan triangulation if more than 3 (rare in STL)
                for i in 1..<(faceVerts.count - 1) {
                    let base = UInt32(positions.count)
                    positions.append(faceVerts[0])
                    positions.append(faceVerts[i])
                    positions.append(faceVerts[i + 1])
                    normals.append(contentsOf: [currentNormal, currentNormal, currentNormal])
                    indices.append(contentsOf: [base, base + 1, base + 2])
                }
                faceVerts = []
            }
        }

        guard !positions.isEmpty else {
            throw MeshLoadError.decodeFailed("ASCII STL에 삼각형이 없습니다: \(name)")
        }
        return MeshBuffer(positions: positions, normals: normals, indices: indices)
    }

    private func loadBinarySTL(data: Data, name: String) throws -> MeshBuffer {
        // header(80) + uint32 count + 50 bytes per triangle
        guard data.count >= 84 else {
            throw MeshLoadError.decodeFailed("binary STL이 너무 짧습니다: \(name)")
        }
        let count: UInt32 = data.subdata(in: 80..<84).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let expected = 84 + Int(count) * 50
        guard data.count >= expected else {
            throw MeshLoadError.decodeFailed("binary STL 크기 불일치: \(name)")
        }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(Int(count) * 3)
        normals.reserveCapacity(Int(count) * 3)
        indices.reserveCapacity(Int(count) * 3)

        var offset = 84
        for _ in 0..<count {
            let n = readFloat3(data, offset)
            offset += 12
            let v0 = readFloat3(data, offset); offset += 12
            let v1 = readFloat3(data, offset); offset += 12
            let v2 = readFloat3(data, offset); offset += 12
            offset += 2 // attribute byte count

            let base = UInt32(positions.count)
            positions.append(contentsOf: [v0, v1, v2])
            normals.append(contentsOf: [n, n, n])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }

        guard !positions.isEmpty else {
            throw MeshLoadError.decodeFailed("binary STL에 삼각형이 없습니다: \(name)")
        }
        return MeshBuffer(positions: positions, normals: normals, indices: indices)
    }

    private func readFloat3(_ data: Data, _ offset: Int) -> SIMD3<Float> {
        func f32(_ o: Int) -> Float {
            var bit: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &bit) { dest in
                data.copyBytes(to: dest, from: o..<(o + 4))
            }
            bit = UInt32(littleEndian: bit)
            return Float(bitPattern: bit)
        }
        return SIMD3(f32(offset), f32(offset + 4), f32(offset + 8))
    }

    // MARK: OBJ (v / f only)

    private func loadOBJ(data: Data, name: String) throws -> MeshBuffer {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii) else {
            throw MeshLoadError.decodeFailed("OBJ 디코딩 실패: \(name)")
        }

        var verts: [SIMD3<Float>] = []
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard let head = parts.first else { continue }
            if head == "v", parts.count >= 4,
               let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) {
                verts.append(SIMD3(x, y, z))
            } else if head == "f", parts.count >= 4 {
                var faceIdx: [Int] = []
                for i in 1..<parts.count {
                    let token = parts[i].split(separator: "/")[0]
                    guard let idx = Int(token) else { continue }
                    // OBJ indices are 1-based; negative relative
                    let resolved = idx > 0 ? idx - 1 : verts.count + idx
                    faceIdx.append(resolved)
                }
                guard faceIdx.count >= 3 else { continue }
                for i in 1..<(faceIdx.count - 1) {
                    let tri = [faceIdx[0], faceIdx[i], faceIdx[i + 1]]
                    let base = UInt32(positions.count)
                    for vi in tri {
                        guard vi >= 0 && vi < verts.count else {
                            throw MeshLoadError.decodeFailed("OBJ 인덱스 범위 초과: \(name)")
                        }
                        positions.append(verts[vi])
                    }
                    indices.append(contentsOf: [base, base + 1, base + 2])
                }
            }
        }

        guard !positions.isEmpty else {
            throw MeshLoadError.decodeFailed("OBJ에 면이 없습니다: \(name)")
        }
        return MeshBuffer(positions: positions, normals: nil, indices: indices)
    }
}
