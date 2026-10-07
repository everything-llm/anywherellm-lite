import 'dart:convert';

import 'package:anywherellm/core/errors.dart';
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
  test('each chat provider with a model names a setting the server takes', () {
    expect(
      systemChoices['LLMProvider']!.where((p) => !chatModelKeys.containsKey(p)),
      ['textgenwebui', 'anythingllm-router'],
    );
    expect(
      chatModelKeys.keys,
      everyElement(isIn(systemChoices['LLMProvider']!)),
    );
    expect(chatModelKeys.values, everyElement(isIn(systemKeys)));
  });

  group('the form', () {
    test('shows writable settings with a value, providers always, set secrets only', () {
      final fields = systemFields(_server);
      expect(
        [for (final f in fields) (f.section.label, f.key, f.value, f.secret)],
        [
          ('Chat model', 'LLMProvider', 'generic-openai', false),
          ('Chat model', 'GenericOpenAiKey', '', true),
          ('Chat model', 'GenericOpenAiModelPref', 'glm-5.3-flash', false),
          ('Chat model', 'GenericOpenAiTokenLimit', '128000', false),
          ('Embedder', 'EmbeddingEngine', 'native', false),
          ('Vector database', 'VectorDB', 'lancedb', false),
          (
            'Agent',
            'AgentSearXNGApiUrl',
            'https://search.example/search',
            false,
          ),
          ('Agent', 'AgentSkillRerankerEnabled', 'true', false),
          ('Image generation', 'ImageGenerationProvider', '', false),
        ],
      );
      expect(fields.firstWhere((f) => f.key == 'VectorDB').readOnly, isTrue);
      expect(
        fields.firstWhere((f) => f.key == 'EmbeddingEngine').resetsVectors,
        isTrue,
      );
    });

    test('the server\'s password and signing secret are never written', () {
      expect(systemKeys, isNot(contains('AuthToken')));
      expect(systemKeys, isNot(contains('JWTSecret')));
      expect(
        () => parseSystemSettings('{"AuthToken": "x"}', _server),
        throwsA(isA<ApiException>()),
      );
    });

    test('the JSON holds no secret', () {
      final json = jsonDecode(systemText(_server)) as Map<String, dynamic>;
      expect(json.keys, isNot(contains('GenericOpenAiKey')));
      expect(json.keys, isNot(contains('OpenAiKey')));
      expect(json['LLMProvider'], 'generic-openai');
    });
  });

  group('a save', () {
    test(
      'the JSON as shown saves as no change, a provider not set included',
      () {
        expect(_server['ImageGenerationProvider'], isNull);
        expect(parseSystemSettings(systemText(_server), _server), isEmpty);
      },
    );

    test('a null secret, set or not, is left as it is', () {
      expect(
        parseSystemSettings(
          '{"OpenAiKey": null, "GenericOpenAiKey": null}',
          _server,
        ),
        isEmpty,
      );
    });

    test('sends only what changed, as text', () {
      expect(
        parseSystemSettings(
          jsonEncode({
            'LLMProvider': 'generic-openai',
            'GenericOpenAiModelPref': 'glm-5.3',
            'GenericOpenAiTokenLimit': 128000,
            'AgentSkillRerankerEnabled': false,
            'VectorDB': 'lancedb',
          }),
          _server,
        ),
        {
          'GenericOpenAiModelPref': 'glm-5.3',
          'AgentSkillRerankerEnabled': 'false',
        },
      );
    });

    test('sends a secret when one is given, and a new setting', () {
      expect(
        parseSystemSettings(
          '{"GenericOpenAiKey": "sk-new", "OpenAiKey": "", "AnthropicModelPref": "claude"}',
          _server,
        ),
        {'GenericOpenAiKey': 'sk-new', 'AnthropicModelPref': 'claude'},
      );
    });

    test('refuses what the server would drop or reject', () {
      String why(String json) {
        try {
          parseSystemSettings(json, _server);
        } on ApiException catch (e) {
          return e.message;
        }
        return 'no problem';
      }

      expect(why('{"VectorDB": "pgvector"}'), contains('deletes every vector'));
      expect(
        why('{"MadeUpKey": "1"}'),
        'MadeUpKey is not a setting the server takes from the app.',
      );
      expect(
        why('{"LLMProvider": "skynet"}'),
        startsWith('LLMProvider must be one of openai,'),
      );
      expect(
        why('{"GenericOpenAiModelPref": ""}'),
        contains('cannot be emptied'),
      );
      expect(why('{"GenericOpenAiModelPref": "***"}'), contains('asterisks'));
      expect(why('{"LLMProvider": null}'), contains('cannot be emptied'));
      expect(
        why('{"LLMProvider": [1]}'),
        contains('text, a number or true or false'),
      );
      expect(why('[1]'), 'The settings must be one JSON object.');
      expect(why('{'), startsWith('The settings are not valid JSON'));
    });
  });
}
