import Foundation
import CoreData

class TrackService {
    
    static func getTracks(
        album: String? = nil,
        artist: String? = nil,
        sortOverrideKey: String? = nil,
        sortAscending: Bool = true,
        showHidden: Bool? = false
    ) -> [Track] {
        var sorts = [(String, Bool, Bool)]()
        
        // Sort differently depending on how we are trying to load things
        if sortOverrideKey != nil {
            sorts.append((sortOverrideKey!, sortAscending, true))
            
            if sortOverrideKey == "album" {
                sorts.append(("track_number", true, false))
            } else if sortOverrideKey == "year" {
                // I no longer remember why we add these additional sorts for year. I'm pretty sure it was a preference Audrey had
                // and she's the one who uses this sort the most so I'm just blindly copying them from web.
                sorts.append(("album", true, true))
                sorts.append(("track_number", true, false))
            }
        } else if artist != nil && album == nil {
            sorts.append(("album", sortAscending, true))
        } else if album != nil {
            sorts.append(("track_number", sortAscending, false))
        } else {
            sorts.append(("name", sortAscending, true))
        }
        
        return TrackDao.getTracks(
            album: album,
            artist: artist,
            isHidden: showHidden,
            isSongCached: OfflineStorageService.offlineModeEnabled ? true : nil,
            sorts: sorts
        )
    }
    
    // This doesn't update the play count. Waits for the server to sync it back down later. Possibly a mistake
    static func markTrackListenedTo(_ track: Track) {
        if !track.isOwnTrack { return }
        
        DispatchQueue.global().async {
            markTrackListenedToInternal(track.id)
        }
    }
    
    static func markTrackListenedToInternal(
        _ trackId: Int,
        _ retry: Int = 0,
        request: MarkListenedRequest? = nil,
        retrySemaphore: DispatchSemaphore? = nil
    ) {
        var postBody = request
        
        // Will be nil the first time we come through here. Will have data when we retry
        if postBody == nil {
            let listenTime = ISO8601DateFormatter().string(from: Date())
            
            let point = LocationService.getLocationPoint()
            
            postBody = MarkListenedRequest(
                trackId: trackId,
                timeListenedAt: listenTime,
                ianaTimezone: TimeZone.current.identifier,
                latitude: point?.coordinate.latitude,
                longitude: point?.coordinate.longitude
            )
        }
        
        if ProcessInfo.processInfo.isLowPowerModeEnabled || OfflineStorageService.offlineModeEnabled || retry > 3 {
            if retry > 3 {
                GGLog.error("Retry limit was reached!")
            }
            GGLog.info("Persisting record of Track \(trackId) to update the API later")
            var failedRequests = FileState.read(FailedListenRequests.self) ?? FailedListenRequests(requests: [])
            failedRequests.requests.append(postBody!)
            
            FileState.save(failedRequests)
            
            retrySemaphore?.signal()
            return
        }
        
        let requestSemaphore = retrySemaphore ?? DispatchSemaphore(value: 0)

        HttpRequester.post("track/mark-listened", EmptyResponse.self, postBody) { _, statusCode ,_ in
            if statusCode == 400 {
                GGLog.warning("400 status received marking a track as listened to. Did you screw up, Ayrton? Are you marking other users' tracks as listened to?")
                return
            }
            
            if (statusCode < 200 || statusCode >= 300) {
                GGLog.warning("Failed to mark track as listened to! For track with ID: \(trackId). Retrying...")
                self.markTrackListenedToInternal(trackId, retry + 1, request: postBody, retrySemaphore: requestSemaphore)
                return
            }
            
            GGLog.info("Track \(trackId) marked listened to")
            requestSemaphore.signal()
        }
        
        requestSemaphore.wait()
    }
    
    struct FailedListenRequests: Codable {
        var requests: [MarkListenedRequest]
    }
    
    struct MarkListenedRequest: Codable {
        let trackId: Int
        let timeListenedAt: String
        let ianaTimezone: String
        let latitude: Double?
        let longitude: Double?
    }
    
    static func retryFailedListens() {
        GGLog.debug("Retrying failed listens if there are any to retry...")
        
        let failedRequests = (FileState.read(FailedListenRequests.self) ?? FailedListenRequests(requests: [])).requests
        if failedRequests.isEmpty {
            return
        }
        
        // Delete them all, as we've got them in memory and we will iterate through them.
        // This is not perfect, as the app crashing here means that we will lose this information. Oh well. I'm lazy right now.
        FileState.save(FailedListenRequests(requests: []))
        
        GGLog.info("Found \(failedRequests.count) failed listen requests to retry")
        
        failedRequests.forEach { failedRequest in
            GGLog.info("Retrying listen request for track \(failedRequest.trackId) that happened at \(failedRequest.timeListenedAt)")
            markTrackListenedToInternal(failedRequest.trackId, 0, request: failedRequest)
        }
    }
    
