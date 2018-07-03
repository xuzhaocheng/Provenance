//  Converted to Swift 4 by Swiftify v4.1.6640 - https://objectivec2swift.com/
//
//  PVEmulatorViewController.swift
//  Provenance
//
//  Created by James Addyman on 14/08/2013.
//  Copyright (c) 2013 James Addyman. All rights reserved.
//

import PVSupport
import QuartzCore
import UIKit
import RealmSwift
import PVLibrary
import GameController

#if os(iOS)
import XLActionController
#endif

private weak var staticSelf: PVEmulatorViewController?

func uncaughtExceptionHandler(exception: NSException?) {
    if let staticSelf =  staticSelf, staticSelf.core.supportsSaveStates {
        do {
            try staticSelf.autoSaveState()
        } catch {
            ELOG("\(error.localizedDescription)")
        }
    }
}

public enum SaveStateError: Error {
	case saveStatesUnsupportedByCore
	case failedToSave(isAutosave: Bool)
}

#if os(tvOS)
typealias PVEmulatorViewControllerRootClass = GCEventViewController
#else
typealias PVEmulatorViewControllerRootClass = UIViewController
#endif

extension UIViewController {
	func presentMessage(_ message : String, title: String, completion: (() -> Swift.Void)? = nil) {
		let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

		let presentingVC = self.presentedViewController ?? self

		if presentingVC.isBeingDismissed || presentingVC.isBeingPresented {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
				presentingVC.present(alert, animated: true, completion: nil)
			}
		} else {
			presentingVC.present(alert, animated: true, completion: nil)
		}
	}

	func presentError(_ message : String, completion: (() -> Swift.Void)? = nil) {
		ELOG("\(message)")
		presentMessage(message, title: "Error", completion: completion)
	}

	func presentWarning(_ message : String, completion: (() -> Swift.Void)? = nil) {
		WLOG("\(message)")
		presentMessage(message, title: "Warning", completion: completion)
	}
}

final class PVEmulatorViewController: PVEmulatorViewControllerRootClass, PVAudioDelegate, PVSaveStatesViewControllerDelegate {

    var core: PVEmulatorCore
    var game: PVGame
    var system: PVSystem

    var batterySavesPath = ""
    var saveStatePath = ""
    var BIOSPath = ""
    var menuButton: UIButton?

	private(set) var glViewController: PVGLViewController?
    var gameAudio: OEGameAudio!
    let controllerViewController: (UIViewController & StartSelectDelegate)?
    var fpsTimer: Timer?
    var fpsLabel: UILabel?
    var secondaryScreen: UIScreen?
    var secondaryWindow: UIWindow?
    var menuGestureRecognizer: UITapGestureRecognizer?

    var isShowingMenu: Bool = false

    let minimumPlayTimeToMakeAutosave : Double = 60
    
    var hasMFiPlus = false
    var shouldShowMFiPlusDemo = false
    var mFiPlusComboView: UIView?
    var mFiPlusComboViewIsActive = false
    var mfiPlusisActive = false
    var mFiPlusControllerTopView = UIImageView(image: #imageLiteral(resourceName: "mFi-HUD-comboExtOFF").withRenderingMode(.alwaysOriginal))
    var mFiPlusControllerCombo = UIImageView(image: #imageLiteral(resourceName: "mFi-HUD-comboLR12").withRenderingMode(.alwaysOriginal))
    var mFiPlusHUDDPadView: UIView?
    var mFiPlusHUDDPadLeft: UIImageView?
    var mFiPlusHUDDPadUp: UIImageView?
    var mFiPlusHUDDPadDown: UIImageView?
    var mFiPlusHUDDPadRight: UIImageView?
    var mFiPlusHUDDPadLeftLabel: UILabel?
    var mFiPlusHUDDPadUpLabel: UILabel?
    var mFiPlusHUDDPadDownLabel: UILabel?
    var mFiPlusHUDDPadRightLabel: UILabel?
    var mFiPlusHUDButtonsView: UIView?
    var mFiPlusHUDButtonX: UIView?
    var mFiPlusHUDButtonY: UIView?
    var mFiPlusHUDButtonA: UIView?
    var mFiPlusHUDButtonB: UIView?
    var mFiPlusHUDButtonXLabel: UILabel?
    var mFiPlusHUDButtonYLabel: UILabel?
    var mFiPlusHUDButtonALabel: UILabel?
    var mFiPlusHUDButtonBLabel: UILabel?
    var mFiPlusHUDGradientView: UIView?
    var mFiPlusHUDGradientLayer: CAGradientLayer!
    
    var mFiButtonXisPressed = false
    var mFiButtonYisPressed = false
    var mFiButtonAisPressed = false
    var mFiButtonBisPressed = false
    var mFiDPadLeftisPressed = false
    var mFiDPadUpisPressed = false
    var mFiDPadDownisPressed = false
    var mFiDPadRightisPressed = false
    var shouldWaitToShowMFiDemo = false

    required init(game: PVGame, core: PVEmulatorCore, system: PVSystem) {
        self.core = core
        self.game = game
        self.system = system

        controllerViewController = PVCoreFactory.controllerViewController(forSystem: game.system, core: core)

        super.init(nibName: nil, bundle: nil)

		staticSelf = self

        if PVSettingsModel.shared.autoSave {
            NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)
        } else {
            NSSetUncaughtExceptionHandler(nil)
        }

		// Add KVO watcher for isRunning state so we can update play time
		core.addObserver(self, forKeyPath: "isRunning", options: .new, context: nil)
    }

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
		if keyPath == "isRunning" {
			if core.isRunning {
				if gameStartTime != nil {
					ELOG("Didn't expect to get a KVO update of isRunning to true while we still have an unflushed gameStartTime variable")
				}
				gameStartTime = Date()
			} else {
				DispatchQueue.main.async { [weak self] in
					self?.updatePlayedDuration()
				}
			}
		}
	}

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
		// These need to be first or mutli-threaded cores can cause crashes on close
		NotificationCenter.default.removeObserver(self)
		core.removeObserver(self, forKeyPath: "isRunning")

        core.stopEmulation()
        //Leave emulation loop first
        gameAudio?.stop()
        NSSetUncaughtExceptionHandler(nil)
        staticSelf = nil
        controllerViewController?.willMove(toParentViewController: nil)
        controllerViewController?.view?.removeFromSuperview()
        controllerViewController?.removeFromParentViewController()
        glViewController?.willMove(toParentViewController: nil)
        glViewController?.view?.removeFromSuperview()
        glViewController?.removeFromParentViewController()
#if os(iOS)
    GCController.controllers().forEach { $0.controllerPausedHandler = nil }
#endif
        updatePlayedDuration()
		destroyAutosaveTimer()

		if let menuGestureRecognizer = menuGestureRecognizer {
			view.removeGestureRecognizer(menuGestureRecognizer)
		}
    }

	private func initNotifcationObservers() {
		NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.appWillEnterForeground(_:)), name: .UIApplicationWillEnterForeground, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.appDidEnterBackground(_:)), name: .UIApplicationDidEnterBackground, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.appWillResignActive(_:)), name: .UIApplicationWillResignActive, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.appDidBecomeActive(_:)), name: .UIApplicationDidBecomeActive, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.controllerDidConnect(_:)), name: .GCControllerDidConnect, object: nil)
//        NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.connectControllers(_:)), name: .GCControllerDidConnect, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.controllerDidDisconnect(_:)), name: .GCControllerDidDisconnect, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.screenDidConnect(_:)), name: .UIScreenDidConnect, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.screenDidDisconnect(_:)), name: .UIScreenDidDisconnect, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.handleControllerManagerControllerReassigned(_:)), name: .PVControllerManagerControllerReassigned, object: nil)
	}

	private func initCore() {
		core.audioDelegate = self
		core.saveStatesPath = self.saveStatePath
		core.batterySavesPath = batterySavesPath
		core.biosPath = BIOSPath
		core.controller1 = PVControllerManager.shared.player1
		core.controller2 = PVControllerManager.shared.player2
		core.controller3 = PVControllerManager.shared.player3
		core.controller4 = PVControllerManager.shared.player4

		let md5Hash: String = game.md5Hash
		core.romMD5 = md5Hash
		core.romSerial = game.romSerial
	}

	private func initMenuButton() {
		//        controllerViewController = PVCoreFactory.controllerViewController(forSystem: game.system, core: core)
		if let aController = controllerViewController {
			addChildViewController(aController)
		}
		if let aView = controllerViewController?.view {
			view.addSubview(aView)
		}
		controllerViewController?.didMove(toParentViewController: self)

		let alpha: CGFloat = PVSettingsModel.sharedInstance().controllerOpacity
		menuButton = UIButton(type: .custom)
		menuButton?.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleBottomMargin]
		menuButton?.setImage(UIImage(named: "button-menu"), for: .normal)
		menuButton?.setImage(UIImage(named: "button-menu-pressed"), for: .highlighted)
		// Commenting out title label for now (menu has changed to graphic only)
		//[self.menuButton setTitle:@"Menu" forState:UIControlStateNormal];
		//menuButton?.titleLabel?.font = UIFont.systemFont(ofSize: 12)
		//menuButton?.setTitleColor(UIColor.white, for: .normal)
		menuButton?.layer.shadowOffset = CGSize(width: 0, height: 1)
		menuButton?.layer.shadowRadius = 3.0
		menuButton?.layer.shadowColor = UIColor.black.cgColor
		menuButton?.layer.shadowOpacity = 0.75
		menuButton?.tintColor = UIColor.white
		menuButton?.alpha = alpha
		menuButton?.addTarget(self, action: #selector(PVEmulatorViewController.showMenu(_:)), for: .touchUpInside)
		view.addSubview(menuButton!)
	}

	private func initFPSLabel() {
		fpsLabel = UILabel()
		fpsLabel?.textColor = UIColor.yellow
		fpsLabel?.text = "\(glViewController?.framesPerSecond ?? 0)"
		fpsLabel?.translatesAutoresizingMaskIntoConstraints = false
		fpsLabel?.textAlignment = .right
		#if os(tvOS)
		fpsLabel?.font = UIFont.systemFont(ofSize: 100, weight: .bold)
		#else
		if #available(iOS 8.2, *) {
			fpsLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
		}
		#endif
		if let aLabel = fpsLabel {
			glViewController?.view.addSubview(aLabel)
		}
		if let aLabel = fpsLabel {
			view.addConstraint(NSLayoutConstraint(item: aLabel, attribute: .top, relatedBy: .equal, toItem: glViewController?.view, attribute: .top, multiplier: 1.0, constant: 30))
		}
		if let aLabel = fpsLabel {
			view.addConstraint(NSLayoutConstraint(item: aLabel, attribute: .right, relatedBy: .equal, toItem: glViewController?.view, attribute: .right, multiplier: 1.0, constant: -40))
		}

		if #available(iOS 10.0, tvOS 10.0, *) {
			// Block-based NSTimer method is only available on iOS 10 and later
			fpsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true, block: {(_ timer: Timer) -> Void in
				if self.core.renderFPS == self.core.emulationFPS {
					self.fpsLabel?.text = String(format: "%2.02f", self.core.renderFPS)
				} else {
					self.fpsLabel?.text = String(format: "%2.02f (%2.02f)", self.core.renderFPS, self.core.emulationFPS)
				}
			})
		} else {

			// Use traditional scheduledTimerWithTimeInterval method on older version of iOS
			fpsTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(self.updateFPSLabel), userInfo: nil, repeats: true)
			fpsTimer?.fire()
		}
	}

	// TODO: This method is way too big, break it up
    override func viewDidLoad() {
        super.viewDidLoad()
        title = game.title
        view.backgroundColor = UIColor.black

		initNotifcationObservers()
		initCore()

        NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.appWillEnterForeground(_:)), name: .UIApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.appDidEnterBackground(_:)), name: .UIApplicationDidEnterBackground, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.appWillResignActive(_:)), name: .UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.appDidBecomeActive(_:)), name: .UIApplicationDidBecomeActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.controllerDidConnect(_:)), name: .GCControllerDidConnect, object: nil)
