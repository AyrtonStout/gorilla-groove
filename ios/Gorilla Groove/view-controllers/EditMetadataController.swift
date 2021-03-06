import Foundation
import UIKit

class EditMetadataController : UIViewController {
    
    private let titleEntry = PropertyEntry("Name")
    private let artistEntry = PropertyEntry("Artist")
    private let featuringEntry = PropertyEntry("Featuring")
    private let albumEntry = PropertyEntry("Album")
    private let genreEntry = PropertyEntry("Genre")
    private let trackNumberEntry = PropertyEntry("Track #")
    private let releaseYearEntry = PropertyEntry("Year")
    private let noteEntry = PropertyEntry("Note")
    private let hiddenEntry = CheckboxEntry("Hidden")
    private let privateEntry = CheckboxEntry("Private")
    
    private var newOfflineAvailability: OfflineAvailabilityType? = nil
    private let offlineAvailability = createTextLabel("Offline Availability:")
    private let offlineAlways = createTextLabel("Always")
    private let offlineNormal = createTextLabel("Normal")
    private let offlineNever = createTextLabel("Never")
    private let offlineSlash1 = createTextLabel("/")
    private let offlineSlash2 = createTextLabel("/")
    
    private let fileSize = createTextLabel("File Size:")
    private let fileSizeValue = createTextLabel("")
    private let isCached = createTextLabel("Is Cached:")
    private let isCachedValue = createTextLabel("")
    
    private let albumArtView: UIImageView = {
        let view = UIImageView()
        
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = Colors.foreground
        // I eventually want tapping on this to let users pick one of three actions:
        // 1) Full screen view album art
        // 2) Set art from URL
        // 3) Undo an album art change that hasn't yet been saved
        // However, I tried to make these options available with an actionSheet and that will dismiss this view
        // as it's presented inside of a pageSheet. So I need to either present it differently or come up with a
        // new way for presenting options that isn't the native iOS actionSheet
        view.isUserInteractionEnabled = true
        
        return view
    }()
    
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .onDrag
        
