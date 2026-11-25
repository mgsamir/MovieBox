package com.example.moviestream

import android.content.Context
import android.os.Bundle
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
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
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
 *
 *  AndroidManifest.xml:
 *    <uses-permission android:name="android.permission.INTERNET" />
 *    and set android:name=".MainActivity" on your launcher activity.
 *
 *  No WebView is used anywhere. Only UI and click handling.
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
        links = listOf(
            QualityLink("480p", "https://your-server.com/m$i/480.mp4"),
            QualityLink("720p", "https://your-server.com/m$i/720.mp4"),
            QualityLink("1080p", "https://your-server.com/m$i/1080.mp4"),
        ),
    )
}

// ------------------------------------------------------------- Click handling

/**
 * Called when the user taps 480p / 720p / 1080p.
 * Put your own player (ExoPlayer) or download code here.
 */
fun onQualitySelected(context: Context, movie: Movie, link: QualityLink) {
    Toast.makeText(context, "${movie.title} • ${link.label}\n${link.url}", Toast.LENGTH_SHORT).show()
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
    val context = LocalContext.current
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
                MovieDetailScreen(
                    movie = movie,
                    onBack = { nav.popBackStack() },
                    onQualityClick = { m, link -> onQualitySelected(context, m, link) },
                )
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

@Composable
fun MovieDetailScreen(
    movie: Movie,
    onBack: () -> Unit,
    onQualityClick: (Movie, QualityLink) -> Unit,
) {
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

                Text("Choose quality", fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    movie.links.forEach { link ->
                        Button(
                            onClick = { onQualityClick(movie, link) },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(12.dp),
                            contentPadding = PaddingValues(vertical = 14.dp),
                        ) {
                            Icon(Icons.Filled.PlayArrow, contentDescription = null)
                            Spacer(Modifier.width(4.dp))
                            Text(link.label, fontWeight = FontWeight.Bold)
                        }
                    }
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
}
