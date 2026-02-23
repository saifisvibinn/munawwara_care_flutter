import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/pilgrim_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim Dashboard Screen
// ─────────────────────────────────────────────────────────────────────────────

class PilgrimDashboardScreen extends ConsumerStatefulWidget {
  const PilgrimDashboardScreen({super.key});

  @override
  ConsumerState<PilgrimDashboardScreen> createState() =>
      _PilgrimDashboardScreenState();
}

class _PilgrimDashboardScreenState extends ConsumerState<PilgrimDashboardScreen>
    with TickerProviderStateMixin {
  // Bottom nav
  int _currentTab = 0;

  // SOS hold animation
  late AnimationController _sosHoldController;
  late AnimationController _sosPulseController;
  Timer? _sosTimer;
  bool _isSosHolding = false;

  // Location
  StreamSubscription<Position>? _locationSub;
  final Battery _battery = Battery();
  final MapController _mapController = MapController();
  LatLng? _myLatLng;

  @override
  void initState() {
    super.initState();

    // SOS hold progress ring (fills in 3 s)
    _sosHoldController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // SOS pulse (idle pulsing glow)
    _sosPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Load data after first frame so the provider is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pilgrimProvider.notifier).loadDashboard();
      _initLocation();
    });
  }

  @override
  void dispose() {
    _sosHoldController.dispose();
    _sosPulseController.dispose();
    _mapController.dispose();
    _sosTimer?.cancel();
    _locationSub?.cancel();
    super.dispose();
  }

  // ── Location ────────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) return;
    if (!mounted) return;

    _locationSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 20, // metres
          ),
        ).listen((pos) async {
          final ll = LatLng(pos.latitude, pos.longitude);
          setState(() => _myLatLng = ll);
          int? battery;
          try {
            final lvl = await _battery.batteryLevel;
            battery = lvl;
            ref.read(pilgrimProvider.notifier).setBattery(lvl);
          } catch (_) {}
          ref
              .read(pilgrimProvider.notifier)
              .updateLocation(
                latitude: pos.latitude,
                longitude: pos.longitude,
                batteryPercent: battery,
              );
        });
  }

  // ── SOS Logic ───────────────────────────────────────────────────────────────

  void _onSosHoldStart() {
    setState(() => _isSosHolding = true);
    _sosHoldController.forward(from: 0);
    _sosTimer = Timer(const Duration(seconds: 3), _fireSOS);
  }

  void _onSosHoldEnd() {
    if (!_isSosHolding) return;
    _sosHoldController.reverse();
    _sosTimer?.cancel();
    setState(() => _isSosHolding = false);
  }

  Future<void> _fireSOS() async {
    setState(() => _isSosHolding = false);
    _sosHoldController.value = 0;
    final ok = await ref.read(pilgrimProvider.notifier).triggerSOS();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ok ? Colors.red.shade700 : Colors.grey.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
        content: Text(
          ok ? 'sos_sent'.tr() : 'sos_failed'.tr(),
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pilgrimState = ref.watch(pilgrimProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tabs = [
      _HomeTab(
        pilgrimState: pilgrimState,
        isDark: isDark,
        sosPulseController: _sosPulseController,
        sosHoldController: _sosHoldController,
        isSosHolding: _isSosHolding,
        onSosHoldStart: _onSosHoldStart,
        onSosHoldEnd: _onSosHoldEnd,
        onRefresh: () => ref.read(pilgrimProvider.notifier).loadDashboard(),
      ),
      _PilgrimMapTab(
        myLocation: _myLatLng,
        mapController: _mapController,
        pilgrimState: pilgrimState,
      ),
      _PlaceholderTab(icon: Symbols.calendar_month, label: 'tab_plan'.tr()),
      _PlaceholderTab(icon: Symbols.chat_bubble, label: 'tab_chat'.tr()),
      _PlaceholderTab(icon: Symbols.person, label: 'tab_me'.tr()),
    ];

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : const Color(0xfff1f5f3),
      body: IndexedStack(index: _currentTab, children: tabs),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentTab,
        onTap: (i) => setState(() => _currentTab = i),
        unreadMessages: 0, // TODO: plug in real unread from messages provider
        isDark: isDark,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home Tab
// ─────────────────────────────────────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  final PilgrimState pilgrimState;
  final bool isDark;
  final AnimationController sosPulseController;
  final AnimationController sosHoldController;
  final bool isSosHolding;
  final VoidCallback onSosHoldStart;
  final VoidCallback onSosHoldEnd;
  final Future<void> Function() onRefresh;

  const _HomeTab({
    required this.pilgrimState,
    required this.isDark,
    required this.sosPulseController,
    required this.sosHoldController,
    required this.isSosHolding,
    required this.onSosHoldStart,
    required this.onSosHoldEnd,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final profile = pilgrimState.profile;
    final group = pilgrimState.groupInfo;

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Header ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 0),
                child: Row(
                  children: [
                    // Logo
                    Container(
                      width: 52.w,
                      height: 52.w,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Symbols.mosque,
                        size: 26.w,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MUNAWWARA CARE',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                          ),
                          Text(
                            pilgrimState.isLoading
                                ? 'Pilgrim ID: ...'
                                : 'Pilgrim ID: ${profile?.displayId ?? '------'}',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12.sp,
                              color: AppColors.textMutedLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Notification bell
                    Stack(
                      children: [
                        Container(
                          width: 42.w,
                          height: 42.w,
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.surfaceDark
                                : Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Symbols.notifications,
                            size: 22.w,
                            color: isDark ? Colors.white70 : AppColors.textDark,
                          ),
                        ),
                        Positioned(
                          top: 6.w,
                          right: 6.w,
                          child: Container(
                            width: 10.w,
                            height: 10.w,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(child: SizedBox(height: 28.h)),

            // ── Greeting ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'greeting_prefix'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 28.sp,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                    Text(
                      pilgrimState.isLoading
                          ? '...'
                          : (profile?.firstName ?? ''),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 32.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      children: [
                        Container(
                          width: 10.w,
                          height: 10.w,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'status_safe_label'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14.sp,
                            color: isDark ? Colors.white70 : AppColors.textDark,
                          ),
                        ),
                        Text(
                          ' ${'status_safe'.tr()}',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(child: SizedBox(height: 24.h)),

            // ── Info Cards ──────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Row(
                  children: [
                    // Group card
                    Expanded(
                      child: _InfoCard(
                        isDark: isDark,
                        icon: Symbols.groups,
                        iconColor: AppColors.primary,
                        label: 'card_my_group'.tr(),
                        value: group?.groupName ?? 'card_no_group'.tr(),
                        badge: null,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    // Location sharing card
                    Expanded(
                      child: _InfoCard(
                        isDark: isDark,
                        icon: Symbols.location_on,
                        iconColor: AppColors.primary,
                        label: 'card_sharing'.tr(),
                        value: pilgrimState.isSharingLocation
                            ? 'card_active'.tr()
                            : 'card_paused'.tr(),
                        badge: pilgrimState.batteryLevel != null
                            ? '🔋 ${pilgrimState.batteryLevel}%'
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(child: SizedBox(height: 40.h)),

            // ── SOS Button ──────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Center(
                child: Column(
                  children: [
                    _SosButton(
                      pulseController: sosPulseController,
                      holdController: sosHoldController,
                      isHolding: isSosHolding,
                      isLoading: pilgrimState.isSosLoading,
                      sosActive: pilgrimState.sosActive,
                      onHoldStart: onSosHoldStart,
                      onHoldEnd: onSosHoldEnd,
                    ),
                    SizedBox(height: 20.h),
                    Text(
                      'sos_title'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'sos_subtitle'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13.sp,
                        color: AppColors.textMutedLight,
                      ),
                    ),
                    SizedBox(height: 24.h),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SOS Button Widget
// ─────────────────────────────────────────────────────────────────────────────

class _SosButton extends StatelessWidget {
  final AnimationController pulseController;
  final AnimationController holdController;
  final bool isHolding;
  final bool isLoading;
  final bool sosActive;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  const _SosButton({
    required this.pulseController,
    required this.holdController,
    required this.isHolding,
    required this.isLoading,
    required this.sosActive,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  @override
  Widget build(BuildContext context) {
    const double size = 180;
    const double ringStroke = 6;

    return GestureDetector(
      onLongPressStart: (_) => onHoldStart(),
      onLongPressEnd: (_) => onHoldEnd(),
      onLongPressCancel: () => onHoldEnd(),
      child: SizedBox(
        width: size.w,
        height: size.w,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Pulse glow
            AnimatedBuilder(
              animation: pulseController,
              builder: (_, __) {
                final scale = 1.0 + 0.15 * pulseController.value;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: size.w,
                    height: size.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (sosActive ? Colors.red : Colors.red).withOpacity(
                        0.15 * pulseController.value,
                      ),
                    ),
                  ),
                );
              },
            ),

            // Main red circle
            Container(
              width: (size - 20).w,
              height: (size - 20).w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    sosActive ? Colors.red.shade300 : Colors.red.shade400,
                    sosActive ? Colors.red.shade700 : Colors.red.shade700,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.45),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '505',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w900,
                            color: Colors.white.withOpacity(0.6),
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          'SOS',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 28.sp,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 4,
                          ),
                        ),
                      ],
                    ),
            ),

            // Hold progress ring
            if (isHolding)
              AnimatedBuilder(
                animation: holdController,
                builder: (_, __) => SizedBox(
                  width: size.w,
                  height: size.w,
                  child: CircularProgressIndicator(
                    value: holdController.value,
                    strokeWidth: ringStroke,
                    color: Colors.white,
                    backgroundColor: Colors.white.withOpacity(0.2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info Card Widget
// ─────────────────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? badge;

  const _InfoCard({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42.w,
                height: 42.w,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22.w, color: iconColor),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12.sp,
              color: AppColors.textMutedLight,
            ),
          ),
          SizedBox(height: 2.h),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null) ...[
                SizedBox(width: 4.w),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Navigation Bar
// ─────────────────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int unreadMessages;
  final bool isDark;

  const _BottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.unreadMessages,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final labels = [
      'tab_home'.tr(),
      'tab_map'.tr(),
      'tab_plan'.tr(),
      'tab_chat'.tr(),
      'tab_me'.tr(),
    ];
    final icons = [
      Symbols.home,
      Symbols.map,
      Symbols.calendar_month,
      Symbols.chat_bubble,
      Symbols.person,
    ];
    final badges = [0, 0, 0, unreadMessages, 0];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(5, (i) {
              final isSelected = i == currentIndex;
              return GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 60.w,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 44.w,
                            height: 36.h,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withOpacity(0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Icon(
                              icons[i],
                              size: 22.w,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textMutedLight,
                            ),
                          ),
                          if (badges[i] > 0)
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                padding: EdgeInsets.all(3.w),
                                decoration: const BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                                constraints: BoxConstraints(
                                  minWidth: 14.w,
                                  minHeight: 14.w,
                                ),
                                child: Text(
                                  badges[i] > 9 ? '9+' : '${badges[i]}',
                                  style: TextStyle(
                                    fontSize: 9.sp,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 11.sp,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textMutedLight,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map Tab
// ─────────────────────────────────────────────────────────────────────────────

class _PilgrimMapTab extends StatelessWidget {
  final LatLng? myLocation;
  final MapController mapController;
  final PilgrimState pilgrimState;

  const _PilgrimMapTab({
    required this.myLocation,
    required this.mapController,
    required this.pilgrimState,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final group = pilgrimState.groupInfo;

    return Stack(
      children: [
        // Map
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: myLocation ?? const LatLng(21.3891, 39.8579),
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.munawwaracare.app',
            ),
            // My location
            if (myLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: myLocation!,
                    width: 60.w,
                    height: 72.h,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 46.w,
                          height: 46.w,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.5),
                                blurRadius: 10,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: Icon(
                            Symbols.person,
                            color: Colors.white,
                            size: 22.w,
                          ),
                        ),
                        Container(
                          margin: EdgeInsets.only(top: 2.h),
                          padding: EdgeInsets.symmetric(
                            horizontal: 5.w,
                            vertical: 2.h,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(
                            'You',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w700,
                              fontSize: 10.sp,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),

        // Top overlay: group name
        if (group != null)
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(14.w),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 16.r,
                      backgroundColor: AppColors.primary.withOpacity(0.15),
                      child: Icon(
                        Symbols.group,
                        color: AppColors.primary,
                        size: 16.w,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      group.groupName,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 13.sp,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Center FAB
        Positioned(
          right: 14.w,
          bottom: 14.h,
          child: GestureDetector(
            onTap: () {
              if (myLocation != null) {
                mapController.move(myLocation!, 15);
              }
            },
            child: Container(
              width: 48.w,
              height: 48.w,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Symbols.my_location,
                color: AppColors.textDark,
                size: 22.w,
              ),
            ),
          ),
        ),

        // No location message
        if (myLocation == null)
          Center(
            child: Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.location_off,
                    size: 40.w,
                    color: AppColors.textMutedLight,
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Locating you...',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: AppColors.textMutedLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Placeholder Tab
// ─────────────────────────────────────────────────────────────────────────────

class _PlaceholderTab extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PlaceholderTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textMutedLight),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 16,
              color: AppColors.textMutedLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming soon',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13,
              color: AppColors.textMutedLight.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}
