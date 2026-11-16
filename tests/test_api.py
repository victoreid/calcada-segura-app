import os

os.environ["DATABASE_URL"] = "sqlite:///./test.db"
os.environ["API_KEY"] = "chave-de-teste"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402

CHAVE = {"X-API-Key": "chave-de-teste"}
OCORRENCIA = {"origem": "robo", "tipo": "rampa_irregular", "lat": -23.561412,
              "lon": -46.655934, "inclinacao_pct": 11.2, "vibracao_rms": 0.42}


def test_health_e_metrics():
    with TestClient(app) as c:
        assert c.get("/health").json()["banco"] == "ok"
        assert c.get("/metrics").status_code == 200


def test_escrita_exige_chave():
    with TestClient(app) as c:
        assert c.post("/api/v1/ocorrencias", json=OCORRENCIA).status_code == 401


def test_fluxo_ocorrencia():
    with TestClient(app) as c:
        r = c.post("/api/v1/ocorrencias", json=OCORRENCIA, headers=CHAVE)
        assert r.status_code == 201
        o = r.json()
        assert o["status"] == "nova" and o["lat"] == -23.5614  # LGPD: 4 casas
        r = c.patch(f"/api/v1/ocorrencias/{o['id']}", headers=CHAVE,
                    json={"status": "priorizada", "prioridade": "alta", "subprefeitura": "Pinheiros"})
        assert r.json()["prioridade"] == "alta"
        assert any(x["id"] == o["id"] for x in c.get("/api/v1/ocorrencias").json())


def test_coordenada_fora_de_sp_e_recusada():
    with TestClient(app) as c:
        r = c.post("/api/v1/ocorrencias", json={**OCORRENCIA, "lat": -10.0}, headers=CHAVE)
        assert r.status_code == 422


def test_erro_forcado_desligado_por_padrao():
    with TestClient(app) as c:
        assert c.get("/teste/erro").status_code == 404
