import 'package:anywherellm/core/providers.dart';
import 'package:anywherellm/core/system_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every setting a provider reads is one the server takes', () {
    for (final setting in providerSettings) {
      for (final provider in setting.providers) {
        for (final key in provider.keys) {
          expect(systemKeys, contains(key), reason: '${setting.chooser} $key');
        }
        expect(
          provider.keys.toSet().length,
          provider.keys.length,
          reason: '${setting.chooser} ${provider.value} lists a key twice',
        );
      }
    }
  });

  test('every value the server takes has a name and its settings', () {
    for (final setting in providerSettings) {
      for (final value in systemChoices[setting.chooser] ?? const <String>[]) {
        expect(
          setting.named(value),
          isNotNull,
          reason: '${setting.chooser} $value',
        );
      }
    }
  });

  test('the chat model of each provider is among its settings', () {
    for (final MapEntry(:key, :value) in chatModelKeys.entries) {
      expect(chatProviders.named(key)!.keys, contains(value), reason: key);
    }
  });

  test('every setting has a label of its own', () {
    for (final setting in providerSettings) {
      for (final provider in setting.providers) {
        for (final field in provider.fields) {
          expect(field.label, isNot(field.key), reason: field.key);
        }
      }
    }
  });

  test('keys and passwords are secret, limits are numbers', () {
    expect(ProviderField('OpenAiKey').kind, FieldKind.secret);
    expect(ProviderField('PGVectorConnectionString').kind, FieldKind.secret);
    expect(ProviderField('OllamaLLMAuthToken').kind, FieldKind.secret);
    expect(ProviderField('OllamaLLMTokenLimit').kind, FieldKind.number);
    expect(ProviderField('OllamaLLMBasePath').kind, FieldKind.text);
    expect(ProviderField('AzureOpenAiModelPref').label, 'Chat deployment name');
  });

  test('a provider the app does not know still shows by its value', () {
    expect(chatProviders.labelOf('ollama'), 'Ollama');
    expect(chatProviders.labelOf('brand-new'), 'brand-new');
    expect(chatProviders.labelOf(''), 'None');
    expect(chatProviders.choices('brand-new').last, 'brand-new');
    expect(chatProviders.choices('ollama'), systemChoices['LLMProvider']);
    expect(vectorProviders.choices('lancedb'), contains('pgvector'));
  });
}
