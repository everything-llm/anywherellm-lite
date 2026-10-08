import 'package:anywherellm/core/outputs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('metricsOf', () {
    test('reads a measured answer, with its cost', () {
      final metrics = metricsOf({
        'prompt_tokens': 219563,
        'completion_tokens': 1642,
        'duration': 73.852,
        'outputTps': 22.23,
        'model': 'deepseek-flash',
        'provider': 'DeepSeekProvider',
        'inputCost': 0.0033,
        'outputCost': 0.0016,
      })!;
      expect(
        metrics.text,
        'deepseek-flash · 1,642 tokens · 22 tok/s · 73.9 s · \$0.0049',
      );
    });

    test('leaves out what is missing', () {
      expect(
        metricsOf({'model': 'glm-5.3', 'duration': 2})!.text,
        'glm-5.3 · 2.0 s',
      );
    });

    test('names each part in the More menu\'s order', () {
      const metrics = AnswerMetrics(
        model: 'glm-5.3',
        tokens: 1642,
        speed: 22.2,
        seconds: 73.852,
        cost: 0.0049,
      );
      expect(metrics.named, [
        ('Model', 'glm-5.3'),
        ('Time', '73.9 s'),
        ('Tokens', '1,642'),
        ('Speed', '22 tok/s'),
        ('Cost', '\$0.0049'),
      ]);
      expect(const AnswerMetrics(tokens: 12).named, [('Tokens', '12')]);
    });

    test('an unmeasured answer has none', () {
      expect(metricsOf({}), isNull);
      expect(metricsOf(null), isNull);
      expect(metricsOf({'model': ' ', 'duration': -1}), isNull);
    });
  });

  test('sizes read in bytes, KB and MB', () {
    expect(
      [sizeText(812), sizeText(14540), sizeText(3250586)],
      ['812 B', '14.2 KB', '3.1 MB'],
    );
  });
}
