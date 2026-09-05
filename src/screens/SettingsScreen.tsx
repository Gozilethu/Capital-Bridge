import { Text, View } from 'react-native';

import { GlassCard } from '../components/GlassCard';
import { InfoRow } from '../components/InfoRow';
import { StatusChip } from '../components/StatusChip';
import { styles } from '../theme/styles';
import type { OrganisationWorkspace, WorkflowState } from '../types';

export function SettingsScreen({ state, workspace }: { state: WorkflowState | null; workspace: OrganisationWorkspace }) {
  return (
    <View style={styles.page}>
      <View style={styles.pageHeader}>
        <View>
          <Text style={styles.pageKicker}>Controls</Text>
          <Text style={styles.pageTitle}>Settings</Text>
          <Text style={styles.pageSubtitle}>Organisation, integration, consent, and privacy values are loaded from Supabase.</Text>
        </View>
        <StatusChip label={workspace.role} tone="slate" />
      </View>

      <View style={styles.contentGrid}>
        <GlassCard style={styles.widePanel}>
          <Text style={styles.panelTitle}>Organisation</Text>
          <InfoRow label="Current organisation" value={workspace.organisationName} />
          <InfoRow label="Signed-in user" value={workspace.email} />
          <InfoRow label="Role" value={workspace.role} />
          <InfoRow label="Authentication" value="Supabase Auth" />
          <InfoRow label="Row level security" value="Organisation membership based" />
        </GlassCard>
        <GlassCard style={styles.sidePanel}>
          <Text style={styles.panelTitle}>Integrations</Text>
          <InfoRow label="Invoice Check" value={state?.apEnvironment?.localUrl || 'Not configured'} />
          <InfoRow label="Source" value={state?.apEnvironment?.source || 'Not configured'} />
          <InfoRow label="Storage" value="Private invoice-documents bucket" />
        </GlassCard>
      </View>
    </View>
  );
}