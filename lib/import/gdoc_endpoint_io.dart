/// Android/VM: Google's DOCX export, fetched directly.
Uri gdocDownloadUri(String id) =>
    Uri.https('docs.google.com', '/document/d/$id/export', {'format': 'docx'});
