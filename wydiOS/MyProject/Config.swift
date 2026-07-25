import Foundation

enum WYDConfig {
    static let baseURL = URL(string: "https://lingcode.dev/api/cloud/be/efedfcd10298b46dad70e2df")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoidHJvbGVfZWZlZGZjZDEwMjk4YjQ2ZGFkNzBlMmRmIiwiaWF0IjoxNzg0OTIzNTcyfQ.P1g2GEeDynKVT0E7361vEFMjK8_gxuADMvfD3RL77zM"

    /// Fallback reference point (FIL Pavilion, Lisbon) when location is unavailable.
    static let conferenceLat = 38.7689
    static let conferenceLng = -9.0939
}
