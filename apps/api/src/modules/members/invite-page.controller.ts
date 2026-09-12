import { Controller, Get, Param, Res } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import type { Response } from 'express';
import { MembersService } from './members.service';

const TOKEN_SHAPE = /^[A-Za-z0-9_-]{10,200}$/;

/**
 * Public landing page for invite links. Invite emails point here (an https
 * link works in every mail client); the page hands off to the app via the
 * `dayflow://` deep link.
 */
@ApiExcludeController()
@Controller()
export class InvitePageController {
  constructor(private readonly members: MembersService) {}

  @Get('invite/:token')
  async invitePage(@Param('token') token: string, @Res() res: Response): Promise<void> {
    const preview = TOKEN_SHAPE.test(token) ? await this.members.preview(token) : { valid: false as const };

    const body = preview.valid
      ? `
        <p class="lead"><strong>${escapeHtml(preview.inviterName ?? '')}</strong> invited you to
          <strong>${escapeHtml(preview.accountName ?? '')}</strong> on Dayflow.</p>
        <a class="button" href="dayflow:///invite/${encodeURIComponent(token)}">Open in Dayflow</a>
        <p class="hint">Opens the Dayflow app on this device. If nothing happens, install Dayflow first,
          then come back to this link on your phone.</p>`
      : `
        <p class="lead">This invitation is no longer valid.</p>
        <p class="hint">It may have expired or already been used. Ask your teammate to send a new one.</p>`;

    res
      .status(preview.valid ? 200 : 404)
      .type('html')
      .send(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Dayflow invitation</title>
<style>
  body { margin: 0; font-family: Inter, -apple-system, 'Segoe UI', sans-serif; background: #F7F8FA; color: #1B1D29;
         display: flex; min-height: 100vh; align-items: center; justify-content: center; }
  .card { background: #fff; border: 1px solid #E9EAF0; border-radius: 16px; padding: 40px 32px; max-width: 400px;
          margin: 24px; text-align: center; }
  .logo { font-size: 22px; font-weight: 800; color: #5B5BD6; letter-spacing: -0.02em; margin: 0 0 24px; }
  .lead { font-size: 16px; line-height: 1.6; color: #1B1D29; margin: 0 0 24px; }
  .button { display: inline-block; background: #5B5BD6; color: #fff; text-decoration: none; font-size: 15px;
            font-weight: 600; padding: 12px 28px; border-radius: 10px; }
  .hint { font-size: 13px; color: #9CA0AF; line-height: 1.6; margin: 24px 0 0; }
</style>
</head>
<body>
  <div class="card">
    <p class="logo">dayflow</p>
    ${body}
  </div>
</body>
</html>`);
  }
}

function escapeHtml(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
