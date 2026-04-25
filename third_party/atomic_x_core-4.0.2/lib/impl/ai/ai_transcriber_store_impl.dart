part of '../../api/ai/ai_transcriber_store.dart';

class _TranscriberStateImpl extends TranscriberState {
  final ValueNotifier<List<TranscriberMessage>> _realtimeMessageList = ValueNotifier([]);

  @override
  ValueListenable<List<TranscriberMessage>> get realtimeMessageList => _realtimeMessageList;
}

class _AITranscriberStoreImpl extends AITranscriberStore {
  final _TranscriberStateImpl _state = _TranscriberStateImpl();
  final Map<String, String> _userNameMap = {};
  
  manager.AITranscriberManager? _aiTranscriberManager;
  late TRTCCloudListener _trtcCloudListener;
  late manager.AITranscriberListener _aiTranscriberListener;

  Completer<CompletionHandler>? _startCompleter;
  Completer<CompletionHandler>? _updateCompleter;
  Completer<CompletionHandler>? _stopCompleter;

  _AITranscriberStoreImpl() {
    _trtcCloudListener = _getTRTCCloudListener();
    _aiTranscriberListener = _getAITranscriberListener();

    TRTCCloud.sharedInstance().then((trtcCloud) {
      _aiTranscriberManager = trtcCloud.getAITranscriberManager();

      trtcCloud.registerListener(_trtcCloudListener);
      _aiTranscriberManager!.addListener(_aiTranscriberListener);
    });
  }

  @override
  TranscriberState get transcriberState => _state;

  @override
  Future<CompletionHandler> startRealtimeTranscriber(TranscriberConfig config) async {
    DataReport.reportAtomicMetrics(AtomicMetrics.aiTranscriber);
    _startCompleter = Completer<CompletionHandler>();

    final param = _configToTRTCParam(config);
    var manager = await _getAITranscriberManager();
    manager.startRealtimeTranscriber(param);
    
    return _startCompleter!.future;
  }

  @override
  Future<CompletionHandler> updateRealtimeTranscriber(TranscriberConfig config) async {
    _updateCompleter = Completer<CompletionHandler>();
    
    _stopCompleter = Completer<CompletionHandler>();
    var manager = await _getAITranscriberManager();
    manager.stopRealtimeTranscriber("");
    
    final stopResult = await _stopCompleter!.future;
    if (stopResult.errorCode != 0) {
      _updateCompleter?.complete(stopResult);
      return _updateCompleter!.future;
    }

    final param = _configToTRTCParam(config);
    manager.startRealtimeTranscriber(param);
    
    return _updateCompleter!.future;
  }

  @override
  Future<CompletionHandler> stopRealtimeTranscriber() async {
    _stopCompleter = Completer<CompletionHandler>();
    var manager = await _getAITranscriberManager();
    manager.stopRealtimeTranscriber("");
    
    return _stopCompleter!.future;
  }

  Future<manager.AITranscriberManager> _getAITranscriberManager() async {
    if (_aiTranscriberManager == null) {
      TRTCCloud trtcCloud = await TRTCCloud.sharedInstance();
      _aiTranscriberManager = trtcCloud.getAITranscriberManager();
    }

    return _aiTranscriberManager!;
  }

  void _clearState() {
    _state._realtimeMessageList.value = [];
    _startCompleter = null;
    _updateCompleter = null;
    _stopCompleter = null;
  }

  manager.TranscriberParams _configToTRTCParam(TranscriberConfig config) {
    return manager.TranscriberParams(
      sourceLanguage: config.sourceLanguage.value,
      translationLanguages: config.translationLanguages.map((lang) => lang.value).toList(),
    );
  }

  TRTCCloudListener _getTRTCCloudListener() {
    return TRTCCloudListener(
      onExitRoom: (reason) {
        _clearState();
      }
    );
  }

  manager.AITranscriberListener _getAITranscriberListener() {
    return manager.AITranscriberListener(
      onRealtimeTranscriberError: (roomId, transcriberRobotId, error, errorInfo) {
        final handler = CompletionHandler()
          ..errorCode = error
          ..errorMessage = errorInfo;
        _startCompleter?.complete(handler);
        _updateCompleter?.complete(handler);
        _stopCompleter?.complete(handler);
        _startCompleter = null;
        _updateCompleter = null;
        _stopCompleter = null;
      },
      onRealtimeTranscriberStarted: (roomId, transcriberRobotId) {
        final handler = CompletionHandler()
          ..errorCode = 0
          ..errorMessage = '';
        _startCompleter?.complete(handler);
        _updateCompleter?.complete(handler);
        _startCompleter = null;
        _updateCompleter = null;
      },
      onRealtimeTranscriberStopped: (roomId, transcriberRobotId, reason) {
        final handler = CompletionHandler()
          ..errorCode = 0
          ..errorMessage = '';
        _stopCompleter?.complete(handler);
        _stopCompleter = null;
      },
      onReceiveTranscriberMessage: (roomId, message) {
        _handleTranscriberMessage(message);
      },
    );
  }

