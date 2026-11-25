import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../controllers/sheet_controller.dart';
import '../models/character.dart';
import '../models/sheet_field.dart';
import '../models/vertical_sheet_schema.dart';
import '../theme/sheet_palette.dart';
import 'comment_dialog.dart';
import 'image_field_overlay.dart';
import 'inline_markdown.dart';
import 'sheet_ornaments.dart';

/// Scheda personaggio ripensata in verticale per smartphone, con la stessa
/// grammatica grafica della scheda D&D 5e (cornici a doppio filo, scudo CA,
/// cartigli caratteristica con ovale del modificatore, righe sottolineate).
///
/// Usa un [CustomScrollView] con [SliverList.builder] così Impeller/Skia
/// disegna soltanto i 3–5 blocchi visibili sullo schermo invece di tutti i
/// ~330 campi contemporaneamente, mantenendo i 120 fps su smartphone.
class VerticalSheetView extends StatefulWidget {
  const VerticalSheetView({
    super.key,
    required this.controller,
    this.compactLayout = false,
  });

  final SheetController controller;
  final bool compactLayout;

  @override
  State<VerticalSheetView> createState() => _VerticalSheetViewState();
}

class _VerticalSheetViewState extends State<VerticalSheetView> {
  static const _sectionLabels = [
    'Identità',
    'Combattimento',
    'Caratteristiche',
    'Abilità',
    'Tratti & Zaino',
    'Storia',
    'Incantesimi',
  ];

  // Indice del primo blocco nello SliverList per ciascuna delle 7 sezioni.
  static const _sectionStartItem = [0, 2, 4, 7, 8, 13, 17];

  // Stime iniziali in pixel per saltare rapidamente a sezioni non ancora
  // montate dallo SliverList; vengono sostituite dagli offset reali appena
  // ciascuna sezione viene misurata dal layout.
  static const _initialSectionEstimates = [
    0.0,
    250.0,
    920.0,
    1580.0,
    2280.0,
    3150.0,
    4350.0,
  ];

  static const _totalItemCount = 29;

  final _scrollController = ScrollController();
  final _sliverKey = GlobalKey();
  final _activeSection = ValueNotifier<int>(0);
  late final List<GlobalKey> _sectionKeys = List.generate(
    _sectionLabels.length,
    (_) => GlobalKey(),
  );
  late final List<GlobalKey> _chipKeys = List.generate(
    _sectionLabels.length,
    (_) => GlobalKey(),
  );
  late final List<double> _sectionOffsets = List<double>.of(
    _initialSectionEstimates,
  );
  late final Set<int> _expandedSpellLevels;
  final Set<int> _showAllSpellRows = {};
  bool _jumpingToSection = false;
  double _lastCheckedOffset = double.negativeInfinity;

