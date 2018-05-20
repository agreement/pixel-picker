//
//  PPState.swift
//  PixelPicker
//

import SwiftyJSON
import MASShortcut
import LaunchAtLogin
import CleanroomLogger

// This state class is responsible for saving/loading application state and keeping
// track of the active state and user configuration.
@objcMembers class PPState: NSObject {
    // Only one instance of this class should be used at a time.
    static let shared = PPState(atPath: defaultConfigurationPath())
    
    // The max float precision we support.
    static let maxFloatPrecision = 12

    // Location of our serialised application state.
    let savePath: URL

    // UserDefaults is used to provide some experimental overrides.
    let defaults: UserDefaults = UserDefaults.standard
    
    // Whether the picker should be square or not.
    // TODO: implement shortcut
    var paschaModeEnabled: Bool = false
    
    // The shortcut that activates the pixel picker.
    var activatingShortcut: MASShortcut?
    
    // Hold this down to enter concentration mode.
    var concentrationModeModifier: NSEvent.ModifierFlags = .control
    
    // The currently chosen format.
    var chosenFormat: PPColor = .genericHex
    
    // How precise floats should be when copied.
    var floatPrecision: UInt = 3
    
    // Recent colors picks.
    var recentPicks: [PPPickedColor] = []
    
    // Whether or not the app should launch after login.
    // TODO: add menu item for this
    private var launchAppAtLogin = LaunchAtLogin.isEnabled

    private init(atPath url: URL) {
        self.savePath = url
        defaults.register(defaults: [:])
    }
    
    func addRecentPick(_ color: PPPickedColor) {
        while recentPicks.count >= 5 { let _ = recentPicks.removeFirst() }
        recentPicks.append(color)
    }
    
    /**
     * Below are methods related to saving/loading state from disk.
     */
    
    func resetState() {
        paschaModeEnabled = false
        concentrationModeModifier = .control
        activatingShortcut = nil
        chosenFormat = .genericHex
        floatPrecision = 3
        recentPicks = []
    }

    // Loads the app state (JSON) from disk - if the file exists - otherwise it does nothing.
    func loadFromDisk() {
        resetState()
        
        do {
            let jsonString = try String(contentsOf: savePath, encoding: .utf8)
            try loadFromString(jsonString)
        } catch {
            // Ignore error when there's no file.
            let err = error as NSError
            if err.domain != NSCocoaErrorDomain && err.code != CocoaError.fileReadNoSuchFile.rawValue {
                Log.error?.message("Unexpected error loading application state from disk: \(error)")
            }
        }
    }

    // Load state from a (JSON encoded) string.
    func loadFromString(_ jsonString: String) throws {
        if let dataFromString = jsonString.data(using: .utf8, allowLossyConversion: false) {
            let json = try JSON(data: dataFromString)
            for (key, value):(String, JSON) in json {
                switch key {
                case "paschaModeEnabled":
                    paschaModeEnabled = value.bool ?? false
                case "concentrationModeModifier":
                    concentrationModeModifier = NSEvent.ModifierFlags(rawValue: value.uInt ?? NSEvent.ModifierFlags.control.rawValue)
                case "activatingShortcut":
                    if let keyCode = value["keyCode"].uInt, let modifierFlags = value["modifierFlags"].uInt {
                        let shortcut = MASShortcut(keyCode: keyCode, modifierFlags: modifierFlags)
                        if MASShortcutValidator.shared().isShortcutValid(shortcut) {
                            activatingShortcut = shortcut
                        }
                    }
                case "chosenFormat":
                    chosenFormat = PPColor(rawValue: value.stringValue) ?? .genericHex
                case "floatPrecision":
                    let n = value.uInt ?? 3
                    floatPrecision = (n > 0 && n < PPState.maxFloatPrecision) ? n : 3
                case "recentPicks":
                    recentPicks = deserializeRecentPicks(fromJSON: value)
                default:
                    Log.warning?.message("unknown key '\(key)' encountered in json")
                }
            }

            Log.info?.message("Loaded config from disk")
        }
    }
    
    // Loads seralised recent picks.
    func deserializeRecentPicks(fromJSON jsonValue: JSON) -> [PPPickedColor] {
        var recents: [PPPickedColor] = []
        for (_, pickedColorJson): (String, JSON) in jsonValue {
            if let pickedColor = PPPickedColor(fromJSON: pickedColorJson) {
                recents.append(pickedColor)
            }
        }
        return recents
    }

    // Saves the app state to disk, creating the parent directories if they don't already exist.
    func saveToDisk() {
        var shortcutData: JSON = [:]
        if let shortcut = activatingShortcut {
            shortcutData["keyCode"].uInt = shortcut.keyCode
            shortcutData["modifierFlags"].uInt = shortcut.modifierFlags
        }
        
        let json: JSON = [
            "paschaModeEnabled": paschaModeEnabled,
            "concentrationModeModifier": concentrationModeModifier.rawValue,
            "activatingShortcut": shortcutData,
            "chosenFormat": chosenFormat.rawValue,
            "floatPrecision": floatPrecision,
            "recentPicks": recentPicks.map({ $0.asJSON })
        ]
        do {
            if let jsonString = json.rawString([:]) {
                let configDir = savePath.deletingLastPathComponent()
                try FileManager.default.createDirectory(atPath: configDir.path, withIntermediateDirectories: true, attributes: nil)
                try jsonString.write(to: savePath, atomically: false, encoding: .utf8)
                Log.info?.message("Saved config to disk")
            } else {
                Log.error?.message("Could not serialise config")
            }
        } catch {
            Log.error?.message("Unexpected error saving application state to disk: \(error)")
        }
    }
}