//
//  Item.swift
//  Kodama
//
//  Created by Daisuke Ooba on 2026/04/02.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
