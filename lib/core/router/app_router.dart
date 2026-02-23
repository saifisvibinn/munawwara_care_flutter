import 'package:go_router/go_router.dart';
import '../../features/splash/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/pilgrim/screens/pilgrim_dashboard_screen.dart';
import '../../features/moderator/screens/moderator_dashboard_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/pilgrim-dashboard',
        name: 'pilgrim-dashboard',
        builder: (context, state) => const PilgrimDashboardScreen(),
      ),
      GoRoute(
        path: '/moderator-dashboard',
        name: 'moderator-dashboard',
        builder: (context, state) => const ModeratorDashboardScreen(),
      ),
    ],
  );
}
