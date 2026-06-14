import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../utils/app_colors.dart';

/// AuthGate widget that handles authentication state routing.
///
/// Uses FirebaseAuth.authStateChanges() as the source of truth for auth state.
/// - Shows loading indicator while checking auth state
/// - Shows HomeScreen if user is logged in OR in guest mode
/// - Shows LoginScreen only if user is not logged in AND not in guest mode
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService.instance;

    // If guest mode is active, go directly to home
    if (authService.isGuestModeActive) {
      debugPrint('[AuthGate] Guest mode active, showing HomeScreen');
      return const HomeScreen();
    }

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // Still loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          debugPrint('[AuthGate] Waiting for auth state...');
          return _buildLoadingScreen();
        }

        // Check auth state
        final user = snapshot.data;

        if (user != null) {
          debugPrint('[AuthGate] User authenticated: ${user.email} (${user.uid})');
          debugPrint('[AuthGate] Navigating to HomeScreen');
          return const HomeScreen();
        }

        // No user and not in guest mode - show login
        debugPrint('[AuthGate] No Firebase user, showing LoginScreen');
        return const LoginScreen();
      },
    );
  }

  Widget _buildLoadingScreen() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'جاري التحميل...',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
