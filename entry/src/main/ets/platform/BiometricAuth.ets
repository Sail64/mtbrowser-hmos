import { userAuth } from '@kit.UserAuthenticationKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LockOutcome } from '../domain/LockPolicy';

const DOMAIN = 0x0001;
const TAG = 'Biometric';

/**
 * 认证看门狗。`on('result')` 在某些情况下不会回调（系统弹框被其它窗口顶掉、
 * 认证进程卡死、切后台时框被系统收回……），而锁屏的解除完全依赖这个 Promise。
 * Promise 悬着 ⇒ lockBusy 永远为 true ⇒ 锁屏永远解不开（没有密码兜底，等于把用户锁死）。
 * 所以必须有上限：到点就按 TIMEOUT 收敛。
 */
const AUTH_TIMEOUT_MS: number = 60000;
/** challenge 长度（字节） */
const CHALLENGE_LEN: number = 32;

/**
 * 指纹认证（平台层）。只做一件事：把 system 的 userAuth 包成「一次调用一个结果」。
 *
 * 关键约束（踩坑点）：
 * - `UserAuthInstance` **一次性**：每次认证都要重新 `getUserAuthInstance()`，
 *   复用同一个实例第二次 start() 不会回调。
 * - `getAvailableStatus()` 是**同步且会抛异常**的：未录入指纹、硬件不支持、
 *   指纹被系统锁定都会抛，不能当布尔返回值用。
 * - 认证过程中用户可能取消、超时、指纹失败：全部收敛成 LockOutcome，绝不让 Promise 悬着
 *   （悬着 = 锁屏永远解不开）。
 */
export class BiometricAuth {
  /**
   * 每次认证一个新的随机 challenge。
   * 现在没有任何地方校验 token（本地 UI 门，无服务端、无密钥派生），所以这不是"缺陷修复"；
   * 但常量 challenge 意味着一旦将来用解锁结果授权敏感动作，就是可重放的空校验。
   * 成本近乎为零，先做对。
   */
  private makeChallenge(): Uint8Array {
    try {
      const blob: cryptoFramework.DataBlob =
        cryptoFramework.createRandom().generateRandomSync(CHALLENGE_LEN);
      return blob.data;
    } catch (e) {
      // 随机源不可用也不能让解锁失败：退回固定值，但记日志
      hilog.error(DOMAIN, TAG, 'random challenge failed: %{public}s', JSON.stringify(e));
      return new Uint8Array([0]);
    }
  }

  /** 设备是否**现在就能**用指纹（已录入、未被锁定、硬件支持） */
  isAvailable(): boolean {
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, userAuth.AuthTrustLevel.ATL2);
      return true;
    } catch (e) {
      // 12500005 TYPE_NOT_SUPPORT / 未录入 / 被锁定：都按「不可用」处理，绝不假装能解锁
      hilog.info(DOMAIN, TAG, 'fingerprint unavailable: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  authenticate(title: string): Promise<LockOutcome> {
    return new Promise<LockOutcome>((resolve: (o: LockOutcome) => void) => {
      let settled: boolean = false;
      const finish = (outcome: LockOutcome): void => {
        if (settled) {
          return;
        }
        settled = true;
        resolve(outcome);
      };
      const watchdog: number = setTimeout(() => {
        hilog.error(DOMAIN, TAG, 'auth watchdog fired after %{public}d ms', AUTH_TIMEOUT_MS);
        finish(LockOutcome.TIMEOUT);
      }, AUTH_TIMEOUT_MS);
      try {
        const authParam: userAuth.AuthParam = {
          challenge: this.makeChallenge(),
          // 只认指纹：人脸在本应用里没有需求，少一种认证就少一条判断路径
          authType: [userAuth.UserAuthType.FINGERPRINT],
          authTrustLevel: userAuth.AuthTrustLevel.ATL2,
          // 指纹被系统临时锁定时直接失败返回，而不是弹一个永远过不去的框
          skipLockedBiometricAuth: true
        };
        const widgetParam: userAuth.WidgetParam = {
          title: title,
          navigationButtonText: '取消'
        };
        const instance: userAuth.UserAuthInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
        instance.on('result', {
          onResult: (result: userAuth.UserAuthResult): void => {
            clearTimeout(watchdog);
            if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
              finish(LockOutcome.SUCCESS);
            } else if (result.result === userAuth.UserAuthResultCode.CANCELED) {
              finish(LockOutcome.CANCELED);
            } else {
              hilog.warn(DOMAIN, TAG, 'fingerprint auth failed: %{public}d', result.result);
              finish(LockOutcome.FAILED);
            }
          }
        });
        instance.start();
      } catch (e) {
        clearTimeout(watchdog);
        hilog.error(DOMAIN, TAG, 'authenticate threw: %{public}s', JSON.stringify(e));
        finish(LockOutcome.UNAVAILABLE);
      }
    });
  }
}