    static func fetchLinksForTrack(
        track: Track,
        fetchSong: Bool,
        fetchArt: Bool,
        linkFetchHandler: @escaping (_ trackLinkResponse: TrackLinkResponse?) -> Void
    ) {
        // Specifying the links we want to fetch is a very slight optimization on the API side, as it does not have to generate
        // links for art if we are fetching just the song, or vice versa. This will rarely be separate. But if album art or
        // song data gets updated and our cache gets busted, then it could happen.
        let linkFetchType: String
        if !fetchSong && !fetchArt {
            return
        } else if fetchSong && !fetchArt {
            linkFetchType = "SONG"
        } else if !fetchSong && fetchArt {
            linkFetchType = "ART"
        } else {
            linkFetchType = "BOTH"
        }
        
        HttpRequester.get("file/link/\(track.id)?audioFormat=MP3&linkFetchType=\(linkFetchType)", TrackLinkResponse.self) { links, status , err in
            if status < 200 || status >= 300 || links == nil {
                GGLog.error("Failed to get track links!")
                return linkFetchHandler(links)
            }
            
            if fetchSong && links!.songLink == nil {
                GGLog.error("Fetched song links from the API for track with ID: \(track.id) but no link was returned!")
            }
            
            if fetchArt && links!.albumArtLink == nil {
                GGLog.error("Fetched art links from the API for track with ID: \(track.id) but no link was returned!")
            }
            
            linkFetchHandler(links)
        }
    }
    
    static func getArtistsFromTracks(_ tracks: [Track], showHidden: Bool = false) -> [String] {
        var uniqueArtists = Set<String>()
        
        var artists: [String] = []
        
        for track in tracks {
            if track.isHidden && !showHidden {
                continue
            }
            
            let lowerArtist = track.artist.lowercased()
            if !uniqueArtists.contains(lowerArtist) {
                uniqueArtists.insert(lowerArtist)
                artists.append(track.artist)
            }
            
            if !track.featuring.isEmpty {
                let lowerFeaturing = track.featuring.lowercased()
                if !uniqueArtists.contains(lowerFeaturing) {
                    uniqueArtists.insert(lowerFeaturing)
                    artists.append(track.featuring)
                }
            }
        }
        
        return artists.sorted()
    }
    
    static func getAlbumsFromTracks(_ tracks: [Track], artist: String? = nil, showHidden: Bool = false) -> [Album] {
        var uniqueAlbums: [String : Track] = [:]
        
        let lowerArtist = artist?.lowercased() ?? ""
        
        for track in tracks {
            if track.isHidden && !showHidden {
                continue
            }
            
            if artist == nil
                || (track.artist.lowercased().contains(lowerArtist) || track.featuring.lowercased().contains(lowerArtist))
                // If artist is an empty string, the track needs to not have an artist
                || (artist == "" && (track.artist == "" && track.featuring == "")) {
                let lowerAlbum = track.album.lowercased()
                if let alreadyFoundAlbum = uniqueAlbums[lowerAlbum] {
                    // We assume that all albums have the same art.
                    // So if one of them already has cached art, use that instead of the earlier one that was found
                    if alreadyFoundAlbum.thumbnailCachedAt == nil && track.thumbnailCachedAt != nil {
                        uniqueAlbums[lowerAlbum] = track
                    }
                } else {
                    uniqueAlbums[lowerAlbum] = track
                }
            }
        }
        
        return uniqueAlbums.values.map { track in
            Album(
                name: track.album,
                trackIdForArt: track.id,
                artCached: track.thumbnailCachedAt != nil
            )
        }.sorted() { $0.name < $1.name }
    }
    
    static func deleteTracks(_ tracks: [Track]) {
        let trackDeleteStr = tracks.map { $0.id.toString() }.joined(separator: ",")
        HttpRequester.delete("track?trackIds=\(trackDeleteStr)") { _, statusCode, _ in
            if statusCode.isSuccessful() {
                tracks.forEach { track in
                    TrackDao.delete(track)
                    broadcastTrackChange(track, type: .DELETION)
                }
                
                let plurality = tracks.count == 1 ? "Track" : "Tracks"
                Toast.show("\(plurality) deleted")
            } else {
                let plurality = tracks.count == 1 ? "the track" : "tracks"
                Toast.show("Failed to delete \(plurality)")
            }
        }
    }
    
    static func importTracks(_ tracks: [Track]) {
        let request = ImportTrackRequest(trackIds: tracks.map { $0.id })
        HttpRequester.post("track/import", ImportTrackResponse.self, request) { res, statusCode, _ in
            guard let trackResponses = res?.items.map({ $0.asTrack() }), statusCode.isSuccessful() else {
                let plurality = tracks.count == 1 ? "track" : "tracks"
                Toast.show("Failed to import \(plurality)!")
                return
            }
            
            trackResponses.forEach { TrackDao.save($0) }
            
            let plurality = tracks.count == 1 ? "Track" : "Tracks"
            Toast.show("\(plurality) imported")
        }
    }
    
    private static var observers = [UUID : (Track, TrackUpdateType) -> Void]()
    
    @discardableResult
    static func observeTrackChanges<T: AnyObject>(
        _ observer: T,
        closure: @escaping (T, Track, TrackUpdateType) -> Void
    ) -> ObservationToken {
        let id = UUID()
        
        observers[id] = { [weak observer] track, changeType in
            guard let observer = observer else {
                observers.removeValue(forKey: id)
                return
            }

            closure(observer, track, changeType)
        }
        
        return ObservationToken {
            observers.removeValue(forKey: id)
        }
    }
    
    static func broadcastTrackChange(_ track: Track, type: TrackUpdateType) {
        observers.values.forEach { $0(track, type) }
    }
}

struct TrackLinkResponse: Codable {
    let songLink: String?
    let albumArtLink: String?
}

struct ImportTrackRequest: Codable {
    let trackIds: [Int]
}

struct ImportTrackResponse: Codable {
    let items: [TrackResponse]
}

enum TrackUpdateType {
    case MODIFICATION
    case DELETION
}
