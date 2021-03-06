package com.example.gorillagroove.activities

// TODO: Make this a fragment

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.media.AudioManager
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.util.Log
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.widget.Button
import android.widget.MediaController.MediaPlayerControl
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.ActionBarDrawerToggle
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.GravityCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.example.gorillagroove.R
import com.example.gorillagroove.adapters.OnItemClickListener
import com.example.gorillagroove.adapters.PlaylistAdapter
import com.example.gorillagroove.client.HttpClient
import com.example.gorillagroove.db.GroovinDB
import com.example.gorillagroove.db.repository.UserRepository
import com.example.gorillagroove.dto.PlaylistDTO
import com.example.gorillagroove.dto.PlaylistSongDTO
import com.example.gorillagroove.dto.Track
import com.example.gorillagroove.dto.User
import com.example.gorillagroove.service.MusicPlayerService
import com.example.gorillagroove.service.MusicPlayerService.MusicBinder
import com.example.gorillagroove.utils.URLs
import com.example.gorillagroove.utils.logger
import com.google.android.material.navigation.NavigationView
import kotlinx.android.synthetic.main.activity_playlist.*
import kotlinx.android.synthetic.main.app_bar_main.*
import kotlinx.coroutines.*
import org.greenrobot.eventbus.EventBus
import org.greenrobot.eventbus.Subscribe
import org.greenrobot.eventbus.ThreadMode
import java.util.concurrent.TimeUnit
import kotlin.system.exitProcess

const val PLAYLIST_GROUP_ID = 1
const val USER_LIBRARIES_GROUP_ID = 2

