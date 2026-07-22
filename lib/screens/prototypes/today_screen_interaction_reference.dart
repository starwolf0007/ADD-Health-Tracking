/// APPROVED INTERACTION REFERENCE
///
/// Passed physical-device testing.
/// Do not modify during production integration.
/// Production TodayScreen must preserve these interaction behaviors.
// lib/screens/today_screen.dart
import 'package:flutter/material.dart';

enum DayPlanStatus {
  loading,
  proposalReady,
  requiresAttention,
  reviewing,
  partiallyAccepted,
  accepted,
  rejected,
  ambient,
  unavailable,
  error,
}

enum MockDayScenario { normalWorkday, overloadedDay, lowEnergyDay, lateAppointment }
enum BlockType { anchor, flex, runway, recoveryBuffer, openSpace }
enum ProposalDecision { notApplicable, pending, accepted, rejected }

class ScheduleBlock {
  final String id;
  final String title;
  final TimeOfDay start;
  final TimeOfDay end;
  final BlockType type;
  final String? explanation;
  final bool isLocked;
  final ProposalDecision decision;

  const ScheduleBlock({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.type,
    this.explanation,
    this.isLocked = false,
    this.decision = ProposalDecision.pending,
  });

  ScheduleBlock copyWith({
    ProposalDecision? decision,
  }) {
    return ScheduleBlock(
      id: id,
      title: title,
      start: start,
      end: end,
      type: type,
      explanation: explanation,
      isLocked: isLocked,
      decision: decision ?? this.decision,
    );
  }
}

class UndoSnapshot {
  final List<ScheduleBlock> blocks;
  final DayPlanStatus status;
  final MockDayScenario scenario;

