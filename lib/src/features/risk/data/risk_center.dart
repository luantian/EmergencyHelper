import 'package:flutter/foundation.dart';

enum RiskProcessStatus { processing, finished }

extension RiskProcessStatusX on RiskProcessStatus {
  String get label {
    switch (this) {
      case RiskProcessStatus.processing:
        return '处理中';
      case RiskProcessStatus.finished:
        return '已办结';
    }
  }
}

class RiskTimelineItem {
  RiskTimelineItem({
    required this.time,
    required this.stage,
    this.content,
    this.operatorName,
    this.receiverNames,
    this.attachmentName,
    this.attachmentPath,
    this.attachmentType,
    this.attachments = const <RiskAttachmentPayload>[],
  });

  final DateTime time;
  final String stage;
  final String? content;
  final String? operatorName;
  final String? receiverNames;
  final String? attachmentName;
  final String? attachmentPath;
  final String? attachmentType;
  final List<RiskAttachmentPayload> attachments;
}

class RiskAttachmentPayload {
  const RiskAttachmentPayload({
    required this.name,
    required this.path,
    this.type,
  });

  final String name;
  final String path;
  final String? type;
}

class RiskRecord {
  RiskRecord({
    required this.id,
    required this.secondaryRisk,
    required this.description,
    required this.status,
    required this.level,
    required this.type,
    required this.department,
    required this.reportTime,
    required this.location,
    required this.street,
    required this.timeline,
    this.attachments = const <RiskAttachmentPayload>[],
    this.relatedEvent,
    this.attachmentName,
    this.attachmentPath,
    this.attachmentType,
  });

  final String id;
  final String secondaryRisk;
  final String? relatedEvent;
  final String description;
  RiskProcessStatus status;
  final String level;
  final String type;
  final String department;
  final DateTime reportTime;
  final String location;
  final String street;
  final List<RiskTimelineItem> timeline;
  List<RiskAttachmentPayload> attachments;
  String? attachmentName;
  String? attachmentPath;
  String? attachmentType;
}

class RiskCenter extends ChangeNotifier {
  RiskCenter._() {
    _risks.addAll(_buildSeedRisks());
  }

  static final RiskCenter instance = RiskCenter._();

  final List<RiskRecord> _risks = <RiskRecord>[];

  void resetSessionData({bool notify = true}) {
    _risks
      ..clear()
      ..addAll(_buildSeedRisks());
    if (notify) {
      notifyListeners();
    }
  }

  List<RiskRecord> queryRisks({
    required RiskProcessStatus status,
    String keyword = '',
  }) {
    final normalizedKeyword = keyword.trim();
    final result = _risks.where((risk) {
      if (risk.status != status) {
        return false;
      }
      if (normalizedKeyword.isEmpty) {
        return true;
      }
      return risk.secondaryRisk.contains(normalizedKeyword) ||
          risk.description.contains(normalizedKeyword) ||
          risk.location.contains(normalizedKeyword) ||
          (risk.relatedEvent ?? '').contains(normalizedKeyword);
    }).toList(growable: false)
      ..sort((a, b) => b.reportTime.compareTo(a.reportTime));

    return List<RiskRecord>.unmodifiable(result);
  }

  RiskRecord? riskById(String riskId) {
    for (final risk in _risks) {
      if (risk.id == riskId) {
        return risk;
      }
    }
    return null;
  }

