import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'providers/navigation_provider.dart';
import 'providers/ai_draft_provider.dart';
import 'screens/custom_recipe_form_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/add_ingredient_screen.dart';
import 'screens/recipes_screen.dart';
import 'screens/shopping_list_screen.dart';
import 'providers/notification_sync_provider.dart';
import 'services/share_intent_service.dart';
import 'widgets/common/top_app_bar.dart';
import 'widgets/common/bottom_nav_bar.dart';
import 'widgets/common/search_overlay.dart';

String _localizedTitle(BuildContext context) {
  final locale = Localizations.localeOf(context);
  return locale.languageCode == 'zh' ? '食材管家' : 'Fresh Pantry';
}

class FreshPantryApp extends StatelessWidget {
  const FreshPantryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kAppSystemOverlayStyle,
      child: MaterialApp(
        onGenerateTitle: _localizedTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  // Order MUST match FkTab constants in navigation_provider.dart.
  static const _screens = [
    DashboardScreen(),
    InventoryScreen(),
    AddIngredientScreen(),
    RecipesScreen(),
    ShoppingListScreen(),
  ];

  StreamSubscription<String>? _shareTextSubscription;

  @override
  void initState() {
    super.initState();
    final source = ref.read(systemShareSourceProvider);
    source.consumeInitialText().then(_handleSharedText);
    _shareTextSubscription = source.incomingTextStream.listen(
      _handleSharedText,
    );
  }

  void _handleSharedText(String? text) {
    if (text == null || text.isEmpty || !mounted) return;
    final url = extractUrl(text);
    if (url == null) return;
    ref.read(navigationProvider.notifier).state = 0;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomRecipeFormScreen(prefilledUrl: url),
      ),
    );
  }

  @override
  void dispose() {
    _shareTextSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationSyncProvider);
    final currentIndex = ref.watch(navigationProvider);
    final isSearchActive = ref.watch(searchActiveProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const TopAppBar(),
                Expanded(
                  child: IndexedStack(index: currentIndex, children: _screens),
                ),
              ],
            ),
            if (isSearchActive) const SearchOverlay(),
          ],
        ),
      ),
      extendBody: true,
      bottomNavigationBar: const BottomNavBar(),
    );
  }
}