  const UndoSnapshot({
    required this.blocks,
    required this.status,
    required this.scenario,
  });
}

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  MockDayScenario _baseScenario = MockDayScenario.normalWorkday;
  MockDayScenario _scenario = MockDayScenario.normalWorkday;
  DayPlanStatus _status = DayPlanStatus.proposalReady;

  List<ScheduleBlock> _originalBlocks = [];
  List<ScheduleBlock> _currentBlocks = [];
  UndoSnapshot? _undoSnapshot;

  final TimeOfDay _mockNow = const TimeOfDay(hour: 10, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadScenario(MockDayScenario.normalWorkday);
  }

  void _loadScenario(MockDayScenario scenario) {
    final blocks = _generateBlocksForScenario(scenario);
    setState(() {
      _baseScenario = scenario;
      _scenario = scenario;
      _status = DayPlanStatus.proposalReady;
      _originalBlocks = List.unmodifiable(blocks);
      _currentBlocks = List.of(blocks);
      _undoSnapshot = null;
    });
  }

  void _simulateDisruption() {
    setState(() {
      _undoSnapshot = UndoSnapshot(blocks: List.of(_currentBlocks), status: _status, scenario: _scenario);
      _scenario = MockDayScenario.lateAppointment;
      _currentBlocks = _generateBlocksForScenario(_scenario);
      _status = DayPlanStatus.requiresAttention;
    });
  }

  void _undo() {
    if (_undoSnapshot != null) {
      setState(() {
        _currentBlocks = List.of(_undoSnapshot!.blocks);
        _status = _undoSnapshot!.status;
        _scenario = _undoSnapshot!.scenario;
        _undoSnapshot = null;
      });
    }
  }

  void _keepOriginal() {
    setState(() {
      _undoSnapshot = UndoSnapshot(blocks: List.of(_currentBlocks), status: _status, scenario: _scenario);
      _scenario = _baseScenario;
      _currentBlocks = List.of(_originalBlocks);
      _status = DayPlanStatus.rejected;
    });
  }

  void _notNow() {
    setState(() {
      _undoSnapshot = UndoSnapshot(blocks: List.of(_currentBlocks), status: _status, scenario: _scenario);
      _scenario = _baseScenario;
      _currentBlocks = List.of(_originalBlocks);
      _status = DayPlanStatus.ambient;
    });
  }

  void _keepDayOpen() {
    setState(() {
      _scenario = _baseScenario;
      _currentBlocks = List.of(_originalBlocks);
      _status = DayPlanStatus.ambient;
    });
  }

  bool _isSelectable(ScheduleBlock block) => !block.isLocked && block.decision != ProposalDecision.notApplicable;

  void _toggleBlock(String id) {
    setState(() {
      _currentBlocks = _currentBlocks.map((block) {
        if (!_isSelectable(block)) return block;
        if (block.id == id) {
          final newDecision = block.decision == ProposalDecision.accepted
              ? ProposalDecision.pending
              : ProposalDecision.accepted;
          return block.copyWith(decision: newDecision);
        }
        return block;
      }).toList();
    });
  }

  void _finishReview() {
    final selectable = _currentBlocks.where(_isSelectable).toList();
    final acceptedCount = selectable.where((block) => block.decision == ProposalDecision.accepted).length;

    setState(() {
      _undoSnapshot = UndoSnapshot(blocks: List.of(_currentBlocks), status: DayPlanStatus.reviewing, scenario: _scenario);

      if (acceptedCount == 0) {
        _scenario = _baseScenario;
        _currentBlocks = List.of(_originalBlocks);
        _status = DayPlanStatus.rejected;
      } else {
        _currentBlocks = _currentBlocks.where((block) => !_isSelectable(block) || block.decision == ProposalDecision.accepted).toList();
        _status = acceptedCount == selectable.length ? DayPlanStatus.accepted : DayPlanStatus.partiallyAccepted;
      }
    });
  }

  void _acceptDay() {
    setState(() {
      _undoSnapshot = UndoSnapshot(blocks: List.of(_currentBlocks), status: _status, scenario: _scenario);
      _currentBlocks = _currentBlocks.map((block) {
        return _isSelectable(block) ? block.copyWith(decision: ProposalDecision.accepted) : block;
      }).toList();
      _status = DayPlanStatus.accepted;
    });
  }

  bool _isNow(ScheduleBlock block, TimeOfDay now) {
    int minutes(TimeOfDay value) => value.hour * 60 + value.minute;
    final current = minutes(now);
    return current >= minutes(block.start) && current < minutes(block.end);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Today', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<DayPlanStatus>(
            icon: const Icon(Icons.developer_mode, color: Colors.blueGrey),
            tooltip: 'Dev: Force Status',
            onSelected: (s) => setState(() => _status = s),
            itemBuilder: (_) => DayPlanStatus.values.map((s) => PopupMenuItem(value: s, child: Text(s.name))).toList(),
          ),
          IconButton(
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            tooltip: 'Simulate Disruption',
            onPressed: _simulateDisruption,
          ),
          PopupMenuButton<MockDayScenario>(
            icon: const Icon(Icons.bug_report, color: Colors.grey),
            tooltip: 'Load Scenario',
            onSelected: _loadScenario,
            itemBuilder: (_) => MockDayScenario.values.map((s) => PopupMenuItem(value: s, child: Text(s.name))).toList(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LexiScene(status: _status, briefing: _getBriefing(_status, _scenario)),
            const SizedBox(height: 28),

            // Contextual Actions
            if (_status == DayPlanStatus.loading) ...[
              const Center(child: CircularProgressIndicator(color: Color(0xFF2FB083))),
              const SizedBox(height: 12),
            ] else if (_status == DayPlanStatus.error) ...[
              Center(child: _ActionButton(label: 'Retry / Review Timeline', color: Colors.orange, onPressed: () => setState(() => _status = DayPlanStatus.proposalReady))),
              const SizedBox(height: 12),
            ] else if (_status == DayPlanStatus.unavailable) ...[
              Center(child: _ActionButton(label: 'Keep Day Open', color: Colors.orange, onPressed: _keepDayOpen)),
              const SizedBox(height: 12),
            ] else if (_status == DayPlanStatus.proposalReady || _status == DayPlanStatus.requiresAttention) ...[
              Row(
                children: [
                  Expanded(child: _ActionButton(label: 'Accept Day', color: const Color(0xFF2FB083), onPressed: _acceptDay)),
                  const SizedBox(width: 12),
                  Expanded(child: _ActionButton(label: 'Review Plan', color: Colors.grey.shade800, onPressed: () => setState(() => _status = DayPlanStatus.reviewing))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(onPressed: _notNow, child: const Text('Not now', style: TextStyle(color: Colors.grey))),
                  const SizedBox(width: 20),
                  TextButton(onPressed: _keepOriginal, child: const Text('Keep original', style: TextStyle(color: Colors.grey))),
                ],
              ),
            ],

            if (_status == DayPlanStatus.reviewing) ...[
              Center(child: _ActionButton(label: 'Done Reviewing', color: const Color(0xFF2FB083), onPressed: _finishReview)),
              const SizedBox(height: 12),
            ],

            if (_undoSnapshot != null && _status != DayPlanStatus.reviewing) ...[
              Center(
                child: TextButton.icon(
                  onPressed: _undo,
                  icon: const Icon(Icons.undo, size: 18, color: Colors.grey),
                  label: const Text('Undo last change', style: TextStyle(color: Colors.grey)),
                ),
              ),
            ],

            const SizedBox(height: 28),
            const Text("Today's Flow", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 14),

            ..._currentBlocks.map((b) => _ScheduleBlockWidget(
              block: b,
              isReviewing: _status == DayPlanStatus.reviewing,
              isNow: _isNow(b, _mockNow),
              isSelectable: _isSelectable(b),
              onToggle: () => _toggleBlock(b.id),
            )),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Scenario data
  // ------------------------------------------------------------------
  List<ScheduleBlock> _generateBlocksForScenario(MockDayScenario scenario) {
    final baseAnchors = [
      const ScheduleBlock(id: '1', title: 'Commute', start: TimeOfDay(hour: 5, minute: 40), end: TimeOfDay(hour: 6, minute: 0), type: BlockType.anchor, isLocked: true, decision: ProposalDecision.notApplicable),
      const ScheduleBlock(id: '2', title: 'Gas Compliance Shift', start: TimeOfDay(hour: 6, minute: 0), end: TimeOfDay(hour: 14, minute: 30), type: BlockType.anchor, isLocked: true, decision: ProposalDecision.notApplicable),
    ];

    final standardCommuteHome = const ScheduleBlock(id: '3', title: 'Commute Home', start: TimeOfDay(hour: 14, minute: 30), end: TimeOfDay(hour: 14, minute: 50), type: BlockType.anchor, isLocked: true, decision: ProposalDecision.notApplicable);

    switch (scenario) {
      case MockDayScenario.normalWorkday:
        return [
          ...baseAnchors,
          standardCommuteHome,
          const ScheduleBlock(id: '4', title: 'Recovery Buffer', start: TimeOfDay(hour: 14, minute: 50), end: TimeOfDay(hour: 15, minute: 30), type: BlockType.recoveryBuffer, explanation: 'Decompress after shift'),
          const ScheduleBlock(id: '5', title: 'Gym', start: TimeOfDay(hour: 15, minute: 30), end: TimeOfDay(hour: 16, minute: 40), type: BlockType.flex),
          const ScheduleBlock(id: '6', title: 'Dinner Runway', start: TimeOfDay(hour: 16, minute: 40), end: TimeOfDay(hour: 17, minute: 0), type: BlockType.runway, explanation: 'Clear counter, pull ingredients'),
          const ScheduleBlock(id: '7', title: 'Prep Zuppa Toscana', start: TimeOfDay(hour: 17, minute: 0), end: TimeOfDay(hour: 18, minute: 30), type: BlockType.flex, explanation: 'Dinner prep window'),
        ];

      case MockDayScenario.overloadedDay:
        return [
          ...baseAnchors,
          standardCommuteHome,
          const ScheduleBlock(id: '4', title: 'Recovery Buffer', start: TimeOfDay(hour: 14, minute: 50), end: TimeOfDay(hour: 15, minute: 15), type: BlockType.recoveryBuffer),
          const ScheduleBlock(id: '5', title: 'UniFi Network Troubleshooting', start: TimeOfDay(hour: 15, minute: 15), end: TimeOfDay(hour: 16, minute: 45), type: BlockType.flex, explanation: 'Cloud Gateway needs attention'),
          const ScheduleBlock(id: '6', title: 'Bambu X2D Maintenance', start: TimeOfDay(hour: 16, minute: 45), end: TimeOfDay(hour: 17, minute: 45), type: BlockType.flex),
          const ScheduleBlock(id: '7', title: 'Family / Dinner', start: TimeOfDay(hour: 18, minute: 0), end: TimeOfDay(hour: 19, minute: 30), type: BlockType.anchor, isLocked: true, decision: ProposalDecision.notApplicable),
        ];

      case MockDayScenario.lowEnergyDay:
        return [
          ...baseAnchors,
          standardCommuteHome,
          const ScheduleBlock(id: '4', title: 'Extended Recovery Buffer', start: TimeOfDay(hour: 14, minute: 50), end: TimeOfDay(hour: 16, minute: 30), type: BlockType.recoveryBuffer, explanation: 'Extra decompression scheduled'),
          const ScheduleBlock(id: '5', title: 'Open Space', start: TimeOfDay(hour: 16, minute: 30), end: TimeOfDay(hour: 18, minute: 0), type: BlockType.openSpace, explanation: 'Intentionally left open', decision: ProposalDecision.notApplicable),
        ];

      case MockDayScenario.lateAppointment:
        return [
          baseAnchors[0],
          baseAnchors[1],
          const ScheduleBlock(id: 'l1', title: 'Emergency Leak Review', start: TimeOfDay(hour: 14, minute: 30), end: TimeOfDay(hour: 15, minute: 45), type: BlockType.anchor, isLocked: true, decision: ProposalDecision.notApplicable, explanation: 'Unexpected late assignment'),
          const ScheduleBlock(id: 'l2', title: 'Commute Home (Delayed)', start: TimeOfDay(hour: 15, minute: 45), end: TimeOfDay(hour: 16, minute: 05), type: BlockType.anchor, isLocked: true, decision: ProposalDecision.notApplicable),
          const ScheduleBlock(id: 'l3', title: 'Recovery Buffer (Shifted)', start: TimeOfDay(hour: 16, minute: 05), end: TimeOfDay(hour: 16, minute: 45), type: BlockType.recoveryBuffer),
        ];
    }
  }

  String _getBriefing(DayPlanStatus status, MockDayScenario scenario) {
    if (status == DayPlanStatus.proposalReady) {
      return switch (scenario) {
        MockDayScenario.normalWorkday => 'I built a steady workday with recovery, gym, and a runway into dinner.',
        MockDayScenario.overloadedDay => 'The afternoon is crowded. I protected a short recovery window before the technical tasks.',
        MockDayScenario.lowEnergyDay => 'I kept the afternoon light and protected a longer recovery window.',
        MockDayScenario.lateAppointment => 'The late assignment delays your commute and shifts recovery later.',
      };
    }

    return switch (status) {
      DayPlanStatus.loading => "I'm organizing the available time.",
      DayPlanStatus.requiresAttention => "A late assignment pushed into your afternoon. I shifted the recovery buffer. Does this work?",
      DayPlanStatus.partiallyAccepted => "I've locked in the blocks you selected. The rest of the time remains open.",
      DayPlanStatus.accepted => "Your day plan is set. I'll show the next useful step.",
      DayPlanStatus.rejected => "Proposed changes rejected. Your original timeline has been restored.",
      DayPlanStatus.ambient => "Standing by.",
      DayPlanStatus.reviewing => "Select the individual blocks you want to keep.",
      DayPlanStatus.unavailable => "No viable plan for this scenario.",
      DayPlanStatus.error => "Something isn't lining up. Let's review the timeline.",
      _ => "",
    };
  }
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------
class LexiScene extends StatelessWidget {
  final DayPlanStatus status;
  final String briefing;

  const LexiScene({super.key, required this.status, required this.briefing});

  Color get _accent {
    switch (status) {
      case DayPlanStatus.proposalReady:
      case DayPlanStatus.accepted:
      case DayPlanStatus.partiallyAccepted:
        return const Color(0xFF2FB083);
      case DayPlanStatus.requiresAttention:
      case DayPlanStatus.error:
      case DayPlanStatus.unavailable:
        return Colors.orange;
      case DayPlanStatus.loading:
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _accent.withOpacity(0.15),
              border: Border.all(color: _accent, width: 2),
            ),
            child: Icon(
              status == DayPlanStatus.loading ? Icons.hourglass_empty :
              status == DayPlanStatus.error ? Icons.warning : Icons.person,
              color: _accent,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lexi', style: TextStyle(color: _accent, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(briefing, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _ActionButton({required this.label, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _ScheduleBlockWidget extends StatelessWidget {
  final ScheduleBlock block;
  final bool isReviewing;
  final bool isNow;
  final bool isSelectable;
  final VoidCallback onToggle;

  const _ScheduleBlockWidget({
    required this.block,
    required this.isReviewing,
    required this.isNow,
    required this.isSelectable,
    required this.onToggle,
  });

  String _formatTime(TimeOfDay t) =>
      '${t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour)}:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';

  BoxDecoration _decorationFor(BlockType type, Color nowColor) => switch (type) {
        BlockType.anchor => BoxDecoration(
            color: const Color(0xFF262626),
            border: Border.all(color: nowColor, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
        BlockType.flex => BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: nowColor, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
        BlockType.runway => BoxDecoration(
            color: Colors.transparent,
            border: Border(
              left: BorderSide(color: nowColor, width: 3),
              top: const BorderSide(color: Colors.white10),
              bottom: const BorderSide(color: Colors.white10),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
        BlockType.recoveryBuffer => BoxDecoration(
            color: Colors.white.withOpacity(0.025),
            border: Border(left: BorderSide(color: nowColor, width: 3)),
            borderRadius: BorderRadius.circular(12),
          ),
        BlockType.openSpace => BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: Colors.white10, width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final nowColor = isNow ? const Color(0xFF2FB083) : Colors.white24;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: _decorationFor(block.type, nowColor),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${_formatTime(block.start)} - ${_formatTime(block.end)}', style: const TextStyle(color: Color(0xFF2FB083), fontWeight: FontWeight.bold, fontSize: 13)),
                    if (block.isLocked) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.lock, size: 14, color: Colors.grey),
                    ]
                  ],
                ),
                const SizedBox(height: 6),
                Text(block.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                if (block.explanation != null) ...[
                  const SizedBox(height: 4),
                  Text(block.explanation!, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ],
            ),
          ),
          if (isReviewing && isSelectable)
            IconButton(
              icon: Icon(block.decision == ProposalDecision.accepted ? Icons.check_circle : Icons.radio_button_unchecked),
              color: block.decision == ProposalDecision.accepted ? const Color(0xFF2FB083) : Colors.grey,
              onPressed: onToggle,
            ),
        ],
      ),
    );
  }
}
