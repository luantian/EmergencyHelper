import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class ImageAttachmentCompressionResult {
  const ImageAttachmentCompressionResult({
    required this.files,
    this.imageCount = 0,
    this.compressedCount = 0,
    this.overSizeCount = 0,
    this.failedCount = 0,
    this.skippedCount = 0,
    this.savedBytes = 0,
  });

  final List<XFile> files;
  final int imageCount;
  final int compressedCount;
  final int overSizeCount;
  final int failedCount;
  final int skippedCount;
  final int savedBytes;

  bool get hasImageInput => imageCount > 0;

  String get savedSizeLabel => _formatBytes(savedBytes);

  static String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0B';
    }
    const units = <String>['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size = size / 1024;
      unitIndex += 1;
    }
    final fixed = size >= 10
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(1);
    return '$fixed${units[unitIndex]}';
  }
}

class ImageAttachmentCompressor {
  const ImageAttachmentCompressor({
    this.targetMaxBytes = 8 * 1024 * 1024,
    this.minBytesForCompression = 8 * 1024 * 1024 + 1,
  });

  final int targetMaxBytes;
  final int minBytesForCompression;

  static bool looksLikeImage({required String path, String? mimeType}) {
    final normalizedMime = mimeType?.toLowerCase().trim() ?? '';
    if (normalizedMime.startsWith('image/')) {
      return !normalizedMime.contains('gif') && !normalizedMime.contains('svg');
    }
    final lowerPath = path.toLowerCase();
    return lowerPath.endsWith('.jpg') ||
        lowerPath.endsWith('.jpeg') ||
        lowerPath.endsWith('.png') ||
        lowerPath.endsWith('.webp') ||
        lowerPath.endsWith('.heic') ||
        lowerPath.endsWith('.heif') ||
        lowerPath.endsWith('.bmp');
  }

  Future<ImageAttachmentCompressionResult> compressPickedFiles(
    List<XFile> files,
  ) async {
    if (files.isEmpty) {
      return const ImageAttachmentCompressionResult(files: <XFile>[]);
    }

    final outputFiles = <XFile>[];
    var imageCount = 0;
    var compressedCount = 0;
    var overSizeCount = 0;
    var failedCount = 0;
    var skippedCount = 0;
    var savedBytes = 0;

    for (final source in files) {
      if (!_isImageFile(source)) {
        outputFiles.add(source);
        continue;
      }

      imageCount += 1;
      final sourceFile = File(source.path);
      if (!await sourceFile.exists()) {
        outputFiles.add(source);
        failedCount += 1;
        continue;
      }

      final sourceBytes = await sourceFile.length();
      final shouldCompress =
          sourceBytes > targetMaxBytes || sourceBytes >= minBytesForCompression;
      if (!shouldCompress) {
        outputFiles.add(source);
        skippedCount += 1;
        continue;
      }

      final compressed = await _tryCompressImage(source, sourceBytes);
      if (compressed == null) {
        outputFiles.add(source);
        failedCount += 1;
        if (sourceBytes > targetMaxBytes) {
          overSizeCount += 1;
        }
        continue;
      }

      outputFiles.add(compressed.file);
      if (compressed.file.path == source.path) {
        skippedCount += 1;
      } else {
        compressedCount += 1;
        savedBytes += compressed.savedBytes;
      }
      if (compressed.finalBytes > targetMaxBytes) {
        overSizeCount += 1;
      }
    }

    return ImageAttachmentCompressionResult(
      files: outputFiles,
      imageCount: imageCount,
      compressedCount: compressedCount,
      overSizeCount: overSizeCount,
      failedCount: failedCount,
      skippedCount: skippedCount,
      savedBytes: savedBytes,
    );
  }

  Future<_CompressedImage?> _tryCompressImage(
    XFile source,
    int sourceBytes,
  ) async {
    try {
      final sourceFile = File(source.path);
      final sourceData = await sourceFile.readAsBytes();
      final decoded = img.decodeImage(sourceData);
      if (decoded == null) {
        return null;
      }

      img.Image working = decoded;
      Uint8List? bestData;
      var resized = false;

      for (var scaleRound = 0; scaleRound < 6; scaleRound += 1) {
        for (final quality in <int>[88, 80, 72, 64, 56, 48, 40, 32, 24, 16]) {
          final jpgBytes = Uint8List.fromList(
            img.encodeJpg(working, quality: quality),
          );
          if (bestData == null || jpgBytes.length < bestData.length) {
            bestData = jpgBytes;
          }
          if (jpgBytes.length <= targetMaxBytes) {
            return _saveCompressedImage(
              source: source,
              bytes: jpgBytes,
              sourceBytes: sourceBytes,
              resized: resized,
            );
          }
        }

        final nextWidth = (working.width * 0.85).round();
        final nextHeight = (working.height * 0.85).round();
        if (nextWidth < 420 || nextHeight < 420) {
          break;
        }
        if (nextWidth >= working.width || nextHeight >= working.height) {
          break;
        }
        working = img.copyResize(
          working,
          width: nextWidth,
          height: nextHeight,
          interpolation: img.Interpolation.average,
        );
        resized = true;
      }

      if (bestData == null) {
        return null;
      }
      return _saveCompressedImage(
        source: source,
        bytes: bestData,
        sourceBytes: sourceBytes,
        resized: resized,
      );
    } catch (_) {
      return null;
    }
  }

  Future<_CompressedImage> _saveCompressedImage({
    required XFile source,
    required Uint8List bytes,
    required int sourceBytes,
    required bool resized,
  }) async {
    if (bytes.isEmpty || bytes.length >= sourceBytes) {
      return _CompressedImage(
        file: source,
        savedBytes: 0,
        finalBytes: sourceBytes,
        resized: false,
      );
    }

    final sourcePath = source.path;
    final sourceFile = File(sourcePath);
    final outputDir = sourceFile.parent.path;
    final outputBase = _baseNameWithoutExtension(source.name, sourcePath);
    final outputName =
        '${outputBase}_compressed_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final outputPath = '$outputDir${Platform.pathSeparator}$outputName';

    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(bytes, flush: true);

    return _CompressedImage(
      file: XFile(outputPath, mimeType: 'image/jpeg', name: outputName),
      savedBytes: sourceBytes - bytes.length,
      finalBytes: bytes.length,
      resized: resized,
    );
  }

  bool _isImageFile(XFile file) {
    return looksLikeImage(path: file.path, mimeType: file.mimeType);
  }

  String _baseNameWithoutExtension(String preferredName, String fallbackPath) {
    final normalizedName = preferredName.trim();
    final fileName = normalizedName.isNotEmpty
        ? normalizedName
        : _fileNameFromPath(fallbackPath);
    if (fileName.isEmpty) {
      return 'image';
    }
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, dotIndex);
  }

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    if (segments.isEmpty) {
      return '';
    }
    return segments.last.trim();
  }
}

class _CompressedImage {
  const _CompressedImage({
    required this.file,
    required this.savedBytes,
    required this.finalBytes,
    required this.resized,
  });

  final XFile file;
  final int savedBytes;
  final int finalBytes;
  final bool resized;
}
