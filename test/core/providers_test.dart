import 'package:anywherellm/core/providers.dart';
import 'package:anywherellm/core/system_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every chat provider the server takes has a name', () {
    for (final value in systemChoices['LLMProvider']!) {
      expect(chatProviders.named(value), isNotNull, reason: value);
    }
  });

  test('a provider the app does not know still shows by its value', () {
    expect(chatProviders.labelOf('ollama'), 'Ollama');
    expect(chatProviders.labelOf('brand-new'), 'brand-new');
    expect(chatProviders.labelOf(''), 'None');
    expect(chatProviders.choices('brand-new').last, 'brand-new');
    expect(
      chatProviders.choices('ollama'),
      unorderedEquals(systemChoices['LLMProvider']!),
    );
    expect(vectorProviders.choices('lancedb'), contains('pgvector'));
  });

  test('a chooser offers its values in the order the app lists them', () {
    expect(chatProviders.choices('ollama').first, 'generic-openai');
    expect(transcriptionProviders.choices('local'), [
      'local',
      'openai',
      'generic-openai',
    ]);
  });

  test('privacy says where the chat model answers', () {
    expect(
      chatModelPrivacy({
        'LLMProvider': 'generic-openai',
        'GenericOpenAiBasePath': 'https://api.z.ai/api/coding/paas/v4',
      }),
      'Generic OpenAI at api.z.ai. Shared under that service\'s terms.',
    );
    expect(
      chatModelPrivacy({
        'LLMProvider': 'ollama',
        'OllamaLLMBasePath': 'http://host.docker.internal:11434',
      }),
      'Ollama at host.docker.internal:11434. Runs on the server.',
    );
    expect(
      chatModelPrivacy({
        'LLMProvider': 'lmstudio',
        'LMStudioBasePath': 'http://192.168.1.20:1234/v1',
      }),
      'LM Studio at 192.168.1.20:1234. Questions go to that machine.',
    );
    expect(
      chatModelPrivacy({'LLMProvider': 'anthropic'}),
      'Anthropic. Shared under that service\'s terms.',
    );
  });

  test('privacy says where documents are prepared and kept', () {
    expect(
      searchModelPrivacy({'EmbeddingEngine': 'native'}),
      'AnythingLLM Embedder. Runs on the server.',
    );
    expect(
      searchModelPrivacy({'EmbeddingEngine': 'openai'}),
      'OpenAI. Your documents\' text goes to it to be prepared.',
    );
    expect(
      storagePrivacy({'VectorDB': 'lancedb'}),
      'LanceDB. Passages and text stay on the server.',
    );
    expect(
      storagePrivacy({'VectorDB': 'pinecone'}),
      'Pinecone. Passages and their text are kept there.',
    );
  });
}
