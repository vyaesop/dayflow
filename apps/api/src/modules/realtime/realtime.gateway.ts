import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { IncomingMessage } from 'node:http';
import type { Server as HttpServer } from 'node:http';
import { WebSocket, WebSocketServer } from 'ws';
import type { AccessTokenPayload } from '../../common/auth-context';
import type { Env } from '../../config/env';

/** Events pushed to clients watching a board. */
export type BoardEvent =
  | { type: 'item.created'; boardId: string; groupId: string; item: unknown }
  | { type: 'item.updated'; boardId: string; itemId: string; patch: unknown }
  | { type: 'item.moved'; boardId: string; itemId: string; groupId: string }
  | { type: 'item.deleted'; boardId: string; itemId: string }
  | { type: 'cell.changed'; boardId: string; itemId: string; columnId: string; value: unknown }
  | { type: 'group.created'; boardId: string; group: unknown }
  | { type: 'group.updated'; boardId: string; groupId: string; patch: unknown }
  | { type: 'group.deleted'; boardId: string; groupId: string }
  | { type: 'column.created'; boardId: string; column: unknown }
  | { type: 'column.updated'; boardId: string; columnId: string; patch: unknown }
  | { type: 'column.deleted'; boardId: string; columnId: string }
  | { type: 'board.updated'; boardId: string; patch: unknown };

interface Client {
  socket: WebSocket;
  userId: string;
  accountId: string;
  /** Boards this connection is subscribed to. */
  boards: Set<string>;
  alive: boolean;
}

/**
 * Board fan-out over a raw `ws` server mounted at `/v1/realtime`.
 *
 * The access token is passed as a query parameter because browsers cannot set
 * headers on a WebSocket handshake. Clients then send `{action:'subscribe',
 * boardId}` frames; the server pushes board events back.
 *
 * Fan-out is in-process: with more than one API instance this needs a shared
 * bus (Redis pub/sub) so events reach clients on other nodes.
 */
@Injectable()
export class RealtimeGateway implements OnModuleDestroy {
  private readonly logger = new Logger(RealtimeGateway.name);
  private readonly clients = new Set<Client>();
  private server: WebSocketServer | null = null;
  private heartbeat: NodeJS.Timeout | null = null;

  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService<Env, true>,
  ) {}

  /** Attaches the WebSocket server to the running HTTP server. */
  attach(httpServer: HttpServer): void {
    if (this.server) return;

    this.server = new WebSocketServer({ noServer: true });

    httpServer.on('upgrade', (request, socket, head) => {
      const { pathname, searchParams } = new URL(request.url ?? '/', 'http://localhost');
      if (pathname !== '/v1/realtime') return; // let other upgrade handlers try

      void this.authenticate(searchParams.get('token')).then((auth) => {
        if (!auth) {
          socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
          socket.destroy();
          return;
        }
        this.server!.handleUpgrade(request, socket, head, (ws) => {
          this.register(ws, auth, request);
        });
      });
    });

    // Drop connections that stop answering pings.
    this.heartbeat = setInterval(() => {
      for (const client of this.clients) {
        if (!client.alive) {
          client.socket.terminate();
          this.clients.delete(client);
          continue;
        }
        client.alive = false;
        client.socket.ping();
      }
    }, 30_000);

    this.logger.log('Realtime gateway listening on /v1/realtime');
  }

  onModuleDestroy(): void {
    if (this.heartbeat) clearInterval(this.heartbeat);
    for (const client of this.clients) client.socket.close();
    this.clients.clear();
    this.server?.close();
  }

  /** Pushes an event to every other connection subscribed to the board. */
  publish(event: BoardEvent, options: { accountId: string; exceptUserId?: string }): void {
    const frame = JSON.stringify(event);
    for (const client of this.clients) {
      if (client.accountId !== options.accountId) continue;
      if (!client.boards.has(event.boardId)) continue;
      if (options.exceptUserId && client.userId === options.exceptUserId) continue;
      if (client.socket.readyState !== WebSocket.OPEN) continue;
      client.socket.send(frame);
    }
  }

  /** Connections currently subscribed to a board, for diagnostics. */
  subscriberCount(boardId: string): number {
    let n = 0;
    for (const client of this.clients) {
      if (client.boards.has(boardId)) n += 1;
    }
    return n;
  }

  private async authenticate(token: string | null): Promise<{ userId: string; accountId: string } | null> {
    if (!token) return null;
    try {
      const payload = await this.jwt.verifyAsync<AccessTokenPayload>(token, {
        secret: this.config.get('JWT_SECRET', { infer: true }),
      });
      if (payload.typ !== 'access' || !payload.acc) return null;
      return { userId: payload.sub, accountId: payload.acc };
    } catch {
      return null;
    }
  }

  private register(socket: WebSocket, auth: { userId: string; accountId: string }, request: IncomingMessage): void {
    const client: Client = {
      socket,
      userId: auth.userId,
      accountId: auth.accountId,
      boards: new Set(),
      alive: true,
    };
    this.clients.add(client);

    // A board can be pre-selected on the handshake for a one-frame startup.
    const initial = new URL(request.url ?? '/', 'http://localhost').searchParams.get('boardId');
    if (initial) client.boards.add(initial);

    socket.on('pong', () => {
      client.alive = true;
    });

    socket.on('message', (raw) => {
      let message: { action?: string; boardId?: string };
      try {
        message = JSON.parse(raw.toString()) as typeof message;
      } catch {
        return; // ignore malformed frames
      }
      if (!message.boardId) return;
      if (message.action === 'subscribe') client.boards.add(message.boardId);
      if (message.action === 'unsubscribe') client.boards.delete(message.boardId);
    });

    socket.on('close', () => this.clients.delete(client));
    socket.on('error', () => {
      this.clients.delete(client);
      socket.terminate();
    });

    socket.send(JSON.stringify({ type: 'ready' }));
  }
}
