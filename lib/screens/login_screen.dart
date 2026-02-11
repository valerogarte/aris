import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({
    super.key,
    required this.onSignIn,
    required this.loading,
    this.error,
  });

  final VoidCallback onSignIn;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ARIS'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Tus vídeos recientes',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Conéctate para ver lo más nuevo de tus suscripciones.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: loading ? null : onSignIn,
                  icon: const Icon(Icons.login),
                  label: Text(
                    loading
                        ? 'Conectando...'
                        : 'Iniciar sesión con Google',
                  ),
                ),
              ),
              if (loading) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
              ],
              if (error != null) ...[
                const SizedBox(height: 20),
                Text(
                  error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
