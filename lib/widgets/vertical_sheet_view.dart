import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/sheet_controller.dart';
import '../models/character.dart';
import '../models/sheet_field.dart';
import '../models/vertical_sheet_schema.dart';
import '../theme/sheet_palette.dart';
import 'comment_dialog.dart';
import 'image_field_overlay.dart';
import 'inline_markdown.dart';

/// Scheda personaggio ripensata in verticale per smartphone.
///
/// Tutti i campi leggono e scrivono le stesse chiavi PDF usate da [SheetPage],
/// mantenendo compatibilità completa con salvataggio, cronologia, export PDF,
/// sincronizzazione Drive, markdown inline, commenti e blocco della scheda.
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

  final _scrollController = ScrollController();
  final _scrollViewportKey = GlobalKey();
  final _activeSection = ValueNotifier<int>(0);
  late final List<GlobalKey> _sectionKeys = List.generate(
    _sectionLabels.length,
    (_) => GlobalKey(),
  );
  late final List<GlobalKey> _chipKeys = List.generate(
    _sectionLabels.length,
    (_) => GlobalKey(),
  );
  bool _jumpingToSection = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    if (_jumpingToSection || !mounted) return;
    final viewport =
        _scrollViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) return;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy + 24;
    var active = 0;
    for (var i = 0; i < _sectionKeys.length; i++) {
      final box =
          _sectionKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      if (box.localToGlobal(Offset.zero).dy <= viewportTop) {
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
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: .5,
          ),
        );
      }
    }
  }

  Future<void> _jumpToSection(int index) async {
    _activeSection.value = index;
    final target = _sectionKeys[index].currentContext;
    if (target == null) return;
    _jumpingToSection = true;
    try {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0,
      );
    } finally {
      _jumpingToSection = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Column(
      children: [
        // Spazio riservato ai controlli fluttuanti in alto (Indietro, Vista,
        // Aspetto, Blocca) così lo scorrimento non passa sotto ai pulsanti.
        SizedBox(height: widget.compactLayout ? 48 : 64),
        if (!widget.compactLayout)
          _SectionNavBar(
            labels: _sectionLabels,
            chipKeys: _chipKeys,
            activeSection: _activeSection,
            onSelect: _jumpToSection,
          ),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => SingleChildScrollView(
              key: _scrollViewportKey,
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                12,
                widget.compactLayout ? 16 : 96,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionAnchor(
                        key: _sectionKeys[0],
                        child: _IdentitySection(controller: widget.controller),
                      ),
                      const SizedBox(height: 14),
                      _SectionAnchor(
                        key: _sectionKeys[1],
                        child: _CombatSection(controller: widget.controller),
                      ),
                      const SizedBox(height: 14),
                      _SectionAnchor(
                        key: _sectionKeys[2],
                        child: _AbilitiesSection(controller: widget.controller),
                      ),
                      const SizedBox(height: 14),
                      _SectionAnchor(
                        key: _sectionKeys[3],
                        child: _SkillsSection(controller: widget.controller),
                      ),
                      const SizedBox(height: 14),
                      _SectionAnchor(
                        key: _sectionKeys[4],
                        child: _TraitsAndEquipmentSection(
                          controller: widget.controller,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionAnchor(
                        key: _sectionKeys[5],
                        child: _StorySection(controller: widget.controller),
                      ),
                      const SizedBox(height: 14),
                      _SectionAnchor(
                        key: _sectionKeys[6],
                        child: _SpellsSection(controller: widget.controller),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Tieni premuto su un campo per aggiungere o leggere una nota.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: palette.ink.withValues(alpha: .65),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _activeSection.dispose();
    super.dispose();
  }
}

class _SectionAnchor extends StatelessWidget {
  const _SectionAnchor({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
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
    return ValueListenableBuilder<int>(
      valueListenable: activeSection,
      builder: (context, selectedIndex, _) => SizedBox(
        height: 44,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Material(
                  key: chipKeys[i],
                  color: i == selectedIndex ? palette.accent : palette.paper,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: i == selectedIndex
                          ? palette.accent
                          : palette.ink.withValues(alpha: .2),
                    ),
                  ),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => onSelect(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      child: Text(
                        labels[i],
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontFamily: 'RobotoSlab',
                              fontWeight: FontWeight.w700,
                              color: i == selectedIndex
                                  ? (ThemeData.estimateBrightnessForColor(
                                              palette.accent,
                                            ) ==
                                            Brightness.dark
                                        ? Colors.white
                                        : Colors.black)
                                  : palette.text,
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
    );
  }
}

class _SheetCard extends StatelessWidget {
  const _SheetCard({this.title, this.trailing, required this.child});

  final String? title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Material(
      color: palette.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.ink.withValues(alpha: .16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title!.toUpperCase(),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontFamily: 'RobotoSlab',
                        fontWeight: FontWeight.w800,
                        letterSpacing: .6,
                        color: palette.accent,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _IdentitySection extends StatelessWidget {
  const _IdentitySection({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return _SheetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VerticalTextField(
            key: const ValueKey('CharacterName'),
            fieldName: 'CharacterName',
            label: 'Nome personaggio',
            controller: controller,
            textStyle: TextStyle(
              fontFamily: 'RobotoSlab',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < verticalIdentityFields.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _VerticalTextField(
                    key: ValueKey(verticalIdentityFields[i].field),
                    fieldName: verticalIdentityFields[i].field,
                    label: verticalIdentityFields[i].label,
                    controller: controller,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _VerticalTextField(
                    key: ValueKey(verticalIdentityFields[i + 1].field),
                    fieldName: verticalIdentityFields[i + 1].field,
                    label: verticalIdentityFields[i + 1].label,
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
}

class _CombatSection extends StatelessWidget {
  const _CombatSection({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final statStyle = TextStyle(
      fontFamily: 'RobotoSlab',
      fontSize: 22,
      fontWeight: FontWeight.w800,
      color: palette.text,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetCard(
          title: 'Combattimento',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatHighlightBox(
                      label: 'CA',
                      icon: Icons.shield_outlined,
                      accentBorder: true,
                      child: _VerticalTextField(
                        key: const ValueKey('AC'),
                        fieldName: 'AC',
                        controller: controller,
                        textAlign: TextAlign.center,
                        textStyle: statStyle,
                        compact: true,
                        showBorder: false,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatHighlightBox(
                      label: 'Iniziativa',
                      icon: Icons.bolt_outlined,
                      child: _VerticalTextField(
                        key: const ValueKey('Initiative'),
                        fieldName: 'Initiative',
                        controller: controller,
                        textAlign: TextAlign.center,
                        textStyle: statStyle,
                        compact: true,
                        showBorder: false,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatHighlightBox(
                      label: 'Velocità',
                      icon: Icons.directions_run_outlined,
                      child: _VerticalTextField(
                        key: const ValueKey('Speed'),
                        fieldName: 'Speed',
                        controller: controller,
                        textAlign: TextAlign.center,
                        textStyle: statStyle,
                        compact: true,
                        showBorder: false,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _StatHighlightBox(
                label: 'Punti ferita attuali',
                icon: Icons.favorite_border,
                child: _VerticalTextField(
                  key: const ValueKey('HPCurrent'),
                  fieldName: 'HPCurrent',
                  controller: controller,
                  textAlign: TextAlign.center,
                  textStyle: TextStyle(
                    fontFamily: 'RobotoSlab',
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                  compact: true,
                  showBorder: false,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _VerticalTextField(
                      key: const ValueKey('HPMax'),
                      fieldName: 'HPMax',
                      label: 'PF massimi',
                      controller: controller,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _VerticalTextField(
                      key: const ValueKey('HPTemp'),
                      fieldName: 'HPTemp',
                      label: 'PF temporanei',
                      controller: controller,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: palette.ink.withValues(alpha: .14)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _VerticalTextField(
                      key: const ValueKey('HD'),
                      fieldName: 'HD',
                      label: 'Dadi vita',
                      controller: controller,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _VerticalTextField(
                      key: const ValueKey('HDTotal'),
                      fieldName: 'HDTotal',
                      label: 'Totale dadi vita',
                      controller: controller,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _DeathSavesBox(controller: controller),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SheetCard(
          title: 'Attacchi e incantesimi',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(flex: 5, child: _ColumnHeaderText('Nome')),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: _ColumnHeaderText(
                        'Bonus',
                        align: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(flex: 4, child: _ColumnHeaderText('Danni / Tipo')),
                  ],
                ),
              ),
              for (var i = 0; i < verticalAttacks.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: _VerticalTextField(
                        key: ValueKey(verticalAttacks[i].nameField),
                        fieldName: verticalAttacks[i].nameField,
                        hintText: 'Arma ${i + 1}',
                        controller: controller,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: _VerticalTextField(
                        key: ValueKey(verticalAttacks[i].bonusField),
                        fieldName: verticalAttacks[i].bonusField,
                        hintText: '+0',
                        controller: controller,
                        textAlign: TextAlign.center,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 4,
                      child: _VerticalTextField(
                        key: ValueKey(verticalAttacks[i].damageField),
                        fieldName: verticalAttacks[i].damageField,
                        hintText: '1d8',
                        controller: controller,
                        compact: true,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              _VerticalTextField(
                key: const ValueKey('AttacksSpellcasting'),
                fieldName: 'AttacksSpellcasting',
                label: 'Note su attacchi e incantesimi',
                controller: controller,
                multiline: true,
                minLines: 3,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatHighlightBox extends StatelessWidget {
  const _StatHighlightBox({
    required this.label,
    required this.icon,
    required this.child,
    this.accentBorder = false,
  });

  final String label;
  final IconData icon;
  final Widget child;
  final bool accentBorder;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.workspace.withValues(alpha: .32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentBorder
              ? palette.accent.withValues(alpha: .55)
              : palette.ink.withValues(alpha: .18),
          width: accentBorder ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: palette.accent),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontFamily: 'RobotoSlab',
                      fontWeight: FontWeight.w700,
                      color: palette.ink.withValues(alpha: .78),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            child,
          ],
        ),
      ),
    );
  }
}

class _DeathSavesBox extends StatelessWidget {
  const _DeathSavesBox({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.workspace.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.ink.withValues(alpha: .15)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TIRI SALVEZZA CONTRO MORTE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontFamily: 'RobotoSlab',
                fontWeight: FontWeight.w700,
                color: palette.ink.withValues(alpha: .78),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Successi',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: palette.text),
                  ),
                ),
                for (final field in verticalDeathSaveSuccesses)
                  _VerticalCheckbox(
                    key: ValueKey(field),
                    fieldName: field,
                    controller: controller,
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Fallimenti',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: palette.text),
                  ),
                ),
                for (final field in verticalDeathSaveFailures)
                  _VerticalCheckbox(
                    key: ValueKey(field),
                    fieldName: field,
                    controller: controller,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AbilitiesSection extends StatelessWidget {
  const _AbilitiesSection({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetCard(
          title: 'Caratteristiche',
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth < 290 ? 2 : 3;
                  final rows = (verticalAbilities.length / columns).ceil();
                  return Column(
                    children: [
                      for (var r = 0; r < rows; r++) ...[
                        if (r > 0) const SizedBox(height: 8),
                        Row(
                          children: [
                            for (var c = 0; c < columns; c++) ...[
                              if (c > 0) const SizedBox(width: 8),
                              Expanded(
                                child:
                                    r * columns + c < verticalAbilities.length
                                    ? _AbilityCard(
                                        ability:
                                            verticalAbilities[r * columns + c],
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
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _VerticalTextField(
                      key: const ValueKey('ProfBonus'),
                      fieldName: 'ProfBonus',
                      label: 'Competenza',
                      controller: controller,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _VerticalTextField(
                      key: const ValueKey('Inspiration'),
                      fieldName: 'Inspiration',
                      label: 'Ispirazione',
                      controller: controller,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _VerticalTextField(
                      key: const ValueKey('Passive'),
                      fieldName: 'Passive',
                      label: 'Perc. passiva',
                      controller: controller,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SheetCard(
          title: 'Tiri salvezza',
          child: Column(
            children: [
              for (var i = 0; i < verticalAbilities.length; i += 2) ...[
                if (i > 0)
                  Divider(height: 8, color: palette.ink.withValues(alpha: .1)),
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
        ),
      ],
    );
  }
}

class _AbilityCard extends StatelessWidget {
  const _AbilityCard({required this.ability, required this.controller});

  final VerticalAbilityDef ability;
  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.workspace.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.ink.withValues(alpha: .18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        child: Column(
          children: [
            Text(
              ability.shortLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontFamily: 'RobotoSlab',
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
                color: palette.accent,
              ),
            ),
            Text(
              ability.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: palette.ink.withValues(alpha: .65),
              ),
            ),
            const SizedBox(height: 4),
            _VerticalTextField(
              key: ValueKey(ability.scoreField),
              fieldName: ability.scoreField,
              hintText: '10',
              controller: controller,
              textAlign: TextAlign.center,
              textStyle: TextStyle(
                fontFamily: 'RobotoSlab',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: palette.text,
              ),
              compact: true,
              showBorder: false,
            ),
            const SizedBox(height: 4),
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.paper,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: palette.ink.withValues(alpha: .22)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _VerticalTextField(
                  key: ValueKey(ability.modField),
                  fieldName: ability.modField,
                  hintText: '+0',
                  controller: controller,
                  textAlign: TextAlign.center,
                  textStyle: TextStyle(
                    fontFamily: 'RobotoSlab',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                  compact: true,
                  showBorder: false,
                ),
              ),
            ),
          ],
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
        _VerticalCheckbox(
          key: ValueKey(ability.saveCheckbox),
          fieldName: ability.saveCheckbox,
          controller: controller,
        ),
        SizedBox(
          width: 44,
          child: _VerticalTextField(
            key: ValueKey(ability.saveField),
            fieldName: ability.saveField,
            hintText: '+0',
            controller: controller,
            textAlign: TextAlign.center,
            compact: true,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ability.shortLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: 'RobotoSlab',
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _SkillsSection extends StatelessWidget {
  const _SkillsSection({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return _SheetCard(
      title: 'Abilità',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 9, color: palette.text),
          const SizedBox(width: 4),
          Text(
            'Comp.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.ink.withValues(alpha: .72),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.circle, size: 9, color: palette.expertise),
          const SizedBox(width: 4),
          Text(
            'Maestria',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.ink.withValues(alpha: .72),
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < verticalSkills.length; i++) ...[
            if (i > 0)
              Divider(height: 6, color: palette.ink.withValues(alpha: .1)),
            Row(
              children: [
                _VerticalCheckbox(
                  key: ValueKey(verticalSkills[i].checkboxField),
                  fieldName: verticalSkills[i].checkboxField,
                  controller: controller,
                  allowExpertise: true,
                ),
                SizedBox(
                  width: 52,
                  child: _VerticalTextField(
                    key: ValueKey(verticalSkills[i].valueField),
                    fieldName: verticalSkills[i].valueField,
                    hintText: '+0',
                    controller: controller,
                    textAlign: TextAlign.center,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    verticalSkills[i].label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'RobotoSlab',
                      color: palette.text,
                    ),
                  ),
                ),
                Text(
                  verticalSkills[i].abilityShort,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: 'RobotoSlab',
                    fontWeight: FontWeight.w700,
                    color: palette.ink.withValues(alpha: .6),
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

class _TraitsAndEquipmentSection extends StatelessWidget {
  const _TraitsAndEquipmentSection({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SheetCard(
        title: 'Privilegi e tratti',
        child: Column(
          children: [
            _VerticalTextField(
              key: const ValueKey('Features and Traits'),
              fieldName: 'Features and Traits',
              label: 'Privilegi e tratti',
              controller: controller,
              multiline: true,
              minLines: 4,
            ),
            const SizedBox(height: 10),
            _VerticalTextField(
              key: const ValueKey('Feat+Traits'),
              fieldName: 'Feat+Traits',
              label: 'Privilegi e tratti aggiuntivi',
              controller: controller,
              multiline: true,
              minLines: 3,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _SheetCard(
        title: 'Competenze e linguaggi',
        child: _VerticalTextField(
          key: const ValueKey('ProficienciesLang'),
          fieldName: 'ProficienciesLang',
          label: 'Altre competenze e linguaggi',
          controller: controller,
          multiline: true,
          minLines: 3,
        ),
      ),
      const SizedBox(height: 12),
      _SheetCard(
        title: 'Equipaggiamento e monete',
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < verticalCoins.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _VerticalTextField(
                      key: ValueKey(verticalCoins[i].field),
                      fieldName: verticalCoins[i].field,
                      label: verticalCoins[i].label,
                      controller: controller,
                      textAlign: TextAlign.center,
                      compact: true,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            _VerticalTextField(
              key: const ValueKey('Equipment'),
              fieldName: 'Equipment',
              label: 'Equipaggiamento',
              controller: controller,
              multiline: true,
              minLines: 4,
            ),
            const SizedBox(height: 10),
            _VerticalTextField(
              key: const ValueKey('Treasure'),
              fieldName: 'Treasure',
              label: 'Tesoro',
              controller: controller,
              multiline: true,
              minLines: 3,
            ),
          ],
        ),
      ),
    ],
  );
}

class _StorySection extends StatelessWidget {
  const _StorySection({required this.controller});

  final SheetController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SheetCard(
        title: 'Aspetto e ritratto',
        child: Column(
          children: [
            _FramedImageField(
              fieldName: 'CharacterAppearanceImage',
              label: 'Ritratto del personaggio',
              boxSize: const Size(172, 222),
              maxHeight: 220,
              controller: controller,
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < verticalAppearanceFields.length; i += 3) ...[
              if (i > 0) const SizedBox(height: 8),
              Row(
                children: [
                  for (var j = 0; j < 3; j++) ...[
                    if (j > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _VerticalTextField(
                        key: ValueKey(verticalAppearanceFields[i + j].field),
                        fieldName: verticalAppearanceFields[i + j].field,
                        label: verticalAppearanceFields[i + j].label,
                        controller: controller,
                        compact: true,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      _SheetCard(
        title: 'Personalità',
        child: Column(
          children: [
            for (var i = 0; i < verticalPersonalityFields.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _VerticalTextField(
                key: ValueKey(verticalPersonalityFields[i].field),
                fieldName: verticalPersonalityFields[i].field,
                label: verticalPersonalityFields[i].label,
                controller: controller,
                multiline: true,
                minLines: 2,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      _SheetCard(
        title: 'Alleati e organizzazioni',
        child: Column(
          children: [
            _VerticalTextField(
              key: const ValueKey('FactionName'),
              fieldName: 'FactionName',
              label: 'Nome organizzazione',
              controller: controller,
            ),
            const SizedBox(height: 10),
            _FramedImageField(
              fieldName: 'FactionSymbolImage',
              label: 'Simbolo organizzazione',
              boxSize: const Size(143, 114),
              maxHeight: 140,
              controller: controller,
            ),
            const SizedBox(height: 10),
            _VerticalTextField(
              key: const ValueKey('Allies'),
              fieldName: 'Allies',
              label: 'Alleati e organizzazioni',
              controller: controller,
              multiline: true,
              minLines: 3,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _SheetCard(
        title: 'Storia del personaggio',
        child: _VerticalTextField(
          key: const ValueKey('Backstory'),
          fieldName: 'Backstory',
          label: 'Storia del personaggio',
          controller: controller,
          multiline: true,
          minLines: 5,
        ),
      ),
    ],
  );
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
              color: palette.workspace.withValues(alpha: .3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.ink.withValues(alpha: .2)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: ImageFieldOverlay(
                key: ValueKey(fieldName),
                fieldName: fieldName,
                boxSize: boxSize,
                sheetController: controller,
                placeholder: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 28,
                          color: palette.ink.withValues(alpha: .45),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: palette.ink.withValues(alpha: .6),
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
      ),
    );
  }
}

class _SpellsSection extends StatefulWidget {
  const _SpellsSection({required this.controller});

  final SheetController controller;

  @override
  State<_SpellsSection> createState() => _SpellsSectionState();
}

class _SpellsSectionState extends State<_SpellsSection> {
  late final Set<int> _expandedLevels;
  final Set<int> _showAllRows = {};

  bool _levelHasData(VerticalSpellLevelDef level) {
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
      if (_slotHasData(slot)) return true;
    }
    return false;
  }

  bool _slotHasData(VerticalSpellSlotDef slot) {
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

  @override
  void initState() {
    super.initState();
    _expandedLevels = {
      for (final level in verticalSpellLevels)
        if (_levelHasData(level)) level.level,
    };
    if (_expandedLevels.isEmpty) _expandedLevels.add(0);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SheetCard(
        title: 'Incantesimi',
        child: Column(
          children: [
            _VerticalTextField(
              key: const ValueKey('Spellcasting Class 2'),
              fieldName: 'Spellcasting Class 2',
              label: 'Classe da incantatore',
              controller: widget.controller,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _VerticalTextField(
                    key: const ValueKey('SpellcastingAbility 2'),
                    fieldName: 'SpellcastingAbility 2',
                    label: 'Caratteristica',
                    controller: widget.controller,
                    textAlign: TextAlign.center,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _VerticalTextField(
                    key: const ValueKey('SpellSaveDC  2'),
                    fieldName: 'SpellSaveDC  2',
                    label: 'CD Salvezza',
                    controller: widget.controller,
                    textAlign: TextAlign.center,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _VerticalTextField(
                    key: const ValueKey('SpellAtkBonus 2'),
                    fieldName: 'SpellAtkBonus 2',
                    label: 'Bonus Attacco',
                    controller: widget.controller,
                    textAlign: TextAlign.center,
                    compact: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      for (final level in verticalSpellLevels) ...[
        const SizedBox(height: 10),
        _SpellLevelCard(
          level: level,
          controller: widget.controller,
          expanded: _expandedLevels.contains(level.level),
          showAllRows: _showAllRows.contains(level.level),
          slotHasData: _slotHasData,
          onToggleExpanded: () => setState(() {
            if (!_expandedLevels.add(level.level)) {
              _expandedLevels.remove(level.level);
            }
          }),
          onToggleShowAll: () => setState(() {
            if (!_showAllRows.add(level.level)) {
              _showAllRows.remove(level.level);
            }
          }),
          onRowEdited: () => setState(() {}),
        ),
      ],
    ],
  );
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

    return Material(
      color: palette.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.ink.withValues(alpha: .16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(14),
              bottom: expanded ? Radius.zero : const Radius.circular(14),
            ),
            onTap: onToggleExpanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(
                        child: Text(
                          '${level.level}',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontFamily: 'RobotoSlab',
                                fontWeight: FontWeight.w800,
                                color: palette.accent,
                              ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      level.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontFamily: 'RobotoSlab',
                        fontWeight: FontWeight.w700,
                        color: palette.text,
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
                          color: palette.ink.withValues(alpha: .72),
                        ),
                      ),
                    ),
                  if (filledCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.workspace.withValues(alpha: .6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text(
                            '$filledCount',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: palette.text,
                                ),
                          ),
                        ),
                      ),
                    ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: palette.ink.withValues(alpha: .7),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (level.slotsTotalField != null &&
                      level.slotsExpendedField != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _VerticalTextField(
                            key: ValueKey(level.slotsTotalField!),
                            fieldName: level.slotsTotalField!,
                            label: 'Slot totali',
                            controller: controller,
                            textAlign: TextAlign.center,
                            compact: true,
                            onChanged: onRowEdited,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _VerticalTextField(
                            key: ValueKey(level.slotsExpendedField!),
                            fieldName: level.slotsExpendedField!,
                            label: 'Slot usati',
                            controller: controller,
                            textAlign: TextAlign.center,
                            compact: true,
                            onChanged: onRowEdited,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  for (var i = 0; i < visibleSlots.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    Row(
                      children: [
                        if (visibleSlots[i].preparedCheckbox != null)
                          _VerticalCheckbox(
                            key: ValueKey(visibleSlots[i].preparedCheckbox!),
                            fieldName: visibleSlots[i].preparedCheckbox!,
                            controller: controller,
                            onChanged: onRowEdited,
                          ),
                        Expanded(
                          child: _VerticalTextField(
                            key: ValueKey(visibleSlots[i].nameField),
                            fieldName: visibleSlots[i].nameField,
                            hintText: level.level == 0
                                ? 'Nuovo trucchetto…'
                                : 'Nuovo incantesimo…',
                            controller: controller,
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
                        onPressed: onToggleShowAll,
                        child: Text(
                          showAllRows
                              ? 'Nascondi spazi vuoti'
                              : 'Mostra tutti gli spazi (${level.spells.length})',
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ColumnHeaderText extends StatelessWidget {
  const _ColumnHeaderText(this.text, {this.align = TextAlign.left});

  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Text(
      text.toUpperCase(),
      textAlign: align,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontFamily: 'RobotoSlab',
        fontWeight: FontWeight.w700,
        color: palette.ink.withValues(alpha: .65),
      ),
    );
  }
}

class _VerticalTextField extends StatefulWidget {
  const _VerticalTextField({
    super.key,
    required this.fieldName,
    required this.controller,
    this.label,
    this.hintText,
    this.multiline = false,
    this.minLines = 1,
    this.textAlign = TextAlign.left,
    this.textStyle,
    this.compact = false,
    this.showBorder = true,
    this.onChanged,
  });

  final String fieldName;
  final SheetController controller;
  final String? label;
  final String? hintText;
  final bool multiline;
  final int minLines;
  final TextAlign textAlign;
  final TextStyle? textStyle;
  final bool compact;
  final bool showBorder;
  final VoidCallback? onChanged;

  @override
  State<_VerticalTextField> createState() => _VerticalTextFieldState();
}

class _VerticalTextFieldState extends State<_VerticalTextField> {
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
  void didUpdateWidget(_VerticalTextField oldWidget) {
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
    fieldName: widget.label ?? widget.fieldName,
    initialValue: widget.controller.commentFor(widget.fieldName),
    readOnly: widget.controller.locked,
    onSave: (value) => widget.controller.setComment(widget.fieldName, value),
  );

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final effectiveStyle =
        widget.textStyle ??
        TextStyle(
          fontFamily: 'RobotoSlab',
          fontSize: widget.multiline ? 14 : 15,
          height: widget.multiline ? 1.35 : 1.2,
          color: palette.text,
        );
    final contentPadding = EdgeInsets.symmetric(
      horizontal: widget.showBorder ? 10 : 4,
      vertical: widget.compact ? 7 : 10,
    );
    return Column(
      crossAxisAlignment: widget.textAlign == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              widget.label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: widget.textAlign,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: palette.ink.withValues(alpha: .72),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: _showComment,
          onSecondaryTapUp: (_) => _showComment(),
          child: ValueListenableBuilder<bool>(
            valueListenable: widget.controller.lockedState,
            builder: (context, locked, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.showBorder
                        ? palette.workspace.withValues(
                            alpha: _editing ? .18 : .26,
                          )
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: widget.showBorder
                        ? Border.all(
                            color: _editing
                                ? palette.accent
                                : palette.ink.withValues(alpha: .2),
                            width: _editing ? 1.5 : 1,
                          )
                        : null,
                  ),
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
                              color: palette.ink.withValues(alpha: .35),
                            ),
                            contentPadding: contentPadding,
                          ),
                          onChanged: (value) {
                            setState(() => _value = value);
                            widget.controller.setText(widget.fieldName, value);
                            widget.onChanged?.call();
                          },
                        )
                      : InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: locked ? null : _startEditing,
                          child: Container(
                            width: double.infinity,
                            constraints: BoxConstraints(
                              minHeight: widget.multiline
                                  ? widget.minLines * 20.0 + 20.0
                                  : (widget.compact ? 36 : 42),
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
                                ? Text(
                                    widget.hintText ?? '—',
                                    textAlign: widget.textAlign,
                                    style: effectiveStyle.copyWith(
                                      color: palette.ink.withValues(alpha: .3),
                                    ),
                                  )
                                : RichText(
                                    text: buildInlineMarkdownSpan(
                                      _value,
                                      effectiveStyle,
                                      boldColor: palette.bold,
                                      italicColor: palette.italic,
                                      boldItalicColor: palette.boldItalic,
                                    ),
                                    textAlign: widget.textAlign,
                                    textDirection: Directionality.of(context),
                                    textScaler: MediaQuery.textScalerOf(
                                      context,
                                    ),
                                  ),
                          ),
                        ),
                ),
                Positioned(
                  top: -2,
                  right: -2,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: widget.controller.commentStateFor(
                      widget.fieldName,
                    ),
                    builder: (context, hasComment, _) => hasComment
                        ? GestureDetector(
                            onTap: _showComment,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: palette.comment,
                                  shape: BoxShape.circle,
                                ),
                                child: const SizedBox.square(dimension: 8),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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

class _VerticalCheckbox extends StatefulWidget {
  const _VerticalCheckbox({
    super.key,
    required this.fieldName,
    required this.controller,
    this.allowExpertise = false,
    this.onChanged,
  });

  final String fieldName;
  final SheetController controller;
  final bool allowExpertise;
  final VoidCallback? onChanged;

  @override
  State<_VerticalCheckbox> createState() => _VerticalCheckboxState();
}

class _VerticalCheckboxState extends State<_VerticalCheckbox> {
  late SheetCheckboxValue _value;

  @override
  void initState() {
    super.initState();
    _value = SheetCheckboxValue.fromStored(
      widget.controller.valueFor(widget.fieldName),
    );
  }

  @override
  void didUpdateWidget(_VerticalCheckbox oldWidget) {
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
          dimension: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _value == SheetCheckboxValue.expertise
                        ? palette.expertise
                        : palette.ink.withValues(alpha: .55),
                    width: _value == SheetCheckboxValue.expertise ? 2 : 1.5,
                  ),
                ),
                child: _value == SheetCheckboxValue.unchecked
                    ? null
                    : Center(
                        child: Container(
                          width: _value == SheetCheckboxValue.expertise
                              ? 10
                              : 12,
                          height: _value == SheetCheckboxValue.expertise
                              ? 10
                              : 12,
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
                top: 2,
                right: 2,
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
