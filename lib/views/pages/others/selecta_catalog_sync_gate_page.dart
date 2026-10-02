import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/selecta_product_controller.dart';
import 'package:selecta_ops/services/offline_sync_service.dart';
import 'package:selecta_ops/views/pages/others/loading_page.dart';

/// Gateway widget that checks if the local dealer database needs to initialize or sync
/// its `selecta_products` catalog with the master [AdminSelectaProduct] API
/// (either on first app load or whenever there are changes in the Admin product list).
class SelectaCatalogSyncGatePage extends StatefulWidget {
  final Widget child;

  const SelectaCatalogSyncGatePage({
    super.key,
    required this.child,
  });

  @override
  State<SelectaCatalogSyncGatePage> createState() => _SelectaCatalogSyncGatePageState();
}

class _SelectaCatalogSyncGatePageState extends State<SelectaCatalogSyncGatePage> {
  final SelectaProductController _controller = SelectaProductController();

  bool _isChecking = true;
  bool _isSyncing = false;
  bool _readyToProceed = false;

  int _currentItem = 0;
  int _totalItems = 1;
  String _statusMessage = 'Checking Selecta product catalog...';

  @override
  void initState() {
    super.initState();
    _checkAndSyncIfNeeded();
  }

  Future<void> _checkAndSyncIfNeeded() async {
    try {
      final isOnline = await OfflineSyncService.isOnline();
      if (!isOnline) {
        if (!mounted) return;
        setState(() {
          _isChecking = false;
          _readyToProceed = true;
        });
        return;
      }

      final check = await _controller.checkSyncNeeded().timeout(const Duration(seconds: 4));
      if (!mounted) return;

      if (!check.needsSync) {
        setState(() {
          _isChecking = false;
          _readyToProceed = true;
        });
        return;
      }

      setState(() {
        _isChecking = false;
        _isSyncing = true;
        _totalItems = check.remoteProducts.isNotEmpty ? check.remoteProducts.length : 1;
        _statusMessage = check.reason;
      });

      await _controller.syncWithAdminCatalog(
        remoteProducts: check.remoteProducts,
        onProgress: (current, total, status) {
          if (!mounted) return;
          setState(() {
            _currentItem = current;
            _totalItems = total > 0 ? total : 1;
            _statusMessage = status;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        _readyToProceed = true;
      });
    } catch (_) {
      // Never block the user from reaching the dashboard if offline or network fails
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _isSyncing = false;
        _readyToProceed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_readyToProceed) {
      return widget.child;
    }

    if (_isChecking && !_isSyncing) {
      return const LoadingPage();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final progress = _totalItems > 0 ? (_currentItem / _totalItems).clamp(0.0, 1.0) : null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.cloud_sync_rounded,
                    size: 44,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Syncing Selecta Products',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _statusMessage,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress != null && progress > 0 ? progress : null,
                    minHeight: 8,
                  ),
                ),
                if (_totalItems > 1 && _currentItem > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '$_currentItem of $_totalItems products',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
