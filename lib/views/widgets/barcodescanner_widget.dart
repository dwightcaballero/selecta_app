import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerWidget extends StatefulWidget {
  const BarcodeScannerWidget({super.key});

  @override
  State<BarcodeScannerWidget> createState() => _BarcodeScannerWidgetState();
}

class _BarcodeScannerWidgetState extends State<BarcodeScannerWidget> {
  final MobileScannerController _controller = MobileScannerController();
  final TextEditingController _manualBarcodeController = TextEditingController();
  bool _hasDetected = false;

  @override
  void dispose() {
    _controller.dispose();
    _manualBarcodeController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasDetected) return;
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || barcode.isEmpty) return;

    _hasDetected = true;
    Navigator.pop(context, barcode);
  }

  Future<void> _enterBarcodeManually() async {
    final barcode = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter barcode'),
        content: TextField(
          controller: _manualBarcodeController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Barcode', hintText: 'Type the barcode number', prefixIcon: Icon(Icons.keyboard_outlined)),
          onSubmitted: (_) => _submitManualBarcode(dialogContext),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => _submitManualBarcode(dialogContext), child: const Text('Continue')),
        ],
      ),
    );

    if (barcode == null || barcode.isEmpty || !mounted) return;
    _hasDetected = true;
    Navigator.pop(context, barcode);
  }

  void _submitManualBarcode(BuildContext dialogContext) {
    final barcode = _manualBarcodeController.text.trim();
    if (barcode.isNotEmpty) Navigator.pop(dialogContext, barcode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        actions: [
          IconButton(icon: const Icon(Icons.keyboard_outlined), tooltip: 'Enter barcode manually', onPressed: _enterBarcodeManually),
          IconButton(icon: const Icon(Icons.flash_on_rounded), onPressed: () => _controller.toggleTorch()),
          IconButton(icon: const Icon(Icons.cameraswitch_rounded), onPressed: () => _controller.switchCamera()),
        ],
      ),
      body: MobileScanner(controller: _controller, onDetect: _onDetect),
    );
  }
}
