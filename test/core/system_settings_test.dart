import 'package:anywherellm/core/system_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings as `GET /v1/system` gives them: a secret is only whether it is set.
const _server = <String, Object?>{
  'LLMProvider': 'generic-openai',
  'GenericOpenAiModelPref': 'glm-5.3-flash',
  'GenericOpenAiTokenLimit': '128000',
  'GenericOpenAiKey': true,
  'OpenAiKey': false,
  'AnthropicModelPref': null,
  'EmbeddingEngine': 'native',
  'VectorDB': 'lancedb',
  'AgentSkillRerankerEnabled': true,
  'AgentSearXNGApiUrl': 'https://search.example/search',
  'ImageGenerationProvider': null,
  'AuthToken': true,
  'RequiresAuth': true,
  'StorageDir': '/app/server/storage',
};

void main() {
  test(
    'every chat provider the server takes but two names its model setting',
    () {
      expect(
        systemChoices['LLMProvider']!.where(
          (p) => !chatModelKeys.containsKey(p),
        ),
        ['textgenwebui', 'anythingllm-router'],
      );
      expect(
        chatModelKeys.keys,
        everyElement(isIn(systemChoices['LLMProvider']!)),
      );
    },
  );

  test('a setting reads as text, and a secret as empty', () {
    expect(settingText(_server, 'LLMProvider'), 'generic-openai');
    expect(settingText(_server, 'GenericOpenAiKey'), '');
    expect(settingText(_server, 'Nope'), '');
    expect(settingText(null, 'LLMProvider'), '');
  });
}
