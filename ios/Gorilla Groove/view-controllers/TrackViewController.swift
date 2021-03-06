import UIKit
import Foundation

class TrackViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, MultiSelectTable {
    
    private var loadTracksFunc: (() -> [TrackReturnable])? = nil
    var trackIds: [Int] = []
    var trackIdToTrack: [Int: TrackReturnable] = [:]
    var visibleTrackIds: [Int] = []
    private let scrollPlayedTrackIntoView: Bool
    let tableView = UITableView()
    private let artistFilter: String?
    private let albumFilter: String?
    private var sortOverrideKey: String? = nil
    private var sortDirectionAscending: Bool = true
    private let user: User?
    let playlist: Playlist?
    private let alwaysReload: Bool
    private let trackContextView: TrackContextView

    private var showHiddenTracks: Bool
    private var lastOfflineMode: Bool
    
    var multiSelectEnabled = false {
        didSet {
            setMultiSelect(multiSelectEnabled)
        }
    }
    
    private lazy var multiSelectActionItem = UIBarButtonItem(
        image: SFIconCreator.create("ellipsis", weight: .medium, scale: .large, multiplier: 1.2),
        style: .plain,
        action: { [weak self] in
            guard let this = self else { return }
            let tracks = this.selectedIndexes.map { this.trackIdToTrack[this.visibleTrackIds[$0]]!.asTrack() }
            this.bringUpSongContextMenu(tracks)
        }
    )
    
    let originalView: LibraryViewType
    
    private let sortsIndex = 1
    
    private var selectedIndexes = Set<Int>()
    
    private lazy var filterOptions: [[FilterOption]] = {
        if originalView == .PLAYLIST || originalView == .NOW_PLAYING {
            return []
        }
        
        let albumSort = originalView == .ARTIST || originalView == .ALBUM
        
        let options = [
            MyLibraryHelper.getNavigationOptions(vc: self, viewType: originalView, user: user),
            [
                FilterOption("Sort by Name", filterImage: albumSort ? .NONE : .ARROW_UP) { [weak self] option in
                    guard let this = self else { return }
                    this.handleSortChange(option: option, key: this.getSortKey("name"), initialSortAsc: true)
                },
                FilterOption("Sort by Play Count") { [weak self] option in
                    guard let this = self else { return }
                    this.handleSortChange(option: option, key: this.getSortKey("play_count"), initialSortAsc: false)
                },
                FilterOption("Sort by Date Added") { [weak self] option in
                    guard let this = self else { return }
                    this.handleSortChange(option: option, key: this.getSortKey("added_to_library"), initialSortAsc: false)
                },
                FilterOption("Sort by Album", filterImage: albumSort ? .ARROW_UP : .NONE) { [weak self] option in
                    guard let this = self else { return }
                    this.handleSortChange(option: option, key: this.getSortKey("album"), initialSortAsc: true)
                },
                FilterOption("Sort by Year") { [weak self] option in
                    guard let this = self else { return }
                    this.handleSortChange(option: option, key: this.getSortKey("year"), initialSortAsc: true)
                },
            ],
            [
                FilterOption("Show Hidden Tracks", filterImage: showHiddenTracks ? .CHECKED : .NONE) { [weak self] option in
                    guard let this = self else { return }
                    this.showHiddenTracks = !this.showHiddenTracks
                    option.filterImage = this.showHiddenTracks ? .CHECKED : .NONE
                    this.filter?.reloadData()
                    this.loadTracks()
                },
            ]
        ]
        
        sortOverrideKey = albumSort ? "album" : "name"

        return options
    }()
    
    // Web uses different sort keys than the app's DB
    func getSortKey(_ key: String) -> String {
        switch (key) {
        case "name": return key
        case "play_count": return user == nil ? key : "playCount"
        case "added_to_library": return user == nil ? key : "addedToLibrary"
        case "album": return user == nil ? key : "album"
        case "year": return user == nil ? "release_year" : "releaseYear"
        default:
            fatalError("Unsupported sort key: \(key)")
        }
    }
    
    private lazy var filter: TableFilter? = {
        if !filterOptions.isEmpty {
            return TableFilter(filterOptions, vc: self)
        } else {
            return nil
        }
    }()
    
