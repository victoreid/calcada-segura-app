"""Calçada Segura - API central (versão provisória para o pipeline de DevOps).

Esta API implementa o mínimo do contrato do grupo para que a infraestrutura,
o pipeline e o monitoramento possam ser construídos e testados antes da API
definitiva. Os endpoints seguem o contrato comum da ocorrência.
"""

import os
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Literal, Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.responses import FileResponse
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, Field
from sqlalchemy import Column, DateTime, Float, String, create_engine, select
from sqlalchemy.orm import Session, declarative_base, sessionmaker

APP_VERSION = os.getenv("APP_VERSION", "dev")
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./local.db")
API_KEY = os.getenv("API_KEY", "")
CHAOS_ENABLED = os.getenv("CHAOS_ENABLED", "false").lower() == "true"

connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(DATABASE_URL, pool_pre_ping=True, connect_args=connect_args)
SessionLocal = sessionmaker(bind=engine, autoflush=False)
Base = declarative_base()

Origem = Literal["robo", "visao", "cidadao"]
Tipo = Literal["buraco", "calcada_quebrada", "obstaculo", "rampa_irregular", "trepidacao", "degrau"]
Status = Literal["nova", "validada", "duplicada", "priorizada", "encaminhada", "resolvida", "rejeitada"]
Prioridade = Literal["alta", "media", "baixa"]


class OcorrenciaDB(Base):
    __tablename__ = "ocorrencias"
    id = Column(String(36), primary_key=True)
    origem = Column(String(20), nullable=False)
    tipo = Column(String(30), nullable=False)
    lat = Column(Float, nullable=False)
    lon = Column(Float, nullable=False)
    foto_url = Column(String(500))
    confianca = Column(Float)
    inclinacao_pct = Column(Float)
    vibracao_rms = Column(Float)
    criado_em = Column(DateTime(timezone=True), nullable=False)
    status = Column(String(20), nullable=False, default="nova")
    prioridade = Column(String(10))
    subprefeitura = Column(String(80))


class OcorrenciaIn(BaseModel):
    origem: Origem
    tipo: Tipo
    lat: float = Field(ge=-24.1, le=-23.3, description="Dentro da cidade de SP")
    lon: float = Field(ge=-46.9, le=-46.3)
    foto_url: Optional[str] = None
    confianca: Optional[float] = Field(default=None, ge=0, le=1)
    inclinacao_pct: Optional[float] = None
    vibracao_rms: Optional[float] = None


class OcorrenciaPatch(BaseModel):
    status: Optional[Status] = None
    prioridade: Optional[Prioridade] = None
    subprefeitura: Optional[str] = None


class Ocorrencia(OcorrenciaIn):
    id: str
    criado_em: datetime
    status: Status
    prioridade: Optional[Prioridade] = None
    subprefeitura: Optional[str] = None


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def exigir_chave(x_api_key: str = Header(default="")):
    """Escrita exige X-API-Key (chave vem de variável de ambiente, nunca do código)."""
    if not API_KEY or x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="X-API-Key inválida")


def para_modelo(o: OcorrenciaDB) -> Ocorrencia:
    # LGPD: coordenadas sempre devolvidas com 4 casas (~11 m)
    return Ocorrencia(
        id=o.id, origem=o.origem, tipo=o.tipo, lat=round(o.lat, 4), lon=round(o.lon, 4),
        foto_url=o.foto_url, confianca=o.confianca, inclinacao_pct=o.inclinacao_pct,
        vibracao_rms=o.vibracao_rms, criado_em=o.criado_em, status=o.status,
        prioridade=o.prioridade, subprefeitura=o.subprefeitura,
    )


@asynccontextmanager
async def lifespan(_app):
    Base.metadata.create_all(engine)
    yield


app = FastAPI(title="Calçada Segura API", version=APP_VERSION, lifespan=lifespan)
Instrumentator(
    should_group_status_codes=True,
    should_instrument_requests_inprogress=True,
    excluded_handlers=["/metrics", "/health"],
    inprogress_labels=True,
).instrument(app).expose(app, include_in_schema=False)


@app.get("/", include_in_schema=False)
def inicio():
    return FileResponse(os.path.join(os.path.dirname(__file__), "static", "index.html"))


@app.get("/health")
def health(db: Session = Depends(get_db)):
    try:
        db.execute(select(1))
        banco = "ok"
    except Exception:  # noqa: BLE001 - health deve responder mesmo com banco fora
        banco = "indisponivel"
    return {"status": "ok" if banco == "ok" else "degradado", "versao": APP_VERSION, "banco": banco}


@app.post("/api/v1/ocorrencias", response_model=Ocorrencia, status_code=201,
          dependencies=[Depends(exigir_chave)])
def criar_ocorrencia(dados: OcorrenciaIn, db: Session = Depends(get_db)):
    o = OcorrenciaDB(id=str(uuid.uuid4()), criado_em=datetime.now(timezone.utc),
                     status="nova", **dados.model_dump())
    db.add(o)
    db.commit()
    db.refresh(o)
    return para_modelo(o)


@app.get("/api/v1/ocorrencias", response_model=list[Ocorrencia])
def listar_ocorrencias(status: Optional[Status] = Query(default=None),
                       limite: int = Query(default=200, le=1000),
                       db: Session = Depends(get_db)):
    q = select(OcorrenciaDB).order_by(OcorrenciaDB.criado_em.desc()).limit(limite)
    if status:
        q = q.where(OcorrenciaDB.status == status)
    return [para_modelo(o) for o in db.scalars(q)]


@app.patch("/api/v1/ocorrencias/{ocorrencia_id}", response_model=Ocorrencia,
           dependencies=[Depends(exigir_chave)])
def atualizar_ocorrencia(ocorrencia_id: str, dados: OcorrenciaPatch, db: Session = Depends(get_db)):
    o = db.get(OcorrenciaDB, ocorrencia_id)
    if not o:
        raise HTTPException(status_code=404, detail="Ocorrência não encontrada")
    for campo, valor in dados.model_dump(exclude_none=True).items():
        setattr(o, campo, valor)
    db.commit()
    db.refresh(o)
    return para_modelo(o)


@app.get("/teste/erro", include_in_schema=False)
def forcar_erro():
    """Gera um 500 de propósito para demonstrar o alerta de taxa de erro.
    Só funciona com CHAOS_ENABLED=true (desligado por padrão)."""
    if not CHAOS_ENABLED:
        raise HTTPException(status_code=404)
    raise HTTPException(status_code=500, detail="Erro forçado para teste de alerta")
