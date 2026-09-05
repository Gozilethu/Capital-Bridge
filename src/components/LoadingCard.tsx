import { ActivityIndicator, Text, View } from 'react-native';

import { styles } from '../theme/styles';

export function LoadingCard({
  detail,
  title = 'Working with Supabase',
}: {
  detail: string;
  title?: string;
}) {
  return (
    <View style={styles.loadingCard}>
      <View style={styles.loadingHeader}>
        <ActivityIndicator color="#cc6b49" />
        <Text style={styles.loadingKicker}>Please wait</Text>
      </View>
      <Text style={styles.loadingTitle}>{title}</Text>
      <Text style={styles.loadingDetail}>{detail}</Text>
    </View>
  );
}