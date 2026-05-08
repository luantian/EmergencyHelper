import 'dart:async';
import 'dart:io';

import 'package:emergency_helper/src/core/data/form_option_service.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/media/image_attachment_compressor.dart';
import 'package:emergency_helper/src/core/media/video_attachment_compressor.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/core/widgets/app_loading_overlay.dart';
import 'package:emergency_helper/src/features/event/data/event_center.dart';
import 'package:flutter/foundation.dart';
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

const TextStyle _formValueTextStyle = TextStyle(
  color: Color(0xFF1F2F43),
  fontSize: 14,
  fontWeight: FontWeight.w600,
  fontFamily: 'sans-serif-medium',
  height: 1.2,
);

class EventReportPage extends StatefulWidget {
  const EventReportPage({super.key});

  @override
  State<EventReportPage> createState() => _EventReportPageState();
}

class _EventReportPageState extends State<EventReportPage> {
  final _eventNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final ImageAttachmentCompressor _imageAttachmentCompressor =
      const ImageAttachmentCompressor();
  final VideoAttachmentCompressor _videoAttachmentCompressor =
      const VideoAttachmentCompressor();
  final FormOptionService _formOptionService = FormOptionService.instance;

  String _status = '0';
  String _level = '0';
  String _type = '0';
  String _street = '\u4E09\u53F0\u5B50\u8857\u9053';
  String? _streetDeptIdValue;
  int? _streetDeptId;
  String _department = '--';
  int? _departmentId;
  String _reportTime = '';
  final List<_PendingAttachment> _attachments = <_PendingAttachment>[];
  BMFCoordinate? _pickedCoordinate;
  bool _submitting = false;
  bool _compressingAttachments = false;
  List<FormOption> _statusOptions = const <FormOption>[
    FormOption(value: '0', label: '\u5904\u7406\u4E2D'),
    FormOption(value: '1', label: '\u5DF2\u529E\u7ED3'),
  ];
  List<FormOption> _levelOptions = const <FormOption>[
    FormOption(value: '0', label: 'IV\u7EA7'),
    FormOption(value: '1', label: 'III\u7EA7'),
    FormOption(value: '2', label: 'II\u7EA7'),
    FormOption(value: '3', label: 'I\u7EA7'),
  ];
  List<FormOption> _typeOptions = const <FormOption>[
    FormOption(value: '0', label: '\u57CE\u5E02\u5185\u6D9D'),
    FormOption(value: '1', label: '\u68EE\u6797\u706B\u707E'),
    FormOption(value: '2', label: '\u5730\u8D28\u707E\u5BB3'),
    FormOption(value: '3', label: '\u4EA4\u901A\u4E8B\u6545'),
    FormOption(value: '4', label: '\u5176\u4ED6'),
  ];
  List<FormOption> _streetOptions = const <FormOption>[
    FormOption(
      value: '\u4E09\u53F0\u5B50\u8857\u9053',
      label: '\u4E09\u53F0\u5B50\u8857\u9053',
    ),
    FormOption(
      value: '\u9EC4\u6CB3\u8857\u9053',
      label: '\u9EC4\u6CB3\u8857\u9053',
    ),
    FormOption(
      value: '\u5317\u5854\u8857\u9053',
      label: '\u5317\u5854\u8857\u9053',
    ),
    FormOption(
      value: '\u957F\u6C5F\u8857\u9053',
      label: '\u957F\u6C5F\u8857\u9053',
    ),
  ];

  String get _attachmentSummary {
    if (_attachments.isEmpty) {
      return '\u672A\u9009\u62E9\u4EFB\u4F55\u6587\u4EF6';
    }
    return '\u5DF2\u9009\u62E9 ${_attachments.length} \u4E2A\u6587\u4EF6';
  }

  @override
  void initState() {
    super.initState();
    _reportTime = _formatNow(DateTime.now());
    unawaited(_loadInitialFormData());
  }

