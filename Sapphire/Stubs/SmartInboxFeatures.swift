//
//  SmartInboxFeatures.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

#if !SAPPHIRE_FULL_BUILD
import Foundation
import Combine

struct OTPEvent: Identifiable, Equatable {
    let id: String
    let code: String
    let source: String
    let title: String
    let body: String
    let date: Date
}

struct ParcelShipment: Identifiable, Equatable, Codable {
    let id: String
    var trackingNumber: String
    var carrier: ParcelCarrier
    var title: String
    var status: String
    var detail: String
    var lastUpdated: Date
    var sourceEmailSubject: String?
    var isDelivered: Bool

    var trackingURL: URL? { carrier.trackingURL(trackingNumber) }
}

enum ParcelCarrier: String, Codable, CaseIterable {
    case ups, fedex, usps, dhl, amazon, unknown

    var displayName: String {
        switch self {
        case .ups: return "UPS"
        case .fedex: return "FedEx"
        case .usps: return "USPS"
        case .dhl: return "DHL"
        case .amazon: return "Amazon"
        case .unknown: return "Carrier"
        }
    }

    var trackingURL: (String) -> URL? { { SmartInboxPolicy.carrierURL(self, number: $0) } }
}

#endif
