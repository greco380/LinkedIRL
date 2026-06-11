import CryptoKit
import Foundation

enum LinkedInImportError: LocalizedError, Equatable {
    case invalidProfileURL
    case unreadableFile
    case archiveExtractionUnavailable
    case missingHeader
    case noConnections

    var errorDescription: String? {
        switch self {
        case .invalidProfileURL:
            return "Enter a valid LinkedIn profile URL."
        case .unreadableFile:
            return "The selected CSV could not be read."
        case .archiveExtractionUnavailable:
            return "Open the LinkedIn archive and select Connections.csv. Full ZIP upload will run through the backend import worker."
        case .missingHeader:
            return "The CSV does not look like a LinkedIn connections export."
        case .noConnections:
            return "No connections were found in the selected CSV."
        }
    }
}

struct LinkedInNetworkImportService {
    func normalizedProfileURL(_ rawURL: String) throws -> String {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: withScheme),
              let host = components.host?.lowercased(),
              host == "linkedin.com" || host.hasSuffix(".linkedin.com"),
              components.path.lowercased().contains("/in/") else {
            throw LinkedInImportError.invalidProfileURL
        }
        return withScheme
    }

    func profileSlug(from rawURL: String) -> String? {
        guard let normalizedURL = try? normalizedProfileURL(rawURL),
              let components = URLComponents(string: normalizedURL) else {
            return nil
        }
        let pathParts = components.path.split(separator: "/").map(String.init)
        guard let inIndex = pathParts.firstIndex(where: { $0.lowercased() == "in" }),
              pathParts.indices.contains(inIndex + 1) else {
            return nil
        }
        return pathParts[inIndex + 1].lowercased()
    }

    func importConnections(from fileURL: URL, accountID: UUID, source: LinkedInImportSource = .csvExport) throws -> LinkedInConnectionImportResult {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        if fileURL.pathExtension.lowercased() == "zip" {
            throw LinkedInImportError.archiveExtractionUnavailable
        }

        guard let data = try? Data(contentsOf: fileURL),
              let text = decodedCSVText(from: data) else {
            throw LinkedInImportError.unreadableFile
        }

        let rows = parseCSV(text)
        guard let headerIndex = rows.firstIndex(where: { row in
            let lowercased = row.map { $0.lowercased() }
            return lowercased.contains("first name") && lowercased.contains("last name")
        }) else {
            throw LinkedInImportError.missingHeader
        }

        let headers = rows[headerIndex].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let dataRows = rows.dropFirst(headerIndex + 1)
        let importedAt = Date()
        let importID = UUID()
        let importRecord = LinkedInImportRecord(
            id: importID,
            accountID: accountID,
            source: source,
            importedAt: importedAt,
            rowCount: 0,
            fileHash: sha256Hex(data)
        )

        var observations: [LinkedInProfileObservation] = []
        var profilesByID: [String: LinkedInProfileRecord] = [:]
        let connections = dataRows.compactMap { row -> LinkedInNetworkConnection? in
            let firstName = value("first name", in: row, headers: headers)
            let lastName = value("last name", in: row, headers: headers)
            let profileURL = value("url", in: row, headers: headers)
            guard !profileURL.isEmpty else { return nil }
            let emailHash = hashedEmail(optionalValue("email address", in: row, headers: headers))
            let company = optionalValue("company", in: row, headers: headers)
            let position = optionalValue("position", in: row, headers: headers)
            let connectedOn = parseDate(optionalValue("connected on", in: row, headers: headers))
            let profileID = connectionProfileID(from: profileURL)
            let slug = profileSlug(from: profileURL)
            let fieldMask = LinkedInConnectionFieldMask(
                hasFirstName: !firstName.isEmpty,
                hasLastName: !lastName.isEmpty,
                hasCompany: company != nil,
                hasPosition: position != nil,
                hasEmailHash: emailHash != nil,
                hasConnectedOn: connectedOn != nil
            )

            profilesByID[profileID] = LinkedInProfileRecord(
                id: profileID,
                normalizedURL: (try? normalizedProfileURL(profileURL)) ?? profileURL,
                slug: slug,
                firstName: firstName.isEmpty ? nil : firstName,
                lastName: lastName.isEmpty ? nil : lastName,
                company: company,
                position: position
            )

            observations.append(
                LinkedInProfileObservation(
                    id: UUID(),
                    profileID: profileID,
                    importID: importID,
                    source: source,
                    observedAt: importedAt,
                    firstName: firstName.isEmpty ? nil : firstName,
                    lastName: lastName.isEmpty ? nil : lastName,
                    company: company,
                    position: position,
                    rawURL: profileURL,
                    rawRowHash: sha256Hex(row.joined(separator: "\u{1F}"))
                )
            )

            return LinkedInNetworkConnection(
                id: UUID(),
                accountID: accountID,
                connectionProfileID: profileID,
                importID: importID,
                confidenceScore: confidenceScore(profileURL: profileURL, fieldMask: fieldMask),
                fieldMask: fieldMask,
                firstName: firstName,
                lastName: lastName,
                profileURL: profileURL,
                emailHash: emailHash,
                company: company,
                position: position,
                connectedOn: connectedOn,
                importedAt: importedAt
            )
        }

        guard !connections.isEmpty else {
            throw LinkedInImportError.noConnections
        }

        var completedRecord = importRecord
        completedRecord.rowCount = connections.count
        return LinkedInConnectionImportResult(
            importRecord: completedRecord,
            profiles: profilesByID.values.sorted { $0.id < $1.id },
            connections: connections,
            profileObservations: observations
        )
    }

    private func decodedCSVText(from data: Data) -> String? {
        guard let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        // Strip a leading UTF-8/UTF-16 byte-order mark. LinkedIn (and some
        // spreadsheet tools that re-save the export) can prefix the file with
        // a BOM, which would otherwise become part of the first header cell
        // ("\u{FEFF}First Name") and break header detection / column lookup.
        if decoded.hasPrefix("\u{FEFF}") {
            return String(decoded.dropFirst())
        }
        return decoded
    }

    private func value(_ key: String, in row: [String], headers: [String]) -> String {
        guard let index = headers.firstIndex(of: key), row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optionalValue(_ key: String, in row: [String], headers: [String]) -> String? {
        let resolved = value(key, in: row, headers: headers)
        return resolved.isEmpty ? nil : resolved
    }

    private func connectionProfileID(from rawURL: String) -> String {
        if let slug = profileSlug(from: rawURL) {
            return "linkedin:in:\(slug)"
        }
        return rawURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func hashedEmail(_ rawEmail: String?) -> String? {
        guard let normalized = rawEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return nil
        }
        return sha256Hex(normalized)
    }

    private func confidenceScore(profileURL: String, fieldMask: LinkedInConnectionFieldMask) -> Double {
        var score = 0.5
        if profileSlug(from: profileURL) != nil { score += 0.25 }
        if fieldMask.hasFirstName || fieldMask.hasLastName { score += 0.1 }
        if fieldMask.hasCompany || fieldMask.hasPosition { score += 0.05 }
        if fieldMask.hasConnectedOn { score += 0.1 }
        return min(score, 1)
    }

    private func sha256Hex(_ string: String) -> String {
        sha256Hex(Data(string.utf8))
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["d MMM yyyy", "dd MMM yyyy", "MMM d, yyyy", "MMM dd, yyyy", "yyyy-MM-dd", "M/d/yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        return nil
    }

    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    inQuotes.toggle()
                }
            } else if character == "," && !inQuotes {
                row.append(field)
                field = ""
            } else if character == "\n" && !inQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }

            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }
}

struct LinkedInConnectionImportResult {
    var importRecord: LinkedInImportRecord
    var profiles: [LinkedInProfileRecord]
    var connections: [LinkedInNetworkConnection]
    var profileObservations: [LinkedInProfileObservation]
}
