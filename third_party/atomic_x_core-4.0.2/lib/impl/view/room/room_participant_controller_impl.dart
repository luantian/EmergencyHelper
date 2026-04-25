part of 'package:atomic_x_core/api/view/room/room_participant_widget.dart';

class RoomParticipantControllerImpl extends RoomParticipantController with ChangeNotifier {
  final _log = Log.getRoomLog('RoomParticipantViewController');

  VideoStreamType _streamType;
  RoomParticipant _participant;
  FillMode? _fillMode;
  bool _isActive = false;
  VoidCallback? _clickAction;

  RoomParticipantControllerImpl({
    required VideoStreamType streamType,
    required RoomParticipant participant,
  })  : _streamType = streamType,
        _participant = participant {
    _log.info('RoomParticipantViewController init ${participant.userID}');
  }

  @override
  void updateStreamType(VideoStreamType streamType) {
    if (_streamType == streamType) return;
    _streamType = streamType;
    notifyListeners();
    _log.info('updateStreamType userId:${_participant.userID}, streamType:$streamType');
  }

  @override
  void updateParticipant(RoomParticipant participant) {
    _participant = participant;
    notifyListeners();
    _log.info('updateParticipant: ${participant.userID}');
  }

  @override
  void setFillMode(FillMode fillMode) {
    if (_fillMode == fillMode) return;
    _fillMode = fillMode;
    notifyListeners();
    _log.info('setFillMode userId:${_participant.userID}, fillMode:$fillMode');
  }

  @override
  void setActive(bool isActive) {
    if (_isActive == isActive) return;
    _isActive = isActive;
    notifyListeners();
    _log.info('setActive userId:${_participant.userID}, isActive:$isActive');
  }

  @override
  void setOnClickAction(VoidCallback action) {
    _clickAction = action;
    _log.info('setOnClickAction userId:${_participant.userID}');
  }
}
