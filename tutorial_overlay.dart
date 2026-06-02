import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/* ═══════════════════════════════════════════
   DATA MODEL
   ═══════════════════════════════════════════ */

class TutorialStep {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final IconData icon;
  final TooltipPosition preferredPosition;

  const TutorialStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.icon = Icons.info_outline_rounded,
    this.preferredPosition = TooltipPosition.auto,
  });
}

enum TooltipPosition { above, below, auto }

/* ═══════════════════════════════════════════
   CONTROLLER
   ═══════════════════════════════════════════ */

class TutorialController extends ChangeNotifier {
  final List<TutorialStep> steps;
  final String tutorialId;
  int _currentStep = 0;
  bool _isActive = false;

  TutorialController({
    required this.steps,
    this.tutorialId = 'dashboard_tutorial',
  });

  int get currentStep => _currentStep;
  bool get isActive => _isActive;
  bool get isFirstStep => _currentStep == 0;
  bool get isLastStep => _currentStep == steps.length - 1;
  int get totalSteps => steps.length;
  TutorialStep get current => steps[_currentStep];

  Future<void> startIfFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('${tutorialId}_done') ?? false;
    if (!done) {
      await Future.delayed(const Duration(milliseconds: 800));
      start();
    }
  }

  void start() {
    _currentStep = 0;
    _isActive = true;
    notifyListeners();
  }

  void next() {
    if (_currentStep < steps.length - 1) {
      _currentStep++;
      notifyListeners();
    } else {
      finish();
    }
  }

  void previous() {
    if (_currentStep > 0) {
      _currentStep--;
      notifyListeners();
    }
  }

  Future<void> skip() async => finish();

  Future<void> finish() async {
    _isActive = false;
    _currentStep = 0;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${tutorialId}_done', true);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${tutorialId}_done', false);
  }
}

/* ═══════════════════════════════════════════
   OVERLAY WIDGET
   ═══════════════════════════════════════════ */

class TutorialOverlay extends StatefulWidget {
  final TutorialController controller;
  final Widget child;
  const TutorialOverlay({
    super.key,
    required this.controller,
    required this.child,
  });
  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fade = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    widget.controller.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (widget.controller.isActive) {
      _animCtrl.forward(from: 0);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    _animCtrl.dispose();
    super.dispose();
  }

  Rect? _targetRect(GlobalKey key) {
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return null;
    final pos = ro.localToGlobal(Offset.zero);
    return Rect.fromLTWH(pos.dx, pos.dy, ro.size.width, ro.size.height);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.controller.isActive)
          FadeTransition(opacity: _fade, child: _overlay(context)),
      ],
    );
  }

  Widget _overlay(BuildContext ctx) {
    final step = widget.controller.current;
    final rect = _targetRect(step.targetKey);
    final size = MediaQuery.of(ctx).size;

    return Stack(
      children: [
        // Dark backdrop with spotlight
        GestureDetector(
          onTap: () {},
          child: CustomPaint(
            size: size,
            painter: _SpotlightPainter(targetRect: rect),
          ),
        ),

        // Pulsing border around target
        if (rect != null) _buildPulse(rect),

        // Tooltip
        _buildTooltip(ctx, step, rect, size),
      ],
    );
  }

  Widget _buildPulse(Rect rect) {
    final r = rect.inflate(8);
    return Positioned(
      left: r.left,
      top: r.top,
      child: _PulseRing(width: r.width, height: r.height),
    );
  }

  Widget _buildTooltip(
    BuildContext ctx,
    TutorialStep step,
    Rect? rect,
    Size screen,
  ) {
    if (rect == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _TooltipCard(
            step: step,
            controller: widget.controller,
          ),
        ),
      );
    }

    const maxW = 320.0;
    const margin = 16.0;

    final spaceBelow = screen.height - rect.bottom;
    final spaceAbove = rect.top;

    bool showBelow;
    switch (step.preferredPosition) {
      case TooltipPosition.below:
        showBelow = spaceBelow >= 180;
        break;
      case TooltipPosition.above:
        showBelow = spaceAbove < 180;
        break;
      case TooltipPosition.auto:
        showBelow = spaceBelow >= 200 || spaceBelow > spaceAbove;
    }

    double left = (rect.center.dx - maxW / 2).clamp(
      margin,
      screen.width - maxW - margin,
    );

    return Positioned(
      left: left,
      top: showBelow ? rect.bottom + 20 : null,
      bottom: !showBelow ? screen.height - rect.top + 20 : null,
      child: SizedBox(
        width: maxW,
        child: _TooltipCard(step: step, controller: widget.controller),
      ),
    );
  }
}

/* ═══════════════════════════════════════════
   SPOTLIGHT PAINTER
   ═══════════════════════════════════════════ */

class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  _SpotlightPainter({this.targetRect});

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.black.withOpacity(0.72);
    final full = Rect.fromLTWH(0, 0, size.width, size.height);

    if (targetRect == null) {
      canvas.drawRect(full, bg);
      return;
    }

    final hole = targetRect!.inflate(8);
    final path = Path()
      ..addRect(full)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(12)));
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, bg);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter o) =>
      o.targetRect != targetRect;
}

/* ═══════════════════════════════════════════
   PULSE RING ANIMATION
   ═══════════════════════════════════════════ */

class _PulseRing extends StatefulWidget {
  final double width, height;
  const _PulseRing({required this.width, required this.height});
  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.5 + 0.5 * _ctrl.value),
            width: 2 + _ctrl.value,
          ),
        ),
      ),
    );
  }
}

/* ═══════════════════════════════════════════
   TOOLTIP CARD
   ═══════════════════════════════════════════ */

class _TooltipCard extends StatelessWidget {
  final TutorialStep step;
  final TutorialController controller;
  const _TooltipCard({required this.step, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Green header ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1FAB64),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(step.icon, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${controller.currentStep + 1}/${controller.totalSteps}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Description ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Text(
                step.description,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),

            // ── Progress dots ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(controller.totalSteps, (i) {
                final active = i == controller.currentStep;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF1FAB64)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),

            // ── Buttons ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: controller.skip,
                    child: Text(
                      'Skip',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ),
                  const Spacer(),
                  if (!controller.isFirstStep)
                    TextButton.icon(
                      onPressed: controller.previous,
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: const Text('Back'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade600,
                      ),
                    ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: controller.next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1FAB64),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(controller.isLastStep ? 'Got it!' : 'Next'),
                        const SizedBox(width: 4),
                        Icon(
                          controller.isLastStep
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}