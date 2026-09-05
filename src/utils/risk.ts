import type { RiskFactor } from '../types';

export function calculateTrustScore(factors: RiskFactor[]) {
  const earned = factors.reduce((total, factor) => total + factor.earned, 0);
  const possible = factors.reduce((total, factor) => total + factor.possible, 0);

  if (possible === 0) {
    return 0;
  }

  return Math.round((earned / possible) * 100);
}

export function factorScore(factor: RiskFactor) {
  return `${factor.earned} / ${factor.possible}`;
}

export function riskBand(score: number) {
  if (score >= 85) {
    return 'Very low';
  }

  if (score >= 70) {
    return 'Low';
  }

  if (score >= 40) {
    return 'Medium';
  }

  return 'High';
}
