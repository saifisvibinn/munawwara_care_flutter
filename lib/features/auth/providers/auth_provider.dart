import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';

// ── Auth State ────────────────────────────────────────────────────────────────

class AuthState {
  final bool isLoading;
  final String? error;
  final String? token;
  final String? role;
  final String? userId;
  final String? fullName;

  const AuthState({
    this.isLoading = false,
    this.error,
    this.token,
    this.role,
    this.userId,
    this.fullName,
  });

  bool get isAuthenticated => token != null;

  AuthState copyWith({
    bool? isLoading,
    String? error,
    String? token,
    String? role,
    String? userId,
    String? fullName,
    bool clearError = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      token: token ?? this.token,
      role: role ?? this.role,
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
    );
  }
}

// ── Auth Notifier ─────────────────────────────────────────────────────────────
// Uses Riverpod 3.x Notifier API (StateNotifier was removed in v3)

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restoreSession();
    return const AuthState();
  }

  // ── Restore session on startup ──────────────────────────────────────────────
  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final role = prefs.getString('user_role');
    final userId = prefs.getString('user_id');
    final fullName = prefs.getString('user_full_name');

    if (token != null) {
      ApiService.dio.options.headers['Authorization'] = 'Bearer $token';
      state = AuthState(
        token: token,
        role: role,
        userId: userId,
        fullName: fullName,
      );
    }
  }

  Future<void> _persistSession(
    String token,
    String role,
    String userId,
    String fullName,
  ) async {
    await ApiService.setAuthToken(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
    await prefs.setString('user_id', userId);
    await prefs.setString('user_full_name', fullName);
  }

  // ── Register Pilgrim ────────────────────────────────────────────────────────
  Future<bool> registerPilgrim({
    required String fullName,
    required String nationalId,
    required String phoneNumber,
    required String password,
    String? medicalHistory,
    int? age,
    String? gender,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final body = <String, dynamic>{
        'full_name': fullName,
        'national_id': nationalId,
        'phone_number': phoneNumber,
        'password': password,
      };
      if (medicalHistory != null && medicalHistory.isNotEmpty) {
        body['medical_history'] = medicalHistory;
      }
      if (age != null) body['age'] = age;
      if (gender != null) body['gender'] = gender;

      final response = await ApiService.dio.post('/auth/register', data: body);
      final data = response.data as Map<String, dynamic>;

      await _persistSession(
        data['token'] as String,
        data['role'] as String,
        data['user_id'] as String,
        data['full_name'] as String,
      );

      state = state.copyWith(
        isLoading: false,
        token: data['token'] as String,
        role: data['role'] as String,
        userId: data['user_id'] as String,
        fullName: data['full_name'] as String,
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
      return false;
    }
  }

  // ── Login ───────────────────────────────────────────────────────────────────
  Future<bool> login({
    required String identifier,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final response = await ApiService.dio.post(
        '/auth/login',
        data: {'identifier': identifier, 'password': password},
      );
      final data = response.data as Map<String, dynamic>;

      await _persistSession(
        data['token'] as String,
        data['role'] as String,
        data['user_id'] as String,
        data['full_name'] as String,
      );

      state = state.copyWith(
        isLoading: false,
        token: data['token'] as String,
        role: data['role'] as String,
        userId: data['user_id'] as String,
        fullName: data['full_name'] as String,
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
      return false;
    }
  }

  // ── Logout ──────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    await ApiService.clearAuthToken();
    state = const AuthState();
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
