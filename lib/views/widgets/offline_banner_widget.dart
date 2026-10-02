import 'dart:async';
import 'package:flutter/material.dart';
import 'package:selecta_ops/services/offline_sync_service.dart';

/// Global wrapper that monitors real network connectivity and displays
/// a non-intrusive animated banner when internet access is lost.
class OfflineBannerWrapper extends StatefulWidget {
  final Widget child;

  const OfflineBannerWrapper({super.key, required this.child});

  @override
  State<OfflineBannerWrapper> createState() => _OfflineBannerWrapperState();
}

class _OfflineBannerWrapperState extends State<OfflineBannerWrapper> with WidgetsBindingObserver {
  Timer? _pollingTimer;
  bool _isOffline = false;
  bool _showBackOnlineBanner = false;
  int _consecutiveFailures = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkConnectivity();
    // Poll every 6 seconds for connectivity changes
    _pollingTimer = Timer.periodic(const Duration(seconds: 6), (_) => _checkConnectivity());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkConnectivity();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    try {
      final isOnline = await OfflineSyncService.isOnline();

      if (isOnline) {
        _consecutiveFailures = 0;
        if (_isOffline && mounted) {
          setState(() {
            _isOffline = false;
            _showBackOnlineBanner = true;
          });
          // Process any pending offline operations now that connectivity is back
          unawaited(OfflineSyncService.instance.processQueue());

          // Show "Back Online" briefly for 3 seconds then dismiss
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() => _showBackOnlineBanner = false);
            }
          });
        }
      } else {
        _handleFailure();
      }
    } catch (_) {
      _handleFailure();
    }
  }

  void _handleFailure() {
    _consecutiveFailures++;
    // Require 2 consecutive failed probes before flagging offline
    // to prevent false positives from transient network latency
    if (_consecutiveFailures >= 2 && !_isOffline && mounted) {
      setState(() {
        _isOffline = true;
        _showBackOnlineBanner = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showBanner = _isOffline || _showBackOnlineBanner;
    final isOnlineToast = _showBackOnlineBanner && !_isOffline;

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: showBanner
              ? Material(
                  color: isOnlineToast
                      ? const Color(0xFF065F46) // Forest green
                      : const Color(0xFFB45309), // Amber 700
                  child: SafeArea(
                    bottom: false,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isOnlineToast ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              isOnlineToast
                                  ? 'Back Online • Changes synced'
                                  : 'Working Offline • Operations cached locally',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: showBanner
              ? MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: widget.child,
                )
              : widget.child,
        ),
      ],
    );
  }
}
