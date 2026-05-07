import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';

void main() {
  group('DraftField', () {
    test('ai factory marks source ai', () {
      final f = DraftField<String>.ai('番茄');
      expect(f.value, '番茄');
      expect(f.source, DraftSource.ai);
    });

    test('user factory marks source user', () {
      final f = DraftField<int>.user(3);
      expect(f.source, DraftSource.user);
    });

    test('editedTo replaces value and flips source to user', () {
      final original = DraftField<String>.ai('番茄');
      final edited = original.editedTo('西红柿');
      expect(edited.value, '西红柿');
      expect(edited.source, DraftSource.user);
      expect(original.source, DraftSource.ai); // immutable
    });

    test('equality compares value + source', () {
      expect(DraftField<int>.ai(1), DraftField<int>.ai(1));
      expect(DraftField<int>.ai(1) == DraftField<int>.user(1), false);
    });
  });
}
