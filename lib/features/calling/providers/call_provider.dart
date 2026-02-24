import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/services/socket_service.dart';

const String _agoraAppId = '9373634e6f454b15a30dab9ed985658d';

// ─────────────────────────────────────────────────────────────────────────────
// Call State
// ─────────────────────────────────────────────────────────────────────────────

enum CallStatus { idle, calling, ringing, connected, ended }

class CallState {
  final CallStatus status;
  final String? remoteUserId;
  final String? remoteUserName;
  final bool isMuted;
  final bool isSpeakerOn;
  final int durationSeconds;
  final String? endReason; // 'declined' | 'busy' | 'ended' | 'cancelled' | 'error'

  const CallState({
    this.status = CallStatus.idle,
    this.remoteUserId,
    this.remoteUserName,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.durationSeconds = 0,
    this.endReason,
  });

  bool get isInCall =>
      status == CallStatus.calling ||
      status == CallStatus.ringing ||
      status == CallStatus.connected;

  String get formattedDuration {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  CallState copyWith({
    CallStatus? status,
    String? remoteUserId,
    String? remoteUserName,
    bool? isMuted,
    bool? isSpeakerOn,
    int? durationSeconds,
    String? endReason,
  }) {
    return CallState(
      status: status ?? this.status,
      remoteUserId: remoteUserId ?? this.remoteUserId,
      remoteUserName: remoteUserName ?? this.remoteUserName,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      endReason: endReason ?? this.endReason,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Call Notifier – owns the WebRTC peer connection lifecycle
// ─────────────────────────────────────────────────────────────────────────────

class CallNotifier extends Notifier<CallState> {
  RtcEngine? _engine;
  String? _pendingChannelName;
  String? _pendingFromId;
  Timer? _callTimer;

  @override
  CallState build() {
    _registerSocketListeners();
    return const CallState();
  }

  // ── Register socket listeners ─────────────────────────────────────────────
  void _registerSocketListeners() {
    SocketService.on('call-offer', _onIncomingOffer);
    SocketService.on('call-answer', _onAnswer);
    SocketService.on('call-declined', _onRemoteDecline);
    SocketService.on('call-end', _onRemoteEnd);
    SocketService.on('call-cancel', _onRemoteCancel);
    SocketService.on('call-busy', _onRemoteBusy);
  }

  /// Re-register after the socket reconnects (called from SocketService.connect).
  void reRegisterListeners() => _registerSocketListeners();

  // ════════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ════════════════════════════════════════════════════════════════════════════

  /// Moderator initiates an internet call to [remoteUserId].
  Future<void> startCall({
    required String remoteUserId,
    required String remoteUserName,
  }) async {
    if (state.isInCall) return;
    state = CallState(
      status: CallStatus.calling,
      remoteUserId: remoteUserId,
      remoteUserName: remoteUserName,
    );

    try {
      await [Permission.microphone].request();
      final channelName = 'call_${DateTime.now().millisecondsSinceEpoch}';
      await _setupEngine();
      await _engine!.joinChannel(
        token: '',
        channelId: channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      SocketService.emit('call-offer', {
        'to': remoteUserId,
        'channelName': channelName,
      });
    } catch (e) {
      _cleanup();
      state = const CallState(status: CallStatus.ended, endReason: 'error');
      _scheduleReset();
    }
  }

  /// Accept an incoming call (status must be [CallStatus.ringing]).
  Future<void> acceptCall() async {
    if (state.status != CallStatus.ringing || _pendingChannelName == null) return;

    final fromId = _pendingFromId!;
    final channelName = _pendingChannelName!;
    state = state.copyWith(status: CallStatus.connected, durationSeconds: 0);

    try {
      await [Permission.microphone].request();
      await _setupEngine();
      await _engine!.joinChannel(
        token: '',
        channelId: channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      SocketService.emit('call-answer', {'to': fromId});
      _pendingChannelName = null;
      _pendingFromId = null;
      _startTimer();
    } catch (e) {
      _cleanup();
      state = const CallState(status: CallStatus.ended, endReason: 'error');
      _scheduleReset();
    }
  }

  /// Decline an incoming call.
  void declineCall() {
    if (state.remoteUserId != null) {
      SocketService.emit('call-declined', {'to': state.remoteUserId});
    }
    _cleanup();
    state = const CallState(status: CallStatus.ended, endReason: 'declined');
    _scheduleReset();
  }

  /// End an in-progress call.
  void endCall() {
    if (state.remoteUserId != null) {
      SocketService.emit('call-end', {'to': state.remoteUserId});
    }
    _cleanup();
    state = const CallState(status: CallStatus.ended, endReason: 'ended');
    _scheduleReset();
  }

  void toggleMute() {
    final muted = !state.isMuted;
    _engine?.muteLocalAudioStream(muted);
    state = state.copyWith(isMuted: muted);
  }

  Future<void> toggleSpeaker() async {
    final on = !state.isSpeakerOn;
    await _engine?.setEnableSpeakerphone(on);
    state = state.copyWith(isSpeakerOn: on);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SOCKET HANDLERS (private)
  // ════════════════════════════════════════════════════════════════════════════

  void _onIncomingOffer(dynamic data) {
    if (state.isInCall) {
      SocketService.emit('call-busy', {'to': data['from']});
      return;
    }

    final channelName = data['channelName'] as String?;
    if (channelName == null) return;

    _pendingChannelName = channelName;
    _pendingFromId = data['from'] as String?;

    final callerInfo = data['callerInfo'] as Map?;
    final callerName = callerInfo?['name'] as String? ?? 'Unknown';

    state = CallState(
      status: CallStatus.ringing,
      remoteUserId: _pendingFromId,
      remoteUserName: callerName,
    );
  }

  void _onAnswer(dynamic data) {
    _startTimer();
    state = state.copyWith(status: CallStatus.connected, durationSeconds: 0);
  }

  void _onRemoteDecline(dynamic _) {
    _cleanup();
    state = const CallState(status: CallStatus.ended, endReason: 'declined');
    _scheduleReset();
  }

  void _onRemoteEnd(dynamic _) {
    _cleanup();
    state = const CallState(status: CallStatus.ended, endReason: 'ended');
    _scheduleReset();
  }

  void _onRemoteCancel(dynamic _) {
    _cleanup();
    state = const CallState(status: CallStatus.ended, endReason: 'cancelled');
    _scheduleReset();
  }

  void _onRemoteBusy(dynamic _) {
    _cleanup();
    state = const CallState(status: CallStatus.ended, endReason: 'busy');
    _scheduleReset();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _setupEngine() async {
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(appId: _agoraAppId));
    await _engine!.enableAudio();
    await _engine!.setAudioProfile(
      profile: AudioProfileType.audioProfileMusicHighQuality,
      scenario: AudioScenarioType.audioScenarioChatroom,
    );
    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onUserOffline: (connection, remoteUid, reason) {
          if (state.status == CallStatus.connected) {
            endCall();
          }
        },
      ),
    );
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(durationSeconds: state.durationSeconds + 1);
    });
  }

  void _scheduleReset({int delaySeconds = 3}) {
    Future.delayed(Duration(seconds: delaySeconds), () {
      if (state.status == CallStatus.ended) {
        state = const CallState();
      }
    });
  }

  void _cleanup() {
    _callTimer?.cancel();
    _callTimer = null;
    _engine?.leaveChannel();
    _engine?.release();
    _engine = null;
    _pendingChannelName = null;
    _pendingFromId = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final callProvider = NotifierProvider<CallNotifier, CallState>(
  CallNotifier.new,
);
