import { webview } from '@kit.ArkWeb';
import { cert } from '@kit.DeviceCertificateKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CertInfo } from '../domain/model/CertModels';
import { CertificateSource } from '../domain/ServerCertReminderService';
import { x509CertToCertInfo } from './CertConversion';

const DOMAIN = 0x0001;
const TAG = 'CertSource';

/**
 * CertificateSource 的 ArkWeb 实现：从 WebviewController 拿当前站点证书链。
 * 注意：getCertificate() 需页面已加载（在 onPageEnd 后调用有效）。
 */
export class ArkWebCertificateSource implements CertificateSource {
  private controller: webview.WebviewController;

  constructor(controller: webview.WebviewController) {
    this.controller = controller;
  }

  async currentServerCert(): Promise<CertInfo | null> {
    try {
      const chain = await this.controller.getCertificate();
      if (chain === null || chain.length === 0) {
        return null;
      }
      const leaf: cert.X509Cert = chain[0];
      return x509CertToCertInfo(leaf);
    } catch (e) {
      // 静默返回 null 是业务要求（无证书站点很多），但必须留痕，别把异常咽掉
      hilog.warn(DOMAIN, TAG, 'getCertificate failed: %{public}s', JSON.stringify(e));
      return null;
    }
  }
}
