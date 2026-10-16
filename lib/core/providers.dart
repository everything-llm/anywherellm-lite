// The server's providers by what they do: a chooser such as `LLMProvider` and its values by
// name, and for a chat provider reached at an address, the setting that holds it.

import 'connection.dart';
import 'system_settings.dart';

/// One value of a chooser, with its name and, for a chat provider reached at an address, the
/// setting that holds the address.
class Provider {
  const Provider(this.value, this.label, {this.address});

  /// The value the server stores.
  final String value;
  final String label;
  final String? address;
}

/// A setting that picks a provider, such as `LLMProvider`, and its values.
class ProviderSetting {
  const ProviderSetting(this.chooser, this.providers);

  final String chooser;
  final List<Provider> providers;

  Provider? named(String value) {
    for (final provider in providers) {
      if (provider.value == value) return provider;
    }
    return null;
  }

  /// What [value] is called, or [value] itself when the app does not know it.
  String labelOf(String value) =>
      value.isEmpty ? 'None' : named(value)?.label ?? value;

  /// The values the chooser offers while the server has [current]: those the server takes, in
  /// [providers]' order and then any the app has no name for, and [current] as well when it is
  /// none of them, so a provider newer than the app still shows.
  List<String> choices(String current) {
    final taken = systemChoices[chooser];
    return [
      for (final p in providers)
        if (taken == null || taken.contains(p.value)) p.value,
      for (final value in taken ?? const <String>[])
        if (named(value) == null) value,
      if (!(taken ?? const []).contains(current) && named(current) == null)
        current,
    ];
  }
}

const chatProviders = ProviderSetting('LLMProvider', [
  Provider(
    'generic-openai',
    'Generic OpenAI',
    address: 'GenericOpenAiBasePath',
  ),
  Provider('openai', 'OpenAI'),
  Provider('azure', 'Azure OpenAI', address: 'AzureOpenAiEndpoint'),
  Provider('anthropic', 'Anthropic'),
  Provider('gemini', 'Gemini'),
  Provider('nvidia-nim', 'NVIDIA NIM', address: 'NvidiaNimLLMBasePath'),
  Provider('ollama', 'Ollama', address: 'OllamaLLMBasePath'),
  Provider('lmstudio', 'LM Studio', address: 'LMStudioBasePath'),
  Provider('llmman', 'llmman', address: 'LlmmanBasePath'),
  Provider('lemonade', 'Lemonade', address: 'LemonadeLLMBasePath'),
  Provider('sambanova', 'SambaNova'),
  Provider('localai', 'Local AI', address: 'LocalAiBasePath'),
  Provider('togetherai', 'Together AI'),
  Provider('fireworksai', 'Fireworks AI'),
  Provider('mistral', 'Mistral'),
  Provider('perplexity', 'Perplexity AI'),
  Provider('openrouter', 'OpenRouter'),
  Provider('groq', 'Groq'),
  Provider('koboldcpp', 'KoboldCPP', address: 'KoboldCPPBasePath'),
  Provider('textgenwebui', 'Oobabooga Web UI', address: 'TextGenWebUIBasePath'),
  Provider('cohere', 'Cohere'),
  Provider('litellm', 'LiteLLM', address: 'LiteLLMBasePath'),
  Provider('deepseek', 'DeepSeek'),
  Provider('ppio', 'PPIO'),
  Provider('bedrock', 'AWS Bedrock'),
  Provider('vertex', 'Google Vertex AI'),
  Provider('apipie', 'APIpie'),
  Provider('moonshotai', 'Moonshot AI'),
  Provider('privatemode', 'Privatemode', address: 'PrivateModeBasePath'),
  Provider('novita', 'Novita AI'),
  Provider('cometapi', 'CometAPI'),
  Provider('foundry', 'Microsoft Foundry Local', address: 'FoundryBasePath'),
  Provider('xai', 'xAI'),
  Provider('zai', 'Z.AI'),
  Provider('giteeai', 'GiteeAI'),
  Provider('minimax', 'Minimax'),
  Provider('cerebras', 'Cerebras'),
  Provider('omlx', 'oMLX', address: 'OMLXLLMBasePath'),
  Provider('anythingllm-router', 'Model router'),
]);

