import 'dart:ui';

/// Single token or word recognized by OCR with its bounding box.
class OcrElement {
  final String text;
  final Rect boundingBox;
  final double? confidence;

  const OcrElement({
    required this.text,
    required this.boundingBox,
    this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'rect': [boundingBox.left, boundingBox.top, boundingBox.right, boundingBox.bottom],
        if (confidence != null) 'confidence': confidence,
      };

  factory OcrElement.fromJson(Map<String, dynamic> json) {
    final rectList = (json['rect'] as List).cast<num>();
    return OcrElement(
      text: json['text'] as String? ?? '',
      boundingBox: Rect.fromLTRB(
        rectList[0].toDouble(),
        rectList[1].toDouble(),
        rectList[2].toDouble(),
        rectList[3].toDouble(),
      ),
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }
}

/// A line of text recognized by OCR, composed of one or more [OcrElement]s.
class OcrLine {
  final String text;
  final Rect boundingBox;
  final List<OcrElement> elements;
  final double? confidence;
  final int pageIndex;

  const OcrLine({
    required this.text,
    required this.boundingBox,
    this.elements = const [],
    this.confidence,
    this.pageIndex = 0,
  });

  double get centerY => boundingBox.top + (boundingBox.height / 2.0);
  double get height => boundingBox.height;

  Map<String, dynamic> toJson() => {
        'text': text,
        'rect': [boundingBox.left, boundingBox.top, boundingBox.right, boundingBox.bottom],
        'elements': elements.map((e) => e.toJson()).toList(),
        if (confidence != null) 'confidence': confidence,
        'pageIndex': pageIndex,
      };

  factory OcrLine.fromJson(Map<String, dynamic> json) {
    final rectList = (json['rect'] as List).cast<num>();
    final elementsJson = json['elements'] as List? ?? [];
    return OcrLine(
      text: json['text'] as String? ?? '',
      boundingBox: Rect.fromLTRB(
        rectList[0].toDouble(),
        rectList[1].toDouble(),
        rectList[2].toDouble(),
        rectList[3].toDouble(),
      ),
      elements: elementsJson.map((e) => OcrElement.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      confidence: (json['confidence'] as num?)?.toDouble(),
      pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A block of text (paragraph/cell/column) recognized by OCR.
class OcrBlock {
  final String text;
  final Rect boundingBox;
  final List<OcrLine> lines;

  const OcrBlock({
    required this.text,
    required this.boundingBox,
    this.lines = const [],
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'rect': [boundingBox.left, boundingBox.top, boundingBox.right, boundingBox.bottom],
        'lines': lines.map((l) => l.toJson()).toList(),
      };

  factory OcrBlock.fromJson(Map<String, dynamic> json) {
    final rectList = (json['rect'] as List).cast<num>();
    final linesJson = json['lines'] as List? ?? [];
    return OcrBlock(
      text: json['text'] as String? ?? '',
      boundingBox: Rect.fromLTRB(
        rectList[0].toDouble(),
        rectList[1].toDouble(),
        rectList[2].toDouble(),
        rectList[3].toDouble(),
      ),
      lines: linesJson.map((l) => OcrLine.fromJson(Map<String, dynamic>.from(l as Map))).toList(),
    );
  }
}

/// Single document page / image result containing text blocks and lines.
class OcrPage {
  final int pageIndex;
  final double width;
  final double height;
  final List<OcrBlock> blocks;

  const OcrPage({
    required this.pageIndex,
    this.width = 0,
    this.height = 0,
    this.blocks = const [],
  });

  List<OcrLine> get lines {
    final list = <OcrLine>[];
    for (final b in blocks) {
      list.addAll(b.lines);
    }
    return list;
  }

  Map<String, dynamic> toJson() => {
        'pageIndex': pageIndex,
        'width': width,
        'height': height,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory OcrPage.fromJson(Map<String, dynamic> json) {
    final blocksJson = json['blocks'] as List? ?? [];
    return OcrPage(
      pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 0,
      height: (json['height'] as num?)?.toDouble() ?? 0,
      blocks: blocksJson.map((b) => OcrBlock.fromJson(Map<String, dynamic>.from(b as Map))).toList(),
    );
  }
}

/// Full OCR result covering one or multiple document images.
class OcrResult {
  final List<OcrPage> pages;

  const OcrResult({this.pages = const []});

  List<OcrLine> get allLines {
    final list = <OcrLine>[];
    for (final page in pages) {
      list.addAll(page.lines);
    }
    return list;
  }

  String get fullText => allLines.map((l) => l.text).join('\n');

  Map<String, dynamic> toJson() => {
        'pages': pages.map((p) => p.toJson()).toList(),
      };

  factory OcrResult.fromJson(Map<String, dynamic> json) {
    final pagesJson = json['pages'] as List? ?? [];
    return OcrResult(
      pages: pagesJson.map((p) => OcrPage.fromJson(Map<String, dynamic>.from(p as Map))).toList(),
    );
  }
}
