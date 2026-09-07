//
//  HTTPClient.swift
//  DoToday
//
//  Data layer — the seam between our code and the network.
//

import Foundation

/// Performs an `Endpoint` and decodes its JSON body.
///
/// This protocol is the single mocking point for the whole data layer: repository
/// tests substitute a stub client and never touch `URLSession` or a live server.
protocol HTTPClient: Sendable {
    /// - Throws: `AppError` — implementations are responsible for translating
    ///   transport and decoding failures into the domain error vocabulary.
    func get<Response: Decodable>(_ endpoint: Endpoint, as type: Response.Type) async throws -> Response
}
