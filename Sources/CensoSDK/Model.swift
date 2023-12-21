import Foundation

struct GetImportDataApiResponse: Codable {
    var importState: ImportState
}

struct ExportedPhrase : Codable {
    var binaryPhrase: String
    var language: Int
    var label: String
}

struct EncryptedPhrase : Codable {
    var encryptedData: Base64EncodedString
}

enum ImportState: Codable {
    case initial
    case accepted(Accepted)
    case completed(Completed)

    struct Accepted: Codable {
        var ownerDeviceKey: Base58EncodedPublicKey
        var ownerProof: Base64EncodedString
        var acceptedAt: Date
    }

    struct Completed: Codable {
        var encryptedData: Base64EncodedString
    }
    
    enum ImportStateCodingKeys: String, CodingKey {
        case type
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ImportStateCodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "Initial":
            self = .initial
        case "Accepted":
            self = .accepted(try Accepted(from: decoder))
        case "Completed":
            self = .completed(try Completed(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Import State")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ImportStateCodingKeys.self)
        switch self {
        case .initial:
            try container.encode("Initial", forKey: .type)
        case .accepted(let accepted):
            try container.encode("Accepted", forKey: .type)
            try accepted.encode(to: encoder)
        case .completed(let completed):
            try container.encode("Completed", forKey: .type)
            try completed.encode(to: encoder)
        }
    }
}

public enum WordListLanguage: CaseIterable {
    case english
    case spanish
    case french
    case italian
    case portugese
    case czech
    case japanese
    case korean
    case chineseTraditional
    case chineseSimplified
}

extension WordListLanguage {
    func toId() -> UInt8 {
        switch (self) {
        case .english:
            return 1
        case .spanish:
            return 2
        case .french:
            return 3
        case .italian:
            return 4
        case .portugese:
            return 5
        case .czech:
            return 6
        case .japanese:
            return 7
        case .korean:
            return 8
        case .chineseTraditional:
            return 9
        case .chineseSimplified:
            return 10
        }
    }
    
    static func fromId(id: UInt8) -> WordListLanguage {
        switch (id) {
        case 1:
            return .english
        case 2:
            return spanish
        case 3:
            return .french
        case 4:
            return .italian
        case 5:
            return .portugese
        case 6:
            return .czech
        case 7:
            return .japanese
        case 8:
            return .korean
        case 9:
            return .chineseTraditional
        case 10:
            return .chineseSimplified
        default:
            return .english
        }
    }
}
