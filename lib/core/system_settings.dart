// The server's own settings, as GET /v1/system gives them: the values a provider setting takes,
// the setting that names each provider's chat model, and a setting read as text.

/// The values the server checks a provider setting against: `LLMProvider`'s, which the chat
/// model picker offers.
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