//        NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.connectControllers(_:)), name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.controllerDidDisconnect(_:)), name: .GCControllerDidDisconnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.screenDidConnect(_:)), name: .UIScreenDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.screenDidDisconnect(_:)), name: .UIScreenDidDisconnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(PVEmulatorViewController.handleControllerManagerControllerReassigned(_:)), name: .PVControllerManagerControllerReassigned, object: nil)

        core.audioDelegate = self
        core.saveStatesPath = self.saveStatePath
        core.batterySavesPath = batterySavesPath
        core.biosPath = BIOSPath
        core.controller1 = PVControllerManager.shared.player1
        core.controller2 = PVControllerManager.shared.player2
        core.controller3 = PVControllerManager.shared.player3
        core.controller4 = PVControllerManager.shared.player4

        let md5Hash: String = game.md5Hash
        core.romMD5 = md5Hash
        core.romSerial = game.romSerial
        glViewController = PVGLViewController(emulatorCore: core)

            // Load now. Moved here becauase Mednafen needed to know what kind of game it's working with in order
            // to provide the correct data for creating views.
		let m3uFile: URL? = PVEmulatorConfiguration.m3uFile(forGame: game)
		let romPathMaybe: URL? = m3uFile ?? game.file.url

		guard let romPath = romPathMaybe else {
			presentingViewController?.presentError("Game has a nil rom path.")
			return
		}

//		guard FileManager.default.fileExists(atPath: romPath.absoluteString) else {
//			ELOG("File doesn't exist at path \(romPath.absoluteString)")
//			presentingViewController?.presentError("File doesn't exist at path \(romPath.absoluteString)")
//			return
//		}

        do {
            try core.loadFile(atPath: romPath.path)
        } catch {
            let alert = UIAlertController(title: error.localizedDescription, message: (error as NSError).localizedRecoverySuggestion, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: {(_ action: UIAlertAction) -> Void in
				self.dismiss(animated: true, completion: nil)
			}))
            let code = (error as NSError).code
            if code == PVEmulatorCoreErrorCode.missingM3U.rawValue {
                alert.addAction(UIAlertAction(title: "View Wiki", style: .cancel, handler: {(_ action: UIAlertAction) -> Void in
                    if let aString = URL(string: "https://bitly.com/provm3u") {
                        UIApplication.shared.openURL(aString)
                    }
                }))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: { [weak self] in
                self?.present(alert, animated: true) {() -> Void in }
            })

            return
        }

        if UIScreen.screens.count > 1 {
            secondaryScreen = UIScreen.screens[1]
            if let aBounds = secondaryScreen?.bounds {
                secondaryWindow = UIWindow(frame: aBounds)
            }
            if let aScreen = secondaryScreen {
                secondaryWindow?.screen = aScreen
            }
            secondaryWindow?.rootViewController = glViewController
            glViewController?.view?.frame = secondaryWindow?.bounds ?? .zero
            if let aView = glViewController?.view {
                secondaryWindow?.addSubview(aView)
            }
            secondaryWindow?.isHidden = false
        } else {
            if let aController = glViewController {
                addChildViewController(aController)
            }
            if let aView = glViewController?.view {
                view.addSubview(aView)
            }
            glViewController?.didMove(toParentViewController: self)
        }
		#if os(iOS)
		initMenuButton()
		#endif

        if PVSettingsModel.sharedInstance().showFPSCount {
			initFPSLabel()
        }

#if !targetEnvironment(simulator)
        if GCController.controllers().count != 0 {
            menuButton?.isHidden = true
        }
#endif

		convertOldSaveStatesToNewIfNeeded()

        core.startEmulation()

        gameAudio = OEGameAudio(core: core)
        gameAudio?.volume = PVSettingsModel.sharedInstance().volume
        gameAudio?.outputDeviceID = 0
        gameAudio?.start()

        // stupid bug in tvOS 9.2
        // the controller paused handler (if implemented) seems to cause a 'back' navigation action
        // as well as calling the pause handler itself. Which breaks the menu functionality.
        // But of course, this isn't the case on iOS 9.3. YAY FRAGMENTATION. ¬_¬
        // Conditionally handle the pause menu differently dependning on tvOS or iOS. FFS.
#if os(tvOS)
        // Adding a tap gesture recognizer for the menu type will override the default 'back' functionality of tvOS
        if menuGestureRecognizer == nil {
            menuGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(PVEmulatorViewController.controllerPauseButtonPressed(_:)))
            menuGestureRecognizer?.allowedPressTypes = [.menu]
        }
        if let aRecognizer = menuGestureRecognizer {
			view.addGestureRecognizer(aRecognizer)
        }
#else
        GCController.controllers().forEach { [unowned self] in
            $0.controllerPausedHandler = { controller in
                self.controllerPauseButtonPressed(controller)
            }
        }
#endif
        
        // Setup MFi+ Views
        if system.shortName == "N64" || system.shortName == "PSX" {
            hasMFiPlus = true
        }
        
        if PVControllerManager.shared.hasControllers && hasMFiPlus {
            PVControllerManager.shared.allLiveControllers.forEach({ (key, controller) in
                self.setupMFiPlusViews(for: controller)
                self.shouldShowMFiPlusDemo = true
            })
        }
        
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        //Notifies UIKit that your view controller updated its preference regarding the visual indicator

        #if os(iOS)
        if #available(iOS 11.0, *) {
            setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
        #endif

		if PVSettingsModel.shared.timedAutoSaves {
			createAutosaveTimer()
		}
        
        // If Should… Show MFi+ Demo
        if shouldShowMFiPlusDemo && !mFiPlusComboViewIsActive {
            showMFiPlusDemo()
            showMFiPlusHUD()
        }
        connectControllers()
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
		destroyAutosaveTimer()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        #if os(iOS)
        //Ignore Smart Invert
        self.view.ignoresInvertColors = true
        #endif
        
        // (Re)Layout MFi+ Views
        layoutMFiPlusCombo()
        layoutMFiPlusHUD()
    }
    
    open override func didMove(toParentViewController parent: UIViewController?) {
        super.didMove(toParentViewController: parent)
        
        // If Should… Show MFi+ Demo
//        connectControllers()
//        if shouldShowMFiPlusCombo && !mFiPlusComboViewIsActive {
//            showMFiPlusCombo()
//            showMFiPlusHUD()
//        }
    }
    
	var autosaveTimer : Timer?
	func destroyAutosaveTimer() {
		autosaveTimer?.invalidate()
		autosaveTimer = nil
	}
	func createAutosaveTimer() {
		autosaveTimer?.invalidate()
		if #available(iOS 10.0, tvOS 10.0, *) {
			let interval = PVSettingsModel.shared.timedAutoSaveInterval
			autosaveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true, block: { (timer) in
				DispatchQueue.main.async {
					let image = self.captureScreenshot()
					do {
						try self.createNewSaveState(auto: true, screenshot: image)
					} catch {
						ELOG("Autosave timer failed to make save state: \(error.localizedDescription)")
					}
				}
			})
		} else {
			// Fallback on earlier versions
		}
	}

	var gameStartTime : Date?
    @objc
    public func updatePlayedDuration() {
		defer {
			// Clear any temp pointer to start time
			self.gameStartTime = nil
		}
		guard let gameStartTime = gameStartTime else {
			return
		}

		// Calcuate what the new total spent time should be
		let duration = gameStartTime.timeIntervalSinceNow * -1
		let totalTimeSpent = game.timeSpentInGame + Int(duration)
		ILOG("Played for duration \(duration). New total play time: \(totalTimeSpent) for \(game.title)")
		// Write that to the database
		do {
			try RomDatabase.sharedInstance.writeTransaction {
				game.timeSpentInGame = totalTimeSpent
			}
		} catch {
			presentError("\(error.localizedDescription)")
		}
    }

    @objc public func updateLastPlayedTime() {
		ILOG("Updating last played")
        do {
            try RomDatabase.sharedInstance.writeTransaction {
                game.lastPlayed = Date()
            }
        } catch {
            presentError("\(error.localizedDescription)")
        }
    }

#if os(iOS) && !(arch(i386) || arch(x86_64))
    //Check Controller Manager if it has a Controller connected and thus if Home Indicator should hide…
    override func prefersHomeIndicatorAutoHidden() -> Bool {
        let shouldHideHomeIndicator: Bool = PVControllerManager.shared.hasControllers
        return shouldHideHomeIndicator
    }

#endif

#if os(iOS)
    var safeAreaInsets: UIEdgeInsets {
        if #available(iOS 11.0, tvOS 11.0, *) {
            return view.safeAreaInsets
        } else {
            return UIEdgeInsets.zero
        }
    }
#endif

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
#if os(iOS)
        layoutMenuButton()
#endif
        // (Re)Layout MFi+ Views
        layoutMFiPlusCombo()
        layoutMFiPlusHUD()
        
        // If Should… Show MFi+ Demo
        if shouldShowMFiPlusDemo {
            showMFiPlusDemo()
            mFiPlusComboViewIsActive = true
        }

    }

#if os(iOS)
    func layoutMenuButton() {
        if let menuButton = self.menuButton {
            let height: CGFloat = 42
            let width: CGFloat = 42
            menuButton.imageView?.contentMode = .center
            let frame = CGRect(x: safeAreaInsets.left + 10, y: safeAreaInsets.top + 5, width: width, height: height)
            menuButton.frame = frame
        }
    }
