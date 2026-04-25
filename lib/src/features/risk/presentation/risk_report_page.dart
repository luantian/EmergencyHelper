import 'dart:async';
import 'dart:io';

import 'package:emergency_helper/src/core/data/form_option_service.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/media/image_attachment_compressor.dart';
import 'package:emergency_helper/src/core/media/video_attachment_compressor.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/core/widgets/app_loading_overlay.dart';
import 'package:emergency_helper/src/features/risk/data/risk_center.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart';
import 'package:flutter_baidu_mapapi_map/flutter_baidu_mapapi_map.dart';
import 'package:flutter_baidu_mapapi_search/flutter_baidu_mapapi_search.dart';
import 'package:flutter_bmflocation/flutter_bmflocation.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

class RiskReportPage extends StatefulWidget {
  const RiskReportPage({super.key});

  @override
  State<RiskReportPage> createState() => _RiskReportPageState();
}

class _RiskReportPageState extends State<RiskReportPage> {
  final _secondaryRiskController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final ImageAttachmentCompressor _imageAttachmentCompressor =
      const ImageAttachmentCompressor();
  final VideoAttachmentCompressor _videoAttachmentCompressor =
      const VideoAttachmentCompressor();
  final FormOptionService _formOptionService = FormOptionService.instance;

  String? _relatedEvent;
  String _level = '0';
  String _type = '0';
  String _street = '三台子街道';
  String? _streetDeptIdValue;
  int? _streetDeptId;
  String _department = '--';
  int? _departmentId;
  String _reporterName = '当前用户';
  String _reportTime = '';
  final List<_SelectedAttachment> _attachments = <_SelectedAttachment>[];
  BMFCoordinate? _pickedCoordinate;
  bool _submitting = false;
  bool _compressingAttachments = false;
  List<FormOption> _relatedEventOptions = const <FormOption>[];
  List<FormOption> _levelOptions = const <FormOption>[
    FormOption(value: '0', label: '低风险'),
    FormOption(value: '1', label: '中风险'),
    FormOption(value: '2', label: '高风险'),
  ];
  List<FormOption> _typeOptions = const <FormOption>[
    FormOption(value: '0', label: '城市内涝'),
    FormOption(value: '1', label: '森林火灾'),
    FormOption(value: '2', label: '地质灾害'),
    FormOption(value: '3', label: '交通事故'),
  ];
  List<FormOption> _streetOptions = const <FormOption>[
    FormOption(value: '三台子街道', label: '三台子街道'),
    FormOption(value: '陵东街道', label: '陵东街道'),
    FormOption(value: '黄河街道', label: '黄河街道'),
    FormOption(value: '怒江街道', label: '怒江街道'),
  ];

  @override
  void initState() {
    super.initState();
    _reportTime = _formatNow(DateTime.now());
    unawaited(_loadInitialFormData());
  }

