import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/services/recipe_page_fetcher.dart';

void main() {
  group('extractRecipePageText', () {
    test('pulls title, description, and visible text from HTML', () {
      const html = '''
<html>
<head>
<title>番茄炒蛋</title>
<meta name="description" content="家常快手菜" />
<script type="application/ld+json">
{"@context":"https://schema.org/","@type":"Recipe","image":"https://i2.chuimg.com/cover.jpg?imageView2/1/w/300/h/200/q/75/format/jpg"}
</script>
</head>
<body>
<script>var x = 1;</script>
<p>鸡蛋 2 个</p>
<p>西红柿 1 个</p>
</body>
</html>
''';

      final text = extractRecipePageText(html);
      expect(text, contains('标题: 番茄炒蛋'));
      expect(text, contains('摘要: 家常快手菜'));
      expect(
        text,
        contains(
          '封面图片: https://i2.chuimg.com/cover.jpg?imageView2/1/w/300/h/200/q/75/format/jpg',
        ),
      );
      expect(text, contains('鸡蛋 2 个'));
      expect(text, isNot(contains('var x')));
    });
  });

  group('RecipePageFetcher.fetchText', () {
    test(
      'retries once when the first response is a human check page',
      () async {
        var calls = 0;
        final client = MockClient((request) async {
          calls += 1;
          if (calls == 1) {
            return http.Response(
              '<html><body id="humancheck_captcha">verify</body></html>',
              200,
              request: request,
            );
          }
          return http.Response(
            '''
<html>
<head><title>Tomato Eggs</title></head>
<body><p>Eggs 2</p><p>Tomato 1</p></body>
</html>
''',
            200,
            request: request,
          );
        });

        final text = await RecipePageFetcher.fetchText(
          'https://lanfanapp.com/recipe/15978',
          client: client,
          humanCheckRetryDelay: Duration.zero,
        );

        expect(calls, 2);
        expect(text, contains('Tomato Eggs'));
        expect(text, contains('Eggs 2'));
      },
    );
  });
}
