enum CensoSDKError : Error {
    case linkSignatureNotVerified
    case nameNotFound
    case sessionFinished
    case sessionNotConnected
    case censoUnderMaintenance
}