        return scrollView
    }()
    
    private let leftActivitySpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView()
        
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = Colors.foreground
        spinner.hidesWhenStopped = true
        
        return spinner
    }()
    
    private let rightActivitySpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView()
        
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = Colors.foreground
        spinner.hidesWhenStopped = true
        
        return spinner
    }()
    
    private let track: Track
    private var newAlbumArtLink: String?
    
    init(track: Track) {
        // Not a huge fan of the DB call on the main thread, but I don't really want to put everything behind a loader
        // and deal with things relying on Track not being null in viewDidLoad() for the small main thread hit.
        // I think it's important to make sure this view has the latest data tho
        self.track = TrackDao.findById(track.id) ?? track
        super.init(nibName: nil, bundle: nil)
    }
    
    private lazy var leftNavButtonItem: UIBarButtonItem = {
        return UIBarButtonItem(title: "Get Info", style: .plain, target: self, action: #selector(getInfo))
    }()
    
    private lazy var rightNavButtonItem: UIBarButtonItem = {
        return UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Track Properties"
        
        self.view.backgroundColor = Colors.background
        
        self.navigationItem.leftBarButtonItem = leftNavButtonItem
        self.navigationItem.rightBarButtonItem = rightNavButtonItem
                
        let spacing: CGFloat = 17
        
        scrollView.addSubview(albumArtView)
        scrollView.addSubview(titleEntry)
        scrollView.addSubview(artistEntry)
        scrollView.addSubview(featuringEntry)
        scrollView.addSubview(albumEntry)
        scrollView.addSubview(genreEntry)
        scrollView.addSubview(trackNumberEntry)
        scrollView.addSubview(releaseYearEntry)
        scrollView.addSubview(noteEntry)
        scrollView.addSubview(hiddenEntry)
        scrollView.addSubview(privateEntry)
        scrollView.addSubview(leftActivitySpinner)
        scrollView.addSubview(rightActivitySpinner)
        scrollView.addSubview(offlineAvailability)
        scrollView.addSubview(offlineAlways)
        scrollView.addSubview(offlineNormal)
        scrollView.addSubview(offlineNever)
        scrollView.addSubview(offlineSlash1)
        scrollView.addSubview(offlineSlash2)
        scrollView.addSubview(fileSize)
        scrollView.addSubview(fileSizeValue)
        scrollView.addSubview(isCached)
        scrollView.addSubview(isCachedValue)

        self.view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: self.view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            scrollView.widthAnchor.constraint(equalTo: self.view.widthAnchor),
            scrollView.heightAnchor.constraint(equalTo: self.view.heightAnchor),
            
            albumArtView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: spacing),
            albumArtView.widthAnchor.constraint(equalToConstant: 150),
            albumArtView.heightAnchor.constraint(equalToConstant: 150),
            albumArtView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            
            titleEntry.topAnchor.constraint(equalTo: albumArtView.bottomAnchor, constant: spacing),
            titleEntry.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            artistEntry.topAnchor.constraint(equalTo: titleEntry.bottomAnchor, constant: spacing),
            artistEntry.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            featuringEntry.topAnchor.constraint(equalTo: artistEntry.bottomAnchor, constant: spacing),
            featuringEntry.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            albumEntry.topAnchor.constraint(equalTo: featuringEntry.bottomAnchor, constant: spacing),
            albumEntry.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            genreEntry.topAnchor.constraint(equalTo: albumEntry.bottomAnchor, constant: spacing),
            genreEntry.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            trackNumberEntry.topAnchor.constraint(equalTo: genreEntry.bottomAnchor, constant: spacing),
            trackNumberEntry.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            releaseYearEntry.topAnchor.constraint(equalTo: trackNumberEntry.bottomAnchor, constant: spacing),
            releaseYearEntry.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            noteEntry.topAnchor.constraint(equalTo: releaseYearEntry.bottomAnchor, constant: spacing),
            noteEntry.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            hiddenEntry.topAnchor.constraint(equalTo: noteEntry.bottomAnchor, constant: spacing),
            hiddenEntry.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            
            privateEntry.topAnchor.constraint(equalTo: hiddenEntry.bottomAnchor, constant: spacing),
            privateEntry.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            
            offlineAvailability.topAnchor.constraint(equalTo: privateEntry.bottomAnchor, constant: spacing),
            offlineAvailability.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 14),
            
            offlineAlways.topAnchor.constraint(equalTo: offlineAvailability.topAnchor),
            offlineAlways.leadingAnchor.constraint(equalTo: offlineAvailability.trailingAnchor, constant: 8),
            
            offlineSlash1.topAnchor.constraint(equalTo: offlineAvailability.topAnchor),
            offlineSlash1.leadingAnchor.constraint(equalTo: offlineAlways.trailingAnchor, constant: 8),
            
            offlineNormal.topAnchor.constraint(equalTo: offlineAvailability.topAnchor),
            offlineNormal.leadingAnchor.constraint(equalTo: offlineSlash1.trailingAnchor, constant: 8),
            
            offlineSlash2.topAnchor.constraint(equalTo: offlineAvailability.topAnchor),
            offlineSlash2.leadingAnchor.constraint(equalTo: offlineNormal.trailingAnchor, constant: 8),
            
            offlineNever.topAnchor.constraint(equalTo: offlineAvailability.topAnchor),
            offlineNever.leadingAnchor.constraint(equalTo: offlineSlash2.trailingAnchor, constant: 8),
            
            fileSize.topAnchor.constraint(equalTo: offlineAvailability.bottomAnchor, constant: spacing),
            fileSize.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 14),
            
            fileSizeValue.topAnchor.constraint(equalTo: fileSize.topAnchor),
            fileSizeValue.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: labelWidth + 15),
            
            isCached.topAnchor.constraint(equalTo: fileSize.bottomAnchor, constant: spacing),
            isCached.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 14),
            isCached.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -8),
            
            isCachedValue.topAnchor.constraint(equalTo: isCached.topAnchor),
            isCachedValue.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: labelWidth + 15),
            
            leftActivitySpinner.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 36),
            leftActivitySpinner.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 10),
            
            rightActivitySpinner.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -23),
            rightActivitySpinner.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 10),
        ])
        
        titleEntry.input.text = track.name
        artistEntry.input.text = track.artist
        featuringEntry.input.text = track.featuring
        albumEntry.input.text = track.album
        genreEntry.input.text = track.genre
        trackNumberEntry.input.text = track.trackNumber?.toString()
        releaseYearEntry.input.text = track.releaseYear?.toString()
        noteEntry.input.text = track.note
        hiddenEntry.input.isChecked = track.isHidden
        privateEntry.input.isChecked = track.isPrivate
        fileSizeValue.text = (track.filesizeSongMp3 + track.filesizeArtPng).toByteString()
        newOfflineAvailability = track.offlineAvailability
        isCachedValue.text = {
            if track.songCachedAt != nil {
                if track.artCachedAt != nil {
                    return "Yes"
                } else {
                    return "Audio Only"
                }
            } else {
                if track.artCachedAt != nil {
                    return "Art Only"
                } else {
                    return "No"
                }
            }
        }()
        colorOfflineAvailability()
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(adjustForKeyboard), name: UIResponder.keyboardWillHideNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(adjustForKeyboard), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        
        offlineAlways.isUserInteractionEnabled = true
        offlineNormal.isUserInteractionEnabled = true
        offlineNever.isUserInteractionEnabled = true
        
        offlineAlways.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(setAlwaysAvailable)))
        offlineNormal.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(setNormalAvailabile)))
        offlineNever.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(setNeverAvailable)))
        
        // Doesn't work properly. See comment in albumArtView initializer
