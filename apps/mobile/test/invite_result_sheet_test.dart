import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/settings/invite_result_sheet.dart';

void main() {
  testWidgets('InviteResultSheet shows invite URL and email', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => InviteResultSheet.show(
                context,
                inviteUrl: 'https://api.fresh-pantry.kunish.eu.org/invite/abc123',
                invitedEmail: 'friend@example.com',
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('邀请已创建'), findsOneWidget);
    expect(find.text('friend@example.com'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    expect(find.text('分享到...'), findsOneWidget);
  });

  testWidgets('InviteResultSheet copy button closes sheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => InviteResultSheet.show(
                context,
                inviteUrl: 'https://example.com/invite/test',
                invitedEmail: 'test@example.com',
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('邀请已创建'), findsOneWidget);

    await tester.tap(find.text('复制链接'));
    await tester.pumpAndSettle();

    expect(find.text('邀请已创建'), findsNothing);
  });
}
