import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// A persistent disk + memory cached product thumbnail widget.
/// Downloads each product image once to local device storage (`product_image_cache/`)
/// and decodes it at a constrained resolution (`cacheSize`) for smooth 100+ item scrolling.
class CachedProductImage extends StatefulWidget {
  final String imageUrl;
  final bool isActive;
  final double size;
  final double borderRadius;
  final int cacheSize;

  const CachedProductImage({
    super.key,
    required this.imageUrl,
    this.isActive = true,
    this.size = 44,
    this.borderRadius = 10,
    this.cacheSize = 132,
  });

  /// Evicts a specific URL from memory and local disk cache (e.g., when an image is updated/deleted).
  static Future<void> evictUrl(String url, {int defaultCacheSize = 132}) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;
    final key = _cacheKey(cleanUrl);
    final cachedFile = _memoryFileCache.remove(key);
    try {
      NetworkImage(cleanUrl).evict();
      final dir = await _getCacheDir();
      final file = cachedFile ?? File('${dir.path}/$key');
      FileImage(file).evict();
      ResizeImage(FileImage(file), width: defaultCacheSize, height: defaultCacheSize).evict();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  /// Synchronous lookup table of verified local files so scrolling back and forth
  /// in a 100+ item ListView renders immediately on the first frame without async flicker.
  static final Map<String, File> _memoryFileCache = {};

  /// Deduplicates concurrent downloads for the same URL.
  static final Map<String, Future<File?>> _inFlightDownloads = {};

  static Directory? _cacheDirectory;

  static Future<Directory> _getCacheDir() async {
    if (_cacheDirectory != null) return _cacheDirectory!;
    final baseDir = await getApplicationSupportDirectory();
    final dir = Directory('${baseDir.path}/product_image_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDirectory = dir;
    return dir;
  }

  static String _cacheKey(String url) {
    // Deterministic 32-bit FNV-1a hash of the full URL (Web/JS and Native safe)
    var hash = 0x811c9dc5;
    for (var i = 0; i < url.length; i++) {
      hash ^= url.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'img_${hash.toRadixString(16)}.bin';
  }

  static Future<File?> _resolveFile(String url) async {
    final key = _cacheKey(url);
    final memFile = _memoryFileCache[key];
    if (memFile != null) {
      if (memFile.existsSync()) return memFile;
      _memoryFileCache.remove(key);
    }

    if (_inFlightDownloads.containsKey(key)) {
      return _inFlightDownloads[key];
    }

    final future = _loadOrDownload(url, key);
    _inFlightDownloads[key] = future;
    try {
      return await future;
    } finally {
      _inFlightDownloads.remove(key);
    }
  }

  static Future<File?> _loadOrDownload(String url, String key) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/$key');

      if (await file.exists() && await file.length() > 0) {
        _memoryFileCache[key] = file;
        return file;
      }

      final tempFile = File('${dir.path}/$key.tmp');
      await _dio.download(url, tempFile.path);
      if (await tempFile.exists() && await tempFile.length() > 0) {
        final savedFile = await tempFile.rename(file.path);
        _memoryFileCache[key] = savedFile;
        return savedFile;
      }
    } catch (_) {
      // Fallback handled by caller
    }
    return null;
  }

  @override
  State<CachedProductImage> createState() => _CachedProductImageState();
}

class _CachedProductImageState extends State<CachedProductImage> {
  File? _localFile;
  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initImage();
  }

  @override
  void didUpdateWidget(covariant CachedProductImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _initImage();
    }
  }

  void _initImage() {
    final url = widget.imageUrl.trim();
    if (url.isEmpty) {
      _localFile = null;
      _isLoading = false;
      _hasError = false;
      return;
    }

    if (kIsWeb) {
      _isLoading = false;
      _hasError = false;
      return;
    }

    final key = CachedProductImage._cacheKey(url);
    final syncFile = CachedProductImage._memoryFileCache[key];
    if (syncFile != null && syncFile.existsSync()) {
      _localFile = syncFile;
      _isLoading = false;
      _hasError = false;
      return;
    }

    _localFile = null;
    _isLoading = true;
    _hasError = false;

    CachedProductImage._resolveFile(url).then((file) {
      if (!mounted || widget.imageUrl.trim() != url) return;
      setState(() {
        _localFile = file;
        _isLoading = false;
        _hasError = file == null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: _buildInnerContent(colorScheme),
      ),
    );
  }

  Widget _buildInnerContent(ColorScheme colorScheme) {
    if (widget.imageUrl.trim().isEmpty || _hasError) {
      return _buildPlaceholder(colorScheme);
    }

    if (kIsWeb) {
      final imageWidget = Image.network(
        widget.imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(colorScheme),
      );
      if (widget.isActive) return imageWidget;
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: imageWidget,
      );
    }

    if (_isLoading || _localFile == null) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    }

    final imageWidget = Image.file(
      _localFile!,
      fit: BoxFit.cover,
      cacheWidth: widget.cacheSize,
      cacheHeight: widget.cacheSize,
      errorBuilder: (_, _, _) => _buildPlaceholder(colorScheme),
    );

    if (widget.isActive) {
      return imageWidget;
    }

    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        0.2126, 0.7152, 0.0722, 0, 0, //
        0.2126, 0.7152, 0.0722, 0, 0, //
        0.2126, 0.7152, 0.0722, 0, 0, //
        0, 0, 0, 1, 0,
      ]),
      child: imageWidget,
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Icon(
      Icons.image_outlined,
      size: widget.size * 0.45,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
    );
  }
}
