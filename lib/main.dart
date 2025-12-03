import 'package:sphere_with_drive/loadingfile.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'package:sphere_with_drive/firebase_options.dart';
import 'package:sphere_with_drive/auth_service.dart';
import 'package:sphere_with_drive/drive_service.dart';
import 'package:sphere_with_drive/loginpage.dart';
import 'package:sphere_with_drive/mainscreen.dart';

// --- 1. Main Function and Firebase Init ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase for configuration/client ID retrieval only.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const SnapSphereApp());
}

// --- 2. Auth Wrapper for Navigation ---
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        // If AuthService provides a loading/checking flag, use it to show a loading screen:
        // if (authService.isChecking) {
        //   return const BouncingBallLoadingScreen();
        // }

        if (authService.isAuthenticated) {
          return const HomeScreen();
        }

        // Otherwise, show the login screen
        return const LoginScreen();
      },
    );
  }
}

// --- 3. App Setup ---
class SnapSphereApp extends StatelessWidget {
  const SnapSphereApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // Use MultiProvider to manage multiple services
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        // DriveService depends on AuthService, so we use ProxyProvider
        ChangeNotifierProxyProvider<AuthService, DriveService>(
          // We provide the AuthService instance to the DriveService constructor
          create: (context) => DriveService(context.read<AuthService>()),
          // The update function ensures DriveService is updated if AuthService changes
          update: (context, auth, drive) => drive!..update(auth),
        ),
      ],
      child: MaterialApp(
        title: 'SnapSphere (Drive)',
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF121212),
          primaryColor: Colors.indigoAccent,
          colorScheme: const ColorScheme.dark(
            primary: Colors.indigoAccent,
            secondary: Colors.tealAccent,
            surface: Color(0xFF1E1E1E),
          ),
          textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Colors.indigoAccent,
            foregroundColor: Colors.white,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF2C2C2C),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.indigoAccent),
            ),
          ),
        ),
        home: const BouncingBallLoadingScreen(),
      ),
    );
  }
}