#endif
    func documentsPath() -> String? {
#if os(tvOS)
        let paths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
#else
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
#endif
        let documentsDirectoryPath: String = paths[0]
        return documentsDirectoryPath
    }

    #if os(iOS)
    override var prefersStatusBarHidden: Bool {
        return true
    }

    override func preferredScreenEdgesDeferringSystemGestures() -> UIRectEdge {
        return .bottom
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    #endif

    @objc func appWillEnterForeground(_ note: Notification?) {
        updateLastPlayedTime()
    }

    @objc func appDidEnterBackground(_ note: Notification?) {

	}

    @objc func appWillResignActive(_ note: Notification?) {
		if PVSettingsModel.sharedInstance().autoSave, core.supportsSaveStates {
			do {
				try autoSaveState()
			} catch {
				ELOG("Auto-save failed \(error.localizedDescription)")
			}
		}
        gameAudio?.pause()
        showMenu(self)
    }

    @objc func appDidBecomeActive(_ note: Notification?) {
        if !isShowingMenu {
            core.setPauseEmulation(false)
        }
        core.setPauseEmulation(true)
        gameAudio?.start()
    }

    func enableControllerInput(_ enabled: Bool) {
#if os(tvOS)
        controllerUserInteractionEnabled = enabled
#else
        // Can enable when we change to iOS 10 base
        // and change super class to GCEventViewController
        //    if (@available(iOS 10, *)) {
        //        self.controllerUserInteractionEnabled = enabled;
        //    }
#endif
    }
    
    func connectControllers() {
        for controller in GCController.controllers() {
            if (controller.extendedGamepad != nil ) {
                controller.extendedGamepad?.valueChangedHandler = nil
                setUpExtendedController(controller: controller)
            }  else if (controller.gamepad != nil ) {
                controller.gamepad?.valueChangedHandler = nil
                setUpStandardController(controller: controller)
            }
        }
    }
    
    func setUpExtendedController(controller: GCController) {
        controller.extendedGamepad?.valueChangedHandler = {
            (gamepad: GCExtendedGamepad, element:GCControllerElement) in
            
            if self.system.shortName == "PSX" && gamepad.leftShoulder.isPressed && gamepad.rightShoulder.isPressed && gamepad.rightTrigger.isPressed && gamepad.leftTrigger.isPressed == true {
                self.mfiPlusisActive = true
            } else if self.system.shortName == "N64" && gamepad.leftShoulder.isPressed && gamepad.rightShoulder.isPressed {
                self.mfiPlusisActive = true
            } else {
                self.mfiPlusisActive = false
            }
            
            
            //Check D-Pad States
            if (gamepad.dpad == element) {
                if gamepad.dpad.left.isPressed {
                    self.mFiDPadLeftisPressed = true
                } else if !gamepad.dpad.left.isPressed {
                    self.mFiDPadLeftisPressed = false
                }
                if gamepad.dpad.up.isPressed {
                    self.mFiDPadUpisPressed = true
                } else if !gamepad.dpad.up.isPressed {
                    self.mFiDPadUpisPressed = false
                }
                if gamepad.dpad.down.isPressed {
                    self.mFiDPadDownisPressed = true
                } else if !gamepad.dpad.down.isPressed {
                    self.mFiDPadDownisPressed = false
                }
                if gamepad.dpad.right.isPressed {
                    self.mFiDPadRightisPressed = true
                } else if !gamepad.dpad.right.isPressed {
                    self.mFiDPadRightisPressed = false
                }
            }
                
                //Check Button States
            else if (gamepad.buttonX == element) {
                if gamepad.buttonX.isPressed {
                    self.mFiButtonXisPressed = true
                } else if !gamepad.buttonX.isPressed {
                    self.mFiButtonXisPressed = false
                }
            } else if (gamepad.buttonY == element) {
                if gamepad.buttonY.isPressed{
                    self.mFiButtonYisPressed = true
                } else if !gamepad.buttonY.isPressed {
                    self.mFiButtonYisPressed = false
                }
            } else if (gamepad.buttonA == element) {
                if gamepad.buttonA.isPressed{
                    self.mFiButtonAisPressed = true
                } else if !gamepad.buttonA.isPressed {
                    self.mFiButtonAisPressed = false
                }
            } else if (gamepad.buttonB == element) {
                if gamepad.buttonB.isPressed {
                    self.mFiButtonBisPressed = true
                } else if !gamepad.buttonB.isPressed {
                    self.mFiButtonBisPressed = false
                }
            }
            
            self.updateMFiHUD()
            
            if self.mfiPlusisActive {
                if self.mFiPlusHUDButtonsView?.alpha == 0.0 {
                    self.showMFiPlusHUD()
                }
            } else if !self.mFiPlusComboViewIsActive {
                self.hideMFiPlusHUD()
            }
            
        }
    }
    
    func setUpStandardController(controller: GCController) {
        controller.gamepad?.valueChangedHandler = {
            (gamepad: GCGamepad, element:GCControllerElement) in
            
            if self.system.shortName == "PSX" && gamepad.leftShoulder.isPressed && gamepad.rightShoulder.isPressed {
                self.mfiPlusisActive = true
            } else if self.system.shortName == "N64" && gamepad.rightShoulder.isPressed {
                self.mfiPlusisActive = true
            } else {
                self.mfiPlusisActive = false
            }
            
            //Check D-Pad States
            if (gamepad.dpad == element) {
                if gamepad.dpad.left.isPressed {
                    self.mFiDPadLeftisPressed = true
                } else if !gamepad.dpad.left.isPressed {
                    self.mFiDPadLeftisPressed = false
                }
                if gamepad.dpad.up.isPressed {
                    self.mFiDPadUpisPressed = true
                } else if !gamepad.dpad.up.isPressed {
                    self.mFiDPadUpisPressed = false
                }
                if gamepad.dpad.down.isPressed {
                    self.mFiDPadDownisPressed = true
                } else if !gamepad.dpad.down.isPressed {
                    self.mFiDPadDownisPressed = false
                }
                if gamepad.dpad.right.isPressed {
                    self.mFiDPadRightisPressed = true
                } else if !gamepad.dpad.right.isPressed {
                    self.mFiDPadRightisPressed = false
                }
            }
                
                //Check Button States
            else if (gamepad.buttonX == element) {
                if gamepad.buttonX.isPressed {
                    self.mFiButtonXisPressed = true
                } else if !gamepad.buttonX.isPressed {
                    self.mFiButtonXisPressed = false
                }
            } else if (gamepad.buttonY == element) {
                if gamepad.buttonY.isPressed{
                    self.mFiButtonYisPressed = true
                } else if !gamepad.buttonY.isPressed {
                    self.mFiButtonYisPressed = false
                }
            } else if (gamepad.buttonA == element) {
                if gamepad.buttonA.isPressed{
                    self.mFiButtonAisPressed = true
                } else if !gamepad.buttonA.isPressed {
                    self.mFiButtonAisPressed = false
                }
            } else if (gamepad.buttonB == element) {
                if gamepad.buttonB.isPressed {
                    self.mFiButtonBisPressed = true
                } else if !gamepad.buttonB.isPressed {
                    self.mFiButtonBisPressed = false
                }
            }
            
            self.updateMFiHUD()
            
            if self.mfiPlusisActive {
                if self.mFiPlusHUDButtonsView?.alpha == 0.0 {
                    self.showMFiPlusHUD()
                }
            } else if !self.mFiPlusComboViewIsActive {
                self.hideMFiPlusHUD()
            }
            
            
        }
    }
    
    func updateMFiHUD() {
        
        let assignedButtonColor = UIColor(white: 1.0, alpha: 0.85)
        //        let assignedButtonBorder = 1.5
        //        let pressedButtonBorder = 0.0
        let assignedLabelColor = UIColor(white: 1.0, alpha: 0.65)
        let pressedColor = UIColor(white: 1.0, alpha: 1.0)
        
        //D-Pad Updates
        if mFiDPadLeftisPressed {
            mFiPlusHUDDPadLeft?.image = #imageLiteral(resourceName: "mFi-HUD-DPad-Press-Left").withRenderingMode(.alwaysOriginal)
            mFiPlusHUDDPadLeftLabel?.textColor = pressedColor
        } else {
            mFiPlusHUDDPadLeft?.image = #imageLiteral(resourceName: "mFi-HUD-DPad-HiLi-Left").withRenderingMode(.alwaysOriginal)
            mFiPlusHUDDPadLeftLabel?.textColor = assignedLabelColor
        }
        if mFiDPadUpisPressed {
            mFiPlusHUDDPadUp?.image = #imageLiteral(resourceName: "mFi-HUD-DPad-Press-Up").withRenderingMode(.alwaysOriginal)
            mFiPlusHUDDPadUpLabel?.textColor = pressedColor
        } else {
            mFiPlusHUDDPadUp?.image = #imageLiteral(resourceName: "mFi-HUD-DPad-HiLi-Up").withRenderingMode(.alwaysOriginal)
            mFiPlusHUDDPadUpLabel?.textColor = assignedLabelColor
        }
        if mFiDPadDownisPressed {
            mFiPlusHUDDPadDown?.image = #imageLiteral(resourceName: "mFi-HUD-DPad-Press-Down").withRenderingMode(.alwaysOriginal)
            mFiPlusHUDDPadDownLabel?.textColor = pressedColor
        } else {
            mFiPlusHUDDPadDown?.image = #imageLiteral(resourceName: "mFi-HUD-DPad-HiLi-Down").withRenderingMode(.alwaysOriginal)
            mFiPlusHUDDPadDownLabel?.textColor = assignedLabelColor
        }
        if mFiDPadRightisPressed {
            mFiPlusHUDDPadRight?.image = #imageLiteral(resourceName: "mFi-HUD-DPad-Press-Right").withRenderingMode(.alwaysOriginal)
            mFiPlusHUDDPadRightLabel?.textColor = pressedColor
        } else {
            mFiPlusHUDDPadRight?.image = #imageLiteral(resourceName: "mFi-HUD-DPad-HiLi-Right").withRenderingMode(.alwaysOriginal)
            mFiPlusHUDDPadRightLabel?.textColor = assignedLabelColor
        }
        
        if mFiButtonXisPressed && mFiPlusHUDButtonX?.borderColor == assignedButtonColor {
            mFiPlusHUDButtonX?.backgroundColor = pressedColor
            mFiPlusHUDButtonXLabel?.textColor = pressedColor
        } else {
            mFiPlusHUDButtonX?.backgroundColor = .clear
            mFiPlusHUDButtonXLabel?.textColor = assignedLabelColor
        }
        if mFiButtonYisPressed && mFiPlusHUDButtonY?.borderColor == assignedButtonColor {
            mFiPlusHUDButtonY?.backgroundColor = pressedColor
            mFiPlusHUDButtonYLabel?.textColor = pressedColor
        } else {
            mFiPlusHUDButtonY?.backgroundColor = .clear
            mFiPlusHUDButtonYLabel?.textColor = assignedLabelColor
        }
        if mFiButtonAisPressed && mFiPlusHUDButtonA?.borderColor == assignedButtonColor {
            mFiPlusHUDButtonA?.backgroundColor = pressedColor
            mFiPlusHUDButtonALabel?.textColor = pressedColor
        } else {
            mFiPlusHUDButtonA?.backgroundColor = .clear
            mFiPlusHUDButtonALabel?.textColor = assignedLabelColor
        }
        if mFiButtonBisPressed && mFiPlusHUDButtonB?.borderColor == assignedButtonColor {
            mFiPlusHUDButtonB?.backgroundColor = pressedColor
            mFiPlusHUDButtonBLabel?.textColor = pressedColor
        } else {
            mFiPlusHUDButtonB?.backgroundColor = .clear
            mFiPlusHUDButtonBLabel?.textColor = assignedLabelColor
        }
    }
    
    func setupMFiPlusViews(for controller: GCController) {
        let yPadding: CGFloat = 54
        #if os(iOS)
        var safeAreaInsets: UIEdgeInsets {
            if #available(iOS 11.0, tvOS 11.0, *) {
                return view.safeAreaInsets
            } else {
                return UIEdgeInsets.zero
            }
        }
        let margin = safeAreaInsets
        #else
        let margin = UIEdgeInsets.zero
        #endif
        let comboFrame = CGRect(x: (UIScreen.main.bounds.width / 2) - ((mFiPlusControllerTopView.image?.size.width)! / 2), y: margin.top + yPadding, width: (mFiPlusControllerTopView.image?.size.width)!, height: (mFiPlusControllerTopView.image?.size.height)!)
        let gradientHeight: CGFloat =  187
        let gradientFrame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: gradientHeight)
        mFiPlusComboView = UIView(frame: comboFrame)
        mFiPlusHUDGradientView = UIView(frame: gradientFrame)
        mFiPlusHUDGradientLayer = CAGradientLayer()
        mFiPlusHUDGradientLayer.frame = (mFiPlusHUDGradientView?.bounds)!
        mFiPlusHUDGradientLayer.colors = [UIColor.black.withAlphaComponent(0.77).cgColor, UIColor.clear.cgColor]
        mFiPlusHUDGradientView?.layer.addSublayer(mFiPlusHUDGradientLayer)
        mFiPlusHUDGradientView?.alpha = 0.0
        self.view.addSubview(mFiPlusHUDGradientView!)
        
        setupMFiPlusHUD()
        updateMFiPlusViews(for: controller)
        mFiPlusComboView?.addSubview(mFiPlusControllerTopView)
        mFiPlusComboView?.addSubview(mFiPlusControllerCombo)
        mFiPlusComboView?.alpha = 0.0
        self.view.addSubview(mFiPlusComboView!)
        mFiPlusComboView?.superview?.bringSubview(toFront: mFiPlusComboView!)
        
        let assignedButtonColor = UIColor(white: 1.0, alpha: 0.85)
        let assignedLabelColor = UIColor(white: 1.0, alpha: 0.65)
        switch system.shortName {
        case "PSX":
            mFiPlusHUDDPadRightLabel?.text = "SELECT"
            mFiPlusHUDDPadRightLabel?.textColor = assignedLabelColor
            mFiPlusHUDDPadRight?.isHidden = false
            mFiPlusHUDButtonXLabel?.text = "START"
            mFiPlusHUDButtonXLabel?.textColor = assignedLabelColor
            mFiPlusHUDButtonX?.borderColor = assignedButtonColor
            mFiPlusHUDDPadDownLabel?.text = "L3"
            mFiPlusHUDDPadDownLabel?.textColor = assignedLabelColor
            mFiPlusHUDDPadDown?.isHidden = false
            mFiPlusHUDButtonALabel?.text = "R3"
            mFiPlusHUDButtonALabel?.textColor = assignedLabelColor
            mFiPlusHUDButtonA?.borderColor = assignedButtonColor
        case "N64":
            mFiPlusHUDButtonXLabel?.text = "C◀"
            mFiPlusHUDButtonYLabel?.text = "C▲"
            mFiPlusHUDButtonALabel?.text = "C▼"
            mFiPlusHUDButtonBLabel?.text = "C▶"
            mFiPlusHUDButtonXLabel?.textColor = assignedLabelColor
            mFiPlusHUDButtonYLabel?.textColor = assignedLabelColor
            mFiPlusHUDButtonALabel?.textColor = assignedLabelColor
            mFiPlusHUDButtonBLabel?.textColor = assignedLabelColor
//            mFiPlusHUDDPadRightLabel?.text = "START"
//            mFiPlusHUDDPadRightLabel?.textColor = assignedLabelColor
//            mFiPlusHUDDPadRight?.isHidden = false
            mFiPlusHUDButtonX?.borderColor = assignedButtonColor
            mFiPlusHUDButtonY?.borderColor = assignedButtonColor
            mFiPlusHUDButtonA?.borderColor = assignedButtonColor
            mFiPlusHUDButtonB?.borderColor = assignedButtonColor
        default:
            break
        }
    }
    
    func updateMFiPlusViews(for controller: GCController) {
        if (controller.extendedGamepad != nil) {
            mFiPlusControllerTopView.image = #imageLiteral(resourceName: "mFi-HUD-comboExtOFF").withRenderingMode(.alwaysOriginal)
        } else if (controller.gamepad != nil) {
            mFiPlusControllerTopView.image = #imageLiteral(resourceName: "mFi-HUD-comboStdOFF").withRenderingMode(.alwaysOriginal)
        }
        
        switch system.shortName {
        case "PSX":
            if (controller.extendedGamepad != nil) {
                mFiPlusControllerCombo.image = #imageLiteral(resourceName: "mFi-HUD-comboLR12").withRenderingMode(.alwaysOriginal)
            } else if (controller.gamepad != nil) {
                mFiPlusControllerCombo.image = #imageLiteral(resourceName: "mFi-HUD-comboLR1").withRenderingMode(.alwaysOriginal)
            }
        case "N64":
            if (controller.extendedGamepad != nil) {
                mFiPlusControllerCombo.image = #imageLiteral(resourceName: "mFi-HUD-comboLR1").withRenderingMode(.alwaysOriginal)
            } else if (controller.gamepad != nil) {
                mFiPlusControllerCombo.image = #imageLiteral(resourceName: "mFi-HUD-comboR1").withRenderingMode(.alwaysOriginal)
            }
        default:
            break
        }
        
        layoutMFiPlusCombo()
        layoutMFiPlusHUD()
    }
    
    func pulseMFiCombo() {
        UIView.animate(withDuration: 0.6, delay: 0.1, options: [.curveEaseInOut], animations: {
            self.mFiPlusControllerCombo.alpha = 1.0
            self.mFiPlusHUDButtonsView?.alpha = 1.0
            self.mFiPlusHUDDPadView?.alpha = 1.0
        }, completion: { (finished: Bool) in
            UIView.animate(withDuration: 0.6, delay: 0.1, options: [.curveEaseInOut], animations: {
                self.mFiPlusControllerCombo.alpha = 0.0
                self.mFiPlusHUDButtonsView?.alpha = 0.6
                self.mFiPlusHUDDPadView?.alpha = 0.6
            }, completion: { (finished: Bool) in
                UIView.animate(withDuration: 0.3, delay: 0.1, options: [.curveEaseInOut], animations: {
                    self.mFiPlusControllerCombo.alpha = 1.0
                    self.mFiPlusHUDButtonsView?.alpha = 1.0
                    self.mFiPlusHUDDPadView?.alpha = 1.0
                }, completion: { (finished: Bool) in
                    UIView.animate(withDuration: 0.6, delay: 0.1, options: [.curveEaseInOut], animations: {
                        self.mFiPlusControllerCombo.alpha = 0.0
                        self.mFiPlusHUDButtonsView?.alpha = 0.6
                        self.mFiPlusHUDDPadView?.alpha = 0.6
                    }, completion: { (finished: Bool) in
                        UIView.animate(withDuration: 0.3, delay: 0.1, options: [.curveEaseInOut], animations: {
                            self.mFiPlusControllerCombo.alpha = 1.0
                            self.mFiPlusHUDButtonsView?.alpha = 1.0
                            self.mFiPlusHUDDPadView?.alpha = 1.0
                        }, completion: { (finished: Bool) in
                            self.hideMFiPlusDemo()
                        })
                    })
                })
            })
        })
    }
    
    func layoutMFiPlusCombo() {
        #if os(iOS)
        var safeAreaInsets: UIEdgeInsets {
            if #available(iOS 11.0, tvOS 11.0, *) {
                return view.safeAreaInsets
            } else {
                return UIEdgeInsets.zero
            }
        }
        let margin = safeAreaInsets
        #else
        let margin = UIEdgeInsets.zero
        #endif
        let yPadding: CGFloat = 54
        let frame = CGRect(x: (UIScreen.main.bounds.width / 2) - ((mFiPlusControllerTopView.image?.size.width)! / 2), y: margin.top + yPadding, width: (mFiPlusControllerTopView.image?.size.width)!, height: (mFiPlusControllerTopView.image?.size.height)!)
        mFiPlusComboView?.frame = frame
        let gradientHeight: CGFloat = 187
        let gradientFrame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: gradientHeight)
        mFiPlusHUDGradientView?.frame = gradientFrame
        mFiPlusHUDGradientLayer?.frame = gradientFrame
    }
    
    func showMFiPlusDemo() {
        var wait: TimeInterval = 0.0
        if shouldWaitToShowMFiDemo {
            wait = 7.0
            shouldWaitToShowMFiDemo = false
        }
        mFiPlusComboViewIsActive = true
        UIView.animate(withDuration: 1.5, delay: wait, options: [.curveEaseInOut], animations: {
            self.mFiPlusHUDGradientView?.alpha = 1.0
        }, completion: nil)
        UIView.animate(withDuration: 1.0, delay: wait, options: [.curveEaseInOut], animations: {
            self.mFiPlusComboView?.alpha = 1.0
        }, completion: { (finished: Bool) in
            self.pulseMFiCombo()
        })
    }
    
    func hideMFiPlusDemo() {
        UIView.animate(withDuration: 1.0, delay: 0.5, options: [.curveEaseInOut], animations: {
            self.mFiPlusControllerCombo.alpha = 0.0
            self.mFiPlusHUDDPadView?.alpha = 0.0
            self.mFiPlusHUDButtonsView?.alpha = 0.0
        }, completion: { (finished: Bool) in
            UIView.animate(withDuration: 1.0, delay: 0.0, options: [.curveEaseInOut], animations: {
                self.mFiPlusHUDGradientView?.alpha = 0.0
            }, completion: nil )
            UIView.animate(withDuration: 0.5, delay: 0.0, options: [.curveEaseInOut], animations: {
                self.mFiPlusComboView?.alpha = 0.0
            }, completion: { (finished: Bool) in
                self.mFiPlusComboViewIsActive = false
                self.shouldShowMFiPlusDemo = false
            })
        })
    }
    
    func setupMFiPlusHUD() {
        #if os(iOS)
        var safeAreaInsets: UIEdgeInsets {
            if #available(iOS 11.0, tvOS 11.0, *) {
                return view.safeAreaInsets
            } else {
                return UIEdgeInsets.zero
            }
        }
        let margin = safeAreaInsets
        #else
        let margin = UIEdgeInsets.zero
        #endif
        let yPadding: CGFloat = 60
        let xPadding: CGFloat = UIScreen.main.bounds.width / 14
        let frameSize: CGFloat = 28
        let frameL = CGRect(x: margin.left + xPadding, y: margin.top + yPadding, width: frameSize, height: frameSize)
        let frameR = CGRect(x: UIScreen.main.bounds.width - margin.right - xPadding - frameSize, y: margin.top + yPadding, width: frameSize, height: frameSize)
        mFiPlusHUDDPadView = UIView(frame: frameL)
        mFiPlusHUDButtonsView = UIView(frame: frameR)
        
        let buttonSize: CGFloat = 10
        let dPadButtonVSize = CGSize(width: 10, height: 9)
        let dPadButtonHSize = CGSize(width: 9, height: 10)
        let buttonBorder: CGFloat = 1.5
        let labelSpace: CGFloat = 4
        let labelSize = CGSize(width: 32, height: 8)
        let inactiveColor = UIColor(white: 1.0, alpha: 0.3)
        let labelFont = UIFont.systemFont(ofSize: 8.0)
        
        //Setup HUD D-Pad
        mFiPlusHUDDPadLeft = UIImageView(frame: CGRect(x: 0, y: (frameSize / 2) - (buttonSize / 2), width: dPadButtonHSize.width, height: dPadButtonHSize.height))
        mFiPlusHUDDPadUp = UIImageView(frame: CGRect(x: (frameSize / 2) - (buttonSize / 2), y: 0, width: dPadButtonVSize.width, height: dPadButtonVSize.height))
        mFiPlusHUDDPadDown = UIImageView(frame: CGRect(x: (frameSize / 2) - (buttonSize / 2), y: frameSize - buttonSize, width: dPadButtonVSize.width, height: dPadButtonVSize.height))
        mFiPlusHUDDPadRight = UIImageView(frame: CGRect(x: frameSize - buttonSize, y: (frameSize / 2) - (buttonSize / 2), width: dPadButtonHSize.width, height: dPadButtonHSize.height))
        
        let dPadBackground = UIImageView(frame: CGRect(x: 0, y: 0, width: frameSize, height: frameSize))
        dPadBackground.image = #imageLiteral(resourceName: "mFi-HUD-DPad-BG").withRenderingMode(.alwaysOriginal)
        mFiPlusHUDDPadView?.insertSubview(dPadBackground, at: 0)
        
        mFiPlusHUDDPadLeft?.image = #imageLiteral(resourceName: "mFi-HUD-DPad-HiLi-Left").withRenderingMode(.alwaysOriginal)
        mFiPlusHUDDPadUp?.image = #imageLiteral(resourceName: "mFi-HUD-DPad-HiLi-Up").withRenderingMode(.alwaysOriginal)
        mFiPlusHUDDPadDown?.image = #imageLiteral(resourceName: "mFi-HUD-DPad-HiLi-Down").withRenderingMode(.alwaysOriginal)
        mFiPlusHUDDPadRight?.image = #imageLiteral(resourceName: "mFi-HUD-DPad-HiLi-Right").withRenderingMode(.alwaysOriginal)
        
        mFiPlusHUDDPadLeft?.isHidden = true
        mFiPlusHUDDPadUp?.isHidden = true
        mFiPlusHUDDPadDown?.isHidden = true
        mFiPlusHUDDPadRight?.isHidden = true
        
        mFiPlusHUDDPadView?.addSubview(mFiPlusHUDDPadLeft!)
        mFiPlusHUDDPadView?.addSubview(mFiPlusHUDDPadUp!)
        mFiPlusHUDDPadView?.addSubview(mFiPlusHUDDPadDown!)
        mFiPlusHUDDPadView?.addSubview(mFiPlusHUDDPadRight!)
        
        mFiPlusHUDDPadLeftLabel = UILabel(frame: CGRect(x: 0 - labelSpace - labelSize.width, y: (frameSize / 2) - (labelSize.height / 2), width: labelSize.width, height: labelSize.height))
        mFiPlusHUDDPadUpLabel = UILabel(frame: CGRect(x: (frameSize / 2) - (labelSize.width / 2), y: 0 - labelSpace - labelSize.height, width: labelSize.width, height: labelSize.height))
        mFiPlusHUDDPadDownLabel = UILabel(frame: CGRect(x: (frameSize / 2) - (labelSize.width / 2), y: frameSize + labelSpace, width: labelSize.width, height: labelSize.height))
        mFiPlusHUDDPadRightLabel = UILabel(frame: CGRect(x: frameSize + labelSpace, y: (frameSize / 2) - (labelSize.height / 2), width: labelSize.width, height: labelSize.height))
        
        mFiPlusHUDDPadLeftLabel?.textAlignment = .right
        mFiPlusHUDDPadUpLabel?.textAlignment = .center
        mFiPlusHUDDPadDownLabel?.textAlignment = .center
        mFiPlusHUDDPadRightLabel?.textAlignment = .left
        
        mFiPlusHUDDPadLeftLabel?.font = labelFont
        mFiPlusHUDDPadUpLabel?.font = labelFont
        mFiPlusHUDDPadDownLabel?.font = labelFont
        mFiPlusHUDDPadRightLabel?.font = labelFont
        
        mFiPlusHUDDPadLeftLabel?.textColor = inactiveColor
        mFiPlusHUDDPadUpLabel?.textColor = inactiveColor
        mFiPlusHUDDPadDownLabel?.textColor = inactiveColor
        mFiPlusHUDDPadRightLabel?.textColor = inactiveColor
        
        mFiPlusHUDDPadView?.clipsToBounds = false
        mFiPlusHUDDPadView?.addSubview(mFiPlusHUDDPadLeftLabel!)
        mFiPlusHUDDPadView?.addSubview(mFiPlusHUDDPadUpLabel!)
        mFiPlusHUDDPadView?.addSubview(mFiPlusHUDDPadDownLabel!)
        mFiPlusHUDDPadView?.addSubview(mFiPlusHUDDPadRightLabel!)
        
        //Setup HUD Buttons
        mFiPlusHUDButtonX = UIView(frame: CGRect(x: 0, y: (frameSize / 2) - (buttonSize / 2), width: buttonSize, height: buttonSize))
        mFiPlusHUDButtonY = UIView(frame: CGRect(x: (frameSize / 2) - (buttonSize / 2), y: 0, width: buttonSize, height: buttonSize))
        mFiPlusHUDButtonA = UIView(frame: CGRect(x: (frameSize / 2) - (buttonSize / 2), y: frameSize - buttonSize, width: buttonSize, height: buttonSize))
        mFiPlusHUDButtonB = UIView(frame: CGRect(x: frameSize - buttonSize, y: (frameSize / 2) - (buttonSize / 2), width: buttonSize, height: buttonSize))
        
        mFiPlusHUDButtonX?.borderColor = inactiveColor
        mFiPlusHUDButtonY?.borderColor = inactiveColor
        mFiPlusHUDButtonA?.borderColor = inactiveColor
        mFiPlusHUDButtonB?.borderColor = inactiveColor
        
        mFiPlusHUDButtonX?.layer.borderWidth = buttonBorder
        mFiPlusHUDButtonY?.layer.borderWidth = buttonBorder
        mFiPlusHUDButtonA?.layer.borderWidth = buttonBorder
        mFiPlusHUDButtonB?.layer.borderWidth = buttonBorder
        
        mFiPlusHUDButtonX?.layer.cornerRadius = buttonSize / 2
        mFiPlusHUDButtonY?.layer.cornerRadius = buttonSize / 2
        mFiPlusHUDButtonA?.layer.cornerRadius = buttonSize / 2
        mFiPlusHUDButtonB?.layer.cornerRadius = buttonSize / 2
        
        mFiPlusHUDButtonsView?.addSubview(mFiPlusHUDButtonX!)
        mFiPlusHUDButtonsView?.addSubview(mFiPlusHUDButtonY!)
        mFiPlusHUDButtonsView?.addSubview(mFiPlusHUDButtonA!)
        mFiPlusHUDButtonsView?.addSubview(mFiPlusHUDButtonB!)
        
        mFiPlusHUDButtonXLabel = UILabel(frame: CGRect(x: 0 - labelSpace - labelSize.width, y: (frameSize / 2) - (labelSize.height / 2), width: labelSize.width, height: labelSize.height))
        mFiPlusHUDButtonYLabel = UILabel(frame: CGRect(x: (frameSize / 2) - (labelSize.width / 2), y: 0 - labelSpace - labelSize.height, width: labelSize.width, height: labelSize.height))
        mFiPlusHUDButtonALabel = UILabel(frame: CGRect(x: (frameSize / 2) - (labelSize.width / 2), y: frameSize + labelSpace, width: labelSize.width, height: labelSize.height))
        mFiPlusHUDButtonBLabel = UILabel(frame: CGRect(x: frameSize + labelSpace, y: (frameSize / 2) - (labelSize.height / 2), width: labelSize.width, height: labelSize.height))
        
        mFiPlusHUDButtonXLabel?.textAlignment = .right
        mFiPlusHUDButtonYLabel?.textAlignment = .center
        mFiPlusHUDButtonALabel?.textAlignment = .center
        mFiPlusHUDButtonBLabel?.textAlignment = .left
        
        mFiPlusHUDButtonXLabel?.textColor = inactiveColor
        mFiPlusHUDButtonYLabel?.textColor = inactiveColor
        mFiPlusHUDButtonALabel?.textColor = inactiveColor
        mFiPlusHUDButtonBLabel?.textColor = inactiveColor
        
        mFiPlusHUDButtonXLabel?.font = labelFont
        mFiPlusHUDButtonYLabel?.font = labelFont
        mFiPlusHUDButtonALabel?.font = labelFont
        mFiPlusHUDButtonBLabel?.font = labelFont
        
        mFiPlusHUDButtonsView?.clipsToBounds = false
        mFiPlusHUDButtonsView?.addSubview(mFiPlusHUDButtonXLabel!)
        mFiPlusHUDButtonsView?.addSubview(mFiPlusHUDButtonYLabel!)
        mFiPlusHUDButtonsView?.addSubview(mFiPlusHUDButtonALabel!)
        mFiPlusHUDButtonsView?.addSubview(mFiPlusHUDButtonBLabel!)
        
        mFiPlusHUDButtonsView?.layer.shadowColor = UIColor.black.cgColor
        mFiPlusHUDButtonsView?.layer.shadowRadius = 4.0
        mFiPlusHUDButtonsView?.layer.shadowOpacity = 0.75
        mFiPlusHUDButtonsView?.layer.shadowOffset = CGSize(width: 0.0, height: 1.0)
        
        mFiPlusHUDDPadView?.layer.shadowColor = UIColor.black.cgColor
        mFiPlusHUDDPadView?.layer.shadowRadius = 4.0
        mFiPlusHUDDPadView?.layer.shadowOpacity = 0.75
        mFiPlusHUDDPadView?.layer.shadowOffset = CGSize(width: 0.0, height: 1.0)
        
        self.mFiPlusHUDDPadView?.alpha = 0.0
        self.mFiPlusHUDButtonsView?.alpha = 0.0
        
        self.view.addSubview(mFiPlusHUDDPadView!)
        self.view.addSubview(mFiPlusHUDButtonsView!)
        mFiPlusHUDDPadView?.superview?.bringSubview(toFront: mFiPlusHUDDPadView!)
        mFiPlusHUDButtonsView?.superview?.bringSubview(toFront: mFiPlusHUDButtonsView!)
        
        #if os(tvOS)
        var transform = CGAffineTransform.identity
        let yOffset: CGFloat = yPadding * 2
        let xOffset: CGFloat = xPadding * 2
        let scale: CGFloat = 2
        transform = transform.scaledBy(x: scale, y: scale)
        mFiPlusHUDButtonsView?.transform = transform.translatedBy(x: -xOffset, y: yOffset)
        mFiPlusHUDDPadView?.transform = transform.translatedBy(x: xOffset, y: yOffset)
        mFiPlusComboView?.transform = transform.translatedBy(x: 0, y: yOffset)
        #endif
    }
    
    
    func layoutMFiPlusHUD() {
        #if os(iOS)
        var safeAreaInsets: UIEdgeInsets {
            if #available(iOS 11.0, tvOS 11.0, *) {
                return view.safeAreaInsets
            } else {
                return UIEdgeInsets.zero
            }
        }
        let margin = safeAreaInsets
        #else
        let margin = UIEdgeInsets.zero
        #endif
        let yPadding: CGFloat = 60
        let xPadding: CGFloat = UIScreen.main.bounds.width / 14
        let frameSize: CGFloat = 28
        let frameL = CGRect(x: margin.left + xPadding, y: margin.top + yPadding, width: frameSize, height: frameSize)
        let frameR = CGRect(x: UIScreen.main.bounds.width - margin.right - xPadding - frameSize, y: margin.top + yPadding, width: frameSize, height: frameSize)
        mFiPlusHUDDPadView?.frame = frameL
        mFiPlusHUDButtonsView?.frame = frameR
    }
    
    func showMFiPlusHUD() {
        mfiPlusisActive = true
        var duration = 0.1
        if shouldShowMFiPlusDemo {
            duration = 1.0
        }
        UIView.animate(withDuration: duration, delay: 0.0, options: [.curveEaseInOut], animations: {
            self.mFiPlusHUDDPadView?.alpha = 1.0
            self.mFiPlusHUDButtonsView?.alpha = 1.0
        }, completion: nil )
    }
    
    func hideMFiPlusHUD() {
        updateMFiHUD()
        var duration = 0.2
        if shouldShowMFiPlusDemo {
            duration = 1.5
        }
        UIView.animate(withDuration: duration, delay: 0.0, options: [.curveEaseInOut], animations: {
            self.mFiPlusHUDDPadView?.alpha = 0.0
            self.mFiPlusHUDButtonsView?.alpha = 0.0
        }, completion: nil)
        mfiPlusisActive = false
    }

    @objc func showMenu(_ sender: Any?) {
        enableControllerInput(true)
        core.setPauseEmulation(true)
        isShowingMenu = true
        let actionsheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if traitCollection.userInterfaceIdiom == .pad {
            actionsheet.popoverPresentationController?.sourceView = menuButton
            actionsheet.popoverPresentationController?.sourceRect = menuButton!.bounds
        }
        menuActionSheet = actionsheet
        if PVControllerManager.shared.iCadeController != nil {
            actionsheet.addAction(UIAlertAction(title: "Disconnect iCade", style: .default, handler: {(_ action: UIAlertAction) -> Void in
                NotificationCenter.default.post(name: .GCControllerDidDisconnect, object: PVControllerManager.shared.iCadeController)
                self.core.setPauseEmulation(false)
                self.isShowingMenu = false
                self.enableControllerInput(false)
            }))
        }

//		if let optionCore = core as? CoreOptional {
		if core is CoreOptional {
			actionsheet.addAction(UIAlertAction(title: "Core Options", style: .default, handler: { (action) in
				self.showCoreOptions()
			}))
		}

        let controllerManager = PVControllerManager.shared
        let wantsStartSelectInMenu: Bool = PVEmulatorConfiguration.systemIDWantsStartAndSelectInMenu(game.system.identifier)
        var hideP1MenuActions = false
        if let player1 = controllerManager.player1 {
#if os(iOS)
            if PVSettingsModel.shared.startSelectAlwaysOn {
                hideP1MenuActions = true
            }
#endif
            if (player1.extendedGamepad != nil || wantsStartSelectInMenu) && !hideP1MenuActions {
                // left trigger bound to Start
                // right trigger bound to Select
                actionsheet.addAction(UIAlertAction(title: "P1 Start", style: .default, handler: {(_ action: UIAlertAction) -> Void in
                    self.core.setPauseEmulation(false)
                    self.isShowingMenu = false
                    self.controllerViewController?.pressStart(forPlayer: 0)
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.5, execute: {() -> Void in
                        self.controllerViewController?.releaseStart(forPlayer: 0)
                    })
                    self.enableControllerInput(false)
                }))
                actionsheet.addAction(UIAlertAction(title: "P1 Select", style: .default, handler: {(_ action: UIAlertAction) -> Void in
                    self.core.setPauseEmulation(false)
                    self.isShowingMenu = false
                    self.controllerViewController?.pressSelect(forPlayer: 0)
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.5, execute: {() -> Void in
                        self.controllerViewController?.releaseSelect(forPlayer: 0)
                    })
                    self.enableControllerInput(false)
                }))
            }
        }
        if let player2 = controllerManager.player2 {
            if (player2.extendedGamepad != nil || wantsStartSelectInMenu) {
                actionsheet.addAction(UIAlertAction(title: "P2 Start", style: .default, handler: {(_ action: UIAlertAction) -> Void in
                    self.core.setPauseEmulation(false)
                    self.isShowingMenu = false
                    self.controllerViewController?.pressStart(forPlayer: 1)
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2, execute: {() -> Void in
                        self.controllerViewController?.releaseStart(forPlayer: 1)
                    })
                    self.enableControllerInput(false)
                }))
                actionsheet.addAction(UIAlertAction(title: "P2 Select", style: .default, handler: {(_ action: UIAlertAction) -> Void in
                    self.core.setPauseEmulation(false)
                    self.isShowingMenu = false
                    self.controllerViewController?.pressSelect(forPlayer: 1)
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2, execute: {() -> Void in
                        self.controllerViewController?.releaseSelect(forPlayer: 1)
                    })
                    self.enableControllerInput(false)
                }))
            }
        }
        if let swappableCore = core as? DiscSwappable, swappableCore.currentGameSupportsMultipleDiscs {
            actionsheet.addAction(UIAlertAction(title: "Swap Disc", style: .default, handler: {(_ action: UIAlertAction) -> Void in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                    self.showSwapDiscsMenu()
                })
            }))
        }

		if let actionableCore = core as? CoreActions, let actions = actionableCore.coreActions {
			actions.forEach { coreAction in
				actionsheet.addAction(UIAlertAction(title: coreAction.title, style: .default, handler: {(_ action: UIAlertAction) -> Void in
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
						actionableCore.selected(action: coreAction)
						self.core.setPauseEmulation(false)
						if coreAction.requiresReset {
							self.core.resetEmulation()
						}
						self.isShowingMenu = false
						self.enableControllerInput(false)
					})
				}))
			}
		}
