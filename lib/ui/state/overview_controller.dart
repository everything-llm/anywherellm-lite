import 'package:flutter/foundation.dart';

import '../../core/models.dart';
import '../../core/ports.dart';

/// What the app knows from nils's overview: what each library holds, what the last check
/// found and where nils keeps things. It starts from the answer the boot probe got, so the
/// sidebar's badges, the Overview page and the inbox's size limit never wait on a request.
class OverviewController extends ChangeNotifier {
  OverviewController(this._api, this.data);

  final NilsApi _api;

  /// The last answer.
  Overview data;

  /// What the last check found in the libraries, for the sidebar's badges and the list pages.
  List<Finding> get findings => data.findings;

  /// What nils accepts.
  Limits get limits => data.limits;

  /// The findings of one library, `research` or `skills`.
  List<Finding> findingsFor(String library) => [
    for (final finding in findings)
      if (finding.library == library) finding,
  ];

  /// Runs the checks again, as when a page opens. A failure keeps what was known.
  Future<void> refresh() async {
    try {
      data = await _api.overview();
    } on ApiException {
      return;
    }
    notifyListeners();
  }
}
