import { Text, View } from 'react-native';

import { styles } from '../theme/styles';
import type { Tone } from '../types';
import { Badge } from './Badge';

export function ScoreRow({
  enabled,
  label,
  score,
  tone,
}: {
  enabled: boolean;
  label: string;
  score: string;
  tone: Tone;
}) {
  return (
    <View style={styles.scoreRow}>
      <Text style={styles.scoreLabel}>{label}</Text>
      <Badge label={enabled ? score : 'Pending'} tone={enabled ? tone : 'neutral'} />
    </View>
  );
}
