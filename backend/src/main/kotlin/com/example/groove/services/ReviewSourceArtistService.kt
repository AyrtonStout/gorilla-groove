package com.example.groove.services

import com.example.groove.db.dao.ReviewSourceArtistDownloadRepository
import com.example.groove.db.dao.ReviewSourceArtistRepository
import com.example.groove.db.dao.TrackRepository
import com.example.groove.db.model.ReviewSourceArtist
import com.example.groove.db.model.ReviewSourceArtistDownload
import com.example.groove.db.model.User
import com.example.groove.dto.YoutubeDownloadDTO
import com.example.groove.util.DateUtils.now
import com.example.groove.util.logger
import com.example.groove.util.toTimestamp
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
class ReviewSourceArtistService(
		private val youtubeApiClient: YoutubeApiClient,
		private val spotifyApiClient: SpotifyApiClient,
		private val reviewSourceArtistRepository: ReviewSourceArtistRepository,
		private val reviewSourceArtistDownloadRepository: ReviewSourceArtistDownloadRepository,
		private val youtubeDownloadService: YoutubeDownloadService,
		private val trackService: TrackService,
		private val trackRepository: TrackRepository
) {
	@Scheduled(cron = "0 0 9 * * *") // 9 AM every day (UTC)
//	@Scheduled(cron = "0 */5 * * * *") // 9 AM every day (UTC)
	@Transactional
	fun downloadNewSongs() {
		val allSources = reviewSourceArtistRepository.findAll()

		logger.info("Running Review Source Artist Downloader")

		allSources.forEach { source ->
			logger.info("Checking for new songs for artist: ${source.artistName} ...")
			val users = source.subscribedUsers

			if (users.isEmpty()) {
				logger.error("No users were set up for review source with ID: ${source.id}! It should be deleted!")
				return@forEach
			}

			// Spotify song releases have "day" granularity, so don't include a time component.
			// Also, Spotify might not always get songs on their service right when they are new, so
			// we can't really keep a rolling search. The way the API works right now we have to request
			// everything every time by the artist anyway.... so just grab everything from the artist, unless
			// the user specified only newer things than a certain date when creating the review source.
			val searchNewerThan = source.searchNewerThan?.toLocalDateTime()?.toLocalDate()

			val newSongs = spotifyApiClient.getSongsByArtist(source.artistName, source.artistId, searchNewerThan)
			logger.info("Found ${newSongs.size} new songs for artist: ${source.artistName}")

			// We are going to be searching over the same music every night. Nothing we can do about it really.
			// Just have to play around the way the Spotify API works. So we have to keep track manually on what
			// songs we've already seen by a given artist
			val existingSongDiscoveries = reviewSourceArtistDownloadRepository.findByReviewSource(source)
			val discoveredSongNames = existingSongDiscoveries.map { it.trackName }.toSet()

			newSongs.forEach { newSong ->
				if (!discoveredSongNames.contains(newSong.name)) {
					val newDownload = ReviewSourceArtistDownload(
							reviewSource = source,
							trackName = newSong.name,
							trackAlbumName = newSong.album,
							trackLength = newSong.songLength,
							trackReleaseYear = newSong.releaseYear,
							trackArtUrl = newSong.albumArtUrl!!
					)
					reviewSourceArtistDownloadRepository.save(newDownload)
				}
			}

			attemptDownloadFromYoutube(source, users)
		}

		logger.info("Review Source Artist Downloader complete")
	}

	// Now we need to find a match on YouTube to download...
	private fun attemptDownloadFromYoutube(source: ReviewSourceArtist, users: List<User>) {
		val oneWeekAgo = now().toLocalDateTime().minusWeeks(1).toTimestamp()

		// Don't keep retrying stuff that failed every day. We have a pretty limited quota so only retry every week
		val songsToDownload = reviewSourceArtistDownloadRepository
				.findByReviewSourceAndDownloadedAtIsNull(source)
				.filter { it.lastDownloadAttempt == null || it.lastDownloadAttempt!!.before(oneWeekAgo) }

		val (firstUser, otherUsers) = users.partition { it.id == users.first().id }

		songsToDownload.forEach { song ->
			val videos = youtubeApiClient.findVideos("${source.artistName} ${song.trackName}").videos

			// There's a chance that our search yields no valid results, but youtube will pretty much always return
			// us videos, even if they're a horrible match. Probably the best thing we can do is check the video title
			// and duration to sanity check and make sure it is at least a decent match.
			// Better to NOT find something than to find a video which isn't correct for something like this...
			val validVideos = videos.filter { it.isValidForSong(source.artistName, song) }

			if (validVideos.isEmpty()) {
				logger.warn("Could not find a valid YouTube download for ${source.artistName} - ${song.trackName}")

				song.lastDownloadAttempt = now()
				reviewSourceArtistDownloadRepository.save(song)

				return@forEach
			}

			// For now, just rely on YouTube's relevance to give us the best result (so take the first one).
			// Might be better to try to exclude music videos and stuff later, though the time checking might help already.
			val video = validVideos.first()

			val downloadDTO = YoutubeDownloadDTO(
					url = video.videoUrl,
					name = song.trackName,
					artist = source.artistName,
					album = song.trackAlbumName,
					releaseYear = song.trackReleaseYear,
					cropArtToSquare = true
			)

			val track = youtubeDownloadService.downloadSong(firstUser.first(), downloadDTO)
			track.reviewSource = source
			track.inReview = true
			track.lastReviewed = now()
			trackRepository.save(track)

			song.downloadedAt = now()
			reviewSourceArtistDownloadRepository.save(song)

			// The YT download service will save the Track for the user that downloads it.
			// So for every other user just copy that DB entity and give it the user. It will
			// point to the same S3 bucket for everything, however, we don't share album art
			// right now so that will need to be copied!
			// TODO album art copying
			otherUsers.forEach { otherUser ->
				trackService.saveTrackForUserReview(otherUser, track, source)
			}
		}
	}

	private fun YoutubeApiClient.YoutubeVideo.isValidForSong(artist: String, song: ReviewSourceArtistDownload): Boolean {
		val lowerTitle = this.title.toLowerCase()

		// Make sure the artist is in the title somewhere. If it isn't that seems like a bad sign
		if (!lowerTitle.contains(artist.toLowerCase())) {
			return false
		}

		// If the duration doesn't match closely with Spotify's expected duration, that's a bad sign
		if (this.duration < song.trackLength - SORT_LENGTH_IDENTIFICATION_TOLERANCE ||
				this.duration > song.trackLength + SORT_LENGTH_IDENTIFICATION_TOLERANCE) {
			return false
		}

		// Now lastly we want to check that the song title is adequately represented in the video title. I ran into
		// a lot of situations where titles were slightly different so a substring match wasn't viable. So I think
		// a better approach is to check each word individually for representation, and get rid of words that have
		// little value or little hope or being matched correctly
		val unimportantWords = setOf("with", "feat", "ft", "featuring")
		val titleWords = this.title
				.toLowerCase()
				.replace("(", "")
				.replace(")", "")
				.replace(".", "")
				.replace("-", "")
				.split(" ")
				.filter { it.isNotBlank() && !unimportantWords.contains(it) }

		return titleWords.all { lowerTitle.contains(it) }
	}

	companion object {
		private val logger = logger()

		// When we are checking if a YouTube video is valid for a given Spotify song, we want to make sure
		// that the song lengths more or less agree. This is the tolerance for that check
		private const val SORT_LENGTH_IDENTIFICATION_TOLERANCE = 4
	}
}
