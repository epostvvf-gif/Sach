import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/permissions.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  runApp(
    const ProviderScope(
      child: _PermissionGate(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Permission gate
// ─────────────────────────────────────────────────────────────────────────────

enum _GateStatus { checking, granted, denied }

class _PermissionGate extends StatefulWidget {
  const _PermissionGate();

  @override
  State<_PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<_PermissionGate> {
  _GateStatus _status = _GateStatus.checking;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final granted = await AppPermissions.hasStoragePermission();
    if (mounted) {
      setState(() =>
          _status = granted ? _GateStatus.granted : _GateStatus.denied);
    }
  }

  Future<void> _request() async {
    setState(() => _status = _GateStatus.checking);
    final granted = await AppPermissions.requestStoragePermissions();
    if (mounted) {
      setState(() =>
          _status = granted ? _GateStatus.granted : _GateStatus.denied);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_status) {
      _GateStatus.checking => const MaterialApp(
          home: Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        ),
      _GateStatus.granted => const DuplicateCleanerApp(),
      _GateStatus.denied => MaterialApp(
          home: _PermissionDeniedScreen(onRetry: _request),
        ),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Permission denied screen
// ─────────────────────────────────────────────────────────────────────────────

class _PermissionDeniedScreen extends StatelessWidget {
  final VoidCallback onRetry;
  const _PermissionDeniedScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_off_outlined,
                  size: 80, color: Colors.blueGrey),
              const SizedBox(height: 28),
              const Text(
                'Storage Access Required',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              const Text(
                'Duplicate Cleaner needs access to your storage '
                'to find and remove duplicate files.\n\n'
                'On Android 11+, tap "Grant" and enable '
                '"Allow access to manage all files".',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Grant Permission'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: AppPermissions.openSettings,
                child: const Text('Open App Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
