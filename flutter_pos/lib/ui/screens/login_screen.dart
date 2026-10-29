// ignore_for_file: prefer_const_constructors

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/staff_user.dart';
import '../../state/pos_controller.dart';
import 'pos_screen.dart';
import 'support_account_screens.dart';

class LoginScreen extends StatefulWidget {
  final PosController controller;

  const LoginScreen({super.key, required this.controller});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _tabletPasswordFocusNode = FocusNode();
  final _tabletAuthScrollController = ScrollController();
  String? _errorMessage;
  bool _isLoading = false;
  bool _isTransitioning = false;
  bool _mustChangePassword = false;
  bool _isNewLogin = false;
  bool _showMobileAuthForm = false;
  bool _acceptedLegal = false;
  bool _obscurePassword = true;
  bool _obscureNewPassword = true;
  late final AnimationController _launchController;
  late final AnimationController _authController;
  late final AnimationController _successController;

  @override
  void initState() {
    super.initState();
    _launchController = AnimationController(vsync: this, value: 1);
    _authController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _tabletPasswordFocusNode.addListener(_scrollTabletPasswordIntoView);
  }

  void _scrollTabletPasswordIntoView() {
    if (!_tabletPasswordFocusNode.hasFocus) return;
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!mounted || !_tabletAuthScrollController.hasClients) return;
      _tabletAuthScrollController.animateTo(
        _tabletAuthScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    _errorMessage = null;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _newPasswordController.dispose();
    _emailFocusNode.dispose();
    _tabletPasswordFocusNode.removeListener(_scrollTabletPasswordIntoView);
    _tabletPasswordFocusNode.dispose();
    _tabletAuthScrollController.dispose();
    _launchController.dispose();
    _authController.dispose();
    _successController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim().toLowerCase();
    final username = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final newPassword = _newPasswordController.text;

    if (email.isEmpty ||
        password.isEmpty ||
        (_isNewLogin && username.isEmpty)) {
      setState(() => _errorMessage = _isNewLogin
          ? 'Please enter your email, username, and password'
          : 'Please enter your email and password');
      return;
    }
    if (_isNewLogin && !_acceptedLegal) {
      setState(() => _errorMessage =
          'Please agree to the Terms of Use and acknowledge the Privacy Policy.');
      return;
    }
    if (_mustChangePassword && newPassword.length < 8) {
      setState(() =>
          _errorMessage = 'Your new password must be at least 8 characters');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    final authAnimation = _authController.forward(from: 0);
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final cachedStaffProfile =
        widget.controller.localStorage.getActiveStaffProfile();
    final cachedPosApiToken = widget.controller.localStorage.getPosApiToken();
    final hasCachedStaffAccount = widget.controller.localStorage.getStaff().any(
        (staff) =>
            staff.role == 'cashier' &&
            (staff.email.trim().toLowerCase() == email ||
                staff.username.trim().toLowerCase() == email));
    widget.controller.supabaseService.setPosApiToken(null);

    StaffUser? authenticatedStaff;
    late final Map<String, dynamic> authRes;

    if (hasCachedStaffAccount && !_mustChangePassword && !_isNewLogin) {
      authenticatedStaff = await widget.controller
          .authenticateCachedStaffOffline(email: email, password: password);
      authRes = {
        'ok': false,
        'offline': true,
        if (authenticatedStaff == null) 'error': 'Invalid Owner credentials',
      };
    } else {
      // Initial enrollment and required password changes need server verification.
      authRes = _mustChangePassword
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
                  legalAccepted: _acceptedLegal,
                  persistSessionToken: false,
                )
              : await widget.controller.supabaseService.authenticateStaff(
                  '',
                  password,
                  email: email,
                  persistSessionToken: false,
                  timeout: Duration(seconds: hasCachedStaffAccount ? 5 : 12),
                );
    }
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
        setState(() => _errorMessage =
            'Connect to the internet to verify this Owner account.');
      }
    }

    if (authenticatedStaff == null) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            authRes['offline'] == true && widget.controller.syncService.isOnline
                ? 'Unable to verify credentials. Please try again.'
                : _errorMessage ??
                    authRes['error']?.toString() ??
                    'Invalid Owner credentials';
      });
      return;
    }

    final authenticatedUser = authenticatedStaff;
    if (!authenticatedUser.canLoginToPos) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'This account cannot log in to the POS app.';
      });
      return;
    }

    if (authRes['ok'] == true) {
      await widget.controller.localStorage.saveOfflineStaffCredential(
          authenticatedUser.id, _mustChangePassword ? newPassword : password);
    }

    final authenticatedToken = authRes['token']?.toString();
    final canReuseCachedToken = cachedStaffProfile?.id == authenticatedUser.id;
    final posApiToken =
        authenticatedToken != null && authenticatedToken.isNotEmpty
            ? authenticatedToken
            : canReuseCachedToken
                ? cachedPosApiToken
                : null;

    await widget.controller.localStorage.clearActiveStaffId();
    await widget.controller.localStorage.saveActiveStaffSession(
      authenticatedUser,
      posApiToken: posApiToken,
    );
    if (authRes['ok'] == true) {
      final cachedStaff = widget.controller.localStorage.getStaff()
        ..removeWhere((staff) => staff.id == authenticatedUser.id);
      cachedStaff.insert(0, authenticatedUser);
      await widget.controller.localStorage.saveStaff(cachedStaff);
    }
    widget.controller.supabaseService.setPosApiToken(posApiToken);
    widget.controller.currentUser = authenticatedUser;
    widget.controller.isPosOpen = true;
    unawaited(widget.controller
        .recordStaffSessionEvent(authenticatedUser, 'login')
        .catchError((_) {}));

    await authAnimation;
    if (mounted) {
      setState(() {
        _isTransitioning = true;
        _mustChangePassword = false;
        _emailController.clear();
        _usernameController.clear();
        _passwordController.clear();
        _newPasswordController.clear();
      });
      FocusManager.instance.primaryFocus?.unfocus();
      await _successController.forward(from: 0);
      if (!mounted) return;
      Navigator.pushReplacement<void, void>(
        context,
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => PosScreen(controller: widget.controller),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (context, child) => ClipPath(
                clipper: _CurtainRevealClipper(
                  progress: Curves.easeInOutExpo.transform(animation.value),
                ),
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
      _acceptedLegal = false;
    });
    if (isNewLogin) {
      await widget.controller.clearActiveSession();
    }
  }

  Future<void> _openMobileAuthForm(bool isNewLogin) async {
    if (_isNewLogin != isNewLogin) await _selectLoginMode(isNewLogin);
    if (!mounted) return;
    setState(() => _showMobileAuthForm = true);
  }

  Future<void> _openLegalDocument(String title) async {
    if (kIsWeb) {
      final path = title == 'Terms of Use' ? '/terms' : '/privacy';
      final opened = await launchUrl(
        Uri.base.resolve(path),
        webOnlyWindowName: '_blank',
      );
      if (!opened && mounted) {
        setState(() => _errorMessage = 'Could not open the legal document.');
      }
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LegalDocumentScreen(title: title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF1B294A);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = MediaQuery.sizeOf(context).height < 780;
    final tabletLayout = screenWidth > 760 && screenWidth < 1600;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
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
            ) *
            (1 -
                Curves.easeIn.transform(
                  ((progress - 0.70) / 0.12).clamp(0.0, 1.0).toDouble(),
                ));
        final barProgress = Curves.easeInOut.transform(
          ((progress - 0.35) / 0.35).clamp(0.0, 1.0).toDouble(),
        );
        final statusReady = progress >= 0.62;
        final blur = (1 - reveal) * 10;
        final mobileAuthForm =
            screenWidth <= 760 && (_showMobileAuthForm || _mustChangePassword);

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarColor:
                mobileAuthForm ? Colors.white : const Color(0xFFF8FAFC),
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: Scaffold(
            backgroundColor:
                mobileAuthForm ? Colors.white : const Color(0xFFF4F6F9),
            // Keep the brand panel's height and artwork fixed while typing on
            // tablet. The right-side form scrolls above the keyboard instead.
            resizeToAvoidBottomInset: !tabletLayout,
            body: Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -0.08),
                        radius: 1.05,
                        colors: [Colors.white, Color(0xFFF4F6F9)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: -250,
                  left: -230,
                  child: Opacity(
                    opacity: 0.55,
                    child: const _LoginBackdropCircle(size: 560),
                  ),
                ),
                Positioned(
                  right: -280,
                  bottom: -270,
                  child: Opacity(
                    opacity: 0.55,
                    child: const _LoginBackdropCircle(size: 600),
                  ),
                ),
                if (mobileAuthForm)
                  Positioned.fill(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Colors.white),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: MediaQuery.sizeOf(context).height * 0.72,
                          child: ShaderMask(
                            shaderCallback: (Rect bounds) =>
                                const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0.0, 0.68, 0.88, 1.0],
                              colors: [
                                Colors.black,
                                Colors.black,
                                Color(0xAA000000),
                                Colors.transparent,
                              ],
                            ).createShader(bounds),
                            blendMode: BlendMode.dstIn,
                            child: ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(
                                sigmaX: 1.0,
                                sigmaY: 2.0,
                              ),
                              child: Transform.scale(
                                scale: 1.75,
                                child: Image.asset(
                                  'lib/src/images/bg-plant.png',
                                  fit: BoxFit.cover,
                                  alignment: const Alignment(1.10, 3.03),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                IgnorePointer(
                  ignoring: reveal < 1 || _isLoading || _isTransitioning,
                  child: Opacity(
                    opacity: reveal * (_isLoading || _isTransitioning ? 0 : 1),
                    child: ImageFiltered(
                      imageFilter:
                          ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      child: RepaintBoundary(
                        child: SafeArea(
                          // The keyboard must not change the left panel's
                          // available height on tablet.
                          bottom: !tabletLayout,
                          child: screenWidth <= 760
                              ? _buildMobileLoginContent(
                                  progress: progress,
                                  screenWidth: screenWidth,
                                )
                              : Row(
                                  children: [
                                    if (tabletLayout)
                                      Expanded(
                                        flex: 1,
                                        child: _buildTabletBrandPanel(),
                                      ),
                                    Expanded(
                                      flex: 1,
                                      child: ColoredBox(
                                        color: tabletLayout
                                            ? Colors.white
                                            : Colors.transparent,
                                        child: Center(
                                          child: SingleChildScrollView(
                                            controller: tabletLayout
                                                ? _tabletAuthScrollController
                                                : null,
                                            padding: EdgeInsets.symmetric(
                                              horizontal: tabletLayout
                                                  ? 20
                                                  : (screenWidth < 420
                                                      ? 28
                                                      : 44),
                                              vertical: compact ? 18 : 32,
                                            ).copyWith(
                                              bottom:
                                                  tabletLayout && keyboardOpen
                                                      ? MediaQuery.viewInsetsOf(
                                                                  context)
                                                              .bottom +
                                                          24
                                                      : (compact ? 18 : 32),
                                            ),
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                  maxWidth: 560),
                                              child: Container(
                                                padding: EdgeInsets.all(
                                                    tabletLayout
                                                        ? 10
                                                        : (screenWidth < 420
                                                            ? 24
                                                            : 36)),
                                                decoration: tabletLayout
                                                    ? null
                                                    : BoxDecoration(
                                                        color: const Color
                                                            .fromRGBO(255, 255,
                                                            255, 0.88),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(32),
                                                        border: Border.all(
                                                            color: const Color(
                                                                0xFFDCE5F0)),
                                                        boxShadow: const [
                                                          BoxShadow(
                                                            color: Color(
                                                                0x1A263B65),
                                                            blurRadius: 42,
                                                            offset:
                                                                Offset(0, 20),
                                                          ),
                                                        ],
                                                      ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    if (!tabletLayout)
                                                      Center(
                                                        child: Container(
                                                          width: logoSize,
                                                          height: logoSize,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: const Color
                                                                .fromRGBO(255,
                                                                255, 255, 0.88),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        42),
                                                            boxShadow: const [
                                                              BoxShadow(
                                                                color: Color(
                                                                    0x1A263B65),
                                                                blurRadius: 36,
                                                                offset: Offset(
                                                                    0, 18),
                                                              ),
                                                            ],
                                                          ),
                                                          clipBehavior:
                                                              Clip.antiAlias,
                                                          padding:
                                                              EdgeInsets.all(
                                                                  logoSize *
                                                                      0.13),
                                                          child: Image.asset(
                                                            'lib/src/images/logo-app-transparent.png',
                                                            fit: BoxFit.contain,
                                                          ),
                                                        ),
                                                      ),
                                                    SizedBox(
                                                        height: verticalGap),
                                                    Text(
                                                      tabletLayout
                                                          ? (_isNewLogin
                                                              ? 'Create Your Account'
                                                              : 'Welcome Back!')
                                                          : 'SYNORRA - POS',
                                                      textAlign: tabletLayout
                                                          ? TextAlign.left
                                                          : TextAlign.center,
                                                      style: TextStyle(
                                                        color: navy,
                                                        fontSize: tabletLayout
                                                            ? 27
                                                            : 20,
                                                        fontWeight: tabletLayout
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                        letterSpacing: 1.4,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    _entrance(
                                                      progress,
                                                      start: 0.47,
                                                      end: 0.65,
                                                      offsetY: 10,
                                                      child: Text(
                                                        tabletLayout
                                                            ? (_isNewLogin
                                                                ? 'Create your SynOrra POS account'
                                                                : 'Log in to your account')
                                                            : 'Build Smarter. Grow Together.',
                                                        textAlign: tabletLayout
                                                            ? TextAlign.left
                                                            : TextAlign.center,
                                                        style: TextStyle(
                                                          color: tabletLayout
                                                              ? navy
                                                              : Color(
                                                                  0xFF9AA6BF),
                                                          fontSize: 15,
                                                          letterSpacing: 0.4,
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                        height:
                                                            compact ? 28 : 42),
                                                    if (!_mustChangePassword) ...[
                                                      if (!tabletLayout)
                                                        _entrance(
                                                          progress,
                                                          start: 0.49,
                                                          end: 0.73,
                                                          offsetY: 20,
                                                          child:
                                                              _loginModeSelector(
                                                                  navy),
                                                        ),
                                                      SizedBox(
                                                          height: tabletLayout
                                                              ? 8
                                                              : (compact
                                                                  ? 24
                                                                  : 34)),
                                                    ] else ...[
                                                      const Text(
                                                        'Credentials verified. Set a new password to finish signing in.',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                            color: Color(
                                                                0xFF66738E),
                                                            fontSize: 14),
                                                      ),
                                                      const SizedBox(
                                                          height: 24),
                                                    ],
                                                    if (!_mustChangePassword)
                                                      AnimatedOpacity(
                                                        duration:
                                                            const Duration(
                                                                milliseconds:
                                                                    180),
                                                        opacity: _isLoading
                                                            ? 0.6
                                                            : 1,
                                                        child: _entrance(
                                                          progress,
                                                          start: 0.54,
                                                          end: 0.78,
                                                          offsetY: 15,
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .stretch,
                                                            children: [
                                                              _fieldLabel(
                                                                  'Email'),
                                                              const SizedBox(
                                                                  height: 8),
                                                              TextField(
                                                                focusNode:
                                                                    _emailFocusNode,
                                                                controller:
                                                                    _emailController,
                                                                keyboardType:
                                                                    TextInputType
                                                                        .emailAddress,
                                                                textInputAction:
                                                                    TextInputAction
                                                                        .next,
                                                                style:
                                                                    const TextStyle(
                                                                        color:
                                                                            navy,
                                                                        fontSize:
                                                                            16),
                                                                cursorColor:
                                                                    navy,
                                                                decoration:
                                                                    _inputDecoration(
                                                                  hint:
                                                                      'Enter your email',
                                                                  icon: Icons
                                                                      .mail_outline,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 12),
                                                              AnimatedSize(
                                                                duration:
                                                                    const Duration(
                                                                        milliseconds:
                                                                            300),
                                                                curve: Curves
                                                                    .easeOutCubic,
                                                                child:
                                                                    AnimatedSwitcher(
                                                                  duration: const Duration(
                                                                      milliseconds:
                                                                          350),
                                                                  switchInCurve:
                                                                      Curves
                                                                          .easeOutCubic,
                                                                  switchOutCurve:
                                                                      Curves
                                                                          .easeInCubic,
                                                                  transitionBuilder:
                                                                      (child, animation) =>
                                                                          SlideTransition(
                                                                    position: Tween<
                                                                        Offset>(
                                                                      begin: Offset(
                                                                          _isNewLogin
                                                                              ? 0.18
                                                                              : -0.18,
                                                                          0),
                                                                      end: Offset
                                                                          .zero,
                                                                    ).animate(
                                                                        animation),
                                                                    child:
                                                                        FadeTransition(
                                                                      opacity:
                                                                          animation,
                                                                      child:
                                                                          child,
                                                                    ),
                                                                  ),
                                                                  child: _isNewLogin
                                                                      ? Column(
                                                                          key: const ValueKey(
                                                                              'register-fields'),
                                                                          crossAxisAlignment:
                                                                              CrossAxisAlignment.stretch,
                                                                          children: [
                                                                            _fieldLabel('Username'),
                                                                            const SizedBox(height: 8),
                                                                            TextField(
                                                                              controller: _usernameController,
                                                                              textInputAction: TextInputAction.next,
                                                                              style: const TextStyle(color: navy, fontSize: 16),
                                                                              cursorColor: navy,
                                                                              decoration: _inputDecoration(
                                                                                hint: 'Enter your username',
                                                                                icon: Icons.person_outline,
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        )
                                                                      : const SizedBox(
                                                                          key: ValueKey(
                                                                              'sign-in-fields'),
                                                                          width:
                                                                              double.infinity,
                                                                          height:
                                                                              0,
                                                                        ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 18),
                                                              _fieldLabel(
                                                                  'Password'),
                                                              const SizedBox(
                                                                  height: 8),
                                                              TextField(
                                                                controller:
                                                                    _passwordController,
                                                                focusNode:
                                                                    tabletLayout
                                                                        ? _tabletPasswordFocusNode
                                                                        : null,
                                                                obscureText:
                                                                    _obscurePassword,
                                                                textInputAction:
                                                                    TextInputAction
                                                                        .done,
                                                                style:
                                                                    const TextStyle(
                                                                        color:
                                                                            navy,
                                                                        fontSize:
                                                                            16),
                                                                cursorColor:
                                                                    navy,
                                                                decoration:
                                                                    _inputDecoration(
                                                                  hint:
                                                                      'Enter your password',
                                                                  icon: Icons
                                                                      .lock_outline,
                                                                  trailing:
                                                                      IconButton(
                                                                    tooltip: _obscurePassword
                                                                        ? 'Show password'
                                                                        : 'Hide password',
                                                                    onPressed: () =>
                                                                        setState(() =>
                                                                            _obscurePassword =
                                                                                !_obscurePassword),
                                                                    icon: Icon(
                                                                      _obscurePassword
                                                                          ? Icons
                                                                              .visibility_outlined
                                                                          : Icons
                                                                              .visibility_off_outlined,
                                                                      color: const Color(
                                                                          0xFF68758F),
                                                                    ),
                                                                  ),
                                                                ),
                                                                onSubmitted: (_) =>
                                                                    _handleLogin(),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    if (_mustChangePassword) ...[
                                                      _fieldLabel(
                                                          'New password (at least 8 characters)'),
                                                      const SizedBox(height: 8),
                                                      TextField(
                                                        controller:
                                                            _newPasswordController,
                                                        obscureText:
                                                            _obscureNewPassword,
                                                        style: const TextStyle(
                                                            color: navy,
                                                            fontSize: 16),
                                                        cursorColor: navy,
                                                        decoration:
                                                            _inputDecoration(
                                                          hint:
                                                              'Create a new password',
                                                          icon: Icons
                                                              .lock_outline,
                                                          trailing: IconButton(
                                                            tooltip: _obscureNewPassword
                                                                ? 'Show password'
                                                                : 'Hide password',
                                                            onPressed: () =>
                                                                setState(() =>
                                                                    _obscureNewPassword =
                                                                        !_obscureNewPassword),
                                                            icon: Icon(
                                                              _obscureNewPassword
                                                                  ? Icons
                                                                      .visibility_outlined
                                                                  : Icons
                                                                      .visibility_off_outlined,
                                                              color: const Color(
                                                                  0xFF68758F),
                                                            ),
                                                          ),
                                                        ),
                                                        onSubmitted: (_) =>
                                                            _handleLogin(),
                                                      ),
                                                    ],
                                                    if (_isNewLogin &&
                                                        !_mustChangePassword)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(top: 8),
                                                        child: Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            SizedBox(
                                                              width: 28,
                                                              height: 30,
                                                              child: Checkbox(
                                                                value:
                                                                    _acceptedLegal,
                                                                activeColor:
                                                                    navy,
                                                                materialTapTargetSize:
                                                                    MaterialTapTargetSize
                                                                        .shrinkWrap,
                                                                visualDensity:
                                                                    VisualDensity
                                                                        .compact,
                                                                onChanged:
                                                                    _isLoading
                                                                        ? null
                                                                        : (value) =>
                                                                            setState(() {
                                                                              _acceptedLegal = value ?? false;
                                                                              _errorMessage = null;
                                                                            }),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 10),
                                                            Expanded(
                                                              child: Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        top: 3),
                                                                child: Wrap(
                                                                  spacing: 4,
                                                                  runSpacing: 2,
                                                                  crossAxisAlignment:
                                                                      WrapCrossAlignment
                                                                          .center,
                                                                  children: [
                                                                    const Text(
                                                                      'I agree to Synorra POS’s',
                                                                      style: TextStyle(
                                                                          color: Color(
                                                                              0xFF53627F),
                                                                          fontSize:
                                                                              13),
                                                                    ),
                                                                    _legalLink(
                                                                        'Terms of Use'),
                                                                    const Text(
                                                                      'and',
                                                                      style: TextStyle(
                                                                          color: Color(
                                                                              0xFF53627F),
                                                                          fontSize:
                                                                              13),
                                                                    ),
                                                                    _legalLink(
                                                                        'Privacy Policy'),
                                                                    const Text(
                                                                      '.',
                                                                      style: TextStyle(
                                                                          color: Color(
                                                                              0xFF53627F),
                                                                          fontSize:
                                                                              13),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    if (_errorMessage !=
                                                        null) ...[
                                                      const SizedBox(
                                                          height: 14),
                                                      Text(
                                                        _errorMessage!,
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: const TextStyle(
                                                            color: Color(
                                                                0xFFB42318),
                                                            fontSize: 13),
                                                      ),
                                                    ],
                                                    SizedBox(
                                                        height:
                                                            compact ? 24 : 34),
                                                    _entrance(
                                                      progress,
                                                      start: 0.64,
                                                      end: 0.90,
                                                      offsetY: 18,
                                                      child: SizedBox(
                                                        height: 62,
                                                        child: DecoratedBox(
                                                          decoration:
                                                              BoxDecoration(
                                                            gradient: tabletLayout
                                                                ? const LinearGradient(
                                                                    colors: [
                                                                      Color(
                                                                          0xFF0E438E),
                                                                      Color(
                                                                          0xFF1768D2),
                                                                    ],
                                                                  )
                                                                : null,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        40),
                                                          ),
                                                          child: ElevatedButton(
                                                            onPressed: _isLoading
                                                                ? null
                                                                : _handleLogin,
                                                            style:
                                                                ElevatedButton
                                                                    .styleFrom(
                                                              backgroundColor:
                                                                  tabletLayout
                                                                      ? Colors
                                                                          .transparent
                                                                      : navy,
                                                              foregroundColor:
                                                                  Colors.white,
                                                              disabledBackgroundColor:
                                                                  tabletLayout
                                                                      ? Colors
                                                                          .transparent
                                                                      : const Color
                                                                          .fromRGBO(
                                                                          27,
                                                                          41,
                                                                          74,
                                                                          0.65),
                                                              elevation:
                                                                  tabletLayout
                                                                      ? 0
                                                                      : 12,
                                                              shadowColor:
                                                                  const Color(
                                                                      0x33203255),
                                                              shape:
                                                                  const StadiumBorder(),
                                                            ),
                                                            child:
                                                                AnimatedSwitcher(
                                                              duration:
                                                                  const Duration(
                                                                      milliseconds:
                                                                          220),
                                                              switchInCurve: Curves
                                                                  .easeOutBack,
                                                              switchOutCurve:
                                                                  Curves.easeIn,
                                                              transitionBuilder:
                                                                  (child, animation) =>
                                                                      FadeTransition(
                                                                opacity:
                                                                    animation,
                                                                child:
                                                                    ScaleTransition(
                                                                  scale:
                                                                      animation,
                                                                  child: child,
                                                                ),
                                                              ),
                                                              child: _isLoading
                                                                  ? const SizedBox(
                                                                      key: ValueKey(
                                                                          'sign-in-loading'),
                                                                      width: 22,
                                                                      height:
                                                                          22,
                                                                      child:
                                                                          CircularProgressIndicator(
                                                                        strokeWidth:
                                                                            2,
                                                                        color: Colors
                                                                            .white,
                                                                      ),
                                                                    )
                                                                  : Row(
                                                                      key: const ValueKey(
                                                                          'sign-in-action'),
                                                                      mainAxisAlignment:
                                                                          MainAxisAlignment
                                                                              .center,
                                                                      children: [
                                                                        Text(
                                                                          _mustChangePassword
                                                                              ? 'Save password'
                                                                              : tabletLayout
                                                                                  ? (_isNewLogin ? 'Sign Up' : 'Log In')
                                                                                  : _isNewLogin
                                                                                      ? 'Register'
                                                                                      : 'Sign In',
                                                                          style: const TextStyle(
                                                                              fontSize: 17,
                                                                              fontWeight: FontWeight.w600),
                                                                        ),
                                                                        const SizedBox(
                                                                            width:
                                                                                14),
                                                                        const Icon(
                                                                            Icons
                                                                                .arrow_forward,
                                                                            size:
                                                                                24),
                                                                      ],
                                                                    ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    if (tabletLayout &&
                                                        !_mustChangePassword)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(top: 20),
                                                        child: Wrap(
                                                          alignment:
                                                              WrapAlignment
                                                                  .center,
                                                          crossAxisAlignment:
                                                              WrapCrossAlignment
                                                                  .center,
                                                          children: [
                                                            Text(
                                                              _isNewLogin
                                                                  ? 'Already have an account?'
                                                                  : 'Don\'t have an account?',
                                                              style:
                                                                  const TextStyle(
                                                                color: Color(
                                                                    0xFF71819B),
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                            TextButton(
                                                              onPressed: _isLoading
                                                                  ? null
                                                                  : () => _selectLoginMode(
                                                                      !_isNewLogin),
                                                              child: Text(
                                                                _isNewLogin
                                                                    ? 'Log In'
                                                                    : 'Sign Up',
                                                                style:
                                                                    const TextStyle(
                                                                  color: Color(
                                                                      0xFF1456B7),
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
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
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (progress < 0.84)
                  _LaunchBrandOverlay(
                    opacity: logoOpacity,
                    scale: 0.7 +
                        0.3 *
                            Curves.easeOutBack.transform(
                              (progress / 0.29).clamp(0.0, 1.0).toDouble(),
                            ),
                    progress: barProgress,
                    pulse: math
                        .sin(
                          (((progress - 0.08) / 0.27).clamp(0.0, 1.0) *
                              math.pi),
                        )
                        .clamp(0.0, 1.0)
                        .toDouble(),
                    statusOpacity: Curves.easeOut.transform(
                          ((progress - 0.34) / 0.08).clamp(0.0, 1.0).toDouble(),
                        ) *
                        (1 -
                            Curves.easeIn.transform(
                              ((progress - 0.70) / 0.10)
                                  .clamp(0.0, 1.0)
                                  .toDouble(),
                            )),
                    status: statusReady
                        ? 'Welcome to Synorra'
                        : 'A better way to serve',
                  ),
                if (_isLoading || _isTransitioning)
                  _SignInTransitionOverlay(
                    animation: _authController,
                    splitAnimation: _successController,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabletBrandPanel() {
    const navy = Color(0xFF14294B);
    const muted = Color(0xFF627895);

    return Container(
      padding: const EdgeInsets.fromLTRB(34, 30, 28, 24),
      decoration: BoxDecoration(
        image: const DecorationImage(
          image: AssetImage('lib/src/images/bg-plant.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const lockupWidth = 138.0 + 18.0 + 200.0;
              final scale = (constraints.maxWidth / lockupWidth)
                      .clamp(0.55, 1.0)
                      .toDouble() *
                  0.9;
              final markSize = 138 * scale;
              final wordmarkWidth = 200 * scale;
              final wordmarkHeight = 56 * scale;

              return SizedBox(
                height: 146 * scale,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: EdgeInsets.only(top: 12 * scale),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRect(
                          child: SizedBox(
                            width: markSize,
                            height: markSize,
                            child: Transform.scale(
                              scale: 1.65,
                              child: Image.asset(
                                'lib/src/images/logo-app-square.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 18 * scale),
                        Padding(
                          padding: EdgeInsets.only(top: 20 * scale),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Image.asset(
                                'lib/src/images/logo-wordmark-cropped.png',
                                width: wordmarkWidth,
                                height: wordmarkHeight,
                                fit: BoxFit.contain,
                              ),
                              Container(
                                width: wordmarkWidth,
                                height: 1,
                                margin:
                                    EdgeInsets.symmetric(vertical: 2 * scale),
                                color: Colors.black,
                              ),
                              Text(
                                'POS',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 26 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 26),
          Text(
            'Smarter POS.\nBetter Business.',
            style: TextStyle(
              color: navy,
              fontSize: 29,
              height: 1.13,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Fast, secure and easy-to-use point of sale for your everyday operations.',
            style: TextStyle(
              color: muted,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Center(
              child: Image.asset(
                'lib/src/images/computer-transparent.png',
                fit: BoxFit.contain,
                alignment: Alignment.center,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildMobileLoginContent({
    required double progress,
    required double screenWidth,
  }) {
    const navy = Color(0xFF1B2A4A);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 720;
        final authForm = _showMobileAuthForm || _mustChangePassword;
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        final phoneLanding = screenWidth <= 760 && !authForm;
        final compactLanding = phoneLanding && constraints.maxHeight < 680;
        final compactAuth = authForm && keyboardOpen;
        final signUp = authForm && _isNewLogin && !_mustChangePassword;
        final tightForm = constraints.maxHeight < 540;
        final horizontalPadding =
            phoneLanding ? 0.0 : (screenWidth < 380 ? 16.0 : 20.0);
        final fieldGap = tightForm ? 5.0 : 10.0;

        Widget logo({double size = 96, double wordmarkFont = 34}) {
          final wordmarkWidth = wordmarkFont * 3.6;
          final wordmarkHeight = wordmarkWidth / 3.67;
          return Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'lib/src/images/logo-app-transparent.png',
                width: size * 0.75,
                height: size * 0.75,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'lib/src/images/logo-wordmark-cropped.png',
                    width: wordmarkWidth,
                    height: wordmarkHeight,
                    fit: BoxFit.contain,
                  ),
                  Container(
                    width: wordmarkWidth,
                    height: 1.2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: Colors.black,
                  ),
                  Text(
                    'POS',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: (wordmarkHeight * 0.58).clamp(12.0, 20.0),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        Widget field(String label, TextField input) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _fieldLabel(label),
                SizedBox(height: tightForm ? 4 : 7),
                SizedBox(height: tightForm ? 48 : 54, child: input),
              ],
            );

        final brand = Padding(
          padding: EdgeInsets.only(
            top: compactLanding
                ? 8
                : compactAuth
                    ? 4
                    : (authForm ? 12 : (phoneLanding ? 40.0 : 40.0)),
            bottom: compactLanding ? 2 : (compactAuth ? 4 : (compact ? 6 : 12)),
          ),
          child: _entrance(
            progress,
            start: 0.2,
            end: 0.48,
            offsetY: 12,
            child: phoneLanding
                ? Transform.translate(
                    offset: compactLanding ? Offset.zero : const Offset(0, 20),
                    child: SizedBox(
                      width: math.min(
                        screenWidth * 0.68,
                        compactLanding ? 340.0 : double.infinity,
                      ),
                      height: math.min(
                        screenWidth * 0.30,
                        compactLanding ? 150.0 : double.infinity,
                      ),
                      child: Image.asset(
                        'lib/src/images/sn-logo-transparent.png',
                        fit: BoxFit.contain,
                        semanticLabel: 'Synorra POS',
                      ),
                    ),
                  )
                : logo(
                    size: compactAuth ? 56 : (authForm ? 76 : 96),
                    wordmarkFont: compactAuth ? 22 : (authForm ? 29 : 34),
                  ),
          ),
        );

        final artHeight = phoneLanding
            ? (compactLanding ? 118.0 : (screenWidth < 390 ? 150.0 : 170.0))
            : (signUp
                ? 80.0
                : (authForm
                    ? (compact ? 150.0 : 180.0)
                    : (screenWidth < 390 ? 180.0 : 200.0)));
        final heroImageWidth = math.min(
          screenWidth * 1.12,
          artHeight * 2.24,
        );
        final heroImageHeight = heroImageWidth / 2.24;

        final formCard = Container(
          width: double.infinity,
          margin: phoneLanding ? const EdgeInsets.fromLTRB(20, 0, 20, 0) : null,
          padding: phoneLanding
              ? EdgeInsets.fromLTRB(
                  24, compactLanding ? 12 : 24, 24, compactLanding ? 12 : 24)
              : EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: tightForm ? 12 : 20,
                ),
          decoration: BoxDecoration(
            color: phoneLanding || (authForm && screenWidth <= 760)
                ? Colors.white
                : const Color(0xFFF4F6F9),
            borderRadius: phoneLanding
                ? BorderRadius.circular(24)
                : const BorderRadius.vertical(
                    top: Radius.circular(28),
                    bottom: Radius.circular(16),
                  ),
            border: Border.all(color: const Color(0xFFECEFF5), width: 1.2),
            boxShadow: phoneLanding
                ? const [
                    BoxShadow(
                      color: Color(0x171B2A4A),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: Color(0x0F1B2A4A),
                      blurRadius: 32,
                      offset: Offset(0, -6),
                    ),
                  ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_showMobileAuthForm && !_mustChangePassword) ...[
                SizedBox(
                  height: compactLanding ? 42 : (phoneLanding ? 48 : 52),
                  child: ElevatedButton(
                    onPressed:
                        _isLoading ? null : () => _openMobileAuthForm(false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: const Color(0x221B2A4A),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(
                      'Log In',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
                if (!phoneLanding) const SizedBox(height: 16),
                if (!phoneLanding)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Don't have an account?",
                        style:
                            TextStyle(color: Color(0xFF53627F), fontSize: 13),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed:
                            _isLoading ? null : () => _openMobileAuthForm(true),
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Sign Up',
                          style: TextStyle(
                            color: navy,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
              ] else ...[
                if (!_mustChangePassword)
                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Back',
                        onPressed: () => setState(() {
                          _showMobileAuthForm = false;
                          _isNewLogin = false;
                          _acceptedLegal = false;
                          _errorMessage = null;
                        }),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      Text(
                        _isNewLogin ? 'Create your account' : 'Log In',
                        style: const TextStyle(
                          color: navy,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                if (_mustChangePassword) ...[
                  const Text(
                    'Set a new password to finish signing in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF66738E)),
                  ),
                  SizedBox(height: fieldGap),
                  field(
                    'New password (at least 8 characters)',
                    TextField(
                      controller: _newPasswordController,
                      obscureText: _obscureNewPassword,
                      scrollPadding: const EdgeInsets.only(bottom: 120),
                      decoration: _inputDecoration(
                        hint: 'Create a new password',
                        icon: Icons.lock_outline,
                        trailing: IconButton(
                          tooltip: _obscureNewPassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () => setState(
                              () => _obscureNewPassword = !_obscureNewPassword),
                          icon: Icon(
                            _obscureNewPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: const Color(0xFF68758F),
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _handleLogin(),
                    ),
                  ),
                ] else ...[
                  field(
                    'Email',
                    TextField(
                      focusNode: _emailFocusNode,
                      controller: _emailController,
                      scrollPadding: const EdgeInsets.only(bottom: 120),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: _inputDecoration(
                        hint: 'Enter your email',
                        icon: Icons.mail_outline,
                      ),
                    ),
                  ),
                  if (_isNewLogin) ...[
                    SizedBox(height: fieldGap),
                    field(
                      'Username',
                      TextField(
                        controller: _usernameController,
                        scrollPadding: const EdgeInsets.only(bottom: 120),
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          hint: 'Enter your username',
                          icon: Icons.person_outline,
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: fieldGap),
                  field(
                    'Password',
                    TextField(
                      controller: _passwordController,
                      scrollPadding: const EdgeInsets.only(bottom: 120),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      decoration: _inputDecoration(
                        hint: 'Enter your password',
                        icon: Icons.lock_outline,
                        trailing: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: const Color(0xFF68758F),
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _handleLogin(),
                    ),
                  ),
                  if (_isNewLogin)
                    Padding(
                      padding: EdgeInsets.only(top: fieldGap),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 30,
                            child: Checkbox(
                              value: _acceptedLegal,
                              activeColor: navy,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              onChanged: _isLoading
                                  ? null
                                  : (value) => setState(() {
                                        _acceptedLegal = value ?? false;
                                        _errorMessage = null;
                                      }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              children: [
                                const Text(
                                  'I agree to Synorra POS’s',
                                  style: TextStyle(
                                      color: Color(0xFF53627F), fontSize: 12),
                                ),
                                _legalLink('Terms of Use'),
                                const Text(
                                  'and',
                                  style: TextStyle(
                                      color: Color(0xFF53627F), fontSize: 12),
                                ),
                                _legalLink('Privacy Policy'),
                                const Text(
                                  '.',
                                  style: TextStyle(
                                      color: Color(0xFF53627F), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (_errorMessage != null) ...[
                  SizedBox(height: fieldGap),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Color(0xFFB42318), fontSize: 13),
                  ),
                ],
                SizedBox(height: tightForm ? 9 : 15),
                SizedBox(
                  height: phoneLanding ? 48 : 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _mustChangePassword
                                ? 'Save Password'
                                : _isNewLogin
                                    ? 'Sign Up'
                                    : 'Log In',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                if (!_mustChangePassword) ...[
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isNewLogin
                            ? 'Already have an account?'
                            : "Don't have an account?",
                        style: const TextStyle(
                            color: Color(0xFF53627F), fontSize: 12),
                      ),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => _selectLoginMode(!_isNewLogin),
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _isNewLogin ? 'Log In' : 'Sign Up',
                          style: const TextStyle(
                            color: navy,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        );

        if (phoneLanding) {
          return Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFF4F6F9),
                ),
              ),
              Positioned(
                top: -100,
                right: -100,
                child: Container(
                  width: 380,
                  height: 380,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0xFFE2EDFC), Color(0x00E2EDFC)],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -24,
                left: 0,
                right: 0,
                height: constraints.maxHeight * 0.74,
                child: ShaderMask(
                  shaderCallback: (Rect bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.70, 0.88, 1.0],
                    colors: [
                      Colors.black,
                      Colors.black,
                      Color(0xAA000000),
                      Colors.transparent,
                    ],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: Transform.scale(
                    scale: 1.75,
                    child: ImageFiltered(
                      imageFilter:
                          ui.ImageFilter.blur(sigmaX: 1.0, sigmaY: 2.0),
                      child: Image.asset(
                        'lib/src/images/bg-plant.png',
                        fit: BoxFit.cover,
                        alignment: const Alignment(1.10, 3.03),
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  brand,
                  Expanded(
                    child: Center(
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: 480,
                          maxHeight: compactLanding ? 190 : 300,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _entrance(
                          progress,
                          start: 0.3,
                          end: 0.6,
                          offsetY: 16,
                          child: Transform.scale(
                            scale: compactLanding ? 1.08 : 1.45,
                            child: Image.asset(
                              'lib/src/images/computer-transparent.png',
                              fit: BoxFit.contain,
                              semanticLabel: 'Synorra point of sale terminal',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      top: compactLanding ? 0 : 4,
                      bottom: compactLanding ? 2 : 8,
                    ),
                    child: Text(
                      'Welcome!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: navy,
                        fontSize: compactLanding ? 18 : 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  formCard,
                  if (!_showMobileAuthForm && !_mustChangePassword) ...[
                    SizedBox(height: compactLanding ? 2 : 8),
                    Padding(
                      padding: EdgeInsets.only(bottom: compactLanding ? 2 : 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Don't have an account?",
                            style: TextStyle(
                                color: Color(0xFF53627F), fontSize: 13),
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => _openMobileAuthForm(true),
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Sign Up',
                              style: TextStyle(
                                color: navy,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        }

        final scrollTop = compactAuth ? 8.0 : 40.0;
        final scrollBottom = compactAuth ? 12.0 : 20.0;
        final availableHeight =
            (constraints.maxHeight - scrollTop - scrollBottom)
                .clamp(0.0, double.infinity)
                .toDouble();
        final headerAndHero = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            brand,
            if (!compactAuth) ...[
              const SizedBox(height: 40),
              ClipRect(
                child: SizedBox(
                  width: double.infinity,
                  height: heroImageHeight,
                  child: _entrance(
                    progress,
                    start: 0.3,
                    end: 0.6,
                    offsetY: 16,
                    child: OverflowBox(
                      minWidth: heroImageWidth,
                      maxWidth: heroImageWidth,
                      minHeight: heroImageHeight,
                      maxHeight: heroImageHeight,
                      child: Image.asset(
                        'lib/src/images/computer-transparent.png',
                        width: heroImageWidth,
                        height: heroImageHeight,
                        fit: BoxFit.contain,
                        semanticLabel: 'Synorra point of sale terminal',
                      ),
                    ),
                  ),
                ),
              ),
              if (!signUp)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _entrance(
                    progress,
                    start: 0.4,
                    end: 0.68,
                    offsetY: 12,
                    child: const Text(
                      'Welcome!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: navy,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );

        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            scrollTop,
            horizontalPadding,
            scrollBottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: availableHeight,
                maxWidth: screenWidth >= 600 ? 420 : double.infinity,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  headerAndHero,
                  AnimatedSize(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeInOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: formCard,
                      ),
                    ),
                  ),
                ],
              ),
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
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      );

  Widget _legalLink(String title) => InkWell(
        onTap: () => _openLegalDocument(title),
        child: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1677FF),
            fontSize: 13,
            decoration: TextDecoration.underline,
          ),
        ),
      );

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? trailing,
  }) {
    const navy = Color(0xFF1B2A4A);
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9AA6BF), fontSize: 15),
      prefixIcon: Icon(icon, color: const Color(0xFF68758F), size: 24),
      suffixIcon: trailing,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD8DFEC), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: navy, width: 2),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
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

class _SignInTransitionOverlay extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double> splitAnimation;

  const _SignInTransitionOverlay({
    required this.animation,
    required this.splitAnimation,
  });

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: RepaintBoundary(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.08),
                radius: 1.05,
                colors: [
                  Colors.white,
                  Color(0xFFF4F6FA),
                ],
              ),
            ),
            child: AnimatedBuilder(
              animation: Listenable.merge([animation, splitAnimation]),
              builder: (context, _) {
                final split = splitAnimation.value;
                final screenWidth = MediaQuery.sizeOf(context).width;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxHeight < 640;
                    final logoSize = (screenWidth * 0.28)
                        .clamp(compact ? 88.0 : 112.0, compact ? 112.0 : 156.0)
                        .toDouble();
                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (constraints.maxHeight - 16)
                              .clamp(0.0, double.infinity)
                              .toDouble(),
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              padding: EdgeInsets.all(
                                  compact ? 16 : (screenWidth < 420 ? 24 : 36)),
                              decoration: BoxDecoration(
                                color:
                                    const Color.fromRGBO(255, 255, 255, 0.92),
                                borderRadius: BorderRadius.circular(32),
                                border:
                                    Border.all(color: const Color(0xFFDCE5F0)),
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
                                children: [
                                  Container(
                                    width: logoSize,
                                    height: logoSize,
                                    padding: EdgeInsets.all(logoSize * 0.13),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(42),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x1A263B65),
                                          blurRadius: 36,
                                          offset: Offset(0, 18),
                                        ),
                                      ],
                                    ),
                                    child: Image.asset(
                                      'lib/src/images/logo-app-transparent.png',
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  SizedBox(height: compact ? 12 : 16),
                                  const Text(
                                    'SYNORRA - POS',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF1B294A),
                                      fontSize: 20,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Build Smarter. Grow Together.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF9AA6BF),
                                      fontSize: 15,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  SizedBox(height: compact ? 16 : 46),
                                  Opacity(
                                    opacity: 1 - split,
                                    child: Transform.translate(
                                      offset: Offset(0, -split * 48),
                                      child: Transform.scale(
                                        scale: 0.82 +
                                            Curves.easeOutBack.transform(
                                                  animation.value
                                                      .clamp(0.0, 1.0)
                                                      .toDouble(),
                                                ) *
                                                0.18,
                                        child: Column(
                                          children: [
                                            Container(
                                              width: compact ? 104 : 124,
                                              height: compact ? 88 : 112,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1B294A),
                                                borderRadius:
                                                    BorderRadius.circular(28),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Color(0x33203255),
                                                    blurRadius: 26,
                                                    offset: Offset(0, 12),
                                                  ),
                                                ],
                                              ),
                                              child: Icon(
                                                Icons.point_of_sale_rounded,
                                                color: Colors.white,
                                                size: compact ? 50 : 62,
                                              ),
                                            ),
                                            SizedBox(height: compact ? 14 : 24),
                                            SizedBox(
                                              width: compact ? 22 : 25,
                                              height: compact ? 22 : 25,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: Color(0xFFB6404B),
                                              ),
                                            ),
                                            SizedBox(height: compact ? 10 : 16),
                                            Text(
                                              'Opening your POS terminal',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Color(0xFF53627F),
                                                fontSize: compact ? 13 : 14,
                                                fontWeight: FontWeight.w500,
                                              ),
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
                    );
                  },
                );
              },
            ),
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
                                'lib/src/images/logo-app-transparent.png',
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

class _CurtainRevealClipper extends CustomClipper<Path> {
  final double progress;

  const _CurtainRevealClipper({required this.progress});

  @override
  Path getClip(Size size) {
    final halfHeight = size.height * progress / 2;
    return Path()
      ..addRect(Rect.fromLTRB(
        0,
        size.height / 2 - halfHeight,
        size.width,
        size.height / 2 + halfHeight,
      ));
  }

  @override
  bool shouldReclip(covariant _CurtainRevealClipper oldClipper) =>
      oldClipper.progress != progress;
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
