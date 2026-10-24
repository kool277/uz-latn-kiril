import { Injectable, signal } from '@angular/core';

/** One short status message at a time, announced to screen readers by the app shell. */
@Injectable({ providedIn: 'root' })
export class ToastService {
  readonly message = signal('');
  private timer: ReturnType<typeof setTimeout> | undefined;

  show(message: string): void {
    this.message.set(message);
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.message.set(''), 2200);
  }
}
