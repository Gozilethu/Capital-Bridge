import { Text, View } from 'react-native';

import { styles } from '../theme/styles';

export function WorkflowStep({
  active,
  done,
  label,
  last,
}: {
  active: boolean;
  done: boolean;
  label: string;
  last: boolean;
}) {
  return (
    <View style={styles.workflowRow}>
      <View style={styles.workflowRail}>
        <View style={[styles.workflowDot, done && styles.workflowDotDone, active && styles.workflowDotActive]}>
          {done && <Text style={styles.workflowCheck}>+</Text>}
        </View>
        {!last && <View style={[styles.workflowLine, done && styles.workflowLineDone]} />}
      </View>
      <View style={styles.workflowCopy}>
        <Text style={[styles.workflowLabel, (done || active) && styles.workflowLabelActive]}>{label}</Text>
        <Text style={styles.workflowMeta}>{done ? 'Complete' : active ? 'Current' : 'Queued'}</Text>
      </View>
    </View>
  );
}
