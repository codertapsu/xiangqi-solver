import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { AdminService } from './admin.service';

interface RequestLike {
  headers: Record<string, string | string[] | undefined>;
}

function header(req: RequestLike, name: string): string | undefined {
  const v = req.headers[name];
  return Array.isArray(v) ? v[0] : v;
}

/**
 * Allows the request only for an ADMIN device (`x-device-id` ∈ admins.json) that
 * also presents the correct shared secret (`x-admin-secret` === ADMIN_SECRET).
 * Applied to every admin endpoint EXCEPT `GET /api/admin/status` (which is just
 * the identity probe the app uses to decide whether to show the admin UI).
 */
@Injectable()
export class AdminGuard implements CanActivate {
  constructor(private readonly admin: AdminService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<RequestLike>();
    const deviceId = (header(req, 'x-device-id') ?? '').trim();
    const secret = header(req, 'x-admin-secret');
    if (!(await this.admin.authorize(deviceId, secret))) {
      throw new ForbiddenException({
        message:
          'Admin access denied (device is not an admin, or the admin secret is missing/invalid).',
        code: 'ADMIN_FORBIDDEN',
      });
    }
    return true;
  }
}
