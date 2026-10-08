// The server's providers by what they do, each with the settings it reads, as Settings shows
// them: a chooser such as `LLMProvider`, its values by name, and each value's own settings.

import 'connection.dart';
import 'system_settings.dart';

/// How a provider's setting is typed.
enum FieldKind {
  text,
  number,

  /// A key, token or password: the server says only whether it is set.
  secret,
}

/// One setting a provider reads, by its `update-env` name.
class ProviderField {
  const ProviderField._(this.key, this.label, this.kind, this.help);

  /// The field for setting [key], named and typed from its name, made once a key.
  factory ProviderField(String key) =>
      _fields[key] ??= ProviderField._named(key);

  factory ProviderField._named(String key) {
    final (label, help) = _named(key);
    // A token limit names a token too, so numbers are told apart first.
    final kind = _numberName.hasMatch(key)
        ? FieldKind.number
        : secretName.hasMatch(key)
        ? FieldKind.secret
        : FieldKind.text;
    return ProviderField._(key, label, kind, help);
  }

  static final _fields = <String, ProviderField>{};

  final String key;
  final String label;
  final FieldKind kind;

  /// A line under the field, or empty.
  final String help;
}

final _numberName = RegExp(
  'TokenLimit|MaxTokens|Timeout|KeepAliveSeconds|MaxChunkLength|BatchSize|MaxConcurrentChunks|'
  'OutputDimensions',
);

/// The label and help of setting [key], from the end of its name.
(String, String) _named(String key) => switch (key) {
  'AzureOpenAiModelPref' => ('Chat deployment name', ''),
  'AzureOpenAiEmbeddingModelPref' => ('Embedding deployment name', ''),
  'ChromaApiHeader' => ('API header', 'The header the key is sent in.'),
  'ChromaApiKey' => ('API header value', ''),
  'ModelRouterId' => ('Router', 'The id of a router made in AnythingLLM.'),
  'WhisperModelPref' => ('Model', 'Downloads on first use.'),
  _ when key.endsWith('ConnectionString') => ('Connection string', ''),
  _ when key.endsWith('ApplicationToken') => ('Application token', ''),
  _ when key.endsWith('ApiToken') => ('API token', ''),
  _ when key.endsWith('AuthToken') => ('Auth token', 'Optional.'),
  _ when key.endsWith('Password') => ('Password', ''),
  _ when key.endsWith('Username') => ('Username', ''),
  _ when key.toLowerCase().endsWith('key') => ('API key', ''),
  _ when key.endsWith('BasePath') || key.endsWith('BaseUrl') => (
    'Base URL',
    'Where the service answers.',
  ),
  _ when key.endsWith('Endpoint') => ('Endpoint', 'Where the service answers.'),
  _ when key.endsWith('Address') => ('Address', 'Where the service answers.'),
  _ when key.endsWith('VoiceModel') => ('Voice', ''),
  _ when key.endsWith('TokenLimit') => (
    'Context window',
    'How much text the model can read at once, in tokens.',
  ),
  _ when key.endsWith('MaxTokens') => (
    'Longest answer',
    'Most tokens one answer may use.',
  ),
  _ when key.endsWith('MaxChunkLength') => (
    'Longest passage',
    'Characters per passage the model accepts.',
  ),
  _ when key.endsWith('KeepAliveSeconds') => (
    'Keep loaded',
    'Seconds the model stays loaded after an answer.',
  ),
  _ when key.endsWith('Timeout') => (
    'Timeout',
    'How long to wait for an answer.',
  ),
  _ when key.endsWith('BatchSize') => ('Batch size', 'Passages sent at once.'),
  _ when key.endsWith('MaxConcurrentChunks') => (
    'Passages at once',
    'How many passages are sent together.',
  ),
  _ when key.endsWith('OutputDimensions') => ('Output dimensions', 'Optional.'),
  _ when key.endsWith('QueryPrefix') => ('Query prefix', 'Optional.'),
  _ when key.endsWith('PassagePrefix') => ('Passage prefix', 'Optional.'),
  _ when key.endsWith('ProjectId') => ('Project ID', ''),
  _ when key.endsWith('Region') => ('Region', ''),
  _ when key.endsWith('Index') => ('Index name', ''),
  _ when key.endsWith('TableName') => ('Table name', ''),
  _ when key.endsWith('Tenant') => ('Tenant', ''),
  _ when key.endsWith('Database') => ('Database', ''),
  _ when key.endsWith('Dimensions') => ('Image size', 'Such as 1024x1024.'),
  _ when key.endsWith('CacheControl') => ('Prompt caching', 'none, 5m or 1h.'),
  _ when key.endsWith('SafetySetting') => ('Safety setting', ''),
  _ when key.endsWith('ServiceTier') => ('Service tier', ''),
  _ when key.endsWith('ModelType') => ('Model type', 'default or reasoning.'),
  _ when key.endsWith('ModelPref') || key.endsWith('Model') => (
    'Model',
    'The provider\'s own name for it.',
  ),
  _ => (key, ''),
};

