// Download scaffold: only use with direct URLs you own or are authorized to download.
// Wire this service to a download manager and a user-facing consent flow before production use.
class DownloadService {
  Future<void> downloadAuthorizedMedia(String url) async {
    if (!url.startsWith('https://')) {
      throw ArgumentError('Only HTTPS media URLs are supported.');
    }
    throw UnimplementedError('Connect an Android download manager before enabling downloads.');
  }
}
