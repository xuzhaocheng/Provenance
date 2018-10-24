//
//  RMSaveStavesViewController.swift
//  Provenance
//
//  Created by James Addyman on 30/03/2018.
//  Copyright © 2018 James Addyman. All rights reserved.
//

import UIKit
import Realm
import RealmSwift
import PVLibrary
import PVSupport

protocol RMSaveStavesViewControllerDelegate: class {
	func saveStatesViewControllerDone(_ saveStatesViewController: RMSaveStavesViewController)
	func saveStatesViewControllerCreateNewState(_ saveStatesViewController: RMSaveStavesViewController) throws
    func saveStatesViewControllerOverwriteState(_ saveStatesViewController: RMSaveStavesViewController, state: RMSaveStave) throws
	func saveStatesViewController(_ saveStatesViewController: RMSaveStavesViewController, load state: RMSaveStave)
}

class RMSaveStavesViewController: UICollectionViewController {

	private var autoSaveStatesObserverToken: NotificationToken!
	private var manualSaveStatesObserverToken: NotificationToken!

	weak var delegate: RMSaveStavesViewControllerDelegate?

	var saveStates: LinkingObjects<RMSaveStave>!
	var screenshot: UIImage?

	var coreID : String?

	private var autoSaves: Results<RMSaveStave>!
	private var manualSaves: Results<RMSaveStave>!

	deinit {
		autoSaveStatesObserverToken.invalidate()
		autoSaveStatesObserverToken = nil
		manualSaveStatesObserverToken.invalidate()
		manualSaveStatesObserverToken = nil
	}

