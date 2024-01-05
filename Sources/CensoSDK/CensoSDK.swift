import Foundation
import CryptoKit

public struct CensoWalletConfig {
    var apiUrl: String
    var apiVersion: String
    var linkScheme: String
    var linkVersion: String
    public init(apiUrl: String? = nil, apiVersion: String? = nil, linkScheme: String? = nil, linkVersion: String? = nil) {
        self.apiUrl = apiUrl ?? "https://api.censo.co"
        self.apiVersion = apiVersion ?? "v1"
        self.linkScheme = linkScheme ?? "censo-main"
        self.linkVersion = linkVersion ?? "v1"
    }
}

public struct CensoWalletIntegration {
    var config: CensoWalletConfig
    public init(config: CensoWalletConfig? = nil) {
        self.config = config ?? CensoWalletConfig()
    }

    public func initiate(onFinished: @escaping (Bool) -> Void) throws -> Session {
        guard let name = (Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String) else {
            throw CensoSDKError.nameNotFound
        }
        return try Session(
            name: name,
            apiUrl: config.apiUrl,
            apiVersion: config.apiVersion,
            linkScheme: config.linkScheme,
            linkVersion: config.linkVersion,
            onFinished: onFinished
        )
    }
}
