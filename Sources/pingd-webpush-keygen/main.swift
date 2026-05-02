import ArgumentParser
import Foundation
import WebPush

@main
struct WebPushKeygenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pingd-webpush-keygen",
        abstract: "Generate a PINGD_WEBPUSH_VAPID_CONFIG value for browser push notifications.",
        discussion: """
        Generate this once for each deployment and keep the primaryKey secret.
        Changing the VAPID key later can require users to re-enable browser notifications.
        """
    )

    @Option(help: "Contact email for push services, for example admin@example.com.")
    var email: String?

    @Option(help: "Contact support URL for push services, for example https://example.com/support.")
    var url: String?

    @Flag(help: "Print only the raw JSON value, without the PINGD_WEBPUSH_VAPID_CONFIG= prefix.")
    var jsonOnly = false

    @Flag(help: "Pretty-print JSON. Best for reading, not for direct .env usage.")
    var pretty = false

    mutating func run() throws {
        let contactInformation: VAPID.Configuration.ContactInformation
        if let email, url == nil {
            contactInformation = .email(email)
        } else if email == nil, let url {
            guard let supportURL = URL(string: url),
                  let scheme = supportURL.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else {
                throw ValidationError("--url must be a fully-qualified HTTP or HTTPS URL.")
            }
            contactInformation = .url(supportURL)
        } else if email != nil, url != nil {
            throw ValidationError("Use either --email or --url, not both.")
        } else {
            throw ValidationError("Provide either --email admin@example.com or --url https://example.com/support.")
        }

        let configuration = VAPID.Configuration(
            key: VAPID.Key(),
            contactInformation: contactInformation
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        let json = String(decoding: try encoder.encode(configuration), as: UTF8.self)

        if jsonOnly {
            print(json)
        } else {
            print("PINGD_WEBPUSH_VAPID_CONFIG='\(json)'")
        }
    }
}
