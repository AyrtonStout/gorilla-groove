package com.example.groove.db.dao

import com.example.groove.db.model.ReviewSourceYoutubeChannel
import org.springframework.data.repository.CrudRepository

interface ReviewSourceYoutubeChannelRepository : CrudRepository<ReviewSourceYoutubeChannel, Long> {
	fun findByChannelId(channelId: String): ReviewSourceYoutubeChannel?
	fun findByChannelName(channelName: String): ReviewSourceYoutubeChannel?
}
