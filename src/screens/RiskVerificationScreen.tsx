import { Text, View } from 'react-native';

import { GlassCard } from '../components/GlassCard';
import { ScoreRow } from '../components/ScoreRow';
import { StatusChip } from '../components/StatusChip';
import { workflowSteps } from '../config/workflow';
import { styles } from '../theme/styles';
import type { WorkflowState } from '../types';
import { calculateTrustScore, factorScore, riskBand } from '../utils/risk';
import { hasReached, statusTone } from '../utils/workflow';

export function RiskVerificationScreen({ state }: { state: WorkflowState }) {
  const trustScore = state.riskFactors.length > 0 ? calculateTrustScore(state.riskFactors) : null;
  const riskReady = hasReached(state.invoice.status, 'RISK_ASSESSED') && trustScore !== null;

  return (
    <View style={styles.page}>
      <View style={styles.pageHeader}>
        <View>
          <Text style={styles.pageKicker}>Transaction evidence</Text>
          <Text style={styles.pageTitle}>Risk & Verification</Text>
          <Text style={styles.pageSubtitle}>Financing decisions are based on buyer confirmation, PO evidence, receivable uniqueness, delivery monitoring, payment behaviour, and settlement history.</Text>
        </View>
        <StatusChip label={riskReady && trustScore !== null ? riskBand(trustScore) : 'Pending'} tone={riskReady ? 'green' : 'neutral'} />
      </View>

      <View style={styles.contentGrid}>
        <GlassCard style={styles.widePanel}>
          <Text style={styles.panelTitle}>Closed-loop monitoring</Text>
          {state.transactionEvents.length === 0 && <Text style={styles.lockedText}>Monitoring events will appear after a receivable is uploaded.</Text>}
          {state.transactionEvents.map((event) => (
            <View key={event.id} style={styles.tableRow}>
              <StatusChip label={event.phase} tone={event.tone} />
              <View style={{ flex: 1 }}>
                <Text style={styles.tablePrimary}>{event.label}</Text>
                <Text style={styles.tableSecondary}>{event.detail}</Text>
                <Text style={styles.tableSecondary}>{event.time}</Text>
              </View>
              <StatusChip label={event.status} tone={event.tone} />
            </View>
          ))}
        </GlassCard>

        <GlassCard style={styles.sidePanel}>
          <Text style={styles.panelTitle}>Transaction confidence</Text>
          <Text style={styles.amountValue}>{trustScore === null ? 'Pending' : `${trustScore} / 100`}</Text>
          <Text style={styles.tableSecondary}>{riskReady && trustScore !== null ? `${riskBand(trustScore)} risk from transaction evidence.` : 'Risk factors will appear after assessment.'}</Text>
          {state.riskFactors.length === 0 && <Text style={styles.lockedText}>No risk factors stored yet.</Text>}
          {state.riskFactors.map((factor) => (
            <ScoreRow enabled={riskReady} key={factor.label} label={factor.label} score={factorScore(factor)} tone={factor.tone} />
          ))}
        </GlassCard>
      </View>

      <GlassCard style={styles.widePanel}>
        <Text style={styles.panelTitle}>Workflow evidence gates</Text>
        {workflowSteps.map((step) => (
          <View key={step.status} style={styles.tableRow}>
            <StatusChip label={hasReached(state.invoice.status, step.status) ? 'Done' : 'Queued'} tone={hasReached(state.invoice.status, step.status) ? statusTone(step.status) : 'neutral'} />
            <View style={{ flex: 1 }}>
              <Text style={styles.tablePrimary}>{step.label}</Text>
              <Text style={styles.tableSecondary}>{step.status}</Text>
            </View>
          </View>
        ))}
      </GlassCard>

      <GlassCard style={styles.widePanel}>
        <Text style={styles.panelTitle}>Supporting automation</Text>
        <Text style={styles.modelCopy}>{state.apEnvironment?.name ?? 'Invoice Check'} can assist extraction and anomaly checks, but the platform score is driven by verified transaction evidence.</Text>
        {state.aiTasks.length === 0 && <Text style={styles.lockedText}>No automation task metadata is stored for this workspace.</Text>}
        <View style={styles.taskList}>
          {state.aiTasks.map((task) => (
            <View key={task.name} style={styles.taskCard}>
              <View style={styles.taskCardTop}>
                <Text style={styles.taskName}>{task.name}</Text>
                <StatusChip label={task.difficulty} tone={task.tone} />
              </View>
              <Text style={styles.taskMap}>{task.mapsTo}</Text>
            </View>
          ))}
        </View>
      </GlassCard>
    </View>
  );
}