// Searching names.

/// Whether [text] contains [query], ignoring case and the spaces around the query. An empty
/// query matches everything.
bool matchesSearch(String query, String text) {
  final wanted = query.trim().toLowerCase();
  return wanted.isEmpty || text.toLowerCase().contains(wanted);
}
