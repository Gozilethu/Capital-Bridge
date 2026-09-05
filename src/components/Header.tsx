import { Text, View } from 'react-native';

import { styles } from '../theme/styles';
import type { Role } from '../types';
import { StatusChip } from './StatusChip';

export function Header({ role }: { role: Role }) {
  return (
    <View style={styles.header}>
      <View style={styles.brandRow}>
        <View>
          <Text style={styles.brand}>CapitalBridge</Text>
          <Text style={styles.headerSubline}>Secure invoice-to-cash workspace</Text>
        </View>
        <StatusChip label={role} tone="slate" />
      </View>
    </View>
  );
}