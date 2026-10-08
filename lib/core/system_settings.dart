// The server's own settings, which `update-env` writes to its `.env`: which may be written, how
// each is checked, and which section of the form it sits in.

import 'dart:convert';

import 'errors.dart';

/// The settings `update-env` takes, from AnythingLLM 1.16.2's `KEY_MAPPING`, less the server's
/// password and signing secret, which it changes only in its own force mode. A key it does not
/// take is dropped without a word, so the app writes no other.
const systemKeys = {
  'AgentAnySearchApiKey',
  'AgentBaiduSearchApiKey',
  'AgentBingSearchApiKey',
  'AgentBraveApiKey',
  'AgentCrwApiKey',
  'AgentCrwApiUrl',
  'AgentExaApiKey',
  'AgentFirecrawlApiKey',
  'AgentKeenableApiKey',
  'AgentKeenableApiUrl',
  'AgentPerplexityApiKey',
  'AgentSearXNGApiUrl',
  'AgentSearchApiEngine',
  'AgentSearchApiKey',
  'AgentSerpApiEngine',
  'AgentSerpApiKey',
  'AgentSerperApiKey',
  'AgentSerplyApiKey',
  'AgentSkillMaxToolCalls',
  'AgentSkillRerankerEnabled',
  'AgentSkillRerankerTopN',
  'AgentTavilyApiKey',
  'AgentYouApiKey',
  'AnthropicApiKey',
  'AnthropicCacheControl',
  'AnthropicModelPref',
  'ApipieLLMApiKey',
  'ApipieLLMModelPref',
  'AstraDBApplicationToken',
  'AstraDBEndpoint',
  'AwsBedrockLLMApiKey',
  'AwsBedrockLLMMaxTokens',
  'AwsBedrockLLMModel',
  'AwsBedrockLLMRegion',
  'AwsBedrockLLMTokenLimit',
  'AzureOpenAiEmbeddingModelPref',
  'AzureOpenAiEndpoint',
  'AzureOpenAiKey',
  'AzureOpenAiModelPref',
  'AzureOpenAiModelType',
  'AzureOpenAiTokenLimit',
  'CerebrasApiKey',
  'CerebrasModelPref',
  'ChromaApiHeader',
  'ChromaApiKey',
  'ChromaCloudApiKey',
  'ChromaCloudDatabase',
  'ChromaCloudTenant',
  'ChromaEndpoint',
  'CohereApiKey',
  'CohereModelPref',
  'CometApiLLMApiKey',
  'CometApiLLMModelPref',
  'CometApiLLMTimeout',
  'DeepSeekApiKey',
  'DeepSeekModelPref',
  'DisableTelemetry',
  'EmbeddingBasePath',
  'EmbeddingEngine',
  'EmbeddingModelMaxChunkLength',
  'EmbeddingModelPref',
  'EmbeddingOutputDimensions',
  'FireworksAiLLMApiKey',
  'FireworksAiLLMModelPref',
  'FoundryBasePath',
  'FoundryModelPref',
  'FoundryModelTokenLimit',
  'GeminiEmbeddingApiKey',
  'GeminiLLMApiKey',
  'GeminiLLMModelPref',
  'GeminiSafetySetting',
  'GenericOpenAiBasePath',
  'GenericOpenAiEmbeddingApiKey',
  'GenericOpenAiEmbeddingMaxConcurrentChunks',
  'GenericOpenAiEmbeddingPassagePrefix',
  'GenericOpenAiEmbeddingQueryPrefix',
  'GenericOpenAiKey',
  'GenericOpenAiMaxTokens',
  'GenericOpenAiModelPref',
  'GenericOpenAiTokenLimit',
  'GiteeAIApiKey',
  'GiteeAIModelPref',
  'GiteeAITokenLimit',
  'GroqApiKey',
  'GroqModelPref',
  'ImageGenerationDimensions',
  'ImageGenerationGeminiApiKey',
  'ImageGenerationLemonadeApiKey',
  'ImageGenerationLemonadeBasePath',
  'ImageGenerationLlmmanAuthToken',
  'ImageGenerationLlmmanBasePath',
  'ImageGenerationLocalAiApiKey',
  'ImageGenerationLocalAiBasePath',
  'ImageGenerationModelPref',
  'ImageGenerationOllamaAuthToken',
  'ImageGenerationOllamaBasePath',
  'ImageGenerationOpenAiKey',
  'ImageGenerationOpenRouterApiKey',
  'ImageGenerationProvider',
  'KoboldCPPBasePath',
  'KoboldCPPMaxTokens',
  'KoboldCPPModelPref',
  'KoboldCPPTokenLimit',
  'LLMProvider',
  'LMStudioAuthToken',
  'LMStudioBasePath',
  'LMStudioModelPref',
  'LMStudioTokenLimit',
  'LemonadeLLMApiKey',
  'LemonadeLLMBasePath',
  'LemonadeLLMModelPref',
  'LemonadeLLMModelTokenLimit',
  'LiteLLMApiKey',
  'LiteLLMBasePath',
  'LiteLLMModelPref',
  'LiteLLMTokenLimit',
  'LlmmanAuthToken',
  'LlmmanBasePath',
  'LlmmanKeepAliveSeconds',
  'LlmmanModelPref',
  'LlmmanTokenLimit',
  'LocalAiApiKey',
  'LocalAiBasePath',
  'LocalAiModelPref',
  'LocalAiTokenLimit',
  'MilvusAddress',
  'MilvusPassword',
  'MilvusUsername',
  'MinimaxApiKey',
  'MinimaxModelPref',
  'MistralApiKey',
  'MistralModelPref',
  'ModelRouterId',
  'MoonshotAiApiKey',
  'MoonshotAiModelPref',
  'NovitaLLMApiKey',
  'NovitaLLMModelPref',
  'NovitaLLMTimeout',
  'NvidiaNimLLMBasePath',
  'NvidiaNimLLMModelPref',
  'OMLXLLMApiKey',
  'OMLXLLMBasePath',
  'OMLXLLMModelPref',
  'OMLXLLMTokenLimit',
  'OllamaEmbeddingBatchSize',
  'OllamaLLMAuthToken',
  'OllamaLLMBasePath',
  'OllamaLLMKeepAliveSeconds',
  'OllamaLLMModelPref',
  'OllamaLLMTokenLimit',
  'OpenAiKey',
  'OpenAiModelPref',
  'OpenRouterApiKey',
  'OpenRouterModelPref',
  'OpenRouterServiceTier',
  'OpenRouterTimeout',
  'PGVectorConnectionString',
  'PGVectorTableName',
  'PPIOApiKey',
  'PPIOModelPref',
  'PerplexityApiKey',
  'PerplexityModelPref',
  'PineConeIndex',
  'PineConeKey',
  'PrivateModeBasePath',
  'PrivateModeModelPref',
  'QdrantApiKey',
  'QdrantEndpoint',
  'STTDeepgramApiKey',
  'STTDeepgramModel',
  'STTGroqApiKey',
  'STTGroqModel',
  'STTLemonadeBasePath',
  'STTLemonadeModelPref',
  'STTOpenAICompatibleEndpoint',
  'STTOpenAICompatibleKey',
  'STTOpenAICompatibleModel',
  'STTOpenAIModel',
  'SambaNovaLLMApiKey',
  'SambaNovaLLMModelPref',
  'SpeechToTextProvider',
  'TTSElevenLabsKey',
  'TTSElevenLabsVoiceModel',
  'TTSKokoroEndpoint',
  'TTSKokoroKey',
  'TTSKokoroVoiceModel',
  'TTSOpenAICompatibleEndpoint',
  'TTSOpenAICompatibleKey',
  'TTSOpenAICompatibleModel',
  'TTSOpenAICompatibleVoiceModel',
  'TTSOpenAIKey',
  'TTSOpenAIVoiceModel',
  'TTSPiperTTSVoiceModel',
  'TextGenWebUIAPIKey',
  'TextGenWebUIBasePath',
  'TextGenWebUITokenLimit',
  'TextToSpeechProvider',
  'TogetherAiApiKey',
  'TogetherAiMaxTokens',
  'TogetherAiModelPref',
  'VectorDB',
  'VertexAiLLMApiKey',
  'VertexAiLLMModelPref',
  'VertexAiLLMProjectId',
  'VertexAiLLMRegion',
  'VertexAiLLMTokenLimit',
  'VoyageAiApiKey',
  'WeaviateApiKey',
  'WeaviateEndpoint',
  'WhisperGenericOpenAiApiKey',
  'WhisperGenericOpenAiBaseUrl',
  'WhisperGenericOpenAiModel',
  'WhisperModelPref',
  'WhisperProvider',
  'XAIApiKey',
  'XAIModelPref',
  'ZAiApiKey',
  'ZAiModelPref',
  'ZillizApiToken',
  'ZillizEndpoint',
};