#if os(iOS)
        actionsheet.addAction(UIAlertAction(title: "Save Screenshot", style: .default, handler: {(_ action: UIAlertAction) -> Void in
            self.perform(#selector(self.takeScreenshot), with: nil, afterDelay: 0.1)
        }))
#endif
        actionsheet.addAction(UIAlertAction(title: "Game Info", style: .default, handler: {(_ action: UIAlertAction) -> Void in
            let sb = UIStoryboard(name: "Provenance", bundle: nil)
            let moreInfoViewContrller = sb.instantiateViewController(withIdentifier: "gameMoreInfoVC") as? PVGameMoreInfoViewController
            moreInfoViewContrller?.game = self.game
            moreInfoViewContrller?.showsPlayButton = false
            moreInfoViewContrller?.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.hideModeInfo))
            let newNav = UINavigationController(rootViewController: moreInfoViewContrller ?? UIViewController())
            self.present(newNav, animated: true) {() -> Void in }
            self.isShowingMenu = false
            self.enableControllerInput(false)
        }))
        actionsheet.addAction(UIAlertAction(title: "Game Speed", style: .default, handler: {(_ action: UIAlertAction) -> Void in
            self.perform(#selector(self.showSpeedMenu), with: nil, afterDelay: 0.1)
        }))
        if core.supportsSaveStates {
            actionsheet.addAction(UIAlertAction(title: "Save States", style: .default, handler: {(_ action: UIAlertAction) -> Void in
                self.perform(#selector(self.showSaveStateMenu), with: nil, afterDelay: 0.1)
            }))
        }
        actionsheet.addAction(UIAlertAction(title: "Reset", style: .default, handler: {(_ action: UIAlertAction) -> Void in
            if PVSettingsModel.sharedInstance().autoSave, self.core.supportsSaveStates {
                try? self.autoSaveState()
            }
            self.core.setPauseEmulation(false)
            self.core.resetEmulation()
            self.isShowingMenu = false
            self.enableControllerInput(false)
        }))
        var quitTitle = "Quit"
		let lastPlayed = game.lastPlayed ?? Date()
		var shouldSave = PVSettingsModel.shared.autoSave
		shouldSave = shouldSave && abs(lastPlayed.timeIntervalSinceNow) > minimumPlayTimeToMakeAutosave
		shouldSave = shouldSave && (game.lastAutosaveAge ?? minutes(2)) > minutes(1)
		shouldSave = shouldSave && abs(game.saveStates.sorted(byKeyPath: "date", ascending: true).last?.date.timeIntervalSinceNow ?? minutes(2)) > minutes(1)
        if shouldSave {
            quitTitle = "Save & Quit"
        }

        actionsheet.addAction(UIAlertAction(title: quitTitle, style: .destructive, handler: {(_ action: UIAlertAction) -> Void in
            self.quit()
        }))
        let resumeAction = UIAlertAction(title: "Resume", style: .cancel, handler: {(_ action: UIAlertAction) -> Void in
                self.core.setPauseEmulation(false)
                self.isShowingMenu = false
                self.enableControllerInput(false)
            })
        actionsheet.addAction(resumeAction)
        if #available(iOS 9.0, *) {
            actionsheet.preferredAction = resumeAction
        }
        present(actionsheet, animated: true, completion: {() -> Void in
            PVControllerManager.shared.iCadeController?.refreshListener()
        })
    }

    @objc func hideModeInfo() {
        dismiss(animated: true, completion: {() -> Void in
#if os(tvOS)
            self.showMenu(nil)
#else
            self.hideMenu()
#endif
        })
    }

    func hideMenu() {
        enableControllerInput(false)
        if menuActionSheet != nil {
            dismiss(animated: true) {() -> Void in }
            isShowingMenu = false
        }
		#endif
        updateLastPlayedTime()
        core.setPauseEmulation(false)
    }

    @objc func updateFPSLabel() {
#if DEBUG
        print("FPS: \(glViewController?.framesPerSecond ?? 0)")
#endif
        fpsLabel?.text = String(format: "%2.02f", core.emulationFPS)
    }

    @objc func showSaveStateMenu() {
		guard let saveStatesNavController = UIStoryboard(name: "Provenance", bundle: nil).instantiateViewController(withIdentifier: "PVSaveStatesViewControllerNav") as? UINavigationController else {
			return
		}

		let image = captureScreenshot()

		if let saveStatesViewController = saveStatesNavController.viewControllers.first as? PVSaveStatesViewController {
			saveStatesViewController.saveStates = game.saveStates
			saveStatesViewController.delegate = self
			saveStatesViewController.screenshot = image
			saveStatesViewController.coreID = core.coreIdentifier
		}

		saveStatesNavController.modalPresentationStyle = .overCurrentContext

#if os(iOS)
		if traitCollection.userInterfaceIdiom == .pad {
			saveStatesNavController.modalPresentationStyle = .formSheet
		}
#endif
#if os(tvOS)
		if #available(tvOS 11, *) {
			saveStatesNavController.modalPresentationStyle = .blurOverFullScreen
		}
