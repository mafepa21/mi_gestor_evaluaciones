import Foundation
import CoreGraphics

/// Generador pseudoaleatorio determinista (SplitMix64).
///
/// Sirve para el "desorden" de la biblioteca (grosor de los lomos, giro de los
/// cuadernos apilados, vetas de la madera): la misma semilla da siempre lo mismo,
/// entre redibujados y entre arranques. Por eso no se usa `hashValue`, que cambia
/// en cada ejecución.
struct StableRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Semilla derivada de un UUID (FNV-1a sobre sus 16 bytes).
    init(_ id: UUID, salt: UInt64 = 0) {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325 ^ salt
        var bytes = id.uuid
        withUnsafeBytes(of: &bytes) { raw in
            for byte in raw { h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        }
        state = h
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Valor en 0..<1.
    mutating func unit() -> CGFloat {
        CGFloat(Double(next() >> 11) / 9_007_199_254_740_992.0)
    }

    /// Valor en -1..<1.
    mutating func signed() -> CGFloat {
        unit() * 2 - 1
    }
}
