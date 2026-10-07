import Foundation
import CryptoKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    fail("Usage: swift scripts/verify-update-signature.swift PUBLIC_KEY_BASE64 ARCHIVE_PATH SIGNATURE_BASE64")
}
guard let keyData = Data(base64Encoded: arguments[1]), keyData.count == 32,
      let signature = Data(base64Encoded: arguments[3]), signature.count == 64 else {
    fail("Invalid update public key or signature.")
}
do {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[2]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: archive) else {
        fail("Update signature verification failed.")
    }
} catch {
    fail("Unable to verify update signature.")
}
