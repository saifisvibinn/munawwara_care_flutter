import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/call_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VoiceCallScreen
// Handles both outgoing (status=calling) and active (status=connected) phases.
// Auto-pops when the call returns to idle.
// ─────────────────────────────────────────────────────────────────────────────

class VoiceCallScreen extends ConsumerStatefulWidget {
  const VoiceCallScreen({super.key});

  @override
  ConsumerState<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends ConsumerState<VoiceCallScreen> {
  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callProvider);

    // Pop when the provider resets back to idle (after ended+delay)
    ref.listen(callProvider, (prev, next) {
      if (next.status == CallStatus.idle && mounted) {
        Navigator.of(context).maybePop();
      }
    });

    final name = call.remoteUserName ?? 'Unknown';
    final initials = name
        .trim()
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ────────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
              child: Row(
                children: [
                  const Spacer(),
                  Text(
                    'Internet Call',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13.sp,
                      fontFamily: 'Lexend',
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),

            const Spacer(flex: 2),

            // ── Avatar ─────────────────────────────────────────────────────
            Container(
              width: 110.w,
              height: 110.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.4),
                    blurRadius: 30,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 38.sp,
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            SizedBox(height: 24.h),

            // ── Name ───────────────────────────────────────────────────────
            Text(
              name,
              style: TextStyle(
                fontSize: 26.sp,
                fontWeight: FontWeight.w700,
                fontFamily: 'Lexend',
                color: Colors.white,
              ),
            ),

            SizedBox(height: 8.h),

            // ── Status / Timer ─────────────────────────────────────────────
            Text(
              _statusLabel(call),
              style: TextStyle(
                fontSize: 14.sp,
                fontFamily: 'Lexend',
                color: call.status == CallStatus.connected
                    ? AppColors.primary
                    : Colors.white54,
              ),
            ),

            const Spacer(flex: 3),

            // ── Side controls (mute + speaker) ─────────────────────────────
            if (call.status == CallStatus.connected) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ControlButton(
                    icon: call.isMuted ? Symbols.mic_off : Symbols.mic,
                    label: call.isMuted ? 'Unmute' : 'Mute',
                    active: call.isMuted,
                    onTap: () =>
                        ref.read(callProvider.notifier).toggleMute(),
                  ),
                  SizedBox(width: 32.w),
                  _ControlButton(
                    icon: call.isSpeakerOn
                        ? Symbols.volume_up
                        : Symbols.volume_down,
                    label: call.isSpeakerOn ? 'Speaker' : 'Earpiece',
                    active: call.isSpeakerOn,
                    onTap: () =>
                        ref.read(callProvider.notifier).toggleSpeaker(),
                  ),
                ],
              ),
              SizedBox(height: 36.h),
            ],

            // ── End call button ────────────────────────────────────────────
            if (call.status != CallStatus.ended) ...[
              GestureDetector(
                onTap: () {
                  if (call.status == CallStatus.calling) {
                    // Cancel outgoing call
                    SocketService.emit(
                        'call-cancel', {'to': call.remoteUserId});
                    ref.read(callProvider.notifier).endCall();
                  } else {
                    ref.read(callProvider.notifier).endCall();
                  }
                },
                child: Container(
                  width: 70.w,
                  height: 70.w,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDC2626),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Symbols.call_end,
                    color: Colors.white,
                    size: 30.w,
                    fill: 1,
                  ),
                ),
              ),
            ],

            // ── End reason ─────────────────────────────────────────────────
            if (call.status == CallStatus.ended) ...[
              Icon(Symbols.info, color: Colors.white38, size: 32.w),
              SizedBox(height: 8.h),
              Text(
                _endReasonLabel(call.endReason),
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14.sp,
                  fontFamily: 'Lexend',
                ),
              ),
            ],

            SizedBox(height: 60.h),
          ],
        ),
      ),
    );
  }

  String _statusLabel(CallState call) {
    switch (call.status) {
      case CallStatus.calling:
        return 'Calling...';
      case CallStatus.connected:
        return call.formattedDuration;
      case CallStatus.ended:
        return _endReasonLabel(call.endReason);
      default:
        return '';
    }
  }

  String _endReasonLabel(String? reason) {
    switch (reason) {
      case 'declined':
        return 'Call declined';
      case 'busy':
        return 'User is busy';
      case 'cancelled':
        return 'Call cancelled';
      case 'error':
        return 'Connection error';
      default:
        return 'Call ended';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widget: mute / speaker buttons
// ─────────────────────────────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60.w,
            height: 60.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? Colors.white.withOpacity(0.25)
                  : Colors.white.withOpacity(0.1),
            ),
            child: Icon(icon, fill: 1, color: Colors.white, size: 26.w),
          ),
          SizedBox(height: 6.h),
          Text(
            label,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11.sp,
              fontFamily: 'Lexend',
            ),
          ),
        ],
      ),
    );
  }
}

