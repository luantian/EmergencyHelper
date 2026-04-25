# AtomicXCore

## 4.0.2

- Live: Removed the default auto-leave seat logic for voice chat room audience upon entering the room.

## 4.0.1

- Call: Changed the `enableCloudRecording` field from bool type to `TUICloudRecordPolicy` enum type.
- LiveInfo adapted to legacy `seatLayoutTemplateID` and other parameters.
- LiveCoreWidget optimized with some bug fixes.
- DeviceStore default video resolution changed to 720P.
- Added plugin version information.

## 4.0.0

- Webinar Support for Room: Added guest, audience, admin, and mute list management with paginated fetching for large-scale rooms.
- Upgrade rtc_room_engine dependencies to version 4.0.0.

## 3.6.7

- Optimize the performance of AI-powered message transcription.

## 3.6.6

- Optimize the performance of AI-powered message transcription.

## 3.6.5

- Added a new store related to AI transcription.

## 3.6.4

- Adjust the VideoWidgetBuilder parameters of LiveCoreWidget.
- Add the CoreViewType parameter to the create method of LiveCoreController.

## 3.6.3

- CallStore and CallParticipantStore have been merged.
- Removed CallParticipantView, added CallCoreView.

## 3.6.2

- Added multi-person room support: `RoomStore`, `RoomParticipantStore` (state management) and `RoomParticipantWidget` (UI component).
- Upgrade rtc_room_engine dependencies.

## 3.6.1

- Add AI bot user filtering logic to call store

## 3.6.0

- Added live streaming-related Store.
- Upgrade rtc_room_engine dependencies to version 3.6.0.

## 3.5.0

- Fix dependency leakage: Redefine Call structs and enums to encapsulate third-party implementation
  details.
- Upgrade rtc_room_engine dependencies to version 3.5.0.

## 3.4.1

- Add call-related store.
