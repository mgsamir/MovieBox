package com.example.moviebox.extract

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject

/**
 * Result of reading one page: what the page's own DOM reports about itself.
 * videoUrl / iframeUrl are whatever the page exposes directly; for a real
 * player you will usually still need to resolve the iframe one level deeper
 * (same idea, call PageExtractor again with the iframe's URL).
 */
data class ExtractedPage(
    val title: String?,
    val posterUrl: String?,
    val videoUrl: String?,
    val iframeUrl: String?,
)

/**
 * Loads a URL in an invisible WebView, waits for the page (and its JS) to
 * settle, then pulls title / poster / video / iframe out of the DOM.
 * Nothing is ever shown to the user — the WebView is 1x1px and detached
 * from any visible layout.
 *
 * Use this only for pages you own or are authorized to read.
 */
class PageExtractor(private val context: Context) {

    private val mainHandler = Handler(Looper.getMainLooper())

    /** [onResult] is called on the main thread, exactly once. */
    @SuppressLint("SetJavaScriptEnabled")
    fun extract(url: String, timeoutMs: Long = 15_000L, onResult: (ExtractedPage?) -> Unit) {
        mainHandler.post {
            val webView = WebView(context).apply {
                layoutParams = ViewGroup.LayoutParams(1, 1)
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.userAgentString =
                    "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/130 Mobile Safari/537.36"
            }

            var finished = false
            fun finish(result: ExtractedPage?) {
                if (finished) return
                finished = true
                mainHandler.removeCallbacksAndMessages(null)
                onResult(result)
                // Give the WebView a moment before tearing it down.
                mainHandler.postDelayed({
                    webView.stopLoading()
                    webView.destroy()
                }, 200)
            }

            webView.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, finishedUrl: String) {
                    // Small delay so late JS (lazy players, ads resolving) has a chance to run.
                    mainHandler.postDelayed({ runExtractionScript(view, ::finish) }, 700)
                }

                override fun onReceivedError(
                    view: WebView,
                    errorCode: Int,
                    description: String?,
                    failingUrl: String?,
                ) {
                    finish(null)
                }
            }

            // Safety net in case the page never fires onPageFinished.
            mainHandler.postDelayed({ finish(null) }, timeoutMs)

            webView.loadUrl(url)
        }
    }

    private fun runExtractionScript(view: WebView, finish: (ExtractedPage?) -> Unit) {
        // Keep this JS defensive: any selector here is a guess about the
        // page's structure and should be adjusted to match the real site.
        val js = """
            (function() {
              function text(el) { return el ? el.textContent.trim() : null; }
              function attr(el, name) { return el ? el.getAttribute(name) : null; }

              var title =
                text(document.querySelector('h1')) ||
                attr(document.querySelector('meta[property="og:title"]'), 'content') ||
                document.title;

              var poster =
                attr(document.querySelector('meta[property="og:image"]'), 'content') ||
                attr(document.querySelector('video'), 'poster');

              var video =
                attr(document.querySelector('video source'), 'src') ||
                attr(document.querySelector('video'), 'src');

              var iframe = attr(document.querySelector('iframe'), 'src');

              return JSON.stringify({
                title: title || null,
                poster: poster || null,
                video: video || null,
                iframe: iframe || null
              });
            })();
        """.trimIndent()

        view.evaluateJavascript(js) { rawJson ->
            try {
                // evaluateJavascript hands back a JSON *string literal*
                // ("{\"title\":...}"), so unwrap it once before parsing.
                val unwrapped = JSONObject.quote("").let { _ ->
                    org.json.JSONTokener(rawJson).nextValue() as String
                }
                val obj = JSONObject(unwrapped)
                finish(
                    ExtractedPage(
                        title = obj.optStringOrNull("title"),
                        posterUrl = obj.optStringOrNull("poster"),
                        videoUrl = obj.optStringOrNull("video"),
                        iframeUrl = obj.optStringOrNull("iframe"),
                    )
                )
            } catch (e: Exception) {
                finish(null)
            }
        }
    }

    private fun JSONObject.optStringOrNull(key: String): String? =
        if (has(key) && !isNull(key)) getString(key) else null
}
