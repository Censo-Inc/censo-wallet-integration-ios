import XCTest
@testable import CensoSDK

final class CensoSDKTests: XCTestCase {
    func testSDKInstantiation() {
        XCTAssertNotNil(CensoWalletIntegration())
    }
    
    func testSessionInitiation() throws {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession.init(configuration: configuration)
        let config = CensoWalletConfig()
        //let expectation = self.expectation(description: "Session Done")
        let session = try Session(
            name: "name",
            apiUrl: config.apiUrl,
            apiVersion: config.apiVersion,
            linkScheme: config.linkScheme,
            linkVersion: config.linkVersion,
            urlSession: urlSession,
            onFinished: {_ in }
        )
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try! JSONEncoder().encode(ImportState.initial))
        }
        
        let link = try session.connect(onConnected: {})
        print(link)
        XCTAssertTrue(link.starts(with: "censo-import://v1/"))
    }
    
    func testSessionConnect() throws {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession.init(configuration: configuration)
        let config = CensoWalletConfig()
        let session = try Session(
            name: "name",
            apiUrl: config.apiUrl,
            apiVersion: config.apiVersion,
            linkScheme: config.linkScheme,
            linkVersion: config.linkVersion,
            urlSession: urlSession,
            onFinished: {_ in }
        )
        let ownerDeviceKey = try! EncryptionKey.generateRandomKey()
        MockURLProtocol.requestHandler = { request in
            if request.url == URL(string: "\(config.apiUrl)/\(config.apiVersion)/import/\(session.encodedChannel)") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.iso8601Full)
                return (
                    response,
                    try! encoder.encode(
                        GetImportDataApiResponse(
                            importState:
                                    .accepted(
                                        ImportState.Accepted(
                                            ownerDeviceKey: ownerDeviceKey.publicExternalRepresentation().data.base58EncodedPublicKey()!,
                                            ownerProof: ownerDeviceKey.signature(for: session.channelPublicKey.data),
                                            acceptedAt: Date()
                                        )
                                    )
                        )
                    )
                )
            } else {
                return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, nil)
            }
        }
        let expectation = self.expectation(description: "Session Connected")
        let link = try session.connect(onConnected: { expectation.fulfill() })
        XCTAssertTrue(link.starts(with: "censo-import://v1/"))
        waitForExpectations(timeout: 5)
    }
    
    func testSessionExport() throws {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession.init(configuration: configuration)
        let config = CensoWalletConfig()
        let expectation = self.expectation(description: "Session Done")
        let session = try Session(
            name: "name",
            apiUrl: config.apiUrl,
            apiVersion: config.apiVersion,
            linkScheme: config.linkScheme,
            linkVersion: config.linkVersion,
            urlSession: urlSession,
            onFinished: {_ in expectation.fulfill() }
        )
        let ownerDeviceKey = try! EncryptionKey.generateRandomKey()
        MockURLProtocol.requestHandler = { request in
            if request.url == URL(string: "\(config.apiUrl)/\(config.apiVersion)/import/\(session.encodedChannel)") {
                
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.iso8601Full)
                return (
                    response,
                    try! encoder.encode(
                        GetImportDataApiResponse(
                            importState:
                                    .accepted(
                                        ImportState.Accepted(
                                            ownerDeviceKey: ownerDeviceKey.publicExternalRepresentation().data.base58EncodedPublicKey()!,
                                            ownerProof: ownerDeviceKey.signature(for: session.channelPublicKey.data),
                                            acceptedAt: Date()
                                        )
                                    )
                        )
                    )
                )
            } else if request.url == URL(string: "\(config.apiUrl)/\(config.apiVersion)/import/\(session.encodedChannel)/encrypted") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
            } else {
                return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, nil)
            }
        }
        let link = try session.connect(onConnected: {
            do {
                try session.phrase(binaryPhrase: "66c6a14c56cd7435d51a61b5aac215824dddd81917f6f80ed10bbf037c8e3676")
            } catch {
                
            }
        })
        XCTAssertTrue(link.starts(with: "censo-import://v1/"))
        waitForExpectations(timeout: 5)
    }
    
    func testSessionConnectServerFails() throws {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession.init(configuration: configuration)
        let config = CensoWalletConfig()
        let expectation = self.expectation(description: "Session Failed")
        let session = try Session(
            name: "name",
            apiUrl: config.apiUrl,
            apiVersion: config.apiVersion,
            linkScheme: config.linkScheme,
            linkVersion: config.linkVersion,
            urlSession: urlSession,
            onFinished: {success in
                if !success {
                    expectation.fulfill()
                }
            }
        )
        MockURLProtocol.requestHandler = { request in
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, nil)
        }
        let _ = try session.connect(onConnected: { })
        waitForExpectations(timeout: 5)
    }

    func testSessionConnectRetriesDuringMaintenance() throws {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession.init(configuration: configuration)
        let config = CensoWalletConfig()
        let session = try Session(
            name: "name",
            apiUrl: config.apiUrl,
            apiVersion: config.apiVersion,
            linkScheme: config.linkScheme,
            linkVersion: config.linkVersion,
            urlSession: urlSession,
            onFinished: {_ in }
        )
        var count = 0
        let expectation = self.expectation(description: "Session Retried After Maintenance")

        MockURLProtocol.requestHandler = { request in
            count += 1
            if (count == 1) {
                return (HTTPURLResponse(url: request.url!, statusCode: 418, httpVersion: nil, headerFields: nil)!, nil)
            } else {
                expectation.fulfill()
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, nil)
            }
        }
        let _ = try session.connect(onConnected: { })
        waitForExpectations(timeout: 6)
    }
    
    func testSessionConnectInvalidOwnerProof() throws {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession.init(configuration: configuration)
        let config = CensoWalletConfig()
        let expectation = self.expectation(description: "Session Failed")
        let session = try Session(
            name: "name",
            apiUrl: config.apiUrl,
            apiVersion: config.apiVersion,
            linkScheme: config.linkScheme,
            linkVersion: config.linkVersion,
            urlSession: urlSession,
            onFinished: {success in
                if !success {
                    expectation.fulfill()
                }
            }
        )
        let ownerDeviceKey = try! EncryptionKey.generateRandomKey()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .formatted(.iso8601Full)
            return (
                response,
                try! encoder.encode(
                    GetImportDataApiResponse(
                        importState:
                                .accepted(
                                    ImportState.Accepted(
                                        ownerDeviceKey: ownerDeviceKey.publicExternalRepresentation().data.base58EncodedPublicKey()!,
                                        ownerProof: Base64EncodedString(data: Data([123])),
                                        acceptedAt: Date()
                                    )
                                )
                    )
                )
            )
            
        }
        let _ = try session.connect(onConnected: { })
        waitForExpectations(timeout: 5)
    }

    func testSessionNotConnected() throws {
        let config = CensoWalletConfig()
        let session = try Session(
            name: "name",
            apiUrl: config.apiUrl,
            apiVersion: config.apiVersion,
            linkScheme: config.linkScheme,
            linkVersion: config.linkVersion,
            onFinished: {_ in }
        )
        XCTAssertThrowsError(try session.phrase(binaryPhrase: ""))
    }
    
    func testSessionFinished() throws {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession.init(configuration: configuration)
        let config = CensoWalletConfig()
        let expectation = self.expectation(description: "Session Done")
        let session = try Session(
            name: "name",
            apiUrl: config.apiUrl,
            apiVersion: config.apiVersion,
            linkScheme: config.linkScheme,
            linkVersion: config.linkVersion,
            urlSession: urlSession,
            onFinished: {_ in expectation.fulfill() }
        )
        let ownerDeviceKey = try! EncryptionKey.generateRandomKey()
        MockURLProtocol.requestHandler = { request in
            if request.url == URL(string: "\(config.apiUrl)/\(config.apiVersion)/import/\(session.encodedChannel)") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.iso8601Full)
                return (
                    response,
                    try! encoder.encode(
                        GetImportDataApiResponse(
                            importState:
                                    .accepted(
                                        ImportState.Accepted(
                                            ownerDeviceKey: ownerDeviceKey.publicExternalRepresentation().data.base58EncodedPublicKey()!,
                                            ownerProof: ownerDeviceKey.signature(for: session.channelPublicKey.data),
                                            acceptedAt: Date()
                                        )
                                    )
                        )
                    )
                )
            } else {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
            }
        }
        let _ = try session.connect(onConnected: {
            do {
                try session.phrase(binaryPhrase: "66c6a14c56cd7435d51a61b5aac215824dddd81917f6f80ed10bbf037c8e3676")
            } catch {
                
            }
        })
        waitForExpectations(timeout: 5)
        XCTAssertThrowsError(try session.phrase(binaryPhrase: ""))
    }
}