/// The values the server checks a provider setting against.
const systemChoices = {
  'LLMProvider': [
    'openai',
    'azure',
    'anthropic',
    'gemini',
    'lmstudio',
    'localai',
    'ollama', //
    'togetherai',
    'fireworksai',
    'mistral',
    'perplexity',
    'openrouter',
    'novita', //
    'groq',
    'koboldcpp',
    'textgenwebui',
    'cohere',
    'litellm',
    'generic-openai', //
    'bedrock',
    'deepseek',
    'apipie',
    'xai',
    'nvidia-nim',
    'ppio',
    'moonshotai', //
    'cometapi',
    'foundry',
    'zai',
    'giteeai',
    'llmman',
    'privatemode',
    'sambanova', //
    'lemonade', 'minimax', 'cerebras', 'omlx', 'anythingllm-router', 'vertex',
  ],
  'EmbeddingEngine': [
    'openai', 'azure', 'gemini', 'localai', 'native', 'ollama', 'lmstudio', //
    'cohere',
    'voyageai',
    'litellm',
    'generic-openai',
    'mistral',
    'openrouter', //
    'lemonade',
  ],
  'TextToSpeechProvider': [
    'native',
    'openai',
    'elevenlabs',
    'generic-openai',
    'kokoro',
  ],
  'SpeechToTextProvider': [
    'native',
    'openai',
    'lemonade',
    'deepgram',
    'groq',
    'generic-openai',
  ],
  'WhisperProvider': ['openai', 'generic-openai', 'local'],
  'ImageGenerationProvider': [
    'openai',
    'ollama',
    'lemonade',
    'openrouter',
    'localai',
    'llmman',
    'gemini',
  ],
};

