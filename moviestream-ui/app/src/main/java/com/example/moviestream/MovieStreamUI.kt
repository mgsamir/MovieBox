package com.example.moviestream

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import coil.compose.AsyncImage
import com.example.moviebox.extract.ExtractedPage
import com.example.moviebox.extract.PageExtractor
import com.example.moviebox.extract.PlayerActivity

/*
 * ---------------------------------------------------------------
 *  Dependencies (app/build.gradle.kts)
 * ---------------------------------------------------------------
 *  implementation(platform("androidx.compose:compose-bom:2024.10.01"))
 *  implementation("androidx.compose.material3:material3")
 *  implementation("androidx.compose.ui:ui")
 *  implementation("androidx.activity:activity-compose:1.9.3")
 *  implementation("androidx.navigation:navigation-compose:2.8.3")
 *  implementation("io.coil-kt:coil-compose:2.7.0")
 *  implementation("androidx.appcompat:appcompat:1.7.0")
 *  implementation("androidx.media3:media3-exoplayer:1.4.1")
 *  implementation("androidx.media3:media3-exoplayer-hls:1.4.1")
 *  implementation("androidx.media3:media3-ui:1.4.1")
 *
 *  AndroidManifest.xml:
 *    <uses-permission android:name="android.permission.INTERNET" />
 *    and set android:name=".MainActivity" on your launcher activity.
 *    PlayerActivity (com.example.moviebox.extract.PlayerActivity) must also
 *    be declared, with a hidden WebView used only to read your own pages
 *    (see HiddenPageExtractor.kt) — never shown to the user.
 * ---------------------------------------------------------------
 */

// ------------------------------------------------------------- Data

/** One button on the detail screen, e.g. label = "720p", url = link from YOUR server. */
data class QualityLink(val label: String, val url: String)

data class Movie(
    val id: String,
    val title: String,
    val year: Int,
    val genre: String,
    val rating: Double,
    val posterUrl: String,
    val synopsis: String,
    /** Your own webpage for this title; Play resolves the live video from here. */
    val sourcePageUrl: String,
    /** Known direct files per quality, used by the Download sheet. */
    val links: List<QualityLink>,
)

/** Demo data. Replace with the list you load from your own server. */
val sampleMovies: List<Movie> = List(12) { i ->
    Movie(
        id = "m$i",
        title = "Movie Title ${i + 1}",
        year = 2020 + i % 6,
        genre = listOf("Action", "Drama", "Sci-Fi")[i % 3],
        rating = 7.0 + (i % 20) / 10.0,
        posterUrl = "https://picsum.photos/seed/movie$i/400/600",
        synopsis = "Yahan movie ki short kahani aayegi. Ye text aap apne server se laoge.",
        sourcePageUrl = "https://your-server.com/movie/$i",
        links = listOf(
            QualityLink("480p", "https://your-server.com/m$i/480.mp4"),
            QualityLink("720p", "https://your-server.com/m$i/720.mp4"),
            QualityLink("1080p", "https://your-server.com/m$i/1080.mp4"),
        ),
    )
}

// ------------------------------------------------------------- Play

/**
 * Reads [Movie.sourcePageUrl] with the hidden WebView extractor, then hands
 * the resolved video URL to [PlayerActivity] for native ExoPlayer playback.
 * No browser is ever shown.
 */
fun playMovie(context: Context, movie: Movie, onDone: () -> Unit) {
    PageExtractor(context).extract(movie.sourcePageUrl) { result: ExtractedPage? ->
        onDone()
        val videoUrl = result?.videoUrl
        if (videoUrl.isNullOrBlank()) {
            Toast.makeText(context, "Could not find a playable video for ${movie.title}.", Toast.LENGTH_SHORT).show()
            return@extract
        }
        val intent = Intent(context, PlayerActivity::class.java).apply {
            putExtra(PlayerActivity.EXTRA_VIDEO_URL, videoUrl)
            putExtra(PlayerActivity.EXTRA_TITLE, movie.title)
            putExtra(PlayerActivity.EXTRA_POSTER_URL, movie.posterUrl)
        }
        context.startActivity(intent)
    }
}

// ------------------------------------------------------------- Download

/** Downloads one quality in the background with Android's own DownloadManager. */
fun startDownload(context: Context, movie: Movie, link: QualityLink) {
    val illegalChars = Regex("[\\\\/:*?\"<>|]")
    val fileName = "${movie.title} [${link.label}].mp4".replace(illegalChars, "_")
    val request = DownloadManager.Request(Uri.parse(link.url))
        .setTitle(movie.title)
        .setDescription(link.label)
        .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
        .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
        .setAllowedOverMetered(true)
    val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    manager.enqueue(request)
    Toast.makeText(context, "Downloading ${link.label}…", Toast.LENGTH_SHORT).show()
}

// ------------------------------------------------------------- Theme

private val Bg = Color(0xFF101114)
private val Panel = Color(0xFF1D1F23)
private val Accent = Color(0xFF22D6A0)

@Composable
fun StreamTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Accent,
            onPrimary = Color.Black,
            background = Bg,
            surface = Panel,
        ),
        content = content,
    )
}

// ------------------------------------------------------------- Activity + navigation

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            StreamTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    MovieApp()
                }
            }
        }
    }
}

