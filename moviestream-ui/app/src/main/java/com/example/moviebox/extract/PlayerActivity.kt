package com.example.moviebox.extract

import android.os.Bundle
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.example.moviestream.R

/*
 * build.gradle.kts dependencies:
 *   implementation("androidx.appcompat:appcompat:1.7.0")
 *   implementation("androidx.media3:media3-exoplayer:1.4.1")
 *   implementation("androidx.media3:media3-exoplayer-hls:1.4.1")
 *   implementation("androidx.media3:media3-ui:1.4.1")
 *
 * Launch with a direct, already-resolved video URL (preferred — this is
 * what MovieStreamUI.kt's playMovie() does after using PageExtractor):
 *   Intent(context, PlayerActivity::class.java).apply {
 *       putExtra(PlayerActivity.EXTRA_VIDEO_URL, videoUrl)
 *       putExtra(PlayerActivity.EXTRA_TITLE, movie.title)
 *       putExtra(PlayerActivity.EXTRA_POSTER_URL, movie.posterUrl)
 *   }
 *
 * Or, if you only have a page to scrape and want PlayerActivity to do the
 * extraction itself, pass EXTRA_PAGE_URL instead of EXTRA_VIDEO_URL.
 */
class PlayerActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_VIDEO_URL = "video_url"
        const val EXTRA_PAGE_URL = "page_url"
        const val EXTRA_TITLE = "title"
        const val EXTRA_POSTER_URL = "poster_url"
    }

    private var player: ExoPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_player)

        val playerView = findViewById<PlayerView>(R.id.playerView)
        val titleView = findViewById<TextView>(R.id.titleOverlay)

        intent.getStringExtra(EXTRA_TITLE)?.let { title ->
            titleView.text = title
            titleView.visibility = android.view.View.VISIBLE
        }

        val directUrl = intent.getStringExtra(EXTRA_VIDEO_URL)
        if (!directUrl.isNullOrBlank()) {
            playVideo(playerView, directUrl)
            return
        }

        val pageUrl = intent.getStringExtra(EXTRA_PAGE_URL)
        if (pageUrl.isNullOrBlank()) return finishWithError()

        PageExtractor(this).extract(pageUrl) { result ->
            val videoUrl = result?.videoUrl
            if (videoUrl.isNullOrBlank()) {
                val iframeUrl = result?.iframeUrl
                if (!iframeUrl.isNullOrBlank()) {
                    PageExtractor(this).extract(iframeUrl) { inner ->
                        val innerUrl = inner?.videoUrl
                        if (innerUrl.isNullOrBlank()) finishWithError() else playVideo(playerView, innerUrl)
                    }
                } else {
                    finishWithError()
                }
                return@extract
            }
            playVideo(playerView, videoUrl)
        }
    }

    private fun playVideo(playerView: PlayerView, url: String) {
        val exo = ExoPlayer.Builder(this).build()
        playerView.player = exo
        exo.setMediaItem(MediaItem.fromUri(url)) // ExoPlayer detects HLS (.m3u8) vs mp4 from the URL
        exo.prepare()
        exo.playWhenReady = true
        player = exo
    }

    private fun finishWithError() {
        Toast.makeText(this, "Could not find a playable video on this page.", Toast.LENGTH_SHORT).show()
        finish()
    }

    override fun onStop() {
        super.onStop()
        player?.release()
        player = null
    }
}
