// lib/welcome.dart
import 'package:flutter/material.dart';
import 'login.dart';
import 'signup.dart';
import 'package:oma/widgets/oma_background.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const OmaBackground(),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    // Logo
                    SizedBox(
                      width: 270,
                      height: 270,
                      child: Image.asset('assets/logo1.png', fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Office of the Municipal Agriculturist',
                      style: TextStyle(
                        color: Color.fromARGB(255, 27, 212, 33),
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 50),
                    const Text(
                      'Apply for permit digitally',
                      style: TextStyle(
                        color: Color.fromARGB(255, 245, 27, 180),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const Spacer(),
                    _PillButton(
                      label: 'LOG IN',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _PillButton(
                      label: 'REGISTER',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignUpPage()),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _PillButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          // CHANGED TO PURPLE GRADIENT
          gradient: LinearGradient(
            colors: [Color(0xFFBA68C8), Color(0xFF9C27B0)], 
          ),
          borderRadius: BorderRadius.all(Radius.circular(32)),
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            shape: const StadiumBorder(),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}