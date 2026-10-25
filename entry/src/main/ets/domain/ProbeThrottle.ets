/**
 * 后台任务限频：同一 host 每 24h 最多执行一次（如服务端证书旁路探测）。
 * 与提醒去重分离：探测无论结果如何都要记录时间，避免退化成每页一连接。
 * （与 Android domain/ProbeThrottle.kt 同源移植）
 */
export interface ProbeThrottle {
  shouldRun(host: string, now?: number): boolean;
  markRun(host: string, now?: number): void;
}
