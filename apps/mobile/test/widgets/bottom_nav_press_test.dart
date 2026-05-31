import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/common/bottom_nav_bar.dart';
import 'package:fresh_pantry/widgets/shared/fk_pressable.dart';

void main() {
  testWidgets('nav items use FkAnimatedPressable', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(bottomNavigationBar: const BottomNavBar()),
        ),
      ),
    );
    expect(find.byType(FkAnimatedPressable), findsWidgets);
  });
}
