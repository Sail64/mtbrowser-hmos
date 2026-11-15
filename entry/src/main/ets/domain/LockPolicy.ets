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
  UNAVAILABLE = 3
}

/** 可选的后台停留时长（分钟）。0 = 立即锁定 */
export const LOCK_TIMEOUT_OPTIONS: number[] = [0, 1, 5, 15, 30];
export const DEFAULT_LOCK_TIMEOUT_MIN: number = 5;

/** 把任意输入收敛到受支持的取值，脏数据回落到默认值 */
export function normalizeLockTimeout(minutes: number): number {
  for (const opt of LOCK_TIMEOUT_OPTIONS) {
    if (opt === minutes) {
      return opt;
    }
  }
  return DEFAULT_LOCK_TIMEOUT_MIN;
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