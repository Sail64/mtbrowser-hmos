/**
 * 自动锁定的**时间策略**（纯函数，可断言）。
 *
 * 语义边界写死在这里，避免散落在页面与能力层：
 * - 从未进过后台（`lastBackgroundAt <= 0`）**不锁**：冷启动该不该锁由调用方单独决定。
 * - 系统时间被回拨（`now < lastBackgroundAt`）**一律锁**（fail-closed）：
 *   宁可多要一次指纹，也不能因为时钟乱跳把锁定绕过。
 * - 延时 0 表示「一离开前台就锁」。
 */
export enum LockOutcome {
  SUCCESS = 0,
  CANCELED = 1,
  FAILED = 2,
  UNAVAILABLE = 3,
  /** 认证没有任何回调（系统框被外部打断/进程卡住）：必须收敛成结果，否则锁屏永远解不开 */
  TIMEOUT = 4
}

/** 允许用户手填的范围（分钟）：0 = 立即锁定，上限一天 */
export const MIN_LOCK_TIMEOUT_MIN: number = 0;
export const MAX_LOCK_TIMEOUT_MIN: number = 1440;
export const DEFAULT_LOCK_TIMEOUT_MIN: number = 5;

/**
 * 把任意输入收敛到合法取值。用户是**手填**的，必须能接住空、负数、超大值、小数：
 * - 非有限数（NaN/Infinity）→ 默认值
 * - 负数 → 默认值（"手滑输入 -5" 不等于"立即锁定"）
 * - 超过一天 → 收敛到上限，而不是静默回落成 5（用户意图要保留）
 */
export function normalizeLockTimeout(minutes: number): number {
  if (!Number.isFinite(minutes)) {
    return DEFAULT_LOCK_TIMEOUT_MIN;
  }
  const n: number = Math.trunc(minutes);
  if (n < MIN_LOCK_TIMEOUT_MIN) {
    return DEFAULT_LOCK_TIMEOUT_MIN;
  }
  if (n > MAX_LOCK_TIMEOUT_MIN) {
    return MAX_LOCK_TIMEOUT_MIN;
  }
  return n;
}

/** 回到前台时是否必须解锁 */
export function shouldLock(lastBackgroundAt: number, timeoutMinutes: number, now: number): boolean {
  if (lastBackgroundAt <= 0) {
    return false;
  }
  const elapsed: number = now - lastBackgroundAt;
  if (elapsed < 0) {
    return true;
  }
  const timeout: number = normalizeLockTimeout(timeoutMinutes);
  if (timeout === 0) {
    return true;
  }
  return elapsed >= timeout * 60000;
}

/** 设置页文案 */
export function lockTimeoutLabel(minutes: number): string {
  const v: number = normalizeLockTimeout(minutes);
  return v === 0 ? '立即锁定' : `${v} 分钟`;
}