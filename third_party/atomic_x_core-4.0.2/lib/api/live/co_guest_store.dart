// Copyright (c) 2025 Tencent. All rights reserved.
// Module:   CoGuestStore @ AtomicXCore
// Function: Live co-guest management related interfaces, managing co-guest application, invitation, acceptance, rejection and other operations between hosts and audience.

import 'package:flutter/foundation.dart';

import '../../impl/live/store_factory.dart';
import '../define.dart';
import 'live_audience_store.dart';
import 'live_seat_store.dart';

/// Reason for no response to co-guest invitation sent by host or co-guest request initiated by audience
///
/// This enum describes why a co-guest request or invitation did not receive a response from the other party.
///
/// > **Note**: The system automatically triggers no-response events when timeout expires or certain state conflicts occur.
///
/// ### Response Scenarios
///
/// The following table shows the trigger conditions for each reason
///
/// | Reason | Trigger Condition | Example Scenario |
/// |------|-----------------|----------------|
/// | `timeout` | Response timeout | Host did not respond to application within 30 seconds |
/// | `alreadySeated` | Target user already on seat | Audience is already co-guesting with another host |
enum NoResponseReason {
  /// Request timeout
  timeout(0),

  /// User already on seat
  alreadySeated(1);

  final int value;
  const NoResponseReason(this.value);
}

/// Co-guest related state data provided externally by CoGuestStore
///
/// A comprehensive snapshot of the current co-guest session state. This structure contains all relevant information about connected users, pending invitations and applications.
///
/// > **Note**: State is automatically updated when users join/leave seats, send/cancel invitations, or apply/cancel applications. Subscribe to [coGuestState] to receive real-time updates.
/// ### Usage Example
///
/// ```dart
/// // Define listeners
/// late final VoidCallback connectedListener = _onConnectedChanged;
/// late final VoidCallback applicantsListener = _onApplicantsChanged;
/// late final VoidCallback inviteesListener = _onInviteesChanged;
///
/// void _onConnectedChanged() {
///     updateConnectedUsersUI(store.coGuestState.connected.value);
/// }
///
/// void _onApplicantsChanged() {
///     final applicants = store.coGuestState.applicants.value;
///     if (applicants.isNotEmpty) {
///         showApplicationsBadge(applicants.length);
///     }
/// }
///
/// void _onInviteesChanged() {
///     final invitees = store.coGuestState.invitees.value;
///     if (invitees.isNotEmpty) {
///         showInvitationsPendingUI(invitees);
///     }
/// }
///
/// // Subscribe to state changes
/// store.coGuestState.connected.addListener(connectedListener);
/// store.coGuestState.applicants.addListener(applicantsListener);
/// store.coGuestState.invitees.addListener(inviteesListener);
/// ```
///
/// ### State Properties Overview
///
/// | Property | Type | Role | Description |
/// |--------|------|------|-----------|
/// | [connected] | `ValueListenable<List<SeatUserInfo>>` | Both | List of users currently on seats |
/// | [invitees] | `ValueListenable<List<LiveUserInfo>>` | Host | Users invited by host (waiting for response) |
/// | [applicants] | `ValueListenable<List<LiveUserInfo>>` | Host | Users who applied (waiting for host decision) |
/// | [candidates] | `ValueListenable<List<LiveUserInfo>>` | Host | List of potential users available for invitation |
abstract class CoGuestState {
  /// List of users already on seats.
  ValueListenable<List<SeatUserInfo>> get connected;

  /// List of users invited by host.
  ValueListenable<List<LiveUserInfo>> get invitees;

  /// List of users who applied for co-guest received by host.
  ValueListenable<List<LiveUserInfo>> get applicants;

  /// List of candidate users for co-guest.
  ValueListenable<List<LiveUserInfo>> get candidates;
}

/// Callback events received on host side
class HostListener {
  /// This callback is triggered when an audience applies for co-guest.
  /// - [guestUser] : Information of the audience applying for co-guest
  void Function(LiveUserInfo guestUser)? onGuestApplicationReceived;

  /// This callback is triggered when an audience cancels co-guest application.
  /// - [guestUser] : Information of the audience cancelling application
  void Function(LiveUserInfo guestUser)? onGuestApplicationCancelled;

  /// This callback is triggered when an audience's co-guest application is processed by another host.
  /// - [guestUser] : Information of the audience applying for co-guest
  /// - [hostUser] : Information of the host processing the application
  void Function(LiveUserInfo guestUser, LiveUserInfo hostUser)? onGuestApplicationProcessedByOtherHost;

  /// This callback is triggered when a co-guest invitation sent by host receives a response from audience.
  /// - [isAccept] : Whether the invitation is accepted
  /// - [guestUser] : Information of the invited audience
  void Function(bool isAccept, LiveUserInfo guestUser)? onHostInvitationResponded;