const embedderProviders = ProviderSetting('EmbeddingEngine', [
  Provider('native', 'AnythingLLM Embedder'),
  Provider('openai', 'OpenAI'),
  Provider('azure', 'Azure OpenAI'),
  Provider('gemini', 'Gemini'),
  Provider('localai', 'Local AI'),
  Provider('ollama', 'Ollama'),
  Provider('lmstudio', 'LM Studio'),
  Provider('lemonade', 'Lemonade'),
  Provider('openrouter', 'OpenRouter'),
  Provider('litellm', 'LiteLLM'),
  Provider('cohere', 'Cohere'),
  Provider('voyageai', 'Voyage AI'),
  Provider('mistral', 'Mistral AI'),
  Provider('generic-openai', 'Generic OpenAI'),
]);

/// Shown, never switched: switching deletes every vector in the old database.
const vectorProviders = ProviderSetting('VectorDB', [
  Provider('lancedb', 'LanceDB'),
  Provider('pgvector', 'PGVector'),
  Provider('chroma', 'Chroma'),
  Provider('chromacloud', 'Chroma Cloud'),
  Provider('pinecone', 'Pinecone'),
  Provider('zilliz', 'Zilliz Cloud'),
  Provider('qdrant', 'QDrant'),
  Provider('weaviate', 'Weaviate'),
  Provider('milvus', 'Milvus'),
  Provider('astra', 'AstraDB'),
]);

const speechToTextProviders = ProviderSetting('SpeechToTextProvider', [
  Provider('native', 'System native'),
  Provider('openai', 'OpenAI (Whisper API)'),
  Provider('lemonade', 'Lemonade'),
  Provider('deepgram', 'Deepgram'),
  Provider('groq', 'Groq'),
  Provider('generic-openai', 'Generic OpenAI'),
]);

const textToSpeechProviders = ProviderSetting('TextToSpeechProvider', [
  Provider('native', 'System native'),
  Provider('openai', 'OpenAI'),
  Provider('elevenlabs', 'ElevenLabs'),
  Provider('kokoro', 'Kokoro'),
  Provider('generic-openai', 'OpenAI Compatible'),
]);

const transcriptionProviders = ProviderSetting('WhisperProvider', [
  Provider('local', 'AnythingLLM Built-In'),
  Provider('openai', 'OpenAI'),
  Provider('generic-openai', 'OpenAI Compatible'),
]);

/// What Privacy and data says of the server's chat model in [values]: its provider, the host it
/// answers at when the provider is reached at an address, and where questions go.
String chatModelPrivacy(Map<String, Object?> values) {
  final provider = settingText(values, 'LLMProvider');
  final label = chatProviders.labelOf(provider);
  final address = chatProviders.named(provider)?.address;
  final host = Uri.tryParse(settingText(values, address ?? '')) ?? Uri();
  final where = host.host.isEmpty ? label : '$label at ${host.authority}';
  return switch (_reach(host.host)) {
    _Reach.server => '$where. Runs on the server.',
    _Reach.network => '$where. Questions go to that machine.',
    _Reach.service => '$where. Shared under that service\'s terms.',
  };
}

/// What Privacy and data says of the server's document search model in [values].
String searchModelPrivacy(Map<String, Object?> values) {
  final engine = settingText(values, 'EmbeddingEngine');
  final label = embedderProviders.labelOf(engine);
  return engine == 'native'
      ? '$label. Runs on the server.'
      : '$label. Your documents\' text goes to it to be prepared.';
}

/// What Privacy and data says of the server's document storage in [values].
String storagePrivacy(Map<String, Object?> values) {
  final store = settingText(values, 'VectorDB');
  final label = vectorProviders.labelOf(store);
  return store == 'lancedb'
      ? '$label. Passages and text stay on the server.'
      : '$label. Passages and their text are kept there.';
}

/// Where an address answers, as seen from the server.
enum _Reach {
  /// The server's own machine.
  server,

  /// A machine on a private network.
  network,

  /// A service on the internet, or a provider with no address.
  service,
}

_Reach _reach(String host) {
  if (host.isEmpty) return _Reach.service;
  if (isLoopback(host) || host == 'host.docker.internal') return _Reach.server;
  // A name under .internal is Docker's for another container beside the server.
  return isPrivateHost(host) || host.endsWith('.internal')
      ? _Reach.network
      : _Reach.service;
}