  @override
  void initState() {
    super.initState();
    _expandedSpellLevels = {
      for (final level in verticalSpellLevels)
        if (_spellLevelHasData(level)) level.level,
    };
    if (_expandedSpellLevels.isEmpty) _expandedSpellLevels.add(0);
    _scrollController.addListener(_handleScroll);
    widget.controller.addListener(_handleControllerChanged);
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didUpdateWidget(VerticalSheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  bool _spellLevelHasData(VerticalSpellLevelDef level) {
    final c = widget.controller;
    if (level.slotsTotalField != null &&
        (c.valueFor(level.slotsTotalField!)?.toString().isNotEmpty ?? false)) {
      return true;
    }
    if (level.slotsExpendedField != null &&
        (c.valueFor(level.slotsExpendedField!)?.toString().isNotEmpty ??
            false)) {
      return true;
    }
    for (final slot in level.spells) {
      if (_spellSlotHasData(slot)) return true;
    }
    return false;
  }

  bool _spellSlotHasData(VerticalSpellSlotDef slot) {
    final c = widget.controller;
    if (c.valueFor(slot.nameField)?.toString().isNotEmpty ?? false) return true;
    if (c.commentFor(slot.nameField)?.isNotEmpty ?? false) return true;
    if (slot.preparedCheckbox != null) {
      if (SheetCheckboxValue.fromStored(c.valueFor(slot.preparedCheckbox!)) !=
          SheetCheckboxValue.unchecked) {
        return true;
      }
      if (c.commentFor(slot.preparedCheckbox!)?.isNotEmpty ?? false) {
        return true;
      }
    }
    return false;
  }

  double? _mountedSectionOffset(int sectionIndex) {
    var object = _sectionKeys[sectionIndex].currentContext?.findRenderObject();
    while (object != null) {
      final parentData = object.parentData;
      if (parentData is SliverMultiBoxAdaptorParentData) {
        return parentData.layoutOffset;
      }
      object = object.parent;
    }
    return null;
  }

  void _syncMountedSectionOffsets() {
    for (var i = 0; i < _sectionKeys.length; i++) {
      final measured = _mountedSectionOffset(i);
      if (measured != null) _sectionOffsets[i] = measured;
    }
  }

  void _handleScroll() {
    if (_jumpingToSection || !mounted || !_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    if ((offset - _lastCheckedOffset).abs() < 20) return;
    _lastCheckedOffset = offset;
    _syncMountedSectionOffsets();
    final threshold = offset + 32;
    var active = 0;
    for (var i = 0; i < _sectionOffsets.length; i++) {
      if (_sectionOffsets[i] <= threshold) {
        active = i;
      } else {
        break;
      }
    }
    if (_activeSection.value != active) {
      _activeSection.value = active;
      final chipContext = _chipKeys[active].currentContext;
      if (chipContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            chipContext,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            alignment: .5,
          ),
        );
      }
    }
  }

  Future<void> _jumpToSection(int index) async {
    _activeSection.value = index;
    if (!_scrollController.hasClients) return;
    _jumpingToSection = true;
    try {
      final mountedTarget = _sectionKeys[index].currentContext;
      if (mountedTarget != null) {
        await Scrollable.ensureVisible(
          mountedTarget,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: 0,
        );
        _syncMountedSectionOffsets();
        if (_scrollController.hasClients) {
          _lastCheckedOffset = _scrollController.offset;
        }
        return;
      }

      // La sezione non è ancora montata dallo SliverList: ci avviciniamo con
      // la stima (o scorrendo a passi) finché non entra nel cacheExtent, poi
      // allineiamo al pixel con ensureVisible.
      for (var step = 0; step < 16 && mounted; step++) {
        if (!_scrollController.hasClients) return;
        final pos = _scrollController.position;
        final desired = _sectionOffsets[index].clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );
        _scrollController.jumpTo(desired);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        final ctx = _sectionKeys[index].currentContext;
        if (ctx != null && ctx.mounted) {
          await Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: 0,
          );
          _syncMountedSectionOffsets();
          if (_scrollController.hasClients) {
            _lastCheckedOffset = _scrollController.offset;
          }
          return;
        }
        // Se la stima era troppo corta/lunga rispetto al contenuto reale,
        // guardiamo gli indici attualmente montati nello SliverList per
        // procedere nella direzione esatta.
        final targetItem = _sectionStartItem[index];
        final sliver = _sliverKey.currentContext?.findRenderObject();
        if (sliver is RenderSliverMultiBoxAdaptor &&
            sliver.firstChild != null &&
            sliver.lastChild != null) {
          final firstIdx = sliver.indexOf(sliver.firstChild!);
          final lastIdx = sliver.indexOf(sliver.lastChild!);
          if (lastIdx < targetItem) {
            _sectionOffsets[index] =
                (_scrollController.offset + pos.viewportDimension * .9).clamp(
                  pos.minScrollExtent,
                  pos.maxScrollExtent,
                );
          } else if (firstIdx > targetItem) {
            _sectionOffsets[index] =
                (_scrollController.offset - pos.viewportDimension * .9).clamp(
                  pos.minScrollExtent,
                  pos.maxScrollExtent,
                );
          } else {
            break;
          }
        } else {
          break;
        }
      }
    } finally {
      _jumpingToSection = false;
    }
  }

  Widget _buildItem(BuildContext context, int index) {
    final c = widget.controller;
    final Widget content;
    switch (index) {
      case 0:
        content = _IdentityBannerBlock(key: _sectionKeys[0], controller: c);
      case 1:
        content = _IdentityMetadataBlock(controller: c);
      case 2:
        content = _CombatVitalsBlock(key: _sectionKeys[1], controller: c);
      case 3:
        content = _CombatAttacksBlock(controller: c);
      case 4:
        content = _AbilitiesTrayBlock(key: _sectionKeys[2], controller: c);
      case 5:
        content = _StatBadgesBlock(controller: c);
      case 6:
        content = _SavingThrowsBlock(controller: c);
      case 7:
        content = _SkillsSection(key: _sectionKeys[3], controller: c);
      case 8:
        content = _MultilineSheetBlock(
          key: _sectionKeys[4],
          fieldName: 'Features and Traits',
          caption: 'Privilegi e tratti',
          minLines: 4,
          controller: c,
        );
      case 9:
        content = _MultilineSheetBlock(
          fieldName: 'Feat+Traits',
          caption: 'Privilegi e tratti aggiuntivi',
          minLines: 3,
          controller: c,
        );
      case 10:
        content = _MultilineSheetBlock(
          fieldName: 'ProficienciesLang',
          caption: 'Altre competenze e linguaggi',
          minLines: 3,
          controller: c,
        );
      case 11:
        content = _EquipmentBlock(controller: c);
      case 12:
        content = _MultilineSheetBlock(
          fieldName: 'Treasure',
          caption: 'Tesoro',
          minLines: 3,
          controller: c,
        );
      case 13:
        content = _AppearanceBlock(key: _sectionKeys[5], controller: c);
      case 14:
        content = _PersonalityBlock(controller: c);
      case 15:
        content = _AlliesBlock(controller: c);
      case 16:
        content = _MultilineSheetBlock(
          fieldName: 'Backstory',
          caption: 'Storia del personaggio',
          minLines: 5,
          controller: c,
        );
      case 17:
        content = _SpellcastingHeaderBlock(key: _sectionKeys[6], controller: c);
      case >= 18 && <= 27:
        final level = verticalSpellLevels[index - 18];
        content = _SpellLevelCard(
          level: level,
          controller: c,
          expanded: _expandedSpellLevels.contains(level.level),
          showAllRows: _showAllSpellRows.contains(level.level),
          slotHasData: _spellSlotHasData,
          onToggleExpanded: () => setState(() {
            if (!_expandedSpellLevels.add(level.level)) {
              _expandedSpellLevels.remove(level.level);
            }
          }),
          onToggleShowAll: () => setState(() {
            if (!_showAllSpellRows.add(level.level)) {
              _showAllSpellRows.remove(level.level);
            }
          }),
          onRowEdited: () => setState(() {}),
        );
      default:
        content = const _FooterHint();
    }

    final bottomGap = switch (index) {
      1 || 3 || 6 || 7 || 12 || 16 => 14.0,
      28 => 0.0,
      _ => 10.0,
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomGap),
          child: content,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return ColoredBox(
      color: palette.paper,
      child: Column(
        children: [
          // Spazio riservato ai controlli fluttuanti in alto (Indietro, Vista,
          // Aspetto, Blocca) così lo scorrimento non passa sotto ai pulsanti.
          SizedBox(height: widget.compactLayout ? 48 : 64),
          if (!widget.compactLayout)
            RepaintBoundary(
              child: _SectionNavBar(
                labels: _sectionLabels,
                chipKeys: _chipKeys,
                activeSection: _activeSection,
                onSelect: _jumpToSection,
              ),
            ),
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              cacheExtent: 450,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    10,
                    10,
                    10,
                    widget.compactLayout ? 16 : 96,
                  ),
                  sliver: SliverList.builder(
                    key: _sliverKey,
                    itemCount: _totalItemCount,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    itemBuilder: _buildItem,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _activeSection.dispose();
    super.dispose();
  }
}

class _FooterHint extends StatelessWidget {
  const _FooterHint();

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Center(
      child: Text(
        'Tieni premuto su un campo per aggiungere o leggere una nota.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'RobotoSlab',
          fontSize: 11,
          color: palette.ink.withValues(alpha: .58),
        ),
      ),
    );
  }
}

class _SectionNavBar extends StatelessWidget {
  const _SectionNavBar({
    required this.labels,
    required this.chipKeys,
    required this.activeSection,
    required this.onSelect,
  });

