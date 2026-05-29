import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../household/household_models.dart';
import '../household/household_session_controller.dart';
import '../household/invite_token.dart';
import '../providers/invite_link_provider.dart';
import '../sync/sync_providers.dart';
import '../theme/app_theme.dart';

/// The active household for the signed-in session: the explicit selection when
/// it still resolves to a joined household, otherwise the first household, or
/// empty when the user has none (local-only).
String selectedHouseholdIdForSession(HouseholdSessionState session) {
  if (session.households.isEmpty) return '';
  final selected = session.selectedHouseholdId;
  final isJoined =
      selected.isNotEmpty &&
      session.households.any((household) => household.id == selected);
  return isJoined ? selected : session.households.first.id;
}

class AuthGateScreen extends ConsumerStatefulWidget {
  const AuthGateScreen({
    super.key,
    required this.authenticatedChild,
    this.initialInviteToken,
  });

  final Widget authenticatedChild;
  final String? initialInviteToken;

  @override
  ConsumerState<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends ConsumerState<AuthGateScreen> {
  final _emailController = TextEditingController();
  final _householdNameController = TextEditingController(text: '我的家庭');
  final _inviteController = TextEditingController();
  String? _pendingInviteToken;
  String? _inviteInputError;
  String? _lastPreviewToken;
  String? _emailError;
  final _dismissedInviteIds = <String>{};
  StreamSubscription<String>? _inviteLinkSubscription;

  @override
  void initState() {
    super.initState();
    final initialInviteToken = widget.initialInviteToken;
    if (initialInviteToken != null) {
      _pendingInviteToken = inviteTokenFromInput(initialInviteToken);
      if (_pendingInviteToken != null) {
        _inviteController.text = initialInviteToken;
      }
    }
    Future.microtask(() {
      if (!mounted) return;
      ref.read(householdSessionControllerProvider.notifier).refreshHouseholds();
    });
    _listenForInviteLinks();
  }

  @override
  void dispose() {
    _inviteLinkSubscription?.cancel();
    _emailController.dispose();
    _householdNameController.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(householdSessionControllerProvider);

    // Project the session's active household into the root-container backing so
    // the root-stored notifiers (inventory/shopping/recipes) enqueue against the
    // right household. Done from a listener (runs outside build) rather than a
    // nested ProviderScope override, which can never reach those root providers.
    ref.listen<String>(
      householdSessionControllerProvider.select(selectedHouseholdIdForSession),
      (_, householdId) {
        ref.read(selectedHouseholdIdStateProvider.notifier).state = householdId;
      },
    );

    final pendingInviteToken = _pendingInviteToken;

    if (pendingInviteToken != null && session.isAuthenticated) {
      _ensureInvitePreviewLoaded(pendingInviteToken);
      return _buildInvitePreview(context, session, pendingInviteToken);
    }

    final pendingInviteReminder = _firstPendingInviteReminder(session);
    if (!session.isLoading &&
        session.isAuthenticated &&
        pendingInviteReminder != null) {
      return _buildPendingInviteReminder(
        context,
        session,
        pendingInviteReminder,
      );
    }

    if (session.households.isNotEmpty) {
      // The active household reaches the notifiers via the root-container
      // projection above, so the child renders in the same (root) scope.
      return widget.authenticatedChild;
    }

    if (session.isLoading) {
      return _buildStartupScreen(context);
    }

    if (session.isAuthenticated) {
      return _buildHouseholdBootstrap(context, session);
    }

    return _buildLoginForm(context, session);
  }

  Widget _buildStartupScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Fresh Pantry',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context, HouseholdSessionState session) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '登录 Fresh Pantry',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    TextField(
                      controller: _emailController,
                      enabled: !session.isSubmitting,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: '邮箱',
                        errorText: _emailError,
                      ),
                      onChanged: (_) {
                        if (_emailError != null) {
                          setState(() => _emailError = null);
                        }
                      },
                      onSubmitted: (_) => _sendOtp(),
                    ),
                    if (session.error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _ErrorText(session.error!),
                    ],
                    if (session.error == null &&
                        session.sentOtpToEmail.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      _OtpSentText(email: session.sentOtpToEmail),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton.icon(
                      onPressed: session.isSubmitting ? null : _sendOtp,
                      icon: session.isSubmitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.mail_outline),
                      label: Text(session.isSubmitting ? '发送中...' : '发送登录链接'),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    _InviteInputSection(
                      controller: _inviteController,
                      error: _inviteInputError,
                      pendingToken: _pendingInviteToken,
                      enabled: !session.isSubmitting,
                      buttonLabel: '保存邀请',
                      onSubmit: _saveInviteInput,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHouseholdBootstrap(
    BuildContext context,
    HouseholdSessionState session,
  ) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '创建家庭配置',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '首次登录后需要创建一个家庭，之后可以在设置里邀请家人加入。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  TextField(
                    controller: _householdNameController,
                    enabled: !session.isSubmitting,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: '家庭名称'),
                    onSubmitted: (_) => _createHousehold(),
                  ),
                  if (session.error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ErrorText(session.error!),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: session.isSubmitting ? null : _createHousehold,
                    icon: session.isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.home_outlined),
                    label: Text(session.isSubmitting ? '创建中...' : '创建家庭'),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _InviteInputSection(
                    controller: _inviteController,
                    error: _inviteInputError,
                    pendingToken: _pendingInviteToken,
                    enabled: !session.isSubmitting,
                    buttonLabel: '查看邀请',
                    onSubmit: _saveInviteInput,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInvitePreview(
    BuildContext context,
    HouseholdSessionState session,
    String token,
  ) {
    final preview = session.invitePreview;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '家庭邀请',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (session.isPreviewLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (preview != null)
                    _InvitePreviewCard(preview: preview)
                  else if (session.error != null)
                    _ErrorText(session.error!)
                  else
                    const SizedBox.shrink(),
                  if (preview != null && session.error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ErrorText(session.error!),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed:
                        session.isSubmitting ||
                            session.isPreviewLoading ||
                            preview == null
                        ? null
                        : () => _acceptInvite(token),
                    icon: session.isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.group_add_outlined),
                    label: Text(session.isSubmitting ? '接受中...' : '接受邀请'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: session.isSubmitting
                        ? null
                        : () {
                            setState(() {
                              _pendingInviteToken = null;
                              _lastPreviewToken = null;
                              _inviteInputError = null;
                            });
                          },
                    child: const Text('输入其他邀请'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingInviteReminder(
    BuildContext context,
    HouseholdSessionState session,
    HouseholdInvitePreview preview,
  ) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '收到家庭邀请',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _InvitePreviewCard(preview: preview),
                  if (session.error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ErrorText(session.error!),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: session.isSubmitting
                        ? null
                        : () => _acceptPendingInvite(preview),
                    icon: session.isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.group_add_outlined),
                    label: Text(session.isSubmitting ? '接受中...' : '接受邀请'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: session.isSubmitting
                        ? null
                        : () {
                            setState(() {
                              _dismissedInviteIds.add(preview.inviteId);
                            });
                          },
                    child: const Text('稍后处理'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _sendOtp() {
    final email = _emailController.text.trim();
    if (email.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _emailError = '请输入有效的邮箱地址');
      return;
    }
    setState(() => _emailError = null);
    ref.read(householdSessionControllerProvider.notifier).sendOtp(email);
  }

  void _createHousehold() {
    ref
        .read(householdSessionControllerProvider.notifier)
        .createHousehold(_householdNameController.text);
  }

  void _saveInviteInput() {
    final token = inviteTokenFromInput(_inviteController.text);
    if (token == null) {
      setState(() {
        _inviteInputError = '请输入有效的邀请链接或邀请码';
      });
      return;
    }

    setState(() {
      _pendingInviteToken = token;
      _lastPreviewToken = null;
      _inviteInputError = null;
    });
  }

  void _listenForInviteLinks() {
    final source = ref.read(inviteLinkSourceProvider);
    unawaited(
      source
          .consumeInitialLink()
          .then(_handleIncomingInviteLink)
          .catchError(_reportInviteLinkError),
    );
    _inviteLinkSubscription = source.incomingLinks.listen(
      _handleIncomingInviteLink,
      onError: _reportInviteLinkError,
    );
  }

  void _reportInviteLinkError(Object error, [StackTrace? stackTrace]) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'fresh_pantry',
        context: ErrorDescription('while handling an invite deep link'),
      ),
    );
  }

  void _handleIncomingInviteLink(String? link) {
    if (link == null || link.isEmpty || !mounted) return;
    final token = inviteTokenFromInput(link);
    if (token == null) return;
    setState(() {
      _pendingInviteToken = token;
      _lastPreviewToken = null;
      _inviteInputError = null;
      _inviteController.text = link;
    });
  }

  void _ensureInvitePreviewLoaded(String token) {
    if (_lastPreviewToken == token) return;
    _lastPreviewToken = token;
    Future.microtask(() {
      if (!mounted) return;
      unawaited(_loadInvitePreview(token));
    });
  }

  Future<void> _loadInvitePreview(String token) async {
    try {
      await ref
          .read(householdSessionControllerProvider.notifier)
          .previewInvite(token);
    } catch (_) {
      // The controller stores the visible error in state.
    }
  }

  Future<void> _acceptInvite(String token) async {
    await ref
        .read(householdSessionControllerProvider.notifier)
        .acceptInvite(token);
    if (!mounted) return;
    final session = ref.read(householdSessionControllerProvider);
    if (session.error != null) return;
    setState(() {
      _pendingInviteToken = null;
      _lastPreviewToken = null;
      _inviteInputError = null;
    });
  }

  Future<void> _acceptPendingInvite(HouseholdInvitePreview preview) async {
    await ref
        .read(householdSessionControllerProvider.notifier)
        .acceptInviteById(preview.inviteId);
  }

  HouseholdInvitePreview? _firstPendingInviteReminder(
    HouseholdSessionState session,
  ) {
    for (final invite in session.pendingInvitePreviews) {
      if (invite.inviteId.isEmpty) continue;
      if (_dismissedInviteIds.contains(invite.inviteId)) continue;
      return invite;
    }
    return null;
  }
}

class _InviteInputSection extends StatelessWidget {
  const _InviteInputSection({
    required this.controller,
    required this.error,
    required this.pendingToken,
    required this.enabled,
    required this.buttonLabel,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? error;
  final String? pendingToken;
  final bool enabled;
  final String buttonLabel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '加入已有家庭',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              enabled: enabled,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: '邀请链接或邀请码',
                errorText: error,
              ),
              onSubmitted: (_) => onSubmit(),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: enabled ? onSubmit : null,
              child: Text(buttonLabel),
            ),
            if (pendingToken != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '已保存邀请，登录后可查看家庭概览',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InvitePreviewCard extends StatelessWidget {
  const _InvitePreviewCard({required this.preview});

  final HouseholdInvitePreview preview;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preview.householdName,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              preview.ownerEmail,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            if (preview.invitedEmail.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                '邀请邮箱：${preview.invitedEmail}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _InviteMetric('${preview.memberCount} 位成员'),
                _InviteMetric('${preview.inventoryCount} 个食材'),
                _InviteMetric('${preview.shoppingCount} 个采购'),
                _InviteMetric('${preview.customRecipeCount} 个菜谱'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteMetric extends StatelessWidget {
  const _InviteMetric(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

class _OtpSentText extends StatelessWidget {
  const _OtpSentText({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          color: AppColors.primaryContainer,
          size: 18,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            '登录链接已发送至 $email，请查收邮件',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.primaryContainer),
          ),
        ),
      ],
    );
  }
}
