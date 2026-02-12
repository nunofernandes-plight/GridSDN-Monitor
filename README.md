# GridSDN Monitor - Power Grid Monitoring System

A comprehensive multi-tier power grid monitoring platform with software-defined network analysis, real-time fault detection, load optimization, and predictive maintenance capabilities.

## Features

- **Multi-Tier Monitoring**: Support for both distribution and transmission networks
- **Real-Time Analytics**: Sub-second fault detection and alerting
- **Predictive Maintenance**: ML-powered equipment health monitoring
- **Load Optimization**: Intelligent load balancing recommendations
- **SDN Integration**: Software-defined network topology management
- **Interactive Visualization**: Real-time network topology and dashboards

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Frontend (React)                         │
│                  Network Viz | Dashboards | Alerts               │
└────────────────────────────┬────────────────────────────────────┘
                             │ WebSocket/REST
┌────────────────────────────┴────────────────────────────────────┐
│                      API Layer (FastAPI)                         │
│                  Auth | REST | GraphQL | WebSocket               │
└────────────┬───────────────────────────────────┬─────────────────┘
             │                                   │
┌────────────┴──────────────┐    ┌──────────────┴─────────────────┐
│   Stream Processing       │    │    Analytics Engine             │
│   (Kafka + Faust)        │    │    (ML Models + Algorithms)     │
└────────────┬──────────────┘    └──────────────┬─────────────────┘
             │                                   │
┌────────────┴───────────────────────────────────┴─────────────────┐
│                   Data Storage Layer                              │
│         TimescaleDB | Redis | PostgreSQL | MinIO                 │
└────────────┬──────────────────────────────────────────────────────┘
             │
┌────────────┴──────────────────────────────────────────────────────┐
│                    Data Acquisition Layer                          │
│           SCADA | PMU | Smart Meters | SDN Controller             │
└───────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Docker & Docker Compose
- Python 3.11+
- Node.js 18+
- 8GB RAM minimum

### Development Setup

1. **Clone and setup**
```bash
cd gridsdn-monitor
./scripts/setup-dev.sh
```

2. **Start services**
```bash
docker-compose up -d
```

3. **Initialize database**
```bash
./scripts/init-db.sh
```

4. **Start backend**
```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

5. **Start frontend**
```bash
cd frontend
npm install
npm start
```

6. **Access the application**
- Frontend: http://localhost:3000
- API Docs: http://localhost:8000/docs
- Grafana: http://localhost:3001 (admin/admin)

## Project Structure

```
gridsdn-monitor/
├── backend/                 # FastAPI backend
│   ├── app/
│   │   ├── api/            # API routes
│   │   ├── core/           # Core config and utilities
│   │   ├── models/         # Database models
│   │   ├── schemas/        # Pydantic schemas
│   │   ├── services/       # Business logic
│   │   ├── ml/             # ML models and training
│   │   └── main.py         # Application entry point
│   ├── alembic/            # Database migrations
│   ├── tests/              # Backend tests
│   └── requirements.txt
├── frontend/               # React frontend
│   ├── src/
│   │   ├── components/     # React components
│   │   ├── pages/          # Page components
│   │   ├── services/       # API clients
│   │   ├── hooks/          # Custom hooks
│   │   └── utils/          # Utilities
│   └── package.json
├── docker/                 # Docker configurations
│   ├── kafka/
│   ├── timescaledb/
│   └── prometheus/
├── scripts/                # Utility scripts
├── docs/                   # Documentation
└── docker-compose.yml
```

## Development Workflow

### Running Tests

```bash
# Backend tests
cd backend
pytest

# Frontend tests
cd frontend
npm test
```

### Code Quality

```bash
# Backend linting
cd backend
black app/
flake8 app/
mypy app/

# Frontend linting
cd frontend
npm run lint
```

### Database Migrations

```bash
cd backend
alembic revision --autogenerate -m "Description"
alembic upgrade head
```

## Configuration

Configuration is managed through environment variables. See `.env.example` for available options.

Key configurations:
- `DATABASE_URL`: TimescaleDB connection string
- `REDIS_URL`: Redis connection string
- `KAFKA_BOOTSTRAP_SERVERS`: Kafka broker addresses
- `JWT_SECRET_KEY`: Secret for JWT token generation

## API Documentation

Interactive API documentation is available at `/docs` (Swagger UI) and `/redoc` (ReDoc) when the backend is running.

### Key Endpoints

- `GET /api/v1/network/topology` - Retrieve network topology
- `GET /api/v1/measurements/realtime` - Real-time measurements stream
- `GET /api/v1/alerts` - Active alerts
- `POST /api/v1/analytics/predict` - Run predictive maintenance analysis
- `GET /api/v1/health` - System health check

## Monitoring & Observability

- **Metrics**: Prometheus metrics exposed at `/metrics`
- **Logs**: Structured JSON logging to stdout
- **Tracing**: OpenTelemetry integration (optional)
- **Dashboards**: Pre-built Grafana dashboards in `docker/grafana/dashboards/`

## Security

- All API endpoints require JWT authentication (except `/health`)
- Role-based access control (RBAC) for different user types
- TLS/SSL encryption for all external communications
- Secrets managed through environment variables or secret managers

## Contributing

1. Create a feature branch from `develop`
2. Make your changes with tests
3. Run linting and tests
4. Submit a pull request

## License

Proprietary - All rights reserved

## Support

For issues and questions, contact the engineering team or create an issue in the project repository.

## Roadmap

- [x] Phase 1: Foundation & basic API
- [ ] Phase 2: Real-time data ingestion
- [ ] Phase 3: Analytics engine
- [ ] Phase 4: ML models for predictive maintenance
- [ ] Phase 5: SDN controller integration
- [ ] Phase 6: Production hardening

---

**Version**: 1.0.0-prototype  
**Last Updated**: February 9, 2026

