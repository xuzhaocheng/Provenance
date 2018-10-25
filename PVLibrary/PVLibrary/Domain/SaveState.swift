//
//  SaveState.swift
//  PVLibrary
//
//  Created by Joseph Mattiello on 10/25/18.
//  Copyright © 2018 Provenance Emu. All rights reserved.
//

import Foundation

public struct SaveState : Codable {
	public let game: Game
	public let core: Core
	public let file: FileInfo
	public let date: Date
	public let lastOpened: Date?
	public let image: LocalFile?
	public let isAutosave: Bool
}
