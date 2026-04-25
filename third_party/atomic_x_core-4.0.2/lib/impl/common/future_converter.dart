import 'package:rtc_room_engine/rtc_room_engine.dart';
import 'package:atomic_x_core/api/define.dart';

CompletionHandler handleCallback(dynamic result, {Function(dynamic data)? onSuccess}) {
  CompletionHandler handler = CompletionHandler();

  if (result is TUIActionCallback) {
    handler.errorCode = result.code.rawValue;
    handler.errorMessage = result.message;
    if (result.code == TUIError.success && onSuccess != null) {
      onSuccess(null);
    }
  } else if (result is TUIValueCallBack) {
    handler.errorCode = result.code.rawValue;
    handler.errorMessage = result.message;
    if (result.code == TUIError.success && onSuccess != null) {
      onSuccess(result.data);
    }
  }

  return handler;
}