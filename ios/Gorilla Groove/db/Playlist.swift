import Foundation

public struct Playlist : Entity {
    public var id: Int
    public var createdAt: Date?
    public var updatedAt: Date?
    public var name: String
    
    public static func fromDict(_ dict: [String : Any?]) -> Playlist {
        return Playlist(
            id: dict["id"] as! Int,
            createdAt: (dict["createdAt"] as! Int).toDate(),
            updatedAt: (dict["updatedAt"] as! Int).toDate(),
            name: dict["name"] as! String
        )
    }
}

public class PlaylistDao : BaseDao<Playlist> {
    static func getPlaylists() -> Array<Playlist> {
        return queryEntities("SELECT * FROM playlist ORDER BY name COLLATE NOCASE ASC")
    }
}