  RiskRecord createRisk({
    required String secondaryRisk,
    String? relatedEvent,
    required String description,
    required String level,
    required String type,
    required String department,
    required DateTime reportTime,
    required String location,
    required String street,
    String? attachmentName,
    String? attachmentPath,
    String? attachmentType,
    List<RiskAttachmentPayload> attachments = const <RiskAttachmentPayload>[],
    String reporterName = '当前用户',
  }) {
    final now = DateTime.now();
    final safeRelatedEvent = relatedEvent?.trim();
    final normalizedReporter = _normalizeOperatorName(reporterName);
    final normalizedAttachments = _normalizeAttachments(
      attachments,
      fallbackName: attachmentName,
      fallbackPath: attachmentPath,
      fallbackType: attachmentType,
    );
    final firstAttachment = _firstAttachment(normalizedAttachments);

    final record = RiskRecord(
      id: 'risk_${now.microsecondsSinceEpoch}',
      secondaryRisk: secondaryRisk.trim(),
      relatedEvent: safeRelatedEvent == null || safeRelatedEvent.isEmpty
          ? null
          : safeRelatedEvent,
      description: description.trim(),
      status: RiskProcessStatus.processing,
      level: level,
      type: type,
      department: department,
      reportTime: reportTime,
      location: location.trim(),
      street: street,
      attachments: normalizedAttachments,
      attachmentName: firstAttachment?.name,
      attachmentPath: firstAttachment?.path,
      attachmentType: firstAttachment?.type,
      timeline: <RiskTimelineItem>[
        RiskTimelineItem(
          time: now,
          stage: '已上报',
          content: description.trim(),
          operatorName: normalizedReporter,
          attachmentName: firstAttachment?.name,
          attachmentPath: firstAttachment?.path,
          attachmentType: firstAttachment?.type,
          attachments: normalizedAttachments,
        ),
      ],
    );

    _risks.insert(0, record);
    notifyListeners();
    return record;
  }

  void submitFeedback(
    String riskId, {
    required String content,
    String? attachmentName,
    String? attachmentPath,
    String? attachmentType,
    List<RiskAttachmentPayload> attachments = const <RiskAttachmentPayload>[],
    String feedbackUser = '当前用户',
  }) {
    final risk = riskById(riskId);
    if (risk == null) {
      return;
    }

    risk.status = RiskProcessStatus.processing;
    final normalizedAttachments = _normalizeAttachments(
      attachments,
      fallbackName: attachmentName,
      fallbackPath: attachmentPath,
      fallbackType: attachmentType,
    );
    if (normalizedAttachments.isNotEmpty) {
      risk.attachments = _mergeAttachmentsUnique(
        risk.attachments,
        normalizedAttachments,
      );
      final first = _firstAttachment(risk.attachments);
      risk.attachmentName = first?.name;
      risk.attachmentPath = first?.path;
      risk.attachmentType = first?.type;
    }

    risk.timeline.insert(
      0,
      RiskTimelineItem(
        time: DateTime.now(),
        stage: '已反馈',
        content: content.trim(),
        operatorName: _normalizeOperatorName(feedbackUser),
        attachmentName: _firstAttachment(normalizedAttachments)?.name,
        attachmentPath: _firstAttachment(normalizedAttachments)?.path,
        attachmentType: _firstAttachment(normalizedAttachments)?.type,
        attachments: normalizedAttachments,
      ),
    );
    notifyListeners();
  }

  void transfer(
    String riskId, {
    String transferUser = '当前用户',
    String receiverNames = '待指派',
    String content = '已转派，请尽快处置',
  }) {
    final risk = riskById(riskId);
    if (risk == null || risk.status == RiskProcessStatus.finished) {
      return;
    }

    final normalizedReceivers =
        receiverNames.trim().isEmpty ? '待指派' : receiverNames.trim();

    risk.timeline.insert(
      0,
      RiskTimelineItem(
        time: DateTime.now(),
        stage: '已转派',
        content: content.trim(),
        operatorName: _normalizeOperatorName(transferUser),
        receiverNames: normalizedReceivers,
      ),
    );
    notifyListeners();
  }

  void finish(String riskId, {String finisher = '当前用户'}) {
    final risk = riskById(riskId);
    if (risk == null) {
      return;
    }

    risk.status = RiskProcessStatus.finished;
    risk.timeline.insert(
      0,
      RiskTimelineItem(
        time: DateTime.now(),
        stage: '已办结',
        operatorName: _normalizeOperatorName(finisher),
      ),
    );
    notifyListeners();
  }

  String _normalizeOperatorName(String? name) {
    final text = (name ?? '').trim();
    return text.isEmpty ? '当前用户' : text;
  }

