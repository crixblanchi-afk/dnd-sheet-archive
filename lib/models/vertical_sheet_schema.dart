/// Struttura logica dei campi della scheda D&D 5e per la vista verticale.
///
/// Ogni chiave corrisponde esattamente al nome del campo in
/// `assets/sheet/fields.json` (inclusi gli spazi finali ereditati dal PDF
/// originale), così le modifiche nella vista verticale e nelle viste PDF
/// leggono e scrivono gli stessi dati.
library;

class VerticalAbilityDef {
  const VerticalAbilityDef({
    required this.label,
    required this.shortLabel,
    required this.scoreField,
    required this.modField,
    required this.saveField,
    required this.saveCheckbox,
  });

  final String label;
  final String shortLabel;
  final String scoreField;
  final String modField;
  final String saveField;
  final String saveCheckbox;
}

class VerticalSkillDef {
  const VerticalSkillDef({
    required this.label,
    required this.abilityShort,
    required this.valueField,
    required this.checkboxField,
  });

  final String label;
  final String abilityShort;
  final String valueField;
  final String checkboxField;
}

class VerticalAttackDef {
  const VerticalAttackDef({
    required this.nameField,
    required this.bonusField,
    required this.damageField,
  });

  final String nameField;
  final String bonusField;
  final String damageField;
}

class VerticalCoinDef {
  const VerticalCoinDef({required this.label, required this.field});

  final String label;
  final String field;
}

class VerticalSpellSlotDef {
  const VerticalSpellSlotDef({required this.nameField, this.preparedCheckbox});

  final String nameField;
  final String? preparedCheckbox;
}

class VerticalSpellLevelDef {
  const VerticalSpellLevelDef({
    required this.level,
    required this.title,
    this.slotsTotalField,
    this.slotsExpendedField,
    required this.spells,
  });

  final int level;
  final String title;
  final String? slotsTotalField;
  final String? slotsExpendedField;
  final List<VerticalSpellSlotDef> spells;
}

const verticalIdentityFields = [
  (label: 'Classe e livello', field: 'ClassLevel'),
  (label: 'Razza', field: 'Race '),
  (label: 'Background', field: 'Background'),
  (label: 'Allineamento', field: 'Alignment'),
  (label: 'Punti esperienza', field: 'XP'),
  (label: 'Giocatore', field: 'PlayerName'),
];

const verticalAbilities = [
  VerticalAbilityDef(
    label: 'Forza',
    shortLabel: 'FOR',
    scoreField: 'STR',
    modField: 'STRmod',
    saveField: 'ST Strength',
    saveCheckbox: 'Check Box 11',
  ),
  VerticalAbilityDef(
    label: 'Destrezza',
    shortLabel: 'DES',
    scoreField: 'DEX',
    modField: 'DEXmod ',
    saveField: 'ST Dexterity',
    saveCheckbox: 'Check Box 18',
  ),
  VerticalAbilityDef(
    label: 'Costituzione',
    shortLabel: 'COS',
    scoreField: 'CON',
    modField: 'CONmod',
    saveField: 'ST Constitution',
    saveCheckbox: 'Check Box 19',
  ),
  VerticalAbilityDef(
    label: 'Intelligenza',
    shortLabel: 'INT',
    scoreField: 'INT',
    modField: 'INTmod',
    saveField: 'ST Intelligence',
    saveCheckbox: 'Check Box 20',
  ),
  VerticalAbilityDef(
    label: 'Saggezza',
    shortLabel: 'SAG',
    scoreField: 'WIS',
    modField: 'WISmod',
    saveField: 'ST Wisdom',
    saveCheckbox: 'Check Box 21',
  ),
  VerticalAbilityDef(
    label: 'Carisma',
    shortLabel: 'CAR',
    scoreField: 'CHA',
    modField: 'CHamod',
    saveField: 'ST Charisma',
    saveCheckbox: 'Check Box 22',
  ),
];

const verticalDeathSaveSuccesses = [
  'Check Box 12',
  'Check Box 13',
  'Check Box 14',
];

