import 'package:anywherellm/core/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a provider the app does not know still shows by its value', () {
    expect(chatProviders.labelOf('ollama'), 'Ollama');
    expect(chatProviders.labelOf('brand-new'), 'brand-new');
    expect(chatProviders.labelOf(''), 'None');
    expect(vectorProviders.labelOf('pgvector'), 'PGVector');
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

  test('privacy shows the host and port of an address, never a login', () {
    String at(String address) => chatModelPrivacy({
      'LLMProvider': 'ollama',
      'OllamaLLMBasePath': address,
    });
    expect(
      at('http://user:pass@192.168.1.5:11434/v1'),
      'Ollama at 192.168.1.5:11434. Questions go to that machine.',
    );
    expect(
      at('https://u:p@api.example.com/v1'),
      'Ollama at api.example.com. Shared under that service\'s terms.',
    );
    expect(
      at('http://[fd00::5]:11434'),
      'Ollama at [fd00::5]:11434. Questions go to that machine.',
    );
  });

  test('privacy reads an address written without its scheme', () {
    String at(String address) => chatModelPrivacy({
      'LLMProvider': 'ollama',
      'OllamaLLMBasePath': address,
    });
    expect(
      at('192.168.1.5:11434'),
      'Ollama at 192.168.1.5:11434. Questions go to that machine.',
    );
    expect(
      at('localhost:11434/v1'),
      'Ollama at localhost:11434. Runs on the server.',
    );
    expect(
      at('api.example.com/v1'),
      'Ollama at api.example.com. Shared under that service\'s terms.',
    );
  });

  test('privacy reads a private address by the rule the key follows', () {
    String at(String host) => chatModelPrivacy({
      'LLMProvider': 'ollama',
      'OllamaLLMBasePath': 'http://$host:11434',
    });
    for (final home in ['nas', 'box.local', '169.254.1.2', '[fd00::5]']) {
      expect(at(home), endsWith('Questions go to that machine.'), reason: home);
    }
    for (final away in ['10.1', '10.evil.com', '134744072']) {
      expect(
        at(away),
        endsWith('Shared under that service\'s terms.'),
        reason: away,
      );
    }
    expect(at('127.0.0.1'), endsWith('Runs on the server.'));
    expect(at('ollama.internal'), endsWith('Questions go to that machine.'));
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
