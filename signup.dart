import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vibration/vibration.dart';

import 'firebase_service.dart';
import 'widgets/oma_background.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  PasswordStrength _passwordStrength = PasswordStrength.weak;

  @override
  void initState() {
    super.initState();
    _password.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }
  
  void _triggerErrorFeedback() {
    Vibration.hasVibrator().then((hasVibrator) {
      if (hasVibrator) {
        Vibration.vibrate(duration: 100);
      }
    });
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) {
      _triggerErrorFeedback();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please correct the errors before submitting.')),
      );
      return;
    }

    setState(() => _loading = true);
    
    try {
      final svc = FirebaseService.instance;
      final email = _email.text.trim();
      final password = _password.text.trim();
      
      await svc.signUp(
        username: _username.text.trim(),
        email: email,
        password: password,
      );
      
      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Check Your Email'),
          content: Text(
            "We've sent a verification link to:\n$email\n\nPlease check your inbox (and spam folder) to complete your registration.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); 
                Navigator.of(context).pop(); 
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
      
      await svc.signOut();
      
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _triggerErrorFeedback();
      
      String errorMessage = 'Sign-up failed';
      switch (e.code) {
        case 'weak-password':
          errorMessage = 'The password is too weak. Please choose a stronger one.';
          break;
        case 'email-already-in-use':
          errorMessage = 'An account already exists with this email address.';
          break;
        case 'invalid-email':
          errorMessage = 'The email address is not valid.';
          break;
        default:
          errorMessage = e.message ?? 'An unknown error occurred';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } catch (e) {
      if (!mounted) return;
       _triggerErrorFeedback();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An unexpected error occurred. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _checkPasswordStrength(String value) {
    setState(() {
      if (value.isEmpty) {
        _passwordStrength = PasswordStrength.weak;
      } else if (value.length < 8) {
        _passwordStrength = PasswordStrength.weak;
      } else {
        bool hasUppercase = value.contains(RegExp(r'[A-Z]'));
        bool hasDigits = value.contains(RegExp(r'[0-9]'));
        bool hasSpecialChars = value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

        int strength = 0;
        if (hasUppercase) strength++;
        if (hasDigits) strength++;
        if (hasSpecialChars) strength++;

        if (strength == 1) {
          _passwordStrength = PasswordStrength.medium;
        } else if (strength >= 2) {
          _passwordStrength = PasswordStrength.strong;
        } else {
          _passwordStrength = PasswordStrength.weak;
        }
      }
    });
  }

  InputDecoration _boxDec({Widget? suffixIcon}) => InputDecoration(
        filled: true,
        fillColor: const Color(0xFFE0E0E0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.transparent),
          borderRadius: BorderRadius.circular(4),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.transparent),
          borderRadius: BorderRadius.circular(4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        suffixIcon: suffixIcon,
      );

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: Colors.black87,
          fontWeight: FontWeight.w800,
        );

    final screenHeight = MediaQuery.of(context).size.height;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 40,
          leadingWidth: 40,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            iconSize: 20,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
          ),
        ),
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: screenHeight),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: screenHeight, 
                  child: const OmaBackground(),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              Text('Register', style: titleStyle),
                              const SizedBox(height: 12),
                              Center(
                                child: SizedBox(
                                  width: 350,
                                  height: 350,
                                  child: Image.asset(
                                    'assets/logo1.png',
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _fieldLabel('Username'),
                              TextFormField(
                                controller: _username,
                                textInputAction: TextInputAction.next,
                                decoration: _boxDec(),
                                style: const TextStyle(color: Colors.black87),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Username is required.';
                                  }
                                  if (value.length < 3) {
                                    return 'Username must be at least 3 characters.';
                                  }
                                  if (value.trim().toLowerCase() ==
                                      _email.text.trim().toLowerCase()) {
                                    return 'Username cannot be the same as your email.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              _fieldLabel('Email'),
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: _boxDec(),
                                style: const TextStyle(color: Colors.black87),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Email is required.';
                                  }
                                  if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value)) {
                                    return 'Please enter a valid email address.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              _fieldLabel('Password'),
                              TextFormField(
                                controller: _password,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.next,
                                decoration: _boxDec(
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility),
                                    onPressed: () => setState(
                                        () => _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                                style: const TextStyle(color: Colors.black87),
                                onChanged: _checkPasswordStrength,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Password is required.';
                                  }
                                  if (value.length < 8) {
                                    return 'Password must be at least 8 characters.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 8),
                              if (_password.text.isNotEmpty)
                                PasswordStrengthIndicator(
                                    strength: _passwordStrength),
                              const SizedBox(height: 16),
                              _fieldLabel('Confirm Password'),
                              TextFormField(
                                controller: _confirm,
                                obscureText: _obscureConfirmPassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _signUp(),
                                decoration: _boxDec(
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscureConfirmPassword
                                        ? Icons.visibility_off
                                        : Icons.visibility),
                                    onPressed: () => setState(() =>
                                        _obscureConfirmPassword =
                                            !_obscureConfirmPassword),
                                  ),
                                ),
                                style: const TextStyle(color: Colors.black87),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please confirm your password.';
                                  }
                                  if (value != _password.text) {
                                    return 'Passwords do not match.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              _PillButton(
                                label: _loading
                                    ? 'CREATING ACCOUNT...'
                                    : 'CREATE ACCOUNT',
                                onPressed: _loading ? null : _signUp,
                              ),
                            ],
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
        // CHANGED TO PURPLE GRADIENT
        gradient: LinearGradient(colors: [Color(0xFFBA68C8), Color(0xFF9C27B0)]), 
        borderRadius: BorderRadius.all(Radius.circular(32)),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(44),
          shape: const StadiumBorder(),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

enum PasswordStrength { weak, medium, strong }

class PasswordStrengthIndicator extends StatelessWidget {
  final PasswordStrength strength;

  const PasswordStrengthIndicator({super.key, required this.strength});

  Color _getColor() {
    switch (strength) {
      case PasswordStrength.weak:
        return Colors.red; 
      case PasswordStrength.medium:
        return Colors.amber.shade700; 
      case PasswordStrength.strong:
        return Colors.blue; 
    }
  }

  String _getText() {
    switch (strength) {
      case PasswordStrength.weak:
        return 'Weak';
      case PasswordStrength.medium:
        return 'Medium';
      case PasswordStrength.strong:
        return 'Strong';
    }
  }

  double _getFraction() {
     switch (strength) {
      case PasswordStrength.weak:
        return 0.33;
      case PasswordStrength.medium:
        return 0.66;
      case PasswordStrength.strong:
        return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _getFraction(),
            backgroundColor: Colors.grey[300],
            color: _getColor(),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              'Password Strength: ',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            Text(
              _getText(),
              style: TextStyle(color: _getColor(), fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}