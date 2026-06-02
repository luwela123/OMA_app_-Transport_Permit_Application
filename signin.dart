import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../firebase_service.dart';
import 'signup.dart';
import 'admin_dashboard.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_email.text.isEmpty || _password.text.isEmpty) {
      setState(() => _error = "Please enter email and password.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Attempt Sign In
      await FirebaseService.instance.auth.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      // 2. Attempt Database Update
      try {
        await FirebaseService.instance.autoPromoteCurrentUser();
      } catch (e) {
        // If database fails, we still allow login, but log the error
        debugPrint("Auto-promote failed (ignoring for login): $e");
      }

      if (!mounted) return;

      // 3. Navigate
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminDashboard()),
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'user-not-found') {
          _error = 'No user found for that email.';
        } else if (e.code == 'wrong-password') {
          _error = 'Wrong password provided.';
        } else {
          _error = e.message ?? 'Authentication failed.';
        }
      });
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;

        final logo = Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Image.asset(
              'assets/logo1.png',
              width: wide ? 300 : 260,
              fit: BoxFit.contain,
            ),
          ),
        );

        final form = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('OMA', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
              const Text('Admin System', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 24),

              const Text('Email'),
              const SizedBox(height: 6),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(hintText: 'Enter your email'),
              ),
              const SizedBox(height: 16),

              const Text('Password'),
              const SizedBox(height: 6),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'Enter your password'),
              ),
              const SizedBox(height: 28),

              _PillButton(
                label: _loading ? 'Logging in…' : 'Login',
                onPressed: _loading ? null : _signIn,
              ),
              const SizedBox(height: 20),

              Row(
                children: const [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Or', style: TextStyle(color: Colors.black54)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),

              Center(
                child: TextButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SignUpPage()),
                          ),
                  child: const Text('Register New Account'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        );

        if (wide) {
          return Row(
            children: [
              Expanded(child: logo),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: form,
                  ),
                ),
              ),
            ],
          );
        } else {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: Center(child: form),
            ),
          );
        }
      }),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _PillButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF2CE67D), Color(0xFF1FAB64)]),
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(54),
          shape: const StadiumBorder(),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
    );
  }
}