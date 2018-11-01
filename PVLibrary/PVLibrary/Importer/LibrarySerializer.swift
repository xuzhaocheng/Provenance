//
//  LibrarySerializer.swift
//  PVLibrary
//
//  Created by Joseph Mattiello on 10/30/18.
//  Copyright © 2018 Provenance Emu. All rights reserved.
//

import Foundation
import Disk

public struct SavePackage : Codable {
    public let data : Data
    public let metadata : SaveState
}

public struct GamePackage : Codable {
    public let data : Data
    public let metadata : Game
    public let saves : [SavePackage]
}

public typealias SerliazeCompletion = (_ error : Error?)->Void

public final class LibrarySerializer {
    public init() {

    }

    static private let serializeQueue = DispatchQueue(label: "com.provenance.serializer", qos: .background)

    public func serialize(_ save : PVSaveState, completion: @escaping SerliazeCompletion) {
        let directory = (save.file.partialPath as NSString).deletingLastPathComponent
        let fileName = save.file.fileName
        let data = save.asDomain()

        LibrarySerializer.serializeQueue.async {
            let jsonFilename = fileName + ".json"
            let relativePath = directory + "/" + jsonFilename
            do {
                try Disk.save(data, to: .documents, as: relativePath)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    public func package(_ save : PVSaveState, completion: @escaping SerliazeCompletion) {
        let directory = (save.file.partialPath as NSString).deletingLastPathComponent
        let fileName = save.file.fileNameWithoutExtension
        let metadata = save.asDomain()
        let path = save.file.url

        LibrarySerializer.serializeQueue.async {

            let jsonFilename = fileName + ".psvsave"
            let relativePath = directory + "/" + jsonFilename
            do {
                let data = try Data(contentsOf: path)
                let package = SavePackage(data: data, metadata: metadata)

                try Disk.save(package, to: .documents, as: relativePath)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    public func package(_ game : PVGame, completion: @escaping SerliazeCompletion) {
        let directory = (game.file.partialPath as NSString).deletingLastPathComponent
        let fileName = game.file.fileNameWithoutExtension
        let romPath = game.file.url

        let gameMetadata = game.asDomain()

        let saves = Array(game.saveStates).map { save -> SavePackage in
            let data = try! Data(contentsOf: save.file.url)
            let metadata = save.asDomain()
            return SavePackage(data: data, metadata: metadata)
        }

        LibrarySerializer.serializeQueue.async {

            let jsonFilename = fileName + ".pvrom"
            let relativePath = directory + "/" + jsonFilename
            do {
                let gameData = try Data(contentsOf: romPath)

                let gamePackage = GamePackage(data: gameData, metadata: gameMetadata, saves: saves)
                try Disk.save(gamePackage, to: .documents, as: relativePath)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }
}
