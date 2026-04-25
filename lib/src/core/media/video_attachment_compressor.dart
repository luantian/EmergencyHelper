import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

class VideoAttachmentCompressionResult {
  const VideoAttachmentCompressionResult({
    required this.files,
    this.videoCount = 0,
    this.compressedCount = 0,
    this.trimmedCount = 0,
    this.overSizeCount = 0,
    this.overDurationCount = 0,
    this.failedCount = 0,
    this.skippedCount = 0,
    this.savedBytes = 0,
  });

  final List<XFile> files;
  final int videoCount;
  final int compressedCount;
  final int trimmedCount;
  final int overSizeCount;
  final int overDurationCount;
  final int failedCount;
  final int skippedCount;
  final int savedBytes;

  bool get hasVideoInput => videoCount > 0;

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

class VideoAttachmentCompressor {
  const VideoAttachmentCompressor({
    this.minBytesForCompression = 512 * 1024,
    this.targetMaxBytes = 10 * 1024 * 1024,
    this.maxDurationSeconds = 20,
    this.enableDurationTrim = false,
  });

  final int minBytesForCompression;
  final int targetMaxBytes;
  final int maxDurationSeconds;
  final bool enableDurationTrim;

  static bool looksLikeVideo({required String path, String? mimeType}) {
    final normalizedMime = mimeType?.toLowerCase().trim() ?? '';
    if (normalizedMime.startsWith('video/')) {
      return true;
    }
    final lowerPath = path.toLowerCase();
    return lowerPath.endsWith('.mp4') ||
        lowerPath.endsWith('.mov') ||
        lowerPath.endsWith('.m4v') ||
        lowerPath.endsWith('.3gp') ||
        lowerPath.endsWith('.webm') ||
        lowerPath.endsWith('.mkv');
  }

  Future<VideoAttachmentCompressionResult> compressPickedFiles(
    List<XFile> files,
  ) async {
    if (files.isEmpty) {
      return const VideoAttachmentCompressionResult(files: <XFile>[]);
    }

    final outputFiles = <XFile>[];
    var videoCount = 0;
    var compressedCount = 0;
    var trimmedCount = 0;
    var overSizeCount = 0;
    var overDurationCount = 0;
    var failedCount = 0;
    var skippedCount = 0;
    var savedBytes = 0;

    for (final source in files) {
      if (!_isVideoFile(source)) {
        outputFiles.add(source);
        continue;
      }

      videoCount += 1;
      final sourceFile = File(source.path);
      if (!await sourceFile.exists()) {
        outputFiles.add(source);
        failedCount += 1;
        continue;
      }

      final sourceBytes = await sourceFile.length();
      final sourceInfo = await _safeGetMediaInfo(source.path);
      final sourceDurationSeconds = _durationSecondsFromMediaInfo(sourceInfo);
      final shouldTrim =
          enableDurationTrim &&
          sourceDurationSeconds != null &&
          sourceDurationSeconds > maxDurationSeconds;
      final shouldCompress =
          shouldTrim ||
          sourceBytes > targetMaxBytes ||
          sourceBytes >= minBytesForCompression;
      if (!shouldCompress) {
        outputFiles.add(source);
        skippedCount += 1;
        continue;
      }

      final compressed = await _tryCompressVideo(
        source,
        sourceBytes,
        limitDurationSeconds: shouldTrim ? maxDurationSeconds : null,
      );
      if (compressed == null) {
        outputFiles.add(source);
        failedCount += 1;
        if (shouldTrim) {
          overDurationCount += 1;
        }
        if (sourceBytes > targetMaxBytes) {
          overSizeCount += 1;
        }
        continue;
      }

      if (compressed.file.path == source.path) {
        outputFiles.add(source);
        skippedCount += 1;
        if (shouldTrim) {
          overDurationCount += 1;
        }
        if (sourceBytes > targetMaxBytes) {
          overSizeCount += 1;
        }
        continue;
      }

      outputFiles.add(compressed.file);
      compressedCount += 1;
      savedBytes += compressed.savedBytes;
      if (compressed.trimmed) {
        trimmedCount += 1;
      }
      if (compressed.finalBytes > targetMaxBytes) {
        overSizeCount += 1;
      }
      final finalDurationSeconds = _durationSecondsFromMediaInfo(
        compressed.mediaInfo,
      );
      if (finalDurationSeconds != null &&
          finalDurationSeconds > maxDurationSeconds) {
        overDurationCount += 1;
      }
    }

    return VideoAttachmentCompressionResult(
      files: outputFiles,
      videoCount: videoCount,
      compressedCount: compressedCount,
      trimmedCount: trimmedCount,
      overSizeCount: overSizeCount,
      overDurationCount: overDurationCount,
      failedCount: failedCount,
      skippedCount: skippedCount,
      savedBytes: savedBytes,
    );
  }

  Future<_CompressedVideo?> _tryCompressVideo(
    XFile source,
    int sourceBytes, {
    int? limitDurationSeconds,
  }) async {
    try {
      final mediaInfo = await VideoCompress.compressVideo(
        source.path,
        quality: VideoQuality.LowQuality,
        includeAudio: true,
        deleteOrigin: false,
        startTime: limitDurationSeconds == null ? null : 0,
        duration: limitDurationSeconds,
        frameRate: 18,
      );
      final compressedPath = _resolveCompressedPath(mediaInfo);
      if (compressedPath == null) {
        return null;
      }
      final compressedFile = File(compressedPath);
      if (!await compressedFile.exists()) {
        return null;
      }
      final compressedBytes = await compressedFile.length();
      if (compressedBytes <= 0 || compressedBytes >= sourceBytes) {
        return _CompressedVideo(
          file: source,
          savedBytes: 0,
          finalBytes: sourceBytes,
          trimmed: false,
          mediaInfo: null,
        );
      }
      final outputName = _fileNameFromPath(compressedPath);
      return _CompressedVideo(
        file: XFile(
          compressedPath,
          mimeType: source.mimeType ?? 'video/mp4',
          name: outputName.isEmpty ? source.name : outputName,
        ),
        savedBytes: sourceBytes - compressedBytes,
        finalBytes: compressedBytes,
        trimmed: limitDurationSeconds != null,
        mediaInfo: mediaInfo,
      );
    } catch (_) {
      return null;
    }
  }

  Future<MediaInfo?> _safeGetMediaInfo(String path) async {
    try {
      return await VideoCompress.getMediaInfo(path);
    } catch (_) {
      return null;
    }
  }

  int? _durationSecondsFromMediaInfo(MediaInfo? mediaInfo) {
    final durationValue = mediaInfo?.duration;
    if (durationValue == null || durationValue <= 0) {
      return null;
    }
    final inSeconds = durationValue / 1000;
    return inSeconds.ceil();
  }

  String? _resolveCompressedPath(MediaInfo? mediaInfo) {
    final path = mediaInfo?.path?.trim();
    if (path != null && path.isNotEmpty) {
      return path;
    }
    final filePath = mediaInfo?.file?.path.trim();
    if (filePath != null && filePath.isNotEmpty) {
      return filePath;
    }
    return null;
  }

  bool _isVideoFile(XFile file) {
    return looksLikeVideo(path: file.path, mimeType: file.mimeType);
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

class _CompressedVideo {
  const _CompressedVideo({
    required this.file,
    required this.savedBytes,
    required this.finalBytes,
    required this.trimmed,
    required this.mediaInfo,
  });

  final XFile file;
  final int savedBytes;
  final int finalBytes;
  final bool trimmed;
  final MediaInfo? mediaInfo;
}
