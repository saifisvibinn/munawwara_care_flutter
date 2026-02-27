import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';

// ── Auth State ────────────────────────────────────────────────────────────────

class AuthState {
  final bool isLoading;
  final bool isRestoringSession;
  final String? error;
  final String? token;
  final String? role;
  final String? userId;
  final String? fullName;
  final String? email;
  final String? phoneNumber;

  const AuthState({
    this.isLoading = false,
    this.isRestoringSession = false,
    this.error,
    this.token,
    this.role,
    this.userId,
    this.fullName,
    this.email,
    this.phoneNumber,
  });

  bool get isAuthenticated => token != null;

  AuthState copyWith({
    bool? isLoading,
    bool? isRestoringSession,
    String? error,
    String? token,
    String? role,
    String? userId,
    String? fullName,
    String? email,
    String? phoneNumber,
    bool clearError = false,
    bool clearPhoneNumber = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isRestoringSession: isRestoringSession ?? this.isRestoringSession,
      error: clearError ? null : (error ?? this.error),
      token: token ?? this.token,
      role: role ?? this.role,
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phoneNumber: clearPhoneNumber ? null : (phoneNumber ?? this.phoneNumber),
    );
  }
}

// ── Auth Notifier ─────────────────────────────────────────────────────────────
// Uses Riverpod 3.x Notifier API (StateNotifier was removed in v3)

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restoreSession();
    return const AuthState(isRestoringSession: true);
  }

  // ── Restore session on startup ──────────────────────────────────────────────
  Future<void> _restoreSession() async {
    try {
      print('AuthNotifier: restoring session');
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final role = prefs.getString('user_role');
      final userId = prefs.getString('user_id');
      final fullName = prefs.getString('user_full_name');

      if (token != null) {
        ApiService.dio.options.headers['Authorization'] = 'Bearer $token';
        state = AuthState(
          isRestoringSession: false,
          token: token,
          role: role,
          userId: userId,
          fullName: fullName,
        );
      } else {
        state = const AuthState(isRestoringSession: false);
      }
      print('AuthNotifier: restore complete');
    } catch (e, st) {
      // If shared preferences fails for any reason, we still want to clear the
      // restoring flag so the UI can proceed. Log the error to console.
      print('AuthNotifier restoreSession error: $e\n$st');
      state = const AuthState(isRestoringSession: false);
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

  // ── Fetch profile ───────────────────────────────────────────────────────────
  Future<void> fetchProfile() async {
    try {
      final response = await ApiService.dio.get('/auth/me');
      final data = response.data as Map<String, dynamic>;
      state = state.copyWith(
        fullName: data['full_name'] as String?,
        email: data['email'] as String?,
        phoneNumber: data['phone_number'] as String?,
      );
      // Persist updated full_name to prefs
      if (data['full_name'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_full_name', data['full_name'] as String);
      }
    } on DioException catch (_) {
      // Silent — profile fetch failures shouldn't disrupt UX
    }
  }

  // ── Update profile ──────────────────────────────────────────────────────────
  Future<bool> updateProfile({
    required String fullName,
    String? phoneNumber,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final body = <String, dynamic>{'full_name': fullName};
      if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
        body['phone_number'] = phoneNumber.trim();
      }
      final response = await ApiService.dio.put(
        '/auth/update-profile',
        data: body,
      );
      final userData =
          (response.data as Map<String, dynamic>)['user']
              as Map<String, dynamic>;

      final newName = userData['full_name'] as String? ?? fullName;
      final newPhone = userData['phone_number'] as String?;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_full_name', newName);

      state = state.copyWith(
        isLoading: false,
        fullName: newName,
        phoneNumber: newPhone,
        clearError: true,
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
