import Foundation
import UIKit

// Pretty slick, and stolen from
// https://stackoverflow.com/a/64712479/13175115
// I changed this to a class because I randomly got a sick error "Simultaneous accesses to 0x6000007fc3d0, but modification requires exclusive access"
// This random 0 upvote stack overflow suggested changing the struct to a class and I haven't had an issue since.
// https://stackoverflow.com/a/59324450/13175115
@propertyWrapper
public class SettingsBundleStorage<T> {
    private let key: String

    public init(key: String) {
        self.key = key
        setBundleDefaults()
    }

    public var wrappedValue: T {
        get { UserDefaults.standard.value(forKey: key) as! T }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    
    private func setBundleDefaults() {
        // Register the default values from Settings.bundle
        let settingsURL = Bundle.main.url(forResource: "Root", withExtension: "plist", subdirectory: "Settings.bundle")!
        let settingsRootDict = NSDictionary(contentsOf: settingsURL)!
        let prefSpecifiers = settingsRootDict["PreferenceSpecifiers"] as! [NSDictionary]
        
        let configurableSpecifiers = prefSpecifiers.filter { $0["Key"] != nil } // Not all settings items are meant to be read (like section titles, or groups)
        let keysAndValues: [(String, Any)] = configurableSpecifiers.map {
            ($0["Key"] as! String, $0["DefaultValue"]!)
        }
        
        UserDefaults.standard.register(defaults: Dictionary(uniqueKeysWithValues: keysAndValues))
    }
}

class SettingsService {
    
    static let observer = SettingsChangeObserver()
    
    static func initialize() {
        UserDefaults.standard.addObserver(
            observer,
            forKeyPath: "max_offline_storage",
            options: [.initial, .new, .old],
            context: nil
        )
        
        UserDefaults.standard.addObserver(
            observer,
            forKeyPath: "offline_mode_enabled",
            options: [.new, .old],
            context: nil
        )
        
        UserDefaults.standard.addObserver(
            observer,
            forKeyPath: "text_speech_voice_identifier",
            options: [.new, .old],
            context: nil
        )
    }

    static func openAppSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
            GGLog.error("Unable to parse URL to open settings screen")
            return
        }
        
        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    private static var observers = [UUID : (Bool) -> Void]()
    
    @discardableResult
    static func observeOfflineModeChanged<T: AnyObject>(
        _ observer: T,
        closure: @escaping (T, Bool) -> Void
    ) -> ObservationToken {
        let id = UUID()
        
        observers[id] = { [weak observer] playbackState in
            guard let observer = observer else {
                observers.removeValue(forKey: id)
                return
            }

            closure(observer, playbackState)
        }
        
        return ObservationToken {
            observers.removeValue(forKey: id)
        }
    }
    
    fileprivate static func notifyOfflineModeChanged() {
        DispatchQueue.global().async {
            observers.values.forEach { $0(OfflineStorageService.offlineModeEnabled) }
        }
    }
}

class SettingsChangeObserver: NSObject {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let change = change else {
            GGLog.error("Setting '\(keyPath ?? "nil")' was triggered but no 'change' was found?")
            return
        }
        
        if keyPath == "max_offline_storage" {
            guard let newValue = change[NSKeyValueChangeKey.init(rawValue: "new")] as? Int else {
                if UserState.isLoggedIn {
                    GGLog.error("Could not parse 'max_offline_storage''s new value from 'change'!")
                }
                
                return
            }
            
            // The "initial" event does not contain an "old" value I guess. So if the old value is absent, it was the init.
            // Set the oldValue to be the newValue if it was nil, as that just makes sense and simplifies later logic in this function
            let oldValue = change[NSKeyValueChangeKey.init(rawValue: "old")] as? Int ?? newValue
            
            if oldValue != newValue {
                GGLog.info("User changed 'max_offline_storage' from \(oldValue) MB to \(newValue) MB")
            } else {
                GGLog.info("App was initialized with 'max_offline_storage' of \(newValue) MB")
            }
            
            if UserState.isLoggedIn {
                DispatchQueue.global().async {
                    if newValue < oldValue {
                        // User restricted how much space we are using. Make sure we purge excess data if there is any
                        OfflineStorageService.purgeExtraTrackDataIfNeeded()
                    } else if newValue > oldValue {
                        // User granted us additional storage. We should look to download more stuff if there is stuff to download
                        OfflineStorageService.downloadAlwaysOfflineMusic()
                    }
                }
            } else {
                GGLog.info("User was not logged in when offline storage handler was invoked. Not checking to purge extra tracks")
            }
        } else if keyPath == "offline_mode_enabled" {
            guard let newValue = change[NSKeyValueChangeKey.init(rawValue: "new")] as? Bool else {
                GGLog.critical("Could not parse 'offline_mode_enabled''s new value from 'change'!")
                return
            }
            
            guard let _ = change[NSKeyValueChangeKey.init(rawValue: "old")] as? Bool else {
                GGLog.info("Could not parse 'offline_mode_enabled''s old value from 'change'. Assuming this is a first time login")
                return
            }
            
            // Change this to broadcast and let other files observe it instead.
            // Then update NowPlayingTracks to remove tracks if offline mode is enabled
            GGLog.info("User changed 'offline_mode_enabled' to \(newValue)")
            
            SettingsService.notifyOfflineModeChanged()
            
            if newValue {
                WebSocket.disconnect()
            } else {
                if !AudioPlayer.isPaused {
                    WebSocket.connect()
                }
                
                DispatchQueue.global().async {
                    ServerSynchronizer.syncWithServer(abortIfRecentlySynced: true)
                }
            }
        } else if keyPath == "text_speech_voice_identifier" {
            TextSpeaker.speak("Your sound card works perfectly")
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
}
