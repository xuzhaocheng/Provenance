//
//  RMCore.swift
//  Provenance
//
//  Created by Joseph Mattiello on 3/11/18.
//  Copyright © 2018 James Addyman. All rights reserved.
//

import Foundation
import RealmSwift

@objcMembers
public final class RMCore: Object {
    dynamic public var identifier: String = ""
    dynamic public var principleClass: String = ""
    dynamic public var supportedSystems = List<PVSystem>()

    dynamic public var projectName = ""
    dynamic public var projectURL = ""
    dynamic public var projectVersion = ""

	// Reverse links
	public var saveStates = LinkingObjects(fromType: RMSaveState.self, property: "core")

    public convenience init(withIdentifier identifier: String, principleClass: String, supportedSystems: [PVSystem], name: String, url: String, version: String) {
        self.init()
        self.identifier = identifier
        self.principleClass = principleClass
        self.supportedSystems.removeAll()
        self.supportedSystems.append(objectsIn: supportedSystems)
        self.projectName = name
        self.projectURL = url
        self.projectVersion = version
    }

    override public static func primaryKey() -> String? {
        return "identifier"
    }
}

// MARK: - Conversions
internal extension Core {
	init(with core : RMCore) {
		identifier = core.identifier
		principleClass = core.principleClass
		// TODO: Supported systems
		project = CoreProject(name: core.projectName, url: URL(string: core.projectURL)!, version: core.projectVersion)
	}
}


extension RMCore: DomainConvertibleType {
	public typealias DomainType = Core

	func asDomain() -> Core {
		return Core(with: self)
	}
}

extension Core: RealmRepresentable {
	var uid: String {
		return identifier
	}

	func asRealm() -> RMCore {
		return RMCore.build({ object in
			object.identifier = identifier
			object.principleClass = principleClass
			#warning("do me")
//			object.supportedSystems
			object.projectName = project.name
			object.projectVersion = project.version
			object.projectURL = project.url.absoluteString
		})
	}
}

