package com.example.moviebox.extract

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.example.moviestream.R

/*
 * build.gradle.kts dependencies:
 *   implementation("androidx.media3:media3-exoplayer:1.4.1")
 *   implementation("androidx.media3:media3-exoplayer-hls:1.4.1")
 *   implementation("androidx.media3:media3-ui:1.4.1")
 *
 * activity_player.xml needs one view:
 *   <androidx.media3.ui.PlayerView
 *       android:id="@+id/playerView"
 *       android:layout_width="match_parent"
 *       android:layout_height="match_parent" />
 *
 * Pass the page URL in, e.g.:
 *   intent.putExtra("page_url", movie.sourceUrl)
 */
class PlayerActivity : AppCompatActivity() {

    private var player: ExoPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_player)

        val playerView = findViewById<PlayerView>(R.id.playerView)
        val pageUrl = intent.getStringExtra("page_url") ?: return finishWithError()

        PageExtractor(this).extract(pageUrl) { result ->
            val videoUrl = result?.videoUrl
            if (videoUrl.isNullOrBlank()) {
                // The page exposed only an <iframe>, not a direct <video> src.
                // Resolve one level deeper if needed:
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
