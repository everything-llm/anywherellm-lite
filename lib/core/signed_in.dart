/// What a service's name in a signed-in link may be: a sign-in's name as library-lean allows it.
final _service = RegExp(r'^[\w .@:-]{1,60}$');

/// The service [text] says the person signed in to, when it is the link
/// `anywherellm://signed-in?service=<name>`, which library-lean's OAuth return page offers once the
/// provider sent a code back; null for any other text, or a name that is not a sign-in's name.
String? signedInOf(String text) {
  final link = Uri.tryParse(text.trim());
  if (link == null ||
      link.scheme != 'anywherellm' ||
      link.host != 'signed-in') {
    return null;
  }
  final String? service;
  try {
    service = link.queryParameters['service']?.trim();
  } on FormatException {
    return null;
  }
  return service != null && _service.hasMatch(service) ? service : null;
}
