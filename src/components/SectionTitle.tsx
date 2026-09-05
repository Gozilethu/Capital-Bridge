import { Text, View } from 'react-native';

import { styles } from '../theme/styles';

export function SectionTitle({ action, compact, title }: { action?: string; compact?: boolean; title: string }) {
  return (
    <View style={[styles.sectionRow, compact && styles.sectionRowCompact]}>
      <Text style={[styles.sectionTitle, compact && styles.sectionTitleCompact]}>{title}</Text>
      {action && <Text style={styles.sectionAction}>{action}</Text>}
    </View>
  );
}
