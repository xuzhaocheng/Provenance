import Foundation

protocol DomainConvertibleType {
    associatedtype DomainType

    func asDomain() -> DomainType
}

// MARK: - Default implimentations
extension LocalFileProvider where Self : DomainConvertibleType {
	func asDomain() -> LocalFile {
		return LocalFile(url: url)!
	}
}

extension DomainConvertibleType where Self:LocalFileInfoProvider {
	func asDomain() -> LocalFile {
		return LocalFile(url: url)!
	}
}