#endif
		present(saveStatesNavController, animated: true)
    }

	func convertOldSaveStatesToNewIfNeeded() {
		let fileManager = FileManager.default
		let infoURL =  URL(fileURLWithPath: saveStatePath).appendingPathComponent("info.plist")
		let autoSaveURL = URL(fileURLWithPath: saveStatePath).appendingPathComponent("auto.svs")
		let saveStateURLs = [
			URL(fileURLWithPath: saveStatePath).appendingPathComponent("0.svs"),
			URL(fileURLWithPath: saveStatePath).appendingPathComponent("1.svs"),
			URL(fileURLWithPath: saveStatePath).appendingPathComponent("2.svs"),
			URL(fileURLWithPath: saveStatePath).appendingPathComponent("3.svs"),
			URL(fileURLWithPath: saveStatePath).appendingPathComponent("4.svs")
		]

		if fileManager.fileExists(atPath: infoURL.path) {
			do {
				try fileManager.removeItem(at: infoURL)
			} catch let error {
				presentError("Unable to remove old save state info.plist: \(error.localizedDescription)")
			}
		}

		guard let realm = try? Realm() else {
			presentError("Unable to instantiate realm, abandoning old save state conversion")
			return
		}

		if fileManager.fileExists(atPath: autoSaveURL.path) {
			do {
				guard let core = realm.object(ofType: PVCore.self, forPrimaryKey: core.coreIdentifier) else {
					presentError("No core in database with id \(self.core.coreIdentifier ?? "null")")
					return
				}

				let newURL = URL(fileURLWithPath: saveStatePath).appendingPathComponent("\(game.md5Hash)|\(Date().timeIntervalSinceReferenceDate)")
				try fileManager.moveItem(at: autoSaveURL, to: newURL)
				let saveFile = PVFile(withURL: newURL)
				let newState = PVSaveState(withGame: game, core: core, file: saveFile, image: nil, isAutosave: true)
				try realm.write {
					realm.add(newState)
				}
			} catch let error {
				presentError("Unable to convert autosave to new format: \(error.localizedDescription)")
			}
		}

		for url in saveStateURLs {
			if fileManager.fileExists(atPath: url.path) {
				do {
					guard let core = realm.object(ofType: PVCore.self, forPrimaryKey: core.coreIdentifier) else {
						presentError("No core in database with id \(self.core.coreIdentifier ?? "null")")
						return
					}

					let newURL = URL(fileURLWithPath: saveStatePath).appendingPathComponent("\(game.md5Hash)|\(Date().timeIntervalSinceReferenceDate)")
					try fileManager.moveItem(at: url, to: newURL)
					let saveFile = PVFile(withURL: newURL)
					let newState = PVSaveState(withGame: game, core: core, file: saveFile, image: nil, isAutosave: false)
					try realm.write {
						realm.add(newState)
					}
				} catch let error {
					presentError("Unable to convert autosave to new format: \(error.localizedDescription)")
				}
			}
		}
	}

	func autoSaveState() throws {
		guard core.supportsSaveStates else {
			WLOG("Core \(core.description) doesn't support save states.")
			throw SaveStateError.saveStatesUnsupportedByCore
		}

		if let lastPlayed = game.lastPlayed, (lastPlayed.timeIntervalSinceNow * -1)  < minimumPlayTimeToMakeAutosave {
			ILOG("Haven't been playing game long enough to make an autosave")
			return
		}

		guard game.lastAutosaveAge == nil || game.lastAutosaveAge! > minutes(1) else {
			ILOG("Last autosave is too new to make new one")
			return
		}

		if let latestManualSaveState = game.saveStates.sorted(byKeyPath: "date", ascending: true).last, (latestManualSaveState.date.timeIntervalSinceNow * -1) < minutes(1) {
			ILOG("Latest manual save state is too recent to make a new auto save")
			return
		}

		let image = captureScreenshot()
        try createNewSaveState(auto: true, screenshot: image)
    }

	func createNewSaveState(auto: Bool, screenshot: UIImage?) throws {
		guard core.supportsSaveStates else {
			WLOG("Core \(core.description) doesn't support save states.")
			throw SaveStateError.saveStatesUnsupportedByCore
		}

		let saveFile = PVFile(withURL: URL(fileURLWithPath: saveStatePath).appendingPathComponent("\(game.md5Hash)|\(Date().timeIntervalSinceReferenceDate).svs"))

		var imageFile: PVImageFile?
		if let screenshot = screenshot {
			if let pngData = UIImagePNGRepresentation(screenshot) {
				let imageURL = URL(fileURLWithPath: saveStatePath).appendingPathComponent("\(game.md5Hash)|\(Date().timeIntervalSinceReferenceDate).png")
				do {
					try pngData.write(to: imageURL)
//					try RomDatabase.sharedInstance.writeTransaction {
//						let newFile = PVImageFile(withURL: imageURL)
//						game.screenShots.append(newFile)
//					}
				} catch let error {
					presentError("Unable to write image to disk, error: \(error.localizedDescription)")
				}

				imageFile = PVImageFile(withURL: imageURL)
			}
		}

		do {
			try self.core.saveStateToFile(atPath: saveFile.url.path)

			DLOG("Succeeded saving state, auto: \(auto)")
			if let realm = try? Realm() {
				guard let core = realm.object(ofType: PVCore.self, forPrimaryKey: core.coreIdentifier) else {
					presentError("No core in database with id \(self.core.coreIdentifier ?? "null")")
					return
				}

				do {
					try realm.write {
						let saveState = PVSaveState(withGame: game, core: core, file: saveFile, image: imageFile, isAutosave: auto)
						realm.add(saveState)
					}
				} catch let error {
					presentError("Unable to write save state to realm: \(error.localizedDescription)")
				}

				// Delete the oldest auto-saves over 5 count
				try? realm.write {
					let autoSaves = game.autoSaves
					if autoSaves.count > 5 {
						autoSaves.suffix(from: 5).forEach {
							DLOG("Deleting old auto save of \($0.game.title) dated: \($0.date.description)")
							realm.delete($0)
						}
					}
				}
			}
		} catch {
			throw error
//			throw SaveStateError.failedToSave(isAutosave: auto)
		}
	}

	func loadSaveState(_ state: PVSaveState) {
		guard core.supportsSaveStates else {
			WLOG("Core \(core.description) doesn't support save states.")
			return
		}

		let realm = try! Realm()
		guard let core = realm.object(ofType: PVCore.self, forPrimaryKey: core.coreIdentifier) else {
			presentError("No core in database with id \(self.core.coreIdentifier ?? "null")")
			return
		}

		let loadSave = {
			try! realm.write {
				state.lastOpened = Date()
			}

			do {
				try self.core.loadStateFromFile(atPath: state.file.url.path)
			} catch {
				self.presentError("Failed to load save state. \(error.localizedDescription)")
			}
			self.core.setPauseEmulation(false)
			self.isShowingMenu = false
			self.enableControllerInput(false)
		}

		if core.projectVersion != state.createdWithCoreVersion {
			let message =
			"""
			Save state created with version \(state.createdWithCoreVersion ?? "nil") but current \(core.projectName) core is version \(core.projectVersion).
			Save file may not load. Create a new save state to avoid this warning in the future.
			"""
			presentWarning(message, completion: loadSave)
		} else {
			loadSave()
		}
	}

	func saveStatesViewControllerDone(_ saveStatesViewController: PVSaveStatesViewController) {
		dismiss(animated: true, completion: nil)
		self.core.setPauseEmulation(false)
		self.isShowingMenu = false
		self.enableControllerInput(false)
	}

	func saveStatesViewControllerCreateNewState(_ saveStatesViewController: PVSaveStatesViewController) throws {
		try createNewSaveState(auto: false, screenshot: saveStatesViewController.screenshot)
	}

    func saveStatesViewControllerOverwriteState(_ saveStatesViewController: PVSaveStatesViewController, state: PVSaveState) throws {
        try createNewSaveState(auto: false, screenshot: saveStatesViewController.screenshot)
		try PVSaveState.delete(state)
    }

	func saveStatesViewController(_ saveStatesViewController: PVSaveStatesViewController, load state: PVSaveState) {
		dismiss(animated: true, completion: nil)
		loadSaveState(state)
	}

	func captureScreenshot() -> UIImage? {
		fpsLabel?.alpha = 0.0
		let width: CGFloat? = self.glViewController?.view.frame.size.width
		let height: CGFloat? = self.glViewController?.view.frame.size.height
		let size = CGSize(width: width ?? 0.0, height: height ?? 0.0)
		UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)
		let rec = CGRect(x: 0, y: 0, width: width ?? 0.0, height: height ?? 0.0)
		self.glViewController?.view.drawHierarchy(in: rec, afterScreenUpdates: true)
		let image: UIImage? = UIGraphicsGetImageFromCurrentImageContext()
		UIGraphicsEndImageContext()
		fpsLabel?.alpha = 1.0
		return image
	}
