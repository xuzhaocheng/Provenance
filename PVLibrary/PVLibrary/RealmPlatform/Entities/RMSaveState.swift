//
//  RMSaveState.swift
//  Provenance
//
//  Created by Joseph Mattiello on 3/11/18.
//  Copyright © 2018 James Addyman. All rights reserved.
//

import Foundation
import RealmSwift
import PVSupport

@objcMembers
public final class RMSaveState: Object {

    dynamic public var game: RMGame!
	dynamic public var core: RMCore!
    dynamic public var file: RMLocalFile!
    dynamic public var date: Date = Date()
	dynamic public var lastOpened: Date?
    dynamic public var image: PVImageFile?
    dynamic public var isAutosave: Bool = false

	dynamic public var createdWithCoreVersion: String!

	public convenience init(withGame game: RMGame, core: RMCore, file: RMLocalFile, image: PVImageFile? = nil, isAutosave: Bool = false) {
        self.init()
        self.game  = game
        self.file  = file
        self.image = image
        self.isAutosave = isAutosave
		self.core = core
		createdWithCoreVersion = core.projectVersion
    }

    public class func delete(_ state: RMSaveState) throws {
        do {
			// Temp store these URLs
			let fileURL = state.file.url
			let imageURl = state.image?.url

			let database = RomDatabase.sharedInstance
			try database.delete(state)

			try FileManager.default.removeItem(at: fileURL)
			if let imageURl = imageURl {
				try FileManager.default.removeItem(at: imageURl)
			}
        } catch {
			ELOG("Failed to delete PVState")
			throw error
		}
    }

	@objc dynamic public var isNewestAutosave : Bool {
		guard isAutosave, let game = game, let newestSave = game.autoSaves.first else {
			return false
		}

		let isNewest = newestSave == self
		return isNewest
	}

	public static func == (lhs: RMSaveState, rhs: RMSaveState) -> Bool {
		return lhs.file.url == rhs.file.url
	}
}

// MARK: - Conversions
fileprivate extension SaveState {
	init(with saveState : RMSaveState) {
		game = saveState.game.asDomain()
		#warning ("DO me")
		core = saveState.core.asDomain()
//		core = saveState.core.asDomain()
		file = FileInfo(fileName: saveState.file.fileName, size: saveState.file.size, md5: saveState.file.md5, online: saveState.file.online, local: true)
		date = saveState.date
		lastOpened = saveState.lastOpened
		#warning ("DO me")
		image = nil
//		image = saveState.image
		isAutosave = saveState.isAutosave
	}
}


extension RMSaveState : DomainConvertibleType {
	public typealias DomainType = SaveState

	func asDomain() -> SaveState {
		return SaveState(with: self)
	}
}

extension SaveState: RealmRepresentable {
	var uid: String {
		return file.fileName
	}

	func asRealm() -> RMSaveState {
		return RMSaveState.build { object in
			#warning ("DO me")
		}
	}
}
