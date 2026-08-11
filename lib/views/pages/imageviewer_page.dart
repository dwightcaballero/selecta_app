import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/data/forms.dart';

class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.image, required this.networkImagePath});
  final File? image;
  final String networkImagePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Image Viewer'),
      body: Center(
        child: InteractiveViewer(
          child: 
            image != null
            ? Image.file(image!)
            : Image.network(networkImagePath)
        ),
      )
    );
  }
}