  void _handleTranscriberMessage(manager.TranscriberMessage message) {
    final segmentId = message.segmentId;
    if (segmentId.isEmpty) {
      return;
    }

    final sourceText = message.sourceText;
    if (sourceText.isEmpty) {
      final currentList = List<TranscriberMessage>.from(_state._realtimeMessageList.value);
      currentList.removeWhere((msg) => msg.segmentId == segmentId);
      _state._realtimeMessageList.value = currentList;
      return;
    }

    final currentList = List<TranscriberMessage>.from(_state._realtimeMessageList.value);
    final existingIndex = currentList.indexWhere((msg) => msg.segmentId == segmentId);

    if (existingIndex < 0) {
      final newMessage = _createTranscriberMessage(message);
      currentList.add(newMessage);
    } else {
      final existingMessage = currentList[existingIndex];
      final updatedMessage = _updateTranscriberMessage(existingMessage, message);
      currentList[existingIndex] = updatedMessage;
    }

    _state._realtimeMessageList.value = currentList;
  }

  TranscriberMessage _createTranscriberMessage(manager.TranscriberMessage trtcMessage) {
    final translationTexts = <TranslationLanguage, String>{};
    _updateTranslationTexts(translationTexts, trtcMessage);
    final userId = trtcMessage.speakerUserId;

    return TranscriberMessage(
      segmentId: trtcMessage.segmentId,
      speakerUserId: userId,
      speakerUserName: _getUserName(userId),
      sourceText: trtcMessage.sourceText,
      translationTexts: translationTexts,
      timestamp: trtcMessage.timestamp,
      isCompleted: trtcMessage.isCompleted,
    );
  }

  TranscriberMessage _updateTranscriberMessage(TranscriberMessage existing, manager.TranscriberMessage trtcMessage) {
    final updatedTranslationTexts = Map<TranslationLanguage, String>.from(existing.translationTexts);
    _updateTranslationTexts(updatedTranslationTexts, trtcMessage);

    return TranscriberMessage(
      segmentId: existing.segmentId,
      speakerUserId: trtcMessage.speakerUserId,
      speakerUserName: existing.speakerUserName,
      sourceText: trtcMessage.sourceText,
      translationTexts: updatedTranslationTexts,
      timestamp: trtcMessage.timestamp,
      isCompleted: trtcMessage.isCompleted,
    );
  }

  void _updateTranslationTexts(Map<TranslationLanguage, String> translationTexts, manager.TranscriberMessage trtcMessage) {
    final translationsObj = trtcMessage.translationTexts;

    for (final entry in translationsObj.entries) {
      final lang = TranslationLanguage.values.where((l) => l.value == entry.key).firstOrNull;
      if (lang != null) {
        final text = entry.value;
        if (text.isNotEmpty) {
          translationTexts[lang] = text;
        }
      }
    }
  }

  String _getUserName(String userId) {
    if (userId.isEmpty) return '';
    
    final cachedName = _userNameMap[userId];
    if (cachedName != null) {
      return cachedName;
    }
    
    _userNameMap[userId] = '';
    _fetchUserName(userId);
    return '';
  }

  Future<void> _fetchUserName(String userId) async {
    final result = await TencentImSDKPlugin.v2TIMManager.getUsersInfo(
        userIDList: [userId]
    );

    if (result.code == 0 && result.data != null && result.data!.isNotEmpty) {
      final userInfo = result.data!.first;
      final userName = userInfo.nickName ?? '';
      if (userName.isEmpty) return;

      _userNameMap[userId] = userName;

      final updatedList = _state._realtimeMessageList.value.map((msg) {
        if (msg.speakerUserId == userId) {
          return TranscriberMessage(
            segmentId: msg.segmentId,
            speakerUserId: msg.speakerUserId,
            speakerUserName: userName,
            sourceText: msg.sourceText,
            translationTexts: msg.translationTexts,
            timestamp: msg.timestamp,
            isCompleted: msg.isCompleted,
          );
        }
        return msg;
      }).toList();

      _state._realtimeMessageList.value = updatedList;
    }
  }
}