#if os(iOS)
    @objc func takeScreenshot() {
		if let screenshot = captureScreenshot() {
			DispatchQueue.global(qos: .default).async(execute: {() -> Void in
				UIImageWriteToSavedPhotosAlbum(screenshot, nil, nil, nil)
			})

			if let pngData = UIImagePNGRepresentation(screenshot) {

				let dateString = PVEmulatorConfiguration.string(fromDate: Date())

				let fileName = game.title  + " - " + dateString + ".png"
				let imageURL = PVEmulatorConfiguration.screenshotsPath(forGame: game).appendingPathComponent(fileName, isDirectory: false)
				do {
					try pngData.write(to: imageURL)
					try RomDatabase.sharedInstance.writeTransaction {
						let newFile = PVImageFile(withURL: imageURL)
						game.screenShots.append(newFile)
					}
				} catch let error {
					presentError("Unable to write image to disk, error: \(error.localizedDescription)")
				}
			}
		}
		self.core.setPauseEmulation(false)
		self.isShowingMenu = false
    }

#endif
    @objc func showSpeedMenu() {
        let actionSheet = UIAlertController(title: "Game Speed", message: nil, preferredStyle: .actionSheet)
        if traitCollection.userInterfaceIdiom == .pad, let menuButton = menuButton {
            actionSheet.popoverPresentationController?.sourceView = menuButton
            actionSheet.popoverPresentationController?.sourceRect = menuButton.bounds
        }
        let speeds = ["Slow", "Normal", "Fast"]
        speeds.enumerated().forEach { (idx, title) in
            actionSheet.addAction(UIAlertAction(title: title, style: .default, handler: {(_ action: UIAlertAction) -> Void in
                self.core.gameSpeed = GameSpeed(rawValue: idx) ?? .normal
                self.core.setPauseEmulation(false)
                self.isShowingMenu = false
                self.enableControllerInput(false)
            }))
        }
        present(actionSheet, animated: true, completion: {() -> Void in
            PVControllerManager.shared.iCadeController?.refreshListener()
        })
    }

    typealias QuitCompletion = () -> Void

	func quit(optionallySave canSave : Bool = true, completion: QuitCompletion? = nil) {
        if canSave, PVSettingsModel.sharedInstance().autoSave, core.supportsSaveStates {
			do {
				try autoSaveState()
			} catch {
				ELOG("Auto-save failed \(error.localizedDescription)")
			}
        }

        core.stopEmulation()
        //Leave emulation loop first
        fpsTimer?.invalidate()
        fpsTimer = nil
        gameAudio?.stop()
#if os(iOS)
        UIApplication.shared.setStatusBarHidden(false, with: .fade)
#endif
        dismiss(animated: true, completion: completion)
        enableControllerInput(false)
        updatePlayedDuration()
    }

