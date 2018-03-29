//
//  CoreSettings.swift
//  PVSupport
//
//  Created by Joseph Mattiello on 3/28/18.
//  Copyright © 2018 James Addyman. All rights reserved.
//

import Foundation

protocol GenericSetting  : Codable {
    associatedtype settingType
    
    var currentValue : settingType {get set}
    var defultValue : settingType {get}
    
    var userVisible : Bool {get}
}

extension GenericSetting {
    var userVisible : Bool { return true }
}

protocol BoolSetting : GenericSetting {
    var currentValue : Bool {get set}
    var defultValue : Bool {get}
}


struct CoreSetting {
    let title : String
    let description : String
}
