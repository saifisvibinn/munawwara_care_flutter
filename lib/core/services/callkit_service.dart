import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:uuid/uuid.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CallKitService — Shows native incoming call screen (like WhatsApp)
// Uses Android ConnectionService / iOS CallKit under the hood.
// Works even when app is killed, screen off, or locked.
// ─────────────────────────────────────────────────────────────────────────────

class CallKitService {
  static final CallKitService instance = CallKitService._();
  CallKitService._();

  static const _uuid = Uuid();

  // Track the current call UUID so we can end it later
  String? _currentCallId;
  String? get currentCallId => _currentCallId;

  /// Show a native incoming call screen.
  /// Call this from both foreground and background FCM handlers.
  Future<void> showIncomingCall({
    required String callerId,
    required String callerName,
    required String channelName,
    String? callerRole,
  }) async {
    _currentCallId = _uuid.v4();

    final params = CallKitParams(
      id: _currentCallId!,
      nameCaller: callerName,
      appName: 'Munawwara Care',
      handle: callerRole ?? 'Voice Call',
      type: 0, // 0 = audio call, 1 = video call
      duration: 60000, // Ring for 60 seconds max
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Missed Call',
        callbackText: 'Call Back',
      ),
      extra: <String, dynamic>{
        'callerId': callerId,
        'callerName': callerName,
        'callerRole': callerRole ?? '',
        'channelName': channelName,
      },
      headers: <String, dynamic>{},
      android: const AndroidParams(
        isCustomNotification: false,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0D1B2A',
        actionColor: '#F97316', // AppColors.primary
        textColor: '#FFFFFF',
        isShowFullLockedScreen: true,
        incomingCallNotificationChannelName: 'Incoming Calls',
        isShowCallID: false,
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        supportsVideo: false,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
    print('📞 Native incoming call screen shown for $callerName');
  }

  /// End/dismiss the current incoming call UI.
  Future<void> endCurrentCall() async {
    if (_currentCallId != null) {
      await FlutterCallkitIncoming.endCall(_currentCallId!);
      _currentCallId = null;
    }
  }

  /// End all calls (cleanup).
  Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
    _currentCallId = null;
  }

  /// Process an FCM message and show incoming call if it's a call notification.
  /// Returns true if it was a call message and was handled.
  static Future<bool> handleFcmMessage(RemoteMessage message) async {
    final data = message.data;
    final type = data['type'];

    if (type != 'incoming_call') return false;

    final callerId = data['callerId'] ?? '';
    final callerName = data['callerName'] ?? data['title'] ?? 'Unknown';
    final callerRole = data['callerRole'] ?? '';
    final channelName = data['channelName'] ?? '';

    print('📞 FCM incoming_call detected — showing native call screen');
    print('   Caller: $callerName ($callerId)');
    print('   Channel: $channelName');

    await CallKitService.instance.showIncomingCall(
      callerId: callerId,
      callerName: callerName,
      channelName: channelName,
      callerRole: callerRole,
    );

    return true;
  }
}
