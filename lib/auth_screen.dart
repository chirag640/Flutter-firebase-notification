import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback? onUserAuthenticated;
  
  const AuthScreen({super.key, this.onUserAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLogin = true;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Validate email format
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter an email';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'Please enter a valid email';
    }
    return null;
  }

  // Validate password strength
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  // Handle sign up
  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Create user account
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Send email verification
      if (userCredential.user != null && !userCredential.user!.emailVerified) {
        await userCredential.user!.sendEmailVerification();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verification email sent. Please check your inbox.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      // Call callback to update FCM token
      widget.onUserAuthenticated?.call();

    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _getErrorMessage(e.code);
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Handle sign in
  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Sign in user
      await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Call callback to update FCM token
      widget.onUserAuthenticated?.call();

    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _getErrorMessage(e.code);
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Get user-friendly error messages
  String _getErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'email-already-in-use':
        return 'An account already exists for this email.';
      case 'user-not-found':
        return 'No user found for this email.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'too-many-requests':
        return 'Too many requests. Please try again later.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  // Reset password
  Future<void> _resetPassword() async {
    if (_emailController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your email address first.';
      });
      return;
    }

    try {
      await _auth.sendPasswordResetEmail(email: _emailController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset email sent. Please check your inbox.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _getErrorMessage(e.code);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App logo/title
                Icon(
                  Icons.notifications_active,
                  size: 80,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(height: 16),
                Text(
                  'FCM Demo App',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _isLogin ? 'Sign in to your account' : 'Create a new account',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Email field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: _validateEmail,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'Enter your email address',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  validator: _validatePassword,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter your password',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),

                // Forgot password link (only show on login)
                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _resetPassword,
                      child: const Text('Forgot Password?'),
                    ),
                  ),

                const SizedBox(height: 16),

                // Error message
                if (_errorMessage.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),

                // Submit button
                ElevatedButton(
                  onPressed: _isLoading ? null : (_isLogin ? _signIn : _signUp),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _isLogin ? 'Sign In' : 'Sign Up',
                          style: const TextStyle(fontSize: 16),
                        ),
                ),
                const SizedBox(height: 16),

                // Toggle between login and signup
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_isLogin
                        ? "Don't have an account? "
                        : "Already have an account? "),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isLogin = !_isLogin;
                          _errorMessage = '';
                        });
                      },
                      child: Text(_isLogin ? 'Sign Up' : 'Sign In'),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Information card
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'How it works',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '• Sign up or log in to register for notifications\n'
                          '• Your FCM token is automatically saved\n'
                          '• Token updates when Firebase refreshes it\n'
                          '• Ready to receive push notifications!',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
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