/// The setting that names the chat model, by each `LLMProvider` that has one, from AnythingLLM
/// 1.16.2's `KEY_MAPPING`. Text Generation Web UI serves whatever model it has loaded, and the
/// model router picks a model itself, so neither is here.
const chatModelKeys = {
  'openai': 'OpenAiModelPref',
  'azure': 'AzureOpenAiModelPref',
  'anthropic': 'AnthropicModelPref',
  'gemini': 'GeminiLLMModelPref',
  'lmstudio': 'LMStudioModelPref',
  'localai': 'LocalAiModelPref',
  'ollama': 'OllamaLLMModelPref',
  'togetherai': 'TogetherAiModelPref',
  'fireworksai': 'FireworksAiLLMModelPref',
  'mistral': 'MistralModelPref',
  'perplexity': 'PerplexityModelPref',
  'openrouter': 'OpenRouterModelPref',
  'novita': 'NovitaLLMModelPref',
  'groq': 'GroqModelPref',
  'koboldcpp': 'KoboldCPPModelPref',
  'cohere': 'CohereModelPref',
  'litellm': 'LiteLLMModelPref',
  'generic-openai': 'GenericOpenAiModelPref',
  'bedrock': 'AwsBedrockLLMModel',
  'deepseek': 'DeepSeekModelPref',
  'apipie': 'ApipieLLMModelPref',
  'xai': 'XAIModelPref',
  'nvidia-nim': 'NvidiaNimLLMModelPref',
  'ppio': 'PPIOModelPref',
  'moonshotai': 'MoonshotAiModelPref',
  'cometapi': 'CometApiLLMModelPref',
  'foundry': 'FoundryModelPref',
  'zai': 'ZAiModelPref',
  'giteeai': 'GiteeAIModelPref',
  'llmman': 'LlmmanModelPref',
  'privatemode': 'PrivateModeModelPref',
  'sambanova': 'SambaNovaLLMModelPref',
  'lemonade': 'LemonadeLLMModelPref',
  'minimax': 'MinimaxModelPref',
  'cerebras': 'CerebrasModelPref',
  'omlx': 'OMLXLLMModelPref',
  'vertex': 'VertexAiLLMModelPref',
};

/// The settings whose change makes the server delete every vector it holds, so that every
/// workspace's documents must be embedded again.
const resetsVectors = {
  'EmbeddingEngine',
  'EmbeddingModelPref',
  'AzureOpenAiEmbeddingModelPref',
};

/// Shown, never written: switching the vector database deletes every vector in the old one and
/// leaves the new one empty.
const readOnlySettings = {'VectorDB'};

