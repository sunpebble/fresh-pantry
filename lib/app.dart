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
import 'screens/shopping_list_screen.dart';
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

  static const _systemUiOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _systemUiOverlayStyle,
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
  static const _screens = [
    DashboardScreen(),
    InventoryScreen(),
    AddIngredientScreen(),
    ShoppingListScreen(),
  ];

  @override
  void initState() {
    super.initState();
    final source = ref.read(systemShareSourceProvider);
    source.consumeInitialText().then(_handleSharedText);
    source.incomingTextStream.listen(_handleSharedText);
  }

  void _handleSharedText(String? text) {
    if (text == null || text.isEmpty || !mounted) return;
    final url = extractUrl(text);
    if (url == null) return;
    ref.read(navigationProvider.notifier).state = 0;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CustomRecipeFormScreen(prefilledUrl: url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(navigationProvider);

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
            // Search overlay on top
            const SearchOverlay(),
          ],
        ),
      ),
      extendBody: true,
      bottomNavigationBar: const BottomNavBar(),
    );
  }
}
