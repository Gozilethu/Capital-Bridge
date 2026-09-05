import { Text, View } from 'react-native';

import { styles } from '../theme/styles';
import type { Tone } from '../types';

export function StatusChip({ label, tone }: { label: string; tone: Tone }) {
  return (
    <View style={[styles.statusChip, statusToneStyle(tone)]}>
      <Text style={[styles.statusChipText, statusTextToneStyle(tone)]}>{label}</Text>
    </View>
  );
}

function statusToneStyle(tone: Tone) {
  if (tone === 'green') {
    return styles.statusChipGreen;
  }

  if (tone === 'amber') {
    return styles.statusChipAmber;
  }

  if (tone === 'red') {
    return styles.statusChipRed;
  }

  if (tone === 'blue') {
    return styles.statusChipBlue;
  }

  return styles.statusChipNeutral;
}

function statusTextToneStyle(tone: Tone) {
  if (tone === 'green') {
    return styles.statusChipTextGreen;
  }

  if (tone === 'amber') {
    return styles.statusChipTextAmber;
  }

  if (tone === 'red') {
    return styles.statusChipTextRed;
  }

  if (tone === 'blue') {
    return styles.statusChipTextBlue;
  }

  return styles.statusChipTextNeutral;
}
