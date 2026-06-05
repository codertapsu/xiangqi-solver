import { HealthController } from './health.controller';

describe('HealthController', () => {
  let controller: HealthController;

  beforeEach(() => {
    controller = new HealthController();
  });

  it('returns status ok', () => {
    expect(controller.check().status).toBe('ok');
  });

  it('returns an ISO-8601 timestamp', () => {
    const { timestamp } = controller.check();
    expect(new Date(timestamp).toISOString()).toBe(timestamp);
  });

  it('returns a non-negative integer uptime', () => {
    const { uptimeSeconds } = controller.check();
    expect(Number.isInteger(uptimeSeconds)).toBe(true);
    expect(uptimeSeconds).toBeGreaterThanOrEqual(0);
  });

  it('returns a version string', () => {
    expect(typeof controller.check().version).toBe('string');
    expect(controller.check().version.length).toBeGreaterThan(0);
  });
});
