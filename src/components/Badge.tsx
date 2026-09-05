import { Text, View } from 'react-native';

import { styles } from '../theme/styles';
import type { Tone } from '../types';

export function Badge({ label, tone }: { label: string; tone: Tone }) {
  return (
    <View style={[styles.badge, badgeToneStyle(tone)]}>
      <Text style={[styles.badgeText, badgeTextToneStyle(tone)]}>{label}</Text>
    </View>
  );
}

function badgeToneStyle(tone: Tone) {
  if (tone === 'blue') {
    return styles.badgeBlue;
  }

  if (tone === 'green') {
    return styles.badgeGreen;
  }

  if (tone === 'amber') {
    return styles.badgeAmber;
  }

  if (tone === 'red') {
    return styles.badgeRed;
  }

  if (tone === 'slate') {
    return styles.badgeSlate;
  }

  return styles.badgeNeutral;
}

function badgeTextToneStyle(tone: Tone) {
  if (tone === 'blue') {
    return styles.badgeTextBlue;
  }

  if (tone === 'green') {
    return styles.badgeTextGreen;
  }

  if (tone === 'amber') {
    return styles.badgeTextAmber;
  }

  if (tone === 'red') {
    return styles.badgeTextRed;
  }

  if (tone === 'slate') {
    return styles.badgeTextSlate;
  }

  return styles.badgeTextNeutral;
}
