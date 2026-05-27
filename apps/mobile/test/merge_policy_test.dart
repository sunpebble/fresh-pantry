import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/sync/merge_policy.dart';

void main() {
  test('mergePatch applies local patch when versions match', () {
    final result = mergeRemotePatch(
      local: const {'name': 'Milk', 'quantity': '1'},
      remote: const {'name': 'Milk', 'quantity': '1'},
      patch: const {'quantity': '2'},
      baseVersion: 1,
      remoteVersion: 1,
    );

    expect(result.value['quantity'], '2');
    expect(result.conflict, isFalse);
  });

  test('mergePatch merges different changed fields', () {
    final result = mergeRemotePatch(
      local: const {'name': 'Milk', 'quantity': '1', 'category': 'Dairy'},
      remote: const {'name': 'Milk', 'quantity': '1', 'category': 'Cold'},
      patch: const {'quantity': '3'},
      baseVersion: 1,
      remoteVersion: 2,
    );

    expect(result.value['quantity'], '3');
    expect(result.value['category'], 'Cold');
    expect(result.conflict, isFalse);
  });

  test('mergePatch records conflict for same-field edits', () {
    final result = mergeRemotePatch(
      local: const {'name': 'Milk', 'quantity': '2'},
      remote: const {'name': 'Milk', 'quantity': '3'},
      patch: const {'quantity': '4'},
      baseVersion: 1,
      remoteVersion: 2,
    );

    expect(result.value['quantity'], '4');
    expect(result.conflict, isTrue);
    expect(result.conflictFields, ['quantity']);
  });

  test('mergePatch compares nested JSON values by content', () {
    final result = mergeRemotePatch(
      local: {
        'name': 'Soup',
        'steps': ['Prep'],
      },
      remote: {
        'name': 'Soup',
        'steps': ['Prep'],
      },
      patch: {
        'steps': ['Prep', 'Cook'],
      },
      baseVersion: 1,
      remoteVersion: 2,
    );

    expect(result.value['steps'], ['Prep', 'Cook']);
    expect(result.conflict, isFalse);
  });

  test('mergePatch returns detached immutable merge results', () {
    final remoteSteps = ['Prep'];
    final patchSteps = ['Prep', 'Cook'];
    final result = mergeRemotePatch(
      local: const {'steps': []},
      remote: {'steps': remoteSteps},
      patch: {'steps': patchSteps},
      baseVersion: 1,
      remoteVersion: 2,
    );

    patchSteps.add('Serve');
    remoteSteps.add('Plate');

    expect(result.value['steps'], ['Prep', 'Cook']);
    expect(
      () => (result.value['steps'] as List).add('Serve'),
      throwsUnsupportedError,
    );
    expect(() => result.value['name'] = 'Soup', throwsUnsupportedError);
  });

  test('mergePatch returns immutable conflict fields', () {
    final result = mergeRemotePatch(
      local: const {'quantity': '2'},
      remote: const {'quantity': '3'},
      patch: const {'quantity': '4'},
      baseVersion: 1,
      remoteVersion: 2,
    );

    expect(result.conflictFields, ['quantity']);
    expect(() => result.conflictFields.add('name'), throwsUnsupportedError);
  });
}
