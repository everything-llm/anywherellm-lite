import 'companion.dart';

/// The toolkit, anythingllm-toolkit, as a [Companion]: its client API serves what AnythingLLM
/// keeps behind its web login, the saved memories and the scheduled jobs, for the developer
/// key.
const toolkitCompanion = Companion(
  service: 'anythingllm-toolkit',
  port: 8467,
  name: 'The toolkit',
);

/// The features the toolkit's `/health` names that the app uses.
abstract final class ToolkitFeature {
  static const memories = 'memories';
  static const jobs = 'jobs';
}