  List<RiskAttachmentPayload> _normalizeAttachments(
    List<RiskAttachmentPayload> attachments, {
    String? fallbackName,
    String? fallbackPath,
    String? fallbackType,
  }) {
    final result = <RiskAttachmentPayload>[];
    final unique = <String>{};

    for (final item in attachments) {
      final name = item.name.trim();
      final path = item.path.trim();
      if (name.isEmpty || path.isEmpty) {
        continue;
      }
      final key = '$name|$path';
      if (unique.add(key)) {
        result.add(
          RiskAttachmentPayload(name: name, path: path, type: item.type?.trim()),
        );
      }
    }

    final fallbackPathText = (fallbackPath ?? '').trim();
    if (fallbackPathText.isNotEmpty) {
      final fallbackNameText = (fallbackName ?? '').trim().isEmpty
          ? fallbackPathText.split('/').last
          : (fallbackName ?? '').trim();
      final fallbackKey = '$fallbackNameText|$fallbackPathText';
      if (unique.add(fallbackKey)) {
        result.add(
          RiskAttachmentPayload(
            name: fallbackNameText,
            path: fallbackPathText,
            type: fallbackType?.trim(),
          ),
        );
      }
    }

    return List<RiskAttachmentPayload>.unmodifiable(result);
  }

  List<RiskAttachmentPayload> _mergeAttachmentsUnique(
    List<RiskAttachmentPayload> base,
    List<RiskAttachmentPayload> extra,
  ) {
    final result = <RiskAttachmentPayload>[];
    final unique = <String>{};
    for (final item in <RiskAttachmentPayload>[...base, ...extra]) {
      final key = '${item.name}|${item.path}';
      if (unique.add(key)) {
        result.add(item);
      }
    }
    return List<RiskAttachmentPayload>.unmodifiable(result);
  }

  RiskAttachmentPayload? _firstAttachment(List<RiskAttachmentPayload> attachments) {
    return attachments.isEmpty ? null : attachments.first;
  }

  List<RiskRecord> _buildSeedRisks() {
    final list = <RiskRecord>[];
    final listTime = DateTime(2025, 2, 2, 15, 55, 55);
    final detailTime = DateTime(2024, 7, 29, 14, 30, 23);

    RiskRecord create({
      required String id,
      required RiskProcessStatus status,
      required DateTime reportTime,
      String? relatedEvent,
    }) {
      const description = '该区域临近商业区与地铁站，地下老旧管网较多，需持续关注衍生风险。';
      final timeline = <RiskTimelineItem>[
        RiskTimelineItem(
          time: reportTime,
          stage: '已上报',
          content: description,
          operatorName: '系统',
        ),
      ];

      if (status == RiskProcessStatus.processing) {
        timeline.insert(
          0,
          RiskTimelineItem(
            time: DateTime(2025, 2, 19, 15, 35, 22),
            stage: '已反馈',
            content: '现场已设置警戒线，正在组织处置。',
            operatorName: '系统',
            attachmentName: '现场照片.jpg',
          ),
        );
        timeline.insert(
          0,
          RiskTimelineItem(
            time: DateTime(2025, 2, 20, 15, 35, 22),
            stage: '已转派',
            content: '请属地与行业部门联合处置。',
            operatorName: '系统',
            receiverNames: '张伟、李强、王芳',
          ),
        );
      } else {
        timeline.insert(
          0,
          RiskTimelineItem(
            time: DateTime(2025, 2, 20, 15, 35, 22),
            stage: '已办结',
            operatorName: '系统',
          ),
        );
      }

      return RiskRecord(
        id: id,
        secondaryRisk: '发生墙皮开裂',
        relatedEvent: relatedEvent,
        description: description,
        status: status,
        level: '低风险',
        type: '城市运行',
        department: '三台子街道',
        reportTime: reportTime,
        location: '沈阳市皇姑区昆山中路与怒江街交叉口北行50米处',
        street: '三台子街道',
        timeline: timeline,
      );
    }

    for (var i = 0; i < 6; i++) {
      list.add(
        create(
          id: 'risk_processing_$i',
          status: RiskProcessStatus.processing,
          reportTime: listTime.subtract(Duration(hours: i * 3)),
          relatedEvent: i.isEven ? '示例关联事件' : null,
        ),
      );
    }

    for (var i = 0; i < 4; i++) {
      list.add(
        create(
          id: 'risk_finished_$i',
          status: RiskProcessStatus.finished,
          reportTime: detailTime.subtract(Duration(days: i + 1)),
          relatedEvent: null,
        ),
      );
    }

    return list;
  }
}