  /// This callback is triggered when a co-guest invitation sent by host receives no response.
  /// - [guestUser] : Information of the invited audience
  /// - [reason] : Reason for no response
  void Function(LiveUserInfo guestUser, NoResponseReason reason)? onHostInvitationNoResponse;

  HostListener({
    this.onGuestApplicationReceived,
    this.onGuestApplicationCancelled,
    this.onGuestApplicationProcessedByOtherHost,
    this.onHostInvitationResponded,
    this.onHostInvitationNoResponse,
  });
}

/// Callback events received on guest side
class GuestListener {
  /// This callback is triggered when receiving a co-guest invitation from host.
  /// - [hostUser] : Information of the host sending invitation
  void Function(LiveUserInfo hostUser)? onHostInvitationReceived;

  /// This callback is triggered when host cancels co-guest invitation.
  /// - [hostUser] : Information of the host cancelling invitation
  void Function(LiveUserInfo hostUser)? onHostInvitationCancelled;

  /// This callback is triggered when audience's co-guest application receives a response from host.
  /// - [isAccept] : Whether the application is accepted
  /// - [hostUser] : Information of the host responding to application
  void Function(bool isAccept, LiveUserInfo hostUser)? onGuestApplicationResponded;

  /// This callback is triggered when audience's co-guest application receives no response.
  /// - [reason] : Reason for no response
  void Function(NoResponseReason reason)? onGuestApplicationNoResponse;

  /// This callback is triggered when audience is kicked off seat by host.
  /// - [seatIndex] : Seat index
  /// - [hostUser] : Information of the host kicking user
  void Function(int seatIndex, LiveUserInfo hostUser)? onKickedOffSeat;

  GuestListener({
    this.onHostInvitationReceived,
    this.onHostInvitationCancelled,
    this.onGuestApplicationResponded,
    this.onGuestApplicationNoResponse,
    this.onKickedOffSeat,
  });
}

/// Live co-guest management related interfaces, managing co-guest application, invitation, acceptance, rejection and other operations between hosts and audience.
///
/// `CoGuestStore` Manages all co-guest related operations between hosts and audience,
/// including application, invitation, acceptance and rejection processes.
/// Co-guest feature enables real-time interaction between hosts and audience members through a seat-based system. `CoGuestStore` provides a comprehensive set of APIs to manage the entire co-guest lifecycle.
///
/// ### Key Features
///
/// - **Bidirectional Invitation**：Hosts can invite audience members, and audience members can also apply to join
/// - **State Management**：Real-time tracking of connected users, invitations and applications
/// - **Event-Driven Architecture**：Provides separate event streams for host and guest roles
/// - **Timeout Handling**：Built-in timeout mechanism for invitations and applications
///
/// > **Important**: Always use the factory method [CoGuestStore.create] with a valid live room ID to create a `CoGuestStore` instance. Do not attempt to initialize directly.
///
/// > **Note**: Co-guest state updates are delivered through the [coGuestState] publisher. Subscribe to it to receive real-time updates about connected users, invitations and applications.
///
/// ### Co-Guest Workflow
///
/// The following table shows a typical co-guest workflow
///
/// | Step | Role | Action | Triggered Event |
/// |------|------|------|---------------|
/// | 1 | Audience | Call [applyForSeat] | [HostListener.onGuestApplicationReceived] |
/// | 2 | Host | Call [acceptApplication] | [GuestListener.onGuestApplicationResponded] |
/// | 3 | System | User connects to seat | State updated through [coGuestState] publisher |
///
/// ### Host-Initiated Flow
///
/// | Step | Role | Action | Triggered Event |
/// |------|------|------|---------------|
/// | 1 | Host | Call [inviteToSeat] | [GuestListener.onHostInvitationReceived] |
/// | 2 | Audience | Call [acceptInvitation] | [HostListener.onHostInvitationResponded] |
/// | 3 | System | User connects to seat | State updated through [coGuestState] publisher |
///
/// ### Usage Example
///
/// ```dart
/// // Create store instance
/// final store = CoGuestStore.create('live_room_123');
///
/// // Define listeners
/// late final VoidCallback connectedListener = _onConnectedChanged;
/// late final VoidCallback applicantsListener = _onApplicantsChanged;
///
/// void _onConnectedChanged() {
///     print('Connected users: ${store.coGuestState.connected.value.length}');
/// }
///
/// void _onApplicantsChanged() {
///     print('Pending applications: ${store.coGuestState.applicants.value.length}');
/// }
///
/// // Subscribe to state changes
/// store.coGuestState.connected.addListener(connectedListener);
/// store.coGuestState.applicants.addListener(applicantsListener);
///
/// // Add host event listener (for hosts)
/// final hostListener = HostListener(
///     onGuestApplicationReceived: (guestUser) {
///         print('Received application from ${guestUser.userName}');
///         // Show accept/reject UI
///     },
///     onHostInvitationResponded: (isAccept, guestUser) {
///         print('Audience ${guestUser.userName} ${isAccept ? "accepted" : "rejected"}');
///     },
/// );
/// store.addHostListener(hostListener);
///
/// // Host: Accept application
/// final result = await store.acceptApplication('user_456');
/// if (result.code == 0) {
///     print('Application accepted successfully');
/// }
///
/// // Unsubscribe when done
/// store.coGuestState.connected.removeListener(connectedListener);
/// store.coGuestState.applicants.removeListener(applicantsListener);
/// store.removeHostListener(hostListener);
/// ```
///
/// ## Topics
///
/// ### Creating Instance
/// - [CoGuestStore.create] : Create object instance
///
/// ### Observing State and Events
/// - [coGuestState] : Reactive state containing connected users, invitees, applicants and candidates
/// - [addHostListener]/[removeHostListener] : Host-side event callbacks
/// - [addGuestListener]/[removeGuestListener] : Guest-side event callbacks
///
/// ### Guest Operations
/// - [applyForSeat] : Guest applies for co-guest
/// - [cancelApplication] : Guest cancels application
/// - [acceptApplication] : Host accepts application
/// - [rejectApplication] : Host rejects application
///
/// ### Host Operations
/// - [inviteToSeat] : Host invites guest to co-guest
/// - [cancelInvitation] : Host cancels invitation
/// - [acceptInvitation] : Guest accepts invitation
/// - [rejectInvitation] : Guest rejects invitation
///
/// ### Connection Control
/// - [disconnect] : End co-guest session
///
/// ## See Also
///
/// - [NoResponseReason]
/// - [CoGuestState]
/// - [HostListener]
/// - [GuestListener]
abstract class CoGuestStore {
  /// Co-guest related state data provided externally by CoGuestStore
  CoGuestState get coGuestState;