  @override
  void dispose() {
    _secondaryRiskController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('risk-report-root'),
      appBar: AppBar(
        title: const Text('\u98CE\u9669\u4E0A\u62A5'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF2F3F5),
      body: AppLoadingOverlay(
        loading: _submitting || _compressingAttachments,
        message: _submitting
            ? '\u63D0\u4EA4\u4E2D...'
            : '\u9644\u4EF6\u5904\u7406\u4E2D\uFF0C\u8BF7\u7A0D\u5019...',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          children: [
            _FormRow(
              label: '\u884D\u751F\u98CE\u9669',
              required: true,
              child: _InputBox(
                child: TextField(
                  controller: _secondaryRiskController,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF213143),
                    height: 1.2,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText:
                        '\u8BF7\u8F93\u5165\u884D\u751F\u98CE\u9669\u5185\u5BB9',
                    hintStyle: TextStyle(color: Color(0xFFA4A9B0)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _FormRow(
              label: '\u5173\u8054\u4E8B\u4EF6',
              required: true,
              child: _buildRelatedEventDropdown(),
            ),
            const SizedBox(height: 14),
            _FormRow(
              label: '\u5185\u5BB9\u63CF\u8FF0',
              required: true,
              child: _InputBox(
                child: TextField(
                  controller: _descriptionController,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF213143),
                    height: 1.2,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: '\u8BF7\u586B\u5199\u98CE\u9669\u63CF\u8FF0',
                    hintStyle: TextStyle(color: Color(0xFFA4A9B0)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _FormRow(
              label: '\u98CE\u9669\u7B49\u7EA7',
              required: true,
              child: _buildDropdown(
                value: _level,
                items: _levelOptions,
                onChanged: (value) {
                  setState(() {
                    _level = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 14),
            _FormRow(
              label: '\u98CE\u9669\u7C7B\u578B',
              required: true,
              child: _buildDropdown(
                value: _type,
                items: _typeOptions,
                onChanged: (value) {
                  setState(() {
                    _type = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 14),
            _FormRow(
              label: '\u4E0A\u62A5\u5355\u4F4D',
              required: true,
              child: _ReadOnlyBox(text: _department),
            ),
            const SizedBox(height: 14),
            _FormRow(
              label: '\u4E0A\u62A5\u65F6\u95F4',
              required: true,
              child: _ReadOnlyBox(text: _reportTime),
            ),
            const SizedBox(height: 14),
            _FormRow(
              label: '\u4E8B\u4EF6\u5730\u70B9',
              required: true,
              child: _LocationSelector(
                text: _locationController.text,
                onPick: _pickLocation,
              ),
            ),
            const SizedBox(height: 14),
            _FormRow(
              label: '\u6240\u5C5E\u8857\u9053',
              required: true,
              child: _buildDropdown(
                value: _streetDeptIdValue ?? _street,
                items: _streetOptions,
                onChanged: (value) {
                  setState(() {
                    _streetDeptIdValue = value;
                    _street = _labelFromOptions(_streetOptions, value) ?? value;
                    _streetDeptId = _asInt(value);
                  });
                },
              ),
            ),
            const SizedBox(height: 4),
            _buildAttachmentSection(),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _submitting ? null : _onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2088E8),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFB9CFEB),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  '\u63D0\u4EA4',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentSection() {
    final attachmentLabel = _attachments.isEmpty
        ? '未选择任何文件'
        : '已选择 ${_attachments.length} 个文件';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE5F1)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x100F2239),
            offset: Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '\u4E0A\u4F20\u9644\u4EF6\uFF08\u56FE\u7247\u6216\u89C6\u9891\uFF09',
            style: TextStyle(
              color: Color(0xFF1F2329),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F6FC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD2DEEC)),
                ),
                child: const Icon(
                  Icons.attach_file_rounded,
                  color: Color(0xFF6E8097),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: _submitting ? null : _pickAttachment,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(86, 34),
                        foregroundColor: const Color(0xFF2E3D52),
                        side: const BorderSide(color: Color(0xFFB8C7D9)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text(
                        '\u9009\u62E9\u6587\u4EF6',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            attachmentLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF5C6876),
                              fontSize: 13,
                            ),
                          ),
                          if (_attachments.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List<Widget>.generate(
                                _attachments.length,
                                (index) {
                                  final item = _attachments[index];
                                  return Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: 280,
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      6,
                                      6,
                                      6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF5FC),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFFD3E0F0),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _isVideoAttachment(item.type)
                                              ? Icons.videocam_rounded
                                              : Icons.image_rounded,
                                          size: 16,
                                          color: const Color(0xFF5D7898),
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF43566F),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        InkWell(
                                          onTap: _submitting
                                              ? null
                                              : () =>
                                                    _removeAttachmentAt(index),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: const Padding(
                                            padding: EdgeInsets.all(2),
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 16,
                                              color: Color(0xFF6F8096),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedEventDropdown() {
    final selectedValue =
        _relatedEventOptions.any((item) => item.value == _relatedEvent)
        ? _relatedEvent
        : null;
    return _InputBox(
      child: DropdownButtonFormField<String>(
        initialValue: selectedValue,
        isExpanded: true,
        menuMaxHeight: 340,
        borderRadius: BorderRadius.circular(12),
        dropdownColor: const Color(0xFFFBFDFF),
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF213143),
          fontWeight: FontWeight.w500,
        ),
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
          hintText: '\u8BF7\u9009\u62E9',
        ),
        icon: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFFD4E3F5)),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.expand_more_rounded,
            color: Color(0xFF2E79CA),
            size: 16,
          ),
        ),
        selectedItemBuilder: (context) {
          return _relatedEventOptions
              .map(
                (item) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1F2F43),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(growable: false);
        },
        items: _relatedEventOptions
            .map(
              (item) => DropdownMenuItem<String>(
                value: item.value,
                alignment: Alignment.centerLeft,
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2A3B4F),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: (newValue) {
          setState(() {
            _relatedEvent = newValue;
          });
        },
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<FormOption> items,
    required ValueChanged<String> onChanged,
  }) {
    final containsValue = items.any((item) => item.value == value);
    return _InputBox(
      child: DropdownButtonFormField<String>(
        initialValue: containsValue
            ? value
            : (items.isNotEmpty ? items.first.value : null),
        isExpanded: true,
        menuMaxHeight: 340,
        borderRadius: BorderRadius.circular(12),
        dropdownColor: const Color(0xFFFBFDFF),
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF213143),
          fontWeight: FontWeight.w500,
        ),
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
        icon: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFFD4E3F5)),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.expand_more_rounded,
            color: Color(0xFF2E79CA),
            size: 16,
          ),
        ),
        selectedItemBuilder: (context) {
          return items
              .map(
                (item) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1F2F43),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(growable: false);
        },
        items: items
            .map(
              (item) => DropdownMenuItem<String>(
                value: item.value,
                alignment: Alignment.centerLeft,
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2A3B4F),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: (newValue) {
          if (newValue == null) {
            return;
          }
          onChanged(newValue);
        },
      ),
    );
  }

  Future<void> _pickLocation() async {
    final picked = await showModalBottomSheet<_RiskPickedLocationResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _RiskBaiduMapPickerSheet(),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _pickedCoordinate = picked.coordinate;
      _locationController.text = picked.address;
    });
  }

  Future<void> _pickAttachment() async {
    final action = await showModalBottomSheet<_AttachmentPickAction>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
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
      ImageAttachmentCompressionResult imageCompressionResult;
      VideoAttachmentCompressionResult videoCompressionResult;
      try {
        imageCompressionResult = await _imageAttachmentCompressor
            .compressPickedFiles(filesToAppend);
        filesToAppend = imageCompressionResult.files;

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

      if (!isVideoFlow && imageCompressionResult.compressedCount > 0) {
        final summaryParts = <String>[
          '已压缩${imageCompressionResult.compressedCount}张图片',
        ];
        if (imageCompressionResult.savedBytes > 0) {
          summaryParts.add('共缩减${imageCompressionResult.savedSizeLabel}');
        }
        _showMessage(summaryParts.join('，'));
      }
      if (!isVideoFlow && imageCompressionResult.failedCount > 0) {
        _showMessage('有${imageCompressionResult.failedCount}张图片压缩失败，已使用原图');
      }
      if (!isVideoFlow && imageCompressionResult.overSizeCount > 0) {
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
    final exists = _attachments.any((item) => item.path == path);
    if (exists) {
      return;
    }
    _attachments.add(
      _SelectedAttachment(
        name: selectedFile.name,
        path: path,
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

  Future<void> _onSave() async {
    if (_secondaryRiskController.text.trim().isEmpty) {
      _showMessage('请填写衍生风险');
      return;
    }
    if ((_relatedEvent ?? '').trim().isEmpty) {
      _showMessage('请选择关联事件');
      return;
    }
    if (_descriptionController.text.trim().isEmpty) {
      _showMessage('请填写内容描述');
      return;
    }
    if (_locationController.text.trim().isEmpty) {
      _showMessage('请选择事件地点');
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) {
        return;
      }

      final relatedEventLabel = _relatedEvent == null
          ? null
          : _labelFromOptions(_relatedEventOptions, _relatedEvent!) ??
                _relatedEvent;
      final levelLabel = _labelFromOptions(_levelOptions, _level) ?? _level;
      final typeLabel = _labelFromOptions(_typeOptions, _type) ?? _type;
      final reporterName = await _resolveCurrentUserName();
      final created = RiskCenter.instance.createRisk(
        secondaryRisk: _secondaryRiskController.text.trim(),
        relatedEvent: relatedEventLabel,
        description: _descriptionController.text.trim(),
        level: levelLabel,
        type: typeLabel,
        department: _department,
        reportTime: DateTime.now(),
        location: _locationController.text.trim(),
        street: _street,
        attachments: _attachments
            .map(
              (item) => RiskAttachmentPayload(
                name: item.name,
                path: item.path,
                type: item.type,
              ),
            )
            .toList(growable: false),
        reporterName: reporterName,
      );
      if (!mounted) {
        return;
      }

      final picked = _pickedCoordinate;
      _showMessage(
        picked == null
            ? '风险已保存（演示）'
            : '已记录坐标：${picked.latitude.toStringAsFixed(6)}, '
                  '${picked.longitude.toStringAsFixed(6)}',
      );
      context.push(RoutePaths.riskDetailById(created.id));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _loadInitialFormData() async {
    await _loadReporterDepartment();
    await _loadFormOptions();
  }

  Future<void> _loadFormOptions() async {
    try {
      final dependencies = context.read<AppDependencies>();
      final relatedEventOptions = await _formOptionService.loadEventNameOptions(
        dependencies.apiClient,
      );
      final levelOptions = await _formOptionService.loadDictOptions(
        dependencies.apiClient,
        dictType: 'event_level',
      );
      final typeOptions = await _formOptionService.loadDictOptions(
        dependencies.apiClient,
        dictType: 'event_type',
      );
      final streetOptions = await _formOptionService.loadDeptOptions(
        dependencies.apiClient,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        if (relatedEventOptions.isNotEmpty) {
          _relatedEventOptions = relatedEventOptions;
          _relatedEvent ??= relatedEventOptions.first.value;
        }
        if (levelOptions.isNotEmpty) {
          _levelOptions = levelOptions;
          _level = _resolveSelectedValue(_level, _levelOptions);
        }
        if (typeOptions.isNotEmpty) {
          _typeOptions = typeOptions;
          _type = _resolveSelectedValue(_type, _typeOptions);
        }
        if (streetOptions.isNotEmpty) {
          _streetOptions = streetOptions;
          final preferredStreetValue =
              _departmentId?.toString() ?? _streetDeptIdValue ?? _street;
          _streetDeptIdValue = _resolveSelectedValue(
            preferredStreetValue,
            _streetOptions,
          );
          _street =
              _labelFromOptions(_streetOptions, _streetDeptIdValue!) ??
              _streetDeptIdValue!;
          _streetDeptId = _asInt(_streetDeptIdValue);
        }
      });
    } catch (_) {}
  }

  Future<void> _loadReporterDepartment() async {
    try {
      final dependencies = context.read<AppDependencies>();
      var info = await dependencies.authService.getCachedPermissionInfo();
      var parsed = _parseDepartment(info);
      var parsedUserName = _parseCurrentUserName(info);

      if (parsed.$1 == null || parsed.$2 == null) {
        await dependencies.authService.fetchUserProfileAndCache();
        info = await dependencies.authService.getCachedPermissionInfo();
        parsed = _parseDepartment(info);
        parsedUserName ??= _parseCurrentUserName(info);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _department = parsed.$1 ?? '--';
        _departmentId = parsed.$2;
        _reporterName = parsedUserName == null || parsedUserName.isEmpty
            ? '当前用户'
            : parsedUserName;
        _streetDeptId ??= parsed.$2;
        _streetDeptIdValue ??= parsed.$2?.toString();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _department = '--';
        _reporterName = '当前用户';
      });
    }
  }

  Future<String> _resolveCurrentUserName() async {
    if (_reporterName.trim().isNotEmpty && _reporterName != '当前用户') {
      return _reporterName.trim();
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
      return (parsed == null || parsed.isEmpty) ? '当前用户' : parsed;
    } catch (_) {
      return _reporterName.trim().isEmpty ? '当前用户' : _reporterName.trim();
    }
  }

  (String?, int?) _parseDepartment(Map<String, dynamic>? info) {
    if (info == null) {
      return (null, null);
    }

    final permissionInfo = _asMap(info['permissionInfo']) ?? info;
    final profileInfo = _asMap(info['profileInfo']);
    final permissionData = _asMap(permissionInfo['data']) ?? permissionInfo;
    final permissionUser = _asMap(permissionData['user']) ?? permissionData;
    final profileData = _asMap(profileInfo?['data']) ?? profileInfo;
    final profileUser = _asMap(profileData?['user']) ?? profileData;

    final permissionDept =
        _asMap(permissionUser['dept']) ?? _asMap(permissionData['dept']);
    final profileDept =
        _asMap(profileUser?['dept']) ?? _asMap(profileData?['dept']);

    String? textFromAny(Object? value) {
      if (value == null) {
        return null;
      }
      final map = _asMap(value);
      if (map != null && map.isNotEmpty) {
        return textFromAny(map['name']) ??
            textFromAny(map['deptName']) ??
            textFromAny(map['fullName']) ??
            textFromAny(map['orgName']) ??
            textFromAny(map['tenantName']);
      }
      if (value is List) {
        for (final item in value) {
          final text = textFromAny(item);
          if (text != null) {
            return text;
          }
        }
        return null;
      }
      if (value is String || value is num || value is bool) {
        return _asText(value);
      }
      return null;
    }

    int? idFromAny(Object? value) {
      if (value == null) {
        return null;
      }
      final map = _asMap(value);
      if (map != null && map.isNotEmpty) {
        return idFromAny(map['id']) ?? idFromAny(map['deptId']);
      }
      if (value is List) {
        for (final item in value) {
          final id = idFromAny(item);
          if (id != null) {
            return id;
          }
        }
        return null;
      }
      return _asInt(value);
    }

    String? pickFirstText(List<Object?> values) {
      for (final value in values) {
        final text = textFromAny(value);
        if (text != null) {
          return text;
        }
      }
      return null;
    }

    int? pickFirstInt(List<Object?> values) {
      for (final value in values) {
        final number = idFromAny(value);
        if (number != null) {
          return number;
        }
      }
      return null;
    }

    final deptName = pickFirstText(<Object?>[
      permissionUser['reportDeptName'],
      permissionUser['reportDept'],
      permissionUser['deptName'],
      permissionUser['deptFullName'],
      permissionData['reportDeptName'],
      permissionData['reportDept'],
      permissionData['deptName'],
      permissionData['deptFullName'],
      permissionInfo['reportDeptName'],
      permissionInfo['deptName'],
      permissionInfo['deptFullName'],
      permissionDept?['name'],
      permissionDept?['fullName'],
      profileUser?['deptName'],
      profileUser?['deptFullName'],
      profileData?['deptName'],
      profileData?['deptFullName'],
      profileDept?['name'],
      profileDept?['fullName'],
      profileInfo?['deptName'],
      profileInfo?['deptFullName'],
      permissionUser['orgName'],
      permissionData['orgName'],
      permissionInfo['orgName'],
      profileUser?['orgName'],
      profileData?['orgName'],
      profileInfo?['orgName'],
      permissionUser['tenantName'],
      permissionData['tenantName'],
      permissionInfo['tenantName'],
      profileUser?['tenantName'],
      profileData?['tenantName'],
      profileInfo?['tenantName'],
    ]);
    final deptId = pickFirstInt(<Object?>[
      permissionUser['deptId'],
      permissionData['deptId'],
      permissionInfo['deptId'],
      profileUser?['deptId'],
      profileData?['deptId'],
      profileInfo?['deptId'],
      permissionDept?['id'],
      permissionDept?['deptId'],
      profileDept?['id'],
      profileDept?['deptId'],
      permissionUser['reportDeptId'],
      permissionData['reportDeptId'],
      permissionInfo['reportDeptId'],
    ]);
    return (deptName, deptId);
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

  String _resolveSelectedValue(String current, List<FormOption> options) {
    for (final option in options) {
      if (option.value == current) {
        return current;
      }
    }
    return options.isNotEmpty ? options.first.value : current;
  }

  String? _labelFromOptions(List<FormOption> options, String value) {
    for (final option in options) {
      if (option.value == value) {
        return option.label;
      }
    }
    return null;
  }

  void _showMessage(String message) {
    AppCenterToast.show(context, message);
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

  bool _isVideoAttachment(String type) {
    final lower = type.toLowerCase();
    return lower.startsWith('video/') ||
        lower.contains('mp4') ||
        lower.contains('mov') ||
        lower.contains('3gp') ||
        lower.contains('mkv') ||
        lower.contains('webm');
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

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  String _formatNow(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    final year = value.year.toString();
    final month = two(value.month);
    final day = two(value.day);
    final hour = two(value.hour);
    final minute = two(value.minute);
    final second = two(value.second);
    return '$year-$month-$day $hour:$minute:$second';
  }
}

class _SelectedAttachment {
  const _SelectedAttachment({
    required this.name,
    required this.path,
    required this.type,
  });

  final String name;
  final String path;
  final String type;
}

enum _AttachmentPickAction { camera, gallery, video, cameraVideo }

class _RiskPickedLocationResult {
  const _RiskPickedLocationResult({
    required this.coordinate,
    required this.address,
  });

  final BMFCoordinate coordinate;
  final String address;
}

class _RiskBaiduMapPickerSheet extends StatefulWidget {
  const _RiskBaiduMapPickerSheet();

  @override
  State<_RiskBaiduMapPickerSheet> createState() =>
      _RiskBaiduMapPickerSheetState();
}

class _RiskBaiduMapPickerSheetState extends State<_RiskBaiduMapPickerSheet> {
  static final BMFCoordinate _fallbackCoordinate = BMFCoordinate(
    41.805698,
    123.431474,
  );

  final LocationFlutterPlugin _locationPlugin = LocationFlutterPlugin();
  final BMFReverseGeoCodeSearch _reverseGeoCodeSearch =
      BMFReverseGeoCodeSearch();

  BMFMapController? _mapController;
  BMFCoordinate _mapCenter = _fallbackCoordinate;
  BMFCoordinate? _selectedCoordinate;
  String _selectedAddress = '';
  String _statusText = '正在定位当前位置...';
  bool _resolvingAddress = false;
  bool _locating = false;
  String? _selectedMarkerId;

  @override
  void initState() {
    super.initState();
    _initPicker();
  }

  @override
  void dispose() {
    final markerId = _selectedMarkerId;
    final controller = _mapController;
    if (controller != null && markerId != null && markerId.isNotEmpty) {
      unawaited(controller.removeOverlay(markerId));
    }
    _selectedMarkerId = null;
    _mapController = null;
    if (Platform.isAndroid) {
      unawaited(_locationPlugin.stopLocation());
    }
    super.dispose();
  }

  Future<void> _initPicker() async {
    _reverseGeoCodeSearch.onGetReverseGeoCodeSearchResult(
      callback: (result, errorCode) {
        final currentPicked = _selectedCoordinate;
        final resultLocation = result.location;
        if (!mounted || currentPicked == null || resultLocation == null) {
          return;
        }
        if (!_sameCoordinate(currentPicked, resultLocation)) {
          return;
        }

        final address = result.address?.trim();
        setState(() {
          _resolvingAddress = false;
          _selectedAddress =
              (errorCode == BMFSearchErrorCode.NO_ERROR &&
                  address != null &&
                  address.isNotEmpty)
              ? address
              : _coordinateText(currentPicked);
          _statusText = '已选中位置';
        });
      },
    );

    if (Platform.isIOS) {
      _locationPlugin.singleLocationCallback(callback: _onLocationUpdated);
    } else {
      _locationPlugin.seriesLocationCallback(
        callback: (result) {
          _onLocationUpdated(result);
          unawaited(_locationPlugin.stopLocation());
        },
      );
    }

    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) {
      setState(() {
        _statusText = '未授予定位权限，请开启定位权限后重试';
      });
      return;
    }

    setState(() {
      _locating = true;
    });

    await _locationPlugin.setAgreePrivacy(true);

    final androidOptions = BaiduLocationAndroidOption(
      coordType: BMFLocationCoordType.bd09ll,
      locationMode: BMFLocationMode.hightAccuracy,
      locationPurpose: BMFLocationPurpose.signIn,
      scanspan: 0,
      isNeedAddress: true,
      isNeedAltitude: false,
      isNeedLocationDescribe: true,
      isNeedLocationPoiList: true,
      isNeedNewVersionRgc: true,
      openGps: true,
    );
    final iosOptions = BaiduLocationIOSOption(
      coordType: BMFLocationCoordType.bd09ll,
      BMKLocationCoordinateType: 'BMKLocationCoordinateTypeBMK09LL',
      desiredAccuracy: BMFDesiredAccuracy.best,
      isNeedNewVersionRgc: true,
      allowsBackgroundLocationUpdates: false,
    );

    await _locationPlugin.prepareLoc(
      androidOptions.getMap(),
      iosOptions.getMap(),
    );

    if (Platform.isIOS) {
      await _locationPlugin.singleLocation({
        'isReGeocode': true,
        'isNetworkState': true,
      });
    } else {
      await _locationPlugin.startLocation();
    }
  }

  Future<bool> _ensureLocationPermission() async {
    var status = await Permission.location.status;
    if (status.isGranted) {
      return true;
    }

    status = await Permission.location.request();
    return status.isGranted;
  }

  void _onLocationUpdated(BaiduLocation result) {
    final latitude = result.latitude;
    final longitude = result.longitude;
    if (!mounted || latitude == null || longitude == null) {
      return;
    }

    final coordinate = BMFCoordinate(latitude, longitude);
    final address = result.address?.trim();

    setState(() {
      _locating = false;
      _mapCenter = coordinate;
      _statusText = '已获取当前位置';
    });

    _onCoordinatePicked(coordinate, addressHint: address);
    unawaited(_centerMapTo(coordinate, animate: false));
  }

  void _onMapCreated(BMFMapController controller) {
    _mapController = controller;

    controller.setMapDidLoadCallback(
      callback: () {
        unawaited(_centerMapTo(_mapCenter, animate: false));
        final selected = _selectedCoordinate;
        if (selected != null) {
          unawaited(_refreshSelectedMarker(selected));
        }
      },
    );

    controller.setMapOnClickedMapBlankCallback(
      callback: (coordinate) {
        _onCoordinatePicked(coordinate);
      },
    );

    controller.setMapOnClickedMapPoiCallback(
      callback: (mapPoi) {
        final point = mapPoi.pt;
        if (point == null) {
          return;
        }
        _onCoordinatePicked(point, addressHint: mapPoi.text);
      },
    );
  }

  Future<void> _centerMapTo(
    BMFCoordinate coordinate, {
    required bool animate,
  }) async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    await controller.setCenterCoordinate(
      coordinate,
      animate,
      animateDurationMs: animate ? 350 : null,
    );
  }

  Future<void> _refreshSelectedMarker(BMFCoordinate coordinate) async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    final oldMarkerId = _selectedMarkerId;
    if (oldMarkerId != null) {
      await controller.removeOverlay(oldMarkerId);
    }

    final marker = BMFMarker.icon(
      icon: 'assets/images/marker.png',
      position: coordinate,
      title: '已选位置',
      canShowCallout: false,
      draggable: false,
    );

    final success = await controller.addMarker(marker);
    if (success && mounted) {
      setState(() {
        _selectedMarkerId = marker.id;
      });
    }
  }

  void _onCoordinatePicked(BMFCoordinate coordinate, {String? addressHint}) {
    final trimmedHint = addressHint?.trim() ?? '';
    setState(() {
      _selectedCoordinate = coordinate;
      _selectedAddress = trimmedHint;
      _statusText = trimmedHint.isNotEmpty ? '已选中位置' : '正在解析地址...';
      _resolvingAddress = trimmedHint.isEmpty;
    });

    unawaited(_refreshSelectedMarker(coordinate));
    unawaited(_centerMapTo(coordinate, animate: true));

    if (trimmedHint.isNotEmpty) {
      return;
    }
    unawaited(_reverseGeocode(coordinate));
  }

  Future<void> _reverseGeocode(BMFCoordinate coordinate) async {
    final ok = await _reverseGeoCodeSearch.reverseGeoCodeSearch(
      BMFReverseGeoCodeSearchOption(
        location: coordinate,
        radius: 1000,
        pageSize: 10,
        pageNum: 0,
      ),
    );

    if (!ok && mounted) {
      setState(() {
        _resolvingAddress = false;
        _selectedAddress = _coordinateText(coordinate);
        _statusText = '地址解析失败，请手动确认位置';
      });
    }
  }

  bool _sameCoordinate(BMFCoordinate a, BMFCoordinate b) {
    return (a.latitude - b.latitude).abs() < 0.000001 &&
        (a.longitude - b.longitude).abs() < 0.000001;
  }

  String _coordinateText(BMFCoordinate coordinate) {
    return '${coordinate.latitude.toStringAsFixed(6)}, ${coordinate.longitude.toStringAsFixed(6)}';
  }

  @override
  Widget build(BuildContext context) {
    final selectedAddress = _selectedAddress.trim();
    final canConfirm = _selectedCoordinate != null;
    final media = MediaQuery.of(context);
    final actionBottomPadding = media.padding.bottom > 0
        ? media.padding.bottom + 8
        : 14.0;

    return SafeArea(
      child: Container(
        height: media.size.height * 0.94,
        decoration: const BoxDecoration(
          color: Color(0xFFF3F6FB),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFCAD5E4),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD7E1EE)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x100D223C),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '选择事件地点',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E2A38),
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '点击地图任意位置完成选点',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF7A8797),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFD4DFEC)),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x130F243D),
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        BMFMapWidget(
                          onBMFMapCreated: _onMapCreated,
                          mapOptions: BMFMapOptions(
                            center: _mapCenter,
                            zoomLevel: 16,
                            showMapScaleBar: false,
                            showZoomControl: true,
                          ),
                        ),
                        const Positioned(
                          left: 2,
                          bottom: 2,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: Colors.white),
                              child: SizedBox(width: 88, height: 22),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.46),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(
                              _locating ? '定位中...' : '可拖动/缩放地图',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD3DEEB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.place_rounded,
                          size: 16,
                          color: Color(0xFF2279D8),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '已选地点地址',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF5F6D7F),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedAddress.isEmpty ? '请在地图上点击一个点位' : selectedAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        color: Color(0xFF1F2A37),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _resolvingAddress ? '正在解析地址，请稍候...' : _statusText,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF728195),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, actionBottomPadding),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: Color(0xFF97A5B5)),
                        foregroundColor: const Color(0xFF3A4756),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: canConfirm
                          ? () {
                              final coordinate = _selectedCoordinate!;
                              final address = _selectedAddress.trim().isEmpty
                                  ? _coordinateText(coordinate)
                                  : _selectedAddress.trim();
                              Navigator.of(context).pop(
                                _RiskPickedLocationResult(
                                  coordinate: coordinate,
                                  address: address,
                                ),
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: const Color(0xFF2088E8),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFB9CFEB),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '确认位置',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({
    required this.label,
    required this.required,
    required this.child,
  });

  final String label;
  final bool required;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE5F1)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x100F2239),
            offset: Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: Color(0xFF223247),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                children: [
                  if (required)
                    const TextSpan(
                      text: '* ',
                      style: TextStyle(color: Color(0xFFD9534F)),
                    ),
                  TextSpan(text: '$label:'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _InputBox extends StatelessWidget {
  const _InputBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD4DDEA)),
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

class _ReadOnlyBox extends StatelessWidget {
  const _ReadOnlyBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _InputBox(
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFF596779), fontSize: 14),
      ),
    );
  }
}

class _LocationSelector extends StatelessWidget {
  const _LocationSelector({required this.text, required this.onPick});

  final String text;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final hasValue = text.trim().isNotEmpty;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD4DDEA)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                hasValue ? text : '\u8BF7\u9009\u62E9\u4E8B\u4EF6\u5730\u70B9',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hasValue
                      ? const Color(0xFF213143)
                      : const Color(0xFF95A0AF),
                  fontSize: 14,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: SizedBox(
              width: 64,
              height: 34,
              child: ElevatedButton(
                onPressed: onPick,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2088E8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: const Text(
                  '\u9009\u62E9',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
