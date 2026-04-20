import 'package:flutter/material.dart';
import '../../core/theme.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _shimmerController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeIn),
    );

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );

    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    _runAnimation();
  }

  Future<void> _runAnimation() async {
    await Future.delayed(const Duration(milliseconds: 200));
    await _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 100));
    _textController.forward();
    _shimmerController.forward();
    await Future.delayed(const Duration(milliseconds: 1200));
    widget.onComplete();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VoltTheme.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo animado
            AnimatedBuilder(
              animation: _logoController,
              builder: (_, child) => Transform.scale(
                scale: _logoScale.value,
                child: Opacity(
                  opacity: _logoOpacity.value,
                  child: child,
                ),
              ),
              child: const Image(
                image: AssetImage('assets/icons/app_icon.png'),
                width: 140,
                height: 140,
              ),
            ),

            const SizedBox(height: 28),

            // Texto con shimmer
            AnimatedBuilder(
              animation: Listenable.merge([_textController, _shimmerController]),
              builder: (_, __) => SlideTransition(
                position: _textSlide,
                child: FadeTransition(
                  opacity: _textOpacity,
                  child: Column(
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) {
                          final shimmerPos = _shimmer.value;
                          return LinearGradient(
                            colors: const [
                              Color(0xFF6B21A8),
                              Color(0xFFD4829A),
                              Color(0xFFE8C07A),
                              Color(0xFFD4829A),
                              Color(0xFF6B21A8),
                            ],
                            stops: [
                              (shimmerPos - 0.4).clamp(0.0, 1.0),
                              (shimmerPos - 0.2).clamp(0.0, 1.0),
                              shimmerPos.clamp(0.0, 1.0),
                              (shimmerPos + 0.2).clamp(0.0, 1.0),
                              (shimmerPos + 0.4).clamp(0.0, 1.0),
                            ],
                          ).createShader(bounds);
                        },
                        child: const Text(
                          'KMD Volt',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'By: @urielovolt',
                        style: TextStyle(
                          color: VoltTheme.primaryLight,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
