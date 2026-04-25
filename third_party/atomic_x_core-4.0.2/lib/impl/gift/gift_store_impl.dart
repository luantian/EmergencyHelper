import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:atomic_x_core/api/gift/gift_store.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';

import '../../api/define.dart';
import '../../api/live/live_list_store.dart';
import '../common/future_converter.dart';
import '../common/type_converter.dart';
import '../common/listener_dispatcher.dart';
import '../live/store_factory.dart';

class _GiftStateImpl implements GiftState {
  final ValueNotifier<List<GiftCategory>> usableGiftsValue = ValueNotifier([]);

  @override
  ValueListenable<List<GiftCategory>> get usableGifts => usableGiftsValue;
}

class GiftStoreImpl extends GiftStore implements IStore {
  final String liveID;
  final ListenerDispatcher<GiftListener> _listenerDispatcher = ListenerDispatcher();
  final _GiftStateImpl _giftState = _GiftStateImpl();
  final TUIRoomEngine _roomEngine = TUIRoomEngine.sharedInstance();
  late final TUILiveGiftManager _giftManager = _roomEngine.getExtension(TUIExtensionType.liveGiftManager);
  late final TUILiveGiftObserver _giftObserver;

  GiftStoreImpl(this.liveID) {
    _initObserver();
  }

  @override
  GiftState get giftState => _giftState;

  @override
  void beforeEnterRoom(String liveID) {
    _addObserver();
  }

  @override
  void afterEnterRoom(LiveInfo liveInfo) {}

  @override
  void leaveRoom(String liveID) {
    _listenerDispatcher.cleanup();
    _removeObserver();
  }

  @override
  void addGiftListener(GiftListener listener) {
    _listenerDispatcher.addListener(listener);
  }

  @override
  void removeGiftListener(GiftListener listener) {
    _listenerDispatcher.removeListener(listener);
  }

  @override
  void setLanguage(String language) async {
    Map<String, dynamic> params = {'language': language};
    Map<String, dynamic> jsonObject = {'api': 'setCurrentLanguage', 'params': params};

    try {
      final jsonString = json.encode(jsonObject);
      await TUIRoomEngine.sharedInstance().invokeExperimentalAPI(jsonString);
      // ignore: empty_catches
    } catch (e) {}
  }

  @override
  Future<CompletionHandler> refreshUsableGifts() async {
    final result = await _giftManager.getGiftList(liveID);
    final handler = handleCallback(result);
    if (result.code != TUIError.success || result.data == null) {
      return handler;
    }

    final giftCategoryList = result.data!;
    final usableGifts =
        giftCategoryList.map((engineGiftCategory) => _giftCategoryFromEngineGiftCategory(engineGiftCategory)).toList();
    _giftState.usableGiftsValue.value = usableGifts;
    return handler;
  }

  @override
  Future<CompletionHandler> sendGift({
    required String giftID,
    required int count,
  }) async {
    final result = _giftManager.sendGift(liveID, giftID, count);
    return handleCallback(result);
  }
}

extension on GiftStoreImpl {
  void _initObserver() {
    _giftObserver = TUILiveGiftObserver(onReceiveGiftMessage: (roomId, giftInfo, count, sender) {
      final gift = _giftFromEngineGiftInfo(giftInfo);
      final giftSender = TypeConverter.liveUserInfoFromEngineUserInfo(sender);
      _listenerDispatcher.notify((listener) {
        listener.onReceiveGift?.call(roomId, gift, count, giftSender);
      });
    });
  }

  void _addObserver() {
    _giftManager.addObserver(_giftObserver);
  }

  void _removeObserver() {
    _giftManager.removeObserver(_giftObserver);
  }

  GiftCategory _giftCategoryFromEngineGiftCategory(TUIGiftCategory engineGiftCategory) {
    return GiftCategory(
        categoryID: engineGiftCategory.categoryId,
        name: engineGiftCategory.name,
        desc: engineGiftCategory.desc,
        extensionInfo: engineGiftCategory.extensionInfo,
        giftList: _giftListFromEngineGiftInfoList(engineGiftCategory.giftList));
  }

  Gift _giftFromEngineGiftInfo(TUIGiftInfo giftInfo) {
    return Gift(
        giftID: giftInfo.giftId,
        name: giftInfo.name,
        desc: giftInfo.desc,
        iconURL: giftInfo.iconUrl,
        resourceURL: giftInfo.resourceUrl,
        level: giftInfo.level,
        coins: giftInfo.coins,
        extensionInfo: giftInfo.extensionInfo);
  }

  List<Gift> _giftListFromEngineGiftInfoList(List<TUIGiftInfo> giftInfoList) {
    return giftInfoList.map((giftInfo) => _giftFromEngineGiftInfo(giftInfo)).toList();
  }
}
