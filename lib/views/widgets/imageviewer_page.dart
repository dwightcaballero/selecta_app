import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({super.key, required this.image, required this.networkImagePath});

  final File? image;
  final String networkImagePath;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  bool _isDownloading = false;

  Future<void> _downloadImage() async {
    if (_isDownloading) return;

    setState(() => _isDownloading = true);

    try {
      final Uint8List bytes;

      if (widget.image != null) {
        bytes = await widget.image!.readAsBytes();
      } else {
        final response = await http.get(Uri.parse(widget.networkImagePath));

        if (response.statusCode != 200) {
          throw Exception('Unable to download image');
        }

        bytes = response.bodyBytes;
      }

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final accessGranted = await Gal.requestAccess();
        if (!accessGranted) {
          throw Exception('Gallery permission was denied');
        }
      }

      await Gal.putImageBytes(bytes, name: 'selecta_${DateTime.now().millisecondsSinceEpoch}');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image saved to your gallery')));
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save image: $error')));
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar(
        'Image Viewer',
        actions: [
          IconButton(
            tooltip: 'Download image',
            onPressed: _isDownloading ? null : _downloadImage,
            icon: _isDownloading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF202124), Color(0xFF080808)]),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  boundaryMargin: const EdgeInsets.all(32),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30, spreadRadius: 2, offset: const Offset(0, 14)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: widget.image != null
                          ? Image.file(widget.image!, fit: BoxFit.contain)
                          : Hero(
                              tag: widget.networkImagePath,
                              child: Image.network(
                                widget.networkImagePath,
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;

                                  return const SizedBox(
                                    height: 260,
                                    child: Center(child: CircularProgressIndicator(color: Colors.white)),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return const SizedBox(
                                    height: 260,
                                    child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.white70, size: 64)),
                                  );
                                },
                              ),
                            ),
                    ),
                  ),
                ),
              ),

              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('Pinch to zoom', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
