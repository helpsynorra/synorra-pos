// ignore_for_file: prefer_const_constructors

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          ? 'Please enter your Owner email, username, and password'
          : 'Please enter your Owner email and password');
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
    if (authenticatedToken != null && authenticatedToken.isNotEmpty) {
      unawaited(widget.controller.syncService.syncAll());
    }
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

  void _openLegalDocument(String title) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LegalDocumentScreen(title: title),
    ));
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

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarColor: const Color(0xFFF8FAFC),
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: Scaffold(
            backgroundColor: const Color(0xFFF4F6F9),
            resizeToAvoidBottomInset: true,
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
                IgnorePointer(
                  ignoring: reveal < 1 || _isLoading || _isTransitioning,
                  child: Opacity(
                    opacity: reveal * (_isLoading || _isTransitioning ? 0 : 1),
                    child: ImageFiltered(
                      imageFilter:
                          ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      child: RepaintBoundary(
                        child: SafeArea(
                          child: screenWidth < 900
                              ? _buildMobileLoginContent(
                                  progress: progress,
                                  screenWidth: screenWidth,
                                )
                              : Center(
                                  child: SingleChildScrollView(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: screenWidth < 420 ? 28 : 44,
                                      vertical: compact ? 18 : 32,
                                    ),
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 560),
                                      child: Container(
                                        padding: EdgeInsets.all(
                                            screenWidth < 420 ? 24 : 36),
                                        decoration: BoxDecoration(
                                          color: const Color.fromRGBO(
                                              255, 255, 255, 0.88),
                                          borderRadius:
                                              BorderRadius.circular(32),
                                          border: Border.all(
                                              color: const Color(0xFFDCE5F0)),
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Center(
                                              child: Container(
                                                width: logoSize,
                                                height: logoSize,
                                                decoration: BoxDecoration(
                                                  color: const Color.fromRGBO(
                                                      255, 255, 255, 0.88),
                                                  borderRadius:
                                                      BorderRadius.circular(42),
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Color(0x1A263B65),
                                                      blurRadius: 36,
                                                      offset: Offset(0, 18),
                                                    ),
                                                  ],
                                                ),
                                                clipBehavior: Clip.antiAlias,
                                                padding: EdgeInsets.all(
                                                    logoSize * 0.13),
                                                child: Image.asset(
                                                  'lib/src/images/logo-app-transparent.png',
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
                                              SizedBox(
                                                  height: compact ? 24 : 34),
                                            ] else ...[
                                              const Text(
                                                'Credentials verified. Set a new password to finish signing in.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    color: Color(0xFF66738E),
                                                    fontSize: 14),
                                              ),
                                              const SizedBox(height: 24),
                                            ],
                                            if (!_mustChangePassword)
                                              AnimatedOpacity(
                                                duration: const Duration(
                                                    milliseconds: 180),
                                                opacity: _isLoading ? 0.6 : 1,
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
                                                      _fieldLabel('Email'),
                                                      const SizedBox(height: 8),
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
                                                        style: const TextStyle(
                                                            color: navy,
                                                            fontSize: 16),
                                                        cursorColor: navy,
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
                                                        curve:
                                                            Curves.easeOutCubic,
                                                        child: AnimatedSwitcher(
                                                          duration:
                                                              const Duration(
                                                                  milliseconds:
                                                                      350),
                                                          switchInCurve: Curves
                                                              .easeOutCubic,
                                                          switchOutCurve: Curves
                                                              .easeInCubic,
                                                          transitionBuilder: (child,
                                                                  animation) =>
                                                              SlideTransition(
                                                            position:
                                                                Tween<Offset>(
                                                              begin: Offset(
                                                                  _isNewLogin
                                                                      ? 0.18
                                                                      : -0.18,
                                                                  0),
                                                              end: Offset.zero,
                                                            ).animate(
                                                                    animation),
                                                            child:
                                                                FadeTransition(
                                                              opacity:
                                                                  animation,
                                                              child: child,
                                                            ),
                                                          ),
                                                          child: _isNewLogin
                                                              ? Column(
                                                                  key: const ValueKey(
                                                                      'register-fields'),
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .stretch,
                                                                  children: [
                                                                    _fieldLabel(
                                                                        'Username'),
                                                                    const SizedBox(
                                                                        height:
                                                                            8),
                                                                    TextField(
                                                                      controller:
                                                                          _usernameController,
                                                                      textInputAction:
                                                                          TextInputAction
                                                                              .next,
                                                                      style: const TextStyle(
                                                                          color:
                                                                              navy,
                                                                          fontSize:
                                                                              16),
                                                                      cursorColor:
                                                                          navy,
                                                                      decoration:
                                                                          _inputDecoration(
                                                                        hint:
                                                                            'Enter your username',
                                                                        icon: Icons
                                                                            .person_outline,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                )
                                                              : const SizedBox(
                                                                  key: ValueKey(
                                                                      'sign-in-fields'),
                                                                  width: double
                                                                      .infinity,
                                                                  height: 0,
                                                                ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                          height: 18),
                                                      _fieldLabel('Password'),
                                                      const SizedBox(height: 8),
                                                      TextField(
                                                        controller:
                                                            _passwordController,
                                                        obscureText:
                                                            _obscurePassword,
                                                        textInputAction:
                                                            TextInputAction
                                                                .done,
                                                        style: const TextStyle(
                                                            color: navy,
                                                            fontSize: 16),
                                                        cursorColor: navy,
                                                        decoration:
                                                            _inputDecoration(
                                                          hint:
                                                              'Enter your password',
                                                          icon: Icons
                                                              .lock_outline,
                                                          trailing: IconButton(
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
                                                    color: navy, fontSize: 16),
                                                cursorColor: navy,
                                                decoration: _inputDecoration(
                                                  hint: 'Create a new password',
                                                  icon: Icons.lock_outline,
                                                  trailing: IconButton(
                                                    tooltip: _obscureNewPassword
                                                        ? 'Show password'
                                                        : 'Hide password',
                                                    onPressed: () => setState(() =>
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
                                                padding: const EdgeInsets.only(
                                                    top: 8),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    SizedBox(
                                                      width: 28,
                                                      height: 30,
                                                      child: Checkbox(
                                                        value: _acceptedLegal,
                                                        activeColor: navy,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        onChanged: _isLoading
                                                            ? null
                                                            : (value) =>
                                                                setState(() {
                                                                  _acceptedLegal =
                                                                      value ??
                                                                          false;
                                                                  _errorMessage =
                                                                      null;
                                                                }),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(top: 3),
                                                        child: Wrap(
                                                          spacing: 4,
                                                          runSpacing: 2,
                                                          crossAxisAlignment:
                                                              WrapCrossAlignment
                                                                  .center,
                                                          children: [
                                                            const Text(
                                                              'I agree to Synorra',
                                                              style: TextStyle(
                                                                  color: Color(
                                                                      0xFF53627F),
                                                                  fontSize: 13),
                                                            ),
                                                            _legalLink(
                                                                'Terms of Use'),
                                                            const Text(
                                                              'and have read and acknowledged',
                                                              style: TextStyle(
                                                                  color: Color(
                                                                      0xFF53627F),
                                                                  fontSize: 13),
                                                            ),
                                                            _legalLink(
                                                                'Privacy Policy'),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (_errorMessage != null) ...[
                                              const SizedBox(height: 14),
                                              Text(
                                                _errorMessage!,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                    color: Color(0xFFB42318),
                                                    fontSize: 13),
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
                                                  onPressed: _isLoading
                                                      ? null
                                                      : _handleLogin,
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor: navy,
                                                    foregroundColor:
                                                        Colors.white,
                                                    disabledBackgroundColor:
                                                        const Color.fromRGBO(
                                                            27, 41, 74, 0.65),
                                                    elevation: 12,
                                                    shadowColor:
                                                        const Color(0x33203255),
                                                    shape:
                                                        const StadiumBorder(),
                                                  ),
                                                  child: AnimatedSwitcher(
                                                    duration: const Duration(
                                                        milliseconds: 220),
                                                    switchInCurve:
                                                        Curves.easeOutBack,
                                                    switchOutCurve:
                                                        Curves.easeIn,
                                                    transitionBuilder:
                                                        (child, animation) =>
                                                            FadeTransition(
                                                      opacity: animation,
                                                      child: ScaleTransition(
                                                        scale: animation,
                                                        child: child,
                                                      ),
                                                    ),
                                                    child: _isLoading
                                                        ? const SizedBox(
                                                            key: ValueKey(
                                                                'sign-in-loading'),
                                                            width: 22,
                                                            height: 22,
                                                            child:
                                                                CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color:
                                                                  Colors.white,
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
                                                                    : _isNewLogin
                                                                        ? 'Register'
                                                                        : 'Sign In',
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        17,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600),
                                                              ),
                                                              const SizedBox(
                                                                  width: 14),
                                                              const Icon(
                                                                  Icons
                                                                      .arrow_forward,
                                                                  size: 24),
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
        final compactAuth = authForm && keyboardOpen;
        final signUp = authForm && _isNewLogin && !_mustChangePassword;
        final tightForm = constraints.maxHeight < 540;
        final horizontalPadding = screenWidth < 380 ? 16.0 : 20.0;
        final fieldGap = tightForm ? 5.0 : 10.0;

        Widget logo({double size = 96, double wordmarkFont = 34}) => Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRect(
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: size * 1.24,
                      maxWidth: size * 1.24,
                      minHeight: size,
                      maxHeight: size,
                      child: Image.asset(
                        'lib/src/images/logo-symbol-transparent.png',
                        width: size * 1.24,
                        height: size,
                        fit: BoxFit.fill,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 0),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset(
                      'lib/src/images/logo-wordmark-transparent.png',
                      width: wordmarkFont * 4.3,
                      height: wordmarkFont * 1.15,
                      fit: BoxFit.cover,
                    ),
                    Container(
                      width: wordmarkFont * 3.25,
                      height: 1,
                      margin: EdgeInsets.only(
                        left: wordmarkFont * 4.3 * (34 / 437),
                      ),
                      color: Colors.black,
                    ),
                    Padding(
                      padding: EdgeInsets.only(
                        left: wordmarkFont * 4.3 * (34 / 437),
                        top: 2,
                      ),
                      child: Text(
                        'POS',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: wordmarkFont * 0.58,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );

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
            top: compactAuth ? 4 : (authForm ? 12 : 40),
            bottom: compactAuth ? 4 : (compact ? 6 : 12),
          ),
          child: _entrance(
            progress,
            start: 0.2,
            end: 0.48,
            offsetY: 12,
            child: logo(
              size: compactAuth ? 56 : (authForm ? 76 : 96),
              wordmarkFont: compactAuth ? 22 : (authForm ? 29 : 34),
            ),
          ),
        );

        final artHeight = signUp
            ? 80.0
            : authForm
                ? (compact ? 150.0 : 180.0)
                : (screenWidth < 390 ? 180.0 : 200.0);
        final heroImageWidth = math.min(
          screenWidth * 1.12,
          artHeight * 2.24,
        );
        final heroImageHeight = heroImageWidth / 2.24;

        final formCard = Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: 20,
            vertical: tightForm ? 12 : 20,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6F9),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
              bottom: Radius.circular(16),
            ),
            border: Border.all(color: const Color(0xFFE7EBF2)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D1B2A4A),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_showMobileAuthForm && !_mustChangePassword) ...[
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        _isLoading ? null : () => _openMobileAuthForm(false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(
                      'Log In',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Don't have an account?",
                      style: TextStyle(color: Color(0xFF53627F), fontSize: 13),
                    ),
                    TextButton(
                      onPressed:
                          _isLoading ? null : () => _openMobileAuthForm(true),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 6),
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
                                  'I agree to Synorra',
                                  style: TextStyle(
                                      color: Color(0xFF53627F), fontSize: 12),
                                ),
                                _legalLink('Terms of Use'),
                                const Text(
                                  'and acknowledge the',
                                  style: TextStyle(
                                      color: Color(0xFF53627F), fontSize: 12),
                                ),
                                _legalLink('Privacy Policy'),
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
                  height: 52,
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
