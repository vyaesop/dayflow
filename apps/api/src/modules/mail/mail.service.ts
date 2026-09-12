import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Resend } from 'resend';
import type { Env } from '../../config/env';

@Injectable()
export class MailService {
  private readonly logger = new Logger(MailService.name);
  private readonly resend: Resend | null;
  private readonly from: string;
  private readonly production: boolean;

  constructor(config: ConfigService<Env, true>) {
    const key = config.get('RESEND_API_KEY', { infer: true });
    this.resend = key ? new Resend(key) : null;
    this.from = config.get('MAIL_FROM', { infer: true });
    this.production = config.get('NODE_ENV', { infer: true }) === 'production';
  }

  async sendOtpEmail(to: string, code: string, purpose: 'signup' | 'login'): Promise<void> {
    const subject = purpose === 'signup' ? `${code} is your Dayflow sign-up code` : `${code} is your Dayflow login code`;
    const html = this.otpHtml(code, purpose);
    await this.send(to, subject, html, `Your Dayflow verification code is ${code}. It expires in 10 minutes.`);
  }

  async sendInviteEmail(to: string, inviterName: string, accountName: string, link: string): Promise<void> {
    const subject = `${inviterName} invited you to ${accountName} on Dayflow`;
    const html = `
      ${this.header()}
      <p style="font-size:16px;color:#1B1D29;margin:0 0 8px">Hi,</p>
      <p style="font-size:15px;color:#6B6F80;line-height:1.6;margin:0 0 24px">
        <strong style="color:#1B1D29">${escapeHtml(inviterName)}</strong> invited you to collaborate in
        <strong style="color:#1B1D29">${escapeHtml(accountName)}</strong> on Dayflow.
      </p>
      <a href="${link}" style="display:inline-block;background:#5B5BD6;color:#fff;text-decoration:none;font-size:15px;font-weight:600;padding:12px 28px;border-radius:10px">Accept invitation</a>
      ${this.footer()}`;
    await this.send(to, subject, html, `${inviterName} invited you to ${accountName} on Dayflow: ${link}`);
  }

  /** Generic one-liner for in-app notification events (mentions, assignments, replies). */
  async sendNotificationEmail(to: string, subject: string, line: string): Promise<void> {
    const html = `
      ${this.header()}
      <p style="font-size:15px;color:#1B1D29;line-height:1.6;margin:0 0 24px">${escapeHtml(line)}</p>
      <p style="font-size:13px;color:#9CA0AF;line-height:1.6;margin:0">Open Dayflow on your phone to see the details.
        You can turn these emails off under Settings &rarr; Notifications.</p>
      ${this.footer()}`;
    await this.send(to, subject, html, `${line} — open Dayflow to see the details.`);
  }

  private async send(to: string, subject: string, html: string, text: string): Promise<void> {
    if (!this.resend) {
      // Never no-op silently in production: the env schema requires the key
      // there, but if this is ever reached, failing beats "sent" lies.
      if (this.production) {
        this.logger.error(`Email not configured — dropping mail to ${to}`);
        throw new Error('Email delivery is not configured');
      }
      this.logger.log(`[dev mail] to=${to} subject="${subject}"`);
      return;
    }
    const { error } = await this.resend.emails.send({ from: this.from, to, subject, html, text });
    if (error) {
      this.logger.error(`Failed to send email to ${to}: ${error.message}`);
      throw new Error('Failed to send email');
    }
  }

  private otpHtml(code: string, purpose: 'signup' | 'login'): string {
    const title = purpose === 'signup' ? 'Confirm your email' : 'Log in to Dayflow';
    const digits = code
      .split('')
      .map(
        (d) =>
          `<td style="width:44px;height:56px;background:#F7F8FA;border:1px solid #E9EAF0;border-radius:10px;text-align:center;font-size:24px;font-weight:700;color:#1B1D29;font-family:ui-monospace,Menlo,monospace">${d}</td><td style="width:8px"></td>`,
      )
      .join('');
    return `
      ${this.header()}
      <p style="font-size:18px;font-weight:700;color:#1B1D29;margin:0 0 8px">${title}</p>
      <p style="font-size:15px;color:#6B6F80;line-height:1.6;margin:0 0 24px">Enter this verification code. It expires in 10 minutes.</p>
      <table role="presentation" cellpadding="0" cellspacing="0"><tr>${digits}</tr></table>
      <p style="font-size:13px;color:#9CA0AF;margin:24px 0 0">If you didn't request this, you can safely ignore this email.</p>
      ${this.footer()}`;
  }

  private header(): string {
    return `<div style="max-width:480px;margin:0 auto;padding:40px 24px;font-family:Inter,-apple-system,'Segoe UI',sans-serif">
      <p style="font-size:20px;font-weight:800;color:#5B5BD6;letter-spacing:-0.02em;margin:0 0 32px">dayflow</p>`;
  }

  private footer(): string {
    return `<hr style="border:none;border-top:1px solid #E9EAF0;margin:32px 0 16px">
      <p style="font-size:12px;color:#9CA0AF;margin:0">Dayflow — get your work done anytime, anywhere.</p></div>`;
  }
}

function escapeHtml(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
