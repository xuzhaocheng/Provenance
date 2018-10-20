//
//  Files.swift
//  PVLibrary
//
//  Created by Joseph Mattiello on 10/19/18.
//  Copyright © 2018 Provenance Emu. All rights reserved.
//

import Foundation

public enum FileSystemType {
	case local
	case remote
}

/// A type that can represent a file for library import usage
///
///
public protocol FileInfoProvider {
	var fileName : String { get }
	var md5 : String? { get }
	var size : UInt64 { get }
	var online : Bool { get }
}

public protocol LocalFileInfoProvider : FileInfoProvider {
	var url : URL { get }
}

public protocol LocalFileProvider : LocalFileInfoProvider, DataProvider {

}

public extension LocalFileProvider {
	var data : Data? {
		return try? Data(contentsOf: url)
	}
}

public protocol DataProvider {
	var data : Data? { get }
}

public protocol RemoteFileInfoProvider : FileInfoProvider {
	var dataProvider : DataProvider { get }
}

// Cache for storing md5's
private let md5Cache : Cache<URL,String> = {
	let c = Cache<URL,String>(lowMemoryAware: false)
	c.countLimit = 1024
	let d = Data()

	return c
}()

extension LocalFileInfoProvider {
	public var size: UInt64 {
		let fileSize: UInt64

		if let attr = try? FileManager.default.attributesOfItem(atPath: url.path) as NSDictionary {
			fileSize = attr.fileSize()
		} else {
			fileSize = 0
		}
		return fileSize
	}

	public var online: Bool {
		return FileManager.default.fileExists(atPath: url.path)
	}

	public var pathExtension: String {
		return url.pathExtension
	}

	public var fileName: String {
		return url.lastPathComponent
	}

	public var fileNameWithoutExtension: String {
		return url.deletingPathExtension().lastPathComponent
	}

	public var md5: String? {
		get {
			if let md5 = md5Cache.object(forKey: url) {
				return md5
			}

			// Lazy make MD5
			guard let calculatedMD5 = FileManager.default.md5ForFile(atPath: url.path, fromOffset: 0) else {
				return nil
			}

			md5Cache.setObject(calculatedMD5, forKey: url)
			return calculatedMD5
		}
	}
}

public protocol FileBacked {
	associatedtype FileInfoProviderType : FileInfoProvider
	var file: FileInfoProviderType? { get }
}

public protocol LocalFileBacked : FileBacked where FileInfoProviderType : LocalFileInfoProvider {

}
