import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/staff_user.dart';
import '../../state/pos_controller.dart';
import 'pos_screen.dart';

class LoginScreen extends StatefulWidget {
  final PosController controller;

  const LoginScreen({super.key, required this.controller});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  String? _errorMessage;
  bool _isLoading = false;
  bool _mustChangePassword = false;
  bool _isNewLogin = false;
  bool _obscurePassword = true;
  bool _obscureNewPassword = true;
  late final AnimationController _launchController;
  late final AnimationController _successController;
  bool _isNavigatingToDashboard = false;

  @override
  void initState() {
    super.initState();
    _launchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted && !_mustChangePassword) {
          _emailFocusNode.requestFocus();
        }
      })
      ..forward();
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    // Pull latest staff accounts, menu, and inventory from Admin on login screen load
    widget.controller.syncService.syncAll();
  }

  @override
  void reassemble() {
    super.reassemble();
    // Ensure Hot Reload immediately syncs with Supabase
    _errorMessage = null;
    widget.controller.syncService.syncAll();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _newPasswordController.dispose();
    _emailFocusNode.dispose();
    _launchController.dispose();
    _successController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim().toLowerCase();
    final username = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final newPassword = _newPasswordController.text;

    if (email.isEmpty || password.isEmpty || (_isNewLogin && username.isEmpty)) {
      setState(() => _errorMessage = _isNewLogin
          ? 'Please enter your Owner email, username, and password'
          : 'Please enter your Owner email and password');
      return;
    }
    if (_mustChangePassword && newPassword.length < 8) {
      setState(() => _errorMessage = 'Your new password must be at least 8 characters');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final cachedStaffProfile =
        widget.controller.localStorage.getActiveStaffProfile();
    final cachedPosApiToken = widget.controller.localStorage.getPosApiToken();
    widget.controller.supabaseService.setPosApiToken(null);

    StaffUser? authenticatedStaff;

    // 1. Authenticate through the POS API without persisting a token yet.
    final authRes = _mustChangePassword
        ? await widget.controller.supabaseService.changeCashierPassword(
            email: email,
            password: password,
            newPassword: newPassword,
          )
        : _isNewLogin
            ? await widget.controller.supabaseService.authenticateNewOwner(
                email: email,
                username: username,
                password: password,
                persistSessionToken: false,
              )
            : await widget.controller.supabaseService.authenticateStaff(
                '',
                password,
                email: email,
                persistSessionToken: false,
              );
    if (authRes['requiresPasswordChange'] == true) {
      setState(() {
        _isLoading = false;
        _mustChangePassword = true;
        _errorMessage = null;
      });
      return;
    }
    if (authRes['ok'] == true && authRes['user'] is StaffUser) {
      authenticatedStaff = authRes['user'] as StaffUser;
    } else if (authRes['offline'] == true && !_isNewLogin) {
      authenticatedStaff = await widget.controller
          .authenticateCachedStaffOffline(email: email, password: password);
      if (authenticatedStaff != null &&
          ((authenticatedStaff.email.trim().toLowerCase() != email &&
                  authenticatedStaff.username.trim().toLowerCase() != email) ||
              !authenticatedStaff.passwordChanged)) {
        authenticatedStaff = null;
        setState(() => _errorMessage = 'Connect to the internet to verify this Owner account.');
      }
    }

    if (authenticatedStaff == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = authRes['offline'] == true &&
                widget.controller.syncService.isOnline
            ? 'Unable to verify credentials. Please try again.'
            : _errorMessage ?? authRes['error']?.toString() ?? 'Invalid Owner credentials';
      });
      return;
    }

    if (!authenticatedStaff.canLoginToPos) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'This account cannot log in to the POS app.';
      });
      return;
    }

    if (authRes['ok'] == true) {
      await widget.controller.localStorage
          .saveOfflineStaffCredential(authenticatedStaff.id, _mustChangePassword ? newPassword : password);
    }

    final authenticatedToken = authRes['token']?.toString();
    final canReuseCachedToken = cachedStaffProfile?.id == authenticatedStaff.id;
    final posApiToken =
        authenticatedToken != null && authenticatedToken.isNotEmpty
            ? authenticatedToken
            : canReuseCachedToken
                ? cachedPosApiToken
                : null;

    await widget.controller.localStorage.clearActiveStaffId();
    await widget.controller.localStorage.saveActiveStaffSession(
      authenticatedStaff,
      posApiToken: posApiToken,
    );
    widget.controller.supabaseService.setPosApiToken(posApiToken);
    if (authenticatedToken != null && authenticatedToken.isNotEmpty) {
      await widget.controller.syncService.syncAll();
      await widget.controller.init();
    }
    widget.controller.currentUser = authenticatedStaff;
    widget.controller.isPosOpen = true;
    await widget.controller
        .recordStaffSessionEvent(authenticatedStaff, 'login');

    if (mounted) {
      setState(() {
        _isLoading = false;
        _mustChangePassword = false;
        _isNavigatingToDashboard = true;
      });
      await _successController.forward();
      if (!mounted) return;
      Navigator.pushReplacement<void, void>(
        context,
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) =>
              PosScreen(controller: widget.controller),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final reveal = CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutExpo,
            );
            return AnimatedBuilder(
              animation: reveal,
              child: child,
              builder: (context, child) => ClipPath(
                clipper: _CurtainRevealClipper(progress: reveal.value),
                child: child,
              ),
            );
          },
        ),
      );
    }
  }

  Future<void> _selectLoginMode(bool isNewLogin) async {
    if (_isNewLogin == isNewLogin || _isLoading || _mustChangePassword) return;
    setState(() {
      _isNewLogin = isNewLogin;
      _emailController.clear();
      _usernameController.clear();
      _passwordController.clear();
      _errorMessage = null;
    });
    if (isNewLogin) {
      await widget.controller.clearActiveSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF1B294A);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = MediaQuery.sizeOf(context).height < 780;
    final double logoSize = (screenWidth * 0.28).clamp(112.0, 156.0).toDouble();
    final verticalGap = compact ? 12.0 : 16.0;

    return AnimatedBuilder(
      animation: _launchController,
      builder: (context, _) {
        final progress = _launchController.value;
        final reveal = Curves.easeInOut.transform(
          ((progress - 0.46) / 0.54).clamp(0.0, 1.0).toDouble(),
        );
        final logoOpacity = Curves.easeOut.transform(
          (progress / 0.29).clamp(0.0, 1.0).toDouble(),
        ) * (1 - Curves.easeIn.transform(
          ((progress - 0.70) / 0.12).clamp(0.0, 1.0).toDouble(),
        ));
        final barProgress = Curves.easeInOut.transform(
          ((progress - 0.35) / 0.35).clamp(0.0, 1.0).toDouble(),
        );
        final statusReady = progress >= 0.62;
        final blur = (1 - reveal) * 10;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarColor: Color.lerp(
              const Color(0xFF101D37),
              const Color(0xFFF5F8FD),
              reveal,
            ),
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: Scaffold(
            backgroundColor: Color.lerp(
              const Color(0xFF101D37),
              const Color(0xFFF5F8FD),
              reveal,
            ),
            body: Stack(
          children: [
            Positioned(
              top: -250,
              left: -230,
              child: Opacity(
                opacity: reveal,
                child: const _LoginBackdropCircle(size: 560),
              ),
            ),
            Positioned(
              right: -280,
              bottom: -270,
              child: Opacity(
                opacity: reveal,
                child: const _LoginBackdropCircle(size: 600),
              ),
            ),
            IgnorePointer(
              ignoring: reveal < 1,
              child: Opacity(
                opacity: reveal,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: RepaintBoundary(
                    child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth < 420 ? 28 : 44,
                    vertical: compact ? 18 : 32,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Container(
                      padding: EdgeInsets.all(screenWidth < 420 ? 24 : 36),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(255, 255, 255, 0.88),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: const Color(0xFFDCE5F0)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1A263B65),
                            blurRadius: 42,
                            offset: Offset(0, 20),
                          ),
                        ],
                      ),
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: logoSize,
                            height: logoSize,
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(255, 255, 255, 0.88),
                              borderRadius: BorderRadius.circular(42),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x1A263B65),
                                  blurRadius: 36,
                                  offset: Offset(0, 18),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            padding: EdgeInsets.all(logoSize * 0.13),
                            child: Image.asset(
                              'lib/src/images/logo_wordmark.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        SizedBox(height: verticalGap),
                        const Text(
                          'SYNORRA - POS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: navy,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _entrance(
                          progress,
                          start: 0.47,
                          end: 0.65,
                          offsetY: 10,
                          child: const Text(
                            'Build Smarter. Grow Together.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF9AA6BF),
                              fontSize: 15,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        SizedBox(height: compact ? 28 : 42),
                        if (!_mustChangePassword) ...[
                          _entrance(
                            progress,
                            start: 0.49,
                            end: 0.73,
                            offsetY: 20,
                            child: _loginModeSelector(navy),
                          ),
                          SizedBox(height: compact ? 24 : 34),
                        ] else ...[
                          const Text(
                            'Credentials verified. Set a new password to finish signing in.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF66738E), fontSize: 14),
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (!_mustChangePassword)
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: _isLoading ? 0.6 : 1,
                            child: _entrance(
                            progress,
                            start: 0.54,
                            end: 0.78,
                            offsetY: 15,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                          _fieldLabel('Email'),
                          const SizedBox(height: 8),
                          TextField(
                            focusNode: _emailFocusNode,
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: navy, fontSize: 16),
                            cursorColor: navy,
                            decoration: _inputDecoration(
                              hint: 'Enter your email',
                              icon: Icons.mail_outline,
                            ),
                          ),
                          const SizedBox(height: 12),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 350),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) =>
                                  SlideTransition(
                                position: Tween<Offset>(
                                  begin: Offset(_isNewLogin ? 0.18 : -0.18, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              ),
                              child: _isNewLogin
                                  ? Column(
                                      key: const ValueKey('register-fields'),
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _fieldLabel('Username'),
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: _usernameController,
                                          textInputAction: TextInputAction.next,
                                          style: const TextStyle(
                                              color: navy, fontSize: 16),
                                          cursorColor: navy,
                                          decoration: _inputDecoration(
                                            hint: 'Enter your username',
                                            icon: Icons.person_outline,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const SizedBox(
                                      key: ValueKey('sign-in-fields'),
                                      width: double.infinity,
                                      height: 0,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _fieldLabel('Password'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            style: const TextStyle(color: navy, fontSize: 16),
                            cursorColor: navy,
                            decoration: _inputDecoration(
                              hint: 'Enter your password',
                              icon: Icons.lock_outline,
                              trailing: IconButton(
                                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: const Color(0xFF68758F),
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _handleLogin(),
                          ),
                              ],
                            ),
                          ),
                          ),
                        if (_mustChangePassword) ...[
                          _fieldLabel('New password (at least 8 characters)'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _newPasswordController,
                            obscureText: _obscureNewPassword,
                            style: const TextStyle(color: navy, fontSize: 16),
                            cursorColor: navy,
                            decoration: _inputDecoration(
                              hint: 'Create a new password',
                              icon: Icons.lock_outline,
                              trailing: IconButton(
                                tooltip: _obscureNewPassword ? 'Show password' : 'Hide password',
                                onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                                icon: Icon(
                                  _obscureNewPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: const Color(0xFF68758F),
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _handleLogin(),
                          ),
                        ],
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFB42318), fontSize: 13),
                          ),
                        ],
                        SizedBox(height: compact ? 24 : 34),
                        _entrance(
                          progress,
                          start: 0.64,
                          end: 0.90,
                          offsetY: 18,
                          child: SizedBox(
                            height: 62,
                            child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: navy,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color.fromRGBO(27, 41, 74, 0.65),
                              elevation: 12,
                              shadowColor: const Color(0x33203255),
                              shape: const StadiumBorder(),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutBack,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: animation,
                                  child: child,
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      key: ValueKey('sign-in-loading'),
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Row(
                                    key: const ValueKey('sign-in-action'),
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _mustChangePassword
                                            ? 'Save password'
                                            : _isNewLogin
                                                ? 'Register'
                                                : 'Sign In',
                                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 14),
                                      const Icon(Icons.arrow_forward, size: 24),
                                    ],
                                  ),
                            ),
                            ),
                          ),
                        ),
                      ],
                      ),
                    ),
                  ),
                  ),
                ),
              ),
                  ),
                ),
              ),
            ),
            if (progress < 0.84)
              _LaunchBrandOverlay(
                opacity: logoOpacity,
                scale: 0.7 + 0.3 * Curves.easeOutBack.transform(
                  (progress / 0.29).clamp(0.0, 1.0).toDouble(),
                ),
                progress: barProgress,
                pulse: math.sin(
                  (((progress - 0.08) / 0.27).clamp(0.0, 1.0) * math.pi),
                ).clamp(0.0, 1.0).toDouble(),
                statusOpacity: Curves.easeOut.transform(
                  ((progress - 0.34) / 0.08).clamp(0.0, 1.0).toDouble(),
                ) * (1 - Curves.easeIn.transform(
                  ((progress - 0.70) / 0.10).clamp(0.0, 1.0).toDouble(),
                )),
                status: statusReady ? 'Ready' : 'Initializing POS Modules...',
              ),
            if (_isNavigatingToDashboard)
              AnimatedBuilder(
                animation: _successController,
                builder: (context, _) {
                  final expansion = Curves.easeInOutExpo.transform(
                    _successController.value,
                  );
                  return Positioned.fill(
                    child: AbsorbPointer(
                      child: Center(
                        child: Transform.scale(
                          alignment: const Alignment(0, 0.55),
                          scale: 0.04 + expansion * 1.55,
                          child: SizedBox(
                            width: screenWidth,
                            height: MediaQuery.sizeOf(context).height,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xFF101D37),
                                borderRadius: BorderRadius.circular(
                                  34 * (1 - expansion),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
          ),
        );
      },
    );
  }

  Widget _entrance(
    double progress, {
    required double start,
    required double end,
    required double offsetY,
    required Widget child,
  }) {
    final t = Curves.easeOutCubic.transform(
      ((progress - start) / (end - start)).clamp(0.0, 1.0).toDouble(),
    );
    final bounce = Curves.easeOutBack.transform(t);
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - bounce) * offsetY),
        child: child,
      ),
    );
  }

  Widget _fieldLabel(String label) => Text(
        label,
        style: const TextStyle(
          color: Color(0xFF53627F),
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
      );

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? trailing,
  }) {
    const navy = Color(0xFF1B294A);
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9AA6BF), fontSize: 15),
      prefixIcon: Icon(icon, color: const Color(0xFF68758F), size: 24),
      suffixIcon: trailing,
      filled: true,
      fillColor: const Color.fromRGBO(255, 255, 255, 0.78),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: Color(0xFFD8DFEC), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: navy, width: 1.5),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: Color(0xFFD8DFEC)),
      ),
    );
  }

  Widget _loginModeSelector(Color navy) {
    return Container(
      height: 54,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF2F8),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment:
                _isNewLogin ? Alignment.centerRight : Alignment.centerLeft,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOutCubic,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: navy,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22203255),
                      blurRadius: 12,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              _loginModeTab(
                label: 'Sign In',
                selected: !_isNewLogin,
                onPressed: () => _selectLoginMode(false),
              ),
              _loginModeTab(
                label: 'Register',
                selected: _isNewLogin,
                onPressed: () => _selectLoginMode(true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _loginModeTab({
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) =>
      Expanded(
        child: TextButton(
          onPressed: _isLoading ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: selected ? Colors.white : const Color(0xFF1B294A),
            shape: const StadiumBorder(),
            minimumSize: const Size.fromHeight(46),
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 160),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF1B294A),
            ),
            child: Text(label),
          ),
        ),
      );
}

