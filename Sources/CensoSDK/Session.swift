import Foundation
import CryptoKit

public class Session {
    var name: String
    private var apiUrl: String
    private var apiVersion: String
    private var linkScheme: String
    private var linkVersion: String
    private var channelKey: EncryptionKey
    private var authKey: EncryptionKey
    private var createdAt: Date
    private var onFinished: (Bool) -> Void
    private var checkConnectionTimer: Timer? = nil
    private var dispatchQueue: DispatchQueue
    private var onConnected: (() -> Void)? = nil
    var finished: Bool = false
    private var ownerDeviceKey: EncryptionKey? = nil
    private var urlSession: URLSession

    var channelPublicKey: Base58EncodedPublicKey {
        get {
            do {
                return try channelKey.publicExternalRepresentation()
            } catch {
                return Base58EncodedPublicKey(data: Data())
            }
        }
    }
    
    var channel: Data {
        get {
            Data(SHA256.hash(data: channelPublicKey.data))
        }
    }
    
    var encodedChannel: String {
        get {
            base64ToBase64Url(base64: Base64EncodedString(data: channel))
        }
    }

    public init(name: String,
        apiUrl: String,
        apiVersion: String,
        linkScheme: String,
        linkVersion: String,
        urlSession: URLSession? = nil,
        onFinished: @escaping (Bool) -> Void
    ) throws {
        self.name = name
        self.apiUrl = apiUrl
        self.apiVersion = apiVersion
        self.linkScheme = linkScheme
        self.linkVersion = linkVersion
        self.channelKey = try EncryptionKey.generateRandomKey()
        self.authKey = try EncryptionKey.generateRandomKey()
        self.createdAt = Date()
        self.onFinished = onFinished
        self.dispatchQueue = DispatchQueue.init(label: "Censo SDK")
        self.urlSession = urlSession ?? URLSession.init(configuration: .ephemeral)
    }

    public func cancel() {
        self.checkConnectionTimer?.invalidate()
        self.finished = true
        self.onFinished(false)
    }

    private func createAPIRequest(path: String, method: String, body: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(apiUrl)/\(apiVersion)/\(path)")!)

        let timestamp = Date().ISO8601Format()
        let bodyBase64 = if (body == nil) { "" } else {
            Base64EncodedString(data: body?.data(using: .utf8) ?? Data()).value
        }
        let dataToSign = "\(method)\(request.url!.path)\(bodyBase64)\(timestamp)".data(using: .utf8)
        let signature = dataToSign.flatMap { try? authKey.signature(for: $0) }?.value ?? "[CORRUPT_AUTH_KEY]"

        request.addValue(timestamp, forHTTPHeaderField: "X-Censo-Timestamp")
        request.addValue("signature \(signature)", forHTTPHeaderField: "Authorization")
        request.addValue((try? authKey.publicExternalRepresentation().data.toBase58()) ?? "", forHTTPHeaderField: "X-Censo-Device-Public-Key")

        request.httpBody = body?.data(using: .utf8)

        request.httpMethod = method
        
        return request
    }
    
    
    private func checkConnection(timer: Timer) {
        if Date().timeIntervalSince(self.createdAt) > 10.0 * 60 {
            self.cancel()
            return
        }
        self.dispatchQueue.async {
            let request = self.createAPIRequest(path: "import/\(self.encodedChannel)", method: "GET")
            
            self.urlSession.dataTask(with: request) { data, response, error in
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.cancel()
                    return
                }
                if (200...299).contains(httpResponse.statusCode) {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .formatted(.iso8601Full)
                    
                    if let data = data,
                       let response = try? decoder.decode(GetImportDataApiResponse.self, from: data) {
                        switch response.importState {
                        case .accepted(let accepted):
                            guard let ownerKey = try? EncryptionKey.generateFromPublicExternalRepresentation(base58PublicKey: accepted.ownerDeviceKey),
                                  let verified = try? (ownerKey.verifySignature(for: self.channelPublicKey.data, signature: accepted.ownerProof)) else {
                                self.cancel()
                                return
                            }
                            if (verified) {
                                self.checkConnectionTimer?.invalidate()
                                self.ownerDeviceKey = ownerKey
                                self.onConnected?()
                            } else {
                                self.cancel()
                            }
                        case .completed:
                            self.cancel()
                        case .initial:
                            break
                        }
                    }
                } else if httpResponse.statusCode != 418 { // 418 is maintenance mode, just keep trying
                    self.cancel()
                }
            }.resume()
        }
    }
    
    public func phrase(binaryPhrase: String, language: WordListLanguage = .english, label: String = "") throws {
        if (self.finished) {
            throw CensoSDKError.sessionFinished
        }
        if (self.ownerDeviceKey == nil) {
            throw CensoSDKError.sessionNotConnected
        }
        let exportedPhrase = ExportedPhrase(binaryPhrase: binaryPhrase, language: Int(language.toId()), label: label)
        let jsonEncoder = JSONEncoder()
        let exportedData = try jsonEncoder.encode(exportedPhrase)
        let encryptedData = try self.ownerDeviceKey!.encrypt(data: exportedData)
        let body = try String(decoding: jsonEncoder.encode(EncryptedPhrase(encryptedData: encryptedData)), as: UTF8.self)
        let request = createAPIRequest(path: "import/\(self.encodedChannel)/encrypted", method: "POST", body: body)

        URLSession.init(configuration: .ephemeral).dataTask(with: request) { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                self.cancel()
                return
            }
            self.finished = true
            self.onFinished(true)
        }.resume()
    }
    
    public func connect(onConnected: @escaping () -> Void) throws -> String {
        let publicKeyBytes = try self.channelKey.publicKeyData()
        let dateInMillis = String(Int(1000 * self.createdAt.timeIntervalSince1970))
        let dateInMillisBytes = dateInMillis.data(using: .utf8)!
        var dataToSign = Data(dateInMillisBytes)
        let nameData = self.name.data(using: .utf8)!
        dataToSign.append(Data(SHA256.hash(data: nameData)))
        let signature = try self.channelKey.signature(for: dataToSign)
        let encodedSignature = base64ToBase64Url(base64: signature)
        let encodedName = base64ToBase64Url(base64: Base64EncodedString(data: nameData))
        let verified = try channelKey.verifySignature(for: dataToSign, signature: signature)
        if (verified) {
            self.onConnected = onConnected
            self.checkConnectionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true, block: checkConnection)
            return "\(linkScheme)://import/\(linkVersion)/\(Base58.encode(publicKeyBytes.bytes))/\(dateInMillis)/\(encodedSignature)/\(encodedName)"
        } else {
            throw CensoSDKError.linkSignatureNotVerified
        }
    }
    
    private func base64ToBase64Url(base64: Base64EncodedString) -> String {
        return base64.value
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