/// Matches the name of a setting that holds a key or password, which the server never shows.
final secretName = RegExp(
  'key|secret|token|password|connectionstring',
  caseSensitive: false,
);

/// One writable setting the server has a value for.
class SystemField {
  const SystemField(this.key, this.value, {this.secret = false});

  final String key;

  /// The value the server has, as text: empty for a secret, whose value is never read.
  final String value;

  /// A key or password: the server says only whether it is set, and it can only be replaced.
  final bool secret;
}

/// The provider the system answers with and its model, as GET /v1/system gives them in
/// [values], each empty while not known.
({String provider, String model}) systemChatModel(
  Map<String, Object?>? values,
) {
  final provider = settingText(values, 'LLMProvider');
  return (
    provider: provider,
    model: settingText(values, chatModelKeys[provider] ?? ''),
  );
}

/// Setting [key] of [settings] as text: empty when it has none, or for a secret, which the server
/// shows only as whether it is set.
String settingText(Map<String, Object?>? settings, String key) =>
    switch (settings?[key]) {
      null || bool() => '',
      final value => '$value',
    };

/// Whether [key], which the server reported as [value], is a secret it hid behind whether it is
/// set. A real on-off setting, such as `AgentSkillRerankerEnabled`, names no secret.
bool _isSecret(String key, Object? value) =>
    value is bool && secretName.hasMatch(key);

/// The settings the server has, by name: each writable one with a value, a provider always, and
/// a secret only when it is set.
List<SystemField> systemFields(Map<String, Object?> settings) {
  final fields = <SystemField>[];
  for (final key in settings.keys.toList()..sort()) {
    if (!systemKeys.contains(key)) continue;
    final value = settings[key];
    if (_isSecret(key, value)) {
      if (value == true) fields.add(SystemField(key, '', secret: true));
    } else if (value != null || systemChoices.containsKey(key)) {
      fields.add(SystemField(key, value == null ? '' : '$value'));
    }
  }
  return fields;
}

const _indented = JsonEncoder.withIndent('  ');

/// The writable settings the server has a value for, as the JSON Settings shows and edits. No
/// secret is in it.
String systemText(Map<String, Object?> settings) =>
    '${_indented.convert({for (final field in systemFields(settings))
      if (!field.secret) field.key: settings[field.key]})}\n';

/// The settings in [text] that differ from [was], each as the text `update-env` writes. A secret,
/// which [was] has only as whether it is set, is sent when it is given as text, since its value is
/// never known; given as true or false, as the server reports it, it is left as it was. Throws [ApiException] when
/// the text is not a JSON object, names a setting the app does not write, empties one, or gives
/// a provider a value the server does not take.
Map<String, String> parseSystemSettings(String text, Map<String, Object?> was) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException catch (error) {
    throw ApiException('The settings are not valid JSON: ${error.message}');
  }
  if (json is! Map<String, dynamic>) {
    throw const ApiException('The settings must be one JSON object.');
  }
  final changed = <String, String>{};
  for (final MapEntry(:key, :value) in json.entries) {
    if (!systemKeys.contains(key) || readOnlySettings.contains(key)) {
      if (readOnlySettings.contains(key) && value == was[key]) continue;
      throw ApiException(
        readOnlySettings.contains(key)
            ? '$key is shown, not written: switching it deletes every vector.'
            : '$key is not a setting the server takes from the app.',
      );
    }
    final secret = _isSecret(key, was[key]);
    if (secret && value is bool) continue;
    if (value == null) {
      if (was[key] == null || secret) continue;
      throw ApiException('$key cannot be emptied here; leave it as it was.');
    }
    if (value is! String && value is! num && value is! bool) {
      throw ApiException('$key must be text, a number or true or false.');
    }
    final next = '$value'.trim();
    if (secret) {
      if (next.isNotEmpty) changed[key] = next;
      continue;
    }
    if (next == '${was[key] ?? ''}'.trim()) continue;
    if (next.isEmpty) {
      throw ApiException('$key cannot be emptied here; leave it as it was.');
    }
    if (next.split('').every((c) => c == '*')) {
      throw ApiException(
        '$key cannot be only asterisks: the server drops such a value.',
      );
    }
    final choices = systemChoices[key];
    if (choices != null && !choices.contains(next)) {
      throw ApiException('$key must be one of ${choices.join(', ')}.');
    }
    changed[key] = next;
  }
  return changed;
}
