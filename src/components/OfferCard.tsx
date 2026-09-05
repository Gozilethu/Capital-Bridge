import { Pressable, Text, View } from 'react-native';

import { styles } from '../theme/styles';
import type { Offer } from '../types';
import { calculateFee, formatBps, formatCurrency } from '../utils/money';
import { Badge } from './Badge';
import { InfoRow } from './InfoRow';
import { MiniStat } from './MiniStat';

export function OfferCard({
  accepted,
  disabled,
  offer,
  selectedAmountCents,
  onAccept,
}: {
  accepted: boolean;
  disabled: boolean;
  offer: Offer;
  selectedAmountCents: number;
  onAccept: () => void;
}) {
  const feeCents = calculateFee(selectedAmountCents, offer.feeBps);
  const netProceedsCents = selectedAmountCents - feeCents;

  return (
    <View style={[styles.offerCard, accepted && styles.offerCardAccepted, disabled && styles.cardMuted]}>
      <View style={styles.offerTopRow}>
        <View style={styles.offerCopy}>
          <Text style={styles.offerTitle}>{offer.name}</Text>
          <Text style={styles.offerPartner}>{offer.partner}</Text>
        </View>
        <View style={styles.offerBadges}>
          {offer.recommended && <Badge label="Evidence preferred" tone="blue" />}
          {accepted && <Badge label="Accepted" tone="green" />}
        </View>
      </View>

      <View style={styles.offerStats}>
        <MiniStat label="Fee" value={formatBps(offer.feeBps)} />
        <MiniStat label="Net proceeds" value={formatCurrency(netProceedsCents)} />
        <MiniStat label="Term" value={`${offer.termDays} days`} />
      </View>
      <InfoRow label="Funding speed" value={offer.speed} />
      <InfoRow label="Settlement obligation" value={formatCurrency(selectedAmountCents + feeCents)} />
      <Pressable
        accessibilityRole="button"
        disabled={disabled || accepted}
        onPress={onAccept}
        style={[styles.offerButton, (disabled || accepted) && styles.disabled]}
      >
        <Text style={styles.offerButtonText}>{accepted ? 'Offer selected' : 'Accept offer'}</Text>
      </Pressable>
    </View>
  );
}