    override func viewDidLoad() {
        super.viewDidLoad()

#if os(iOS)
		title = "Save States"
#endif
		#if os(tvOS)
		collectionView?.register(UINib(nibName: "RMSaveStaveCollectionViewCell~tvOS", bundle: nil), forCellWithReuseIdentifier: "SaveStateView")
		#else
		collectionView?.register(UINib(nibName: "RMSaveStaveCollectionViewCell", bundle: nil), forCellWithReuseIdentifier: "SaveStateView")
		#endif

		let allSaves : Results<RMSaveStave>
		if let coreID = coreID {
			let filter : String = "core.identifier == \"" + coreID + "\""
			allSaves = saveStates.filter(filter).sorted(byKeyPath: "date", ascending: false)
		} else {
			allSaves = saveStates.sorted(byKeyPath: "date", ascending: false)
		}

		autoSaves = allSaves.filter("isAutosave == true")
		manualSaves = allSaves.filter("isAutosave == false")

		if screenshot == nil {
			navigationItem.rightBarButtonItem = nil
		}

		autoSaveStatesObserverToken = autoSaves.observe { [unowned self] (changes: RealmCollectionChange) in
			switch changes {
			case .initial:
				self.collectionView?.reloadData()
			case .update(_, let deletions, _, _):
				guard deletions.count > 0 else {
					return
				}

				let fromItem = { (item: Int) -> IndexPath in
					let section = 0
					return IndexPath(item: item, section: section)
				}
				self.collectionView?.performBatchUpdates({
					self.collectionView?.deleteItems(at: deletions.map(fromItem))
				}, completion: nil)
			case .error(let error):
				ELOG("Error updating save states: " + error.localizedDescription)
			}
		}

		manualSaveStatesObserverToken = manualSaves.observe { [unowned self] (changes: RealmCollectionChange) in
			switch changes {
			case .initial:
				self.collectionView?.reloadData()
			case .update(_, let deletions, let insertions, _):
				guard deletions.count > 0 || insertions.count > 0 else {
					return
				}
				let fromItem = { (item: Int) -> IndexPath in
					let section = 1
					return IndexPath(item: item, section: section)
				}
				self.collectionView?.performBatchUpdates({
					self.collectionView?.deleteItems(at: deletions.map(fromItem))
					self.collectionView?.insertItems(at: insertions.map(fromItem))
				}, completion: nil)
			case .error(let error):
				ELOG("Error updating save states: " + error.localizedDescription)
			}
		}

		let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(self.longPressRecognized(_:)))
		collectionView?.addGestureRecognizer(longPressRecognizer)
    }

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		if let emulatorViewController = presentingViewController as? PVEmulatorViewController {
			emulatorViewController.core.setPauseEmulation(false)
			emulatorViewController.isShowingMenu = false
			emulatorViewController.enableContorllerInput(false)
		}
	}

	@objc func longPressRecognized(_ recognizer: UILongPressGestureRecognizer) {
		switch recognizer.state {
		case .began:
			let point: CGPoint = recognizer.location(in: collectionView)
			var maybeIndexPath: IndexPath? = collectionView?.indexPathForItem(at: point)

#if os(tvOS)
			if maybeIndexPath == nil, let focusedView = UIScreen.main.focusedView as? UICollectionViewCell {
				maybeIndexPath = collectionView?.indexPath(for: focusedView)
			}
#endif
			guard let indexPath = maybeIndexPath else {
				ELOG("No index path at touch point")
				return
			}

			var state: RMSaveStave?
			switch indexPath.section {
			case 0:
				state = autoSaves[indexPath.item]
			case 1:
				state = manualSaves[indexPath.item]
			default:
				break
			}

			guard let saveState = state else {
				ELOG("No save state at indexPath: \(indexPath)")
				return
			}

			let alert = UIAlertController(title: "Delete this save state?", message: nil, preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: "Yes", style: .destructive) {[unowned self] action in
				do {
					try RMSaveStave.delete(saveState)
				} catch {
					self.presentError("Error deleting save state: \(error.localizedDescription)")
				}
			})
			alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil))
			present(alert, animated: true)
		default:
			break
		}
	}

	@IBAction func done(_ sender: Any) {
		delegate?.saveStatesViewControllerDone(self)
	}

	@IBAction func newSaveState(_ sender: Any) {
		do {
			try delegate?.saveStatesViewControllerCreateNewState(self)
		} catch {
			let reason = (error as NSError).localizedFailureReason
			self.presentError("Error creating save state: \(error.localizedDescription) \(reason ?? "")")
		}
	}

    func showSaveStateOptions(saveState: RMSaveStave) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Load", style: .default, handler: { (action: UIAlertAction) in
            self.delegate?.saveStatesViewController(self, load: saveState)
        }))
        alert.addAction(UIAlertAction(title: "Save & Overwrite", style: .default, handler: { (action: UIAlertAction) in
			do {
				try self.delegate?.saveStatesViewControllerOverwriteState(self, state: saveState)
			} catch {
				self.presentError("Error overwriting save state: \(error.localizedDescription)")
			}
        }))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { (action: UIAlertAction) in
			do {
				try RMSaveStave.delete(saveState)
			} catch {
                self.presentError("Error deleting save state: \(error.localizedDescription)")
            }
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true)
    }

	override func numberOfSections(in collectionView: UICollectionView) -> Int {
		return 2
	}

	override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
		let reusableView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "SaveStateHeader", for: indexPath) as! RMSaveStaveHeaderView
		switch indexPath.section {
		case 0:
			reusableView.label.text = "Auto Save"
		case 1:
			reusableView.label.text = "Save States"
		default:
			break
		}

		return reusableView
	}

	override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		switch section {
		case 0:
			return autoSaves.count
		case 1:
			return manualSaves.count
		default:
			return 0
		}
	}

	override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "SaveStateView", for: indexPath) as! RMSaveStaveCollectionViewCell
		var saveState: RMSaveStave?
		switch indexPath.section {
		case 0:
			saveState = autoSaves[indexPath.item]
		case 1:
			saveState = manualSaves[indexPath.item]
		default:
			break
		}

		cell.saveState = saveState

		return cell
	}

	override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		switch indexPath.section {
		case 0:
			let saveState = autoSaves[indexPath.item]
			delegate?.saveStatesViewController(self, load: saveState)
		case 1:
            var saveState: RMSaveStave?
			saveState = manualSaves[indexPath.item]
            guard let state = saveState else {
                ELOG("No save state at indexPath: \(indexPath)")
                return
            }
            showSaveStateOptions(saveState: state)
		default:
			break
		}
	}
}
