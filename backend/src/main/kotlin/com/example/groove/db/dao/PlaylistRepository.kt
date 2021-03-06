package com.example.groove.db.dao

import com.example.groove.db.model.Playlist
import org.springframework.data.domain.Page
import org.springframework.data.domain.Pageable
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.CrudRepository
import org.springframework.data.repository.query.Param
import java.sql.Timestamp

interface PlaylistRepository : CrudRepository<Playlist, Long>, RemoteSyncableDao {
	@Query("""
			SELECT p
			FROM Playlist p
			WHERE p.updatedAt > :minimum
			AND p.updatedAt < :maximum
			AND (p.deleted = FALSE OR p.createdAt < :minimum)
			AND p.id IN (
			  SELECT pu.playlist.id
			  FROM PlaylistUser pu
			  WHERE pu.user.id = :userId
			)
			ORDER BY p.id
			""")
	// Filter out things that were created AND deleted in the same time frame
	// Order by ID so the pagination is predictable
	fun getPlaylistsUpdatedBetweenTimestamp(
			@Param("userId") userId: Long,
			@Param("minimum") minimum: Timestamp,
			@Param("maximum") maximum: Timestamp,
			pageable: Pageable
	): Page<Playlist>

	@Query("""
			SELECT max(p.updatedAt)
			FROM Playlist p
			WHERE p.id IN (
			  SELECT pu.playlist.id
			  FROM PlaylistUser pu
			  WHERE pu.user.id = :userId
			)
			""")
	override fun getLastModifiedRow(userId: Long): Timestamp?
}
