import { useMemo, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { GlassCard } from '../components/GlassCard';
import { ScoreRow } from '../components/ScoreRow';
import { StatusChip } from '../components/StatusChip';
import { workflowSteps } from '../config/workflow';
import { styles } from '../theme/styles';
import type { WorkflowState } from '../types';
import { calculateTrustScore, factorScore, riskBand } from '../utils/risk';
import { hasReached, statusTone } from '../utils/workflow';

export function RiskVerificationScreen({ state }: { state: WorkflowState }) {
  const defaultTaskName = state.aiTasks[0]?.name ?? '';
  const [selectedTaskName, setSelectedTaskName] = useState(defaultTaskName);
  const selectedTask = useMemo(
    () => state.aiTasks.find((task) => task.name === selectedTaskName) ?? state.aiTasks[0] ?? null,
    [selectedTaskName, state.aiTasks],
  );
  const trustScore = state.riskFactors.length > 0 ? calculateTrustScore(state.riskFactors) : null;
  const riskReady = hasReached(state.invoice.status, 'RISK_ASSESSED') && trustScore !== null;

  return (
    <View style={styles.page}>
      <View style={styles.pageHeader}>
        <View>
          <Text style={styles.pageKicker}>Verification and intelligence</Text>
          <Text style={styles.pageTitle}>Risk & Verification</Text>
          <Text style={styles.pageSubtitle}>Extraction, ERP matching, duplicate detection, fraud checks, and scoring are stored as database evidence.</Text>
        </View>
        <StatusChip label={riskReady && trustScore !== null ? riskBand(trustScore) : 'Pending'} tone={riskReady ? 'green' : 'neutral'} />
      </View>

      <View style={styles.contentGrid}>
        <GlassCard style={styles.widePanel}>
          <Text style={styles.panelTitle}>Verification timeline</Text>
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

        <GlassCard style={styles.sidePanel}>
          <Text style={styles.panelTitle}>Transaction confidence</Text>
          <Text style={styles.amountValue}>{trustScore === null ? 'Pending' : `${trustScore} / 100`}</Text>
          <Text style={styles.tableSecondary}>{riskReady && trustScore !== null ? `${riskBand(trustScore)} risk from database factors.` : 'Risk factors will appear after assessment.'}</Text>
          {state.riskFactors.length === 0 && <Text style={styles.lockedText}>No risk factors stored yet.</Text>}
          {state.riskFactors.map((factor) => (
            <ScoreRow enabled={riskReady} key={factor.label} label={factor.label} score={factorScore(factor)} tone={factor.tone} />
          ))}
        </GlassCard>
      </View>

      <GlassCard style={styles.widePanel}>
        <Text style={styles.panelTitle}>{state.apEnvironment?.name ?? 'AI verification service'}</Text>
        <Text style={styles.modelCopy}>Integration metadata is loaded from Supabase and should stay behind the backend API.</Text>
        {state.aiTasks.length === 0 && <Text style={styles.lockedText}>No AI task metadata is stored for this workspace.</Text>}
        <View style={styles.taskList}>
          {state.aiTasks.map((task) => (
            <Pressable
              accessibilityRole="button"
              key={task.name}
              onPress={() => setSelectedTaskName(task.name)}
              style={[styles.taskCard, selectedTask?.name === task.name && styles.taskCardActive]}
            >
              <View style={styles.taskCardTop}>
                <Text style={styles.taskName}>{task.name}</Text>
                <StatusChip label={task.difficulty} tone={task.tone} />
              </View>
              <Text style={styles.taskMap}>{task.mapsTo}</Text>
            </Pressable>
          ))}
        </View>
        {selectedTask && <Text style={styles.tableSecondary}>Selected: {selectedTask.mapsTo}</Text>}
      </GlassCard>
    </View>
  );
}