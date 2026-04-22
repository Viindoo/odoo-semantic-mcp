---
status: scratch
scope: tasks/_scratch_server_setup
audience: operator (not a permanent doc)
TODO: DELETE trước Gate 2 release hoặc trước khi publish OSS. File này
      là ghi chú tạm cho việc setup máy server test dev-loop. Khi
      docs/docker-quickstart.md + docs/dev-workflow.md chính thức
      ship ở WP-10, xoá file này và chỉ giữ redirect comment trong
      tasks/todo.md.
---

# Scratch — setup máy server để test Phase 1

Ghi chú tạm cho workflow "laptop code, server chạy test". Xoá khi
deploy / public release. Không phải permanent doc.

## Kiến trúc 2 máy

```
[Laptop Viindoo]          [Server test (WSL/Linux)]
  Tailscale client          Tailscale client
  VS Code                   Docker + git + uv
  git working tree    <->   git bare repo (origin)
                            Docker stack (db + mcp + indexer)
```

Kết nối qua Tailscale personal tailnet (đã chốt ở ADR-0005).

## Prereq trên server (làm 1 lần)

```bash
# 1. Tailscale + SSH
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh

# 2. Docker + compose plugin
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# logout + login lại để group docker có hiệu lực

# 3. Git + uv (cho tests ngoài docker nếu cần)
sudo apt install -y git postgresql-client
curl -LsSf https://astral.sh/uv/install.sh | sh

# 4. Bare repo origin ngay trên server (không cần GitHub)
mkdir -p ~/git
git init --bare ~/git/osm.git

# 5. Ghi tên tailnet của server để laptop biết
tailscale status   # copy cái tên máy này
```

## Prereq trên laptop (làm 1 lần)

- Tailscale client đã có (admin đã setup cho anh).
- VS Code extension: `ms-vscode-remote.remote-ssh`.
- Test SSH được chưa:

```bash
tailscale status                       # xem có thấy server trong list
tailscale ssh <server-tailnet-name>    # login thử; exit về lại
```

## Push bundle Phase 1 từ laptop lên server

Chạy SAU KHI đã `git commit` bundle trên laptop.

```bash
cd /home/soncrits/git/17.0/odoo-semantic-mcp
git remote add origin <server-tailnet-name>:/home/<user-server>/git/osm.git
git push -u origin init_structor
```

`<server-tailnet-name>` lấy từ `tailscale status`.
`<user-server>` là tên user trên máy server (KHÔNG phải trên laptop).

## Kéo về + test trên server

SSH vào server qua Tailscale rồi chạy:

```bash
cd ~
git clone ~/git/osm.git osm
cd osm
git checkout init_structor

# Config env
cp .env.example .env
# Sửa .env: đổi POSTGRES_PASSWORD + confirm DATABASE_URL match

# Build images (lần đầu ~2-3 phút vì pip install)
docker compose build

# Start db trước, đợi healthy
docker compose up -d db
docker compose ps    # chờ db ở trạng thái "healthy"

# Chạy migrate (schema public)
docker compose run --rm mcp uv run python scripts/migrate.py --schema public

# Chạy indexer 1 lần trên fixture (smoke test)
docker compose run --rm mcp uv run python scripts/index.py \
  --addons tests/fixtures/odoo_ce_subset \
  --addons tests/fixtures/custom_addons \
  --tenant public --git-sha smoke-test

# Start MCP server
docker compose up -d mcp
docker logs -f osm-mcp-1
```

## LƯU Ý — sẽ lỗi ở bước `docker compose up -d mcp`

Dockerfile hiện tại **chưa wire WP-10** — CMD của `Dockerfile.server` và
`Dockerfile.indexer` là placeholder print. Sẽ thấy:

```
osm server: placeholder, implemented in WP-8
```

rồi container exit. Đây là hành vi ĐÃ BIẾT. Việc sửa nằm trong
WP-10 (phase-01-plan.md §2). Tạm thời test kiểu **không docker**
trên server:

```bash
# Trên server, ngoài container
cd ~/osm
uv sync --extra dev
uv run pytest -q         # 227 tests phải pass
export DATABASE_URL="postgresql://osm:<password>@127.0.0.1:5432/osm"
uv run python scripts/migrate.py --schema public
uv run python scripts/index.py \
  --addons tests/fixtures/odoo_ce_subset \
  --addons tests/fixtures/custom_addons \
  --tenant public --git-sha smoke-test
uv run python -m osm.server.app --http --host 0.0.0.0 --port 8765
```

Test 1 tool call:

```bash
# Trên laptop (Tailscale-reachable về server:8765)
curl -sS -X POST http://<server-tailnet-name>:8765/mcp \
  -H 'Content-Type: application/json' \
  -d '{"method":"tools/call","params":{"name":"resolve_model","arguments":{"model_name":"sale.order"}}}' | jq .
```

(Cú pháp chính xác tuỳ FastMCP version — khi chạy thực tế có thể
cần mcp-inspector thay cho curl.)

## Workflow hằng ngày (sau setup xong)

### Cách 1 — push/pull thủ công (đơn giản)

```
Laptop:  edit → commit → git push
Server:  git pull → pytest / docker compose up -d
```

### Cách 2 — VS Code Remote-SSH (em đề xuất)

Trên laptop:

1. `Cmd/Ctrl+Shift+P` → **Remote-SSH: Connect to Host...**
2. Host: `<user-server>@<server-tailnet-name>`
3. Lần đầu VS Code cài `vscode-server` vào server (~30s).
4. **File > Open Folder** → `/home/<user-server>/osm`
5. Mọi edit, terminal, debug giờ chạy native trên server.

Git vẫn work bình thường — commit trên server working tree, push
lên bare repo (`/home/<user-server>/git/osm.git`).

## Claude Code trên server (nếu cần)

```bash
# Trên server
curl -fsSL https://claude.ai/install.sh | bash
claude login
cd ~/osm
claude
```

## Khi nào xoá file này

Xoá khi WP-10 đóng VÀ có 2 file chính thức sau:

- `docs/docker-quickstart.md` (self-host recipe)
- `docs/dev-workflow.md` (Tailscale + VS Code Remote hay tương đương)

Khi xoá, cũng bỏ dòng "scratch doc cleanup" trong `tasks/todo.md`
(mục Backlog).
