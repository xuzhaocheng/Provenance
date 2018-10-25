//
//  RMGameLibraryViewController+PeekPop.swift
//  Provenance
//
//  Created by Joseph Mattiello on 5/26/18.
//  Copyright © 2018 Provenance. All rights reserved.
//

import Foundation
import UIKit
import PVLibrary
import PVSupport

#if os(iOS)
@available(iOS 9.0, *)
extension RMGameLibraryViewController: UIViewControllerPreviewingDelegate {
	func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {

		if let moreInfoVC = viewControllerToCommit as? RMGameMoreInfoViewController {
			let moreInfoGamePageVC = UIStoryboard(name: "Provenance", bundle: nil).instantiateViewController(withIdentifier: "gameMoreInfoPageVC") as! GameMoreInfoPageViewController
			moreInfoGamePageVC.setViewControllers([moreInfoVC], direction: .forward, animated: false, completion: nil)
			navigationController!.show(moreInfoGamePageVC, sender: self)
		} else if let saveSaveInfoVC = viewControllerToCommit as? RMSaveStateInfoViewController {
			navigationController!.show(saveSaveInfoVC, sender: self)
		}
	}

	func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
		if let indexPath = collectionView!.indexPathForItem(at: location), let cellAttributes = collectionView!.layoutAttributesForItem(at: indexPath) {

			//This will show the cell clearly and blur the rest of the screen for our peek.
			previewingContext.sourceRect = cellAttributes.frame


			if searchResults == nil, indexPath.section == saveStateSection {
				let storyBoard = UIStoryboard(name: "SaveStates", bundle: nil)

				let saveStateInfoVC = storyBoard.instantiateViewController(withIdentifier: "saveStateInfoVC") as! RMSaveStateInfoViewController
				let saveStatesCell = collectionView!.cellForItem(at: IndexPath(row: 0, section: saveStateSection)) as! SaveStatesCollectionCell

				let location2 = saveStatesCell.internalCollectionView.convert(location, from: collectionView)
				let indexPath2 = saveStatesCell.internalCollectionView.indexPathForItem(at: location2)!
				saveStateInfoVC.saveState = saveStates![indexPath2.row]
				return saveStateInfoVC
			} else {
				guard let game = game(at: indexPath, location: location) else {
					ELOG("No game at index : \(indexPath)")
					return nil
				}
				let storyBoard = UIStoryboard(name: "Provenance", bundle: nil)

				let moreInfoViewContrller = storyBoard.instantiateViewController(withIdentifier: "gameMoreInfoVC") as! RMGameMoreInfoViewController
				moreInfoViewContrller.game = game
				moreInfoViewContrller.showsPlayButton = true
				return moreInfoViewContrller
			}
		}
		return nil
	}
}
#endif