  @override
  void dispose() {
    _eventNameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('event-report-root'),
      appBar: AppBar(
        title: const Text('\u4E8B\u4EF6\u4E0A\u62A5'),
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
              label: '\u4E8B\u4EF6\u540D\u79F0',
              required: true,
              child: _InputBox(
                child: TextField(
                  controller: _eventNameController,
                  textAlignVertical: TextAlignVertical.center,
                  style: _formValueTextStyle,
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: '\u8BF7\u8F93\u5165\u4E8B\u4EF6\u540D\u79F0',
                    hintStyle: TextStyle(color: Color(0xFFA4A9B0)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _FormRow(
              label: '\u4E8B\u4EF6\u72B6\u6001',
              required: true,
              child: _buildDropdown(
                value: _status,
                items: _statusOptions,
                onChanged: (value) {
                  setState(() {
                    _status = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 14),
            _FormRow(
              label: '\u5185\u5BB9\u63CF\u8FF0',
              required: true,
              child: _InputBox(
                child: TextField(
                  controller: _descriptionController,
                  textAlignVertical: TextAlignVertical.center,
                  style: _formValueTextStyle,
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: '\u8BF7\u586B\u5199\u4E8B\u4EF6\u6982\u51B5',
                    hintStyle: TextStyle(color: Color(0xFFA4A9B0)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _FormRow(
              label: '\u4E8B\u4EF6\u7B49\u7EA7',
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
              label: '\u4E8B\u4EF6\u7C7B\u578B',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                          child: Text(
                            _attachmentSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF5C6876),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_attachments.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List<Widget>.generate(_attachments.length, (
                          index,
                        ) {
                          final item = _attachments[index];
                          return Container(
                            constraints: const BoxConstraints(maxWidth: 280),
                            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
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
                                      : () => _removeAttachmentAt(index),
                                  borderRadius: BorderRadius.circular(10),
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
                        }),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
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
          color: Color(0xFF1F2F43),
          fontWeight: FontWeight.w600,
          fontFamily: 'sans-serif-medium',
        ),
        decoration: const InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
        icon: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(7),
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
                      fontFamily: 'sans-serif-medium',
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
    final picked = await showModalBottomSheet<_EventPickedLocationResult>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => const _EventBaiduMapPickerSheet(),
    );

    if (picked == null || !mounted) {
      return;
    }

    final matchedStreet = _findStreetOptionByHint(picked.streetHint);
    setState(() {
      _pickedCoordinate = picked.coordinate;
      _locationController.text = picked.address;
      if (matchedStreet != null) {
        _streetDeptIdValue = matchedStreet.value;
        _street = matchedStreet.label;
        _streetDeptId = _asInt(matchedStreet.value);
      }
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
                title: const Text('\u62CD\u7167\u4E0A\u4F20'),
                onTap: () =>
                    Navigator.of(context).pop(_AttachmentPickAction.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('\u4ECE\u76F8\u518C\u9009\u62E9'),
                onTap: () =>
                    Navigator.of(context).pop(_AttachmentPickAction.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: const Text('\u9009\u62E9\u89C6\u9891'),
                onTap: () =>
                    Navigator.of(context).pop(_AttachmentPickAction.video),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('\u62CD\u6444\u89C6\u9891'),
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
          '有${imageCompressionResult.overSizeCount}张图片仍超过8MB，建议重新选择后重试',
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
        _appendAttachments(filesToAppend);
      });
    } on MissingPluginException {
      _showMessage(
        '\u5F53\u524D\u73AF\u5883\u6682\u4E0D\u652F\u6301\u8C03\u7528\u7CFB\u7EDF\u76F8\u518C/\u76F8\u673A',
      );
    } catch (_) {
      _showMessage(
        '\u6253\u5F00\u7CFB\u7EDF\u76F8\u518C/\u76F8\u673A\u5931\u8D25\uFF0C\u8BF7\u91CD\u8BD5',
      );
    }
  }

  Future<List<XFile>> _pickAttachmentFiles(_AttachmentPickAction action) async {
    switch (action) {
      case _AttachmentPickAction.camera:
        final hasPermission = await _ensureCameraPermission();
        if (!hasPermission) {
          return const <XFile>[];
        }
        final image = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
          maxWidth: 2048,
        );
        if (image == null) {
          return const <XFile>[];
        }
        return <XFile>[image];
      case _AttachmentPickAction.gallery:
        final image = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
          maxWidth: 2048,
        );
        if (image == null) {
          return const <XFile>[];
        }
        return <XFile>[image];
      case _AttachmentPickAction.video:
        final video = await _imagePicker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(seconds: 20),
        );
        if (video == null) {
          return const <XFile>[];
        }
        return <XFile>[video];
      case _AttachmentPickAction.cameraVideo:
        final hasPermission = await _ensureCameraPermission();
        if (!hasPermission) {
          return const <XFile>[];
        }
        final captured = await _imagePicker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(seconds: 20),
          preferredCameraDevice: CameraDevice.rear,
        );
        if (captured == null) {
          return const <XFile>[];
        }
        return <XFile>[captured];
    }
  }

  void _appendAttachments(List<XFile> selectedFiles) {
    for (final selectedFile in selectedFiles) {
      final exists = _attachments.any(
        (item) => item.file.path == selectedFile.path,
      );
      if (exists) {
        continue;
      }
      _attachments.add(_PendingAttachment.fromXFile(selectedFile));
    }
  }

  void _removeAttachmentAt(int index) {
    if (index < 0 || index >= _attachments.length) {
      return;
    }
    setState(() {
      _attachments.removeAt(index);
    });
  }

  bool _isVideoAttachment(String? mimeType) {
    final normalized = (mimeType ?? '').toLowerCase();
    if (normalized.startsWith('video/')) {
      return true;
    }
    return normalized.contains('mp4') ||
        normalized.contains('mov') ||
        normalized.contains('3gp') ||
        normalized.contains('mkv') ||
        normalized.contains('webm');
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
      _showMessage(
        '\u672A\u6388\u4E88\u76F8\u673A\u6743\u9650\uFF0C\u65E0\u6CD5\u62CD\u7167',
      );
    }
    return false;
  }

  Future<void> _onSave() async {
    if (_eventNameController.text.trim().isEmpty) {
      _showMessage('\u8BF7\u586B\u5199\u4E8B\u4EF6\u540D\u79F0');
      return;
    }
    if (_descriptionController.text.trim().isEmpty) {
      _showMessage('\u8BF7\u586B\u5199\u5185\u5BB9\u63CF\u8FF0');
      return;
    }
    if (_locationController.text.trim().isEmpty) {
      _showMessage('\u8BF7\u9009\u62E9\u4E8B\u4EF6\u5730\u70B9');
      return;
    }
    if (_pickedCoordinate == null) {
      _showMessage('\u8BF7\u5728\u5730\u56FE\u4E0A\u9009\u62E9\u4E8B\u4EF6\u5730\u70B9');
      return;
    }
    final submitDeptId = _streetDeptId ?? _departmentId;
    if (submitDeptId == null || submitDeptId <= 0) {
      _showMessage('\u8BF7\u9009\u62E9\u6240\u5C5E\u8857\u9053');
      return;
    }

    setState(() {
      _submitting = true;
    });

    final dependencies = context.read<AppDependencies>();
    final uploadedAttachmentIds = <int>[];
    int? createdEventId;
    var submitSucceeded = false;
    try {
      EventCenter.instance.bindApiClient(dependencies.apiClient);

      final attachments = <EventAttachmentPayload>[];
      for (final attachment in _attachments) {
        final uploadedPayload = await EventCenter.instance
            .uploadAttachmentPayload(
              attachment.file,
              directory: 'event-report',
            );
        if (uploadedPayload == null || uploadedPayload.path.trim().isEmpty) {
          continue;
        }
        attachments.add(
          EventAttachmentPayload(
            id: uploadedPayload.id,
            name: uploadedPayload.name,
            path: uploadedPayload.path,
            type: uploadedPayload.type ?? attachment.type,
          ),
        );
        final uploadedId = uploadedPayload.id;
        if (uploadedId != null && uploadedId > 0) {
          uploadedAttachmentIds.add(uploadedId);
        }
      }

      final level = _toLevelCode(_level);
      final type = _toTypeCode(_type);
      createdEventId = await EventCenter.instance.createEvent(
        name: _eventNameController.text.trim(),
        description: _descriptionController.text.trim(),
        level: level,
        type: type,
        longitude: _pickedCoordinate!.longitude,
        latitude: _pickedCoordinate!.latitude,
        locationName: _locationController.text.trim(),
        deptId: submitDeptId,
        attachments: attachments,
      );
      submitSucceeded = true;
    } on AppException catch (error) {
      await _cleanupUploadedAttachmentIds(uploadedAttachmentIds);
      _showMessage(error.message);
    } catch (error, stackTrace) {
      await _cleanupUploadedAttachmentIds(uploadedAttachmentIds);
      dependencies.logger.error(
        'event report submit unexpected failure',
        error: error,
        stackTrace: stackTrace,
      );
      _showMessage('\u4E8B\u4EF6\u4E0A\u62A5\u5931\u8D25\uFF1A$error');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }

    if (!mounted || !submitSucceeded) {
      return;
    }
    await _handleSubmitSuccess(createdEventId);
  }

  Future<void> _handleSubmitSuccess(int? eventId) async {
    _showMessage('\u4E8B\u4EF6\u4E0A\u62A5\u6210\u529F');
    if (!mounted) {
      return;
    }
    if (eventId != null) {
      context.go(RoutePaths.eventDetailById(eventId.toString()));
      return;
    }
    context.go(RoutePaths.eventList);
  }

  Future<void> _cleanupUploadedAttachmentIds(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }
    try {
      await EventCenter.instance.deleteAttachmentIds(ids);
    } catch (_) {}
  }

  void _showMessage(String message) {
    AppCenterToast.show(context, message);
  }

  Future<void> _loadInitialFormData() async {
    await _loadReporterDepartment();
    await _loadFormOptions();
  }

  Future<void> _loadFormOptions() async {
    try {
      final dependencies = context.read<AppDependencies>();
      final statusOptions = await _formOptionService.loadDictOptions(
        dependencies.apiClient,
        dictType: 'event_status',
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
        if (statusOptions.isNotEmpty) {
          _statusOptions = statusOptions;
          _status = _resolveSelectedValue(_status, _statusOptions);
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

      if (parsed.$1 == null || parsed.$2 == null) {
        await dependencies.authService.fetchUserProfileAndCache();
        info = await dependencies.authService.getCachedPermissionInfo();
        parsed = _parseDepartment(info);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _department = parsed.$1 ?? '--';
        _departmentId = parsed.$2;
        _streetDeptId ??= parsed.$2;
        _streetDeptIdValue ??= parsed.$2?.toString();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _department = '--';
      });
    }
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

  FormOption? _findStreetOptionByHint(String? streetHint) {
    final hint = streetHint?.trim();
    if (hint == null || hint.isEmpty) {
      return null;
    }

    // 1) exact match first
    for (final option in _streetOptions) {
      if (option.label.trim() == hint || option.value.trim() == hint) {
        return option;
      }
    }

    // 2) fuzzy match in normalized tokens
    final normalizedHint = _normalizeStreetText(hint);
    if (normalizedHint.isEmpty) {
      return null;
    }
    FormOption? best;
    var bestScore = -1;
    for (final option in _streetOptions) {
      final label = _normalizeStreetText(option.label);
      final value = _normalizeStreetText(option.value);
      final score = _streetMatchScore(
        normalizedHint: normalizedHint,
        normalizedLabel: label,
        normalizedValue: value,
      );
      if (score > bestScore) {
        bestScore = score;
        best = option;
      }
    }
    return bestScore > 0 ? best : null;
  }

  String _normalizeStreetText(String value) {
    var text = value.trim();
    text = text.replaceAll(RegExp(r'\s+'), '');
    text = text.replaceAll('（', '(').replaceAll('）', ')');
    text = text.replaceAll('街道办事处', '街道');
    text = text.replaceAll('镇人民政府', '镇');
    return text;
  }

  int _streetMatchScore({
    required String normalizedHint,
    required String normalizedLabel,
    required String normalizedValue,
  }) {
    var score = 0;
    if (normalizedLabel == normalizedHint || normalizedValue == normalizedHint) {
      return 200;
    }
    if (normalizedLabel.isNotEmpty &&
        (normalizedLabel.contains(normalizedHint) ||
            normalizedHint.contains(normalizedLabel))) {
      score = score > 120 ? score : 120;
    }
    if (normalizedValue.isNotEmpty &&
        (normalizedValue.contains(normalizedHint) ||
            normalizedHint.contains(normalizedValue))) {
      score = score > 110 ? score : 110;
    }
    final hintTokens = _streetTokens(normalizedHint);
    for (final token in hintTokens) {
      if (token.length < 2) {
        continue;
      }
      if (normalizedLabel.contains(token)) {
        score += 8;
      } else if (normalizedValue.contains(token)) {
        score += 6;
      }
    }
    return score;
  }

  List<String> _streetTokens(String value) {
    final separators = RegExp(r'[省市区县旗镇乡街道办事处路号村社区组]');
    return value
        .split(separators)
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
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

  int _toLevelCode(String value) {
    final parsed = _asInt(value);
    if (parsed != null) {
      return parsed;
    }
    if (value.contains('IV')) {
      return 0;
    }
    if (value.contains('III')) {
      return 1;
    }
    if (value.contains('II')) {
      return 2;
    }
    return 3;
  }

  int _toTypeCode(String value) {
    final parsed = _asInt(value);
    if (parsed != null) {
      return parsed;
    }
    for (var index = 0; index < _typeOptions.length; index += 1) {
      if (_typeOptions[index].label == value) {
        return index;
      }
    }
    if (_typeOptions.isEmpty) {
      return 0;
    }
    return _asInt(_typeOptions.first.value) ?? 0;
  }
}

class _PendingAttachment {
  const _PendingAttachment({required this.file, required this.name, this.type});

  final File file;
  final String name;
  final String? type;

  factory _PendingAttachment.fromXFile(XFile selectedFile) {
    final originalName = selectedFile.name.trim();
    final fileName = originalName.isEmpty
        ? _fileNameFromPath(selectedFile.path)
        : originalName;
    return _PendingAttachment(
      file: File(selectedFile.path),
      name: fileName,
      type: _guessType(fileName, selectedFile.mimeType),
    );
  }

  static String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    final last = segments.isEmpty ? '' : segments.last.trim();
    return last.isEmpty ? 'attachment' : last;
  }

  static String? _guessType(String fileName, String? mimeType) {
    final normalizedMime = mimeType?.trim();
    if (normalizedMime != null && normalizedMime.isNotEmpty) {
      return normalizedMime;
    }

    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    if (lower.endsWith('.mp4')) {
      return 'video/mp4';
    }
    if (lower.endsWith('.mov')) {
      return 'video/quicktime';
    }
    if (lower.endsWith('.mkv')) {
      return 'video/x-matroska';
    }
    if (lower.endsWith('.3gp')) {
      return 'video/3gpp';
    }
    if (lower.endsWith('.webm')) {
      return 'video/webm';
    }
    return null;
  }
}

enum _AttachmentPickAction { camera, gallery, video, cameraVideo }

class _EventPickedLocationResult {
  const _EventPickedLocationResult({
    required this.coordinate,
    required this.address,
    this.streetHint,
  });

  final BMFCoordinate coordinate;
  final String address;
  final String? streetHint;
}

class _EventBaiduMapPickerSheet extends StatefulWidget {
  const _EventBaiduMapPickerSheet();

  @override
  State<_EventBaiduMapPickerSheet> createState() =>
      _EventBaiduMapPickerSheetState();
}

class _EventBaiduMapPickerSheetState extends State<_EventBaiduMapPickerSheet> {
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
  String? _selectedStreetHint;
  String _statusText = '正在定位当前位置...';
  bool _resolvingAddress = false;
  bool _locating = false;
  bool _locationServiceMaybeDisabled = false;
  bool _serviceDialogShown = false;
  Timer? _locatingTimeoutTimer;
  int _coordinatePickEpoch = 0;
  String _addressPoiName = '';

  @override
  void initState() {
    super.initState();
    _initPicker();
  }

  @override
  void dispose() {
    _stopLocatingTimeoutGuard();
    _mapController = null;
    if (Platform.isAndroid) {
      unawaited(_locationPlugin.stopLocation());
    }
    super.dispose();
  }

  Future<void> _initPicker() async {
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

    final locationReady = await _ensureLocationReady();
    if (!locationReady) {
      return;
    }
    _serviceDialogShown = false;
    _stopLocatingTimeoutGuard();

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

    final started = Platform.isIOS
        ? await _locationPlugin.singleLocation({
        'isReGeocode': true,
        'isNetworkState': true,
      })
        : await _locationPlugin.startLocation();
    if (!started) {
      if (mounted) {
        setState(() {
          _locating = false;
          _statusText = '定位启动失败，请检查定位服务';
        });
      }
      if (_locationServiceMaybeDisabled) {
        await _maybeShowLocationServiceDialog();
      }
      return;
    }
    _startLocatingTimeoutGuard();
  }

  Future<bool> _ensureLocationReady() async {
    var status = await Permission.location.status;
    if (!(status.isGranted || status.isLimited)) {
      status = await Permission.location.request();
    }
    if (!(status.isGranted || status.isLimited)) {
      await _showLocationPermissionDialog(status);
      if (mounted) {
        setState(() {
          _statusText = '定位权限未开启，请授权后重试';
        });
      }
      return false;
    }

    final serviceStatus = await Permission.location.serviceStatus;
    _locationServiceMaybeDisabled =
        serviceStatus != ServiceStatus.enabled &&
        serviceStatus != ServiceStatus.notApplicable;

    return true;
  }

  Future<void> _maybeShowLocationServiceDialog() async {
    if (_serviceDialogShown) {
      return;
    }
    _serviceDialogShown = true;
    await _showLocationServiceDialog();
  }

  Future<void> _showLocationPermissionDialog(PermissionStatus status) async {
    if (!mounted) {
      return;
    }
    final permanentlyDenied = status.isPermanentlyDenied || status.isRestricted;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('需要定位权限'),
          content: Text(
            permanentlyDenied
                ? '定位权限已被禁止，请前往设置开启权限后再试。'
                : '请先允许定位权限，用于自动定位当前位置。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await openAppSettings();
              },
              child: const Text('去设置'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLocationServiceDialog() async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('请开启定位服务'),
          content: const Text('系统定位服务未开启，开启后可自动定位当前位置。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await openAppSettings();
              },
              child: const Text('去设置'),
            ),
          ],
        );
      },
    );
  }

  void _onLocationUpdated(BaiduLocation result) {
    final latitude = result.latitude;
    final longitude = result.longitude;
    if (!mounted || latitude == null || longitude == null) {
      return;
    }
    _stopLocatingTimeoutGuard();

    final coordinate = BMFCoordinate(latitude, longitude);
    final address = result.address?.trim();

    setState(() {
      _locating = false;
      _mapCenter = coordinate;
      _statusText = '已定位当前位置';
    });

    _onCoordinatePicked(coordinate, addressHint: address);
    unawaited(_centerMapTo(coordinate, animate: false));
  }

  void _startLocatingTimeoutGuard() {
    _stopLocatingTimeoutGuard();
    _locatingTimeoutTimer = Timer(const Duration(seconds: 8), () async {
      if (!mounted || !_locating) {
        return;
      }
      setState(() {
        _locating = false;
        _statusText = '定位超时，请手动选择位置';
      });
      if (_locationServiceMaybeDisabled) {
        await _maybeShowLocationServiceDialog();
      }
    });
  }

  void _stopLocatingTimeoutGuard() {
    _locatingTimeoutTimer?.cancel();
    _locatingTimeoutTimer = null;
  }

  void _onMapCreated(BMFMapController controller) {
    _mapController = controller;

    controller.setMapDidLoadCallback(
      callback: () {
        unawaited(_centerMapTo(_mapCenter, animate: false));
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

  void _onCoordinatePicked(BMFCoordinate coordinate, {String? addressHint}) {
    _coordinatePickEpoch++;
    final trimmedHint = addressHint?.trim() ?? '';
    final streetHint = _extractStreetHintFromAddress(trimmedHint);
    final needReverse = streetHint == null;
    setState(() {
      _selectedCoordinate = coordinate;
      _selectedStreetHint = streetHint;
      _addressPoiName = trimmedHint;
      _selectedAddress = '';
      _statusText =
          needReverse
              ? '正在解析地址...'
              : (trimmedHint.isNotEmpty ? '地址已选中' : '已选中位置');
      _resolvingAddress = needReverse;
    });
    if (needReverse) {
      unawaited(_reverseGeocode(coordinate, fallbackAddress: trimmedHint));
    }
  }

  Future<void> _reverseGeocode(
    BMFCoordinate coordinate, {
    String? fallbackAddress,
  }) async {
    final thisEpoch = _coordinatePickEpoch;
    final resolvedCompleter = Completer<BMFReverseGeoCodeSearchResult?>();
    _reverseGeoCodeSearch.onGetReverseGeoCodeSearchResult(
      callback: (result, errorCode) {
        debugPrint('[GEO-DEBUG] callback fired: errorCode=$errorCode, result.location=${result?.location?.latitude.toStringAsFixed(4)}, result.address=${result?.address}');
        if (thisEpoch != _coordinatePickEpoch) {
          debugPrint('[GEO-DEBUG] callback: epoch mismatch, ignoring (thisEpoch=$thisEpoch, current=$_coordinatePickEpoch)');
          return;
        }
        final loc = result.location;
        if (loc == null) {
          debugPrint('[GEO-DEBUG] callback: result.location is null');
          return;
        }
        if (!_sameCoordinate(coordinate, loc)) {
          debugPrint('[GEO-DEBUG] callback: coordinate mismatch, ignoring');
          return;
        }
        if (errorCode == BMFSearchErrorCode.NO_ERROR) {
          debugPrint('[GEO-DEBUG] callback: NO_ERROR, completing with result');
          resolvedCompleter.complete(result);
        } else {
          debugPrint('[GEO-DEBUG] callback: error code $errorCode, completing with error');
          resolvedCompleter.completeError('解析失败: $errorCode');
        }
      },
    );

    final ok = await _reverseGeoCodeSearch.reverseGeoCodeSearch(
      BMFReverseGeoCodeSearchOption(
        location: coordinate,
        radius: 1000,
        pageSize: 10,
        pageNum: 0,
      ),
    );
    debugPrint('[GEO-DEBUG] reverseGeoCodeSearch returned: ok=$ok, coord=(${coordinate.latitude.toStringAsFixed(4)}, ${coordinate.longitude.toStringAsFixed(4)})');
    if (!ok) {
      debugPrint('[GEO-DEBUG] reverseGeoCodeSearch failed immediately, falling back');
      if (mounted && thisEpoch == _coordinatePickEpoch) {
        _applyReverseGeoFallback(coordinate, fallbackAddress);
      }
      return;
    }

    try {
      final result = await resolvedCompleter.future.timeout(
        const Duration(seconds: 10),
      );
      if (!mounted || thisEpoch != _coordinatePickEpoch) {
        return;
      }
      final resolvedAddress = result?.address?.trim();
      final streetHint = _extractStreetHint(
        result?.addressDetail,
        resolvedAddress,
      );
      setState(() {
        _resolvingAddress = false;
        _selectedStreetHint = streetHint;
        if (resolvedAddress != null && resolvedAddress.isNotEmpty) {
          _selectedAddress = resolvedAddress;
        } else {
          _applyFallbackAddress(coordinate, fallbackAddress);
        }
        _addressPoiName = '';
        _statusText = '地址已选中';
      });
    } catch (e) {
      debugPrint('[GEO-DEBUG] caught exception: $e');
      if (mounted && thisEpoch == _coordinatePickEpoch) {
        _applyReverseGeoFallback(coordinate, fallbackAddress);
      }
    }
  }

  void _applyFallbackAddress(
    BMFCoordinate coordinate,
    String? fallbackAddress,
  ) {
    final fallback = fallbackAddress?.trim() ?? '';
    _selectedAddress = fallback.isNotEmpty
        ? fallback
        : _coordinateText(coordinate);
  }

  void _applyReverseGeoFallback(
    BMFCoordinate coordinate,
    String? fallbackAddress,
  ) {
    final fallback = fallbackAddress?.trim() ?? '';
    setState(() {
      _resolvingAddress = false;
      _addressPoiName = '';
      _selectedAddress = fallback.isNotEmpty
          ? fallback
          : _coordinateText(coordinate);
      _statusText = '地址解析失败，请确认网络后重试';
    });
  }

  bool _sameCoordinate(BMFCoordinate a, BMFCoordinate b) {
    return (a.latitude - b.latitude).abs() < 0.000001 &&
        (a.longitude - b.longitude).abs() < 0.000001;
  }

  String _coordinateText(BMFCoordinate coordinate) {
    return '${coordinate.latitude.toStringAsFixed(6)}, ${coordinate.longitude.toStringAsFixed(6)}';
  }

  String _buildDisplayAddressText(String resolvedAddress) {
    final poi = _addressPoiName.trim();
    if (resolvedAddress.isEmpty && poi.isEmpty) {
      return '请在地图上点击一个点位';
    }
    if (resolvedAddress.isNotEmpty && poi.isNotEmpty) {
      return '$resolvedAddress（$poi）';
    }
    if (resolvedAddress.isNotEmpty) {
      return resolvedAddress;
    }
    if (poi.isNotEmpty) {
      return poi;
    }
    return '请在地图上点击一个点位';
  }

  String? _extractStreetHint(dynamic addressDetail, String? fullAddress) {
    if (addressDetail == null) {
      return _extractStreetHintFromAddress(fullAddress ?? '');
    }
    String? normalize(dynamic value) {
      if (value == null) {
        return null;
      }
      final text = value.toString().trim();
      if (text.isEmpty || text == 'null') {
        return null;
      }
      return text;
    }

    final town = normalize(addressDetail.town);
    if (town != null) {
      return town;
    }
    return normalize(addressDetail.streetName) ??
        _extractStreetHintFromAddress(fullAddress ?? '');
  }

  String? _extractStreetHintFromAddress(String address) {
    final text = address.trim();
    if (text.isEmpty) {
      return null;
    }
    final match = RegExp(
      r'([\u4E00-\u9FFFA-Za-z0-9]{2,20}(?:街道|镇|乡))',
    ).firstMatch(text);
    if (match == null) {
      return null;
    }
    return match.group(1)?.trim();
  }

  @override
  Widget build(BuildContext context) {
    final selectedAddress = _selectedAddress.trim();
    final displayAddress = _buildDisplayAddressText(selectedAddress);
    final canConfirm = _selectedCoordinate != null && !_resolvingAddress;
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
                      displayAddress,
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
                      _resolvingAddress ? '正在解析地址...' : _statusText,
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
                                _EventPickedLocationResult(
                                  coordinate: coordinate,
                                  address: address,
                                  streetHint: _selectedStreetHint,
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
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFCDD7E4), width: 1),
      ),
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
        style: _formValueTextStyle,
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
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFCDD7E4), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                hasValue ? text : '请选择事件地点',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hasValue
                      ? const Color(0xFF1F2F43)
                      : const Color(0xFF95A0AF),
                  fontSize: 14,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                  fontFamily: hasValue ? 'sans-serif-medium' : null,
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
                  '选择',
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
