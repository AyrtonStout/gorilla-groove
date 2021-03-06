import Foundation
import UIKit


class PlaylistsController : UIViewController, UITableViewDataSource, UITableViewDelegate {

    private var playlists: [Playlist] = []
    private let tableView = UITableView()

    private let activitySpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView()
        
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.color = Colors.foreground
        
        return spinner
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Playlists"
        
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addReviewSource)
        )
        
        self.view.addSubview(tableView)
        self.view.addSubview(activitySpinner)
        
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            activitySpinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activitySpinner.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
        ])
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(TableViewCell<Playlist>.self, forCellReuseIdentifier: "playlistCell")
        
        OfflineStorageService.addOfflineModeToggleObserverToVc(self)

        // Remove extra table row lines that have no content
        tableView.tableFooterView = UIView(frame: .zero)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        playlists = PlaylistDao.getPlaylists()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        GGNavLog.info("Loaded playlists view")
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return playlists.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let rawCell = tableView.dequeueReusableCell(withIdentifier: "playlistCell", for: indexPath)
        let cell = rawCell as! TableViewCell<Playlist>
        
        cell.textLabel!.text = playlists[indexPath.row].name
        cell.data = playlists[indexPath.row]
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        cell.addGestureRecognizer(tapGesture)
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(bringUpLongPressMenu))
        cell.addGestureRecognizer(longPressGesture)
        
        return cell
    }
    
    @objc private func handleTap(sender: UITapGestureRecognizer) {
        let cell = sender.view as! TableViewCell<Playlist>
        cell.animateSelectionColor()
        
        let playlist = cell.data!
        
        let view = PlaylistTrackController(playlist.name, originalView: .PLAYLIST, playlist: playlist, trackContextView: .PLAYLIST, loadTracksFunc: {
            let isSongCached = OfflineStorageService.offlineModeEnabled ? true : nil
            let playlistTracks = PlaylistTrackDao.getPlaylistTracksForPlaylist(playlist.id, isSongCached: isSongCached)
            
            let trackIds = playlistTracks.map { $0.trackId }
            let trackIdToTrack = TrackDao.findByIdIn(trackIds).keyBy { $0.id }
            
            return playlistTracks.map {
                PlaylistTrackWithTrack(id: $0.id, playlistId: playlist.id, track: trackIdToTrack[$0.trackId]!)
            }
        })
        self.navigationController!.pushViewController(view, animated: true)
    }
    
    @objc private func bringUpLongPressMenu(sender: UITapGestureRecognizer) {
        if sender.state != .began {
            return
        }
        
        let cell = sender.view as! TableViewCell<Playlist>
        var playlist = cell.data!
        
        let alert = GGActionSheet.create()
        
        alert.addAction(UIAlertAction(title: "Rename", style: .default, handler: { _ in
            ViewUtil.showTextFieldAlert(message: "Rename \(playlist.name) to:", yesText: "Rename") { [weak self] text in
                guard let this = self else { return }
                let request = PlaylistRequest(name: text)
                this.activitySpinner.startAnimating()
                
                HttpRequester.put("playlist/\(playlist.id)", EmptyResponse.self, request) { _, status, _ in
                    if !status.isSuccessful() {
                        DispatchQueue.main.async {
                            Toast.show("Could not rename playlist")
                            this.activitySpinner.stopAnimating()
                        }
                        return
                    }
                    playlist.name = text
                    PlaylistDao.save(playlist)
                    
                    DispatchQueue.main.async {
                        this.activitySpinner.stopAnimating()
                        cell.data = playlist
                        cell.textLabel!.text = playlist.name
                    }
                }
            }
        }))
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { _ in
            ViewUtil.showAlert(message: "Delete \(playlist.name)?", yesText: "Delete", yesStyle: .destructive) { [weak self] in
                guard let this = self else { return }
                this.activitySpinner.startAnimating()
                
                HttpRequester.delete("playlist/\(playlist.id)", nil) { _, status, _ in
                    if !status.isSuccessful() {
                        DispatchQueue.main.async {
                            Toast.show("Could not delete playlist")
                            this.activitySpinner.stopAnimating()
                        }
                        return
                    }
                    PlaylistDao.delete(playlist)
                    this.playlists = this.playlists.filter { $0.id != playlist.id }
                    
                    DispatchQueue.main.async {
                        this.activitySpinner.stopAnimating()
                        this.tableView.reloadData()
                    }
                }
            }
        }))
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            GGNavLog.info("User clicked context menu 'Cancel' button")
        }))
        
        ViewUtil.showAlert(alert)
    }
    
    @objc func addReviewSource() {
        GGNavLog.info("User tapped add playlist")
        
        ViewUtil.showTextFieldAlert(title: "Add Playlist", message: "Give it a name", yesText: "Add", dismissText: "Cancel") { [weak self] text in
            guard let this = self else { return }
            let request = PlaylistRequest(name: text)
            this.activitySpinner.startAnimating()
            
            HttpRequester.post("playlist", PlaylistResponse.self, request) { playlistResponse, status, _ in
                guard let newPlaylist = playlistResponse?.asEntity() as? Playlist else {
                    DispatchQueue.main.async {
                        if status.isSuccessful() {
                            Toast.show("Playlist created but could not be loaded")
                        } else {
                            Toast.show("Could not create playlist")
                        }
                        this.activitySpinner.stopAnimating()
                    }
                    return
                }
                
                PlaylistDao.save(newPlaylist)
                this.playlists = PlaylistDao.getPlaylists()
                
                DispatchQueue.main.async {
                    Toast.show("Playlist created")
                    this.activitySpinner.stopAnimating()
                    this.tableView.reloadData()
                }
            }
        }
    }
}

struct PlaylistRequest : Codable {
    let name: String
}

class PlaylistTrackWithTrack : TrackReturnable {
    let id: Int
    let playlistId: Int
    let track: Track
    
    init(
        id: Int,
        playlistId: Int,
        track: Track
    ) {
        self.id = id
        self.playlistId = playlistId
        self.track = track
    }
    
    func asTrack() -> Track {
        return track
    }
}