@Composable
fun MovieApp() {
    val nav = rememberNavController()
    val movies = remember { sampleMovies } // TODO: replace with data from your server

    NavHost(navController = nav, startDestination = "grid") {
        composable("grid") {
            MovieGridScreen(
                movies = movies,
                onMovieClick = { movie -> nav.navigate("detail/${movie.id}") },
            )
        }
        composable(
            route = "detail/{id}",
            arguments = listOf(navArgument("id") { type = NavType.StringType }),
        ) { entry ->
            val movie = movies.firstOrNull { it.id == entry.arguments?.getString("id") }
            if (movie != null) {
                MovieDetailScreen(movie = movie, onBack = { nav.popBackStack() })
            }
        }
    }
}

// ------------------------------------------------------------- Grid screen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MovieGridScreen(movies: List<Movie>, onMovieClick: (Movie) -> Unit) {
    Scaffold(
        containerColor = Bg,
        topBar = {
            TopAppBar(
                title = { Text("MovieStream", fontWeight = FontWeight.ExtraBold) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Bg),
            )
        },
    ) { padding ->
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 110.dp),
            contentPadding = PaddingValues(12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier.padding(padding),
        ) {
            items(movies, key = { it.id }) { movie ->
                MovieCard(movie = movie, onClick = { onMovieClick(movie) })
            }
        }
    }
}

@Composable
fun MovieCard(movie: Movie, onClick: () -> Unit) {
    Column(modifier = Modifier.clickable(onClick = onClick)) {
        AsyncImage(
            model = movie.posterUrl,
            contentDescription = movie.title,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(2f / 3f)
                .clip(RoundedCornerShape(12.dp))
                .background(Panel),
        )
        Spacer(Modifier.height(6.dp))
        Text(
            text = movie.title,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "${movie.year} • ${movie.genre}",
            maxLines = 1,
            fontSize = 11.sp,
            color = Color.Gray,
        )
    }
}

// ------------------------------------------------------------- Detail screen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MovieDetailScreen(movie: Movie, onBack: () -> Unit) {
    val context = LocalContext.current
    var resolving by remember { mutableStateOf(false) }
    var showDownloadSheet by remember { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxSize().background(Bg)) {
        Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
            Box(modifier = Modifier.fillMaxWidth().height(380.dp)) {
                AsyncImage(
                    model = movie.posterUrl,
                    contentDescription = movie.title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Brush.verticalGradient(0.4f to Color.Transparent, 1f to Bg)),
                )
            }

            Column(modifier = Modifier.padding(horizontal = 16.dp).offset(y = (-40).dp)) {
                Text(movie.title, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold)
                Spacer(Modifier.height(4.dp))
                Text("${movie.year} • ${movie.genre} • ★ ${movie.rating}", color = Color.Gray)
                Spacer(Modifier.height(14.dp))
                Text(movie.synopsis, lineHeight = 21.sp, color = Color(0xFFD0D0D5))
                Spacer(Modifier.height(24.dp))

                // Large Play button: resolves the video from sourcePageUrl, then
                // hands it to PlayerActivity (ExoPlayer) — no browser ever shown.
                Button(
                    onClick = {
                        if (!resolving) {
                            resolving = true
                            playMovie(context, movie) { resolving = false }
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    contentPadding = PaddingValues(vertical = 16.dp),
                ) {
                    if (resolving) {
                        CircularProgressIndicator(
                            modifier = Modifier.height(20.dp).width(20.dp),
                            color = Color.Black,
                            strokeWidth = 2.dp,
                        )
                        Spacer(Modifier.width(10.dp))
                        Text("Finding video…", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                    } else {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text("Play", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                    }
                }
                Spacer(Modifier.height(10.dp))

                // Download button: opens the quality picker below.
                OutlinedButton(
                    onClick = { showDownloadSheet = true },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    contentPadding = PaddingValues(vertical = 16.dp),
                ) {
                    Icon(Icons.Filled.Download, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Download", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                }
            }
        }

        IconButton(
            onClick = onBack,
            modifier = Modifier
                .statusBarsPadding()
                .padding(8.dp)
                .background(Color(0x66000000), CircleShape),
        ) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Color.White)
        }
    }

    if (showDownloadSheet) {
        ModalBottomSheet(
            onDismissRequest = { showDownloadSheet = false },
            containerColor = Panel,
        ) {
            DownloadQualitySheet(
                movie = movie,
                onQualityPicked = { link ->
                    startDownload(context, movie, link)
                    showDownloadSheet = false
                },
            )
        }
    }
}

/** Lists 480p / 720p / 1080p (whatever [Movie.links] has); tap to download. */
@Composable
fun DownloadQualitySheet(movie: Movie, onQualityPicked: (QualityLink) -> Unit) {
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text("Download", fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(4.dp))
        Text(movie.title, color = Color.Gray, fontSize = 13.sp)
        Spacer(Modifier.height(16.dp))
        movie.links.forEach { link ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onQualityPicked(link) }
                    .padding(vertical = 14.dp),
            ) {
                Icon(Icons.Filled.Download, contentDescription = null, tint = Accent)
                Spacer(Modifier.width(14.dp))
                Column {
                    Text(link.label, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                    Text(movie.title, color = Color.Gray, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}