/// One value of a chooser, with its name and the settings it reads.
class Provider {
  const Provider(this.value, this.label, [this.keys = const []]);

  /// The value the server stores.
  final String value;
  final String label;
  final List<String> keys;

  List<ProviderField> get fields => [
    for (final key in keys) ProviderField(key),
  ];
}

/// A setting that picks a provider, such as `LLMProvider`, and what each value reads.
class ProviderSetting {
  const ProviderSetting(
    this.chooser,
    this.label,
    this.providers, {
    this.recommended,
    this.help = '',
  });

  final String chooser;

  /// What the chooser is called on its page.
  final String label;
  final List<Provider> providers;

  /// Whether the chooser itself may be changed. The fields of the chosen provider always may.
  bool get writable => !readOnlySettings.contains(chooser);

  /// The value that needs no setup, which Settings marks as recommended.
  final String? recommended;

  /// A line under the chooser, or empty. With a [recommended] value it is about that value, and
  /// shows only while that value is chosen, beside its badge.
  final String help;

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

const _embedLocal = [
  'EmbeddingBasePath',
  'EmbeddingModelPref',
  'EmbeddingModelMaxChunkLength',
];

const chatProviders = ProviderSetting(
  'LLMProvider',
  'Provider',
  help: 'Any OpenAI-compatible service works with Generic OpenAI.',
  [
    Provider('generic-openai', 'Generic OpenAI', [
      'GenericOpenAiBasePath', 'GenericOpenAiKey', 'GenericOpenAiModelPref', //
      'GenericOpenAiTokenLimit', 'GenericOpenAiMaxTokens',
    ]),
    Provider('openai', 'OpenAI', ['OpenAiKey', 'OpenAiModelPref']),
    Provider('azure', 'Azure OpenAI', [
      'AzureOpenAiEndpoint', 'AzureOpenAiKey', 'AzureOpenAiModelPref', //
      'AzureOpenAiTokenLimit', 'AzureOpenAiModelType',
    ]),
    Provider('anthropic', 'Anthropic', [
      'AnthropicApiKey',
      'AnthropicModelPref',
      'AnthropicCacheControl',
    ]),
    Provider('gemini', 'Gemini', [
      'GeminiLLMApiKey',
      'GeminiLLMModelPref',
      'GeminiSafetySetting',
    ]),
    Provider('nvidia-nim', 'NVIDIA NIM', [
      'NvidiaNimLLMBasePath',
      'NvidiaNimLLMModelPref',
    ]),
    Provider('ollama', 'Ollama', [
      'OllamaLLMBasePath', 'OllamaLLMModelPref', 'OllamaLLMTokenLimit', //
      'OllamaLLMKeepAliveSeconds', 'OllamaLLMAuthToken',
    ]),
    Provider('lmstudio', 'LM Studio', [
      'LMStudioBasePath', 'LMStudioModelPref', 'LMStudioTokenLimit', //
      'LMStudioAuthToken',
    ]),
    Provider('llmman', 'llmman', [
      'LlmmanBasePath', 'LlmmanModelPref', 'LlmmanTokenLimit', //
      'LlmmanKeepAliveSeconds', 'LlmmanAuthToken',
    ]),
    Provider('lemonade', 'Lemonade', [
      'LemonadeLLMBasePath', 'LemonadeLLMModelPref', //
      'LemonadeLLMModelTokenLimit', 'LemonadeLLMApiKey',
    ]),
    Provider('sambanova', 'SambaNova', [
      'SambaNovaLLMApiKey',
      'SambaNovaLLMModelPref',
    ]),
    Provider('localai', 'Local AI', [
      'LocalAiBasePath', 'LocalAiModelPref', 'LocalAiTokenLimit', //
      'LocalAiApiKey',
    ]),
    Provider('togetherai', 'Together AI', [
      'TogetherAiApiKey',
      'TogetherAiModelPref',
      'TogetherAiMaxTokens',
    ]),
    Provider('fireworksai', 'Fireworks AI', [
      'FireworksAiLLMApiKey',
      'FireworksAiLLMModelPref',
    ]),
    Provider('mistral', 'Mistral', ['MistralApiKey', 'MistralModelPref']),
    Provider('perplexity', 'Perplexity AI', [
      'PerplexityApiKey',
      'PerplexityModelPref',
    ]),
    Provider('openrouter', 'OpenRouter', [
      'OpenRouterApiKey', 'OpenRouterModelPref', 'OpenRouterTimeout', //
      'OpenRouterServiceTier',
    ]),
    Provider('groq', 'Groq', ['GroqApiKey', 'GroqModelPref']),
    Provider('koboldcpp', 'KoboldCPP', [
      'KoboldCPPBasePath', 'KoboldCPPModelPref', 'KoboldCPPTokenLimit', //
      'KoboldCPPMaxTokens',
    ]),
    Provider('textgenwebui', 'Oobabooga Web UI', [
      'TextGenWebUIBasePath',
      'TextGenWebUITokenLimit',
      'TextGenWebUIAPIKey',
    ]),
    Provider('cohere', 'Cohere', ['CohereApiKey', 'CohereModelPref']),
    Provider('litellm', 'LiteLLM', [
      'LiteLLMBasePath', 'LiteLLMModelPref', 'LiteLLMTokenLimit', //
      'LiteLLMApiKey',
    ]),
    Provider('deepseek', 'DeepSeek', ['DeepSeekApiKey', 'DeepSeekModelPref']),
    Provider('ppio', 'PPIO', ['PPIOApiKey', 'PPIOModelPref']),
    Provider('bedrock', 'AWS Bedrock', [
      'AwsBedrockLLMApiKey', 'AwsBedrockLLMRegion', 'AwsBedrockLLMModel', //
      'AwsBedrockLLMTokenLimit', 'AwsBedrockLLMMaxTokens',
    ]),
    Provider('vertex', 'Google Vertex AI', [
      'VertexAiLLMProjectId', 'VertexAiLLMRegion', 'VertexAiLLMApiKey', //
      'VertexAiLLMModelPref', 'VertexAiLLMTokenLimit',
    ]),
    Provider('apipie', 'APIpie', ['ApipieLLMApiKey', 'ApipieLLMModelPref']),
    Provider('moonshotai', 'Moonshot AI', [
      'MoonshotAiApiKey',
      'MoonshotAiModelPref',
    ]),
    Provider('privatemode', 'Privatemode', [
      'PrivateModeBasePath',
      'PrivateModeModelPref',
    ]),
    Provider('novita', 'Novita AI', [
      'NovitaLLMApiKey',
      'NovitaLLMModelPref',
      'NovitaLLMTimeout',
    ]),
    Provider('cometapi', 'CometAPI', [
      'CometApiLLMApiKey',
      'CometApiLLMModelPref',
      'CometApiLLMTimeout',
    ]),
    Provider('foundry', 'Microsoft Foundry Local', [
      'FoundryBasePath',
      'FoundryModelPref',
      'FoundryModelTokenLimit',
    ]),
    Provider('xai', 'xAI', ['XAIApiKey', 'XAIModelPref']),
    Provider('zai', 'Z.AI', ['ZAiApiKey', 'ZAiModelPref']),
    Provider('giteeai', 'GiteeAI', [
      'GiteeAIApiKey',
      'GiteeAIModelPref',
      'GiteeAITokenLimit',
    ]),
    Provider('minimax', 'Minimax', ['MinimaxApiKey', 'MinimaxModelPref']),
    Provider('cerebras', 'Cerebras', ['CerebrasApiKey', 'CerebrasModelPref']),
    Provider('omlx', 'oMLX', [
      'OMLXLLMBasePath', 'OMLXLLMModelPref', 'OMLXLLMTokenLimit', //
      'OMLXLLMApiKey',
    ]),
    Provider('anythingllm-router', 'Model router', ['ModelRouterId']),
  ],
);

const embedderProviders = ProviderSetting(
  'EmbeddingEngine',
  'Provider',
  recommended: 'native',
  help: 'Built in, no setup.',
  [
    Provider('native', 'AnythingLLM Embedder', ['EmbeddingModelPref']),
    Provider('openai', 'OpenAI', ['OpenAiKey', 'EmbeddingModelPref']),
    Provider('azure', 'Azure OpenAI', [
      'AzureOpenAiEndpoint',
      'AzureOpenAiKey',
      'AzureOpenAiEmbeddingModelPref',
    ]),
    Provider('gemini', 'Gemini', [
      'GeminiEmbeddingApiKey',
      'EmbeddingModelPref',
    ]),
    Provider('localai', 'Local AI', [..._embedLocal, 'LocalAiApiKey']),
    Provider('ollama', 'Ollama', [..._embedLocal, 'OllamaEmbeddingBatchSize']),
    Provider('lmstudio', 'LM Studio', _embedLocal),
    Provider('lemonade', 'Lemonade', _embedLocal),
    Provider('openrouter', 'OpenRouter', [
      'OpenRouterApiKey',
      'EmbeddingModelPref',
    ]),
    Provider('litellm', 'LiteLLM', [..._embedLocal, 'LiteLLMApiKey']),
    Provider('cohere', 'Cohere', ['CohereApiKey', 'EmbeddingModelPref']),
    Provider('voyageai', 'Voyage AI', ['VoyageAiApiKey', 'EmbeddingModelPref']),
    Provider('mistral', 'Mistral AI', ['MistralApiKey', 'EmbeddingModelPref']),
    Provider('generic-openai', 'Generic OpenAI', [
      ..._embedLocal,
      'GenericOpenAiEmbeddingApiKey',
      'GenericOpenAiEmbeddingMaxConcurrentChunks',
      'EmbeddingOutputDimensions',
      'GenericOpenAiEmbeddingQueryPrefix',
      'GenericOpenAiEmbeddingPassagePrefix',
    ]),
  ],
);

/// Shown, never switched: switching deletes every vector in the old database.
const vectorProviders = ProviderSetting(
  'VectorDB',
  'Database',
  help:
      'Shown, not changed here: switching it deletes every stored passage, and every '
      'document would have to be read again.',
  [
    Provider('lancedb', 'LanceDB'),
    Provider('pgvector', 'PGVector', [
      'PGVectorConnectionString',
      'PGVectorTableName',
    ]),
    Provider('chroma', 'Chroma', [
      'ChromaEndpoint',
      'ChromaApiHeader',
      'ChromaApiKey',
    ]),
    Provider('chromacloud', 'Chroma Cloud', [
      'ChromaCloudApiKey',
      'ChromaCloudTenant',
      'ChromaCloudDatabase',
    ]),
    Provider('pinecone', 'Pinecone', ['PineConeKey', 'PineConeIndex']),
    Provider('zilliz', 'Zilliz Cloud', ['ZillizEndpoint', 'ZillizApiToken']),
    Provider('qdrant', 'QDrant', ['QdrantEndpoint', 'QdrantApiKey']),
    Provider('weaviate', 'Weaviate', ['WeaviateEndpoint', 'WeaviateApiKey']),
    Provider('milvus', 'Milvus', [
      'MilvusAddress',
      'MilvusUsername',
      'MilvusPassword',
    ]),
    Provider('astra', 'AstraDB', [
      'AstraDBEndpoint',
      'AstraDBApplicationToken',
    ]),
  ],
);

const _imageModel = 'ImageGenerationModelPref';

const imageProviders = ProviderSetting('ImageGenerationProvider', 'Provider', [
  Provider('openai', 'OpenAI', [
    'ImageGenerationOpenAiKey',
    _imageModel,
    'ImageGenerationDimensions',
  ]),
  Provider('ollama', 'Ollama (macOS only)', [
    'ImageGenerationOllamaBasePath',
    _imageModel,
    'ImageGenerationOllamaAuthToken',
  ]),
  Provider('lemonade', 'Lemonade', [
    'ImageGenerationLemonadeBasePath',
    _imageModel,
    'ImageGenerationLemonadeApiKey',
  ]),
  Provider('localai', 'LocalAI', [
    'ImageGenerationLocalAiBasePath',
    _imageModel,
    'ImageGenerationLocalAiApiKey',
  ]),
  Provider('openrouter', 'OpenRouter', [
    'ImageGenerationOpenRouterApiKey',
    _imageModel,
  ]),
  Provider('gemini', 'Gemini', ['ImageGenerationGeminiApiKey', _imageModel]),
  Provider('llmman', 'llmman', [
    'ImageGenerationLlmmanBasePath',
    _imageModel,
    'ImageGenerationLlmmanAuthToken',
  ]),
]);

const speechToTextProviders = ProviderSetting(
  'SpeechToTextProvider',
  'Speech to text',
  recommended: 'native',
  help: 'System native uses the device. No setup.',
  [
    Provider('native', 'System native'),
    Provider('openai', 'OpenAI (Whisper API)', ['STTOpenAIModel']),
    Provider('lemonade', 'Lemonade', [
      'STTLemonadeBasePath',
      'STTLemonadeModelPref',
    ]),
    Provider('deepgram', 'Deepgram', ['STTDeepgramApiKey', 'STTDeepgramModel']),
    Provider('groq', 'Groq', ['STTGroqApiKey', 'STTGroqModel']),
    Provider('generic-openai', 'Generic OpenAI', [
      'STTOpenAICompatibleEndpoint',
      'STTOpenAICompatibleKey',
      'STTOpenAICompatibleModel',
    ]),
  ],
);

const textToSpeechProviders = ProviderSetting(
  'TextToSpeechProvider',
  'Text to speech',
  recommended: 'native',
  help: 'System native uses the device. No setup.',
  [
    Provider('native', 'System native'),
    Provider('openai', 'OpenAI', ['TTSOpenAIKey', 'TTSOpenAIVoiceModel']),
    Provider('elevenlabs', 'ElevenLabs', [
      'TTSElevenLabsKey',
      'TTSElevenLabsVoiceModel',
    ]),
    Provider('kokoro', 'Kokoro', [
      'TTSKokoroEndpoint',
      'TTSKokoroKey',
      'TTSKokoroVoiceModel',
    ]),
    Provider('generic-openai', 'OpenAI Compatible', [
      'TTSOpenAICompatibleEndpoint',
      'TTSOpenAICompatibleKey',
      'TTSOpenAICompatibleModel',
      'TTSOpenAICompatibleVoiceModel',
    ]),
  ],
);

const transcriptionProviders = ProviderSetting(
  'WhisperProvider',
  'Provider',
  recommended: 'local',
  help: 'Runs a Whisper model privately on the server.',
  [
    Provider('local', 'AnythingLLM Built-In', ['WhisperModelPref']),
    Provider('openai', 'OpenAI', ['OpenAiKey']),
    Provider('generic-openai', 'OpenAI Compatible', [
      'WhisperGenericOpenAiBaseUrl',
      'WhisperGenericOpenAiApiKey',
      'WhisperGenericOpenAiModel',
    ]),
  ],
);

/// Every chooser Settings shows.
const providerSettings = [
  chatProviders,
  embedderProviders,
  vectorProviders,
  imageProviders,
  speechToTextProviders,
  textToSpeechProviders,
  transcriptionProviders,
];

/// What Privacy and data says of the server's chat model in [values]: its provider, the host it
/// answers at when the provider is reached at an address, and where questions go.
String chatModelPrivacy(Map<String, Object?> values) {
  final provider = settingText(values, 'LLMProvider');
  final label = chatProviders.labelOf(provider);
  final address = chatProviders
      .named(provider)
      ?.keys
      .where(_addressName.hasMatch)
      .firstOrNull;
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

final _addressName = RegExp(r'(BasePath|BaseUrl|Endpoint|Address)$');

/// Where an address answers, as seen from the server.
enum _Reach {
  /// The server's own machine.
  server,

  /// A machine on a private network.
  network,

  /// A service on the internet, or a provider with no address.
  service,
}

final _privateHost = RegExp(
  r'^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.)'
  r'|\.(local|lan|internal|home\.arpa|ts\.net)$'
  r'|^[^.:]+$',
);

_Reach _reach(String host) {
  if (host.isEmpty) return _Reach.service;
  if (isLoopback(host) || host == 'host.docker.internal') return _Reach.server;
  return _privateHost.hasMatch(host) ? _Reach.network : _Reach.service;
}
