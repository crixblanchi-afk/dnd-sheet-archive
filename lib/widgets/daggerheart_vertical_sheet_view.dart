import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../controllers/sheet_controller.dart';
import '../models/daggerheart_card.dart';
import '../models/game_system.dart';
import '../models/sheet_field.dart';
import '../theme/sheet_palette.dart';
import 'comment_dialog.dart';
import 'daggerheart_cards_page.dart';
import 'image_field_overlay.dart';
import 'inline_markdown.dart';
import 'sheet_ornaments.dart';

const _dhTraits = [
  (key: 'Agility', label: 'Agility', actions: 'Sprint · Leap · Maneuver'),
  (key: 'Strength', label: 'Strength', actions: 'Lift · Smash · Grapple'),
  (key: 'Finesse', label: 'Finesse', actions: 'Control · Hide · Tinker'),
  (key: 'Instinct', label: 'Instinct', actions: 'Perceive · Sense · Navigate'),
  (key: 'Presence', label: 'Presence', actions: 'Charm · Perform · Deceive'),
  (
    key: 'Knowledge',
    label: 'Knowledge',
    actions: 'Recall · Analyze · Comprehend',
  ),
];

const _dhHopeFeatures = <DaggerheartClass, String>{
  DaggerheartClass.bard:
      'Make a Scene: spendi 3 Hope per distrarre un bersaglio entro Close (−2 Difficulty).',
  DaggerheartClass.druid:
      'Evolution: spendi 3 Hope per trasformarti in Beastform senza segnare Stress (+1 a un tratto).',
  DaggerheartClass.guardian:
      'Frontline Tank: spendi 3 Hope per recuperare 2 Armor Slot.',
  DaggerheartClass.ranger:
      'Hold Them Off: spendi 3 Hope su un attacco riuscito per colpire altri 2 avversari a portata.',
  DaggerheartClass.rogue:
      'Rogue’s Dodge: spendi 3 Hope per +2 Evasion finché un attacco non ti colpisce o fino al riposo.',
  DaggerheartClass.seraph:
      'Life Support: spendi 3 Hope per curare 1 HP a un alleato entro Close.',
  DaggerheartClass.sorcerer:
      'Volatile Magic: spendi 3 Hope per ritirare qualsiasi dado danno di un attacco magico.',
  DaggerheartClass.warrior:
      'No Mercy: spendi 3 Hope per +1 ai tiri per colpire fino al prossimo riposo.',
  DaggerheartClass.wizard:
      'Not This Time: spendi 3 Hope per costringere un avversario entro Far a ritirare attacco o danno.',
};

const _dhTier2Rows = [
  (key: 'Traits', count: 3, label: '+1 a due tratti non segnati e segnali'),
  (key: 'HP', count: 2, label: 'Guadagna permanentemente 1 slot HP'),
  (key: 'Stress', count: 2, label: 'Guadagna permanentemente 1 slot Stress'),
  (key: 'Exp', count: 1, label: 'Guadagna permanentemente +1 a due Esperienze'),
  (
    key: 'DomainCard',
    count: 1,
    label: 'Scegli una card Domain extra (fino a lv 4)',
  ),
  (key: 'Evasion', count: 1, label: 'Guadagna permanentemente +1 a Evasion'),
];

const _dhTierHighRows = [
  (key: 'Traits', count: 3, label: '+1 a due tratti non segnati e segnali'),
  (key: 'HP', count: 2, label: 'Guadagna permanentemente 1 slot HP'),
  (key: 'Stress', count: 2, label: 'Guadagna permanentemente 1 slot Stress'),
  (key: 'Exp', count: 1, label: 'Guadagna permanentemente +1 a due Esperienze'),
  (key: 'DomainCard', count: 1, label: 'Scegli una card Domain extra'),
  (key: 'Evasion', count: 1, label: 'Guadagna permanentemente +1 a Evasion'),
  (key: 'Subclass', count: 1, label: 'Prendi una card Subclass potenziata'),
  (key: 'Proficiency', count: 2, label: 'Aumenta Proficiency di +1'),
  (
    key: 'Multiclass',
    count: 2,
    label: 'Multiclasse: scegli una classe aggiuntiva',
  ),
];

const _dhCompanionTrainingRows = [
  (
    key: 'Intelligent',
    count: 3,
    label: 'Intelligent: +1 a una Companion Experience',
  ),
  (
    key: 'LightInDark',
    count: 1,
    label: 'Light in the Dark: slot Hope aggiuntivo',
  ),
  (key: 'LightInDarkHope', count: 1, label: 'Light in the Dark · Hope segnato'),
  (
    key: 'CreatureComfort',
    count: 1,
    label: 'Creature Comfort: guadagna Hope o cura Stress',
  ),
  (
    key: 'Armored',
    count: 1,
    label: 'Armored: segna un tuo Armor Slot invece dello Stress',
  ),
  (
    key: 'Vicious',
    count: 3,
    label: 'Vicious: aumenta dado danno o gittata di un passo',
  ),
  (
    key: 'Resilient',
    count: 3,
    label: 'Resilient: slot Stress aggiuntivo per il compagno',
  ),
  (
    key: 'Bonded',
    count: 1,
    label: 'Bonded: tiro salvezza del compagno sull’ultimo HP',
  ),
  (
    key: 'Aware',
    count: 3,
    label: 'Aware: +2 permanente a Evasion del compagno',
  ),
];

class _SectionSpec {
  const _SectionSpec(this.label, this.startIndex);

  final String label;
  final int startIndex;
}

/// Scheda Daggerheart in scorrimento verticale compatto, coerente con la
/// grammatica grafica della vista verticale D&D 5e.
class DaggerheartVerticalSheetView extends StatefulWidget {
  const DaggerheartVerticalSheetView({
    super.key,
    required this.controller,
    required this.onManageCards,
    this.compactLayout = false,
  });

  final SheetController controller;
  final VoidCallback onManageCards;
  final bool compactLayout;

  @override
  State<DaggerheartVerticalSheetView> createState() =>
      _DaggerheartVerticalSheetViewState();
}

