import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

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
    // Poll every 12 seconds for connectivity changes
    _pollingTimer = Timer.periodic(const Duration(seconds: 12), (_) => _checkConnectivity());
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
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 4));
      final isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;

      if (isOnline) {
        _consecutiveFailures = 0;
        if (_isOffline && mounted) {
          setState(() {
            _isOffline = false;
            _showBackOnlineBanner = true;
          });
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

    return Stack(
      children: [
        widget.child,

        // Animated drop-down banner below system status bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              offset: showBanner ? Offset.zero : const Offset(0, -1.2),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: showBanner ? 1.0 : 0.0,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isOnlineToast
                          ? const Color(0xFF065F46) // Forest green
                          : const Color(0xFFB45309), // Amber 700
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isOnlineToast ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isOnlineToast
                                ? 'Back Online • Changes synced'
                                : 'Working Offline • Operations cached locally',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
