import 'package:atomic_x_core/atomicxcore.dart';

import '../barrage/barrage_store_impl.dart';
import '../device/audio_effect_store_impl.dart';
import '../gift/gift_store_impl.dart';
import 'battle_store_impl.dart';
import 'co_guest_store_impl.dart';
import 'co_host_store_impl.dart';
import 'like_store_impl.dart';
import 'live_audience_store_impl.dart';
import 'live_seat_store_impl.dart';
import 'live_summary_store_impl.dart';
import 'live_list_store_impl.dart';
import '../device/base_beauty_store_impl.dart';

abstract class IStore {
  void beforeEnterRoom(String liveID);

  void afterEnterRoom(LiveInfo liveInfo);

  void leaveRoom(String liveID);
}

class StoreFactory {
  static final StoreFactory shared = StoreFactory._();

  StoreFactory._();

  final Map<String, Map<String, IStore>> _storeMap = {};

  T getStore<T>({String liveID = ''}) {
    if (T == AudioEffectStore) {
      return AudioEffectStoreImpl.shared as T;
    }
    if (T == BaseBeautyStore) {
      return BaseBeautyStoreImpl.shared as T;
    }
    if (T == DeviceStore) {
      return DeviceStore.shared as T;
    }
    if (T == LiveListStore) {
      return LiveListStoreImpl.shared as T;
    }

    assert(liveID.isNotEmpty, 'getStore ${T.toString()} liveID is empty');

    final storeProviderMap = _storeMap.putIfAbsent(liveID, () => {});

    return storeProviderMap.putIfAbsent(T.toString(), () {
      if (T == BarrageStore) {
        return BarrageStoreImpl(liveID);
      } else if (T == BattleStore) {
        return BattleStoreImpl(liveID);
      } else if (T == CoGuestStore) {
        return CoGuestStoreImpl(liveID);
      } else if (T == CoHostStore) {
        return CoHostStoreImpl(liveID);
      } else if (T == GiftStore) {
        return GiftStoreImpl(liveID);
      } else if (T == LikeStore) {
        return LikeStoreImpl(liveID);
      } else if (T == LiveAudienceStore) {
        return LiveAudienceStoreImpl(liveID);
      } else if (T == LiveSeatStore) {
        return LiveSeatStoreImpl(liveID);
      } else if (T == LiveSummaryStore) {
        return LiveSummaryStoreImpl(liveID);
      } else {
        throw Exception('Type ${T.toString()} is not supported');
      }
    }) as T;
  }

  void beforeEnterRoom(String liveID) {
    (getStore<BattleStore>(liveID: liveID) as IStore?)?.beforeEnterRoom(liveID);
    (getStore<CoGuestStore>(liveID: liveID) as IStore?)?.beforeEnterRoom(liveID);
    (getStore<CoHostStore>(liveID: liveID) as IStore?)?.beforeEnterRoom(liveID);
    (getStore<LiveSeatStore>(liveID: liveID) as IStore?)?.beforeEnterRoom(liveID);
    (getStore<BarrageStore>(liveID: liveID) as IStore?)?.beforeEnterRoom(liveID);
    (getStore<GiftStore>(liveID: liveID) as IStore?)?.beforeEnterRoom(liveID);
    (getStore<LikeStore>(liveID: liveID) as IStore?)?.beforeEnterRoom(liveID);
    (getStore<LiveAudienceStore>(liveID: liveID) as IStore?)?.beforeEnterRoom(liveID);
    (getStore<LiveSummaryStore>(liveID: liveID) as IStore?)?.beforeEnterRoom(liveID);
  }

  void afterEnterRoom(LiveInfo liveInfo) {
    final liveStoreMap = _storeMap[liveInfo.liveID];
    liveStoreMap?.forEach((key, store) {
      store.afterEnterRoom(liveInfo);
    });
  }

  void leaveRoom(String liveID) {
    final liveStoreMap = _storeMap.remove(liveID);
    liveStoreMap?.forEach((key, store) {
      store.leaveRoom(liveID);
    });
    getStore<BaseBeautyStore>().reset();
    getStore<AudioEffectStore>().reset();
    getStore<DeviceStore>().reset();
  }

  void removeAllStores() {
    _storeMap.keys.toList().forEach((liveID) {
      leaveRoom(liveID);
    });
    _storeMap.clear();
  }
}
