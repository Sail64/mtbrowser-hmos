import { common } from '@kit.AbilityKit';
import { certificateManagerDialog } from '@kit.DeviceCertificateKit';
import { BusinessError } from '@kit.BasicServicesKit';
import hilog from '@ohos.hilog';
import { ClientCertSelector, ClientCertIdentityStore } from '../domain/ClientCertSelector';

const TAG = 'CertManagerSelector';
const DOMAIN = 0x0001;

/**
 * ClientCertSelector 的 DeviceCertificateKit 实现：
 * 缓存职责委托 data 层 store（经 domain 端口），系统凭据授权弹窗交互隔离在这里。
 * 对应 Android KeyChainCertSelector。
 *
 * identity = CertReference.keyUri（凭据统一资源标识），
 * 交给 ArkWeb ClientAuthenticationHandler.confirm(authUri) 完成 mTLS 握手。
 */
export class CertManagerClientCertSelector implements ClientCertSelector {
  private context: common.UIAbilityContext;
  private store: ClientCertIdentityStore;

  constructor(context: common.UIAbilityContext, store: ClientCertIdentityStore) {
    this.context = context;
    this.store = store;
  }

  cachedIdentity(host: string): string | null {
    return this.store.cachedIdentity(host);
  }

  saveIdentity(host: string, identity: string): void {
    this.store.saveIdentity(host, identity);
  }

  clearIdentity(host: string): void {
    this.store.clearIdentity(host);
  }

  chooseIdentity(host: string, port: number, callback: (identity: string | null) => void): void {
    hilog.info(DOMAIN, TAG, 'Prompting for client cert: host=%{public}s port=%{public}d', host, port);
    const request: certificateManagerDialog.AuthorizeRequest = {
      // 浏览器场景：用户凭据 + 应用凭据都列出来（对应安卓 KeyChain 全 keystore 列表）
      certTypes: [
        certificateManagerDialog.CertificateType.CREDENTIAL_USER,
        certificateManagerDialog.CertificateType.CREDENTIAL_APP
      ]
    };
    certificateManagerDialog.openAuthorizeDialog(this.context, request)
      .then((reference: certificateManagerDialog.CertReference) => {
        const keyUri = reference.keyUri;
        if (keyUri === undefined || keyUri === '') {
          hilog.warn(DOMAIN, TAG, 'Authorize dialog returned no keyUri');
          callback(null);
          return;
        }
        hilog.info(DOMAIN, TAG, 'Cert selected for host=%{public}s', host);
        this.store.saveIdentity(host, keyUri);
        callback(keyUri);
      })
      .catch((err: BusinessError) => {
        // 用户取消/授权被拒：静默回调 null（与 Android KeyChain 取消语义一致）
        hilog.warn(DOMAIN, TAG, 'openAuthorizeDialog failed: code=%{public}d msg=%{public}s',
          err.code, err.message);
        callback(null);
      });
  }
}