//        albumArtView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(chooseNewArtFromUrl)))
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        GGNavLog.info("Loaded EditMetadataController")
        
        setInitialArt()
    }
    
    private func setInitialArt() {
        if track.hasAlbumArt {
            if track.artCachedAt != nil {
                if let cachedArt = CacheService.getCachedData(trackId: track.id, cacheType: .art) {
                    albumArtView.contentMode = .scaleAspectFit
                    albumArtView.image = UIImage(data: cachedArt)
                    return
                } else {
                    GGLog.error("Failed to find cached art data, despite the track thinking it had a cache! Clearing cache from DB for track \(track.id)")
                    CacheService.deleteCachedData(trackId: track.id, cacheType: .art, ignoreWarning: true)
                }
            }
            
            TrackService.fetchLinksForTrack(
                track: track,
                fetchSong: false,
                fetchArt: true
            ) { [self] trackLinkResponse in
                guard let response = trackLinkResponse else {
                    Toast.show("Could not fetch album art", view: self.view)
                    setNoAlbumArtPicture()
                    
                    return
                }
                
                if let artUrl = response.albumArtLink, !artUrl.isEmpty {
                    displayUrl(artUrl)
                }
            }
        } else {
            self.setNoAlbumArtPicture()
        }
    }
    
    private func colorOfflineAvailability() {
        [offlineAlways, offlineNormal, offlineNever].forEach {
            $0.textColor = Colors.foreground
        }
        
        switch newOfflineAvailability {
        case .AVAILABLE_OFFLINE:
            offlineAlways.textColor = Colors.primary
        case .NORMAL:
            offlineNormal.textColor = Colors.primary
        case .ONLINE_ONLY:
            offlineNever.textColor = Colors.primary
        case .UNKNOWN, .none: break;
        }
    }
    
    @objc private func setAlwaysAvailable() {
        newOfflineAvailability = .AVAILABLE_OFFLINE
        colorOfflineAvailability()
    }
    @objc private func setNormalAvailabile() {
        newOfflineAvailability = .NORMAL
        colorOfflineAvailability()
    }
    @objc private func setNeverAvailable() {
        newOfflineAvailability = .ONLINE_ONLY
        colorOfflineAvailability()
    }
    
    @objc private func chooseNewArtFromUrl() {
        ViewUtil.showTextFieldAlert(message: "Provide a URL for the new art", yesText: "Add", dismissText: "Cancel") { [weak self] url in
            self?.displayUrl(url)
        }
    }
    
    @objc private func save() {
        GGNavLog.info("User tapped 'save'")
        self.navigationItem.rightBarButtonItem = nil
        rightActivitySpinner.startAnimating()
        
        let trackNum = (trackNumberEntry.input.text ?? "").trim()
        let releaseYear = (releaseYearEntry.input.text ?? "").trim()

        if !trackNum.isEmpty && Int(trackNum) == nil {
            Toast.show("Track # must be a number", view: self.view)
            return
        }
        if !releaseYear.isEmpty && Int(releaseYear) == nil {
            Toast.show("Year must be a number", view: self.view)
            return
        }
        
        let request = UpdateTrackRequest(
            trackIds: [track.id],
            name: titleEntry.input.text ?? "",
            artist: artistEntry.input.text ?? "",
            featuring: featuringEntry.input.text ?? "",
            album: albumEntry.input.text ?? "",
            genre: genreEntry.input.text ?? "",
            trackNumber: Int(trackNum),
            note: noteEntry.input.text ?? "",
            releaseYear: Int(releaseYear),
            hidden: hiddenEntry.input.isChecked,
            private: privateEntry.input.isChecked,
            albumArtUrl: newAlbumArtLink,
            offlineAvailability: newOfflineAvailability
        )

        HttpRequester.put("track/simple-update", TrackUpdateResponse.self, request) { trackUpdateResponse, statusCode, _ in
            if let updatedTrack = trackUpdateResponse?.items.first, statusCode.isSuccessful() {
                let upToDateTrack = TrackDao.findById(self.track.id)!
                
                upToDateTrack.name = updatedTrack.name
                upToDateTrack.artist = updatedTrack.artist
                upToDateTrack.featuring = updatedTrack.featuring
                upToDateTrack.album = updatedTrack.album
                upToDateTrack.genre = updatedTrack.genre
                upToDateTrack.trackNumber = updatedTrack.trackNumber
                upToDateTrack.note = updatedTrack.note
                upToDateTrack.releaseYear = updatedTrack.releaseYear
                upToDateTrack.isHidden = updatedTrack.hidden
                upToDateTrack.isPrivate = updatedTrack.`private`
                upToDateTrack.offlineAvailability = OfflineAvailabilityType(rawValue: updatedTrack.offlineAvailability)!
                
                if self.newAlbumArtLink != nil {
                    upToDateTrack.filesizeArtPng = updatedTrack.filesizeArtPng
                    upToDateTrack.filesizeThumbnailPng = updatedTrack.filesizeThumbnail64x64Png
                    upToDateTrack.artCachedAt = nil
                }
                
                TrackDao.save(upToDateTrack)
                
                if upToDateTrack.offlineAvailability == .ONLINE_ONLY && (upToDateTrack.songCachedAt != nil || upToDateTrack.artCachedAt != nil) {
                    CacheService.deleteAllData(trackId: upToDateTrack.id)
                    upToDateTrack.songCachedAt = nil
                    upToDateTrack.artCachedAt = nil
                }
                
                TrackService.broadcastTrackChange(upToDateTrack, type: .MODIFICATION)
                
                if upToDateTrack.offlineAvailability == .AVAILABLE_OFFLINE && upToDateTrack.songCachedAt == nil {
                    OfflineStorageService.downloadAlwaysOfflineMusic()
                }
                
                DispatchQueue.main.async {
                    self.navigationController!.dismiss(animated: true)
                    Toast.show("Track data updated")
                }
            } else {
                DispatchQueue.main.async {
                    Toast.show("Failed to update track data", view: self.view)
                    self.navigationItem.rightBarButtonItem = self.rightNavButtonItem
                    self.rightActivitySpinner.stopAnimating()
                }
            }
        }
    }
    
    @objc private func getInfo() {
        GGNavLog.info("User tapped 'get info'")
        
        scrollView.firstResponder?.resignFirstResponder()
        
        guard let artist = artistEntry.input.text, !artist.isEmpty else {
            Toast.show("Artist must not be empty", view: self.view)
            return
        }
        
        guard let name = titleEntry.input.text, !name.isEmpty else {
            Toast.show("Name must not be empty", view: self.view)
            return
        }
        
        // I tried putting an activity spinner in here, but for whatever reason, the 2nd time it goes in there it doesn't animate.
        // It just holds still. This sucks because if you tap the "Get Info" item then tap the "Save" item the "save" item will never animate.
        // Makes it look like it's stuck and that you need to kill your app or something. I have now moved the spinners out sadly.
        self.navigationItem.leftBarButtonItem = nil
        leftActivitySpinner.startAnimating()
        
        HttpRequester.get("search/spotify/artist/\(artist)/name/\(name)/length/\(track.length)", SpotifyTrackSearchResponse.self) { [self] response, status, _ in
            DispatchQueue.main.async {
                self.navigationItem.leftBarButtonItem = leftNavButtonItem
                leftActivitySpinner.stopAnimating()
            }
            
            guard let items = response?.items, status.isSuccessful() else {
                GGLog.error("Failed to get a metadata search response for artist '\(artist)' and name '\(name)'!")
                DispatchQueue.main.async {
                    Toast.show("Metadata could not be fetched", view: self.view)
                }
                
                return
            }
            
            guard let metadata = items.first else {
                DispatchQueue.main.async {
                    Toast.show("No info could be found", view: self.view)
                }
                return
            }
            
            DispatchQueue.main.async { [self] in
                albumEntry.setEditedTextIfNeeded(metadata.album)
                trackNumberEntry.setEditedTextIfNeeded(metadata.trackNumber.toString())
                releaseYearEntry.setEditedTextIfNeeded(metadata.releaseYear.toString())
            }
            
            if let artLink = metadata.albumArtLink {
                displayUrl(artLink)
                newAlbumArtLink = artLink
            }
        }
    }
    
    private func displayUrl(_ artLink: String) {
        DispatchQueue.global().async {
            guard let image = UIImage.fromUrl(artLink) else {
                GGLog.error("Could not display album art from URL \(artLink)")
                Toast.show("Could not display new album art")
                
                return
            }
            
            DispatchQueue.main.async { [self] in
                albumArtView.contentMode = .scaleAspectFit
                albumArtView.image = image
            }
        }
    }
    
    private func setNoAlbumArtPicture() {
        albumArtView.contentMode = .center
        albumArtView.image = SFIconCreator.create("music.note", weight: .light, scale: .large, multiplier: 6.0)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.view.endEditing(true)
    }
    
    @objc func adjustForKeyboard(notification: Notification) {
        guard let keyboardValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        
        let keyboardScreenEndFrame = keyboardValue.cgRectValue
        let keyboardViewEndFrame = view.convert(keyboardScreenEndFrame, from: view.window)

        if notification.name == UIResponder.keyboardWillHideNotification {
            scrollView.contentInset = .zero
        } else {
            scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: keyboardViewEndFrame.height - view.safeAreaInsets.bottom, right: 0)
        }

        scrollView.scrollIndicatorInsets = scrollView.contentInset

        guard let activeInput = scrollView.firstResponder?.superview else {
            GGLog.error("Could not find active input when keyboard came up during metadata editing!")
            return
        }
        
        let point = activeInput.frame.origin
        
        // I can't find a way to get the visible bounds of a scrollView. So I take its bounds and subtract its insets
        // to get its actual bounds here.
        let bounds = CGRect(
            x: scrollView.bounds.minX,
            y: scrollView.bounds.minY,
            width: scrollView.bounds.width,
            height: scrollView.bounds.height - scrollView.contentInset.bottom
        )
        
        // If the input is already visible, don't mess with the view as it's jarring.
        if bounds.contains(activeInput.frame) {
            return
        }
        
        // Don't want the scroll to go below the scrollView
        let bottomOffset = scrollView.contentSize.height - scrollView.bounds.size.height + scrollView.contentInset.bottom
        
        GGLog.info("Point: \(point.x), \(point.y)")
        scrollView.contentOffset = CGPoint(x: 0, y: min(point.y, bottomOffset))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

