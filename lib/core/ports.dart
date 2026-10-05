import 'models.dart';

/// A read or a write nils refused or could not do. [status] is null when nils gave no answer.
class ApiException implements Exception {
  const ApiException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// The nils libraries and inbox, as the UI sees them. Every method throws [ApiException] on
/// failure.
abstract interface class NilsApi {
  Future<Overview> overview();
  Future<List<ResearchEntry>> research();
  Future<ResearchDoc> researchDoc(String path);
  Future<List<SkillMeta>> skills();
  Future<SkillDoc> skillDoc(String name);
  Future<List<String>> inbox();

  /// Stages [bytes] as [name]. nils may rename it, so read the inbox for what was staged.
  Future<void> upload(String name, List<int> bytes);
}