    private func handleSortChange(option: FilterOption, key: String, initialSortAsc: Bool) {
        // This [1] is so dumb don't hate me
        filterOptions[1].forEach { $0.filterImage = .NONE }
        
        if sortOverrideKey == key {
            sortDirectionAscending = !sortDirectionAscending
        } else {
            sortDirectionAscending = initialSortAsc
            sortOverrideKey = key
        }
        option.filterImage = sortDirectionAscending ? .ARROW_UP : .ARROW_DOWN
        
        filter!.reloadData()
        loadTracks()
    }
    
    private let activitySpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView()
        
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.color = Colors.foreground
        
        return spinner
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        GGNavLog.info("Loaded track view")

        view.addSubview(tableView)
        view.addSubview(activitySpinner)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            activitySpinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activitySpinner.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
        ])
        filter?.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        filter?.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -10).isActive = true
        
        tableView.keyboardDismissMode = .onDrag
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(TrackViewCell.self, forCellReuseIdentifier: "songCell")
        
        // Remove extra table rows when we don't have a full screen of songs
        // Might possibly use this to display warnings for like, offline mode or w/e later
        let footerView = UIView(frame: CGRect.init(x: 0, y: 0, width: tableView.frame.width, height: 0))
        footerView.backgroundColor = UIColor.green
        tableView.tableFooterView = footerView
        
        TableSearchAugmenter.addSearchToNavigation(
            controller: self,
            tableView: tableView,
            onTap: { [weak self] in
                self?.filter?.setIsHiddenAnimated(true)
                self?.setEditing(false, animated: true)
            }
        ) { [weak self] _ in
            self?.setVisibleTracks()
        }
        
        NowPlayingTracks.addTrackChangeObserver(self) { vc, track, type in
            if type == .NOW_PLAYING {
                DispatchQueue.main.async {
                    vc.tableView.visibleCells.forEach { cell in
                        let songViewCell = cell as! TrackViewCell
                        let indexPath = vc.tableView.indexPath(for: cell)!
                        vc.checkIfCellIsPlaying(songViewCell, indexPath: indexPath)
                    }
                }
            }
        }
        
        // If offline mode changes while we're actively looking at this VC, then we should update it.
        // Otherwise, it will update when the user loads the view later.
        SettingsService.observeOfflineModeChanged(self) { _, offlineModeEnabled in
            DispatchQueue.main.async { [weak self] in
                if self?.isActiveVc == true {
                    self?.lastOfflineMode = OfflineStorageService.offlineModeEnabled
                    self?.loadTracks()
                }
            }
        }
        
        let multiSelectItem = UIBarButtonItem(
            image: SFIconCreator.create("square.on.square", weight: .medium, scale: .large, multiplier: 1.2),
            style: .plain,
            action: { [weak self] in
                guard let this = self else { return }
                this.multiSelectEnabled = !this.multiSelectEnabled
            }
        )
        
        navigationItem.leftItemsSupplementBackButton = true
        navigationItem.leftBarButtonItem = multiSelectItem
        
        OfflineStorageService.addOfflineModeToggleObserverToVc(self)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(closeFilter))
        view.addGestureRecognizer(tapGesture)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if visibleTrackIds.isEmpty || alwaysReload || lastOfflineMode != OfflineStorageService.offlineModeEnabled {
            lastOfflineMode = OfflineStorageService.offlineModeEnabled
            loadTracks()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        filter?.isHidden = true
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return visibleTrackIds.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "songCell", for: indexPath) as! TrackViewCell
        let trackId = visibleTrackIds[indexPath.row]
        let track = trackIdToTrack[trackId]!
        
        cell.track = track.asTrack()
        
        if !tableView.isEditing {
            applyGestureRecognizers(cell)
        }
            
        return cell
    }
    
    private func applyGestureRecognizers(_ cell: TrackViewCell) {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        cell.addGestureRecognizer(tapGesture)
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressMenu))
        cell.addGestureRecognizer(longPressGesture)
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let songViewCell = cell as! TrackViewCell
        checkIfCellIsPlaying(songViewCell, indexPath: indexPath)
        
        if multiSelectEnabled {
            songViewCell.setSelectionModeEnabled(multiSelectEnabled)
            if selectedIndexes.contains(indexPath.row) {
                songViewCell.setSelected(true, animated: false)
            }
        }
    }
    
    func checkIfCellIsPlaying(_ cell: TrackViewCell, indexPath: IndexPath) {
        cell.checkIfPlaying()
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        
        tableView.setEditing(editing, animated: animated)
        
        // Have had serious issues with click handlers interfering with the reordering process. Can't handle it in their respective click handlers
        // because they interfere with the process before the click handler even fires.
        // Clear the handlers if we're editing, and of course, put them back if we're not.
        tableView.visibleCells.forEach { cell in
            let songViewCell = cell as! TrackViewCell
            if editing {
                songViewCell.gestureRecognizers?.removeAll()
            } else {
                applyGestureRecognizers(songViewCell)
            }
        }
        
        editingChanged(editing)
    }
    
    func editingChanged(_ isEditing: Bool) { /* For subclassing */ }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        filter?.setIsHiddenAnimated(true)
    }
    
    @objc private func closeFilter(sender: UITapGestureRecognizer) {
        filter?.setIsHiddenAnimated(true)
    }
    
    @objc private func handleTap(sender: UITapGestureRecognizer) {
        filter?.setIsHiddenAnimated(true)
        
        let cell = sender.view as! TrackViewCell
        let tableIndex = tableView.indexPath(for: cell)!
        
        if multiSelectEnabled {
            if cell.isSelected {
                selectedIndexes.remove(tableIndex.row)
            } else {
                selectedIndexes.insert(tableIndex.row)
            }
            
            cell.setSelected(!cell.isSelected, animated: true)
            return
        }
        
        cell.animateSelectionColor()
        
        if originalView == .NOW_PLAYING {
            NowPlayingTracks.setNowPlayingIndex(tableIndex.row)
        } else {
            let visibleTracks = visibleTrackIds.map { trackIdToTrack[$0]!.asTrack() }
            NowPlayingTracks.setNowPlayingTracks(visibleTracks, playFromIndex: tableIndex.row)
        }
        
        if let search = navigationItem.searchController {
            search.searchBar.delegate!.searchBarTextDidEndEditing!(search.searchBar)
        }
    }
    
    @objc private func handleLongPressMenu(sender: UITapGestureRecognizer) {
        if sender.state != .began || multiSelectEnabled {
            return
        }
        
        let cell = sender.view as! TrackViewCell
        
        let tableIndex = tableView.indexPath(for: cell)!
        let trackId = visibleTrackIds[tableIndex.row]
        let track = trackIdToTrack[trackId]!.asTrack()
        
        bringUpSongContextMenu([track])
    }
    
    private func bringUpSongContextMenu(_ tracks: [Track]) {
        let alert = TrackContextMenu.createMenuForTracks(tracks, view: trackContextView, playlist: playlist, parentVc: self)
        
        ViewUtil.showAlert(alert)
    }
    
    // TBH I don't really like how I've done this. Now that this can take either DB or Web tracks, I'd rather rework this so that
    // the tracks are loaded in from either source, and then sorted by this controller
    func loadTracks(scrollIntoView: Bool = false) {
        if multiSelectEnabled {
            multiSelectEnabled = false
        }
        
        activitySpinner.startAnimating()
        
        if user == nil {
            loadDbTracks()
        } else {
            loadWebTracks()
        }
    }
    
    private func setVisibleTracks() {
        let searchTerm = searchText.lowercased()
        if (searchTerm.isEmpty) {
            visibleTrackIds = trackIds
        } else {
            visibleTrackIds = trackIds.filter {
                let track = trackIdToTrack[$0]!.asTrack()
                return track.name.lowercased().contains(searchTerm)
            }
        }
    }
    
    private func loadDbTracks() {
        DispatchQueue.global().async { [weak self] in
            guard let this = self else { return }
            let loadFunc: (() -> [TrackReturnable]) = this.loadTracksFunc ?? {
                TrackService.getTracks(
                    album: this.albumFilter,
                    artist: this.artistFilter,
                    sortOverrideKey: this.sortOverrideKey,
                    sortAscending: this.sortDirectionAscending,
                    showHidden: this.showHiddenTracks ? nil : false // nil returns both hidden and not hidden, which is what we want
                )
            }
            
            let tracks = loadFunc()
            this.trackIds = tracks.map { $0.asTrack().id }
            this.trackIdToTrack = tracks.keyBy { $0.asTrack().id }
            
            DispatchQueue.main.async {
                this.setVisibleTracks()
                
                this.activitySpinner.stopAnimating()
                this.tableView.reloadData()
                
                if this.scrollPlayedTrackIntoView && NowPlayingTracks.nowPlayingIndex >= 0 {
                    let indexPath = IndexPath(row: NowPlayingTracks.nowPlayingIndex, section: 0)
                    this.tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
                } else if !this.visibleTrackIds.isEmpty {
                    // Reset the view to the top after reloading
                    let indexPath = IndexPath(row: 0, section: 0)
                    this.tableView.scrollToRow(at: indexPath, at: .top, animated: false)
                }
            }
        }
    }
    
    private func loadWebTracks() {
        let sortDir = sortDirectionAscending ? "ASC" : "DESC"
        let extraSort: String
        if sortOverrideKey == "album" {
            extraSort = "&sort=trackNumber,ASC"
        } else if sortOverrideKey == "releaseYear" {
            extraSort = "&sort=album,ASC&sort=trackNumber,ASC"
        } else {
            extraSort = ""
        }
        
        // Offload some processing by providing a search term if we have an artist.
        // Will dramatically reduce the number of things we need to process
        let searchTerm = artistFilter == nil ? "" : "&searchTerm=\(artistFilter!)"
        
        let url = "track?userId=\(user!.id)&sort=\(sortOverrideKey!),\(sortDir)\(extraSort)\(searchTerm)&size=100000&page=0&showHidden=\(showHiddenTracks)"
        HttpRequester.get(url, LiveTrackRequest.self) { [weak self] res, status, _ in
            guard let this = self else { return }
            guard var tracks = res?.content, status.isSuccessful() else {
                this.trackIds = []
                this.trackIdToTrack = [:]
                
                DispatchQueue.main.async {
                    this.setVisibleTracks()

                    Toast.show("Could not load tracks")
                    this.tableView.reloadData()
                }
                return
            }
            
            // We provide the artist search term to the API, but because the search term on the API side searches for multiple fields,
            // we need to make sure it's actually valid on our side. It will be the majority of the time
            if let artistFilter = this.artistFilter?.lowercased() {
                // If artist filter is an empty string, we specifically only want tracks without artists
                if artistFilter == "" {
                    tracks = tracks.filter { $0.artist == "" && $0.featuring == "" }
                } else {
                    tracks = tracks.filter { $0.artist.lowercased().contains(artistFilter) || $0.featuring.lowercased().contains(artistFilter) }
                }
            }
            if let albumFilter = this.albumFilter?.lowercased() {
                // If album filter is an empty string, we specifically only want tracks without albums
                if albumFilter == "" {
                    tracks = tracks.filter { $0.album == "" }
                } else {
                    tracks = tracks.filter { $0.album.lowercased().contains(albumFilter) }
                }
            }
            
            this.trackIds = tracks.map { $0.id }
            this.trackIdToTrack = tracks.map { $0.asTrack(userId: this.user?.id ?? 0) }.keyBy { $0.asTrack().id }
            
            DispatchQueue.main.async {
                this.setVisibleTracks()

                this.activitySpinner.stopAnimating()
                this.tableView.reloadData()
                
                // Reset the view to the top after reloading
                if !this.visibleTrackIds.isEmpty { // I don't THINK this should ever be empty. But it's a crash if it is
                    let indexPath = IndexPath(row: 0, section: 0)
                    this.tableView.scrollToRow(at: indexPath, at: .top, animated: false)
                }
            }
        }
    }
    
    private func addMultiSelectActionItem() {
        var newNavItems = navigationItem.rightBarButtonItems ?? []
        newNavItems.append(multiSelectActionItem)
        navigationItem.rightBarButtonItems = newNavItems
    }
    
    private func removeSelectActionItem() {
        navigationItem.rightBarButtonItems = navigationItem.rightBarButtonItems?.filter { $0 != multiSelectActionItem }
    }
    
    private func setMultiSelect(_ enabled: Bool) {
        tableView.visibleCells.forEach { cell in
            let songViewCell = cell as! TrackViewCell
            songViewCell.setSelectionModeEnabled(enabled)
        }
        
        if multiSelectEnabled {
            filter?.removeFilterFromNavigation()
            addMultiSelectActionItem()
        } else {
            removeSelectActionItem()
            filter?.addFilterToNavigation()
            selectedIndexes.removeAll()
        }
    }
    
    init(
        _ title: String,
        scrollPlayedTrackIntoView: Bool = false,
        originalView: LibraryViewType,
        artistFilter: String? = nil,
        albumFilter: String? = nil,
        user: User? = nil,
        playlist: Playlist? = nil,
        alwaysReload: Bool = false,
        trackContextView: TrackContextView? = nil,
        showingHidden: Bool? = nil,
        loadTracksFunc: (() -> [TrackReturnable])? = nil
    ) {
        self.scrollPlayedTrackIntoView = scrollPlayedTrackIntoView
        self.loadTracksFunc = loadTracksFunc
        self.originalView = originalView
        self.artistFilter = artistFilter
        self.albumFilter = albumFilter
        self.user = user
        self.playlist = playlist
        self.alwaysReload = alwaysReload
        self.trackContextView = trackContextView ?? (user == nil ? .MY_LIBRARY : .OTHER_USER)
        self.lastOfflineMode = OfflineStorageService.offlineModeEnabled
        self.showHiddenTracks = showingHidden ?? (user != nil) // Hidden tracks are for our own benefit, so don't show them by default when looking at our own library (user == nil)
        
        super.init(nibName: nil, bundle: nil)
        
        self.title = title
        
        // We hold track data fairly long term in this controller a lot of the time. Subscribe to broadcasts for track changes
        // so that we can update our track information in real time
        TrackService.observeTrackChanges(self) { vc, changedTrack, changeType in
            if vc.trackIdToTrack[changedTrack.id] == nil {
                return
            }
            
            if changeType == .MODIFICATION {
                vc.trackIdToTrack[changedTrack.id] = changedTrack
                
                DispatchQueue.main.async {
                    vc.tableView.visibleCells.forEach { cell in
                        let songViewCell = cell as! TrackViewCell
                        if songViewCell.track!.id == changedTrack.id {
                            songViewCell.track = changedTrack
                        }
                    }
                }
            }
            
            if changeType == .DELETION || (!vc.showHiddenTracks && changedTrack.isHidden && originalView != .NOW_PLAYING) {
                GGLog.info("Removing existing track from track list in response to change")
                DispatchQueue.main.async {
                    if let index = vc.visibleTrackIds.index(where: { $0 == changedTrack.id }) {
                        vc.visibleTrackIds.remove(at: index)
                        vc.tableView.deleteRows(at: [IndexPath(item: index, section: 0)], with: .automatic)
                    }
                }
            }
        }
        
        if playlist != nil {
            PlaylistService.observePlaylistTrackChanges(self) { vc, changedPlaylistTrack, changeType in
                if vc.playlist?.id != changedPlaylistTrack.playlistId {
                    return
                }
                
                if changeType != .REMOVAL {
                    return
                }

                // This is a bug. It only removes the first instance of this from the view. A track could be repeated on a playlist
                // multiple times. But it's such an unlikely scenario I don't feel like coding around it. Good programmer.
                if let index = vc.visibleTrackIds.index(where: { $0 == changedPlaylistTrack.trackId }) {
                    vc.visibleTrackIds.remove(at: index)
                    DispatchQueue.main.async {
                        vc.tableView.deleteRows(at: [IndexPath(item: index, section: 0)], with: .automatic)
                    }
                }
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

protocol TrackReturnable {
    func asTrack() -> Track
}

protocol MultiSelectTable {
    var multiSelectEnabled: Bool { get set }
}
