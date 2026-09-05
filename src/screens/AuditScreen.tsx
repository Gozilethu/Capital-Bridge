import { Text, View } from 'react-native';

import { GlassCard } from '../components/GlassCard';
import { StatusChip } from '../components/StatusChip';
import { styles } from '../theme/styles';
import type { WorkflowState } from '../types';

export function AuditScreen({ state }: { state: WorkflowState }) {
  return (
    <View style={styles.page}>
      <View style={styles.pageHeader}>
        <View>
          <Text style={styles.pageKicker}>Append-oriented security log</Text>
          <Text style={styles.pageTitle}>Audit Trail</Text>
          <Text style={styles.pageSubtitle}>Critical database transitions record actor, code, detail, and timestamp for investigation.</Text>
        </View>
      </View>

      <View style={styles.contentGrid}>
        <GlassCard style={styles.widePanel}>
          <Text style={styles.panelTitle}>Events</Text>
          {state.auditEvents.length === 0 && <Text style={styles.lockedText}>No audit events stored for this invoice yet.</Text>}
          {state.auditEvents.map((event) => (
            <View key={`${event.code}-${event.time}`} style={styles.auditRow}>
              <View style={[styles.auditDot, styles.auditDotActive]} />
              <View style={{ flex: 1 }}>
                <Text style={styles.auditText}>{event.code}</Text>
                <Text style={styles.tableSecondary}>{event.detail}</Text>
              </View>
              <StatusChip label={event.time} tone="slate" />
            </View>
          ))}
        </GlassCard>

        <GlassCard style={styles.sidePanel}>
          <Text style={styles.panelTitle}>Risk rules</Text>
          {state.ruleWeights.length === 0 && <Text style={styles.lockedText}>Risk rule weights will appear after risk factors are stored.</Text>}
          {state.ruleWeights.map((rule) => (
            <View key={rule.label} style={styles.ruleRow}>
              <View style={styles.ruleHeader}>
                <Text style={styles.ruleLabel}>{rule.label}</Text>
                <Text style={styles.ruleValue}>{rule.value}%</Text>
              </View>
              <View style={styles.ruleTrack}>
                <View style={[styles.ruleFill, { width: `${rule.value}%` }]} />
              </View>
            </View>
          ))}
        </GlassCard>
      </View>
    </View>
  );
}