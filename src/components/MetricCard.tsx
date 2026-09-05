import { Text, View } from 'react-native';

import { styles } from '../theme/styles';
import { formatCurrency } from '../utils/money';
import { GlassCard } from './GlassCard';

export function MetricCard({
  label,
  valueCents,
  helper,
  accent,
}: {
  label: string;
  valueCents: number;
  helper: string;
  accent?: string;
}) {
  return (
    <GlassCard style={styles.metricCard}>
      <View style={[styles.metricAccent, { backgroundColor: accent ?? '#4aa3ff' }]} />
      <Text style={styles.metricCardLabel}>{label}</Text>
      <Text style={styles.metricCardValue}>{formatCurrency(valueCents)}</Text>
      <Text style={styles.metricCardHelper}>{helper}</Text>
    </GlassCard>
  );
}
