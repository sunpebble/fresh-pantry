import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class RecipeImage extends StatefulWidget {
  const RecipeImage({
    super.key,
    required this.imageSource,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.semanticLabel,
  });

  final String? imageSource;
  final Widget fallback;
  final BoxFit fit;
  final double? width;
  final double? height;
  final String? semanticLabel;

  @override
  State<RecipeImage> createState() => _RecipeImageState();
}

class _RecipeImageState extends State<RecipeImage> {
  String? _decodedDataSource;
  Uint8List? _decodedDataBytes;

  @override
  void didUpdateWidget(covariant RecipeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageSource != widget.imageSource) {
      _decodedDataSource = null;
      _decodedDataBytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.imageSource?.trim();
    if (source == null || source.isEmpty) {
      return widget.fallback;
    }

    if (_isDataImage(source)) {
      final bytes = _dataImageBytes(source);
      if (bytes == null) {
        return widget.fallback;
      }

      return Image.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        semanticLabel: widget.semanticLabel,
        errorBuilder: (_, _, _) => widget.fallback,
      );
    }

    return Image.network(
      source,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      semanticLabel: widget.semanticLabel,
      errorBuilder: (_, _, _) => widget.fallback,
    );
  }

  Uint8List? _dataImageBytes(String source) {
    if (_decodedDataSource != source) {
      _decodedDataSource = source;
      _decodedDataBytes = _decodeDataImage(source);
    }
    return _decodedDataBytes;
  }
}

bool _isDataImage(String source) {
  return source.toLowerCase().startsWith('data:image/');
}

Uint8List? _decodeDataImage(String source) {
  const marker = ';base64,';
  final markerIndex = source.indexOf(marker);
  if (markerIndex == -1) {
    return null;
  }

  try {
    return base64Decode(source.substring(markerIndex + marker.length));
  } on FormatException {
    return null;
  }
}
