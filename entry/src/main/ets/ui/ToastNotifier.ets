import { PromptAction } from '@kit.ArkUI';
import { CertReminderNotifier } from '../domain/ServerCertReminderService';

/**
 * CertReminderNotifier 的 ArkUI toast 实现（类实现而非对象字面量——ArkTS arkts-no-untyped-obj-literals）。
 */
export class ToastNotifier implements CertReminderNotifier {
  private prompt: PromptAction;

  constructor(prompt: PromptAction) {
    this.prompt = prompt;
  }

  show(message: string): void {
    this.prompt.showToast({ message: message, duration: 4000 });
  }
}