const verticalDeathSaveFailures = [
  'Check Box 15',
  'Check Box 16',
  'Check Box 17',
];

const verticalAttacks = [
  VerticalAttackDef(
    nameField: 'Wpn Name',
    bonusField: 'Wpn1 AtkBonus',
    damageField: 'Wpn1 Damage',
  ),
  VerticalAttackDef(
    nameField: 'Wpn Name 2',
    bonusField: 'Wpn2 AtkBonus ',
    damageField: 'Wpn2 Damage ',
  ),
  VerticalAttackDef(
    nameField: 'Wpn Name 3',
    bonusField: 'Wpn3 AtkBonus  ',
    damageField: 'Wpn3 Damage ',
  ),
];

/// Tutte le 18 abilità in ordine alfabetico italiano.
const verticalSkills = [
  VerticalSkillDef(
    label: 'Acrobazia',
    abilityShort: 'DES',
    valueField: 'Acrobatics',
    checkboxField: 'Check Box 23',
  ),
  VerticalSkillDef(
    label: 'Addestrare Animali',
    abilityShort: 'SAG',
    valueField: 'Animal',
    checkboxField: 'Check Box 24',
  ),
  VerticalSkillDef(
    label: 'Arcano',
    abilityShort: 'INT',
    valueField: 'Arcana',
    checkboxField: 'Check Box 25',
  ),
  VerticalSkillDef(
    label: 'Atletica',
    abilityShort: 'FOR',
    valueField: 'Athletics',
    checkboxField: 'Check Box 26',
  ),
  VerticalSkillDef(
    label: 'Furtività',
    abilityShort: 'DES',
    valueField: 'Stealth ',
    checkboxField: 'Check Box 39',
  ),
  VerticalSkillDef(
    label: 'Indagare',
    abilityShort: 'INT',
    valueField: 'Investigation ',
    checkboxField: 'Check Box 31',
  ),
  VerticalSkillDef(
    label: 'Inganno',
    abilityShort: 'CAR',
    valueField: 'Deception ',
    checkboxField: 'Check Box 27',
  ),
  VerticalSkillDef(
    label: 'Intimidire',
    abilityShort: 'CAR',
    valueField: 'Intimidation',
    checkboxField: 'Check Box 30',
  ),
  VerticalSkillDef(
    label: 'Intrattenere',
    abilityShort: 'CAR',
    valueField: 'Performance',
    checkboxField: 'Check Box 35',
  ),
  VerticalSkillDef(
    label: 'Intuizione',
    abilityShort: 'SAG',
    valueField: 'Insight',
    checkboxField: 'Check Box 29',
  ),
  VerticalSkillDef(
    label: 'Medicina',
    abilityShort: 'SAG',
    valueField: 'Medicine',
    checkboxField: 'Check Box 32',
  ),
  VerticalSkillDef(
    label: 'Natura',
    abilityShort: 'INT',
    valueField: 'Nature',
    checkboxField: 'Check Box 33',
  ),
  VerticalSkillDef(
    label: 'Percezione',
    abilityShort: 'SAG',
    valueField: 'Perception ',
    checkboxField: 'Check Box 34',
  ),
  VerticalSkillDef(
    label: 'Persuasione',
    abilityShort: 'CAR',
    valueField: 'Persuasion',
    checkboxField: 'Check Box 36',
  ),
  VerticalSkillDef(
    label: 'Rapidità di Mano',
    abilityShort: 'DES',
    valueField: 'SleightofHand',
    checkboxField: 'Check Box 38',
  ),
  VerticalSkillDef(
    label: 'Religione',
    abilityShort: 'INT',
    valueField: 'Religion',
    checkboxField: 'Check Box 37',
  ),
  VerticalSkillDef(
    label: 'Sopravvivenza',
    abilityShort: 'SAG',
    valueField: 'Survival',
    checkboxField: 'Check Box 40',
  ),
  VerticalSkillDef(
    label: 'Storia',
    abilityShort: 'INT',
    valueField: 'History ',
    checkboxField: 'Check Box 28',
  ),
];

