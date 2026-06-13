export interface Ad {
  adId: string;
  campaignId: string;
  text: string;
  clickUrl: string;
  bannerEnabled: boolean;
}
export interface Portfolio {
  lifetimeUsd: number;
  todayUsd: number;
  ads: Ad[];
  viewThresholdSeconds: number | null;
  kill: boolean;
}
export interface Cap {
  scope: "hourly" | "daily";
  capUsd: number;
  resetSeconds: number;
}
export interface Earnings {
  cap: Cap | null;
}
export interface Tokens {
  access_token: string;
  refresh_token?: string;
}
export interface Sample {
  ts: number;          // unix ms
  lifetimeUsd: number;
  todayUsd: number;
  adId: string;
  kill: boolean;
}
