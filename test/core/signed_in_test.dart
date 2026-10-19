import 'package:anywherellm/core/signed_in.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? of(String link) => signedInOf(link);

  test('a signed-in link names its service', () {
    expect(of('anywherellm://signed-in?service=github'), 'github');
    expect(of('anywherellm://signed-in?service=me%40work'), 'me@work');
    expect(
      of('anywherellm://signed-in?service=Google%20Calendar'),
      'Google Calendar',
    );
  });

  test('never another link, no service, or one that is not a short label', () {
    expect(of('anywherellm://connect?service=github'), isNull);
    expect(of('https://signed-in?service=github'), isNull);
    expect(of('anywherellm://signed-in'), isNull);
    expect(of('anywherellm://signed-in?service=%20'), isNull);
    expect(of('anywherellm://signed-in?service=${'a' * 61}'), isNull);
    expect(of('anywherellm://signed-in?service=a%0Ab'), isNull);
    expect(of('anywherellm://signed-in?service=%3Cb%3E'), isNull);
  });
}
