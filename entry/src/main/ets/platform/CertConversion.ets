import { cert } from '@kit.DeviceCertificateKit';
import { CertInfo } from '../domain/model/CertModels';
import { parseAsn1Time } from '../domain/Asn1Time';

/**
 * ArkWeb X509Cert → domain CertInfo。
 * subject：X509Cert.getSubjectName() 返回 DER 编码 DataBlob，非展示明文；
 * 展示用途暂留空，待真机接入证书框架（cert.X509Certificate / 事件 certChainData DER）后补全。
 */
export function x509CertToCertInfo(x509: cert.X509Cert): CertInfo | null {
  try {
    const notAfterMs = parseAsn1Time(x509.getNotAfterTime());
    if (notAfterMs === null) {
      return null;
    }
    return new CertInfo('', notAfterMs);
  } catch (e) {
    return null;
  }
}
