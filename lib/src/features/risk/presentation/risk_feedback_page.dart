import 'dart:io';

import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/media/image_attachment_compressor.dart';
import 'package:emergency_helper/src/core/media/video_attachment_compressor.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/core/widgets/app_loading_overlay.dart';
import 'package:emergency_helper/src/features/risk/data/risk_center.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

class RiskFeedbackPage extends StatefulWidget {
  const RiskFeedbackPage({required this.riskId, super.key});

  final String riskId;

  @override
  State<RiskFeedbackPage> createState() => _RiskFeedbackPageState();
}

class _RiskFeedbackPageState extends State<RiskFeedbackPage> {
  final TextEditingController _contentController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final ImageAttachmentCompressor _imageAttachmentCompressor =
      const ImageAttachmentCompressor();
  final VideoAttachmentCompressor _videoAttachmentCompressor =
      const VideoAttachmentCompressor();
  final List<_SelectedAttachment> _attachments = <_SelectedAttachment>[];
  bool _submitting = false;
  bool _compressingAttachments = false;
  String _feedbackUser = '当前用户';

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('risk-feedback-root'),
      appBar: AppBar(
        title: const Text('风险反馈'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF3F6FB),
      body: AppLoadingOverlay(
        loading: _submitting || _compressingAttachments,
        message: _submitting ? '提交中...' : '附件处理中，请稍候...',
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                children: <Widget>[
                  _buildIntroCard(),
                  const SizedBox(height: 12),
                  _buildContentCard(),
                  const SizedBox(height: 12),
                  _buildAttachmentCard(),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _onSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2088E8),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFABCDF1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '提交反馈',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCFE3F9)),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFF2D78C6)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '请填写风险处置进展，可附上图片或视频作为补充材料。',
              style: TextStyle(
                color: Color(0xFF2F4F70),
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE7F4)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0A153254),
            offset: Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '反馈内容',
            style: TextStyle(
              color: Color(0xFF17283A),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(minHeight: 130),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFD),
              borderRadius: BorderRadius.circular(10),
              border: const Border(
                top: BorderSide(color: Color(0xFFB9C8D8), width: 1.4),
                right: BorderSide(color: Color(0xFFB9C8D8), width: 1.4),
                bottom: BorderSide(color: Color(0xFFB9C8D8), width: 1.4),
                left: BorderSide(color: Color(0xFFB9C8D8), width: 1.4),
              ),
            ),
            child: TextField(
              controller: _contentController,
              minLines: 6,
              maxLines: null,
              style: const TextStyle(
                color: Color(0xFF1E2C3B),
                fontSize: 14,
                height: 1.4,
              ),
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: '请填写风险处置进展、现场变化和建议措施',
                hintStyle: TextStyle(color: Color(0xFF8A94A1), fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentCard() {
    final summary = _attachments.isEmpty
        ? '暂未添加附件'
        : '已添加 ${_attachments.length} 个附件';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE7F4)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0A153254),
            offset: Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '附件材料',
            style: TextStyle(
              color: Color(0xFF17283A),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickAttachment,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(98, 36),
                  foregroundColor: const Color(0xFF2F4864),
                  side: const BorderSide(color: Color(0xFFBFD0E4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: const Text(
                  '添加附件',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF627388),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_attachments.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFE),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2ECF8)),
              ),
              child: const Text(
                '支持拍照、相册、视频选择与拍摄',
                style: TextStyle(color: Color(0xFF8794A3), fontSize: 12),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List<Widget>.generate(_attachments.length, (index) {
                final item = _attachments[index];
                final isVideo = _isVideoType(item.type);
                return Container(
                  constraints: const BoxConstraints(maxWidth: 290),
                  padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF5FC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFD4E1F1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        isVideo ? Icons.videocam_rounded : Icons.image_rounded,
                        size: 16,
                        color: const Color(0xFF5C7898),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF415973),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: _submitting
                            ? null
                            : () => _removeAttachmentAt(index),
                        borderRadius: BorderRadius.circular(10),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Color(0xFF6C7E93),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAttachment() async {
    final action = await showModalBottomSheet<_AttachmentPickAction>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍照上传'),
                onTap: () =>
                    Navigator.of(context).pop(_AttachmentPickAction.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                onTap: () =>
                    Navigator.of(context).pop(_AttachmentPickAction.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: const Text('选择视频'),
                onTap: () =>
                    Navigator.of(context).pop(_AttachmentPickAction.video),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('拍摄视频'),
                onTap: () => Navigator.of(
                  context,
                ).pop(_AttachmentPickAction.cameraVideo),
              ),
            ],
          ),
        );
      },
    );

    if (action == null || !mounted) {
      return;
    }
    final isVideoFlow =
        action == _AttachmentPickAction.video ||
        action == _AttachmentPickAction.cameraVideo;

    try {
      final selectedFiles = await _pickAttachmentFiles(action);
      if (selectedFiles.isEmpty || !mounted) {
        return;
      }
      var filesToAppend = selectedFiles;
      if (mounted) {
        setState(() {
          _compressingAttachments = true;
        });
      }
      var imageCompressionResult = ImageAttachmentCompressionResult(
        files: filesToAppend,
      );
      VideoAttachmentCompressionResult videoCompressionResult;
      try {
        if (!isVideoFlow) {
          imageCompressionResult = await _imageAttachmentCompressor
              .compressPickedFiles(filesToAppend);
          filesToAppend = imageCompressionResult.files;
        }

        videoCompressionResult = await _videoAttachmentCompressor
            .compressPickedFiles(filesToAppend);
        filesToAppend = videoCompressionResult.files;
      } finally {
        if (mounted) {
          setState(() {
            _compressingAttachments = false;
          });
        }
      }
      if (!mounted) {
        return;
      }

      if (!isVideoFlow &&
          imageCompressionResult.hasImageInput &&
          imageCompressionResult.compressedCount > 0) {
        final summaryParts = <String>[
          '已压缩${imageCompressionResult.compressedCount}张图片',
        ];
        if (imageCompressionResult.savedBytes > 0) {
          summaryParts.add('共缩减${imageCompressionResult.savedSizeLabel}');
        }
        _showMessage(summaryParts.join('，'));
      }
      if (!isVideoFlow &&
          imageCompressionResult.hasImageInput &&
          imageCompressionResult.failedCount > 0) {
        _showMessage('有${imageCompressionResult.failedCount}张图片压缩失败，已使用原图');
      }
      if (!isVideoFlow &&
          imageCompressionResult.hasImageInput &&
          imageCompressionResult.overSizeCount > 0) {
        _showMessage(
          '有${imageCompressionResult.overSizeCount}张图片仍超过8MB，建议裁剪后重试',
        );
      }

      if (videoCompressionResult.compressedCount > 0 ||
          videoCompressionResult.trimmedCount > 0) {
        final summaryParts = <String>[];
        if (videoCompressionResult.compressedCount > 0) {
          summaryParts.add('已压缩${videoCompressionResult.compressedCount}个视频');
        }
        if (videoCompressionResult.trimmedCount > 0) {
          summaryParts.add(
            '已自动截取${videoCompressionResult.trimmedCount}个视频的前20秒',
          );
        }
        if (videoCompressionResult.savedBytes > 0) {
          summaryParts.add('共缩减${videoCompressionResult.savedSizeLabel}');
        }
        _showMessage(summaryParts.join('，'));
      } else if (videoCompressionResult.failedCount > 0) {
        _showMessage('视频压缩失败，已使用原视频');
      }
      if (videoCompressionResult.overDurationCount > 0) {
        _showMessage(
          '有${videoCompressionResult.overDurationCount}个视频仍超过20秒，建议重新录制',
        );
      }
      if (videoCompressionResult.overSizeCount > 0) {
        _showMessage(
          '有${videoCompressionResult.overSizeCount}个视频仍超过10MB，建议缩短时长后重试',
        );
      }
      if (filesToAppend.isEmpty || !mounted) {
        return;
      }
      setState(() {
        for (final selectedFile in filesToAppend) {
          _addPickedAttachment(selectedFile, action);
        }
      });
    } on MissingPluginException {
      _showMessage('当前环境暂不支持调用系统相册/相机');
    } catch (_) {
      _showMessage('打开系统相册/相机失败，请重试');
    }
  }

  Future<List<XFile>> _pickAttachmentFiles(_AttachmentPickAction action) async {
    switch (action) {
      case _AttachmentPickAction.camera:
        final hasPermission = await _ensureCameraPermission();
        if (!hasPermission) {
          return const <XFile>[];
        }
        final picked = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
          maxWidth: 2048,
        );
        return picked == null ? const <XFile>[] : <XFile>[picked];
      case _AttachmentPickAction.gallery:
        final picked = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
          maxWidth: 2048,
        );
        return picked == null ? const <XFile>[] : <XFile>[picked];
      case _AttachmentPickAction.video:
        final picked = await _imagePicker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(seconds: 20),
        );
        return picked == null ? const <XFile>[] : <XFile>[picked];
      case _AttachmentPickAction.cameraVideo:
        final hasPermission = await _ensureCameraPermission();
        if (!hasPermission) {
          return const <XFile>[];
        }
        final picked = await _imagePicker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(seconds: 20),
          preferredCameraDevice: CameraDevice.rear,
        );
        return picked == null ? const <XFile>[] : <XFile>[picked];
    }
  }

  void _addPickedAttachment(XFile selectedFile, _AttachmentPickAction action) {
    final path = selectedFile.path.trim();
    if (path.isEmpty) {
      return;
    }
    final exists = _attachments.any((item) => item.file.path == path);
    if (exists) {
      return;
    }
    final normalizedPath = path.replaceAll('\\', '/');
    final fallbackName = normalizedPath.split('/').last.trim();
    final fileName = selectedFile.name.trim().isEmpty
        ? (fallbackName.isEmpty ? 'attachment' : fallbackName)
        : selectedFile.name.trim();
    _attachments.add(
      _SelectedAttachment(
        file: File(path),
        name: fileName,
        type: _inferAttachmentType(path: path, action: action),
      ),
    );
  }

  void _removeAttachmentAt(int index) {
    if (index < 0 || index >= _attachments.length) {
      return;
    }
    setState(() {
      _attachments.removeAt(index);
    });
  }

  Future<bool> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted) {
      return true;
    }

    status = await Permission.camera.request();
    if (status.isGranted) {
      return true;
    }

    if (mounted) {
      _showMessage('未授予相机权限，无法拍摄');
    }
    return false;
  }

  Future<void> _onSubmit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      _showMessage('请输入反馈内容');
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) {
        return;
      }
      RiskCenter.instance.submitFeedback(
        widget.riskId,
        content: content,
        attachments: _attachments
            .map(
              (item) => RiskAttachmentPayload(
                name: item.name,
                path: item.file.path,
                type: item.type,
              ),
            )
            .toList(growable: false),
        feedbackUser: await _resolveCurrentUserName(),
      );
      _showMessage('反馈已提交');
      if (!mounted) {
        return;
      }
      context.pop();
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  String _inferAttachmentType({
    required String path,
    required _AttachmentPickAction action,
  }) {
    if (action == _AttachmentPickAction.video ||
        action == _AttachmentPickAction.cameraVideo) {
      return 'video/*';
    }
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm')) {
      return 'video/*';
    }
    return 'image/*';
  }

  bool _isVideoType(String type) {
    final lower = type.toLowerCase();
    return lower.startsWith('video/') ||
        lower.contains('mp4') ||
        lower.contains('mov') ||
        lower.contains('3gp') ||
        lower.contains('mkv') ||
        lower.contains('webm');
  }

  void _showMessage(String message) {
    AppCenterToast.show(context, message);
  }

  Future<String> _resolveCurrentUserName() async {
    if (_feedbackUser.trim().isNotEmpty && _feedbackUser != '当前用户') {
      return _feedbackUser.trim();
    }
    try {
      final dependencies = context.read<AppDependencies>();
      var info = await dependencies.authService.getCachedPermissionInfo();
      var parsed = _parseCurrentUserName(info);
      if (parsed == null || parsed.isEmpty) {
        await dependencies.authService.fetchUserProfileAndCache();
        info = await dependencies.authService.getCachedPermissionInfo();
        parsed = _parseCurrentUserName(info);
      }
      if (parsed == null || parsed.isEmpty) {
        return '当前用户';
      }
      _feedbackUser = parsed;
      return parsed;
    } catch (_) {
      return _feedbackUser.trim().isEmpty ? '当前用户' : _feedbackUser.trim();
    }
  }

  String? _parseCurrentUserName(Map<String, dynamic>? info) {
    if (info == null) {
      return null;
    }
    final permissionInfo = _asMap(info['permissionInfo']) ?? info;
    final profileInfo = _asMap(info['profileInfo']);
    final permissionData = _asMap(permissionInfo['data']) ?? permissionInfo;
    final permissionUser = _asMap(permissionData['user']) ?? permissionData;
    final profileData = _asMap(profileInfo?['data']);

    return _asText(permissionUser['nickname']) ??
        _asText(permissionUser['name']) ??
        _asText(permissionUser['username']) ??
        _asText(profileData?['nickname']) ??
        _asText(profileData?['name']) ??
        _asText(profileData?['username']);
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, data) => MapEntry(key.toString(), data));
    }
    return null;
  }

  String? _asText(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }
}

class _SelectedAttachment {
  const _SelectedAttachment({
    required this.file,
    required this.name,
    required this.type,
  });

  final File file;
  final String name;
  final String type;
}

enum _AttachmentPickAction { camera, gallery, video, cameraVideo }