  final List<String> labels;
  final List<GlobalKey> chipKeys;
  final ValueListenable<int> activeSection;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paper,
        border: Border(
          top: BorderSide(color: palette.ink.withValues(alpha: .16)),
          bottom: BorderSide(color: palette.ink.withValues(alpha: .32)),
        ),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: activeSection,
        builder: (context, selectedIndex, _) => SizedBox(
          height: 40,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  GestureDetector(
                    key: chipKeys[i],
                    onTap: () => onSelect(i),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: i == selectedIndex ? palette.ink : palette.paper,
                        shape: BeveledRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                          side: BorderSide(
                            color: palette.ink.withValues(
                              alpha: i == selectedIndex ? 1 : .42,
                            ),
                            width: i == selectedIndex ? 1.3 : 1,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: Text(
                          labels[i],
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontFamily: 'RobotoSlab',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: i == selectedIndex
                                    ? palette.paper
                                    : palette.ink,
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IdentityBannerBlock extends StatelessWidget {
  const _IdentityBannerBlock({super.key, required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return SheetBannerBox(
      caption: 'Nome personaggio',
      child: _SheetTextField(
        key: const ValueKey('CharacterName'),
        fieldName: 'CharacterName',
        dialogLabel: 'Nome personaggio',
        controller: controller,
        textAlign: TextAlign.center,
        style: _FieldDecorationStyle.plain,
        textStyle: TextStyle(
          fontFamily: 'RobotoSlab',
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: palette.text,
        ),
      ),
    );
  }
}

class _IdentityMetadataBlock extends StatelessWidget {
  const _IdentityMetadataBlock({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) => SheetFrameBox(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
    child: Column(
      children: [
        for (var i = 0; i < verticalIdentityFields.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _UnderlinedLabeledField(
                  fieldName: verticalIdentityFields[i].field,
                  caption: verticalIdentityFields[i].label,
                  controller: controller,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _UnderlinedLabeledField(
                  fieldName: verticalIdentityFields[i + 1].field,
                  caption: verticalIdentityFields[i + 1].label,
                  controller: controller,
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _CombatVitalsBlock extends StatelessWidget {
  const _CombatVitalsBlock({super.key, required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final bigNumberStyle = TextStyle(
      fontFamily: 'RobotoSlab',
      fontSize: 23,
      fontWeight: FontWeight.w800,
      color: palette.text,
    );
    return SheetTray(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 88),
                  child: ArmorClassShield(
                    child: _SheetTextField(
                      key: const ValueKey('AC'),
                      fieldName: 'AC',
                      dialogLabel: 'Classe armatura',
                      controller: controller,
                      textAlign: TextAlign.center,
                      style: _FieldDecorationStyle.plain,
                      compact: true,
                      textStyle: bigNumberStyle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 88),
                  child: SheetFrameBox(
                    caption: 'Iniziativa',
                    padding: const EdgeInsets.fromLTRB(6, 16, 6, 8),
                    child: _SheetTextField(
                      key: const ValueKey('Initiative'),
                      fieldName: 'Initiative',
                      dialogLabel: 'Iniziativa',
                      controller: controller,
                      textAlign: TextAlign.center,
                      style: _FieldDecorationStyle.plain,
                      compact: true,
                      textStyle: bigNumberStyle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 88),
                  child: SheetFrameBox(
                    caption: 'Velocità',
                    padding: const EdgeInsets.fromLTRB(6, 16, 6, 8),
                    child: _SheetTextField(
                      key: const ValueKey('Speed'),
                      fieldName: 'Speed',
                      dialogLabel: 'Velocità',
                      controller: controller,
                      textAlign: TextAlign.center,
                      style: _FieldDecorationStyle.plain,
                      compact: true,
                      textStyle: bigNumberStyle,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SheetFrameBox(
            caption: 'Punti ferita attuali',
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      'Punti ferita massimi',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontFamily: 'RobotoSlab',
                        fontSize: 10,
                        color: palette.ink.withValues(alpha: .62),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SheetTextField(
                        key: const ValueKey('HPMax'),
                        fieldName: 'HPMax',
                        dialogLabel: 'Punti ferita massimi',
                        controller: controller,
                        textAlign: TextAlign.center,
                        style: _FieldDecorationStyle.underline,
                        compact: true,
                        textStyle: TextStyle(
                          fontFamily: 'RobotoSlab',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: palette.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _SheetTextField(
                  key: const ValueKey('HPCurrent'),
                  fieldName: 'HPCurrent',
                  dialogLabel: 'Punti ferita attuali',
                  controller: controller,
                  textAlign: TextAlign.center,
                  style: _FieldDecorationStyle.plain,
                  textStyle: TextStyle(
                    fontFamily: 'RobotoSlab',
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SheetFrameBox(
            caption: 'Punti ferita temporanei',
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: _SheetTextField(
              key: const ValueKey('HPTemp'),
              fieldName: 'HPTemp',
              dialogLabel: 'Punti ferita temporanei',
              controller: controller,
              textAlign: TextAlign.center,
              style: _FieldDecorationStyle.plain,
              textStyle: TextStyle(
                fontFamily: 'RobotoSlab',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 9,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 98),
                  child: SheetFrameBox(
                    caption: 'Dadi vita',
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              'Totale',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontFamily: 'RobotoSlab',
                                    fontSize: 9.5,
                                    color: palette.ink.withValues(alpha: .62),
                                  ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _SheetTextField(
                                key: const ValueKey('HDTotal'),
                                fieldName: 'HDTotal',
                                dialogLabel: 'Totale dadi vita',
                                controller: controller,
                                textAlign: TextAlign.center,
                                style: _FieldDecorationStyle.underline,
                                compact: true,
                                textStyle: TextStyle(
                                  fontFamily: 'RobotoSlab',
                                  fontSize: 13,
                                  color: palette.text,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _SheetTextField(
                          key: const ValueKey('HD'),
                          fieldName: 'HD',
                          dialogLabel: 'Dadi vita',
                          controller: controller,
                          textAlign: TextAlign.center,
                          style: _FieldDecorationStyle.plain,
                          compact: true,
                          textStyle: TextStyle(
                            fontFamily: 'RobotoSlab',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: palette.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 11,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 98),
                  child: SheetFrameBox(
                    caption: 'Tiri salvezza contro morte',
                    padding: const EdgeInsets.fromLTRB(8, 10, 6, 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _DeathSaveRow(
                          label: 'SUCCESSI',
                          fields: verticalDeathSaveSuccesses,
                          controller: controller,
                        ),
                        const SizedBox(height: 2),
                        _DeathSaveRow(
                          label: 'FALLIMENTI',
                          fields: verticalDeathSaveFailures,
                          controller: controller,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CombatAttacksBlock extends StatelessWidget {
  const _CombatAttacksBlock({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return SheetFrameBox(
      caption: 'Attacchi e incantesimi',
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(flex: 5, child: _MicroHeader('NOME')),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: _MicroHeader('BONUS', align: TextAlign.center),
                ),
                const SizedBox(width: 6),
                Expanded(flex: 4, child: _MicroHeader('DANNI / TIPO')),
              ],
            ),
          ),
          for (var i = 0; i < verticalAttacks.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: _SheetTextField(
                    key: ValueKey(verticalAttacks[i].nameField),
                    fieldName: verticalAttacks[i].nameField,
                    dialogLabel: 'Arma ${i + 1}',
                    controller: controller,
                    style: _FieldDecorationStyle.shaded,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: _SheetTextField(
                    key: ValueKey(verticalAttacks[i].bonusField),
                    fieldName: verticalAttacks[i].bonusField,
                    dialogLabel: 'Bonus attacco ${i + 1}',
                    controller: controller,
                    textAlign: TextAlign.center,
                    style: _FieldDecorationStyle.shaded,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 4,
                  child: _SheetTextField(
                    key: ValueKey(verticalAttacks[i].damageField),
                    fieldName: verticalAttacks[i].damageField,
                    dialogLabel: 'Danni ${i + 1}',
                    controller: controller,
                    style: _FieldDecorationStyle.shaded,
                    compact: true,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Divider(height: 1, color: palette.ink.withValues(alpha: .2)),
          const SizedBox(height: 4),
          _SheetTextField(
            key: const ValueKey('AttacksSpellcasting'),
            fieldName: 'AttacksSpellcasting',
            dialogLabel: 'Note su attacchi e incantesimi',
            hintText: 'Note su attacchi e incantesimi…',
            controller: controller,
            multiline: true,
            minLines: 3,
            style: _FieldDecorationStyle.plain,
          ),
        ],
      ),
    );
  }
}

class _DeathSaveRow extends StatelessWidget {
  const _DeathSaveRow({
    required this.label,
    required this.fields,
    required this.controller,
  });

  final String label;
  final List<String> fields;
  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontFamily: 'RobotoSlab',
              fontSize: 8.2,
              fontWeight: FontWeight.w700,
              color: palette.ink.withValues(alpha: .82),
            ),
          ),
        ),
        const SizedBox(width: 4),
        DeathSaveTrack(
          children: [
            for (final field in fields)
              _SheetCheckbox(
                key: ValueKey(field),
                fieldName: field,
                controller: controller,
                size: 28,
              ),
          ],
        ),
      ],
    );
  }
}

class _AbilitiesTrayBlock extends StatelessWidget {
  const _AbilitiesTrayBlock({super.key, required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) => SheetTray(
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 290 ? 2 : 3;
        final rows = (verticalAbilities.length / columns).ceil();
        return Column(
          children: [
            for (var r = 0; r < rows; r++) ...[
              if (r > 0) const SizedBox(height: 10),
              Row(
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) const SizedBox(width: 8),
                    Expanded(
                      child: r * columns + c < verticalAbilities.length
                          ? _AbilityItem(
                              ability: verticalAbilities[r * columns + c],
                              controller: controller,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    ),
  );
}

class _StatBadgesBlock extends StatelessWidget {
  const _StatBadgesBlock({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final badgeStyle = TextStyle(
      fontFamily: 'RobotoSlab',
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: palette.text,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatBadgeBar(
          label: 'Ispirazione',
          shape: StatEmblemShape.square,
          value: _SheetTextField(
            key: const ValueKey('Inspiration'),
            fieldName: 'Inspiration',
            dialogLabel: 'Ispirazione',
            controller: controller,
            textAlign: TextAlign.center,
            style: _FieldDecorationStyle.plain,
            compact: true,
            textStyle: badgeStyle,
          ),
        ),
        const SizedBox(height: 8),
        StatBadgeBar(
          label: 'Bonus competenza',
          shape: StatEmblemShape.circle,
          value: _SheetTextField(
            key: const ValueKey('ProfBonus'),
            fieldName: 'ProfBonus',
            dialogLabel: 'Bonus competenza',
            controller: controller,
            textAlign: TextAlign.center,
            style: _FieldDecorationStyle.plain,
            compact: true,
            textStyle: badgeStyle,
          ),
        ),
        const SizedBox(height: 8),
        StatBadgeBar(
          label: 'Percezione passiva (Saggezza)',
          shape: StatEmblemShape.circle,
          value: _SheetTextField(
            key: const ValueKey('Passive'),
            fieldName: 'Passive',
            dialogLabel: 'Percezione passiva',
            controller: controller,
            textAlign: TextAlign.center,
            style: _FieldDecorationStyle.plain,
            compact: true,
            textStyle: badgeStyle,
          ),
        ),
      ],
    );
  }
}

class _SavingThrowsBlock extends StatelessWidget {
  const _SavingThrowsBlock({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) => SheetFrameBox(
    caption: 'Tiri salvezza',
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    child: Column(
      children: [
        for (var i = 0; i < verticalAbilities.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: _SavingThrowCell(
                  ability: verticalAbilities[i],
                  controller: controller,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SavingThrowCell(
                  ability: verticalAbilities[i + 1],
                  controller: controller,
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _AbilityItem extends StatelessWidget {
  const _AbilityItem({required this.ability, required this.controller});

  final VerticalAbilityDef ability;
  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return AbilityCartouche(
      label: ability.label,
      score: _SheetTextField(
        key: ValueKey(ability.scoreField),
        fieldName: ability.scoreField,
        dialogLabel: ability.label,
        controller: controller,
        textAlign: TextAlign.center,
        style: _FieldDecorationStyle.plain,
        compact: true,
        textStyle: TextStyle(
          fontFamily: 'RobotoSlab',
          fontSize: 23,
          fontWeight: FontWeight.w800,
          color: palette.text,
        ),
      ),
      modifier: _SheetTextField(
        key: ValueKey(ability.modField),
        fieldName: ability.modField,
        dialogLabel: 'Modificatore ${ability.label}',
        controller: controller,
        textAlign: TextAlign.center,
        style: _FieldDecorationStyle.plain,
        compact: true,
        textStyle: TextStyle(
          fontFamily: 'RobotoSlab',
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          color: palette.text,
        ),
      ),
    );
  }
}

class _SavingThrowCell extends StatelessWidget {
  const _SavingThrowCell({required this.ability, required this.controller});

  final VerticalAbilityDef ability;
  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Row(
      children: [
        _SheetCheckbox(
          key: ValueKey(ability.saveCheckbox),
          fieldName: ability.saveCheckbox,
          controller: controller,
        ),
        SizedBox(
          width: 36,
          child: _SheetTextField(
            key: ValueKey(ability.saveField),
            fieldName: ability.saveField,
            dialogLabel: 'Tiro salvezza ${ability.label}',
            controller: controller,
            textAlign: TextAlign.center,
            style: _FieldDecorationStyle.underline,
            compact: true,
            textStyle: TextStyle(
              fontFamily: 'RobotoSlab',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ability.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'RobotoSlab',
              fontSize: 12.5,
              color: palette.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _SkillsSection extends StatelessWidget {
  const _SkillsSection({super.key, required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return SheetFrameBox(
      caption: 'Abilità',
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      topTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: palette.text),
          const SizedBox(width: 4),
          Text(
            'Comp.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontFamily: 'RobotoSlab',
              fontSize: 10,
              color: palette.ink.withValues(alpha: .7),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.circle, size: 8, color: palette.expertise),
          const SizedBox(width: 4),
          Text(
            'Maestria',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontFamily: 'RobotoSlab',
              fontSize: 10,
              color: palette.ink.withValues(alpha: .7),
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < verticalSkills.length; i++) ...[
            if (i > 0)
              Divider(height: 2, color: palette.ink.withValues(alpha: .08)),
            Row(
              children: [
                _SheetCheckbox(
                  key: ValueKey(verticalSkills[i].checkboxField),
                  fieldName: verticalSkills[i].checkboxField,
                  controller: controller,
                  allowExpertise: true,
                ),
                SizedBox(
                  width: 42,
                  child: _SheetTextField(
                    key: ValueKey(verticalSkills[i].valueField),
                    fieldName: verticalSkills[i].valueField,
                    dialogLabel: verticalSkills[i].label,
                    controller: controller,
                    textAlign: TextAlign.center,
                    style: _FieldDecorationStyle.underline,
                    compact: true,
                    textStyle: TextStyle(
                      fontFamily: 'RobotoSlab',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'RobotoSlab',
                        fontSize: 13.5,
                        color: palette.text,
                      ),
                      children: [
                        TextSpan(text: verticalSkills[i].label),
                        TextSpan(
                          text: ' (${verticalSkills[i].abilityShort})',
                          style: TextStyle(
                            fontSize: 11,
                            color: palette.ink.withValues(alpha: .58),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MultilineSheetBlock extends StatelessWidget {
  const _MultilineSheetBlock({
    super.key,
    required this.fieldName,
    required this.caption,
    required this.minLines,
    required this.controller,
  });

  final String fieldName;
  final String caption;
  final int minLines;
  final SheetController controller;

  @override
  Widget build(BuildContext context) => SheetFrameBox(
    caption: caption,
    child: _SheetTextField(
      key: ValueKey(fieldName),
      fieldName: fieldName,
      dialogLabel: caption,
      controller: controller,
      multiline: true,
      minLines: minLines,
      style: _FieldDecorationStyle.plain,
    ),
  );
}

class _EquipmentBlock extends StatelessWidget {
  const _EquipmentBlock({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return SheetFrameBox(
      caption: 'Equipaggiamento',
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < verticalCoins.length; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(
                  child: CoinPlaque(
                    label: verticalCoins[i].label,
                    child: _SheetTextField(
                      key: ValueKey(verticalCoins[i].field),
                      fieldName: verticalCoins[i].field,
                      dialogLabel: verticalCoins[i].label,
                      controller: controller,
                      textAlign: TextAlign.center,
                      style: _FieldDecorationStyle.plain,
                      compact: true,
                      textStyle: TextStyle(
                        fontFamily: 'RobotoSlab',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: palette.ink.withValues(alpha: .2)),
          const SizedBox(height: 4),
          _SheetTextField(
            key: const ValueKey('Equipment'),
            fieldName: 'Equipment',
            dialogLabel: 'Equipaggiamento',
            controller: controller,
            multiline: true,
            minLines: 4,
            style: _FieldDecorationStyle.plain,
          ),
        ],
      ),
    );
  }
}

class _AppearanceBlock extends StatelessWidget {
  const _AppearanceBlock({super.key, required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) => SheetFrameBox(
    caption: 'Aspetto del personaggio',
    child: Column(
      children: [
        _FramedImageField(
          fieldName: 'CharacterAppearanceImage',
          label: 'Ritratto del personaggio',
          boxSize: const Size(172, 222),
          maxHeight: 220,
          controller: controller,
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < verticalAppearanceFields.length; i += 3) ...[
          if (i > 0) const SizedBox(height: 6),
          Row(
            children: [
              for (var j = 0; j < 3; j++) ...[
                if (j > 0) const SizedBox(width: 8),
                Expanded(
                  child: _UnderlinedLabeledField(
                    fieldName: verticalAppearanceFields[i + j].field,
                    caption: verticalAppearanceFields[i + j].label,
                    controller: controller,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    ),
  );
}

class _PersonalityBlock extends StatelessWidget {
  const _PersonalityBlock({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) => SheetTray(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < verticalPersonalityFields.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          SheetFrameBox(
            caption: verticalPersonalityFields[i].label,
            child: _SheetTextField(
              key: ValueKey(verticalPersonalityFields[i].field),
              fieldName: verticalPersonalityFields[i].field,
              dialogLabel: verticalPersonalityFields[i].label,
              controller: controller,
              multiline: true,
              minLines: 2,
              style: _FieldDecorationStyle.plain,
            ),
          ),
        ],
      ],
    ),
  );
}

class _AlliesBlock extends StatelessWidget {
  const _AlliesBlock({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return SheetFrameBox(
      caption: 'Alleati e organizzazioni',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTray(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MicroHeader('NOME ORGANIZZAZIONE'),
                const SizedBox(height: 4),
                _SheetTextField(
                  key: const ValueKey('FactionName'),
                  fieldName: 'FactionName',
                  dialogLabel: 'Nome organizzazione',
                  controller: controller,
                  textAlign: TextAlign.center,
                  style: _FieldDecorationStyle.shaded,
                  compact: true,
                ),
                const SizedBox(height: 8),
                _FramedImageField(
                  fieldName: 'FactionSymbolImage',
                  label: 'Simbolo',
                  boxSize: const Size(143, 114),
                  maxHeight: 136,
                  controller: controller,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: palette.ink.withValues(alpha: .2)),
          const SizedBox(height: 4),
          _SheetTextField(
            key: const ValueKey('Allies'),
            fieldName: 'Allies',
            dialogLabel: 'Alleati e organizzazioni',
            controller: controller,
            multiline: true,
            minLines: 3,
            style: _FieldDecorationStyle.plain,
          ),
        ],
      ),
    );
  }
}

class _FramedImageField extends StatelessWidget {
  const _FramedImageField({
    required this.fieldName,
    required this.label,
    required this.boxSize,
    required this.maxHeight,
    required this.controller,
  });

  final String fieldName;
  final String label;
  final Size boxSize;
  final double maxHeight;
  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: AspectRatio(
          aspectRatio: boxSize.width / boxSize.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.paper,
              border: Border.all(color: palette.ink.withValues(alpha: .45)),
            ),
            child: ImageFieldOverlay(
              key: ValueKey(fieldName),
              fieldName: fieldName,
              boxSize: boxSize,
              sheetController: controller,
              placeholder: Center(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 26,
                        color: palette.ink.withValues(alpha: .4),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontFamily: 'RobotoSlab',
                          fontSize: 9,
                          letterSpacing: .6,
                          color: palette.ink.withValues(alpha: .55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpellcastingHeaderBlock extends StatelessWidget {
  const _SpellcastingHeaderBlock({super.key, required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final statStyle = TextStyle(
      fontFamily: 'RobotoSlab',
      fontSize: 18,
      fontWeight: FontWeight.w800,
      color: palette.text,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetBannerBox(
          caption: 'Classe da incantatore',
          child: _SheetTextField(
            key: const ValueKey('Spellcasting Class 2'),
            fieldName: 'Spellcasting Class 2',
            dialogLabel: 'Classe da incantatore',
            controller: controller,
            textAlign: TextAlign.center,
            style: _FieldDecorationStyle.plain,
            textStyle: TextStyle(
              fontFamily: 'RobotoSlab',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SheetTray(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SheetFrameBox(
                  caption: 'Caratteristica',
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
                  child: _SheetTextField(
                    key: const ValueKey('SpellcastingAbility 2'),
                    fieldName: 'SpellcastingAbility 2',
                    dialogLabel: 'Caratteristica da incantatore',
                    controller: controller,
                    textAlign: TextAlign.center,
                    style: _FieldDecorationStyle.plain,
                    compact: true,
                    textStyle: statStyle,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SheetFrameBox(
                  caption: 'CD Salvezza',
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
                  child: _SheetTextField(
                    key: const ValueKey('SpellSaveDC  2'),
                    fieldName: 'SpellSaveDC  2',
                    dialogLabel: 'CD Tiro Salvezza Incantesimi',
                    controller: controller,
                    textAlign: TextAlign.center,
                    style: _FieldDecorationStyle.plain,
                    compact: true,
                    textStyle: statStyle,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SheetFrameBox(
                  caption: 'Bonus Attacco',
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
                  child: _SheetTextField(
                    key: const ValueKey('SpellAtkBonus 2'),
                    fieldName: 'SpellAtkBonus 2',
                    dialogLabel: 'Bonus Attacco Incantesimi',
                    controller: controller,
                    textAlign: TextAlign.center,
                    style: _FieldDecorationStyle.plain,
                    compact: true,
                    textStyle: statStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpellLevelCard extends StatelessWidget {
  const _SpellLevelCard({
    required this.level,
    required this.controller,
    required this.expanded,
    required this.showAllRows,
    required this.slotHasData,
    required this.onToggleExpanded,
    required this.onToggleShowAll,
    required this.onRowEdited,
  });

  final VerticalSpellLevelDef level;
  final SheetController controller;
  final bool expanded;
  final bool showAllRows;
  final bool Function(VerticalSpellSlotDef slot) slotHasData;
  final VoidCallback onToggleExpanded;
  final VoidCallback onToggleShowAll;
  final VoidCallback onRowEdited;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final filledCount = level.spells.where(slotHasData).length;
    final totalSlots = level.slotsTotalField == null
        ? ''
        : controller.valueFor(level.slotsTotalField!)?.toString() ?? '';
    final usedSlots = level.slotsExpendedField == null
        ? ''
        : controller.valueFor(level.slotsExpendedField!)?.toString() ?? '';

    final visibleSlots = <VerticalSpellSlotDef>[];
    if (showAllRows) {
      visibleSlots.addAll(level.spells);
    } else {
      var includedEmpty = false;
      for (final slot in level.spells) {
        if (slotHasData(slot)) {
          visibleSlots.add(slot);
        } else if (!includedEmpty) {
          visibleSlots.add(slot);
          includedEmpty = true;
        }
      }
    }
    final hiddenEmptyCount = level.spells.length - visibleSlots.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggleExpanded,
          child: SpellLevelHeaderFrame(
            level: level.level,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    level.title.toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontFamily: 'RobotoSlab',
                      fontWeight: FontWeight.w800,
                      letterSpacing: .7,
                      color: palette.ink,
                    ),
                  ),
                ),
                if (!expanded &&
                    (totalSlots.isNotEmpty || usedSlots.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      'Slot ${usedSlots.isEmpty ? '0' : usedSlots}/${totalSlots.isEmpty ? '–' : totalSlots}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontFamily: 'RobotoSlab',
                        fontSize: 10.5,
                        color: palette.ink.withValues(alpha: .72),
                      ),
                    ),
                  ),
                if (filledCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '($filledCount)',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontFamily: 'RobotoSlab',
                        fontWeight: FontWeight.w700,
                        color: palette.ink.withValues(alpha: .72),
                      ),
                    ),
                  ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: palette.ink,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: palette.paper,
              border: Border(
                left: BorderSide(color: palette.ink.withValues(alpha: .55)),
                right: BorderSide(color: palette.ink.withValues(alpha: .55)),
                bottom: BorderSide(color: palette.ink.withValues(alpha: .55)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (level.slotsTotalField != null &&
                    level.slotsExpendedField != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _UnderlinedLabeledField(
                          fieldName: level.slotsTotalField!,
                          caption: 'Slot totali',
                          controller: controller,
                          textAlign: TextAlign.center,
                          onChanged: onRowEdited,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _UnderlinedLabeledField(
                          fieldName: level.slotsExpendedField!,
                          caption: 'Slot usati',
                          controller: controller,
                          textAlign: TextAlign.center,
                          onChanged: onRowEdited,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                for (var i = 0; i < visibleSlots.length; i++) ...[
                  if (i > 0) const SizedBox(height: 2),
                  Row(
                    children: [
                      if (visibleSlots[i].preparedCheckbox != null)
                        _SheetCheckbox(
                          key: ValueKey(visibleSlots[i].preparedCheckbox!),
                          fieldName: visibleSlots[i].preparedCheckbox!,
                          controller: controller,
                          onChanged: onRowEdited,
                        ),
                      Expanded(
                        child: _SheetTextField(
                          key: ValueKey(visibleSlots[i].nameField),
                          fieldName: visibleSlots[i].nameField,
                          dialogLabel: level.level == 0
                              ? 'Trucchetto'
                              : 'Incantesimo livello ${level.level}',
                          hintText: level.level == 0
                              ? 'Nuovo trucchetto…'
                              : 'Nuovo incantesimo…',
                          controller: controller,
                          style: _FieldDecorationStyle.underline,
                          compact: true,
                          onChanged: onRowEdited,
                        ),
                      ),
                    ],
                  ),
                ],
                if (hiddenEmptyCount > 0 || showAllRows)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: palette.ink,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onToggleShowAll,
                      child: Text(
                        showAllRows
                            ? 'Nascondi spazi vuoti'
                            : 'Mostra tutti gli spazi (${level.spells.length})',
                        style: const TextStyle(
                          fontFamily: 'RobotoSlab',
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Campo singolo sottolineato con etichetta maiuscola sotto la riga,
/// identico alla testata e alle caratteristiche fisiche della scheda PDF.
class _UnderlinedLabeledField extends StatelessWidget {
  const _UnderlinedLabeledField({
    required this.fieldName,
    required this.caption,
    required this.controller,
    this.textAlign = TextAlign.left,
    this.onChanged,
  });

  final String fieldName;
  final String caption;
  final SheetController controller;
  final TextAlign textAlign;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Column(
      crossAxisAlignment: textAlign == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SheetTextField(
          key: ValueKey(fieldName),
          fieldName: fieldName,
          dialogLabel: caption,
          controller: controller,
          textAlign: textAlign,
          style: _FieldDecorationStyle.underline,
          compact: true,
          onChanged: onChanged,
        ),
        const SizedBox(height: 2),
        Text(
          caption.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontFamily: 'RobotoSlab',
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
            color: palette.ink.withValues(alpha: .72),
          ),
        ),
      ],
    );
  }
}

class _MicroHeader extends StatelessWidget {
  const _MicroHeader(this.text, {this.align = TextAlign.left});

  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Text(
      text,
      textAlign: align,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontFamily: 'RobotoSlab',
        fontSize: 8.5,
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
        color: palette.ink.withValues(alpha: .62),
      ),
    );
  }
}

enum _FieldDecorationStyle { plain, underline, shaded }

class _SheetTextField extends StatefulWidget {
  const _SheetTextField({
    super.key,
    required this.fieldName,
    required this.controller,
    this.dialogLabel,
    this.hintText,
    this.multiline = false,
    this.minLines = 1,
    this.textAlign = TextAlign.left,
    this.textStyle,
    this.compact = false,
    this.style = _FieldDecorationStyle.underline,
    this.onChanged,
  });

  final String fieldName;
  final SheetController controller;
  final String? dialogLabel;
  final String? hintText;
  final bool multiline;
  final int minLines;
  final TextAlign textAlign;
  final TextStyle? textStyle;
  final bool compact;
  final _FieldDecorationStyle style;
  final VoidCallback? onChanged;

  @override
  State<_SheetTextField> createState() => _SheetTextFieldState();
}

class _SheetTextFieldState extends State<_SheetTextField> {
  TextEditingController? _textController;
  FocusNode? _focusNode;
  late String _value;
  bool _editing = false;

  bool get _followsName => characterNameFields.contains(widget.fieldName);

  @override
  void initState() {
    super.initState();
    _value = widget.controller.valueFor(widget.fieldName)?.toString() ?? '';
    if (_followsName) {
      widget.controller.nameState.addListener(_handleNameChanged);
    }
  }

  void _handleNameChanged() {
    if (!mounted) return;
    final value = widget.controller.nameState.value;
    if (_value == value) return;
    setState(() => _value = value);
    _synchronizeEditor(value);
  }

  void _synchronizeEditor(String value) {
    final controller = _textController;
    if (controller != null && controller.text != value) {
      controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  void didUpdateWidget(_SheetTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value =
        widget.controller.valueFor(widget.fieldName)?.toString() ?? '';
    if (_value != value) {
      _value = value;
      _synchronizeEditor(value);
    }
  }

  void _handleFocus() {
    if (!(_focusNode?.hasFocus ?? false) && _editing && mounted) {
      setState(() => _editing = false);
    }
  }

  void _startEditing() {
    if (_editing || widget.controller.locked) return;
    _textController ??= TextEditingController(text: _value);
    _synchronizeEditor(_value);
    _focusNode ??= FocusNode()..addListener(_handleFocus);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _focusNode?.requestFocus();
    });
  }

  void _showComment() => showFieldCommentDialog(
    context: context,
    fieldName: widget.dialogLabel ?? widget.fieldName,
    initialValue: widget.controller.commentFor(widget.fieldName),
    readOnly: widget.controller.locked,
    onSave: (value) => widget.controller.setComment(widget.fieldName, value),
  );

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveStyle =
        widget.textStyle ??
        TextStyle(
          fontFamily: 'RobotoSlab',
          fontSize: widget.multiline ? 13.5 : 14.5,
          height: widget.multiline ? 1.35 : 1.15,
          color: palette.text,
        );
    final contentPadding = switch (widget.style) {
      _FieldDecorationStyle.shaded => EdgeInsets.symmetric(
        horizontal: 6,
        vertical: widget.compact ? 5 : 7,
      ),
      _FieldDecorationStyle.underline => EdgeInsets.symmetric(
        horizontal: 2,
        vertical: widget.compact ? 4 : 6,
      ),
      _FieldDecorationStyle.plain => EdgeInsets.symmetric(
        horizontal: 2,
        vertical: widget.compact ? 2 : 4,
      ),
    };
    final decoration = switch (widget.style) {
      _FieldDecorationStyle.shaded => BoxDecoration(
        color: palette.ink.withValues(alpha: isDark ? .14 : .10),
        borderRadius: BorderRadius.circular(3),
        border: _editing ? Border.all(color: palette.accent, width: 1.3) : null,
      ),
      _FieldDecorationStyle.underline => BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: _editing
                ? palette.accent
                : palette.ink.withValues(alpha: .48),
            width: _editing ? 1.6 : 1,
          ),
        ),
      ),
      _FieldDecorationStyle.plain => BoxDecoration(
        border: _editing
            ? Border(bottom: BorderSide(color: palette.accent, width: 1.4))
            : null,
      ),
    };
    return ValueListenableBuilder<bool>(
      valueListenable: widget.controller.lockedState,
      builder: (context, locked, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _editing || locked ? null : _startEditing,
        onLongPress: _showComment,
        onSecondaryTapUp: (_) => _showComment(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: decoration,
              child: _editing
                  ? TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      readOnly: locked,
                      textAlign: widget.textAlign,
                      minLines: widget.multiline ? widget.minLines : 1,
                      maxLines: widget.multiline ? null : 1,
                      style: effectiveStyle,
                      cursorColor: palette.accent,
                      onTapOutside: (_) => _focusNode?.unfocus(),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: widget.hintText,
                        hintStyle: effectiveStyle.copyWith(
                          color: palette.ink.withValues(alpha: .32),
                        ),
                        contentPadding: contentPadding,
                      ),
                      onChanged: (value) {
                        setState(() => _value = value);
                        widget.controller.setText(widget.fieldName, value);
                        widget.onChanged?.call();
                      },
                    )
                  : Container(
                      width: double.infinity,
                      constraints: BoxConstraints(
                        minHeight: widget.multiline
                            ? widget.minLines * 20.0 + 12.0
                            : (widget.compact ? 28 : 34),
                      ),
                      padding: contentPadding,
                      alignment: widget.multiline
                          ? Alignment.topLeft
                          : switch (widget.textAlign) {
                              TextAlign.center => Alignment.center,
                              TextAlign.right => Alignment.centerRight,
                              _ => Alignment.centerLeft,
                            },
                      child: _value.isEmpty
                          ? (widget.hintText == null
                                ? const SizedBox.shrink()
                                : Text(
                                    widget.hintText!,
                                    textAlign: widget.textAlign,
                                    style: effectiveStyle.copyWith(
                                      color: palette.ink.withValues(alpha: .32),
                                    ),
                                  ))
                          : RichText(
                              text: _value.contains('*') || _value.contains('_')
                                  ? buildInlineMarkdownSpan(
                                      _value,
                                      effectiveStyle,
                                      boldColor: palette.bold,
                                      italicColor: palette.italic,
                                      boldItalicColor: palette.boldItalic,
                                    )
                                  : TextSpan(
                                      text: _value,
                                      style: effectiveStyle,
                                    ),
                              textAlign: widget.textAlign,
                              textDirection: Directionality.of(context),
                              textScaler: MediaQuery.textScalerOf(context),
                            ),
                    ),
            ),
            Positioned(
              top: -3,
              right: -3,
              child: ValueListenableBuilder<bool>(
                valueListenable: widget.controller.commentStateFor(
                  widget.fieldName,
                ),
                builder: (context, hasComment, _) => hasComment
                    ? GestureDetector(
                        onTap: _showComment,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: palette.comment,
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox.square(dimension: 7.5),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_followsName) {
      widget.controller.nameState.removeListener(_handleNameChanged);
    }
    _focusNode
      ?..removeListener(_handleFocus)
      ..dispose();
    _textController?.dispose();
    super.dispose();
  }
}

class _SheetCheckbox extends StatefulWidget {
  const _SheetCheckbox({
    super.key,
    required this.fieldName,
    required this.controller,
    this.allowExpertise = false,
    this.size = 34,
    this.onChanged,
  });

  final String fieldName;
  final SheetController controller;
  final bool allowExpertise;
  final double size;
  final VoidCallback? onChanged;

  @override
  State<_SheetCheckbox> createState() => _SheetCheckboxState();
}

class _SheetCheckboxState extends State<_SheetCheckbox> {
  late SheetCheckboxValue _value;

  @override
  void initState() {
    super.initState();
    _value = SheetCheckboxValue.fromStored(
      widget.controller.valueFor(widget.fieldName),
    );
  }

  @override
  void didUpdateWidget(_SheetCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    _value = SheetCheckboxValue.fromStored(
      widget.controller.valueFor(widget.fieldName),
    );
  }

  void _showComment() => showFieldCommentDialog(
    context: context,
    fieldName: widget.fieldName,
    initialValue: widget.controller.commentFor(widget.fieldName),
    readOnly: widget.controller.locked,
    onSave: (value) => widget.controller.setComment(widget.fieldName, value),
  );

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: widget.controller.lockedState,
      builder: (context, locked, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: locked
            ? null
            : () {
                setState(() {
                  _value = _value.next(allowExpertise: widget.allowExpertise);
                });
                widget.controller.setCheckbox(widget.fieldName, _value);
                widget.onChanged?.call();
              },
        onLongPress: _showComment,
        onSecondaryTapUp: (_) => _showComment(),
        child: SizedBox.square(
          dimension: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 17,
                height: 17,
                decoration: BoxDecoration(
                  color: palette.paper,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _value == SheetCheckboxValue.expertise
                        ? palette.expertise
                        : palette.ink,
                    width: 1.5,
                  ),
                ),
                child: _value == SheetCheckboxValue.unchecked
                    ? null
                    : Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _value == SheetCheckboxValue.expertise
                                ? palette.expertise
                                : palette.text,
                          ),
                        ),
                      ),
              ),
              Positioned(
                top: 1,
                right: 1,
                child: ValueListenableBuilder<bool>(
                  valueListenable: widget.controller.commentStateFor(
                    widget.fieldName,
                  ),
                  builder: (context, hasComment, _) => hasComment
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: palette.comment,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: 7),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
