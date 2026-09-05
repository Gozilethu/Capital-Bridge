import { Text, View } from 'react-native';

import { styles } from '../theme/styles';

export function CheckRow({ checked, label, value }: { checked: boolean; label: string; value: string }) {
  return (
    <View style={styles.checkRow}>
      <View style={[styles.checkMark, checked && styles.checkMarkActive]}>
        <Text style={[styles.checkSymbol, checked && styles.checkSymbolActive]}>{checked ? '+' : '-'}</Text>
      </View>
      <Text style={styles.checkLabel}>{label}</Text>
      <Text style={styles.checkValue}>{value}</Text>
    </View>
  );
}