class _DaggerheartVerticalSheetViewState
    extends State<DaggerheartVerticalSheetView> {
  final _scrollController = ScrollController();
  final _sliverKey = GlobalKey();
  final _activeSection = ValueNotifier<int>(0);
  late final List<_SectionSpec> _sections;
  late final List<GlobalKey> _sectionKeys;
  late final List<GlobalKey> _chipKeys;
  late final List<double> _sectionOffsets;
  late final List<Widget Function(BuildContext)> _itemBuilders;
  List<DaggerheartCardDef>? _catalog;
  final Set<String> _expandedSections = {};
  final Map<String, int> _extraRevealedRows = {};
  bool _jumpingToSection = false;
  double _lastCheckedOffset = double.negativeInfinity;

  DaggerheartClass get _cls =>
      widget.controller.character.daggerheartClass ?? DaggerheartClass.blank;

  bool _weaponHasData(String prefix, {bool includeSlots = false}) {
    final c = widget.controller;
    for (final suffix in [
      '_Name',
      '_TraitRange',
      '_Damage',
      '_Feature',
      '_Feature2',
    ]) {
      if (_dhHasValue(c, '$prefix$suffix')) return true;
    }
    if (includeSlots &&
        (_dhIsChecked(c, '${prefix}_Primary') ||
            _dhIsChecked(c, '${prefix}_Secondary') ||
            _dhIsChecked(c, '${prefix}_Hand1') ||
            _dhIsChecked(c, '${prefix}_Hand2'))) {
      return true;
    }
    return false;
  }

  void _toggleExpanded(String key) => setState(() {
    if (!_expandedSections.add(key)) {
      _expandedSections.remove(key);
    }
  });

  void _revealOneRow(String key) => setState(() {
    _extraRevealedRows[key] = (_extraRevealedRows[key] ?? 0) + 1;
  });

  void _hideEmptyRows(String key) => setState(() {
    _extraRevealedRows.remove(key);
  });

  void _onFieldEdited() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _catalog = DaggerheartCardDef.cachedCatalog;
    if (_catalog == null) {
      unawaited(
        DaggerheartCardDef.loadCatalog().then((cards) {
          if (!mounted) return;
          setState(() => _catalog = cards);
        }, onError: (Object _) {}),
      );
    }
    if (_weaponHasData('DH_SecondaryWeapon')) {
      _expandedSections.add('secondary_weapon');
    }
    if (_weaponHasData('DH_InvWeapon1', includeSlots: true)) {
      _expandedSections.add('inv_weapon_1');
    }
    if (_weaponHasData('DH_InvWeapon2', includeSlots: true)) {
      _expandedSections.add('inv_weapon_2');
    }
    _buildSections();
    _scrollController.addListener(_handleScroll);
    widget.controller.addListener(_handleControllerChanged);
  }

  void _buildSections() {
    final c = widget.controller;
    final sections = <_SectionSpec>[];
    final items = <Widget Function(BuildContext)>[];

    void addSection(String label, List<Widget Function(BuildContext)> blocks) {
      sections.add(_SectionSpec(label, items.length));
      items.addAll(blocks);
    }

    addSection('Scheda', [
      (_) => _IdentityBlock(controller: c, daggerheartClass: _cls),
    ]);

    addSection('Salute', [
      (_) => _DefenseAndVitalsBlock(
        controller: c,
        daggerheartClass: _cls,
        onFieldEdited: _onFieldEdited,
      ),
    ]);

    addSection('Tratti', [
      (_) => _TraitsBlock(controller: c),
      (_) => _ExperienceBlock(
        controller: c,
        extraRows: _extraRevealedRows['experience'] ?? 0,
        onAddRow: () => _revealOneRow('experience'),
        onHideEmpty: () => _hideEmptyRows('experience'),
        onFieldEdited: _onFieldEdited,
      ),
      (_) => _GoldBarBlock(controller: c, onFieldEdited: _onFieldEdited),
    ]);

    addSection('Equip', [
      (_) => _EquipmentBlock(
        controller: c,
        secondaryExpanded:
            _expandedSections.contains('secondary_weapon') ||
            _weaponHasData('DH_SecondaryWeapon'),
        onToggleSecondary: () => _toggleExpanded('secondary_weapon'),
        onFieldEdited: _onFieldEdited,
      ),
    ]);

    addSection('Card', [
      (_) => _SelectedCardsBlock(
        controller: c,
        catalog: _catalog,
        onManageCards: widget.onManageCards,
      ),
    ]);

    addSection('Zaino', [
      (_) => _InventoryMultilineBlock(
        controller: c,
        showWeapon1:
            _expandedSections.contains('inv_weapon_1') ||
            _weaponHasData('DH_InvWeapon1', includeSlots: true),
        showWeapon2:
            _expandedSections.contains('inv_weapon_2') ||
            _weaponHasData('DH_InvWeapon2', includeSlots: true),
        onRevealWeapon1: () => _toggleExpanded('inv_weapon_1'),
        onRevealWeapon2: () => _toggleExpanded('inv_weapon_2'),
        onFieldEdited: _onFieldEdited,
      ),
    ]);

    if (_cls == DaggerheartClass.ranger) {
      addSection('Compagno', [
        (_) => _RangerCompanionBlock(
          controller: c,
          extraExpRows: _extraRevealedRows['comp_experience'] ?? 0,
          onAddExpRow: () => _revealOneRow('comp_experience'),
          onHideEmptyExp: () => _hideEmptyRows('comp_experience'),
          trainingExpanded: _expandedSections.contains('comp_training'),
          onToggleTraining: () => _toggleExpanded('comp_training'),
          onFieldEdited: _onFieldEdited,
        ),
      ]);
    }

    addSection('Guida', [
      if (_cls == DaggerheartClass.blank ||
          _cls == DaggerheartClass.guardian ||
          _cls == DaggerheartClass.seraph ||
          _cls == DaggerheartClass.wizard)
        (_) => _ClassFeatureExtrasBlock(controller: c, daggerheartClass: _cls),
      if (_cls != DaggerheartClass.blank) ...[
        (_) => _GuideQuestionsBlock(
          controller: c,
          backgroundExpanded: _expandedSections.contains('background'),
          connectionsExpanded: _expandedSections.contains('connections'),
          onToggleBackground: () => _toggleExpanded('background'),
          onToggleConnections: () => _toggleExpanded('connections'),
          onFieldEdited: _onFieldEdited,
        ),
        (_) => _LevelUpTiersBlock(
          controller: c,
          expandedTiers: {
            if (_expandedSections.contains('tier_2')) 2,
            if (_expandedSections.contains('tier_3')) 3,
            if (_expandedSections.contains('tier_4')) 4,
          },
          onToggleTier: (tier) => _toggleExpanded('tier_$tier'),
          onFieldEdited: _onFieldEdited,
        ),
      ],
      (_) => const _FooterHint(),
    ]);

    _sections = sections;
    _itemBuilders = items;
    _sectionKeys = List.generate(sections.length, (_) => GlobalKey());
    _chipKeys = List.generate(sections.length, (_) => GlobalKey());
    _sectionOffsets = List.generate(sections.length, (i) => i * 320.0);
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didUpdateWidget(DaggerheartVerticalSheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
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
        final targetItem = _sections[index].startIndex;
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
    final sectionIndex = _sections.indexWhere((s) => s.startIndex == index);
    Widget content = _itemBuilders[index](context);
    if (sectionIndex >= 0) {
      content = KeyedSubtree(key: _sectionKeys[sectionIndex], child: content);
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: index == _itemBuilders.length - 1 ? 0 : 10,
          ),
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
          SizedBox(height: widget.compactLayout ? 48 : 64),
          if (!widget.compactLayout)
            RepaintBoundary(
              child: _SectionNavBar(
                labels: [for (final section in _sections) section.label],
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
                    itemCount: _itemBuilders.length,
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

bool _dhHasValue(SheetController c, String fieldName) =>
    (c.valueFor(fieldName)?.toString().isNotEmpty ?? false) ||
    (c.commentFor(fieldName)?.isNotEmpty ?? false);

bool _dhIsChecked(SheetController c, String fieldName) =>
    SheetCheckboxValue.fromStored(c.valueFor(fieldName)) !=
    SheetCheckboxValue.unchecked;

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
          height: 38,
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
                          horizontal: 9,
                          vertical: 4,
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

/// Testata compatta: Nome + badge Livello affiancati, e sotto Heritage,
/// Subclass e Pronomi ben proporzionati.
class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({
    required this.controller,
    required this.daggerheartClass,
  });

  final SheetController controller;
  final DaggerheartClass daggerheartClass;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final classCaption = daggerheartClass == DaggerheartClass.blank
        ? 'DAGGERHEART'
        : '${daggerheartClass.label.toUpperCase()} · '
              '${daggerheartClass.domains.map((d) => (daggerheartDomainLabels[d] ?? d).toUpperCase()).join(' & ')}';
    final subclassCaption = daggerheartClass == DaggerheartClass.blank
        ? 'Class & Subclass'
        : 'Subclass';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SheetBannerBox(
                caption: classCaption,
                child: _DhTextField(
                  key: const ValueKey('CharacterName'),
                  fieldName: 'CharacterName',
                  dialogLabel: 'Nome personaggio',
                  controller: controller,
                  textAlign: TextAlign.center,
                  style: _FieldStyle.plain,
                  textStyle: TextStyle(
                    fontFamily: 'RobotoSlab',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 62,
              child: SheetFrameBox(
                caption: 'Lv',
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 5),
                child: _DhTextField(
                  key: const ValueKey('DH_Level'),
                  fieldName: 'DH_Level',
                  dialogLabel: 'Level',
                  controller: controller,
                  textAlign: TextAlign.center,
                  style: _FieldStyle.plain,
                  compact: true,
                  hintText: '1',
                  textStyle: TextStyle(
                    fontFamily: 'RobotoSlab',
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SheetFrameBox(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 400) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: _UnderlinedField(
                        fieldName: 'DH_Heritage',
                        caption: 'Heritage',
                        controller: controller,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 4,
                      child: _UnderlinedField(
                        fieldName: 'DH_Subclass',
                        caption: subclassCaption,
                        controller: controller,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 92,
                      child: _UnderlinedField(
                        fieldName: 'DH_Pronouns',
                        caption: 'Pronouns',
                        controller: controller,
                      ),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _UnderlinedField(
                          fieldName: 'DH_Heritage',
                          caption: 'Heritage',
                          controller: controller,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 88,
                        child: _UnderlinedField(
                          fieldName: 'DH_Pronouns',
                          caption: 'Pronouns',
                          controller: controller,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _UnderlinedField(
                    fieldName: 'DH_Subclass',
                    caption: subclassCaption,
                    controller: controller,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Blocco Difesa, Soglie di danno, HP, Stress e Hope compattato e proporzionato.
class _DefenseAndVitalsBlock extends StatelessWidget {
  const _DefenseAndVitalsBlock({
    required this.controller,
    required this.daggerheartClass,
    required this.onFieldEdited,
  });

  final SheetController controller;
  final DaggerheartClass daggerheartClass;
  final VoidCallback onFieldEdited;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final statStyle = TextStyle(
      fontFamily: 'RobotoSlab',
      fontSize: 20,
      fontWeight: FontWeight.w800,
      color: palette.text,
    );
    final thresholdStyle = TextStyle(
      fontFamily: 'RobotoSlab',
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: palette.text,
    );
    final hopeFeature = _dhHopeFeatures[daggerheartClass];

    return SheetTray(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Riga singola proporzionata: Evasion + Armor Score (compatti) + Armor Slots.
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 400;
              final statWidth = compact ? 74.0 : 86.0;
              final slotCols = compact ? 4 : 6;
              final slotRows = 12 ~/ slotCols;
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: statWidth,
                      child: SheetFrameBox(
                        caption: 'Evasion',
                        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                        child: Center(
                          child: _DhTextField(
                            key: const ValueKey('DH_Evasion'),
                            fieldName: 'DH_Evasion',
                            dialogLabel: 'Evasion',
                            controller: controller,
                            textAlign: TextAlign.center,
                            style: _FieldStyle.plain,
                            compact: true,
                            hintText: '${daggerheartClass.startingEvasion}',
                            textStyle: statStyle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: statWidth,
                      child: ArmorClassShield(
                        caption: 'ARMOR\nSCORE',
                        child: _DhTextField(
                          key: const ValueKey('DH_ArmorScore'),
                          fieldName: 'DH_ArmorScore',
                          dialogLabel: 'Armor Score',
                          controller: controller,
                          textAlign: TextAlign.center,
                          style: _FieldStyle.plain,
                          compact: true,
                          hintText: '0',
                          textStyle: statStyle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SheetFrameBox(
                        caption:
                            'Armor Slots (${_countChecked(controller, 'DH_ArmorSlot_', 12)}/12)',
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var row = 0; row < slotRows; row++)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var col = 0; col < slotCols; col++)
                                    _DhCheckbox(
                                      key: ValueKey(
                                        'DH_ArmorSlot_${row * slotCols + col + 1}',
                                      ),
                                      fieldName:
                                          'DH_ArmorSlot_${row * slotCols + col + 1}',
                                      dialogLabel:
                                          'Armor Slot ${row * slotCols + col + 1}',
                                      controller: controller,
                                      shape: _SlotShape.shield,
                                      size: compact ? 23 : 26,
                                      onChanged: onFieldEdited,
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // Soglie di danno + HP + Stress in un unico riquadro ordinato.
          SheetFrameBox(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: _ThresholdBadge(title: 'MINOR', subtitle: '1 HP'),
                    ),
                    SizedBox(
                      width: 48,
                      child: _DhTextField(
                        key: const ValueKey('DH_Threshold_Major'),
                        fieldName: 'DH_Threshold_Major',
                        dialogLabel: 'Soglia Major',
                        controller: controller,
                        textAlign: TextAlign.center,
                        style: _FieldStyle.shaded,
                        compact: true,
                        hintText: '–',
                        textStyle: thresholdStyle,
                      ),
                    ),
                    const Expanded(
                      child: _ThresholdBadge(title: 'MAJOR', subtitle: '2 HP'),
                    ),
                    SizedBox(
                      width: 48,
                      child: _DhTextField(
                        key: const ValueKey('DH_Threshold_Severe'),
                        fieldName: 'DH_Threshold_Severe',
                        dialogLabel: 'Soglia Severe',
                        controller: controller,
                        textAlign: TextAlign.center,
                        style: _FieldStyle.shaded,
                        compact: true,
                        hintText: '–',
                        textStyle: thresholdStyle,
                      ),
                    ),
                    const Expanded(
                      child: _ThresholdBadge(title: 'SEVERE', subtitle: '3 HP'),
                    ),
                  ],
                ),
                Divider(height: 14, color: palette.ink.withValues(alpha: .18)),
                _VitalTrackerRow(
                  label: 'HP',
                  count: _effectiveVitalMax(
                    controller: controller,
                    maxFieldName: 'DH_HP_Max',
                    slotPrefix: 'DH_HP_',
                    defaultMax: daggerheartClass.startingHp,
                    hardMax: 12,
                  ),
                  hardMax: 12,
                  fieldPrefix: 'DH_HP_',
                  shape: _SlotShape.box,
                  controller: controller,
                  onChanged: onFieldEdited,
                  decrementKey: const ValueKey('dh-hp-max-dec'),
                  incrementKey: const ValueKey('dh-hp-max-inc'),
                  onMaxChanged: (next) => _setVitalMax(
                    controller: controller,
                    maxFieldName: 'DH_HP_Max',
                    slotPrefix: 'DH_HP_',
                    nextMax: next,
                    hardMax: 12,
                    onEdited: onFieldEdited,
                  ),
                ),
                const SizedBox(height: 6),
                _VitalTrackerRow(
                  label: 'STRESS',
                  count: _effectiveVitalMax(
                    controller: controller,
                    maxFieldName: 'DH_Stress_Max',
                    slotPrefix: 'DH_Stress_',
                    defaultMax: daggerheartClass.startingStress,
                    hardMax: 12,
                  ),
                  hardMax: 12,
                  fieldPrefix: 'DH_Stress_',
                  shape: _SlotShape.box,
                  controller: controller,
                  onChanged: onFieldEdited,
                  decrementKey: const ValueKey('dh-stress-max-dec'),
                  incrementKey: const ValueKey('dh-stress-max-inc'),
                  onMaxChanged: (next) => _setVitalMax(
                    controller: controller,
                    maxFieldName: 'DH_Stress_Max',
                    slotPrefix: 'DH_Stress_',
                    nextMax: next,
                    hardMax: 12,
                    onEdited: onFieldEdited,
                  ),
                ),
                Divider(height: 14, color: palette.ink.withValues(alpha: .18)),
                _VitalTrackerRow(
                  label: 'HOPE',
                  count: 6,
                  fieldPrefix: 'DH_Hope_',
                  shape: _SlotShape.diamond,
                  controller: controller,
                  onChanged: onFieldEdited,
                ),
                if (hopeFeature != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    hopeFeature,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'RobotoSlab',
                      fontSize: 10.5,
                      height: 1.3,
                      color: palette.ink.withValues(alpha: .72),
                    ),
                  ),
                ] else if (daggerheartClass == DaggerheartClass.blank) ...[
                  const SizedBox(height: 6),
                  _UnderlinedField(
                    fieldName: 'DH_HopeFeature',
                    caption: 'Hope Feature',
                    controller: controller,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

int _countChecked(SheetController c, String prefix, int count) {
  var total = 0;
  for (var i = 1; i <= count; i++) {
    if (_dhIsChecked(c, '$prefix$i')) total++;
  }
  return total;
}

int _highestCheckedSlot(SheetController c, String prefix, int hardMax) {
  var highest = 0;
  for (var i = 1; i <= hardMax; i++) {
    if (_dhIsChecked(c, '$prefix$i')) highest = i;
  }
  return highest;
}

int _effectiveVitalMax({
  required SheetController controller,
  required String maxFieldName,
  required String slotPrefix,
  required int defaultMax,
  required int hardMax,
}) {
  final raw = controller.valueFor(maxFieldName)?.toString().trim();
  final parsed = raw == null ? null : int.tryParse(raw);
  final configured = (parsed ?? defaultMax).clamp(1, hardMax);
  final highest = _highestCheckedSlot(controller, slotPrefix, hardMax);
  return highest > configured ? highest : configured;
}

void _setVitalMax({
  required SheetController controller,
  required String maxFieldName,
  required String slotPrefix,
  required int nextMax,
  required int hardMax,
  required VoidCallback onEdited,
}) {
  final clamped = nextMax.clamp(1, hardMax);
  controller.setText(maxFieldName, '$clamped');
  for (var i = clamped + 1; i <= hardMax; i++) {
    if (_dhIsChecked(controller, '$slotPrefix$i')) {
      controller.setCheckbox('$slotPrefix$i', SheetCheckboxValue.unchecked);
    }
  }
  onEdited();
}

class _VitalTrackerRow extends StatelessWidget {
  const _VitalTrackerRow({
    required this.label,
    required this.count,
    required this.fieldPrefix,
    required this.shape,
    required this.controller,
    required this.onChanged,
    this.hardMax,
    this.decrementKey,
    this.incrementKey,
    this.onMaxChanged,
  });

  final String label;
  final int count;
  final String fieldPrefix;
  final _SlotShape shape;
  final SheetController controller;
  final VoidCallback onChanged;
  final int? hardMax;
  final Key? decrementKey;
  final Key? incrementKey;
  final ValueChanged<int>? onMaxChanged;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final checked = _countChecked(controller, fieldPrefix, count);
    final maxAllowed = hardMax ?? count;
    final showStepper = onMaxChanged != null && !controller.locked;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 56,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontFamily: 'RobotoSlab',
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .6,
                  color: palette.ink,
                ),
              ),
              Text(
                '$checked / $count',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontFamily: 'RobotoSlab',
                  fontSize: 9.5,
                  color: palette.ink.withValues(alpha: .62),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 2,
            runSpacing: 2,
            children: [
              for (var i = 1; i <= count; i++)
                _DhCheckbox(
                  key: ValueKey('$fieldPrefix$i'),
                  fieldName: '$fieldPrefix$i',
                  dialogLabel: '$label $i',
                  controller: controller,
                  shape: shape,
                  size: 27,
                  onChanged: onChanged,
                ),
            ],
          ),
        ),
        if (showStepper) ...[
          const SizedBox(width: 4),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.ink.withValues(alpha: .22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Riduci slot $label',
                  child: InkWell(
                    key: decrementKey,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(11),
                    ),
                    onTap: count > 1 ? () => onMaxChanged!(count - 1) : null,
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: Icon(
                        Icons.remove,
                        size: 13,
                        color: palette.ink.withValues(
                          alpha: count > 1 ? .78 : .22,
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 12,
                  color: palette.ink.withValues(alpha: .18),
                ),
                Tooltip(
                  message: 'Aggiungi slot $label',
                  child: InkWell(
                    key: incrementKey,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(11),
                    ),
                    onTap: count < maxAllowed
                        ? () => onMaxChanged!(count + 1)
                        : null,
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: Icon(
                        Icons.add,
                        size: 13,
                        color: palette.ink.withValues(
                          alpha: count < maxAllowed ? .78 : .22,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ThresholdBadge extends StatelessWidget {
  const _ThresholdBadge({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontFamily: 'RobotoSlab',
            fontSize: 9.2,
            fontWeight: FontWeight.w800,
            color: palette.ink,
          ),
        ),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontFamily: 'RobotoSlab',
            fontSize: 8.2,
            color: palette.ink.withValues(alpha: .62),
          ),
        ),
      ],
    );
  }
}

class _TraitsBlock extends StatelessWidget {
  const _TraitsBlock({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return SheetTray(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 420 ? 3 : 2;
          return Column(
            children: [
              for (var i = 0; i < _dhTraits.length; i += columns) ...[
                if (i > 0) const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var col = 0; col < columns; col++) ...[
                      if (col > 0) const SizedBox(width: 6),
                      Expanded(
                        child: i + col < _dhTraits.length
                            ? _TraitCard(
                                trait: _dhTraits[i + col],
                                controller: controller,
                                palette: palette,
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
}

class _TraitCard extends StatelessWidget {
  const _TraitCard({
    required this.trait,
    required this.controller,
    required this.palette,
  });

  final ({String key, String label, String actions}) trait;
  final SheetController controller;
  final SheetPalette palette;

  @override
  Widget build(BuildContext context) => SheetFrameBox(
    padding: const EdgeInsets.fromLTRB(8, 5, 6, 6),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                trait.label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontFamily: 'RobotoSlab',
                  fontSize: 9.2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .4,
                  color: palette.ink,
                ),
              ),
            ),
            _DhCheckbox(
              key: ValueKey('DH_TraitMark_${trait.key}'),
              fieldName: 'DH_TraitMark_${trait.key}',
              dialogLabel: '${trait.label} segnato',
              controller: controller,
              size: 22,
            ),
          ],
        ),
        _DhTextField(
          key: ValueKey('DH_Trait_${trait.key}'),
          fieldName: 'DH_Trait_${trait.key}',
          dialogLabel: trait.label,
          controller: controller,
          textAlign: TextAlign.center,
          style: _FieldStyle.plain,
          compact: true,
          hintText: '+0',
          textStyle: TextStyle(
            fontFamily: 'RobotoSlab',
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: palette.text,
          ),
        ),
        Text(
          trait.actions,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontFamily: 'RobotoSlab',
            fontSize: 8.2,
            color: palette.ink.withValues(alpha: .62),
          ),
        ),
      ],
    ),
  );
}

class _CollapsibleSheetBox extends StatelessWidget {
  const _CollapsibleSheetBox({
    super.key,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.summary,
  });

  final String title;
  final String? summary;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return SheetFrameBox(
      padding: EdgeInsets.fromLTRB(12, 8, 10, expanded ? 10 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontFamily: 'RobotoSlab',
                      fontSize: 9.8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .75,
                      color: palette.ink,
                    ),
                  ),
                ),
                if (summary != null && summary!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      summary!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontFamily: 'RobotoSlab',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: palette.ink.withValues(alpha: .68),
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
          if (expanded) ...[const SizedBox(height: 8), child],
        ],
      ),
    );
  }
}

/// Experience compatto: barra singola finché vuota, poi mostra solo le righe
/// compilate con pulsante rapido "+" direttamente nell'intestazione.
class _ExperienceBlock extends StatelessWidget {
  const _ExperienceBlock({
    required this.controller,
    required this.extraRows,
    required this.onAddRow,
    required this.onHideEmpty,
    required this.onFieldEdited,
  });

  final SheetController controller;
  final int extraRows;
  final VoidCallback onAddRow;
  final VoidCallback onHideEmpty;
  final VoidCallback onFieldEdited;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final filledIndices = <int>[];
    final emptyIndices = <int>[];
    for (var i = 1; i <= 5; i++) {
      if (_dhHasValue(controller, 'DH_Experience_$i') ||
          _dhHasValue(controller, 'DH_ExperienceMod_$i')) {
        filledIndices.add(i);
      } else {
        emptyIndices.add(i);
      }
    }
    final shownEmpty = emptyIndices.take(extraRows).toList();
    final visible = [...filledIndices, ...shownEmpty]..sort();
    final remainingEmpty = emptyIndices.length - shownEmpty.length;

    return SheetFrameBox(
      padding: EdgeInsets.fromLTRB(12, 7, 8, visible.isEmpty ? 7 : 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'EXPERIENCE (${filledIndices.length}/5)',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: 'RobotoSlab',
                    fontSize: 9.8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .75,
                    color: palette.ink,
                  ),
                ),
              ),
              if (!controller.locked && shownEmpty.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: palette.ink.withValues(alpha: .72),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 28),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onHideEmpty,
                  child: const Text(
                    'Nascondi vuote',
                    style: TextStyle(fontFamily: 'RobotoSlab', fontSize: 10.5),
                  ),
                ),
              if (!controller.locked && remainingEmpty > 0)
                TextButton.icon(
                  key: const ValueKey('dh-add-experience'),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.ink,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 28),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onAddRow,
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text(
                    'Aggiungi',
                    style: TextStyle(fontFamily: 'RobotoSlab', fontSize: 11),
                  ),
                ),
            ],
          ),
          if (visible.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (var idx = 0; idx < visible.length; idx++) ...[
              if (idx > 0) const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: _DhTextField(
                      key: ValueKey('DH_Experience_${visible[idx]}'),
                      fieldName: 'DH_Experience_${visible[idx]}',
                      dialogLabel: 'Experience ${visible[idx]}',
                      controller: controller,
                      hintText: 'Esperienza ${visible[idx]}',
                      compact: true,
                      onChanged: onFieldEdited,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 52,
                    child: _DhTextField(
                      key: ValueKey('DH_ExperienceMod_${visible[idx]}'),
                      fieldName: 'DH_ExperienceMod_${visible[idx]}',
                      dialogLabel: 'Bonus Experience ${visible[idx]}',
                      controller: controller,
                      textAlign: TextAlign.center,
                      style: _FieldStyle.shaded,
                      hintText: '+2',
                      compact: true,
                      onChanged: onFieldEdited,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Barra Gold compatta in una sola riga con contatori − / + sincronizzati con
/// i checkbox `DH_GoldHandful_1..9`, `DH_GoldBag_1..9` e `DH_GoldChest`.
class _GoldBarBlock extends StatelessWidget {
  const _GoldBarBlock({required this.controller, required this.onFieldEdited});

  final SheetController controller;
  final VoidCallback onFieldEdited;

  void _setCount(String prefix, int max, int target) {
    final clamped = target.clamp(0, max);
    for (var i = 1; i <= max; i++) {
      controller.setCheckbox(
        '$prefix$i',
        i <= clamped
            ? SheetCheckboxValue.proficient
            : SheetCheckboxValue.unchecked,
      );
    }
    onFieldEdited();
  }

  @override
  Widget build(BuildContext context) {
    final handfuls = _countChecked(controller, 'DH_GoldHandful_', 9);
    final bags = _countChecked(controller, 'DH_GoldBag_', 9);
    final chest = _dhIsChecked(controller, 'DH_GoldChest');
    final locked = controller.locked;

    return SheetFrameBox(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: _GoldStepperPlaque(
              label: 'HANDFULS',
              value: handfuls,
              max: 9,
              locked: locked,
              decrementKey: const ValueKey('dh-gold-handful-dec'),
              incrementKey: const ValueKey('dh-gold-handful-inc'),
              onChanged: (next) => _setCount('DH_GoldHandful_', 9, next),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: _GoldStepperPlaque(
              label: 'BAGS',
              value: bags,
              max: 9,
              locked: locked,
              decrementKey: const ValueKey('dh-gold-bag-dec'),
              incrementKey: const ValueKey('dh-gold-bag-inc'),
              onChanged: (next) => _setCount('DH_GoldBag_', 9, next),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: _GoldChestPlaque(
              checked: chest,
              locked: locked,
              onToggle: () {
                controller.setCheckbox(
                  'DH_GoldChest',
                  chest
                      ? SheetCheckboxValue.unchecked
                      : SheetCheckboxValue.proficient,
                );
                onFieldEdited();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GoldStepperPlaque extends StatelessWidget {
  const _GoldStepperPlaque({
    required this.label,
    required this.value,
    required this.max,
    required this.locked,
    required this.decrementKey,
    required this.incrementKey,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int max;
  final bool locked;
  final Key decrementKey;
  final Key incrementKey;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return CoinPlaque(
      label: label,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          _MicroStepButton(
            key: decrementKey,
            icon: Icons.remove,
            enabled: !locked && value > 0,
            onTap: () => onChanged(value - 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$value',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFamily: 'RobotoSlab',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: palette.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _MicroStepButton(
            key: incrementKey,
            icon: Icons.add,
            enabled: !locked && value < max,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _MicroStepButton extends StatelessWidget {
  const _MicroStepButton({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: 26,
        child: Icon(
          icon,
          size: 16,
          color: palette.ink.withValues(alpha: enabled ? .85 : .25),
        ),
      ),
    );
  }
}

class _GoldChestPlaque extends StatelessWidget {
  const _GoldChestPlaque({
    required this.checked,
    required this.locked,
    required this.onToggle,
  });

  final bool checked;
  final bool locked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return InkWell(
      key: const ValueKey('DH_GoldChest'),
      onTap: locked ? null : onToggle,
      borderRadius: BorderRadius.circular(6),
      child: CoinPlaque(
        label: 'CHEST',
        child: SizedBox(
          height: 26,
          child: Center(
            child: Icon(
              checked ? Icons.inventory_2 : Icons.inventory_2_outlined,
              size: 18,
              color: checked
                  ? palette.accent
                  : palette.ink.withValues(alpha: .42),
            ),
          ),
        ),
      ),
    );
  }
}

/// Blocco Armi attive, Proficiency e Armatura attiva.
class _EquipmentBlock extends StatelessWidget {
  const _EquipmentBlock({
    required this.controller,
    required this.secondaryExpanded,
    required this.onToggleSecondary,
    required this.onFieldEdited,
  });

  final SheetController controller;
  final bool secondaryExpanded;
  final VoidCallback onToggleSecondary;
  final VoidCallback onFieldEdited;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final profCount = _countChecked(controller, 'DH_Proficiency_', 6);
    return SheetTray(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Proficiency + mani attive compatti (a capo automatico su schermi stretti).
          SheetFrameBox(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'PROFICIENCY ($profCount/6)',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontFamily: 'RobotoSlab',
                        fontSize: 9.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(width: 6),
                    for (var i = 1; i <= 6; i++)
                      _DhCheckbox(
                        key: ValueKey('DH_Proficiency_$i'),
                        fieldName: 'DH_Proficiency_$i',
                        dialogLabel: 'Proficiency $i',
                        controller: controller,
                        shape: _SlotShape.circle,
                        size: 22,
                        onChanged: onFieldEdited,
                      ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'MANI',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontFamily: 'RobotoSlab',
                        fontSize: 8.8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                        color: palette.ink.withValues(alpha: .78),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _HandTogglePair(
                      leftFieldName: 'DH_ActiveHand_1',
                      rightFieldName: 'DH_ActiveHand_2',
                      controller: controller,
                      onChanged: onFieldEdited,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _WeaponCard(
            caption: 'Primary Weapon',
            prefix: 'DH_PrimaryWeapon',
            controller: controller,
            onFieldEdited: onFieldEdited,
          ),
          const SizedBox(height: 6),
          if (secondaryExpanded)
            _WeaponCard(
              caption: 'Secondary Weapon',
              prefix: 'DH_SecondaryWeapon',
              controller: controller,
              onFieldEdited: onFieldEdited,
            )
          else if (!controller.locked)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('dh-add-secondary-weapon'),
                style: TextButton.styleFrom(
                  foregroundColor: palette.ink,
                  minimumSize: const Size(0, 28),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: onToggleSecondary,
                icon: const Icon(Icons.add, size: 15),
                label: const Text(
                  'Arma secondaria',
                  style: TextStyle(fontFamily: 'RobotoSlab', fontSize: 11),
                ),
              ),
            ),
          const SizedBox(height: 6),
          _ActiveArmorBlock(
            controller: controller,
            onFieldEdited: onFieldEdited,
          ),
        ],
      ),
    );
  }
}

class _WeaponCard extends StatelessWidget {
  const _WeaponCard({
    required this.caption,
    required this.prefix,
    required this.controller,
    required this.onFieldEdited,
    this.showSlotCheckboxes = false,
  });

  final String caption;
  final String prefix;
  final SheetController controller;
  final VoidCallback onFieldEdited;
  final bool showSlotCheckboxes;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final showFeature2 =
        _dhHasValue(controller, '${prefix}_Feature') ||
        _dhHasValue(controller, '${prefix}_Feature2');
    return SheetFrameBox(
      caption: caption,
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showSlotCheckboxes) ...[
            Row(
              children: [
                _DhCheckbox(
                  key: ValueKey('${prefix}_Primary'),
                  fieldName: '${prefix}_Primary',
                  dialogLabel: '$caption Primary',
                  controller: controller,
                  shape: _SlotShape.box,
                  size: 24,
                  onChanged: onFieldEdited,
                ),
                Text(
                  'PRIMARY',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: 'RobotoSlab',
                    fontSize: 8.8,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(width: 12),
                _DhCheckbox(
                  key: ValueKey('${prefix}_Secondary'),
                  fieldName: '${prefix}_Secondary',
                  dialogLabel: '$caption Secondary',
                  controller: controller,
                  shape: _SlotShape.box,
                  size: 24,
                  onChanged: onFieldEdited,
                ),
                Text(
                  'SECONDARY',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: 'RobotoSlab',
                    fontSize: 8.8,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
                const Spacer(),
                _HandTogglePair(
                  leftFieldName: '${prefix}_Hand1',
                  rightFieldName: '${prefix}_Hand2',
                  controller: controller,
                  onChanged: onFieldEdited,
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _UnderlinedField(
                  fieldName: '${prefix}_Name',
                  caption: 'Name',
                  controller: controller,
                  onChanged: onFieldEdited,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _UnderlinedField(
                  fieldName: '${prefix}_Damage',
                  caption: 'Damage & Type',
                  controller: controller,
                  onChanged: onFieldEdited,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _UnderlinedField(
                  fieldName: '${prefix}_TraitRange',
                  caption: 'Trait & Range',
                  controller: controller,
                  onChanged: onFieldEdited,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _UnderlinedField(
                  fieldName: '${prefix}_Feature',
                  caption: 'Feature',
                  controller: controller,
                  onChanged: onFieldEdited,
                ),
              ),
            ],
          ),
          if (showFeature2) ...[
            const SizedBox(height: 4),
            _UnderlinedField(
              fieldName: '${prefix}_Feature2',
              caption: 'Feature (continua)',
              controller: controller,
              onChanged: onFieldEdited,
            ),
          ],
        ],
      ),
    );
  }
}

class _HandTogglePair extends StatelessWidget {
  const _HandTogglePair({
    required this.leftFieldName,
    required this.rightFieldName,
    required this.controller,
    required this.onChanged,
  });

  final String leftFieldName;
  final String rightFieldName;
  final SheetController controller;
  final VoidCallback onChanged;

  Widget _buildHand(
    BuildContext context, {
    required String fieldName,
    required String tooltip,
    required bool flipX,
  }) {
    final palette = SheetPalette.of(context);
    final checked = _dhIsChecked(controller, fieldName);
    final locked = controller.locked;
    Widget icon = Icon(
      checked ? Icons.front_hand : Icons.front_hand_outlined,
      size: 16,
      color: checked ? palette.accent : palette.ink.withValues(alpha: .48),
    );
    if (flipX) {
      icon = Transform.flip(flipX: true, child: icon);
    }
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: ValueKey(fieldName),
        borderRadius: BorderRadius.circular(12),
        onTap: locked
            ? null
            : () {
                controller.setCheckbox(
                  fieldName,
                  checked
                      ? SheetCheckboxValue.unchecked
                      : SheetCheckboxValue.proficient,
                );
                onChanged();
              },
        child: SizedBox.square(dimension: 24, child: Center(child: icon)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHand(
          context,
          fieldName: leftFieldName,
          tooltip: 'Mano sinistra',
          flipX: true,
        ),
        _buildHand(
          context,
          fieldName: rightFieldName,
          tooltip: 'Mano destra',
          flipX: false,
        ),
      ],
    );
  }
}

class _ActiveArmorBlock extends StatelessWidget {
  const _ActiveArmorBlock({
    required this.controller,
    required this.onFieldEdited,
  });

  final SheetController controller;
  final VoidCallback onFieldEdited;

  @override
  Widget build(BuildContext context) {
    final showFeature2 =
        _dhHasValue(controller, 'DH_Armor_Feature') ||
        _dhHasValue(controller, 'DH_Armor_Feature2');
    return SheetFrameBox(
      caption: 'Active Armor',
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _UnderlinedField(
                  fieldName: 'DH_Armor_Name',
                  caption: 'Name',
                  controller: controller,
                  onChanged: onFieldEdited,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 78,
                child: _UnderlinedField(
                  fieldName: 'DH_Armor_Thresholds',
                  caption: 'Thresholds',
                  controller: controller,
                  textAlign: TextAlign.center,
                  onChanged: onFieldEdited,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 50,
                child: _UnderlinedField(
                  fieldName: 'DH_Armor_BaseScore',
                  caption: 'Score',
                  controller: controller,
                  textAlign: TextAlign.center,
                  onChanged: onFieldEdited,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _UnderlinedField(
            fieldName: 'DH_Armor_Feature',
            caption: 'Feature',
            controller: controller,
            onChanged: onFieldEdited,
          ),
          if (showFeature2) ...[
            const SizedBox(height: 4),
            _UnderlinedField(
              fieldName: 'DH_Armor_Feature2',
              caption: 'Feature (continua)',
              controller: controller,
              onChanged: onFieldEdited,
            ),
          ],
        ],
      ),
    );
  }
}

/// Inventario come singola casella multiriga sincronizzata con le 5 righe del
/// PDF (`DH_Inventory_1..5`) + eventuali righe aggiuntive (`DH_Inventory_Extra`),
/// con armi in inventario mostrate solo se presenti o aggiunte.
class _InventoryMultilineBlock extends StatefulWidget {
  const _InventoryMultilineBlock({
    required this.controller,
    required this.showWeapon1,
    required this.showWeapon2,
    required this.onRevealWeapon1,
    required this.onRevealWeapon2,
    required this.onFieldEdited,
  });

  final SheetController controller;
  final bool showWeapon1;
  final bool showWeapon2;
  final VoidCallback onRevealWeapon1;
  final VoidCallback onRevealWeapon2;
  final VoidCallback onFieldEdited;

  @override
  State<_InventoryMultilineBlock> createState() =>
      _InventoryMultilineBlockState();
}

class _InventoryMultilineBlockState extends State<_InventoryMultilineBlock> {
  TextEditingController? _textController;
  FocusNode? _focusNode;
  late String _value;
  bool _editing = false;

  String _readCombined() {
    final c = widget.controller;
    final lines = <String>[
      for (var i = 1; i <= 5; i++)
        c.valueFor('DH_Inventory_$i')?.toString() ?? '',
    ];
    final extra = c.valueFor('DH_Inventory_Extra')?.toString() ?? '';
    if (extra.isNotEmpty) {
      lines.addAll(extra.split('\n'));
    }
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines.join('\n');
  }

  void _writeCombined(String value) {
    final c = widget.controller;
    if (value.isEmpty) {
      for (var i = 1; i <= 5; i++) {
        c.setText('DH_Inventory_$i', '');
      }
      c.setText('DH_Inventory_Extra', '');
      return;
    }
    final lines = value.split('\n');
    for (var i = 0; i < 5; i++) {
      c.setText('DH_Inventory_${i + 1}', i < lines.length ? lines[i] : '');
    }
    final extra = lines.length > 5 ? lines.skip(5).join('\n') : '';
    c.setText('DH_Inventory_Extra', extra);
  }

  @override
  void initState() {
    super.initState();
    _value = _readCombined();
  }

  @override
  void didUpdateWidget(_InventoryMultilineBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing) {
      final latest = _readCombined();
      if (_value != latest) {
        _value = latest;
        final ctrl = _textController;
        if (ctrl != null && ctrl.text != latest) {
          ctrl.value = TextEditingValue(
            text: latest,
            selection: TextSelection.collapsed(offset: latest.length),
          );
        }
      }
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
    if (_textController!.text != _value) {
      _textController!.value = TextEditingValue(
        text: _value,
        selection: TextSelection.collapsed(offset: _value.length),
      );
    }
    _focusNode ??= FocusNode()..addListener(_handleFocus);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _focusNode?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final locked = widget.controller.locked;
    final textStyle = TextStyle(
      fontFamily: 'RobotoSlab',
      fontSize: 13.5,
      height: 1.38,
      color: palette.text,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetFrameBox(
          caption: 'Inventory',
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: ValueListenableBuilder<bool>(
            valueListenable: widget.controller.lockedState,
            builder: (context, isLocked, _) => GestureDetector(
              key: const ValueKey('DH_Inventory_Multiline'),
              behavior: HitTestBehavior.opaque,
              onTap: _editing || isLocked ? null : _startEditing,
              child: _editing
                  ? TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      readOnly: isLocked,
                      minLines: 3,
                      maxLines: null,
                      style: textStyle,
                      cursorColor: palette.accent,
                      onTapOutside: (_) => _focusNode?.unfocus(),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText:
                            'Scrivi oggetti e consumabili (uno per riga)…',
                        hintStyle: textStyle.copyWith(
                          color: palette.ink.withValues(alpha: .34),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      ),
                      onChanged: (value) {
                        setState(() => _value = value);
                        _writeCombined(value);
                      },
                    )
                  : Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 68),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      alignment: Alignment.topLeft,
                      child: _value.isEmpty
                          ? Text(
                              'Tocca per annotare oggetti e consumabili…',
                              style: textStyle.copyWith(
                                color: palette.ink.withValues(alpha: .36),
                              ),
                            )
                          : RichText(
                              text: _value.contains('*') || _value.contains('_')
                                  ? buildInlineMarkdownSpan(
                                      _value,
                                      textStyle,
                                      boldColor: palette.bold,
                                      italicColor: palette.italic,
                                      boldItalicColor: palette.boldItalic,
                                    )
                                  : TextSpan(text: _value, style: textStyle),
                              textDirection: Directionality.of(context),
                              textScaler: MediaQuery.textScalerOf(context),
                            ),
                    ),
            ),
          ),
        ),
        if (widget.showWeapon1) ...[
          const SizedBox(height: 8),
          _WeaponCard(
            caption: 'Inventory Weapon 1',
            prefix: 'DH_InvWeapon1',
            controller: widget.controller,
            showSlotCheckboxes: true,
            onFieldEdited: widget.onFieldEdited,
          ),
        ],
        if (widget.showWeapon2) ...[
          const SizedBox(height: 8),
          _WeaponCard(
            caption: 'Inventory Weapon 2',
            prefix: 'DH_InvWeapon2',
            controller: widget.controller,
            showSlotCheckboxes: true,
            onFieldEdited: widget.onFieldEdited,
          ),
        ],
        if (!locked && (!widget.showWeapon1 || !widget.showWeapon2))
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('dh-add-inv-weapon'),
              style: TextButton.styleFrom(
                foregroundColor: palette.ink,
                minimumSize: const Size(0, 30),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: !widget.showWeapon1
                  ? widget.onRevealWeapon1
                  : widget.onRevealWeapon2,
              icon: const Icon(Icons.add, size: 15),
              label: Text(
                !widget.showWeapon1 && !widget.showWeapon2
                    ? 'Arma in inventario'
                    : 'Seconda arma in inventario',
                style: const TextStyle(fontFamily: 'RobotoSlab', fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _focusNode
      ?..removeListener(_handleFocus)
      ..dispose();
    _textController?.dispose();
    super.dispose();
  }
}

class _RangerCompanionBlock extends StatelessWidget {
  const _RangerCompanionBlock({
    required this.controller,
    required this.extraExpRows,
    required this.onAddExpRow,
    required this.onHideEmptyExp,
    required this.trainingExpanded,
    required this.onToggleTraining,
    required this.onFieldEdited,
  });

  final SheetController controller;
  final int extraExpRows;
  final VoidCallback onAddExpRow;
  final VoidCallback onHideEmptyExp;
  final bool trainingExpanded;
  final VoidCallback onToggleTraining;
  final VoidCallback onFieldEdited;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final filledExp = <int>[];
    final emptyExp = <int>[];
    for (var i = 1; i <= 5; i++) {
      if (_dhHasValue(controller, 'DH_Comp_Exp_$i') ||
          _dhHasValue(controller, 'DH_Comp_ExpMod_$i')) {
        filledExp.add(i);
      } else {
        emptyExp.add(i);
      }
    }
    final shownEmptyExp = emptyExp.take(extraExpRows).toList();
    final visibleExp = [...filledExp, ...shownEmptyExp]..sort();
    final remainingExp = emptyExp.length - shownEmptyExp.length;

    var trainingChecked = 0;
    for (final row in _dhCompanionTrainingRows) {
      for (var i = 1; i <= row.count; i++) {
        if (_dhIsChecked(controller, 'DH_Comp_Train_${row.key}_$i')) {
          trainingChecked++;
        }
      }
    }

    return SheetTray(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetFrameBox(
            caption: 'Ranger Companion',
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _UnderlinedField(
                        fieldName: 'DH_Comp_Name',
                        caption: 'Companion Name',
                        controller: controller,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 68,
                      child: _UnderlinedField(
                        fieldName: 'DH_Comp_Evasion',
                        caption: 'Evasion',
                        controller: controller,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AspectRatio(
                  aspectRatio: 362 / 145,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: palette.ink.withValues(alpha: .35),
                      ),
                    ),
                    child: ImageFieldOverlay(
                      key: const ValueKey('DH_CompanionImage'),
                      fieldName: 'DH_CompanionImage',
                      boxSize: const Size(362, 145),
                      sheetController: controller,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SheetFrameBox(
            padding: EdgeInsets.fromLTRB(10, 7, 8, visibleExp.isEmpty ? 7 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'COMPANION EXPERIENCE (${filledExp.length}/5)',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontFamily: 'RobotoSlab',
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .6,
                          color: palette.ink,
                        ),
                      ),
                    ),
                    if (!controller.locked && shownEmptyExp.isNotEmpty)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: palette.ink.withValues(alpha: .72),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 28),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: onHideEmptyExp,
                        child: const Text(
                          'Nascondi vuote',
                          style: TextStyle(
                            fontFamily: 'RobotoSlab',
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    if (!controller.locked && remainingExp > 0)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: palette.ink,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 28),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: onAddExpRow,
                        icon: const Icon(Icons.add, size: 15),
                        label: const Text(
                          'Aggiungi',
                          style: TextStyle(
                            fontFamily: 'RobotoSlab',
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
                if (visibleExp.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  for (var idx = 0; idx < visibleExp.length; idx++) ...[
                    if (idx > 0) const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: _DhTextField(
                            key: ValueKey('DH_Comp_Exp_${visibleExp[idx]}'),
                            fieldName: 'DH_Comp_Exp_${visibleExp[idx]}',
                            dialogLabel:
                                'Companion Experience ${visibleExp[idx]}',
                            controller: controller,
                            compact: true,
                            onChanged: onFieldEdited,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 52,
                          child: _DhTextField(
                            key: ValueKey('DH_Comp_ExpMod_${visibleExp[idx]}'),
                            fieldName: 'DH_Comp_ExpMod_${visibleExp[idx]}',
                            dialogLabel:
                                'Companion Experience Mod ${visibleExp[idx]}',
                            controller: controller,
                            textAlign: TextAlign.center,
                            style: _FieldStyle.shaded,
                            hintText: '+2',
                            compact: true,
                            onChanged: onFieldEdited,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SheetFrameBox(
            caption: 'Attack, Damage & Stress',
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _UnderlinedField(
                        fieldName: 'DH_Comp_Attack',
                        caption: 'Standard Attack',
                        controller: controller,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _UnderlinedField(
                        fieldName: 'DH_Comp_Range',
                        caption: 'Range',
                        controller: controller,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final die in ['d6', 'd8', 'd10', 'd12'])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _DhCheckbox(
                            key: ValueKey('DH_Comp_Die_$die'),
                            fieldName: 'DH_Comp_Die_$die',
                            dialogLabel: 'Companion Die $die',
                            controller: controller,
                            size: 26,
                          ),
                          Text(
                            die,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  fontFamily: 'RobotoSlab',
                                  color: palette.ink,
                                ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                _VitalTrackerRow(
                  label: 'STRESS',
                  count: 6,
                  fieldPrefix: 'DH_Comp_Stress_',
                  shape: _SlotShape.box,
                  controller: controller,
                  onChanged: onFieldEdited,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _CollapsibleSheetBox(
            key: const ValueKey('dh-section-comp-training'),
            title: 'Companion Training',
            summary: trainingChecked > 0 ? '($trainingChecked)' : null,
            expanded: trainingExpanded,
            onToggle: onToggleTraining,
            child: Column(
              children: [
                for (final row in _dhCompanionTrainingRows)
                  _CheckboxOptionRow(
                    controller: controller,
                    fieldPrefix: 'DH_Comp_Train_${row.key}_',
                    count: row.count,
                    label: row.label,
                    onChanged: onFieldEdited,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassFeatureExtrasBlock extends StatelessWidget {
  const _ClassFeatureExtrasBlock({
    required this.controller,
    required this.daggerheartClass,
  });

  final SheetController controller;
  final DaggerheartClass daggerheartClass;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    switch (daggerheartClass) {
      case DaggerheartClass.blank:
        return SheetFrameBox(
          caption: 'Class Feature',
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: _DhTextField(
            key: const ValueKey('DH_ClassFeature'),
            fieldName: 'DH_ClassFeature',
            dialogLabel: 'Class Feature',
            controller: controller,
            multiline: true,
            minLines: 3,
            style: _FieldStyle.plain,
          ),
        );
      case DaggerheartClass.guardian:
        return SheetFrameBox(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'UNSTOPPABLE DIE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: 'RobotoSlab',
                    fontSize: 9.8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                    color: palette.ink,
                  ),
                ),
              ),
              SizedBox(
                width: 60,
                child: _DhTextField(
                  key: const ValueKey('DH_UnstoppableDie'),
                  fieldName: 'DH_UnstoppableDie',
                  dialogLabel: 'Unstoppable Die',
                  controller: controller,
                  textAlign: TextAlign.center,
                  style: _FieldStyle.shaded,
                  compact: true,
                  hintText: '1',
                ),
              ),
            ],
          ),
        );
      case DaggerheartClass.seraph:
        return SheetFrameBox(
          caption: 'Prayer Dice',
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
          child: Row(
            children: [
              for (var i = 1; i <= 6; i++) ...[
                if (i > 1) const SizedBox(width: 6),
                Expanded(
                  child: _DhTextField(
                    key: ValueKey('DH_PrayerDie_$i'),
                    fieldName: 'DH_PrayerDie_$i',
                    dialogLabel: 'Prayer Die $i',
                    controller: controller,
                    textAlign: TextAlign.center,
                    style: _FieldStyle.shaded,
                    hintText: 'd4',
                    compact: true,
                  ),
                ),
              ],
            ],
          ),
        );
      case DaggerheartClass.wizard:
        return SheetFrameBox(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'STRANGE PATTERNS (1–12)',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: 'RobotoSlab',
                    fontSize: 9.8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                    color: palette.ink,
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: _DhTextField(
                  key: const ValueKey('DH_StrangePatterns'),
                  fieldName: 'DH_StrangePatterns',
                  dialogLabel: 'Strange Patterns',
                  controller: controller,
                  textAlign: TextAlign.center,
                  style: _FieldStyle.shaded,
                  compact: true,
                  hintText: '–',
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _GuideQuestionsBlock extends StatelessWidget {
  const _GuideQuestionsBlock({
    required this.controller,
    required this.backgroundExpanded,
    required this.connectionsExpanded,
    required this.onToggleBackground,
    required this.onToggleConnections,
    required this.onFieldEdited,
  });

  final SheetController controller;
  final bool backgroundExpanded;
  final bool connectionsExpanded;
  final VoidCallback onToggleBackground;
  final VoidCallback onToggleConnections;
  final VoidCallback onFieldEdited;

  @override
  Widget build(BuildContext context) {
    var bgFilled = 0;
    var connFilled = 0;
    for (var i = 1; i <= 3; i++) {
      if (_dhHasValue(controller, 'DH_Background_$i')) bgFilled++;
      if (_dhHasValue(controller, 'DH_Connection_$i')) connFilled++;
    }
    return SheetTray(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          _CollapsibleSheetBox(
            key: const ValueKey('dh-section-background'),
            title: 'Background Questions',
            summary: bgFilled > 0 ? '($bgFilled/3)' : null,
            expanded: backgroundExpanded,
            onToggle: onToggleBackground,
            child: Column(
              children: [
                for (var i = 1; i <= 3; i++) ...[
                  if (i > 1) const SizedBox(height: 8),
                  _DhTextField(
                    key: ValueKey('DH_Background_$i'),
                    fieldName: 'DH_Background_$i',
                    dialogLabel: 'Background Question $i',
                    controller: controller,
                    hintText: 'Risposta background $i',
                    multiline: true,
                    minLines: 2,
                    onChanged: onFieldEdited,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          _CollapsibleSheetBox(
            key: const ValueKey('dh-section-connections'),
            title: 'Connections',
            summary: connFilled > 0 ? '($connFilled/3)' : null,
            expanded: connectionsExpanded,
            onToggle: onToggleConnections,
            child: Column(
              children: [
                for (var i = 1; i <= 3; i++) ...[
                  if (i > 1) const SizedBox(height: 8),
                  _DhTextField(
                    key: ValueKey('DH_Connection_$i'),
                    fieldName: 'DH_Connection_$i',
                    dialogLabel: 'Connection $i',
                    controller: controller,
                    hintText: 'Connessione $i',
                    multiline: true,
                    minLines: 2,
                    onChanged: onFieldEdited,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelUpTiersBlock extends StatelessWidget {
  const _LevelUpTiersBlock({
    required this.controller,
    required this.expandedTiers,
    required this.onToggleTier,
    required this.onFieldEdited,
  });

  final SheetController controller;
  final Set<int> expandedTiers;
  final ValueChanged<int> onToggleTier;
  final VoidCallback onFieldEdited;

  int _countTierChecked(
    int tier,
    List<({String key, int count, String label})> rows,
  ) {
    var total = 0;
    for (final row in rows) {
      for (var i = 1; i <= row.count; i++) {
        if (_dhIsChecked(controller, 'DH_Tier${tier}_${row.key}_$i')) {
          total++;
        }
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final t2Count = _countTierChecked(2, _dhTier2Rows);
    return SheetTray(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          _CollapsibleSheetBox(
            key: const ValueKey('dh-section-tier-2'),
            title: 'Tier 2 · Levels 2–4',
            summary: t2Count > 0 ? '($t2Count)' : null,
            expanded: expandedTiers.contains(2),
            onToggle: () => onToggleTier(2),
            child: Column(
              children: [
                for (final row in _dhTier2Rows)
                  _CheckboxOptionRow(
                    controller: controller,
                    fieldPrefix: 'DH_Tier2_${row.key}_',
                    count: row.count,
                    label: row.label,
                    onChanged: onFieldEdited,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          for (final tier in [
            (num: 3, title: 'Tier 3 · Levels 5–7'),
            (num: 4, title: 'Tier 4 · Levels 8–10'),
          ]) ...[
            if (tier.num == 4) const SizedBox(height: 6),
            Builder(
              builder: (_) {
                final count = _countTierChecked(tier.num, _dhTierHighRows);
                return _CollapsibleSheetBox(
                  key: ValueKey('dh-section-tier-${tier.num}'),
                  title: tier.title,
                  summary: count > 0 ? '($count)' : null,
                  expanded: expandedTiers.contains(tier.num),
                  onToggle: () => onToggleTier(tier.num),
                  child: Column(
                    children: [
                      for (final row in _dhTierHighRows)
                        _CheckboxOptionRow(
                          controller: controller,
                          fieldPrefix: 'DH_Tier${tier.num}_${row.key}_',
                          count: row.count,
                          label: row.label,
                          onChanged: onFieldEdited,
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckboxOptionRow extends StatelessWidget {
  const _CheckboxOptionRow({
    required this.controller,
    required this.fieldPrefix,
    required this.count,
    required this.label,
    this.onChanged,
  });

  final SheetController controller;
  final String fieldPrefix;
  final int count;
  final String label;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 1; i <= count; i++)
            _DhCheckbox(
              key: ValueKey('$fieldPrefix$i'),
              fieldName: '$fieldPrefix$i',
              dialogLabel: '$label ($i)',
              controller: controller,
              shape: _SlotShape.box,
              size: 25,
              onChanged: onChanged,
            ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'RobotoSlab',
                fontSize: 11.5,
                color: palette.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedCardsBlock extends StatelessWidget {
  const _SelectedCardsBlock({
    required this.controller,
    required this.catalog,
    required this.onManageCards,
  });

  final SheetController controller;
  final List<DaggerheartCardDef>? catalog;
  final VoidCallback onManageCards;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final selectedMap = controller.selectedCards;
    final selectedCards = <DaggerheartCardDef>[
      if (catalog != null)
        for (final card in catalog!)
          if (selectedMap.containsKey(card.id)) card,
    ];

    return SheetFrameBox(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'CARD (${selectedMap.length})',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: 'RobotoSlab',
                    fontSize: 9.8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .75,
                    color: palette.ink,
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('dh-vertical-manage-cards'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.ink,
                  side: BorderSide(color: palette.ink.withValues(alpha: .35)),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 30),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: onManageCards,
                icon: Icon(
                  selectedMap.isEmpty ? Icons.add : Icons.edit_outlined,
                  size: 15,
                ),
                label: Text(
                  selectedMap.isEmpty ? 'Seleziona card' : 'Modifica',
                  style: const TextStyle(
                    fontFamily: 'RobotoSlab',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (selectedCards.isNotEmpty) ...[
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 148,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.65,
              ),
              itemCount: selectedCards.length,
              itemBuilder: (context, index) {
                final card = selectedCards[index];
                final isVault =
                    selectedMap[card.id] == DaggerheartCardState.vault;
                return InkWell(
                  key: ValueKey('dh-vertical-card-${card.id}'),
                  onTap: () => showDaggerheartCardPreviewDialog(
                    context: context,
                    controller: controller,
                    card: card,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: palette.ink.withValues(alpha: .35),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(
                                  card.asset,
                                  fit: BoxFit.cover,
                                  cacheWidth: 260,
                                ),
                                if (isVault)
                                  Positioned(
                                    right: 4,
                                    bottom: 4,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.secondaryContainer,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        child: Text(
                                          'Vault',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Text(
                              card.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontFamily: 'RobotoSlab',
                                    fontWeight: FontWeight.w700,
                                    color: palette.ink,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
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

enum _SlotShape { circle, box, diamond, shield }

class _UnderlinedField extends StatelessWidget {
  const _UnderlinedField({
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DhTextField(
          key: ValueKey(fieldName),
          fieldName: fieldName,
          dialogLabel: caption,
          controller: controller,
          textAlign: textAlign,
          style: _FieldStyle.underline,
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
            fontSize: 8.2,
            fontWeight: FontWeight.w700,
            letterSpacing: .45,
            color: palette.ink.withValues(alpha: .72),
          ),
        ),
      ],
    );
  }
}

enum _FieldStyle { plain, underline, shaded }

class _DhTextField extends StatefulWidget {
  const _DhTextField({
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
    this.style = _FieldStyle.underline,
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
  final _FieldStyle style;
  final VoidCallback? onChanged;

  @override
  State<_DhTextField> createState() => _DhTextFieldState();
}

class _DhTextFieldState extends State<_DhTextField> {
  TextEditingController? _textController;
  FocusNode? _focusNode;
  late String _value;
  bool _editing = false;

  bool get _followsName =>
      widget.controller.character.nameFields.contains(widget.fieldName);

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
  void didUpdateWidget(_DhTextField oldWidget) {
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
          fontSize: widget.multiline ? 13.5 : 14,
          height: widget.multiline ? 1.35 : 1.15,
          color: palette.text,
        );
    final contentPadding = switch (widget.style) {
      _FieldStyle.shaded => EdgeInsets.symmetric(
        horizontal: 6,
        vertical: widget.compact ? 4 : 6,
      ),
      _FieldStyle.underline => EdgeInsets.symmetric(
        horizontal: 2,
        vertical: widget.compact ? 3 : 5,
      ),
      _FieldStyle.plain => EdgeInsets.symmetric(
        horizontal: 2,
        vertical: widget.compact ? 2 : 3,
      ),
    };
    final decoration = switch (widget.style) {
      _FieldStyle.shaded => BoxDecoration(
        color: palette.ink.withValues(alpha: isDark ? .14 : .10),
        borderRadius: BorderRadius.circular(3),
        border: _editing ? Border.all(color: palette.accent, width: 1.3) : null,
      ),
      _FieldStyle.underline => BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: _editing
                ? palette.accent
                : palette.ink.withValues(alpha: .48),
            width: _editing ? 1.6 : 1,
          ),
        ),
      ),
      _FieldStyle.plain => BoxDecoration(
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
                            ? widget.minLines * 20.0 + 10.0
                            : (widget.compact ? 25 : 32),
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

class _DhCheckbox extends StatefulWidget {
  const _DhCheckbox({
    super.key,
    required this.fieldName,
    required this.controller,
    this.dialogLabel,
    this.shape = _SlotShape.circle,
    this.size = 28,
    this.onChanged,
  });

  final String fieldName;
  final SheetController controller;
  final String? dialogLabel;
  final _SlotShape shape;
  final double size;
  final VoidCallback? onChanged;

  @override
  State<_DhCheckbox> createState() => _DhCheckboxState();
}

class _DhCheckboxState extends State<_DhCheckbox> {
  late SheetCheckboxValue _value;

  @override
  void initState() {
    super.initState();
    _value = SheetCheckboxValue.fromStored(
      widget.controller.valueFor(widget.fieldName),
    );
  }

  @override
  void didUpdateWidget(_DhCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    _value = SheetCheckboxValue.fromStored(
      widget.controller.valueFor(widget.fieldName),
    );
  }

  void _showComment() => showFieldCommentDialog(
    context: context,
    fieldName: widget.dialogLabel ?? widget.fieldName,
    initialValue: widget.controller.commentFor(widget.fieldName),
    readOnly: widget.controller.locked,
    onSave: (value) => widget.controller.setComment(widget.fieldName, value),
  );

  Widget _buildMarker(SheetPalette palette) {
    final checked = _value != SheetCheckboxValue.unchecked;
    switch (widget.shape) {
      case _SlotShape.circle:
        final outer = widget.size <= 24 ? 15.0 : 17.0;
        final inner = widget.size <= 24 ? 8.0 : 9.5;
        return Container(
          width: outer,
          height: outer,
          decoration: BoxDecoration(
            color: palette.paper,
            shape: BoxShape.circle,
            border: Border.all(color: palette.ink, width: 1.4),
          ),
          child: checked
              ? Center(
                  child: Container(
                    width: inner,
                    height: inner,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.text,
                    ),
                  ),
                )
              : null,
        );
      case _SlotShape.box:
        return Container(
          width: 18,
          height: 15,
          decoration: BoxDecoration(
            color: checked ? palette.text : palette.paper,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: palette.ink, width: 1.4),
          ),
          child: checked
              ? Icon(Icons.check, size: 11, color: palette.paper)
              : null,
        );
      case _SlotShape.diamond:
        return Transform.rotate(
          angle: 0.785398,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: checked ? palette.accent : palette.paper,
              border: Border.all(color: palette.ink, width: 1.4),
            ),
          ),
        );
      case _SlotShape.shield:
        return Icon(
          checked ? Icons.shield : Icons.shield_outlined,
          size: widget.size <= 24 ? 17 : 19,
          color: checked ? palette.text : palette.ink.withValues(alpha: .78),
        );
    }
  }

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
                  _value = _value.next(allowExpertise: false);
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
              _buildMarker(palette),
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
                          child: const SizedBox.square(dimension: 6.5),
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