class PlaylistActivity : AppCompatActivity(),
        CoroutineScope by MainScope(), MediaPlayerControl, OnItemClickListener,
        NavigationView.OnNavigationItemSelectedListener, SeekBar.OnSeekBarChangeListener {

    private val httpClient = HttpClient()
    private val logger = logger()
    private val mHandler = Handler()

    private var musicBound = false
    private var repeatEnabled = false
    private var token: String = ""
    private var email: String = ""
    private var userName: String = ""
    private var deviceId: String = ""
    private var playbackPaused = true
    private var playIntent: Intent? = null
    private var musicPlayerService: MusicPlayerService? = null
    private var activeSongsList: List<PlaylistSongDTO> = emptyList()

    private lateinit var playButton: Button
    private lateinit var seekBar: SeekBar
    private lateinit var songPlayingTextView: TextView
    private lateinit var songPositionTextView: TextView
    private lateinit var songDurationTextView: TextView
    private lateinit var recyclerView: RecyclerView
    private lateinit var repository: UserRepository
    private var songCurrentPosition = 0
    private var songCurrentDuration = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_playlist)
        setSupportActionBar(toolbar)
        volumeControlStream = AudioManager.STREAM_MUSIC

        repository = UserRepository(GroovinDB.getDatabase().userRepository())

        // Start listening for events on the EventBus.
        // This is how we communicate between the MusicPlayerService and the PlaylistActivity.
        if (!EventBus.getDefault().isRegistered(this@PlaylistActivity)) {
            EventBus.getDefault().register(this@PlaylistActivity)
        }

        val toggle = ActionBarDrawerToggle(
                this@PlaylistActivity,
                drawer_layout,
                toolbar,
                R.string.navigation_drawer_open,
                R.string.navigation_drawer_close
        )
        drawer_layout.addDrawerListener(toggle)
        toggle.syncState()

        // Retrieve the metadata passed from the MainActivity
        token = intent.getStringExtra("token")
        userName = intent.getStringExtra("username")
        email = intent.getStringExtra("email")
        deviceId = intent.getStringExtra("deviceId")

        // Set the username in the drawer menu for the logged in user
        val header = nav_view.getHeaderView(0)
        val navHeaderText = header.findViewById(R.id.tv_nav_header) as TextView
        navHeaderText.text = userName

        // Initialize the seekbar
        seekBar = findViewById(R.id.seekBar_expanded_nav)
        seekBar.progress = 0
        seekBar.setOnSeekBarChangeListener(this)

        // Set up Media Controls
        val shuffleButton: Button = findViewById(R.id.button_expanded_nav_shuffle)
        shuffleButton.setOnClickListener {
            when (musicPlayerService!!.setShuffle()) {
                true -> it.setBackgroundResource(R.drawable.shuffle_active)
                false -> it.setBackgroundResource(R.drawable.shuffle_inactive)
            }
        }

        val repeatButton: Button = findViewById(R.id.button_expanded_nav_repeat)
        repeatButton.setOnClickListener {
            repeatEnabled = when (repeatEnabled) {
                true -> {
                    it.setBackgroundResource(R.drawable.repeat_inactive)
                    Toast.makeText(this, "The cake is a lie", Toast.LENGTH_SHORT).show()
                    false
                }
                false -> {
                    Toast.makeText(this, "Ha! Repeat is ALWAYS enabled!", Toast.LENGTH_SHORT).show()
                    it.setBackgroundResource(R.drawable.repeat_active)
                    true
                }
            }
        }

        playButton = findViewById(R.id.button_expanded_nav_play)
        playButton.setOnClickListener {
            when (playbackPaused) {
                true -> {
                    it.setBackgroundResource(android.R.drawable.ic_media_pause)
                    play()
                }
                false -> {
                    it.setBackgroundResource(android.R.drawable.ic_media_play)
                    pause()
                }
            }
        }

        val nextButton: Button = findViewById(R.id.button_expanded_nav_next)
        nextButton.setOnClickListener { playNext() }

        val previousButton: Button = findViewById(R.id.button_expanded_nav_previous)
        previousButton.setOnClickListener { playPrevious() }

        songPlayingTextView = findViewById(R.id.textView_expanded_nav_current_song)
        songPositionTextView = findViewById(R.id.textView_expanded_nav_position)
        songDurationTextView = findViewById(R.id.textView_expanded_nav_length)

        loadLibrarySongs()
        requestUsers()
        requestPlaylists()

        nav_view.setNavigationItemSelectedListener(this@PlaylistActivity)
    }

    // Load My Library and attach it to the adapter and music player
    private fun loadLibrarySongs() {
        httpClient.get(URLs.LIBRARY, LibraryResponse::class) { response ->
            activeSongsList = response.data.content.map { PlaylistSongDTO(0, it) }

            runOnUiThread {
                attachActiveSongsListToAdapter()
                if (musicBound) musicPlayerService!!.setSongList(activeSongsList)
            }
        }
    }


    // When a playlist is selected, load it and attach it to the adapter and music player
    private fun loadPlaylistSongs(playlistId: Long) {
        val url = "${URLs.PLAYLIST_BASE}playlistId=$playlistId&size=200"
        httpClient.get(url, PlaylistResponse::class) { response ->
            activeSongsList = response.data.content

            runOnUiThread {
                attachActiveSongsListToAdapter()
                if (musicBound) musicPlayerService!!.setSongList(activeSongsList)
            }
        }
    }

    // When a user library is selected, load it and attach it to the adapter and music player
    private fun loadUserLibraries(userId: Long) {
        httpClient.get("${URLs.LIBRARY}&userId=$userId", LibraryResponse::class) { response ->
            activeSongsList = response.data.content.map { PlaylistSongDTO(0, it) }

            runOnUiThread {
                attachActiveSongsListToAdapter()
                if (musicBound) musicPlayerService!!.setSongList(activeSongsList)
            }
        }
    }

    // Add the active songs list to the adapter
    private fun attachActiveSongsListToAdapter() {
        recyclerView = findViewById(R.id.rv_playlist)
        recyclerView.layoutManager = LinearLayoutManager(this)

        val playlistAdapter = PlaylistAdapter(activeSongsList)
        recyclerView.adapter = playlistAdapter
        playlistAdapter.setClickListener(this)
    }

    // Load in the other GG users library information and add it to the menu
    private fun requestUsers() {
        val menu = nav_view.menu
        val subMenu = menu.addSubMenu("User Libraries")

        httpClient.get(URLs.USER, Array<User>::class) { response ->
            if (!response.success) {
                logger.error("Failed to fetch users!")
                return@get
            }

            runOnUiThread {
                response.data.forEach { subMenu.add(USER_LIBRARIES_GROUP_ID, it.id.toInt(), 0, it.username) }
            }
        }
    }

    // Load in the user's playlists and them to the menu
    private fun requestPlaylists() {
        val menu = nav_view.menu
        val subMenu = menu.addSubMenu("Playlists")

        httpClient.get(URLs.PLAYLISTS, Array<PlaylistDTO>::class) { response ->
            if (!response.success) {
                logger.error("Failed to fetch playlists!")
                return@get
            }

            runOnUiThread {
                response.data.forEach { subMenu.add(PLAYLIST_GROUP_ID, it.id.toInt(), 1, it.name) }
            }
        }
    }

    //connect to the service
    private val musicConnection = object : ServiceConnection {

        override fun onServiceConnected(name: ComponentName, service: IBinder) {
            val binder = service as MusicBinder
            //get service
            musicPlayerService = binder.getService()
            //pass list
            musicPlayerService!!.setSongList(activeSongsList)
            musicBound = true
        }

        override fun onServiceDisconnected(name: ComponentName) {
            musicBound = false
        }
    }

    override fun onStart() {
        Log.i("PlaylistActivity", "onStart Called!")
        super.onStart()
        if (playIntent == null) {
            playIntent = Intent(this@PlaylistActivity, MusicPlayerService::class.java)
                    .putExtra("email", email)
                    .putExtra("token", token)
                    .putExtra("deviceId", deviceId)

            bindService(playIntent, musicConnection, Context.BIND_IMPORTANT)
            startService(playIntent)
        }
        if (!EventBus.getDefault().isRegistered(this@PlaylistActivity)) {
            EventBus.getDefault().register(this@PlaylistActivity)
        }
    }

    override fun onClick(view: View, position: Int) {
        logger.info("onClick called! and playbackPaused = $playbackPaused")
        musicPlayerService!!.setSong(position)
        if (!musicPlayerService!!.isPlaying()) {
            playButton.setBackgroundResource(android.R.drawable.ic_media_pause)
            playbackPaused = false
        }
        musicPlayerService!!.playSong()
        updateProgressBar()
    }

    override fun onBackPressed() {
        if (drawer_layout.isDrawerOpen(GravityCompat.START)) {
            drawer_layout.closeDrawer(GravityCompat.START)
        } else {
            super.onBackPressed()
        }
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        // Inflate the menu; This adds items to the action bar if it is present.
        menuInflater.inflate(R.menu.main, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        when (item.itemId) {
            R.id.action_end -> {
                stopService(playIntent)
                musicPlayerService = null
                exitProcess(0)
            }
            R.id.action_settings_logout -> {
                val user =
                        runBlocking { withContext(Dispatchers.IO) { repository.findUser(email) } }
                logout(user!!.id)
                exitProcess(0)
            }
        }
        return super.onOptionsItemSelected(item)
    }

    override fun onDestroy() {
        if (EventBus.getDefault().isRegistered(this@PlaylistActivity)) {
            EventBus.getDefault().unregister(this@PlaylistActivity)
        }
        stopService(playIntent)
        musicPlayerService = null
        super.onDestroy()
    }

    private fun playNext() {
        musicPlayerService!!.playNext()
        if (playbackPaused) {
            playbackPaused = false
        }
    }

    private fun playPrevious() {
        musicPlayerService!!.playPrevious()
        if (playbackPaused) {
            playbackPaused = false
        }
    }

    override fun isPlaying(): Boolean {
        return if (musicPlayerService != null && musicBound) musicPlayerService!!.isPlaying()
        else false
    }

    override fun canSeekForward(): Boolean {
        return true
    }

    override fun getDuration(): Int {
        if (musicPlayerService != null && musicBound && musicPlayerService!!.isPlaying()) {
            songCurrentDuration = musicPlayerService!!.getDuration()
        }
        return songCurrentDuration
    }

    override fun pause() {
        playbackPaused = true
        musicPlayerService!!.pausePlayer()
    }

    override fun seekTo(pos: Int) {
        musicPlayerService!!.seek(pos)
    }

    override fun getCurrentPosition(): Int {
        if (musicPlayerService != null && musicBound && musicPlayerService!!.isPlaying()) {
            songCurrentPosition = musicPlayerService!!.getPosition()
        }
        return songCurrentPosition
    }

    override fun canSeekBackward(): Boolean {
        return true
    }

    override fun start() {
        musicPlayerService!!.requestAudioFocus()
    }

    private fun play() {
        playbackPaused = false
        start()
    }

    override fun canPause(): Boolean {
        return true
    }

    override fun onPause() {
        super.onPause()
        playbackPaused = true
    }

    override fun onResume() {
        super.onResume()
        if (playbackPaused) {
            playbackPaused = false
        }
    }

    override fun getBufferPercentage(): Int {
        return musicPlayerService!!.getBufferPercentage()
    }

    override fun getAudioSessionId(): Int {
        return musicPlayerService!!.getAudioSessionId()
    }

    private fun logout(userId: Long) {
        runBlocking {
            withContext(Dispatchers.IO) {
                repository.logout(userId)
                stopService(playIntent)
                musicPlayerService = null
            }
        }
    }

    override fun onNavigationItemSelected(item: MenuItem): Boolean {
        when (item.itemId) {
            R.id.nav_library -> {
                loadLibrarySongs()
            }
        }
        when (item.groupId) {
            PLAYLIST_GROUP_ID -> {
                loadPlaylistSongs(item.itemId.toLong())
            }
            USER_LIBRARIES_GROUP_ID -> {
                loadUserLibraries(item.itemId.toLong())
            }
        }
        drawer_layout.closeDrawer(GravityCompat.START)
        return true
    }

    // *********
    //  SeekBar
    // *********

    private fun updateProgressBar() {
        mHandler.postDelayed(mUpdateTimeTask, 1000)
    }

    private val mUpdateTimeTask = Runnable { run() }

    private fun run() {
        if (!playbackPaused) {
            musicPlayerService!!.getPosition()
        }

        mHandler.postDelayed(mUpdateTimeTask, 1000)
    }

    override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {}

    override fun onStartTrackingTouch(seekBar: SeekBar?) {
        mHandler.removeCallbacks(mUpdateTimeTask)
    }

    override fun onStopTrackingTouch(seekBar: SeekBar?) {
        mHandler.removeCallbacks(mUpdateTimeTask)
        val currentPosition = seekBar!!.progress

        musicPlayerService!!.seek(currentPosition)
        updateProgressBar()
    }

    // ******************
    //  EventBus Methods
    // ******************

    @Subscribe(threadMode = ThreadMode.MAIN_ORDERED)
    fun playNextEvent(event: PlayNextSongEvent) {
        logger.debug("EventBus", "Message received ${event.message}")
        playNext()
    }

    @Subscribe(threadMode = ThreadMode.MAIN_ORDERED)
    fun onMediaPlayerLoadedEvent(event: MediaPlayerLoadedEvent) {
        logger.debug("EventBus", "Message received ${event.message}")
        logger.debug("EventBus", "Duration is ${event.songDuration}")
        val currentSong = "${event.songTitle} - ${event.songArtist}"
        songDurationTextView.text = event.songDuration.toLong().getSongTimeFromMilliseconds()
        songPositionTextView.text = getString(R.string.zeroPosition)
        songPlayingTextView.text = currentSong
        seekBar.max = event.songDuration
    }

    @Subscribe(threadMode = ThreadMode.MAIN_ORDERED)
    fun onAudioFocusLosses(event: MediaPlayerTransientAudioLossEvent) {
        logger.debug("EventBus", "Message received ${event.message}")
        pause()
    }

    @Subscribe(threadMode = ThreadMode.MAIN_ORDERED)
    fun onPauseEvent(event: MediaPlayerPauseEvent) {
        logger.debug("EventBus", "Message received ${event.message}")
        pause()
    }

    @Subscribe(threadMode = ThreadMode.MAIN_ORDERED)
    fun onAudioFocusLoss(event: MediaPlayerAudioLossEvent) {
        logger.debug("EventBus", "Message received ${event.message}")
        stopService(playIntent)
    }

    @Subscribe(threadMode = ThreadMode.MAIN_ORDERED)
    fun onStartSongEvent(event: MediaPlayerStartSongEvent) {
        logger.debug("EventBus", "Message received ${event.message}")
        start()
    }

    @Subscribe(threadMode = ThreadMode.MAIN_ORDERED)
    fun onPlayPreviousSongEvent(event: PlayPreviousSongEvent) {
        logger.debug("EventBus", "Message received ${event.message}")
        playPrevious()
    }

    @Subscribe(threadMode = ThreadMode.MAIN_ORDERED)
    fun onUpdateSeekBarEvent(event: UpdateSeekBarEvent) {
        logger.debug("EventBus", "Message received ${event.message}")
        seekBar.progress = event.position
        songPositionTextView.text = event.position.toLong().getSongTimeFromMilliseconds()
    }

    private data class LibraryResponse(val content: List<Track>)
    private data class PlaylistResponse(val content: List<PlaylistSongDTO>)
}

fun Long.getSongTimeFromMilliseconds(): String {
    return String.format(
            "%02d:%02d",
            TimeUnit.MILLISECONDS.toMinutes(this),
            TimeUnit.MILLISECONDS.toSeconds(this) -
                    TimeUnit.MINUTES.toSeconds((TimeUnit.MILLISECONDS.toMinutes(this))
                    )
    )
}

fun Long.getSongTimeFromSeconds(): String {
    val minutes = this / 60
    val seconds = this % 60
    return "$minutes:${String.format("%02d", seconds)}"
}

class PlayNextSongEvent(val message: String)

class MediaPlayerLoadedEvent(
    val message: String,
    val songTitle: String?,
    val songArtist: String?,
    val songDuration: Int
)

class MediaPlayerTransientAudioLossEvent(val message: String)

class MediaPlayerAudioLossEvent(val message: String)

class MediaPlayerPauseEvent(val message: String)

class MediaPlayerStartSongEvent(val message: String)

class PlayPreviousSongEvent(val message: String)

class UpdateSeekBarEvent(val message: String, val position: Int)