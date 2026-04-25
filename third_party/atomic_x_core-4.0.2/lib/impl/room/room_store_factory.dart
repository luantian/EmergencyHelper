import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/impl/barrage/barrage_store_impl.dart';
import 'package:atomic_x_core/impl/live/room_engine_login.dart';
import 'package:atomic_x_core/impl/live/store_factory.dart';

import 'room_participant_store_impl.dart';
import 'room_store_impl.dart';

abstract class IStore {
  void beforeEnterRoom(String roomID);

  void afterEnterRoom(RoomInfo roomInfo);

  void leaveRoom(String roomID);
}

class RoomStoreFactory {
  static final RoomStoreFactory shared = RoomStoreFactory._();

  RoomStoreFactory._() {
    RoomEngineLogin.shared.startAutoLogin();
  }

  final Map<String, Map<String, IStore>> _storeMap = {};

  T getStore<T>({String roomID = ''}) {
    if (T == RoomStore) {
      return RoomStoreImpl.shared as T;
    }
    if (T == DeviceStore) {
      return DeviceStore.shared as T;
    }

    assert(roomID.isNotEmpty, 'getStore ${T.toString()} roomID is empty');

    final storeProviderMap = _storeMap.putIfAbsent(roomID, () => {});

    return storeProviderMap.putIfAbsent(T.toString(), () {
      if (T == RoomParticipantStore) {
        return RoomParticipantStoreImpl(roomID);
      } else {
        throw Exception('Type ${T.toString()} is not supported');
      }
    }) as T;
  }

  void beforeEnterRoom(String roomID) {
    (getStore<RoomParticipantStore>(roomID: roomID) as IStore?)?.beforeEnterRoom(roomID);
    final barrageStore = StoreFactory.shared.getStore<BarrageStore>(liveID: roomID) as BarrageStoreImpl;
    barrageStore.beforeEnterRoom(roomID);
  }

  void afterEnterRoom(RoomInfo roomInfo) {
    final roomStoreMap = _storeMap[roomInfo.roomID];
    roomStoreMap?.forEach((key, store) {
      store.afterEnterRoom(roomInfo);
    });
  }

  void leaveRoom(String roomID) {
    final roomStoreMap = _storeMap.remove(roomID);
    roomStoreMap?.forEach((key, store) {
      store.leaveRoom(roomID);
    });
    getStore<RoomStore>().reset();
    getStore<DeviceStore>().reset();

    StoreFactory.shared.leaveRoom(roomID);
  }

  void removeAllStores() {
    _storeMap.keys.toList().forEach((roomID) {
      leaveRoom(roomID);
    });
    _storeMap.clear();
  }
}
