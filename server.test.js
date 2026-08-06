process.env.NODE_ENV = "production"; // avoids the pino-pretty transport worker thread in tests
process.env.LOG_LEVEL = "silent";
process.env.DB_HOST = "localhost";
process.env.DB_PORT = "5432";
process.env.DB_USER = "test_user";
process.env.DB_PASSWORD = "test_password";
process.env.DB_NAME = "test_db";
process.env.JWT_SECRET = "test-jwt-secret-for-unit-tests";
process.env.PORT = "0"; // let the OS assign a free port

jest.mock("pg", () => {
  const query = jest.fn();
  const Pool = jest.fn().mockImplementation(() => ({
    query,
    on: jest.fn(),
    end: jest.fn().mockResolvedValue(undefined),
  }));
  return { Pool, __mockQuery: query };
});

const request = require("supertest");
const jwt = require("jsonwebtoken");
const { __mockQuery: mockQuery } = require("pg");
const app = require("./server");

afterEach(() => {
  mockQuery.mockReset();
});

afterAll((done) => {
  app.server.close(done);
});

describe("GET /health", () => {
  it("returns 200 without touching the database", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("healthy");
    expect(mockQuery).not.toHaveBeenCalled();
  });
});

describe("GET /ready", () => {
  it("returns 200 when the database is reachable", async () => {
    mockQuery.mockResolvedValueOnce({ rows: [{ "?column?": 1 }] });
    const res = await request(app).get("/ready");
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("ready");
  });

  it("returns 503 when the database is unreachable", async () => {
    mockQuery.mockRejectedValueOnce(new Error("connection refused"));
    const res = await request(app).get("/ready");
    expect(res.status).toBe(503);
    expect(res.body.status).toBe("not ready");
  });
});

describe("POST /api/auth/login", () => {
  it("rejects requests without a phone number", async () => {
    const res = await request(app).post("/api/auth/login").send({});
    expect(res.status).toBe(400);
    expect(mockQuery).not.toHaveBeenCalled();
  });

  it("returns 401 when no driver matches the phone number", async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });
    const res = await request(app).post("/api/auth/login").send({ phone: "+10000000000" });
    expect(res.status).toBe(401);
  });

  it("uses a parameterized query — the phone is bound, never concatenated into the SQL string", async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [{ id: 1, phone: "+15551234567", name: "Test Driver" }],
    });
    await request(app).post("/api/auth/login").send({ phone: "+15551234567" });

    expect(mockQuery).toHaveBeenCalledTimes(1);
    const [sqlText, params] = mockQuery.mock.calls[0];
    expect(sqlText).toContain("$1");
    expect(sqlText).not.toContain("+15551234567");
    expect(params).toEqual(["+15551234567"]);
  });

  it("issues a valid, 8-hour JWT on successful login", async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [{ id: 42, phone: "+15551234567", name: "Test Driver" }],
    });
    const res = await request(app).post("/api/auth/login").send({ phone: "+15551234567" });

    expect(res.status).toBe(200);
    const decoded = jwt.verify(res.body.token, process.env.JWT_SECRET);
    expect(decoded.driverId).toBe(42);
    expect(decoded.exp - decoded.iat).toBe(8 * 60 * 60);
  });
});

describe("GET /api/admin/drivers", () => {
  it("rejects requests without a bearer token", async () => {
    const res = await request(app).get("/api/admin/drivers");
    expect(res.status).toBe(401);
    expect(mockQuery).not.toHaveBeenCalled();
  });

  it("returns the driver list for a valid token", async () => {
    const token = jwt.sign({ driverId: 1 }, process.env.JWT_SECRET);
    mockQuery.mockResolvedValueOnce({
      rows: [{ id: 1, phone: "+15551234567", name: "Test Driver", created_at: "2026-01-01" }],
    });
    const res = await request(app).get("/api/admin/drivers").set("Authorization", `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(1);
  });
});