fileprivate let labelWidth: CGFloat = 90

fileprivate class PropertyEntry : UIView, UITextFieldDelegate  {
    
    let label: UILabel = {
        let label = UILabel()
        label.font = label.font.withSize(17)
        label.textColor = Colors.tableText
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = true
        
        return label
    }()
    
    let input: UITextField = {
        let field = UITextField()
        field.textColor = Colors.tableText
        field.translatesAutoresizingMaskIntoConstraints = false
        field.autocorrectionType = .no
        
        return field
    }()
    
    private let bottomInputLine: UIView = {
        let view = UIView()
        
        view.backgroundColor = Colors.inputLine
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        
        return view
    }()
    
    func setEditedTextIfNeeded(_ newValue: String) {
        if input.text != newValue {
            input.text = newValue
            input.textColor = Colors.primary
        }
    }
    
    init(_ labelText: String) {
        super.init(frame: .zero)
        
        label.text = labelText + ":"
        input.delegate = self
        input.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        self.addSubview(label)
        self.addSubview(input)
        self.addSubview(bottomInputLine)
        
        self.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 14),
            label.widthAnchor.constraint(equalToConstant: labelWidth),
            input.leadingAnchor.constraint(equalTo: label.trailingAnchor),
            input.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -14),
            bottomInputLine.leadingAnchor.constraint(equalTo: input.leadingAnchor),
            bottomInputLine.trailingAnchor.constraint(equalTo: input.trailingAnchor),
            bottomInputLine.topAnchor.constraint(equalTo: input.bottomAnchor, constant: 1),
            self.heightAnchor.constraint(equalToConstant: 25),
        ])
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    @objc private func textFieldDidChange() {
        input.textColor = Colors.tableText
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

fileprivate class CheckboxEntry : UIView {
    
    let label: UILabel = {
        let label = UILabel()
        label.font = label.font.withSize(17)
        label.textColor = Colors.tableText
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = true
        
        return label
    }()
    
    let input: GGCheckbox = GGCheckbox(size: 25)
    
    init(_ labelText: String) {
        super.init(frame: .zero)
        
        label.text = labelText + ":"
        
        self.addSubview(label)
        self.addSubview(input)
        
        self.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 14),
            label.widthAnchor.constraint(equalToConstant: labelWidth),
            input.leadingAnchor.constraint(equalTo: label.trailingAnchor),
            input.trailingAnchor.constraint(equalTo: self.trailingAnchor), // This constraint is somehow necessary for it being tappable
            input.topAnchor.constraint(equalTo: self.topAnchor, constant: -3),
            self.heightAnchor.constraint(equalToConstant: 25),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

fileprivate func createTextLabel(_ text: String) -> UILabel {
    let field = UILabel()
    field.font = field.font!.withSize(17)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.textColor = Colors.foreground
    field.text = text
    
    return field
}


struct TrackUpdateResponse : Codable {
    let items: [TrackResponse]
}
