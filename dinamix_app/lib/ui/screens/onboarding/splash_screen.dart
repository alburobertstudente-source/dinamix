import 'package:flutter/material.dart';

import '../../brand/logo.dart';

/// Animated splash: the mark and the wordmark draw themselves (≤ 1.2 s), then
/// [onDone]. With "reduce animations" it shows the final frame at once.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
    } else {
      _c.forward().whenComplete(() {
        if (mounted) widget.onDone();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = Curves.easeOutCubic.transform(_c.value);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(scale: 0.85 + 0.15 * v, child: DynamixMark(size: 112, progress: v)),
                const SizedBox(height: 26),
                DynamixWordmark(height: 30, progress: (v * 1.3 - 0.3).clamp(0, 1).toDouble()),
                const SizedBox(height: 14),
                Opacity(
                  opacity: (v * 2 - 1).clamp(0, 1).toDouble(),
                  child: Text('Analisi del movimento e degli urti',
                      style: TextStyle(color: muted, letterSpacing: 0.4)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