class _LaunchBrandOverlay extends StatelessWidget {
  final double opacity;
  final double scale;
  final double progress;
  final double pulse;
  final double statusOpacity;
  final String status;

  const _LaunchBrandOverlay({
    required this.opacity,
    required this.scale,
    required this.progress,
    required this.pulse,
    required this.statusOpacity,
    required this.status,
  });

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: Offset(0, (1 - opacity) * 18),
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                      width: 196,
                      height: 148,
                      padding: const EdgeInsets.all(25),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FBFF),
                        borderRadius: BorderRadius.circular(34),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x6683B8FF),
                            blurRadius: 56,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Image.asset(
                              'lib/src/images/logo_wordmark.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          Positioned(
                            left: 78,
                            top: 34,
                            child: Opacity(
                              opacity: pulse,
                              child: Container(
                                width: 19,
                                height: 28,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x88E34040),
                                      blurRadius: 15,
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: 156,
                  height: 2,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(color: const Color(0x4760738F)),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(color: const Color(0xFF91B9E8)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Opacity(
                  opacity: statusOpacity,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      status,
                      key: ValueKey(status),
                      style: const TextStyle(
                        color: Color(0xFF91A2BB),
                        fontSize: 11,
                        letterSpacing: 0.45,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _LoginBackdropCircle extends StatelessWidget {
  final double size;

  const _LoginBackdropCircle({required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [Color(0xFFF0F3FA), Color(0x00F0F3FA)],
          ),
        ),
      );
}
