import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _auth = FirebaseAuth.instance;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _adController = TextEditingController();
  bool _girisMode = true;
  bool _yukleniyor = false;
  String _hata = '';

  Future<void> _submit() async {
    setState(() { _yukleniyor = true; _hata = ''; });
    try {
      if (_girisMode) {
        await _auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        final userCred = await _auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        await userCred.user?.updateDisplayName(_adController.text.trim());
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'user-not-found': _hata = 'Kullanıcı bulunamadı.'; break;
          case 'wrong-password': _hata = 'Yanlış şifre.'; break;
          case 'email-already-in-use': _hata = 'Bu email zaten kayıtlı.'; break;
          case 'weak-password': _hata = 'Şifre en az 6 karakter olmalı.'; break;
          case 'invalid-email': _hata = 'Geçersiz email adresi.'; break;
          default: _hata = e.message ?? 'Bir hata oluştu.';
        }
      });
    } finally {
      setState(() => _yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.note_alt, size: 40, color: Color(0xFF6C63FF)),
                ),
                const SizedBox(height: 24),
                Text(
                  _girisMode ? 'Hoş Geldin!' : 'Hesap Oluştur',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _girisMode ? 'Notlarına devam et' : 'Hemen başla',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                if (!_girisMode) ...[
                  TextField(
                    controller: _adController,
                    decoration: InputDecoration(
                      hintText: 'Adın',
                      prefixIcon: const Icon(Icons.person_outline),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'Email',
                    prefixIcon: const Icon(Icons.email_outlined),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Şifre',
                    prefixIcon: const Icon(Icons.lock_outline),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                if (_hata.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_hata, style: const TextStyle(color: Colors.red)),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _yukleniyor ? null : _submit,
                    child: _yukleniyor
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_girisMode ? 'Giriş Yap' : 'Kayıt Ol',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() { _girisMode = !_girisMode; _hata = ''; }),
                  child: Text(
                    _girisMode ? 'Hesabın yok mu? Kayıt ol' : 'Zaten hesabın var mı? Giriş yap',
                    style: const TextStyle(color: Color(0xFF6C63FF)),
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