const verticalCoins = [
  VerticalCoinDef(label: 'MR', field: 'CP'),
  VerticalCoinDef(label: 'MA', field: 'SP'),
  VerticalCoinDef(label: 'ME', field: 'EP'),
  VerticalCoinDef(label: 'MO', field: 'GP'),
  VerticalCoinDef(label: 'MP', field: 'PP'),
];

const verticalAppearanceFields = [
  (label: 'Età', field: 'Age'),
  (label: 'Altezza', field: 'Height'),
  (label: 'Peso', field: 'Weight'),
  (label: 'Occhi', field: 'Eyes'),
  (label: 'Carnagione', field: 'Skin'),
  (label: 'Capelli', field: 'Hair'),
];

const verticalPersonalityFields = [
  (label: 'Tratti caratteriali', field: 'PersonalityTraits '),
  (label: 'Ideali', field: 'Ideals'),
  (label: 'Legami', field: 'Bonds'),
  (label: 'Difetti', field: 'Flaws'),
];

const verticalSpellLevels = [
  VerticalSpellLevelDef(
    level: 0,
    title: 'Trucchetti',
    spells: [
      VerticalSpellSlotDef(nameField: 'Spells 1014'),
      VerticalSpellSlotDef(nameField: 'Spells 1016'),
      VerticalSpellSlotDef(nameField: 'Spells 1017'),
      VerticalSpellSlotDef(nameField: 'Spells 1018'),
      VerticalSpellSlotDef(nameField: 'Spells 1019'),
      VerticalSpellSlotDef(nameField: 'Spells 1020'),
      VerticalSpellSlotDef(nameField: 'Spells 1021'),
      VerticalSpellSlotDef(nameField: 'Spells 1022'),
    ],
  ),
  VerticalSpellLevelDef(
    level: 1,
    title: 'Livello 1',
    slotsTotalField: 'SlotsTotal 19',
    slotsExpendedField: 'SlotsRemaining 19',
    spells: [
      VerticalSpellSlotDef(
        nameField: 'Spells 1015',
        preparedCheckbox: 'Check Box 251',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1023',
        preparedCheckbox: 'Check Box 309',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1024',
        preparedCheckbox: 'Check Box 3010',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1025',
        preparedCheckbox: 'Check Box 3011',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1026',
        preparedCheckbox: 'Check Box 3012',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1027',
        preparedCheckbox: 'Check Box 3013',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1028',
        preparedCheckbox: 'Check Box 3014',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1029',
        preparedCheckbox: 'Check Box 3015',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1030',
        preparedCheckbox: 'Check Box 3016',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1031',
        preparedCheckbox: 'Check Box 3017',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1032',
        preparedCheckbox: 'Check Box 3018',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1033',
        preparedCheckbox: 'Check Box 3019',
      ),
    ],
  ),
  VerticalSpellLevelDef(
    level: 2,
    title: 'Livello 2',
    slotsTotalField: 'SlotsTotal 20',
    slotsExpendedField: 'SlotsRemaining 20',
    spells: [
      VerticalSpellSlotDef(
        nameField: 'Spells 1046',
        preparedCheckbox: 'Check Box 313',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1034',
        preparedCheckbox: 'Check Box 310',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1035',
        preparedCheckbox: 'Check Box 3020',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1036',
        preparedCheckbox: 'Check Box 3021',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1037',
        preparedCheckbox: 'Check Box 3022',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1038',
        preparedCheckbox: 'Check Box 3023',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1039',
        preparedCheckbox: 'Check Box 3024',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1040',
        preparedCheckbox: 'Check Box 3025',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1041',
        preparedCheckbox: 'Check Box 3026',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1042',
        preparedCheckbox: 'Check Box 3027',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1043',
        preparedCheckbox: 'Check Box 3028',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1044',
        preparedCheckbox: 'Check Box 3029',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1045',
        preparedCheckbox: 'Check Box 3030',
      ),
    ],
  ),
  VerticalSpellLevelDef(
    level: 3,
    title: 'Livello 3',
    slotsTotalField: 'SlotsTotal 21',
    slotsExpendedField: 'SlotsRemaining 21',
    spells: [
      VerticalSpellSlotDef(
        nameField: 'Spells 1048',
        preparedCheckbox: 'Check Box 315',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1047',
        preparedCheckbox: 'Check Box 314',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1049',
        preparedCheckbox: 'Check Box 3031',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1050',
        preparedCheckbox: 'Check Box 3032',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1051',
        preparedCheckbox: 'Check Box 3033',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1052',
        preparedCheckbox: 'Check Box 3034',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1053',
        preparedCheckbox: 'Check Box 3035',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1054',
        preparedCheckbox: 'Check Box 3036',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1055',
        preparedCheckbox: 'Check Box 3037',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1056',
        preparedCheckbox: 'Check Box 3038',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1057',
        preparedCheckbox: 'Check Box 3039',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1058',
        preparedCheckbox: 'Check Box 3040',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1059',
        preparedCheckbox: 'Check Box 3041',
      ),
    ],
  ),
  VerticalSpellLevelDef(
    level: 4,
    title: 'Livello 4',
    slotsTotalField: 'SlotsTotal 22',
    slotsExpendedField: 'SlotsRemaining 22',
    spells: [
      VerticalSpellSlotDef(
        nameField: 'Spells 1061',
        preparedCheckbox: 'Check Box 317',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1060',
        preparedCheckbox: 'Check Box 316',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1062',
        preparedCheckbox: 'Check Box 3042',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1063',
        preparedCheckbox: 'Check Box 3043',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1064',
        preparedCheckbox: 'Check Box 3044',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1065',
        preparedCheckbox: 'Check Box 3045',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1066',
        preparedCheckbox: 'Check Box 3046',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1067',
        preparedCheckbox: 'Check Box 3047',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1068',
        preparedCheckbox: 'Check Box 3048',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1069',
        preparedCheckbox: 'Check Box 3049',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1070',
        preparedCheckbox: 'Check Box 3050',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1071',
        preparedCheckbox: 'Check Box 3051',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1072',
        preparedCheckbox: 'Check Box 3052',
      ),
    ],
  ),
  VerticalSpellLevelDef(
    level: 5,
    title: 'Livello 5',
    slotsTotalField: 'SlotsTotal 23',
    slotsExpendedField: 'SlotsRemaining 23',
    spells: [
      VerticalSpellSlotDef(
        nameField: 'Spells 1074',
        preparedCheckbox: 'Check Box 319',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1073',
        preparedCheckbox: 'Check Box 318',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1075',
        preparedCheckbox: 'Check Box 3053',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1076',
        preparedCheckbox: 'Check Box 3054',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1077',
        preparedCheckbox: 'Check Box 3055',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1078',
        preparedCheckbox: 'Check Box 3056',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1079',
        preparedCheckbox: 'Check Box 3057',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1080',
        preparedCheckbox: 'Check Box 3058',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1081',
        preparedCheckbox: 'Check Box 3059',
      ),
    ],
  ),
  VerticalSpellLevelDef(
    level: 6,
    title: 'Livello 6',
    slotsTotalField: 'SlotsTotal 24',
    slotsExpendedField: 'SlotsRemaining 24',
    spells: [
      VerticalSpellSlotDef(
        nameField: 'Spells 1083',
        preparedCheckbox: 'Check Box 321',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1082',
        preparedCheckbox: 'Check Box 320',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1084',
        preparedCheckbox: 'Check Box 3060',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1085',
        preparedCheckbox: 'Check Box 3061',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1086',
        preparedCheckbox: 'Check Box 3062',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1087',
        preparedCheckbox: 'Check Box 3063',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1088',
        preparedCheckbox: 'Check Box 3064',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1089',
        preparedCheckbox: 'Check Box 3065',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1090',
        preparedCheckbox: 'Check Box 3066',
      ),
    ],
  ),
  VerticalSpellLevelDef(
    level: 7,
    title: 'Livello 7',
    slotsTotalField: 'SlotsTotal 25',
    slotsExpendedField: 'SlotsRemaining 25',
    spells: [
      VerticalSpellSlotDef(
        nameField: 'Spells 1092',
        preparedCheckbox: 'Check Box 323',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1091',
        preparedCheckbox: 'Check Box 322',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1093',
        preparedCheckbox: 'Check Box 3067',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1094',
        preparedCheckbox: 'Check Box 3068',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1095',
        preparedCheckbox: 'Check Box 3069',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1096',
        preparedCheckbox: 'Check Box 3070',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1097',
        preparedCheckbox: 'Check Box 3071',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1098',
        preparedCheckbox: 'Check Box 3072',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 1099',
        preparedCheckbox: 'Check Box 3073',
      ),
    ],
  ),
  VerticalSpellLevelDef(
    level: 8,
    title: 'Livello 8',
    slotsTotalField: 'SlotsTotal 26',
    slotsExpendedField: 'SlotsRemaining 26',
    spells: [
      VerticalSpellSlotDef(
        nameField: 'Spells 10101',
        preparedCheckbox: 'Check Box 325',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 10100',
        preparedCheckbox: 'Check Box 324',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 10102',
        preparedCheckbox: 'Check Box 3074',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 10103',
        preparedCheckbox: 'Check Box 3075',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 10104',
        preparedCheckbox: 'Check Box 3076',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 10105',
        preparedCheckbox: 'Check Box 3077',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 10106',
        preparedCheckbox: 'Check Box 3078',
      ),
    ],
  ),
  VerticalSpellLevelDef(
    level: 9,
    title: 'Livello 9',
    slotsTotalField: 'SlotsTotal 27',
    slotsExpendedField: 'SlotsRemaining 27',
    spells: [
      VerticalSpellSlotDef(
        nameField: 'Spells 10108',
        preparedCheckbox: 'Check Box 327',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 10107',
        preparedCheckbox: 'Check Box 326',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 10109',
        preparedCheckbox: 'Check Box 3079',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 101010',
        preparedCheckbox: 'Check Box 3080',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 101011',
        preparedCheckbox: 'Check Box 3081',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 101012',
        preparedCheckbox: 'Check Box 3082',
      ),
      VerticalSpellSlotDef(
        nameField: 'Spells 101013',
        preparedCheckbox: 'Check Box 3083',
      ),
    ],
  ),
];

