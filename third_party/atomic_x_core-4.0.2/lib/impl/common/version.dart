import 'log.dart';

const kVersion = '4.0.2';

class Version {
  static final Log _log = Log.getCommonLog('Version');

  static void printVersion() {
    _log.info("atomic_x_core version:$kVersion");
  }
}
