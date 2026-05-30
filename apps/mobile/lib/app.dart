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
import 'screens/auth_gate_screen.dart';
import 'screens/recipes_screen.dart';
import 'screens/shopping_list_screen.dart';
import 'providers/notification_sync_provider.dart';
import 'services/share_intent_service.dart';
import 'household/invite_token.dart';
import 'sync/household_content_sync.dart';
import 'sync/sync_flush_coordinator.dart';
import 'widgets/common/bottom_nav_bar.dart';
import 'widgets/common/search_overlay.dart';
import 'widgets/common/sync_status_banner.dart';

String _localizedTitle(BuildContext context) {
  final locale = Localizations.localeOf(context);
  return locale.languageCode == 'zh' ? '食材管家' : 'Fresh Pantry';
}

bool _isRootAuthCallbackRoute(String? routeName) {
  if (routeName == null) return false;

  final uri = Uri.tryParse(routeName);
  if (uri == null) return false;

  final isRootPath = uri.path.isEmpty || uri.path == '/';
  return isRootPath && (uri.hasQuery || uri.hasFragment);
}

class FreshPantryApp extends StatelessWidget {
  const FreshPantryApp({super.key, this.home});

  final Widget? home;

  Widget _buildHome({String? initialInviteToken}) {
    return home ??
        AuthGateScreen(
          authenticatedChild: const AppShell(),
          initialInviteToken: initialInviteToken,
        );
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    final inviteToken = settings.name == null
        ? null
        : inviteTokenFromInput(settings.name!);
    if (inviteToken != null) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => _buildHome(initialInviteToken: inviteToken),
      );
    }

    if (!_isRootAuthCallbackRoute(settings.name)) return null;

    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => _buildHome(),
    );
  }

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
        home: _buildHome(),
        onGenerateRoute: _generateRoute,
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
    final isHome = currentIndex == FkTab.home;

    // SafeArea 常驻树中、仅切换 top,避免 home/非 home 间结构变动重建 IndexedStack
    // (会丢子页面 State 并反复重启 sync 订阅)。首页 top: false → hero(含其内部
    // Header)自己铺到物理顶并让出状态栏。
    final pages = SyncFlushCoordinator(
      child: HouseholdContentSync(
        child: SafeArea(
          top: !isHome,
          bottom: false,
          child: IndexedStack(index: currentIndex, children: _screens),
        ),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 首页状态栏后面始终是不透明蓝色 scrim(见下),故图标固定浅色。
      value: isHome ? kHeroSystemOverlayStyle : kAppSystemOverlayStyle,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              Positioned.fill(child: pages),
              if (isHome)
                // 状态栏专用不透明蓝色 scrim — 让首页状态栏像其他页面一样有稳定
                // 背景(不透出滚动中的 hero 渐变/装饰),图标也始终清晰。
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.paddingOf(context).top,
                  child: const ColoredBox(color: AppColors.primary),
                ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SyncStatusBanner(),
              ),
              if (isSearchActive) const SearchOverlay(),
            ],
          ),
        ),
        extendBody: true,
        bottomNavigationBar: const BottomNavBar(),
      ),
    );
  }
}
