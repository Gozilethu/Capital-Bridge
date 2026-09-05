export function calculateFee(amountCents: number, feeBps: number) {
  return Math.floor((amountCents * feeBps + 5_000) / 10_000);
}

export function formatCurrency(cents: number) {
  const sign = cents < 0 ? '-' : '';
  const absolute = Math.abs(cents);
  const rand = Math.floor(absolute / 100);
  const centsPart = absolute % 100;
  const randText = rand.toLocaleString('en-ZA');

  if (centsPart === 0) {
    return `${sign}R${randText}`;
  }

  return `${sign}R${randText}.${String(centsPart).padStart(2, '0')}`;
}

export function formatBps(bps: number) {
  const whole = Math.floor(bps / 100);
  const remainder = bps % 100;

  if (remainder === 0) {
    return `${whole}%`;
  }

  return `${whole}.${String(remainder).padStart(2, '0').replace(/0+$/, '')}%`;
}
