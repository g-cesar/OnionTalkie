import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  MobileScannerController? _controller;
  bool _scanned = false;
  final _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _controller = MobileScannerController();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _addressController.dispose();
    super.dispose();
  }

  String _sanitizeAddress(String input) {
    return input
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/$'), '')
        .trim();
  }

  void _showConfirmationDialog(String address) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Indirizzo trovato'),
        content: Text(
          address,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (!kIsWeb) {
                setState(() => _scanned = false);
                _controller?.start();
              }
            },
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx); // Chiudi l'alert
              context.pop(address); // Ritorna l'indirizzo scansionato
            },
            child: const Text('Usa indirizzo'),
          ),
        ],
      ),
    );
  }

  void _handleAddress(String raw) {
    if (raw.isEmpty) return;
    final address = _sanitizeAddress(raw);
    if (address.contains('.onion')) {
      if (kIsWeb) {
        context.pop(address);
      } else {
        _showConfirmationDialog(address);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Indirizzo .onion non valido'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _addressController.text = data!.text!;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebInput();
    }
    return _buildNativeScanner();
  }

  // ---------- Web: text input ----------

  Widget _buildWebInput() {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Inserisci indirizzo')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.qr_code_2,
                  size: 80,
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'Scanner QR non disponibile nel browser',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Incolla l\'indirizzo .onion per avviare la chiamata.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: 'Indirizzo .onion',
                    hintText: 'xxxxxxxx.onion',
                    prefixIcon: const Icon(Icons.link),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste),
                      tooltip: 'Incolla',
                      onPressed: _pasteFromClipboard,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'monospace'),
                  onSubmitted: _handleAddress,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _handleAddress(_addressController.text),
                    icon: const Icon(Icons.check),
                    label: const Text('Conferma'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Native: camera scanner ----------

  Widget _buildNativeScanner() {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scansiona QR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller?.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller?.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller!,
            onDetect: (capture) {
              if (_scanned) return;
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null && value.contains('.onion')) {
                  setState(() => _scanned = true);
                  final address = _sanitizeAddress(value);
                  _controller?.stop();
                  _showConfirmationDialog(address);
                  break;
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'Inquadra il codice QR con l\'indirizzo .onion',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
