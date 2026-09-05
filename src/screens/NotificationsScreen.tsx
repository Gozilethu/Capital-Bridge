import { Text, View } from 'react-native';

import { GlassCard } from '../components/GlassCard';
import { StatusChip } from '../components/StatusChip';
import { styles } from '../theme/styles';
import type { WorkflowState } from '../types';

export function NotificationsScreen({ state }: { state: WorkflowState }) {
  return (
    <View style={styles.page}>
      <View style={styles.pageHeader}>
        <View>
          <Text style={styles.pageKicker}>In-app notifications</Text>
          <Text style={styles.pageTitle}>Notifications</Text>
          <Text style={styles.pageSubtitle}>Notifications are database events for offers, funding, settlement, and manual review.</Text>
        </View>
      </View>

      <GlassCard style={styles.widePanel}>
        {state.notifications.length === 0 && <Text style={styles.lockedText}>No notifications are stored for this invoice yet.</Text>}
        {state.notifications.map((notification) => (
          <View key={notification.id} style={styles.tableRow}>
            <StatusChip label={notification.title} tone={notification.tone} />
            <Text style={[styles.tableSecondary, { flex: 1 }]}>{notification.detail}</Text>
          </View>
        ))}
      </GlassCard>
    </View>
  );
}