  /// Create CoGuestStore instance
  /// - [liveID] : Live room ID
  /// Returns: CoGuestStore instance
  static CoGuestStore create(String liveID) {
    return StoreFactory.shared.getStore<CoGuestStore>(liveID: liveID);
  }

  /// Apply to go on seat
  ///
  /// Request to join co-guest session as an audience member.
  ///
  /// After calling this method, a co-guest request is sent to all hosts in the live room. The request will remain active until:
  /// • Host accepts via [acceptApplication]
  /// • Host rejects via [rejectApplication]
  /// • Timeout expires
  /// • You cancel via [cancelApplication]
  ///
  /// - [seatIndex] : Seat index, -1 means auto-assign seat
  /// - [timeout] : Timeout (unit: seconds)
  /// - [extraInfo] : Extra information
  Future<CompletionHandler> applyForSeat({
    required int seatIndex,
    required int timeout,
    String? extraInfo,
  });

  /// Cancel seat application
  ///
  /// Cancel a previously sent co-guest application. After calling this method, all hosts will be notified of the application cancellation.
  ///
  Future<CompletionHandler> cancelApplication();

  /// Accept seat application
  ///
  /// - [userID] : User ID
  Future<CompletionHandler> acceptApplication(String userID);

  /// Reject seat application
  ///
  /// - [userID] : User ID
  Future<CompletionHandler> rejectApplication(String userID);

  /// Invite audience to seat
  ///
  /// - [inviteeID] : Invited user ID
  /// - [seatIndex] : Seat index, -1 means auto-assign seat
  /// - [timeout] : Timeout (unit: seconds)
  /// - [extraInfo] : Extra information
  Future<CompletionHandler> inviteToSeat({
    required String inviteeID,
    required int seatIndex,
    required int timeout,
    String? extraInfo,
  });

  /// Cancel seat invitation
  ///
  /// - [inviteeID] : Invited user ID
  Future<CompletionHandler> cancelInvitation(String inviteeID);

  /// Accept seat invitation
  ///
  /// - [inviterID] : Inviter user ID
  Future<CompletionHandler> acceptInvitation(String inviterID);

  /// Reject seat invitation
  ///
  /// - [inviterID] : Inviter user ID
  Future<CompletionHandler> rejectInvitation(String inviterID);

  /// Disconnect co-guest
  ///
  Future<CompletionHandler> disconnect();

  /// Add host-side event callback listener
  ///
  /// - [listener] : Listener
  void addHostListener(HostListener listener);

  /// Remove host-side event callback listener
  ///
  /// - [listener] : Listener
  void removeHostListener(HostListener listener);

  /// Add guest-side event callback listener
  ///
  /// - [listener] : Listener
  void addGuestListener(GuestListener listener);

  /// Remove guest-side event callback listener
  ///
  /// - [listener] : Listener
  void removeGuestListener(GuestListener listener);
}
