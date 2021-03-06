import Foundation

typealias PageCompleteCallback = (_ completedPage: Int, _ totalPages: Int, _ type: SyncType) -> Void

class ServerSynchronizer {
    
    static let baseUrl = "sync/entity-type/%@/minimum/%ld/maximum/%ld?size=400&page="
    
    private static var syncRunning = false
    
    static var lastSync: Date = {
        var syncStatuses = SyncStatusDao.getStatusByTypes(SyncType.allCases)

        return syncStatuses.map { $0.value.lastSyncAttempted }.max()!
    }()
    
    @discardableResult
    static func syncWithServer(
        syncTypes: [SyncType] = SyncType.allCases,
        pageCompleteCallback: PageCompleteCallback? = nil,
        abortIfRecentlySynced: Bool = false
    ) -> Set<SyncType> {
        
        if Thread.isMainThread {
            fatalError("Do not sync on the main thread!")
        }
        
        GGSyncLog.info("Initiating sync with server...")
        if syncRunning {
            GGSyncLog.info("Sync already running. Not syncing")
            return Set()
        }
        
        if OfflineStorageService.offlineModeEnabled {
            GGSyncLog.debug("Not syncing as we are in offline mode")
            return Set()
        }
        
        if abortIfRecentlySynced {
            if let diff = Calendar.current.dateComponents([.minute], from: lastSync, to: Date()).minute, diff >= 5 {
                GGSyncLog.debug("Last sync was old enough to do a new sync")
            } else {
                GGSyncLog.debug("Last sync was too recent. Not syncing")
                return Set()
            }
        }

        syncRunning = true
        
        let newDate = Date()
        let maximum = newDate.toEpochTime()
       
        var syncStatuses = SyncStatusDao.getStatusByTypes(syncTypes)
        syncTypes.forEach { syncType in
            syncStatuses[syncType]!.lastSyncAttempted = newDate
        }
        
        let (lastModifiedResponse, status, _) = HttpRequester.getSync("sync/last-modified", LastModifiedTimes.self)
        if !status.isSuccessful() {
            GGSyncLog.error("Could not get last modified times from the API. Not syncing")
            syncRunning = false
            return Set()
        }
        
        guard let lastModifiedTimestamps = lastModifiedResponse?.lastModifiedTimestamps else {
            GGSyncLog.error("Unable to parse last modified timestamps from the API. Not syncing")
            syncRunning = false
            return Set()
        }
        
        var syncsPerformed: Set<SyncType> = Set()
        var semaphores: [DispatchSemaphore] = []
        
        syncTypes.forEach { syncType in
            var syncStatus = syncStatuses[syncType]!
            let lastSynced = syncStatus.lastSynced
            let lastModified = lastModifiedTimestamps[syncType.rawValue]!

            if lastSynced < lastModified {
                GGSyncLog.debug("Syncing \(syncType). Last synced on device: \(lastSynced) and last modified on the server: \(lastModified)")
                
                let semaphore = DispatchSemaphore(value: 0)
                semaphores.append(semaphore)
                
                DispatchQueue.global().async {
                    var syncSuccess = true
                    
                    switch syncType {
                    case .track:
                        syncSuccess = TrackSynchronizer.sync(syncStatus, maximum, pageCompleteCallback)
                    case .playlist:
                        syncSuccess = PlaylistSynchronizer.sync(syncStatus, maximum, pageCompleteCallback)
                    case .playlistTrack:
                        syncSuccess = PlaylistTrackSynchronizer.sync(syncStatus, maximum, pageCompleteCallback)
                    case .user:
                        syncSuccess = UserSynchronizer.sync(syncStatus, maximum, pageCompleteCallback)
                    case .reviewSource:
                        syncSuccess = ReviewSourceSynchronizer.sync(syncStatus, maximum, pageCompleteCallback)
                    }
                    
                    if !syncSuccess {
                        GGSyncLog.error("Unable to completely sync entity \(syncStatus.syncType). Not saving sync date")
                    } else {
                        syncStatus.lastSynced = newDate
                        syncsPerformed.insert(syncType)
                        SyncStatusDao.save(syncStatus)
                    }
                    
                    semaphore.signal()
                }
            } else {
                SyncStatusDao.save(syncStatus)
            }
        }
        
        semaphores.forEach { $0.wait() }
        
        if OfflineStorageService.offlineModeEnabled {
            GGSyncLog.warning("Offline mode was enabled while we were syncing.")
        }
        
        // Don't update lastSync if we did a partial sync, as we could ignore syncing a particular endpoint for too long
        if syncTypes.count == SyncType.allCases.count {
            // Even if the sync is not entirely successful, we still want to update the last sync time so we dont just spam if there's an error
            lastSync = newDate
        }
        
        syncRunning = false

        GGSyncLog.info("Sync finished")
        
        DispatchQueue.global().async {
            TrackService.retryFailedListens()
        }
        
        return syncsPerformed
    }
}

struct EntityChangeResponse<T: Codable>: Codable {
    let content: EntityChangeContent<T>
    let pageable: EntitySyncPagination
}

struct EntityChangeContent<T: Codable>: Codable {
    let new: Array<T>
    let modified: Array<T>
    let removed: Array<Int>
}

struct EntitySyncPagination: Codable {
    let offset: Int
    let pageSize: Int
    let pageNumber: Int
    let totalPages: Int
    let totalElements: Int
}

struct LastModifiedTimes: Codable {
    // Can't deserialize to a raw value apparently, and I don't feel like renaming these enums to match the server since it feels wrong.
    // So I'm using a String here as it only needs to be converted to a SyncType in one place anyway...
//    let lastModifiedTimestamps: [SyncType: Date]
    let lastModifiedTimestamps: [String: Date]
}
