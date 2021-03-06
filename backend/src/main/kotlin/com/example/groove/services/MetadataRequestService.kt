package com.example.groove.services

import com.example.groove.db.dao.TrackLinkRepository
import com.example.groove.db.dao.TrackRepository
import com.example.groove.db.model.Track
import com.example.groove.db.model.User
import com.example.groove.dto.MetadataResponseDTO
import com.example.groove.dto.MetadataUpdateRequestDTO
import com.example.groove.services.enums.MetadataOverrideType
import com.example.groove.services.storage.FileStorageService
import com.example.groove.util.*
import com.example.groove.util.DateUtils.now
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.io.IOException
import java.net.URL
import javax.imageio.ImageIO

@Service
class MetadataRequestService(
		private val trackRepository: TrackRepository,
		private val spotifyApiClient: SpotifyApiClient,
		private val fileStorageService: FileStorageService,
		private val fileUtils: FileUtils,
		private val songIngestionService: SongIngestionService,
		private val trackLinkRepository: TrackLinkRepository
) {

	@Transactional
	fun requestTrackMetadata(request: MetadataUpdateRequestDTO, user: User): Pair<List<Track>, List<Long>> {
		val trackIds = request.trackIds
		val now = now()

		val updatedSuccessTracks = findUpdatableTracks(trackIds, user).map { (track, metadataResponse) ->
			if (track.album.shouldBeUpdated(request.changeAlbum)) {
				track.album = metadataResponse.album
				track.updatedAt = now
			}

			// We only want to update this info if we are actually using the same album as the response
			if (metadataResponse.albumArtLink != null && track.album.equals(metadataResponse.album, ignoreCase = true)) {
				if (track.releaseYear.shouldBeUpdated(request.changeReleaseYear)) {
					track.releaseYear = metadataResponse.releaseYear
					track.updatedAt = now
				}
				if (track.trackNumber.shouldBeUpdated(request.changeTrackNumber)) {
					track.trackNumber = metadataResponse.trackNumber
					track.updatedAt = now
				}
				saveAlbumArt(track, metadataResponse.albumArtLink, request.changeAlbumArt)
			}

			trackRepository.save(track)
		}

		val successfulIds = updatedSuccessTracks.map { it.id }.toSet()
		val failedIds = trackIds - successfulIds

		return updatedSuccessTracks to failedIds
	}

	private fun Any?.shouldBeUpdated(metadataOverrideType: MetadataOverrideType): Boolean {
		return when (metadataOverrideType) {
			MetadataOverrideType.NEVER -> false
			MetadataOverrideType.ALWAYS -> true
			MetadataOverrideType.IF_EMPTY -> if (this is String) {
				isNullOrBlank()
			} else {
				this == null
			}
		}
	}

	private fun saveAlbumArt(track: Track, newAlbumArtUrl: String, overrideType: MetadataOverrideType) {
		if (overrideType == MetadataOverrideType.NEVER) {
			return
		}

		if (overrideType == MetadataOverrideType.IF_EMPTY) {
			fileStorageService.loadAlbumArt(track.id, ArtSize.LARGE)?.run {
				logger.info("Updating album art conditionally and existing album art was found for track ID ${track.id}. " +
						"Skipping album art save")
				return
			}
		}

		val artImage = try {
			ImageIO.read(URL(newAlbumArtUrl))
		} catch (e: IOException) {
			logger.error("Failed to read in image URL! $newAlbumArtUrl")
			return
		}

		val file = fileUtils.createTemporaryFile(".png")
		artImage.writeToFile(file, "png")
		logger.info("Writing new album art for track ${track.id} to storage...")
		songIngestionService.storeAlbumArtForTrack(file, track, false)
		file.delete()

		trackLinkRepository.forceExpireLinksByTrackId(track.id)
	}

	private fun findUpdatableTracks(trackIds: List<Long>, user: User): List<Pair<Track, MetadataResponseDTO>> {
		val validTracks = trackIds
				.map { trackRepository.get(it) }
				.filterNot { track ->
					track == null
							|| track.user.id != user.id
							|| track.artist.isBlank()
							|| track.name.isBlank()
				}

		return validTracks.map {
			logger.info("Checking Spotify Metadata for artist: ${it!!.artist}, name: ${it.name}")
			val metadataResponse = spotifyApiClient.getMetadataByTrackArtistAndName(
					artist = it.artist,
					name = it.name,
					limit = 1
			).firstOrNull()
			
			logger.info("Metadata was ${if (metadataResponse == null) "not " else ""}found for search")

			it to metadataResponse
		}.filter { (_, metadataResponse) -> metadataResponse != null }
				.map { it.first to it.second!! }
	}

	companion object {
		private val logger = logger()
	}
}