/// Elenco completo dei nomi di campo mappati nella vista verticale.
///
/// Esclude `CharacterName 2` perché è sincronizzato con `CharacterName` dal
/// controller del personaggio.
List<String> allVerticalSheetFieldNames() => [
  'CharacterName',
  for (final item in verticalIdentityFields) item.field,
  'AC',
  'Initiative',
  'Speed',
  'HPCurrent',
  'HPMax',
  'HPTemp',
  'HD',
  'HDTotal',
  ...verticalDeathSaveSuccesses,
  ...verticalDeathSaveFailures,
  for (final attack in verticalAttacks) ...[
    attack.nameField,
    attack.bonusField,
    attack.damageField,
  ],
  'AttacksSpellcasting',
  for (final ability in verticalAbilities) ...[
    ability.scoreField,
    ability.modField,
    ability.saveField,
    ability.saveCheckbox,
  ],
  'ProfBonus',
  'Inspiration',
  'Passive',
  for (final skill in verticalSkills) ...[
    skill.valueField,
    skill.checkboxField,
  ],
  'Features and Traits',
  'Feat+Traits',
  'ProficienciesLang',
  for (final coin in verticalCoins) coin.field,
  'Equipment',
  'Treasure',
  for (final item in verticalAppearanceFields) item.field,
  for (final item in verticalPersonalityFields) item.field,
  'FactionName',
  'Allies',
  'Backstory',
  'Spellcasting Class 2',
  'SpellcastingAbility 2',
  'SpellSaveDC  2',
  'SpellAtkBonus 2',
  for (final level in verticalSpellLevels) ...[
    if (level.slotsTotalField != null) level.slotsTotalField!,
    if (level.slotsExpendedField != null) level.slotsExpendedField!,
    for (final spell in level.spells) ...[
      spell.nameField,
      if (spell.preparedCheckbox != null) spell.preparedCheckbox!,
    ],
  ],
];
