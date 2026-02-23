import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/moderator_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Group Management Screen  (map-first + manage pilgrims/moderators)
// ─────────────────────────────────────────────────────────────────────────────

class GroupManagementScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String currentUserId;

  const GroupManagementScreen({
    super.key,
    required this.groupId,
    required this.currentUserId,
  });

  @override
  ConsumerState<GroupManagementScreen> createState() =>
      _GroupManagementScreenState();
}

class _GroupManagementScreenState
    extends ConsumerState<GroupManagementScreen> {
  final _mapController = MapController();
  final _dssController = DraggableScrollableController();
  final _searchController = TextEditingController();
  String _searchQuery = '';

  LatLng? _myLocation;
  StreamSubscription<Position>? _locationSub;
  bool _sosLoading = false;
  String? _focusedPilgrimId;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _searchController.addListener(() {
      if (mounted) setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    _dssController.dispose();
    _searchController.dispose();
    _locationSub?.cancel();
    super.dispose();
  }

  // ── Location ──────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted || !mounted) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      _mapController.move(_myLocation!, 15);
    } catch (_) {}
    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30,
      ),
    ).listen((pos) {
      if (mounted) {
        setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      }
    });
  }

  // ── Map helpers ───────────────────────────────────────────────────────────

  void _centerOnMe() {
    final target = _myLocation ?? const LatLng(21.3891, 39.8579);
    _mapController.move(target, 15);
  }

  void _centerOnGroup(ModeratorGroup group) {
    final located = group.pilgrims.where((p) => p.hasLocation).toList();
    if (located.isEmpty) {
      _centerOnMe();
      return;
    }
    final latAvg =
        located.map((p) => p.lat!).reduce((a, b) => a + b) / located.length;
    final lngAvg =
        located.map((p) => p.lng!).reduce((a, b) => a + b) / located.length;
    _mapController.move(LatLng(latAvg, lngAvg), 14);
  }

  void _focusPilgrim(PilgrimInGroup p) {
    if (!p.hasLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${p.firstName} has no location data yet')),
      );
      return;
    }
    setState(() => _focusedPilgrimId = p.id);
    _mapController.move(LatLng(p.lat!, p.lng!), 17);
    _dssController.animateTo(
      0.28,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _navigateToPilgrim(PilgrimInGroup p) async {
    if (!p.hasLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${p.firstName} has no location data')),
      );
      return;
    }
    final lat = p.lat!;
    final lng = p.lng!;
    final geoUri =
        Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeFull(p.fullName)})');
    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri);
    } else {
      final gmUrl = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking');
      if (await canLaunchUrl(gmUrl)) {
        await launchUrl(gmUrl, mode: LaunchMode.externalApplication);
      }
    }
  }

  // ── SOS broadcast ─────────────────────────────────────────────────────────

  Future<void> _broadcastSOS(ModeratorGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text(
          '🚨 Broadcast Emergency SOS?',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 16.sp,
            color: Colors.red.shade700,
          ),
        ),
        content: Text(
          'This will send an urgent SOS message to all pilgrims in ${group.groupName}.',
          style: TextStyle(fontFamily: 'Lexend', fontSize: 14.sp),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TextStyle(
                    fontFamily: 'Lexend', color: AppColors.textMutedLight)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.r)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send SOS',
                style: TextStyle(
                    fontFamily: 'Lexend', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _sosLoading = true);
    final ok = await ref.read(moderatorProvider.notifier).broadcastSOS();
    if (!mounted) return;
    setState(() => _sosLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? Colors.red.shade700 : Colors.grey.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      content: Text(
        ok ? '🚨 SOS broadcast sent!' : 'Failed to send SOS. Try again.',
        style: const TextStyle(color: Colors.white, fontFamily: 'Lexend'),
      ),
    ));
  }

  // ── Add Pilgrim ───────────────────────────────────────────────────────────

  Future<void> _showAddPilgrimOptions(ModeratorGroup group) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddPilgrimChoiceSheet(
        group: group,
        onManual: () async {
          Navigator.pop(ctx);
          await _showAddPilgrimManual(group);
        },
        onQr: () async {
          Navigator.pop(ctx);
          await _showQrSheet(group);
        },
      ),
    );
  }

  Future<void> _showAddPilgrimManual(ModeratorGroup group) async {
    final ctrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          bool loading = false;
          String? fieldError;

          Future<void> submit() async {
            final val = ctrl.text.trim();
            if (val.isEmpty) {
              setSheetState(() => fieldError = 'Enter an identifier');
              return;
            }
            setSheetState(() {
              loading = true;
              fieldError = null;
            });
            final (ok, err) = await ref
                .read(moderatorProvider.notifier)
                .addPilgrimToGroup(group.id, val);
            if (ctx.mounted) {
              if (ok) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pilgrim added successfully!')),
                );
              } else {
                setSheetState(() {
                  loading = false;
                  fieldError = err ?? 'Failed to add pilgrim';
                });
              }
            }
          }

          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24.r)),
              ),
              padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 28.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2.r),
                      ),
                    ),
                  ),
                  SizedBox(height: 20.h),
                  Row(
                    children: [
                      Container(
                        width: 40.w,
                        height: 40.w,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Symbols.person_add,
                            color: AppColors.primary, size: 20.w),
                      ),
                      SizedBox(width: 12.w),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Pilgrim',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w700,
                              fontSize: 18.sp,
                              color: AppColors.textDark,
                            ),
                          ),
                          Text(
                            'Email, phone, or national ID',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12.sp,
                              color: AppColors.textMutedLight,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 20.h),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: AppColors.textDark,
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g. +966501234567 or 1234567890',
                      hintStyle: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13.sp,
                          color: AppColors.textMutedLight),
                      errorText: fieldError,
                      prefixIcon: Icon(Symbols.search,
                          size: 20.w, color: AppColors.textMutedLight),
                      filled: true,
                      fillColor: const Color(0xFFF6F8F7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide:
                            BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          vertical: 14.h, horizontal: 16.w),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  SizedBox(height: 16.h),
                  SizedBox(
                    width: double.infinity,
                    height: 52.h,
                    child: ElevatedButton(
                      onPressed: loading ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                        elevation: 0,
                      ),
                      child: loading
                          ? SizedBox(
                              width: 20.w,
                              height: 20.w,
                              child: const CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'Add to Group',
                              style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15.sp),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showQrSheet(ModeratorGroup group) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _QrShareSheet(group: group),
    );
  }

  // ── Remove pilgrim ────────────────────────────────────────────────────────

  Future<void> _confirmRemovePilgrim(
      ModeratorGroup group, PilgrimInGroup pilgrim) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text(
          'Remove Pilgrim?',
          style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 17.sp),
        ),
        content: Text(
          'Remove ${pilgrim.fullName} from this group?',
          style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14.sp,
              color: AppColors.textMutedLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(
                    fontFamily: 'Lexend',
                    color: AppColors.textMutedLight)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove',
                style: TextStyle(
                    fontFamily: 'Lexend',
                    color: Colors.red,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final (ok, err) = await ref
          .read(moderatorProvider.notifier)
          .removePilgrimFromGroup(group.id, pilgrim.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? '${pilgrim.firstName} removed'
              : err ?? 'Failed to remove'),
          backgroundColor: ok ? null : Colors.red,
        ));
      }
    }
  }

  // ── Moderator management sheet ────────────────────────────────────────────

  void _showManageSheet(ModeratorGroup group) {
    // Refresh group data in the background so the moderator list is always up-to-date
    ref.read(moderatorProvider.notifier).refreshGroup(group.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ModeratorManageSheet(
        group: group,
        currentUserId: widget.currentUserId,
        isCreator: group.createdBy == widget.currentUserId,
      ),
    );
  }

  // ── Filtered list ─────────────────────────────────────────────────────────

  List<PilgrimInGroup> _getFiltered(ModeratorGroup group) {
    if (_searchQuery.isEmpty) return group.pilgrims;
    final q = _searchQuery.toLowerCase();
    return group.pilgrims.where((p) {
      return p.fullName.toLowerCase().contains(q) ||
          (p.nationalId?.toLowerCase().contains(q) ?? false) ||
          (p.phoneNumber?.contains(q) ?? false);
    }).toList();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final group = ref
        .watch(moderatorProvider)
        .groups
        .cast<ModeratorGroup?>()
        .firstWhere((g) => g?.id == widget.groupId, orElse: () => null);

    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group')),
        body: const Center(child: Text('Group not found')),
      );
    }

    final locatedPilgrims =
        group.pilgrims.where((p) => p.hasLocation).toList();
    final filtered = _getFiltered(group);

    return Scaffold(
      body: Stack(
        children: [
          // ── Map (full screen) ─────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation ?? const LatLng(21.3891, 39.8579),
              initialZoom: 14,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.munawwaracare.app',
              ),
              if (_myLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _myLocation!,
                      width: 20.w,
                      height: 20.w,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (var p in locatedPilgrims)
                    Marker(
                      point: LatLng(p.lat!, p.lng!),
                      width: 64.w,
                      height: 72.h,
                      child: GestureDetector(
                        onTap: () => _focusPilgrim(p),
                        child: _PilgrimMapMarker(
                          pilgrim: p,
                          isSelected: _focusedPilgrimId == p.id,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // ── Top overlay bar ───────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 0),
                child: Row(
                  children: [
                    _CircleButton(
                      icon: Symbols.arrow_back,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    SizedBox(width: 10.w),
                    Flexible(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 14.w, vertical: 10.h),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14.r),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 30.w,
                              height: 30.w,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Symbols.group,
                                  color: AppColors.primary, size: 16.w),
                            ),
                            SizedBox(width: 8.w),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    group.groupName,
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.sp,
                                      color: AppColors.textDark,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${group.onlineCount}/${group.totalPilgrims} Online',
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 11.sp,
                                      color: AppColors.textMutedLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    _CircleButton(
                      icon: Symbols.settings,
                      onTap: () => _showManageSheet(group),
                    ),
                    SizedBox(width: 8.w),
                    GestureDetector(
                      onTap: _sosLoading
                          ? null
                          : () => _broadcastSOS(group),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 12.w, vertical: 10.h),
                        decoration: BoxDecoration(
                          color: Colors.red.shade600,
                          borderRadius: BorderRadius.circular(14.r),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _sosLoading
                            ? SizedBox(
                                width: 18.w,
                                height: 18.w,
                                child: const CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Symbols.cell_tower,
                                      size: 18.w, color: Colors.white),
                                  SizedBox(width: 5.w),
                                  Text(
                                    'SOS',
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.sp,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Right-side map FABs ───────────────────────────────────────────
          Positioned(
            right: 14.w,
            bottom: 230.h,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MapFab(icon: Symbols.my_location, onTap: _centerOnMe),
                SizedBox(height: 10.h),
                _MapFab(
                  icon: Symbols.group,
                  onTap: () => _centerOnGroup(group),
                ),
              ],
            ),
          ),

          // ── Add Pilgrim FAB (bottom-left) ─────────────────────────────────
          Positioned(
            left: 14.w,
            bottom: 230.h,
            child: GestureDetector(
              onTap: () => _showAddPilgrimOptions(group),
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(16.r),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Symbols.person_add, size: 18.w, color: Colors.white),
                    SizedBox(width: 6.w),
                    Text(
                      'Add Pilgrim',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 13.sp,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Pilgrim list sheet ────────────────────────────────────────────
          DraggableScrollableSheet(
            controller: _dssController,
            initialChildSize: 0.28,
            minChildSize: 0.1,
            maxChildSize: 0.72,
            snap: true,
            snapSizes: const [0.1, 0.28, 0.72],
            builder: (ctx, scrollController) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24.r)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Drag handle
                  Padding(
                    padding: EdgeInsets.only(top: 12.h, bottom: 8.h),
                    child: Container(
                      width: 36.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(2.r),
                      ),
                    ),
                  ),
                  // Sheet header
                  Padding(
                    padding:
                        EdgeInsets.fromLTRB(16.w, 0, 16.w, 10.h),
                    child: Row(
                      children: [
                        Text(
                          '${group.totalPilgrims} Pilgrims',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 15.sp,
                            color: AppColors.textDark,
                          ),
                        ),
                        const Spacer(),
                        if (group.sosCount > 0)
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1F2),
                              borderRadius: BorderRadius.circular(100.r),
                              border: Border.all(
                                  color: const Color(0xFFFFE4E6)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Symbols.warning,
                                    size: 12.w,
                                    color: const Color(0xFFDC2626),
                                    fill: 1),
                                SizedBox(width: 3.w),
                                Text(
                                  '${group.sosCount} SOS',
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.sp,
                                    color: const Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Search bar
                  Padding(
                    padding:
                        EdgeInsets.fromLTRB(16.w, 0, 16.w, 10.h),
                    child: Container(
                      height: 40.h,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F8F7),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13.sp,
                          color: AppColors.textDark,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search pilgrims...',
                          hintStyle: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13.sp,
                            color: AppColors.textMutedLight,
                          ),
                          prefixIcon: Icon(Symbols.search,
                              size: 18.w,
                              color: AppColors.textMutedLight),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Symbols.close,
                                      size: 16.w,
                                      color: AppColors.textMutedLight),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 11.h),
                        ),
                      ),
                    ),
                  ),
                  // Pilgrim tiles
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isNotEmpty
                                  ? 'No matches'
                                  : 'No pilgrims yet',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                color: AppColors.textMutedLight,
                                fontSize: 13.sp,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding:
                                EdgeInsets.fromLTRB(16.w, 0, 16.w, 24.h),
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final p = filtered[i];
                              return _PilgrimManageTile(
                                pilgrim: p,
                                isSelected: _focusedPilgrimId == p.id,
                                onTap: () => _focusPilgrim(p),
                                onNavigate: () => _navigateToPilgrim(p),
                                onRemove: () =>
                                    _confirmRemovePilgrim(group, p),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Pilgrim choice sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AddPilgrimChoiceSheet extends StatelessWidget {
  final ModeratorGroup group;
  final VoidCallback onManual;
  final VoidCallback onQr;

  const _AddPilgrimChoiceSheet({
    required this.group,
    required this.onManual,
    required this.onQr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 32.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'Add Pilgrim',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 18.sp,
              color: AppColors.textDark,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'How would you like to add a pilgrim?',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              color: AppColors.textMutedLight,
            ),
          ),
          SizedBox(height: 24.h),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onManual,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        vertical: 20.h, horizontal: 12.w),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 52.w,
                          height: 52.w,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Symbols.person_search,
                              color: Colors.white, size: 26.w),
                        ),
                        SizedBox(height: 12.h),
                        Text(
                          'Add Manually',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 14.sp,
                            color: AppColors.textDark,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Search by email, phone or ID',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 11.sp,
                            color: AppColors.textMutedLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: GestureDetector(
                  onTap: onQr,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        vertical: 20.h, horizontal: 12.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8C97A).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(
                          color:
                              const Color(0xFFE8C97A).withOpacity(0.4)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 52.w,
                          height: 52.w,
                          decoration: const BoxDecoration(
                            color: Color(0xFFB0924A),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Symbols.qr_code,
                              color: Colors.white, size: 26.w),
                        ),
                        SizedBox(height: 12.h),
                        Text(
                          'Share QR Code',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 14.sp,
                            color: AppColors.textDark,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Pilgrim scans to join group',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 11.sp,
                            color: AppColors.textMutedLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QR share bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _QrShareSheet extends StatefulWidget {
  final ModeratorGroup group;
  const _QrShareSheet({required this.group});

  @override
  State<_QrShareSheet> createState() => _QrShareSheetState();
}

class _QrShareSheetState extends State<_QrShareSheet> {
  Uint8List? _qrBytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadQr();
  }

  Future<void> _loadQr() async {
    try {
      final resp =
          await ApiService.dio.get('/groups/${widget.group.id}/qr');
      final qrCode = resp.data['qr_code'] as String?;
      if (qrCode != null) {
        final b64 =
            qrCode.contains(',') ? qrCode.split(',').last : qrCode;
        setState(() {
          _qrBytes = base64Decode(b64);
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'QR not available';
        });
      }
    } on DioException catch (e) {
      setState(() {
        _loading = false;
        _error = ApiService.parseError(e);
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 32.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'Scan to Join',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 18.sp,
              color: AppColors.textDark,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'Share this QR code with your pilgrims',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12.sp,
              color: AppColors.textMutedLight,
            ),
          ),
          SizedBox(height: 20.h),
          Container(
            width: 200.w,
            height: 200.w,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE8C97A), width: 2),
              borderRadius: BorderRadius.circular(12.r),
              color: Colors.white,
            ),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 12.sp,
                                color: Colors.red)))
                    : _qrBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10.r),
                            child:
                                Image.memory(_qrBytes!, fit: BoxFit.contain),
                          )
                        : const SizedBox.shrink(),
          ),
          SizedBox(height: 16.h),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8F7),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                  color: const Color(0xFFE8C97A).withOpacity(0.5)),
            ),
            padding:
                EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GROUP CODE',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFB0924A),
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      widget.group.groupCode,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 22.sp,
                        letterSpacing: 4,
                        color: const Color(0xFFB0924A),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(
                        ClipboardData(text: widget.group.groupCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Group code copied!')),
                    );
                  },
                  child: Container(
                    width: 36.w,
                    height: 36.w,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8C97A).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(Symbols.content_copy,
                        size: 18.w, color: const Color(0xFFB0924A)),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          SizedBox(
            width: double.infinity,
            height: 50.h,
            child: OutlinedButton.icon(
              onPressed: () {
                Share.share(
                  'Join my Munawwara group!\n\nGroup: ${widget.group.groupName}\nCode: ${widget.group.groupCode}\n\nDownload the Munawwara Care app and enter this code to join.',
                  subject: 'Join ${widget.group.groupName}',
                );
              },
              icon: Icon(Symbols.share, size: 18.w, color: AppColors.primary),
              label: Text(
                'Share Invite Link',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 14.sp,
                  color: AppColors.primary,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Moderator management bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ModeratorManageSheet extends ConsumerWidget {
  final ModeratorGroup group;
  final String currentUserId;
  final bool isCreator;

  const _ModeratorManageSheet({
    required this.group,
    required this.currentUserId,
    required this.isCreator,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveGroup = ref
            .watch(moderatorProvider)
            .groups
            .cast<ModeratorGroup?>()
            .firstWhere((g) => g?.id == group.id, orElse: () => null) ??
        group;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 32.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'Moderators',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 17.sp,
              color: AppColors.textDark,
            ),
          ),
          if (!isCreator) ...[
            SizedBox(height: 4.h),
            Text(
              'Only the group creator can add or remove moderators.',
              style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 11.sp,
                  color: AppColors.textMutedLight),
            ),
          ],
          SizedBox(height: 12.h),
          ...liveGroup.moderators.map((mod) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 20.r,
                  backgroundColor:
                      const Color(0xFF6C63FF).withOpacity(0.15),
                  child: Text(
                    mod.initials,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 12.sp,
                      color: const Color(0xFF6C63FF),
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        mod.fullName,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 14.sp,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    if (mod.id == liveGroup.createdBy)
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 8.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFE8C97A).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20.r),
                        ),
                        child: Text(
                          'Creator',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFB0924A),
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: mod.email != null
                    ? Text(mod.email!,
                        style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 11.sp,
                            color: AppColors.textMutedLight))
                    : null,
                trailing: (isCreator && mod.id != liveGroup.createdBy)
                    ? GestureDetector(
                        onTap: () async {
                          final (ok, err) = await ref
                              .read(moderatorProvider.notifier)
                              .removeModeratorFromGroup(liveGroup.id, mod.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                              content: Text(ok
                                  ? '${mod.fullName} removed'
                                  : err ?? 'Failed'),
                              backgroundColor: ok ? null : Colors.red,
                            ));
                          }
                        },
                        child: Container(
                          width: 34.w,
                          height: 34.w,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Symbols.person_remove,
                              size: 16.w, color: Colors.red),
                        ),
                      )
                    : null,
              )),
          if (isCreator) ...[
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              height: 50.h,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await _showInviteSheet(context, ref, liveGroup);
                },
                icon: Icon(Symbols.person_add,
                    size: 18.w, color: const Color(0xFF6C63FF)),
                label: Text(
                  'Invite Co-Moderator',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 14.sp,
                    color: const Color(0xFF6C63FF),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                      color: Color(0xFF6C63FF), width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showInviteSheet(
      BuildContext context, WidgetRef ref, ModeratorGroup g) async {
    final ctrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          bool loading = false;
          String? fieldError;

          Future<void> submit() async {
            final val = ctrl.text.trim();
            if (val.isEmpty || !val.contains('@')) {
              setSheetState(() => fieldError = 'Enter a valid email');
              return;
            }
            setSheetState(() {
              loading = true;
              fieldError = null;
            });
            final (ok, err) = await ref
                .read(moderatorProvider.notifier)
                .inviteModerator(g.id, val);
            if (ctx.mounted) {
              if (ok) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          "Invitation sent! They'll receive an email.")),
                );
              } else {
                setSheetState(() {
                  loading = false;
                  fieldError = err ?? 'Failed';
                });
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24.r)),
              ),
              padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 28.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2.r),
                      ),
                    ),
                  ),
                  SizedBox(height: 20.h),
                  Text(
                    'Invite Co-Moderator',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 18.sp,
                      color: AppColors.textDark,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'An invitation email will be sent to them',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      color: AppColors.textMutedLight,
                    ),
                  ),
                  SizedBox(height: 20.h),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: AppColors.textDark,
                    ),
                    decoration: InputDecoration(
                      hintText: 'moderator@email.com',
                      hintStyle: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13.sp,
                          color: AppColors.textMutedLight),
                      errorText: fieldError,
                      prefixIcon: Icon(Symbols.email,
                          size: 20.w, color: AppColors.textMutedLight),
                      filled: true,
                      fillColor: const Color(0xFFF6F8F7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: const BorderSide(
                            color: Color(0xFF6C63FF), width: 1.5),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          vertical: 14.h, horizontal: 16.w),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  SizedBox(height: 16.h),
                  SizedBox(
                    width: double.infinity,
                    height: 52.h,
                    child: ElevatedButton(
                      onPressed: loading ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                        elevation: 0,
                      ),
                      child: loading
                          ? SizedBox(
                              width: 20.w,
                              height: 20.w,
                              child: const CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'Send Invitation',
                              style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15.sp),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim tile in the bottom sheet (focus + navigate + remove)
// ─────────────────────────────────────────────────────────────────────────────

class _PilgrimManageTile extends StatelessWidget {
  final PilgrimInGroup pilgrim;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onNavigate;
  final VoidCallback onRemove;

  const _PilgrimManageTile({
    required this.pilgrim,
    required this.isSelected,
    required this.onTap,
    required this.onNavigate,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final battColor = switch (pilgrim.batteryStatus) {
      BatteryStatus.good => const Color(0xFF16A34A),
      BatteryStatus.medium => const Color(0xFFF59E0B),
      BatteryStatus.low => const Color(0xFFDC2626),
      BatteryStatus.unknown => AppColors.textMutedLight,
    };

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.08)
              : pilgrim.hasSOS
                  ? const Color(0xFFFFF1F2)
                  : const Color(0xFFF6F8F7),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withOpacity(0.4)
                : pilgrim.hasSOS
                    ? const Color(0xFFFFE4E6)
                    : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Avatar + online/location dot
            Stack(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: pilgrim.hasSOS
                        ? const Color(0xFFDC2626)
                        : AppColors.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: pilgrim.hasSOS
                        ? Icon(Symbols.warning,
                            color: Colors.white, size: 18.w, fill: 1)
                        : Text(
                            pilgrim.initials,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w700,
                              fontSize: 13.sp,
                              color: AppColors.primaryDark,
                            ),
                          ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 10.w,
                    height: 10.w,
                    decoration: BoxDecoration(
                      color: pilgrim.hasLocation ? AppColors.primary : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(width: 10.w),
            // Name + last seen
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pilgrim.fullName,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 13.sp,
                      color: AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (pilgrim.lastSeenText.isNotEmpty)
                    Text(
                      pilgrim.lastSeenText,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 11.sp,
                        color: AppColors.textMutedLight,
                      ),
                    ),
                ],
              ),
            ),
            // Battery
            if (pilgrim.batteryPercent != null) ...[
              SizedBox(width: 6.w),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.battery_5_bar, size: 12.w, color: battColor),
                  SizedBox(width: 2.w),
                  Text(
                    '${pilgrim.batteryPercent}%',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 10.sp,
                      color: battColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            SizedBox(width: 8.w),
            // Navigate button (opens phone's map app)
            GestureDetector(
              onTap: onNavigate,
              child: Container(
                width: 32.w,
                height: 32.w,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(Symbols.near_me, size: 15.w, color: AppColors.primary),
              ),
            ),
            SizedBox(width: 6.w),
            // Remove button
            GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 32.w,
                height: 32.w,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Symbols.delete_outline, size: 15.w, color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim map marker
// ─────────────────────────────────────────────────────────────────────────────

class _PilgrimMapMarker extends StatelessWidget {
  final PilgrimInGroup pilgrim;
  final bool isSelected;

  const _PilgrimMapMarker({
    required this.pilgrim,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSOS = pilgrim.hasSOS;
    final color = isSOS ? const Color(0xFFDC2626) : AppColors.primaryDark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isSelected ? 42.w : 36.w,
          height: isSelected ? 42.w : 36.w,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.amber : Colors.white,
              width: isSelected ? 3 : 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(isSelected ? 0.7 : 0.45),
                blurRadius: isSelected ? 12 : 8,
                spreadRadius: isSelected ? 4 : 2,
              ),
            ],
          ),
          child: isSOS
              ? Icon(Symbols.warning,
                  color: Colors.white, size: 18.w, fill: 1)
              : Center(
                  child: Text(
                    pilgrim.initials,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: isSelected ? 12.sp : 10.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
        ),
        CustomPaint(
          size: Size(10.w, 6.h),
          painter: _MarkerTailPainter(color: color),
        ),
      ],
    );
  }
}

class _MarkerTailPainter extends CustomPainter {
  final Color color;
  const _MarkerTailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MarkerTailPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42.w,
        height: 42.w,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20.w, color: AppColors.textDark),
      ),
    );
  }
}

class _MapFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapFab({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44.w,
        height: 44.w,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20.w, color: AppColors.textDark),
      ),
    );
  }
}