// MARK: - Controllers
    //#if os(tvOS)
    // Ensure that override of menu gesture is caught and handled properly for tvOS
    @available(iOS 9.0, *)
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {

        if let press = presses.first, press.type == .menu && !isShowingMenu {
            //         [self controllerPauseButtonPressed];
        } else {
            super.pressesBegan(presses, with: event)
        }
    }

    //#endif
    @objc func controllerPauseButtonPressed(_ sender: Any?) {
        DispatchQueue.main.async(execute: {() -> Void in
            if !self.isShowingMenu {
                self.showMenu(self)
            } else {
                self.hideMenu()
            }
        })
    }

    @objc func controllerDidConnect(_ note: Notification?) {
        let controller = note?.object as? GCController
        // 8Bitdo controllers doesn't have a pause button, so don't hide the menu
        if !(controller is PViCade8BitdoController || controller is PViCade8BitdoZeroController) {
            menuButton?.isHidden = true
                // In instances where the controller is connected *after* the VC has been shown, we need to set the pause handler
#if os(iOS)

    controller?.controllerPausedHandler = {[unowned self] controller in
        self.controllerPauseButtonPressed(controller)
    }
            if #available(iOS 11.0, *) {
                setNeedsUpdateOfHomeIndicatorAutoHidden()
            }
#endif
        }
        
        // Setup MFi+ Views
        setupMFiPlusViews(for: controller!)
        shouldShowMFiPlusDemo = true
        #if os(tvOS)
        shouldWaitToShowMFiDemo = true
        #endif
        
        connectControllers()
        
    }

    @objc func controllerDidDisconnect(_ note: Notification?) {
        menuButton?.isHidden = false
#if os(iOS)
        if #available(iOS 11.0, *) {
            setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
#endif
        // Hide MFi+ Views
//        if !mFiPlusComboViewIsActive && !shouldShowMFiPlusCombo {
//            hideMFIPlusCombo()
//            hideMFiPlusHUD()
//        }
    }

    @objc func handleControllerManagerControllerReassigned(_ notification: Notification?) {
        core.controller1 = PVControllerManager.shared.player1
        core.controller2 = PVControllerManager.shared.player2
        core.controller3 = PVControllerManager.shared.player3
        core.controller4 = PVControllerManager.shared.player4
    }

