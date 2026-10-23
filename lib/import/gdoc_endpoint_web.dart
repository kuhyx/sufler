/// Web: the same-origin desktop wrapper proxies the export (Google sends
/// no CORS headers, so the browser cannot fetch it directly).
Uri gdocDownloadUri(String id) =>
    Uri.base.resolve('/api/gdoc?id=${Uri.encodeQueryComponent(id)}');
