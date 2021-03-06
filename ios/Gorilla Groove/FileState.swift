import Foundation

class FileState {
    static func save<T: Codable>(_ data: T) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        
        let path = getPlistPath(T.self)
        
        do {
            let data = try encoder.encode(data)
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            GGLog.error("Could not save file state of type '\(type(of: data))': \(error.localizedDescription)")
        }
    }
    
    static func read<T: Codable>(_ type: T.Type) -> T? {
        let path = getPlistPath(type)
        
        let xml = FileManager.default.contents(atPath: path)
        if (xml == nil) {
            return nil
        }
        let savedState = try? PropertyListDecoder().decode(T.self, from: xml!)
        
        return savedState
    }
    
    static func clear<T: Codable>(_ type: T.Type) {
        let path = getPlistPath(type)
        
        try? FileManager.default.removeItem(atPath: path)
    }
    
    static private func getPlistPath<T>(_ type: T.Type) -> String {
        let plistFileName = "\(type).plist"
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let documentPath = paths[0] as NSString
        let plistPath = documentPath.appendingPathComponent(plistFileName)
        return plistPath
    }
}

struct LoginState: Codable {
    let token: String
    let id: Int
}

struct DeviceState: Codable {
    let deviceId: String
}