// MARK: - UIScreenNotifications
    @objc func screenDidConnect(_ note: Notification?) {
        ILOG("Screen did connect: \(note?.object ?? "")")
        if secondaryScreen == nil {
            secondaryScreen = UIScreen.screens[1]
            if let aBounds = secondaryScreen?.bounds {
                secondaryWindow = UIWindow(frame: aBounds)
            }
            if let aScreen = secondaryScreen {
                secondaryWindow?.screen = aScreen
            }
            glViewController?.view?.removeFromSuperview()
            glViewController?.removeFromParentViewController()
            secondaryWindow?.rootViewController = glViewController
            glViewController?.view?.frame = secondaryWindow?.bounds ?? .zero
            if let aView = glViewController?.view {
                secondaryWindow?.addSubview(aView)
            }
            secondaryWindow?.isHidden = false
            glViewController?.view?.setNeedsLayout()
        }
    }

    @objc func screenDidDisconnect(_ note: Notification?) {
        ILOG("Screen did disconnect: \(note?.object ?? "")")
        let screen = note?.object as? UIScreen
        if secondaryScreen == screen {
            glViewController?.view?.removeFromSuperview()
            glViewController?.removeFromParentViewController()
            if let aController = glViewController {
                addChildViewController(aController)
            }
            if let aView = glViewController?.view, let aView1 = controllerViewController?.view {
                view.insertSubview(aView, belowSubview: aView1)
            }
            glViewController?.view?.setNeedsLayout()
            secondaryWindow = nil
            secondaryScreen = nil
        }
    }

// MARK: - PVAudioDelegate
    func audioSampleRateDidChange() {
        gameAudio?.stop()
        gameAudio?.start()
    }
}

extension PVEmulatorViewController {
    func showSwapDiscsMenu() {
        guard let core = self.core as? (PVEmulatorCore & DiscSwappable) else {
			presentError("Internal error: No core found.")
			self.isShowingMenu = false
			self.enableControllerInput(false)
            return
        }

        let numberOfDiscs = core.numberOfDiscs
        guard numberOfDiscs > 1 else {
            presentError("Game only supports 1 disc.")
			core.setPauseEmulation(false)
			self.isShowingMenu = false
			self.enableControllerInput(false)
            return
        }

        // Add action for each disc
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        for index in 1...numberOfDiscs {
            actionSheet.addAction(UIAlertAction(title: "\(index)", style: .default, handler: {[unowned self] (sheet) in

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: {
                    core.swapDisc(number: index)
                })

                core.setPauseEmulation(false)
                self.isShowingMenu = false
                self.enableControllerInput(false)
            }))
        }

        // Add cancel action
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: {[unowned self] (sheet) in
            core.setPauseEmulation(false)
            self.isShowingMenu = false
			self.enableControllerInput(false)
        }))

        // Present
        if traitCollection.userInterfaceIdiom == .pad {
            actionSheet.popoverPresentationController?.sourceView = menuButton
            actionSheet.popoverPresentationController?.sourceRect = menuButton?.bounds ?? .zero
        }

        self.present(actionSheet, animated: true) {
            PVControllerManager.shared.iCadeController?.refreshListener()
        }
    }
}

// Extension to make gesture.allowedPressTypes and gesture.allowedTouchTypes sane.
@available(iOS 9.0, *)
extension NSNumber {
    static var menu: NSNumber {
        return NSNumber(pressType: .menu)
    }
    static var playPause: NSNumber {
        return NSNumber(pressType: .playPause)
    }
    static var select: NSNumber {
        return NSNumber(pressType: .select)
    }
    static var upArrow: NSNumber {
        return NSNumber(pressType: .upArrow)
    }

    static var downArrow: NSNumber {
        return NSNumber(pressType: .downArrow)
    }
    static var leftArrow: NSNumber {
        return NSNumber(pressType: .leftArrow)
    }
    static var rightArrow: NSNumber {
        return NSNumber(pressType: .rightArrow)
    }
    // MARK: - Private

    private convenience init(pressType: UIPressType) {
        self.init(integerLiteral: pressType.rawValue)
    }
}

@available(iOS 9.0, *)
extension NSNumber {
    static var direct: NSNumber {
        return NSNumber(touchType: .direct)
    }
    static var indirect: NSNumber {
        return NSNumber(touchType: .indirect)
    }
    // MARK: - Private

    private convenience init(touchType: UITouchType) {
        self.init(integerLiteral: touchType.rawValue)
    }
}

extension PVEmulatorViewController {
	func showCoreOptions() {
		let nav = UINavigationController(rootViewController: CoreOptionsViewController(withCore: type(of: core) as! CoreOptional.Type))
		present(nav, animated: true, completion: nil)
	}
}

class CoreOptionsViewController : UITableViewController {
	let core : CoreOptional.Type
	init(withCore core : CoreOptional.Type) {
		self.core = core
		super.init(style: .grouped)
	}

	struct TableGroup {
		let title : String
		let options : [CoreOption]
	}

	lazy var groups : [TableGroup] = {
		var rootOptions = [CoreOption]()

		var groups = core.options.compactMap({ (option) -> TableGroup? in
			switch option {
			case .group(let display, let subOptions):
				return TableGroup(title: display.title, options: subOptions)
			default:
				rootOptions.append(option)
				return nil
			}
		})

		if !rootOptions.isEmpty {
			groups.insert(TableGroup(title: "", options: rootOptions), at: 0)
		}

		return groups
	}()

	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return groups.count
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return groups[section].options.count
	}

	override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
		return groups.map { return $0.title }
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell : UITableViewCell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)

		let group = groups[indexPath.section]
		let option = group.options[indexPath.row]

		cell.textLabel?.text = option.key

		return cell
	}

}
