import 'package:flutter/material.dart';
import 'modern_login_page.dart';

/// Thin alias to keep existing imports working while we ship the new design.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) => const ModernLoginPage();
}
