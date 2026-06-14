import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Authentication service for handling user login, registration, and session.
///
/// This service wraps Firebase Authentication and provides:
/// - Email/password login and registration
/// - Guest mode (continue without account)
/// - Current user state
/// - Sign out functionality
class AuthService {
  static AuthService? _instance;
  FirebaseAuth? _auth;
  bool _isInitialized = false;

  AuthService._();

  static AuthService get instance {
    _instance ??= AuthService._();
    return _instance!;
  }

  /// Whether Firebase Auth is initialized
  bool get isInitialized => _isInitialized;

  /// Current authenticated user (null if guest or not logged in)
  User? get currentUser => _auth?.currentUser;

  /// Whether user is logged in (not a guest)
  bool get isLoggedIn => _auth?.currentUser != null;

  /// Whether user is a guest (not logged in)
  bool get isGuest => _auth?.currentUser == null;

  /// User display name or email
  String get userDisplayName {
    final user = currentUser;
    if (user == null) return 'ضيف';
    return user.displayName ?? user.email ?? 'مستخدم';
  }

  /// User email
  String? get userEmail => currentUser?.email;

  /// User ID (null for guests)
  String? get userId => currentUser?.uid;

  /// Initialize Firebase Auth
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _auth = FirebaseAuth.instance;
      _isInitialized = true;
      debugPrint('AuthService: Firebase Auth initialized');
      return true;
    } catch (e) {
      debugPrint('AuthService: Failed to initialize Firebase Auth: $e');
      return false;
    }
  }

  /// Sign in with email and password
  ///
  /// Returns [AuthResult] with success status and optional error message
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        return AuthResult.failure('خدمة المصادقة غير متوفرة');
      }
    }

    try {
      await _auth!.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      debugPrint('AuthService: User signed in successfully');
      return AuthResult.success();
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_getArabicErrorMessage(e.code));
    } catch (e) {
      debugPrint('AuthService: Sign in error: $e');
      return AuthResult.failure('حدث خطأ أثناء تسجيل الدخول');
    }
  }

  /// Register a new user with email and password
  ///
  /// Returns [AuthResult] with success status and optional error message
  Future<AuthResult> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        return AuthResult.failure('خدمة المصادقة غير متوفرة');
      }
    }

    try {
      final credential = await _auth!.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Update display name if provided
      if (displayName != null && displayName.isNotEmpty) {
        await credential.user?.updateDisplayName(displayName);
      }

      debugPrint('AuthService: User registered successfully');
      return AuthResult.success();
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_getArabicErrorMessage(e.code));
    } catch (e) {
      debugPrint('AuthService: Registration error: $e');
      return AuthResult.failure('حدث خطأ أثناء إنشاء الحساب');
    }
  }

  /// Sign out the current user
  Future<void> signOut() async {
    if (!_isInitialized || _auth == null) return;

    try {
      await _auth!.signOut();
      debugPrint('AuthService: User signed out');
    } catch (e) {
      debugPrint('AuthService: Sign out error: $e');
    }
  }

  /// Send password reset email
  Future<AuthResult> sendPasswordResetEmail(String email) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        return AuthResult.failure('خدمة المصادقة غير متوفرة');
      }
    }

    try {
      await _auth!.sendPasswordResetEmail(email: email.trim());
      return AuthResult.success();
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_getArabicErrorMessage(e.code));
    } catch (e) {
      debugPrint('AuthService: Password reset error: $e');
      return AuthResult.failure('حدث خطأ أثناء إرسال رابط إعادة تعيين كلمة المرور');
    }
  }

  /// Convert Firebase error codes to Arabic messages
  String _getArabicErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'لا يوجد حساب بهذا البريد الإلكتروني';
      case 'wrong-password':
        return 'كلمة المرور غير صحيحة';
      case 'invalid-email':
        return 'البريد الإلكتروني غير صالح';
      case 'user-disabled':
        return 'تم تعطيل هذا الحساب';
      case 'email-already-in-use':
        return 'هذا البريد الإلكتروني مستخدم بالفعل';
      case 'weak-password':
        return 'كلمة المرور ضعيفة جداً';
      case 'operation-not-allowed':
        return 'هذه العملية غير مسموح بها';
      case 'too-many-requests':
        return 'عدد محاولات كثيرة. يرجى المحاولة لاحقاً';
      case 'network-request-failed':
        return 'فشل الاتصال بالإنترنت';
      case 'invalid-credential':
        return 'البريد الإلكتروني أو كلمة المرور غير صحيحة';
      default:
        return 'حدث خطأ غير متوقع ($code)';
    }
  }
}

/// Result of an authentication operation
class AuthResult {
  final bool success;
  final String? errorMessage;

  AuthResult._({required this.success, this.errorMessage});

  factory AuthResult.success() => AuthResult._(success: true);

  factory AuthResult.failure(String message) => AuthResult._(
        success: false,
        errorMessage: message,
      );
}
