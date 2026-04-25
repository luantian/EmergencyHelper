import 'dart:async';
import 'dart:convert';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/impl/common/future_converter.dart';
import 'package:flutter/foundation.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:tencent_rtc_sdk/trtc_cloud.dart';
import 'package:tencent_rtc_sdk/trtc_cloud_listener.dart';
import 'package:tencent_rtc_sdk/ai_transcriber_manager.dart' as manager;
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:atomic_x_core/impl/common/data_report.dart';

part '../../impl/ai/ai_transcriber_store_impl.dart';

enum SourceLanguage {
  chineseEnglish('zh_en'),
  chinese('zh'),
  english('en');

  final String value;
  const SourceLanguage(this.value);
}

enum TranslationLanguage {
  chinese('zh'),
  english('en'),
  vietnamese('vi'),
  japanese('ja'),
  korean('ko'),
  indonesian('id'),
  thai('th'),
  portuguese('pt'),
  arabic('ar'),
  spanish('es'),
  french('fr'),
  malay('ms'),
  german('de'),
  italian('it'),
  russian('ru');

  final String value;
  const TranslationLanguage(this.value);
}

class TranscriberMessage {
  final String segmentId;
  String speakerUserId;
  String speakerUserName;
  String sourceText;
  final Map<TranslationLanguage, String> translationTexts;
  int timestamp;
  bool isCompleted;

  TranscriberMessage({
    required this.segmentId,
    this.speakerUserId = '',
    this.speakerUserName = '',
    this.sourceText = '',
    Map<TranslationLanguage, String>? translationTexts,
    this.timestamp = 0,
    this.isCompleted = false,
  }) : translationTexts = translationTexts ?? {};
}

class TranscriberConfig {
  SourceLanguage sourceLanguage;
  final List<TranslationLanguage> translationLanguages;

  TranscriberConfig({
    this.sourceLanguage = SourceLanguage.chineseEnglish,
    List<TranslationLanguage>? translationLanguages,
  }) : translationLanguages = translationLanguages ?? [];
}

abstract class TranscriberState {
  ValueListenable<List<TranscriberMessage>> get realtimeMessageList;
}

abstract class AITranscriberStore {
  static final AITranscriberStore _instance = _AITranscriberStoreImpl();

  static AITranscriberStore get shared => _instance;

  TranscriberState get transcriberState;

  Future<CompletionHandler> startRealtimeTranscriber(TranscriberConfig config);

  Future<CompletionHandler> updateRealtimeTranscriber(TranscriberConfig config);

  Future<CompletionHandler> stopRealtimeTranscriber();
}
